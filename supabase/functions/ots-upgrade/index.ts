// ots-upgrade — #569 Slice 3 (ADR-0101). Internal OTS upgrade pass (service-role only).
//
// For each `pending` asset, asks the calendars to upgrade the proof; once Bitcoin-anchored, resolves the
// block height -> UTC (the OTS attestation carries only the height) and marks the asset `confirmed`.
// Eficácia probatória = `confirmed`, not `pending`. Single-consumer discipline via cron non-overlap
// (02:40 vs 02:10 UTC — Slice 3 mig 20260805000136). Deploy --no-verify-jwt; invoked from
// pg_cron -> pg_net with the DEDICATED vault secret ots_cron_secret as Bearer (NOT the vault
// service_role_key — stale vs the EF-injected key; #618).

import { timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { upgrade, bytesToHex } from "../_shared/ots.ts";

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

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
function toByteaHex(b: Uint8Array): string { return "\\x" + bytesToHex(b); }
function b64ToBytes(b64: string): Uint8Array { return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)); }

// Constant-time token comparison (council security MEDIUM — see ots-stamp/index.ts).
function tokenMatches(token: string, secret: string): boolean {
  if (secret.length === 0 || token.length !== secret.length) return false;
  return timingSafeEqual(Buffer.from(token), Buffer.from(secret));
}

// Bitcoin block height -> attested UTC. The proof is the legal anchor; this UTC is a convenience field
// derived from a public explorer (blockstream, mempool fallback). Untrusted-but-non-probative.
async function blockTimeUtc(height: number, timeoutMs = 15000): Promise<string> {
  const sources = [
    { h: (n: number) => `https://blockstream.info/api/block-height/${n}`, b: (hash: string) => `https://blockstream.info/api/block/${hash}` },
    { h: (n: number) => `https://mempool.space/api/block-height/${n}`, b: (hash: string) => `https://mempool.space/api/block/${hash}` },
  ];
  let lastErr: unknown;
  for (const s of sources) {
    try {
      const hr = await fetch(s.h(height), { signal: AbortSignal.timeout(timeoutMs) });
      if (!hr.ok) throw new Error(`block-height ${hr.status}`);
      const hash = (await hr.text()).trim();
      if (!/^[0-9a-f]{64}$/.test(hash)) throw new Error("bad block hash");
      const br = await fetch(s.b(hash), { signal: AbortSignal.timeout(timeoutMs) });
      if (!br.ok) throw new Error(`block ${br.status}`);
      const blk = await br.json();
      if (typeof blk?.timestamp !== "number") throw new Error("block has no timestamp");
      return new Date(blk.timestamp * 1000).toISOString();
    } catch (e) { lastErr = e; }
  }
  throw new Error(`block-time lookup failed for height ${height}: ${extractError(lastErr)}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  // #569 Slice 3: dedicated cron secret (see ots-stamp/index.ts for rationale + #618).
  // FAIL-CLOSED: empty/unset cron secret never matches.
  const cronSecret = Deno.env.get("OTS_CRON_SECRET") ?? "";

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return jsonResponse({ success: false, error: "Unauthorized" }, 401);
  const authorized = tokenMatches(token, serviceRoleKey) || tokenMatches(token, cronSecret);
  if (!authorized) return jsonResponse({ success: false, error: "Forbidden: service-role or cron-secret only" }, 403);

  let limit = DEFAULT_LIMIT;
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    if (typeof body?.limit === "number" && body.limit > 0) limit = Math.min(Math.floor(body.limit), MAX_LIMIT);
  } catch { /* default */ }

  const sb = createClient(supabaseUrl, serviceRoleKey);

  try {
    const { data: pendingRows, error: listErr } = await sb.rpc("_ots_list_pending", { p_limit: limit });
    if (listErr) throw listErr;
    const rows = (pendingRows ?? []) as { id: string; sha256: string; ots_proof_b64: string }[];
    if (rows.length === 0) return jsonResponse({ success: true, checked: 0, confirmed: 0, still_pending: 0, errors: 0, results: [] });

    let confirmed = 0, stillPending = 0, errors = 0;
    const results: Record<string, unknown>[] = [];

    for (const row of rows) {
      try {
        const proof = b64ToBytes(row.ots_proof_b64);
        const up = await upgrade(proof, { timeoutMs: 20000 });
        if (up.confirmed && up.bitcoinBlockHeight !== null) {
          let attestedAt: string;
          try {
            attestedAt = await blockTimeUtc(up.bitcoinBlockHeight);
          } catch (e) {
            // anchored but explorer unavailable -> leave pending, retry next pass (don't mark error)
            stillPending++;
            results.push({ id: row.id, status: "pending", note: "anchored; block-time lookup deferred", detail: extractError(e) });
            continue;
          }
          const { error: confErr } = await sb.rpc("_ots_mark_confirmed", {
            p_asset_id: row.id,
            p_ots_proof: toByteaHex(up.otsBytes),
            p_bitcoin_block: up.bitcoinBlockHeight,
            p_attested_at: attestedAt,
          });
          if (confErr) throw confErr;
          confirmed++;
          results.push({ id: row.id, status: "confirmed", block: up.bitcoinBlockHeight, attested_at: attestedAt });
        } else {
          stillPending++;
          results.push({ id: row.id, status: "pending", changed: up.changed });
        }
      } catch (e) {
        errors++;
        const msg = extractError(e);
        await sb.rpc("_ots_mark_error", { p_asset_id: row.id, p_error: msg.slice(0, 500) }).catch(() => {});
        results.push({ id: row.id, status: "error", error: msg });
      }
    }

    return jsonResponse({ success: true, checked: rows.length, confirmed, still_pending: stillPending, errors, results });
  } catch (error) {
    return jsonResponse({ success: false, error: extractError(error) }, 500);
  }
});
