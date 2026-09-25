/**
 * Funcao SECURITY DEFINER nao decide papel por current_user.
 *
 * Dentro de uma funcao SECURITY DEFINER de dono postgres, current_user e sempre o dono. Uma checagem
 * como `current_user IN ('postgres', ...)` e sempre verdadeira e nao distingue quem chamou. O
 * discriminador canonico e public._request_is_rest_caller() (#684), que le o GUC de role da
 * requisicao: verdadeiro para authenticated/anon via PostgREST, falso para service_role, pg_cron e
 * conexao direta.
 *
 * Catalogo: a captura VIGENTE de cada funcao em supabase/migrations, com comentario de linha
 * mascarado. Que a captura vigente e o corpo vivo, quem garante e o gate de drift (Phase C). Este
 * guard nao repete essa prova.
 *
 * Duas excecoes nomeadas, e a lista so desce: quando uma delas for corrigida, ela SAI daqui, e o
 * teste reprova se continuar listada sem ter o padrao.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = join(ROOT, 'supabase/migrations');
const PADRAO = /\bcurrent_user\s+(?:NOT\s+)?IN\s*\(/i;

const EXCECOES = new Map([
  ['compute_ai_calibration_weekly',
    'chamada por trigger_ai_calibration_run (RPC de usuario): trocar ativa o gate cron-only e quebra o disparo manual'],
  ['check_pre_onboarding_auto_steps',
    'chamada por approve_selection_application e get_candidate_onboarding_progress: trocar ativa o gate interno (proprio membro ou manage_member) nesses fluxos'],
]);

/** Captura vigente de toda funcao de public: nome -> { file, secdef, body mascarado }. */
function catalogo() {
  const vigente = new Map();
  for (const file of readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(DIR, file), 'utf8'));
    const re = /\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"?public"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi;
    let m;
    while ((m = re.exec(sql)) !== null) {
      let depth = 1;
      let i = re.lastIndex;
      while (i < sql.length && depth > 0) {
        if (sql[i] === '(') depth++;
        else if (sql[i] === ')') depth--;
        i++;
      }
      const as = sql.slice(i).match(/\bAS\s+(\$[a-zA-Z_]*\$)/);
      if (!as) continue;
      const inicio = i + as.index + as[0].length;
      const fim = sql.indexOf(as[1], inicio);
      if (fim < 0) continue;
      const cabecalho = sql.slice(m.index, inicio);
      const cauda = (sql.slice(fim + as[1].length).match(/^[^;]*/) || [''])[0];
      vigente.set(m[1].toLowerCase(), {
        file,
        secdef: /SECURITY\s+DEFINER/i.test(cabecalho + cauda),
        body: sql.slice(inicio, fim),
      });
    }
  }
  return vigente;
}

test('nenhuma SECURITY DEFINER vigente decide papel por current_user, fora das excecoes nomeadas', () => {
  const cat = catalogo();
  // Controle: o catalogo enxerga SECURITY DEFINER; vazio aqui deixaria a assercao abaixo verde a toa.
  const secdef = [...cat.values()].filter((v) => v.secdef).length;
  assert.ok(secdef > 500, `o catalogo achou so ${secdef} funcoes SECURITY DEFINER: o parser quebrou`);

  const comPadrao = [...cat].filter(([, v]) => v.secdef && PADRAO.test(v.body)).map(([n]) => n).sort();
  const novas = comPadrao.filter((n) => !EXCECOES.has(n));
  assert.deepEqual(novas, [],
    `funcao SECURITY DEFINER decidindo papel por current_user: ${novas.join(', ')}. ` +
    'Use public._request_is_rest_caller() (#684).');

  const corrigidas = [...EXCECOES.keys()].filter((n) => !comPadrao.includes(n));
  assert.deepEqual(corrigidas, [],
    `${corrigidas.join(', ')} nao tem mais o padrao: tire da lista de excecoes (a lista so desce)`);
});

// Cada corrigida decide pelo GUC de role NO statement que decide: a condicao amarrada ao que ela produz.
const DECIDE = {
  record_drive_discovery: /IF\s+public\._request_is_rest_caller\(\)\s+THEN\s+DECLARE\s+v_caller_id\s+uuid;/,
  list_initiatives_missing_drive_workspace: /v_system\s*:=\s*\(NOT\s+public\._request_is_rest_caller\(\)\);\s*IF\s+NOT\s+v_system\s+THEN/,
  member_resolve_email: /IF\s+auth\.uid\(\)\s+IS\s+NULL\s+AND\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Not authenticated';\s+END IF;\s+IF\s+public\._request_is_rest_caller\(\)\s+AND\s+NOT\s+public\.rls_is_member\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized: member_resolve_email requires membership'/,
  check_schema_invariants: /IF\s+auth\.uid\(\)\s+IS\s+NULL\s+AND\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
  get_cycle_renewal_radar: /ELSIF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
  get_entry_chapter_diagnosis: /ELSIF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
  nudge_entry_chapter_cohort: /ELSIF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
  notify_missing_drive_workspaces: /IF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'service-role or cron only'/,
  auto_promote_eligible_leads_daily: /v_cron_context\s*:=\s*\(NOT\s+public\._request_is_rest_caller\(\)\);\s*IF\s+NOT\s+v_cron_context\s+THEN/,
  _get_vault_secret: /IF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RETURN\s+NULL;/,
  _audit_merit_transfer_on_completed_cards: /IF\s+NOT\s+\(\s*NOT\s+public\._request_is_rest_caller\(\)\s+OR\s+\(auth\.uid\(\)\s+IS\s+NOT\s+NULL/,
  _test_detect_inactive_with_threshold: /IF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
  _test_invariants_with_synthetic_breach: /IF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
  _test_meeting_close_summary_roundtrip: /IF\s+public\._request_is_rest_caller\(\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
};

for (const [fn, decide] of Object.entries(DECIDE)) {
  test(`${fn}: o gate decide pelo GUC de role`, () => {
    const body = maskLineComments(latestFunctionCapture(ROOT, fn).body);
    assert.match(body, decide, `${fn}: a condicao que decide nao e mais a do GUC de role`);
    assert.doesNotMatch(body, PADRAO, `${fn}: voltou a decidir por current_user`);
  });
}
