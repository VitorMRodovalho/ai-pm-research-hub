/**
 * Contract: #1586 — o resgate manual tem contador PRÓPRIO, e com ele um autor.
 *
 * O defeito da issue não é o cap, é a AUSÊNCIA de superfície. Para re-convidar uma candidatura em
 * `interview_pending` (convite emitido e nunca agendado) só havia SQL direto, e por ali a conexão é
 * `service_role`: a RPC entra no ramo `v_is_cron`, e o `admin_audit_log` grava `actor_id = NULL` com
 * `dispatch_source: 'cron'` — registra ato do SISTEMA o que foi decisão de uma PESSOA. Aconteceu em
 * 03/08/2026 (3 candidaturas) e de novo em 13/08/2026.
 *
 * Expor a RPC no MCP, sozinho, não resolveria: medido em 14/08/2026, **7 das 10** candidaturas em
 * `interview_pending` do ciclo aberto já tinham `interview_auto_rescue_count >= 1`, e o guard levanta
 * exceção nesse caso. A superfície recusaria 7 dos 10 casos que ela mostra.
 *
 * ⚖️ Decisão do PM (14/08/2026): contador SEPARADO, cap 3 no manual. Duas inversas que este teste
 * proíbe, cada uma por um motivo distinto:
 *
 * 1. **Nunca afrouxar o contador automático.** O invariante `AI_unbooked_rescue_cap_respected` trata
 *    `interview_auto_rescue_count > 1` como violação de schema (baseline 0). Se o caminho manual
 *    voltar a incrementar essa coluna, o invariante passa a acusar uso legítimo — e a saída fácil
 *    seria afrouxar o invariante, que é justamente o que não pode acontecer.
 *
 * 2. **A mutação continua DEPOIS do despacho.** O contrato do #1598 casa por regex o literal
 *    `interview_auto_rescue_count = interview_auto_rescue_count + 1` e exige que ele apareça depois
 *    da chamada ao notify. Ramificar o incremento não pode apagar esse literal: se ele sumir, o
 *    guard do #1598 falha dizendo "padrão obsoleto" e a proteção real (recusa não queima o cap)
 *    fica sem teste.
 *
 * Camada A (estática, sobre a migration e a EF) + camada B (VIVA, sobre o banco): um guard que só lê
 * arquivo fica verde com o mecanismo inerte — a lição do #1649.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const EF_PATH = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');

const MIGRATION = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.includes('1586_resgate_manual_com_contador_proprio'))
  .sort()
  .pop();

/**
 * Comentários FORA antes de qualquer asserção de ausência: o cabeçalho da migration cita
 * literalmente os nomes das duas colunas e do invariante, e um guard de ausência sobre o fonte cru
 * casaria o próprio comentário que explica a decisão.
 */
const semComentarios = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

const SQL = MIGRATION
  ? semComentarios(readFileSync(join(MIGRATIONS_DIR, MIGRATION), 'utf8'))
  : '';
const SQL_CRU = MIGRATION ? readFileSync(join(MIGRATIONS_DIR, MIGRATION), 'utf8') : '';
const EF = readFileSync(EF_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const anonSkipMsg = 'Skipped: SUPABASE_URL + PUBLIC_SUPABASE_ANON_KEY required';

async function rest(caminho, init) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${caminho}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      ...(init?.headers ?? {}),
    },
  });
  return { status: r.status, body: await r.json().catch(() => null) };
}

// ── A · a migration e a superfície dizem o que a decisão foi ─────────────────────────────────

test('A1: a migration do #1586 está no repositório', () => {
  assert.ok(MIGRATION, 'nenhuma migration 1586_resgate_manual_* em supabase/migrations');
});

test('A2: a coluna do contador manual é criada NOT NULL DEFAULT 0', () => {
  assert.match(
    SQL,
    /ADD COLUMN IF NOT EXISTS interview_manual_rescue_count integer NOT NULL DEFAULT 0/,
    'a coluna do contador manual sumiu ou perdeu NOT NULL/DEFAULT 0 — sem default, uma candidatura '
    + 'antiga com NULL passaria pelo guard `v_used >= v_cap` com comparação nula (nunca verdadeira) '
    + 'e o cap manual não valeria para ninguém.',
  );
});

test('A3: o cap manual é 3 e o automático continua 1, cada um lendo o SEU contador', () => {
  assert.match(SQL, /v_cap := 1;\s*v_used := v_app\.interview_auto_rescue_count;/,
    'o ramo automático deixou de ler interview_auto_rescue_count com cap 1');
  assert.match(SQL, /v_cap := 3;\s*v_used := v_app\.interview_manual_rescue_count;/,
    'o ramo manual deixou de ler interview_manual_rescue_count com cap 3');
});

test('A4: o caminho MANUAL não encosta no contador automático (o invariante depende disso)', () => {
  // A inversa da decisão 1. O ramo manual tem de incrementar a coluna PRÓPRIA; se ele voltar a
  // somar em interview_auto_rescue_count, `AI_unbooked_rescue_cap_respected` passa a acusar uso
  // legítimo como violação de schema.
  assert.match(
    SQL,
    /ELSE\s*UPDATE public\.selection_applications SET interview_manual_rescue_count = interview_manual_rescue_count \+ 1/,
    'o ramo manual não incrementa interview_manual_rescue_count — se ele estiver somando no '
    + 'contador automático, o invariante AI_unbooked_rescue_cap_respected vai acusar violação de '
    + 'schema em cada resgate humano.',
  );
});

test('A5: o literal do incremento automático sobrevive — o contrato do #1598 casa por regex nele', () => {
  // A inversa da decisão 2. Não basta o incremento existir: ele precisa existir com ESTE texto,
  // porque 1598-rescue-refusal-and-cron-error-capture casa exatamente este padrão para provar que
  // a mutação vem DEPOIS do despacho. Um CASE WHEN ... THEN 1 ELSE 0 END quebraria o guard vizinho
  // em silêncio (ele falharia dizendo "padrão obsoleto, corrigir o teste").
  assert.match(
    SQL_CRU,
    /interview_auto_rescue_count = interview_auto_rescue_count \+ 1/,
    'o literal do incremento automático mudou de forma: o guard do #1598 casa exatamente este '
    + 'padrão e vai falhar como "padrão obsoleto", deixando sem teste a proteção de que uma recusa '
    + 'de gate NÃO queima o cap.',
  );
  const iNotify = SQL_CRU.indexOf('notify_selection_cutoff_approved(p_application_id)');
  const iMut = SQL_CRU.indexOf('interview_auto_rescue_count = interview_auto_rescue_count + 1');
  assert.ok(iNotify > -1 && iMut > iNotify,
    'a mutação de estado voltou a acontecer ANTES do despacho — regressão da #1598');
});

test('A6: a RPC é revogada de PUBLIC/anon — ela DESPACHA e-mail a candidato real', () => {
  assert.match(
    SQL,
    /REVOKE ALL ON FUNCTION public\.selection_rescue_unbooked_invite\(uuid\) FROM PUBLIC, anon/,
    'sumiu o REVOKE: CREATE FUNCTION nasce com EXECUTE para PUBLIC, e esta RPC dispara e-mail.',
  );
  assert.doesNotMatch(
    SQL,
    /GRANT EXECUTE ON FUNCTION public\.selection_rescue_unbooked_invite\(uuid\) TO [^;]*\banon\b/,
    'a RPC de despacho de e-mail foi concedida a anon',
  );
});

test('A7: o MCP expõe rescue_unbooked, e ele aponta para a RPC do caso NÃO-AGENDADO', () => {
  assert.match(EF, /"rescue_unbooked"/,
    'action rescue_unbooked não está no enum de interview_manage — sem superfície, o operador volta '
    + 'ao SQL direto por service_role, que é o defeito inteiro da issue.');
  assert.match(
    EF,
    /case "rescue_unbooked":[\s\S]{0,900}?rpc = "selection_rescue_unbooked_invite"/,
    'rescue_unbooked não mapeia para selection_rescue_unbooked_invite',
  );
  // O par: 'rescue' continua sendo o caso AGENDADO-que-travou. Trocar as duas é o erro que o
  // arranque de 13/08 registrou (a issue fala de _unbooked_invite, e action='rescue' é a _stuck).
  assert.match(
    EF,
    /case "rescue":[\s\S]{0,300}?rpc = "selection_rescue_stuck_interview"/,
    "action='rescue' deixou de apontar para selection_rescue_stuck_interview",
  );
});

// ── B · o mecanismo está VIVO no banco, não só descrito no arquivo ───────────────────────────

test('B1: a coluna existe no banco e nenhuma linha está com o contador nulo', { skip: dbGated ? false : skipMsg }, async () => {
  // Se a migration não tiver sido aplicada, o PostgREST devolve 400 (coluna desconhecida) — é a
  // prova de existência que uma consulta de catálogo daria, sem depender do catálogo.
  const r = await rest('selection_applications?select=id,interview_manual_rescue_count&interview_manual_rescue_count=is.null');
  assert.equal(r.status, 200,
    `interview_manual_rescue_count não é consultável (HTTP ${r.status}) — a migration do #1586 `
    + 'provavelmente não foi aplicada ao banco.');
  assert.equal(r.body.length, 0,
    `${r.body.length} candidaturas com interview_manual_rescue_count NULO. Com NULL, o guard `
    + '`v_used >= v_cap` compara com nulo (nunca verdadeiro) e o cap manual não vale para elas.');
});

test('B2: o corpo VIVO ramifica o cap, e o ramo manual não toca o contador automático', { skip: dbGated ? false : skipMsg }, async () => {
  const { status, body } = await rest('rpc/_audit_function_source', {
    method: 'POST',
    body: JSON.stringify({ p_proname: 'selection_rescue_unbooked_invite' }),
  });
  assert.equal(status, 200, `_audit_function_source devia responder 200 (veio ${status})`);
  assert.ok(Array.isArray(body) && body.length > 0, 'a RPC não existe no banco');
  const src = body[0].prosrc;
  assert.match(src, /v_cap := 3;/, 'o corpo vivo não tem o cap manual de 3');
  assert.match(src, /interview_manual_rescue_count = interview_manual_rescue_count \+ 1/,
    'o corpo vivo não incrementa o contador manual');
  const iNotify = src.indexOf('notify_selection_cutoff_approved(p_application_id)');
  const iAuto = src.indexOf('interview_auto_rescue_count = interview_auto_rescue_count + 1');
  assert.ok(iNotify > -1 && iAuto > iNotify,
    'no corpo VIVO a mutação automática voltou a preceder o despacho — regressão da #1598');
});

test('B3: o invariante do cap automático continua em ZERO violações', { skip: dbGated ? false : skipMsg }, async () => {
  // A prova de que a separação funcionou: o caminho manual pode ser usado sem que a coluna vigiada
  // se mexa. Se este número sair de 0, alguém religou o incremento na coluna errada.
  const { status, body } = await rest('rpc/check_schema_invariants', { method: 'POST', body: '{}' });
  if (status !== 200) {
    // O catálogo de invariantes estoura statement_timeout sob contenção (#1742): um 504 aqui não é
    // prova de violação, e a camada A já fixa que o ramo manual usa a coluna própria.
    assert.ok([504, 500, 408].includes(status),
      `resposta inesperada de check_schema_invariants: HTTP ${status}`);
    return;
  }
  const inv = body.find((i) => i.invariant_name === 'AI_unbooked_rescue_cap_respected');
  assert.ok(inv, 'o invariante AI_unbooked_rescue_cap_respected sumiu do catálogo');
  assert.equal(Number(inv.violation_count), 0,
    'AI_unbooked_rescue_cap_respected saiu de 0: o caminho manual provavelmente voltou a '
    + 'incrementar interview_auto_rescue_count.');
});

test('B4: anon NÃO alcança a RPC — sonda direta na porta, não inspeção do grant', { skip: anonGated ? false : anonSkipMsg }, async () => {
  // Sonda na porta é mais forte que ler proacl: prova o que o PostgREST realmente responde.
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/selection_rescue_unbooked_invite`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: ANON_KEY,
      Authorization: `Bearer ${ANON_KEY}`,
    },
    body: JSON.stringify({ p_application_id: '00000000-0000-0000-0000-000000000000' }),
  });
  assert.notEqual(r.status, 200,
    `anon recebeu 200 de selection_rescue_unbooked_invite — uma RPC que DESPACHA e-mail a `
    + `candidato real ficou aberta ao público.`);
});
