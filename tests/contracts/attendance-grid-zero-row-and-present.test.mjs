/**
 * p124 — get_tribe_attendance_grid cell_status guards.
 *
 * Static contract: assert that the migration that fixes two known bugs in
 * `get_tribe_attendance_grid` is present and that no later migration
 * undoes it.
 *
 * Bugs fixed (diagnosed in handoff_p122):
 *
 * 1. **0-row events generate false absences.** Pre-fix, the cell_status CTE
 *    fell through to `'absent'` whenever no attendance row existed for an
 *    active member, regardless of whether the meeting was tracked at all.
 *    4 cycle-3 tribe events (Agentes Autônomos x2, Talentos, ROI) had 0
 *    rows total and produced ~26 implicit absences for engaged members.
 *
 * 2. **`a.present` was ignored.** The CASE only checked `a.id IS NOT NULL`
 *    and treated any row (other than excused) as `'present'`. 6 rows had
 *    `present=false AND excused=false` (explicit absences entered by
 *    leaders) but were silently rendered as `'present'`.
 *
 * The fix migration must:
 *   - introduce an `event_row_counts` CTE (pre-aggregate row counts per event)
 *   - branch on `a.present = true` / `a.present = false` explicitly
 *   - return `'na'` when `event_row_counts.row_count = 0`
 *
 * Action item #5 from Reunião Geral 2026-05-07, deadline 2026-05-15.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';

const MIG_PATH = path.resolve(
  'supabase/migrations/20260517180000_p124_fix_attendance_grid_zero_row_and_present.sql'
);

test('p124: fix migration for get_tribe_attendance_grid exists', async () => {
  const stat = await fs.stat(MIG_PATH).catch(() => null);
  assert.ok(stat, `Migration file must exist at ${MIG_PATH}`);
});

test('p124: migration includes event_row_counts CTE for 0-row detection', async () => {
  const src = await fs.readFile(MIG_PATH, 'utf-8');
  assert.match(
    src,
    /event_row_counts\s+AS\s*\(/,
    'migration must define an event_row_counts CTE that aggregates COUNT(*) per event_id'
  );
  assert.match(
    src,
    /COALESCE\(erc\.row_count,\s*0\)\s*=\s*0\s+THEN\s+'na'/,
    "migration must return 'na' when COALESCE(erc.row_count, 0) = 0 (meeting was not tracked)"
  );
});

test('p124: cell_status branches on a.present (not just row existence)', async () => {
  const src = await fs.readFile(MIG_PATH, 'utf-8');
  assert.match(
    src,
    /a\.id\s+IS\s+NOT\s+NULL\s+AND\s+a\.present\s*=\s*true\s+THEN\s+'present'/,
    "cell_status must explicitly check a.present = true → 'present'"
  );
  assert.match(
    src,
    /a\.id\s+IS\s+NOT\s+NULL\s+AND\s+a\.present\s*=\s*false\s+THEN\s+'absent'/,
    "cell_status must explicitly check a.present = false → 'absent' (was missing pre-p124)"
  );
});

test('p124: NOTIFY pgrst reload schema fires after migration', async () => {
  const src = await fs.readFile(MIG_PATH, 'utf-8');
  assert.match(
    src,
    /NOTIFY\s+pgrst\s*,\s*'reload schema'/,
    'migration must NOTIFY pgrst reload schema so PostgREST picks up the new function body'
  );
});

/**
 * SUPERSEDIDO EM PARTE PELO #1657 (2026-08-09).
 *
 * O fix #1 do p124 ("0 linhas no evento => 'na'") protegia por EVENTO: só valia quando NINGUÉM
 * registrou. Ele saiu do corpo vivo na migration de captura de deriva
 * `20260802000001_p209_issue_226_phase_b_drift_capture_26_fns.sql` e ninguém percebeu, porque este
 * guard só exigia que o CTE `event_row_counts` EXISTISSE nas migrations posteriores - e ele
 * continuou existindo, alimentando um alias (`erc`) que nenhuma linha lia. Defesa decorativa: o
 * teste provava que um texto estava num arquivo, não que a regra rodava.
 *
 * O #1657 substituiu a regra por uma mais forte, por CÉLULA: sem linha num evento NÃO SELADO é
 * 'unrecorded', não 'absent'. Ela cobre os eventos com zero linha (o caso do p124) E os eventos em
 * que só uma parte registrou, que o p124 não alcançava. O CTE morto saiu junto.
 *
 * Por isso a checagem para-a-frente abaixo passou a exigir a regra NOVA. O fix #2 do p124
 * (`a.present` explícito) continua vivo e continua sendo exigido.
 */
test('p124/#1657: toda migration posterior mantém a.present explícito E a regra de "sem registro"', async () => {
  const dir = path.resolve('supabase/migrations');
  const files = (await fs.readdir(dir))
    .filter(f => f.endsWith('.sql') && f > '20260517180000_')
    .sort();

  const redefinem = [];
  for (const f of files) {
    const src = await fs.readFile(path.join(dir, f), 'utf-8');
    if (!/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?get_tribe_attendance_grid\b/i.test(src)) continue;
    redefinem.push(f);

    // p124 fix #2 — segue de pé em toda recaptura.
    assert.match(
      src,
      /a\.present\s*=\s*(?:true|false)/,
      `Later migration ${f} redefines get_tribe_attendance_grid but does not branch on a.present (regression of p124 fix #2)`
    );
  }

  // A captura MAIS RECENTE tem de carregar a regra que substituiu o fix #1. Afirmar sobre a última
  // (e não sobre todas) é o que permite que uma recaptura intermediária tenha existido sem a regra
  // enquanto ela ainda não existia.
  assert.ok(redefinem.length > 0, 'alguma migration precisa definir get_tribe_attendance_grid');
  const ultima = await fs.readFile(path.join(dir, redefinem[redefinem.length - 1]), 'utf-8');
  assert.match(
    ultima,
    /roster_sealed_at IS NULL THEN 'unrecorded'/,
    `${redefinem[redefinem.length - 1]} é a captura mais recente e não tem a regra do #1657 ` +
      '(sem linha em evento não selado = "unrecorded"), que substituiu o fix #1 do p124'
  );
});
