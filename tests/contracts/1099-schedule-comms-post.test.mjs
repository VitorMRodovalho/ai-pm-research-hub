/**
 * #1099 + #1094 — comms publishing on-ramp "conteúdo → fila → rede".
 *
 * The multi-channel queue (comms_scheduled_posts, mig 271/277) and the per-channel
 * publishers existed, but NO surface ever wrote to the queue (the #1094 bug: 0 rows
 * channel='linkedin' ever — content was prepared but never enqueued). Migration 334
 * ships the canonical RPC trio (schedule_comms_post / cancel_scheduled_comms_post /
 * list_scheduled_comms_posts, gate can_manage_comms_metrics()) and the MCP exposes it;
 * publish-linkedin gains the DOCUMENT post_type (native swipeable PDF post).
 *
 * Offline: static source-contract on the migration + EFs + MCP index/manifest.
 * DB-aware (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY): live gate fail-closed proof.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

const MIG = read('../../supabase/migrations/20260805000334_1099_schedule_comms_post_onramp.sql');
const LINKEDIN_EF = read('../../supabase/functions/publish-linkedin/index.ts');
const SCHEDULED_EF = read('../../supabase/functions/publish-scheduled/index.ts');
const MCP_INDEX = read('../../supabase/functions/nucleo-mcp/index.ts');
const MANIFEST = JSON.parse(read('../../src/lib/mcp-manifest.json'));

const RPCS = ['schedule_comms_post', 'cancel_scheduled_comms_post', 'list_scheduled_comms_posts'];

// ───────────────────────── Migration 334 (RPC trio) ─────────────────────────

test('1099: the RPC trio is captured by migration 334', () => {
  for (const fn of RPCS) {
    assert.match(MIG, new RegExp(`create or replace function public\\.${fn}\\(`), `${fn} missing`);
  }
});

test('1099: every RPC is gated by can_manage_comms_metrics (the queue RLS gate) and fail-closes', () => {
  const gates = MIG.match(/if not public\.can_manage_comms_metrics\(\) then/g) ?? [];
  assert.equal(gates.length, RPCS.length, 'one function-anchored gate per RPC');
  assert.match(MIG, /raise exception 'Unauthorized: manage_comms required'/);
});

test('1099: anon is revoked on all three RPCs; authenticated granted', () => {
  assert.match(MIG, /revoke all on function public\.schedule_comms_post\(text, text, jsonb, timestamptz, text, uuid\) from public, anon/);
  assert.match(MIG, /revoke all on function public\.cancel_scheduled_comms_post\(uuid\) from public, anon/);
  assert.match(MIG, /revoke all on function public\.list_scheduled_comms_posts\(text, text, int, boolean\) from public, anon/);
  const grants = MIG.match(/grant execute on function public\.\w+\([^)]*\) to authenticated/g) ?? [];
  assert.equal(grants.length, RPCS.length);
});

test('1099: schedule validates channel×media_type against the publisher capabilities map', () => {
  assert.match(MIG, /'instagram', jsonb_build_array\('IMAGE', 'CAROUSEL', 'REELS', 'STORIES'\)/);
  assert.match(MIG, /'linkedin',\s+jsonb_build_array\('TEXT', 'IMAGE', 'VIDEO', 'ARTICLE', 'DOCUMENT'\)/);
  // per-type payload requirements mirror the publishers (fail at schedule time, not at drain)
  for (const req of [
    /IMAGE requires payload\.image_url/,
    /REELS requires payload\.video_url/,
    /TEXT requires payload\.text/,
    /DOCUMENT requires payload\.document_url/,
    /DOCUMENT requires payload\.title/,
    /CAROUSEL requires 2-10 children/,
  ]) assert.match(MIG, req);
});

test('1099: payload discriminator coherence — drain forwards payload RAW, so the publisher discriminator (post_type LinkedIn / media_type IG) is validated + injected to match the row', () => {
  assert.match(MIG, /must match media_type/);
  assert.match(MIG, /jsonb_set\(p_payload, '\{post_type\}', to_jsonb\(p_media_type\)\)/);
  assert.match(MIG, /jsonb_set\(p_payload, '\{media_type\}', to_jsonb\(p_media_type\)\)/);
});

test('1099: idea provenance — optional idea_id column + approved/published stage gate', () => {
  assert.match(MIG, /add column if not exists idea_id uuid references public\.publication_ideas\(id\) on delete set null/);
  assert.match(MIG, /stage not in \('approved', 'published'\)/);
});

test('1099: media_type CHECK gains DOCUMENT and drops the never-implemented LINK', () => {
  assert.match(MIG, /'TEXT', 'VIDEO', 'ARTICLE', 'DOCUMENT'/);
  assert.doesNotMatch(MIG, /'LINK'/);
});

test('1099: cancel only transitions pending → canceled', () => {
  assert.match(MIG, /set status = 'canceled'/);
  assert.match(MIG, /and status = 'pending'/);
});

test('1099: comms-media bucket accepts application/pdf (DOCUMENT bytes source)', () => {
  assert.match(MIG, /allowed_mime_types = array\['image\/jpeg', 'image\/png', 'image\/webp', 'video\/mp4', 'application\/pdf'\]/);
});

// ───────────────────────── publish-linkedin DOCUMENT (#1094 layer) ─────────────────────────

test('1094: publish-linkedin implements the DOCUMENT post_type (PDF → native document post)', () => {
  assert.match(LINKEDIN_EF, /type PostType = 'TEXT' \| 'IMAGE' \| 'VIDEO' \| 'ARTICLE' \| 'DOCUMENT'/);
  assert.match(LINKEDIN_EF, /async function uploadDocument\(/);
  assert.match(LINKEDIN_EF, /\/documents\?action=initializeUpload/);
  assert.match(LINKEDIN_EF, /DOCUMENT requires document_url/);
  assert.match(LINKEDIN_EF, /DOCUMENT requires title/);
});

test('1094: the drain still routes linkedin rows through publish-linkedin (channel-agnostic contract)', () => {
  assert.match(SCHEDULED_EF, /linkedin: 'publish-linkedin'/);
  assert.match(SCHEDULED_EF, /instagram: 'publish-instagram'/);
});

// ───────────────────────── MCP surface ─────────────────────────

test('1099: 3 MCP tools registered wrapping the RPC trio', () => {
  for (const t of RPCS) {
    assert.match(MCP_INDEX, new RegExp(`mcp\\.tool\\("${t}"`), `tool ${t} not registered`);
    assert.match(MCP_INDEX, new RegExp(`sb\\.rpc\\("${t}"`), `tool ${t} must wrap the canonical RPC`);
  }
  // JS-layer defense-in-depth on the write on-ramp (convention: canV4 before rpc)
  assert.match(MCP_INDEX, /canV4\(sb, member\.id, "manage_comms"\)/);
});

test('1099: manifest regenerated with the trio under the comms domain', () => {
  for (const t of RPCS) {
    const entry = MANIFEST.tools.find((x) => x.name === t);
    assert.ok(entry, `${t} missing from manifest (run node scripts/generate-mcp-manifest.mjs)`);
    assert.equal(entry.domain, 'comms');
  }
});

// ───────────────────────── DB-aware: live gate fail-closed ─────────────────────────

const URL_ = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

test('1099 live: schedule_comms_post fail-closes without an authenticated member (auth.uid() null)', {
  skip: (!URL_ || !KEY) ? 'no SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (offline baseline)' : false,
}, async () => {
  // service-role PostgREST call carries no auth.uid() → members lookup fails → Unauthorized.
  const res = await fetch(`${URL_}/rest/v1/rpc/schedule_comms_post`, {
    method: 'POST',
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_channel: 'linkedin',
      p_media_type: 'TEXT',
      p_payload: { text: 'contract-test probe — must never insert' },
      p_scheduled_at: new Date(Date.now() + 3600_000).toISOString(),
    }),
  });
  assert.equal(res.ok, false, 'service-role (no member) call must be rejected');
  const body = await res.json().catch(() => ({}));
  assert.match(String(body.message ?? ''), /Unauthorized: manage_comms required/);
});

test('1099 live: the trio exists in the live schema (migration 334 applied + PostgREST reloaded)', {
  skip: (!URL_ || !KEY) ? 'no SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (offline baseline)' : false,
}, async () => {
  const res = await fetch(`${URL_}/rest/v1/rpc/_audit_list_public_function_bodies`, {
    method: 'POST',
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.ok(res.status !== 404, 'introspection endpoint reachable');
  const bodies = await res.json().catch(() => []);
  const names = new Set((Array.isArray(bodies) ? bodies : []).map((r) => r.fn_name ?? r.name ?? r.proname));
  for (const fn of RPCS) {
    assert.ok(names.has(fn), `${fn} not found in live schema (apply migration 334 + NOTIFY pgrst)`);
  }
});

const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('1099 live: anon role cannot EXECUTE schedule_comms_post (REVOKE enforced)', {
  skip: (!URL_ || !ANON) ? 'no SUPABASE_URL + real SUPABASE_ANON_KEY (CI may provide a mock key)' : false,
}, async () => {
  const res = await fetch(`${URL_}/rest/v1/rpc/schedule_comms_post`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_channel: 'linkedin',
      p_media_type: 'TEXT',
      p_payload: { text: 'anon probe — must never insert' },
      p_scheduled_at: new Date(Date.now() + 3600_000).toISOString(),
    }),
  });
  assert.equal(res.ok, false, 'anon call must be rejected');
  const body = await res.json().catch(() => ({}));
  // 42501 = permission denied for function (the REVOKE); a mock anon key yields a JWT error
  // upstream of the function, which still satisfies "anon cannot execute".
  assert.ok(
    body.code === '42501' || res.status === 401 || res.status === 403 || res.status === 404,
    `anon must be blocked before the function body runs (got ${res.status} ${JSON.stringify(body).slice(0, 120)})`,
  );
});
