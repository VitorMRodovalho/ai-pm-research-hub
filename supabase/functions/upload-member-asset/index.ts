/**
 * upload-member-asset — authenticated storage write for a member's own photo / signature.
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
 *   canonical path — so no user can write as another. The caller still updates members
 *   (photo_url / signature_url) via the existing `update_my_profile` RPC, which works.
 *
 * Auth: caller's user JWT (sent automatically by supabase-js `functions.invoke`).
 * Body: multipart/form-data with fields `kind` ("photo" | "signature") and `file`.
 * Returns: { success: true, url, path, bucket }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

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

  // 3) resolve the caller's OWN member record (service role) — path is always the caller's
  const admin = createClient<any, "public", any>(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: member, error: mErr } = await admin
    .from("members").select("id,email").eq("auth_id", user.id).maybeSingle();
  if (mErr) return json({ error: "member lookup failed", detail: mErr.message }, 500);
  if (!member?.email) return json({ error: "no member record for caller" }, 403);

  // 4) canonical path (same convention as the legacy FE: email with [@.] -> _)
  const sanitized = String(member.email).replace(/[@.]/g, "_");
  const path = `${cfg.prefix}${sanitized}.${extFor(file.type)}`;

  // 5) privileged write (service role bypasses the storage RLS that rejects authed uploads)
  const bytes = new Uint8Array(await file.arrayBuffer());
  const { error: upErr } = await admin.storage.from(cfg.bucket).upload(path, bytes, { upsert: true, contentType: file.type });
  if (upErr) return json({ error: "upload failed", detail: upErr.message }, 500);

  const { data: urlData } = admin.storage.from(cfg.bucket).getPublicUrl(path);
  return json({ success: true, url: `${urlData.publicUrl}?t=${Date.now()}`, path, bucket: cfg.bucket });
});
