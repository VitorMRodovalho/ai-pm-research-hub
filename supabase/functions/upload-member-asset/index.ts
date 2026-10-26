/**
 * upload-member-asset - authenticated storage write for a member's own photo / signature.
 *
 * WHY THIS EXISTS (2026-06-19):
 *   Direct browser `supabase.storage.from(bucket).upload(...)` for member-photos AND
 *   member-signatures returns HTTP 400 "new row violates row-level security policy" for an
 *   authenticated user, even though (a) the request carries a valid `authenticated` JWT,
 *   (b) the identical INSERT as the `authenticated` role passes at the SQL level, and
 *   (c) the WITH CHECK expression evaluates true. The storage-api's evaluation of the
 *   members-subquery storage RLS policy does not match the SQL-level result. Rather than
 *   depend on that fragile cross-table storage RLS, the upload is performed here with the
 *   service role (PROVEN to succeed) AFTER authenticating the caller and resolving THEIR OWN
 *   canonical path - so no user can write as another.
 *
 * PHOTO NAME IS OPAQUE (item interno, 2026-10-26):
 *   member-photos is a PUBLIC bucket and members.photo_url carries the object URL, so the object
 *   name is public. It used to be the caller's e-mail; it is now `avatars/<key>.<ext>`, where
 *   <key> is the caller's row in public.member_photo_keys (128 random bits, no personal data).
 *   The path is still always the caller's own: the key is looked up by the caller's member id,
 *   which comes from the caller's JWT, never from the request body.
 *   For a photo the EF also persists the URL through the caller's OWN `update_my_profile` (same
 *   writer as before, members + persons) and only then removes the same key under the other
 *   extension, which is an old photo nobody references. The response says `persisted: true`, and
 *   the page skips its own update_my_profile call when it sees that.
 *   Signatures (PRIVATE bucket) keep the e-mail path: out of scope here.
 *
 * Auth: caller's user JWT (sent automatically by supabase-js `functions.invoke`).
 * Body: multipart/form-data with fields `kind` ("photo" | "signature") and `file`.
 * Returns: { success: true, url, path, bucket, persisted }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { PHOTO_KEY_RE, photoObjectPath, stalePhotoPaths } from "./photo-path.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

type KindCfg = { bucket: string; prefix: string; maxBytes: number; mimes: string[] };
const KINDS: Record<string, KindCfg> = {
  photo:     { bucket: "member-photos",     prefix: "avatars/",    maxBytes: 2 * 1024 * 1024, mimes: ["image/jpeg", "image/png"] },
  signature: { bucket: "member-signatures", prefix: "signatures/", maxBytes: 512 * 1024,      mimes: ["image/png", "image/jpeg", "image/webp"] },
};

const extFor = (mime: string) => (mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg");

// deno-lint-ignore no-explicit-any
type Admin = any;

/** The caller's photo key, created on first use (the migration backfilled every member that existed then). */
async function ownPhotoKey(admin: Admin, memberId: string): Promise<string> {
  const read = () =>
    admin.from("member_photo_keys").select("object_key").eq("member_id", memberId).maybeSingle();
  let { data, error } = await read();
  if (error) throw new Error(`photo key lookup failed: ${error.message}`);
  if (!data) {
    // object_key comes from the column default (gen_random_bytes), never from here.
    const ins = await admin.from("member_photo_keys").insert({ member_id: memberId });
    if (ins.error && ins.error.code !== "23505") throw new Error(`photo key create failed: ${ins.error.message}`);
    ({ data, error } = await read());
    if (error) throw new Error(`photo key lookup failed: ${error.message}`);
  }
  const key = String(data?.object_key ?? "");
  if (!PHOTO_KEY_RE.test(key)) throw new Error("photo key missing or malformed");
  return key;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "missing bearer token" }, 401);

  // 1) authenticate the caller (their own JWT)
  const userClient = createClient<any, "public", any>(SUPABASE_URL, ANON, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authErr } = await userClient.auth.getUser();
  if (authErr || !user) return json({ error: "not authenticated" }, 401);

  // 2) parse multipart body
  let form: FormData;
  try { form = await req.formData(); }
  catch { return json({ error: "expected multipart form-data" }, 400); }

  const kind = String(form.get("kind") ?? "");
  const cfg = KINDS[kind];
  if (!cfg) return json({ error: "invalid kind (expected photo|signature)" }, 400);

  const file = form.get("file");
  if (!(file instanceof File)) return json({ error: "missing file" }, 400);
  if (file.size === 0) return json({ error: "empty file" }, 400);
  if (file.size > cfg.maxBytes) return json({ error: "file too large", max_bytes: cfg.maxBytes }, 413);
  if (!cfg.mimes.includes(file.type)) return json({ error: "unsupported type", got: file.type, allowed: cfg.mimes }, 415);

  // 3) resolve the caller's OWN member record (service role) - path is always the caller's
  const admin = createClient<any, "public", any>(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: member, error: mErr } = await admin
    .from("members").select("id,email").eq("auth_id", user.id).maybeSingle();
  if (mErr) return json({ error: "member lookup failed", detail: mErr.message }, 500);
  if (!member?.id) return json({ error: "no member record for caller" }, 403);

  // 4) canonical path, always derived from the caller's own record
  let path: string;
  if (kind === "photo") {
    try { path = photoObjectPath(await ownPhotoKey(admin, member.id), file.type); }
    catch (e) { return json({ error: "photo key unavailable", detail: (e as Error).message }, 500); }
  } else {
    // signatures: same convention as the legacy FE (email with [@.] -> _), private bucket
    if (!member.email) return json({ error: "no member record for caller" }, 403);
    const sanitized = String(member.email).replace(/[@.]/g, "_");
    path = `${cfg.prefix}${sanitized}.${extFor(file.type)}`;
  }

  // 5) privileged write (service role bypasses the storage RLS that rejects authed uploads)
  const bytes = new Uint8Array(await file.arrayBuffer());
  const { error: upErr } = await admin.storage.from(cfg.bucket).upload(path, bytes, { upsert: true, contentType: file.type });
  if (upErr) return json({ error: "upload failed", detail: upErr.message }, 500);

  const { data: urlData } = admin.storage.from(cfg.bucket).getPublicUrl(path);
  const url = `${urlData.publicUrl}?t=${Date.now()}`;

  if (kind !== "photo") return json({ success: true, url, path, bucket: cfg.bucket, persisted: false });

  // 6) photo: persist through the caller's own update_my_profile, THEN drop the stale extension.
  //    Removing before the URL is saved would leave photo_url pointing at a deleted object.
  const { data: saved, error: saveErr } = await userClient.rpc("update_my_profile", { p_fields: { photo_url: url } });
  if (saveErr || (saved as { error?: string } | null)?.error) {
    return json({ error: "photo stored but profile not updated", detail: saveErr?.message ?? (saved as { error?: string }).error }, 500);
  }
  const { error: rmErr } = await admin.storage.from(cfg.bucket).remove(stalePhotoPaths(path));
  return json({ success: true, url, path, bucket: cfg.bucket, persisted: true, stale_removed: !rmErr });
});
