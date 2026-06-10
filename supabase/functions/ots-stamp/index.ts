// ots-stamp — #569 Slice 2 (ADR-0101). Internal OTS stamping pipeline (service-role only).
//
// Claims a batch of `unstamped` PI-exclusion assets, submits each digest to the OpenTimestamps
// calendars via the zero-dep engine (`../_shared/ots.ts`), and persists the `pending` `.ots` proof.
// Digest-only: only the SHA-256 leaves the Núcleo. Single-consumer until `_ots_claim_unstamped_assets`
// gains FOR UPDATE SKIP LOCKED (ADR-0101 open item) — do NOT run two invocations concurrently.
//
// Invoke (later) from pg_cron -> pg_net with the service-role key as Bearer. Deploy with --no-verify-jwt.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { stamp, hexToBytes, bytesToHex, describe } from "../_shared/ots.ts";

// Keep the batch small: each asset = up to 4 sequential-ish calendar round-trips; stay well under the
// 150s wall-clock. Tunable by the caller (pg_cron job) via the request body.
const DEFAULT_LIMIT = 10;
const MAX_LIMIT = 50;

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function extractError(err: unknown): string {
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    if (typeof e.message === "string" && e.message) return e.message;
    try { return JSON.stringify(err); } catch { /* fallthrough */ }
  }
  return String(err || "Unknown error");
}

// bytea over PostgREST: a JSON string in Postgres `\x<hex>` input format casts to bytea byte-exact.
function toByteaHex(b: Uint8Array): string { return "\\x" + bytesToHex(b); }

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // service-role only: this drives the internal `_ots_*` RPCs (REVOKEd from anon/authenticated).
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return jsonResponse({ success: false, error: "Unauthorized" }, 401);
  if (token !== serviceRoleKey) return jsonResponse({ success: false, error: "Forbidden: service-role only" }, 403);

  let limit = DEFAULT_LIMIT;
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    if (typeof body?.limit === "number" && body.limit > 0) limit = Math.min(Math.floor(body.limit), MAX_LIMIT);
  } catch { /* default limit */ }

  const sb = createClient(supabaseUrl, serviceRoleKey);

  try {
    const { data: claimed, error: claimErr } = await sb.rpc("_ots_claim_unstamped_assets", { p_limit: limit });
    if (claimErr) throw claimErr;
    const assets = (claimed ?? []) as { id: string; sha256: string }[];
    if (assets.length === 0) return jsonResponse({ success: true, claimed: 0, stamped: 0, failed: 0, results: [] });

    let stamped = 0, failed = 0;
    const results: Record<string, unknown>[] = [];

    // sequential per asset (single-consumer + deterministic wall-clock); calendars fan out inside stamp()
    for (const a of assets) {
      try {
        if (!/^[0-9a-f]{64}$/.test(a.sha256)) throw new Error("asset sha256 is not 64 lowercase hex");
        const res = await stamp(hexToBytes(a.sha256), { m: 1, timeoutMs: 20000 });
        const { error: markErr } = await sb.rpc("_ots_mark_stamped", { p_asset_id: a.id, p_ots_proof: toByteaHex(res.otsBytes) });
        if (markErr) throw markErr;
        stamped++;
        results.push({ id: a.id, status: "pending", calendars: res.calendarsOk.length, bytes: res.otsBytes.length, pending: describe(res.otsBytes).pending });
      } catch (e) {
        failed++;
        const msg = extractError(e);
        // best-effort error mark (status flips to 'error' on the 5th attempt); never throws the whole batch
        await sb.rpc("_ots_mark_error", { p_asset_id: a.id, p_error: msg.slice(0, 500) }).catch(() => {});
        results.push({ id: a.id, status: "error", error: msg });
      }
    }

    return jsonResponse({ success: true, claimed: assets.length, stamped, failed, results });
  } catch (error) {
    return jsonResponse({ success: false, error: extractError(error) }, 500);
  }
});
