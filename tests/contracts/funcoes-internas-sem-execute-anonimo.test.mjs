/**
 * Funções que só servem a quem tem login não têm EXECUTE para PUBLIC nem anon (#2565, lote 2c).
 *
 * authenticated e service_role mantêm EXECUTE explícito. Para cada função da lista, este guard afirma:
 *   - a migration do lote 2c revoga o EXECUTE de PUBLIC e anon pela assinatura exata (revogar só de
 *     anon não basta: anon herda o EXECUTE de PUBLIC);
 *   - nenhuma migration posterior devolve EXECUTE a anon ou PUBLIC.
 * get_cpmai_leaderboard fica fora de propósito: a W6b (#1383) a manteve com anon, como feed público.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const DIR = join(process.cwd(), 'supabase/migrations');
const ASSINATURAS = [
  '_artia_safe_monthly_metrics(integer, integer)',
  'add_publication_submission_author(uuid, uuid, integer, boolean)',
  'get_card_detail(uuid)',
  'get_card_full_history(uuid)',
  'get_gamification_leaderboard(integer, integer, text, text, text, uuid)',
  'get_meeting_detail(uuid)',
  'get_my_attendance_history(integer)',
  'get_my_cards()',
  'get_my_tasks(text, text)',
  'get_portfolio_planned_vs_actual(integer)',
  'get_tribe_events_timeline(integer, integer, integer)',
  'is_event_mandatory_for_member(uuid, uuid)',
  'list_active_boards()',
  'list_meeting_action_items(uuid, text, uuid, text, boolean)',
  'list_meetings_with_notes(integer, text, text, boolean, integer, integer)',
  'remove_publication_submission_author(uuid, uuid)',
  'submit_cpmai_mock_score(uuid, integer, integer, integer, text, text)',
  'update_cpmai_progress(uuid, text)',
  'update_publication_submission(uuid, text, text, text, text, date, date, date, date, numeric, numeric, text, text, text, uuid)',
  'update_publication_submission_status(uuid, public.submission_status, text)',
];

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
const sql = (f) => maskLineComments(readFileSync(join(DIR, f), 'utf8'));
const idx = files.findIndex((f) => /_lote_2c_status_e_funcoes_internas\.sql$/.test(f));

test('a migration do lote 2c existe', () => {
  assert.ok(idx >= 0);
});

for (const sig of ASSINATURAS) {
  const nome = sig.slice(0, sig.indexOf('('));
  test(`${nome}: sem EXECUTE para PUBLIC e anon`, () => {
    assert.match(
      sql(files[idx]),
      new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${esc(sig)} FROM PUBLIC, anon;`),
      'revogado de PUBLIC e anon pela assinatura',
    );
    for (const f of files.slice(idx + 1)) {
      assert.doesNotMatch(
        sql(f),
        new RegExp(`GRANT[^;]*ON FUNCTION public\\.${esc(nome)}\\([^;]*\\bTO\\b[^;]*\\b(anon|PUBLIC)\\b`, 'i'),
        `${f} devolve EXECUTE a anon ou PUBLIC`,
      );
    }
  });
}

test('get_cpmai_leaderboard fica fora (W6b, #1383)', () => {
  assert.doesNotMatch(sql(files[idx]), /get_cpmai_leaderboard/);
});
