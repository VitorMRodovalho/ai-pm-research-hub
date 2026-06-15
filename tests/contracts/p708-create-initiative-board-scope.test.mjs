/**
 * #708 — create_initiative deve provisionar o board com board_scope correto para
 * kinds NÃO-tribo (congress/committee/workgroup/book_club/study_group).
 *
 * Bug: o INSERT em project_boards não setava board_scope → default 'tribe', e o
 * trigger enforce_project_board_taxonomy() exige que board 'tribe' aponte para
 * iniciativa tribe-scoped (legacy_tribe_id NOT NULL). Para kinds não-tribo isso
 * sempre falhava → criar Congresso/Comitê/Workgroup pelo /admin/portfolio quebrava.
 *
 * Fix (mig 174): deriva board_scope da tribe-scoping real (tribe-scoped → 'tribe';
 * senão 'global' + domain_key de metadata ou fallback 'cross_functional').
 *
 * STATIC: a migration deriva board_scope + seta domain_key no insert do board.
 * DB-AWARE: invariante de taxonomy — nenhum board de iniciativa NÃO-tribo está com
 *           board_scope='tribe' (o que o fix garante + o trigger exige).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260805000174_708_create_initiative_board_scope_non_tribe.sql');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

// ── STATIC ──────────────────────────────────────────────────────────────────
test('#708 static: create_initiative derives board_scope + sets domain_key', () => {
  assert.ok(existsSync(MIG), 'migration 20260805000174 present');
  const src = readFileSync(MIG, 'utf8');
  const code = src.replace(/^\s*--.*$/gm, ''); // strip line comments

  assert.match(code, /CREATE OR REPLACE FUNCTION public\.create_initiative\(/, 'redefine create_initiative');
  // reads legacy_tribe_id of the freshly-created initiative
  assert.match(code, /SELECT\s+legacy_tribe_id\s+INTO\s+v_legacy_tribe_id\s+FROM\s+public\.initiatives\s+WHERE\s+id\s*=\s*v_new_id/i,
    'must re-read legacy_tribe_id of the new initiative');
  // tribe-scoped → 'tribe'; else 'global'
  assert.match(code, /v_legacy_tribe_id\s+IS\s+NOT\s+NULL[\s\S]*?v_board_scope\s*:=\s*'tribe'/i, "tribe-scoped → board_scope='tribe'");
  assert.match(code, /ELSE[\s\S]*?v_board_scope\s*:=\s*'global'/i, "non-tribe → board_scope='global'");
  // global requires domain_key (from metadata or fallback)
  assert.match(code, /v_domain_key\s*:=\s*coalesce\(\s*nullif\(\s*p_metadata->>'domain_key'[\s\S]*?\)/i,
    'global board domain_key from metadata.domain_key with a fallback');
  // the board insert now passes board_scope + domain_key
  assert.match(code, /INSERT INTO public\.project_boards\s*\([^)]*board_scope[^)]*domain_key[^)]*\)/i,
    'project_boards INSERT must include board_scope + domain_key columns');
  // research_tribe fail-loud guard (a tribe needs the legacy_tribe_id bridge; create_initiative can't make a valid tribe board)
  assert.match(code, /IF\s+p_kind\s*=\s*'research_tribe'\s+THEN[\s\S]*?RAISE\s+EXCEPTION/i,
    'must fail-loud for research_tribe (use the tribe bridge instead)');
  // self-contained GRANT
  assert.match(code, /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.create_initiative\([^)]*\)\s+TO\s+authenticated/i,
    'migration must include GRANT EXECUTE for self-containment');
});

// ── DB-AWARE INVARIANT ────────────────────────────────────────────────────────
test('#708 invariant: no board of a non-tribe initiative is board_scope=tribe',
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  // pull boards joined to their initiative's legacy_tribe_id
  const { data, error } = await sb
    .from('project_boards')
    .select('id, board_scope, board_name, initiative_id, initiatives!inner(legacy_tribe_id, kind)')
    .not('initiative_id', 'is', null);
  assert.ok(!error, `query failed: ${error?.message}`);

  const violations = (data ?? []).filter(b =>
    b.board_scope === 'tribe' && (b.initiatives?.legacy_tribe_id ?? null) === null
  );
  assert.equal(violations.length, 0,
    `non-tribe initiatives must not carry a 'tribe'-scoped board (taxonomy trigger forbids it): ` +
      JSON.stringify(violations.map(v => ({ board: v.board_name, kind: v.initiatives?.kind }))));
});
