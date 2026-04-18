/**
 * ADR-0015 — Writers to dual-write C3 tables must write BOTH tribe_id AND initiative_id
 *
 * Static contract complementing:
 *   - rpc-v4-auth.test.mjs         — ADR-0011 auth gate static check
 *   - schema-cache-columns.test.mjs — ADR-0012 cache columns + triggers
 *   - schema-invariants.test.mjs   — ADR-0012 live-DB runtime violations
 *
 * Gap this test closes: after Phase 2 (dual-write trigger drop, upcoming), a
 * new migration that INSERTs or UPDATEs a C3 table with only `tribe_id` would
 * leave `initiative_id` NULL. Readers refactored in Phase 1 JOIN on
 * `initiatives.legacy_tribe_id` to reach those rows and would return stale/
 * empty shapes.
 *
 * Contract: in any migration post-cutover, if an INSERT or UPDATE targets a
 * C3 table AND assigns `tribe_id`, it MUST also assign `initiative_id`.
 *
 * Enforcement window: migrations ≥ 20260427140000 (Commit 1 of writer refactor,
 * 2026-04-17). Earlier migrations hold the pre-dual-write writers that
 * Commit 1 itself rewrote; the rewritten bodies live in the post-cutover files.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const MIGRATIONS_DIR = resolve(process.cwd(), 'supabase/migrations');

// ADR-0015 Phase 1 writer refactor cutover: first migration where dual-write
// from the writer side became the expected pattern.
const CUTOVER = '20260427140000';

// C3 tables that carry both tribe_id and initiative_id dual-write (Phase 1).
// As Phase 3 drops the tribe_id column table-by-table, those entries are
// removed from this list — after the drop, Postgres itself rejects any
// INSERT referencing the missing column, so the static check becomes
// redundant for the dropped tables.
//
// Phase 3 drop log:
//   - 2026-04-17 (migration 20260427180000): announcements, ia_pilots, pilots
//   - 2026-04-17 (migration 20260427190000): webinars
//   - 2026-04-17 (migration 20260427200000): meeting_artifacts, publication_submissions, public_publications, tribe_deliverables
//   - 2026-04-18 (migration 20260428010000): broadcast_log, hub_resources (Phase 3c)
const C3_TABLES = [
  'project_boards',
  'events',
];

// Allowlist for specific migration files whose tribe_id-only writes are
// intentional (one-off backfill that sets initiative_id via separate pass,
// a data fix with no row coverage risk, etc.). Each entry documents why.
const DUAL_WRITE_EXEMPT = new Map([
  // Example (remove if unused):
  // ['20260427999999_backfill_initiative_id.sql', 'Backfill sweep; second pass sets initiative_id from legacy_tribe_id'],
]);

function splitColumnList(text) {
  return text
    .split(',')
    .map(c => c.trim().replace(/^[\s\n\r]+/, '').replace(/[\s\n\r].*$/, ''))
    .filter(Boolean);
}

function scanInserts(sql, table) {
  const out = [];
  const re = new RegExp(`INSERT\\s+INTO\\s+(?:public\\.)?${table}\\s*\\(([\\s\\S]*?)\\)`, 'gi');
  let m;
  while ((m = re.exec(sql)) !== null) {
    const cols = splitColumnList(m[1]);
    if (cols.includes('tribe_id') && !cols.includes('initiative_id')) {
      out.push({
        kind: 'INSERT',
        table,
        snippet: m[1].replace(/\s+/g, ' ').trim().slice(0, 80),
      });
    }
  }
  return out;
}

function scanUpdates(sql, table) {
  const out = [];
  // Match `UPDATE <table> SET <body>` bounded by WHERE / RETURNING / ;
  const re = new RegExp(`UPDATE\\s+(?:public\\.)?${table}\\s+SET\\s+([\\s\\S]*?)(?:\\s+WHERE\\b|\\s+RETURNING\\b|;)`, 'gi');
  let m;
  while ((m = re.exec(sql)) !== null) {
    const setBlock = m[1];
    if (/\btribe_id\s*=/.test(setBlock) && !/\binitiative_id\s*=/.test(setBlock)) {
      out.push({
        kind: 'UPDATE',
        table,
        snippet: setBlock.replace(/\s+/g, ' ').trim().slice(0, 80),
      });
    }
  }
  return out;
}

test('ADR-0015: C3 writers must dual-write tribe_id + initiative_id', () => {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql') && f >= CUTOVER)
    .sort();

  const violations = [];
  for (const f of files) {
    if (DUAL_WRITE_EXEMPT.has(f)) continue;
    const sql = readFileSync(resolve(MIGRATIONS_DIR, f), 'utf8');
    for (const table of C3_TABLES) {
      for (const v of [...scanInserts(sql, table), ...scanUpdates(sql, table)]) {
        violations.push(`${f} :: ${v.kind} ${v.table} — tribe_id present, initiative_id missing: ${v.snippet}`);
      }
    }
  }

  if (violations.length > 0) {
    const msg = [
      'ADR-0015 violation: writers into dual-write C3 tables reference tribe_id',
      'without also writing initiative_id. After Phase 2 (dual-write trigger drop),',
      'these writes would leave initiative_id NULL — readers that JOIN initiatives',
      'on legacy_tribe_id return stale or empty rows.',
      '',
      'Fix: derive initiative_id inside the RPC body and include it alongside',
      'tribe_id in the column list / SET clause:',
      '',
      '  DECLARE v_initiative_id uuid;',
      '  ...',
      '  IF p_tribe_id IS NOT NULL THEN',
      '    SELECT id INTO v_initiative_id FROM public.initiatives',
      '    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;',
      '  END IF;',
      '  INSERT INTO <c3_table> (..., tribe_id, initiative_id, ...)',
      '  VALUES (..., p_tribe_id, v_initiative_id, ...);',
      '',
      'If the write is intentionally single-column (one-off backfill etc.), add',
      'the migration filename to DUAL_WRITE_EXEMPT with a short rationale.',
      '',
      'Violations:',
      ...violations.map(v => `  - ${v}`),
    ].join('\n');
    assert.fail(msg);
  }
});

test('ADR-0015: cutover migration itself is dual-write compliant (self-check)', () => {
  // Sanity — the first migration of the writer refactor must pass its own rule.
  const sql = readFileSync(resolve(MIGRATIONS_DIR, `${CUTOVER}_adr0015_phase1_writers_batch_a_dual_write.sql`), 'utf8');
  const violations = [];
  for (const table of C3_TABLES) {
    for (const v of [...scanInserts(sql, table), ...scanUpdates(sql, table)]) {
      violations.push(`${v.kind} ${v.table}: ${v.snippet}`);
    }
  }
  assert.equal(violations.length, 0,
    `Cutover migration must be dual-write compliant; found ${violations.length} issue(s):\n  ${violations.join('\n  ')}`);
});
