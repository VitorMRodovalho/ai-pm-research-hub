/**
 * #1192 — Filiação queue chapter resolution is registry-driven end to end.
 *
 * Root cause (grounded live 2026-07-08, index case João/PMI-AM): the frontend kept a
 * SECOND, hardcoded copy of the BR-chapter parser (/brazil chapter/i in
 * src/lib/affiliation-chapters.ts), so "Amazônia Chapter" (a chapter_registry
 * vep_name_alias for AM) parsed to [] and the row fell to the amber "verificar
 * manualmente" branch despite the verified SSOT row in member_chapter_affiliations.
 * The chapter filter likewise derived its options from the loaded rows' parse (5
 * options) instead of chapter_registry (15 BR chapters, D2/#1178).
 *
 * The fix (migration 20260805000372 + island/lib changes) locks:
 *   1. the queue RPC read-throughs the SSOT: per-row 'chapter_affiliations' built from
 *      member_chapter_affiliations × chapter_registry, ALL name→code resolution done
 *      server-side by resolve_br_chapter_code() (#1175 F2 — the ONE resolver);
 *   2. the island's chapter filter options come from chapter_registry, never from the
 *      loaded rows' parse;
 *   3. the client raw parse survives only as display fallback (unifiedBrChapters), and
 *      the amber warning fires only when NEITHER the SSOT nor the raw data resolve
 *      (behavioural lock: tests/affiliation-chapters.test.mjs #1192 cases);
 *   4. no new hardcoded chapter-name heuristics/aliases re-enter the client lib —
 *      aliases are chapter_registry.vep_name_aliases config, not code.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

const MIG = read('../../supabase/migrations/20260805000372_1192_affiliation_queue_chapter_ssot_readthrough.sql');
const MIG_CODE = MIG.replace(/--.*$/gm, '');
const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
const ISLAND_CODE = stripComments(read('../../src/components/admin/AffiliationQueueIsland.tsx'));
const LIB_CODE = stripComments(read('../../src/lib/affiliation-chapters.ts'));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rest(path, init = {}) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      ...(init.headers || {}),
    },
  });
  if (!res.ok) throw new Error(`${path} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── Source contract (offline) ───────────────────────────────────────────────

test('1192: queue RPC emits chapter_affiliations from the SSOT via the one resolver', () => {
  assert.match(MIG, /'chapter_affiliations'/, 'chapter_affiliations key emitted');
  assert.match(MIG_CODE, /member_chapter_affiliations/, 'reads the SSOT fact table');
  assert.match(MIG_CODE, /chapter_registry/, 'labels come from chapter_registry');
  assert.match(MIG_CODE, /resolve_br_chapter_code/, 'name→code resolution via the #1175 F2 SSOT resolver');
  for (const key of ['chapter_code', 'chapter_label', 'source', 'verified_at', 'raw_name', 'expiry']) {
    assert.match(MIG, new RegExp(`'${key}'`), `entry field ${key}`);
  }
  // 659/996/1129 invariants preserved (not weakened by the read-through)
  assert.match(MIG_CODE, /filiacao_director/, 'function-anchored gate intact');
  assert.match(MIG_CODE, /log_pii_access_batch/, 'LGPD Art. 37 trail intact');
  assert.match(MIG_CODE, /REVOKE ALL ON FUNCTION public\.get_affiliation_verification_queue\(\) FROM public, anon/, 'hardened grants intact');
});

test('1192: island chapter filter options come from chapter_registry, not from row parsing', () => {
  assert.match(ISLAND_CODE, /from\('chapter_registry'\)/, 'reads the registry directly (RLS read-all authenticated)');
  assert.doesNotMatch(ISLAND_CODE, /rows\.forEach\(\s*r\s*=>\s*brChapters/, 'the old rows-derived chapterOptions is gone');
});

test('1192: island resolves chapters SSOT-first; raw parse is fallback only', () => {
  assert.match(ISLAND_CODE, /unifiedBrChapters\(/, 'cell/filter/sort go through the SSOT-first helper');
  assert.match(ISLAND_CODE, /soonestChapterExpiry\(/, 'Vencimento/farol go through the SSOT-first summary');
  assert.match(ISLAND_CODE, /chapter_affiliations/, 'QueueRow carries the read-through payload');
  // The island must never call the raw parser directly again — everything routes through the
  // SSOT-first helpers. (The "Brazil Chapter" strings that remain are the free-text verify
  // modal's placeholder/prefill, which is a write field, not resolution logic.)
  assert.doesNotMatch(ISLAND_CODE, /(?<!unified)brChapters\(/, 'no direct raw-parser call left in the island');
  assert.doesNotMatch(ISLAND_CODE, /soonestBrExpiry\(/, 'no raw-only expiry summary left in the island');
});

test('1192: no hardcoded aliases re-enter the client lib (aliases are registry config)', () => {
  assert.doesNotMatch(LIB_CODE, /Amaz[oô]nia/i, 'the alias that motivated the fix must live in chapter_registry.vep_name_aliases, not in code');
});

// ── DB-aware (behavioural) ──────────────────────────────────────────────────

test('1192: resolve_br_chapter_code resolves the registry alias (no suffix) to AM', { skip: canRun ? false : skipMsg }, async () => {
  const code = await rest('/rest/v1/rpc/resolve_br_chapter_code', {
    method: 'POST',
    body: JSON.stringify({ p_name: 'Amazônia Chapter' }),
  });
  assert.equal(code, 'AM', 'alias resolves via chapter_registry.vep_name_aliases');
});

test('1192: chapter_registry offers the full BR option list (the bug: only 5 parse-derived options)', { skip: canRun ? false : skipMsg }, async () => {
  const rows = await rest('/rest/v1/chapter_registry?select=chapter_code,state&country=eq.BR&is_active=eq.true');
  assert.ok(Array.isArray(rows) && rows.length > 5, `registry must offer more than the 5 parse-derived options (got ${rows.length})`);
  const codes = rows.map((r) => r.chapter_code);
  assert.ok(codes.includes('AM'), 'AM (the alias chapter) is filterable');
  assert.ok(codes.includes('GO'), 'GO (sede) is filterable');
  assert.ok(rows.every((r) => r.state), 'every option has a display label (state)');
});
