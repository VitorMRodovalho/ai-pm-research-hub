/**
 * RPCs internas nao sao executaveis por clientes, e create_initiative exige manage_platform de quem chama
 * pelo PostgREST.
 *
 * Cinco funcoes SECURITY DEFINER tiveram o grafo de chamadores revisado (app, Edge Functions, outras
 * funcoes, cron) e nao tem chamador cliente legitimo: a ultima instrucao de GRANT/REVOKE que toca
 * PUBLIC/anon/authenticated em cada uma tem de ser um REVOKE, e nenhum GRANT posterior pode devolver o
 * acesso. create_initiative tem um unico chamador cliente (admin/initiatives, tier manager), e o gate
 * espelha essa regra.
 *
 * Estatico sobre supabase/migrations (comentarios de linha mascarados). O efeito no banco foi provado por
 * impersonacao no momento da aplicacao; este guard impede a regressao pelo arquivo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = join(ROOT, 'supabase/migrations');
const INTERNAS = [
  ['_get_peer_review_eligibility', 'uuid'],
  ['anonymize_application_for_ai_training', 'uuid'],
  ['check_application_score_consistency', ''],
  ['process_interview_reminders_1h', ''],
  ['v4_notify_expiring_affiliations', 'boolean'],
];
const CLIENTES = /\b(PUBLIC|anon|authenticated)\b/i;

/** Instrucoes GRANT/REVOKE EXECUTE sobre a funcao, em ordem cronologica de migration. */
function privilegios(nome) {
  const out = [];
  const re = new RegExp(`\\b(GRANT|REVOKE)\\s+(?:ALL|EXECUTE)[^;]*?ON\\s+FUNCTION\\s+(?:public\\.)?${nome}\\s*\\([^)]*\\)[^;]*;`, 'gi');
  for (const file of readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = maskLineComments(readFileSync(join(DIR, file), 'utf8'));
    for (const m of sql.matchAll(re)) out.push({ file, verbo: m[1].toUpperCase(), texto: m[0] });
  }
  return out;
}

for (const [nome, args] of INTERNAS) {
  test(`${nome}(${args}): a ultima instrucao que toca clientes e um REVOKE`, () => {
    const tocam = privilegios(nome).filter((p) => CLIENTES.test(p.texto.split(/\b(?:TO|FROM)\b/i).pop()));
    assert.ok(tocam.length > 0, `nenhuma instrucao de privilegio encontrada para ${nome}: o parser quebrou`);
    const ultima = tocam[tocam.length - 1];
    assert.equal(ultima.verbo, 'REVOKE', `${nome}: a ultima instrucao sobre clientes e ${ultima.verbo} (${ultima.file})`);
    assert.match(ultima.texto, /FROM\s+PUBLIC,\s*anon,\s*authenticated/i, `${nome}: o REVOKE tem de cobrir os tres`);
  });
}

test('create_initiative: chamador REST precisa de manage_platform, e a condicao decide o RAISE', () => {
  const body = maskLineComments(latestFunctionCapture(ROOT, 'create_initiative').body);
  assert.match(body,
    /IF\s+public\._request_is_rest_caller\(\)\s+THEN\s+SELECT\s+id\s+INTO\s+v_caller_id\s+FROM\s+public\.members\s+WHERE\s+auth_id\s*=\s*auth\.uid\(\);\s+IF\s+v_caller_id\s+IS\s+NULL\s+OR\s+NOT\s+public\.can_by_member\(v_caller_id,\s*'manage_platform'\)\s+THEN\s+RAISE\s+EXCEPTION\s+'Unauthorized/,
    'o gate de create_initiative saiu ou deixou de decidir o RAISE');
});
