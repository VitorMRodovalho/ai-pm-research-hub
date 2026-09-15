import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

/**
 * #2292 — o credito de presenca tinha DUAS implementacoes da mesma regra, e elas
 * divergiam em cinco pontos. A que o cron chama (a EF) de-duplicava por id de LINHA;
 * a que declarava a regra (a RPC) checava os dois formatos de ref_id e gravava o
 * antigo. Rodar as duas produz credito em dobro POR CONSTRUCAO.
 *
 * O que a medicao de 2026-09-15 mostrou, e que e o motivo de este guard existir:
 *   - 224 pares duplicados, 2.240 pontos, 40 pessoas;
 *   - 100% deles com a MESMA forma (1 linha de formato evento + 1 de formato presenca);
 *   - ZERO pares de outra forma, ZERO grupos de 3, e ZERO linhas de formato evento
 *     que NAO fossem duplicata. Toda linha que a RPC escreveu na vida era a segunda
 *     copia de um credito que a EF ja tinha dado.
 *
 * O guard tem duas metades de proposito. A metade de DADO reprova se a duplicata
 * voltar; a metade ESTATICA reprova se alguem reintroduzir a segunda implementacao,
 * que e a causa. Sem a segunda, o defeito so seria notado depois de ja ter contaminado
 * o placar de novo.
 */

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

async function corpo(nome) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: nome });
  assert.ifError(error);
  assert.equal(data.length, 1, `${nome} precisa existir, e uma vez so (achadas ${data.length})`);
  return data[0];
}

test('#2292 nenhum credito de presenca duplicado por (pessoa, evento)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_attendance_xp_duplicates');
  assert.ifError(error);
  const m = Array.isArray(data) ? data[0] : data;

  // CONTROLE POSITIVO, na mesma leitura. Um "0 duplicatas" so significa saude se houver
  // linha para duplicar: lido de uma categoria vazia, o mesmo zero seria vacuidade.
  assert.ok(m.total_attendance_points > 0,
    'sem linhas de categoria attendance — o zero abaixo passaria por vacuidade, nao por saude');

  assert.equal(m.duplicated_pairs, 0,
    `${m.duplicated_pairs} pares (pessoa, evento) com mais de um credito, ${m.duplicated_points} pontos em dobro`);
});

test('#2292 a RPC delega e nao reimplementa a regra', { skip: dbGated ? false : skipMsg }, async () => {
  const f = await corpo('sync_attendance_points');

  assert.match(f.prosrc, /_sync_attendance_points_worker/,
    'sync_attendance_points precisa DELEGAR ao worker');
  assert.doesNotMatch(f.prosrc, /INSERT\s+INTO\s+(public\.)?gamification_points/i,
    'sync_attendance_points voltou a escrever credito por conta propria — e essa a segunda ' +
    'implementacao que produziu as 224 duplicatas');
});

test('#2292 o worker existe, e de-duplica por evento e nao por id de linha', { skip: dbGated ? false : skipMsg }, async () => {
  const f = await corpo('_sync_attendance_points_worker');

  assert.equal(f.is_secdef, true, 'o worker roda sem sessao e precisa ser SECURITY DEFINER');
  // O COALESCE e o que faz os DOIS formatos de ref_id se enxergarem. Sem ele, a
  // de-duplicacao volta a ser por id de linha, que e o defeito.
  assert.match(f.prosrc, /COALESCE\s*\(\s*a2\.event_id\s*,\s*gp\.ref_id\s*\)/i,
    'a de-duplicacao precisa resolver o ref_id polimorfico para o EVENTO');
  assert.match(f.prosrc, /gamification_rules/,
    'os pontos vem do catalogo, nao de constante no codigo');
  assert.match(f.prosrc, /status\s+IS\s+NULL\s+OR\s+e\.status\s*<>\s*'cancelled'/i,
    'evento cancelado nao gera credito — o filtro que a EF nunca teve');
});

test('#2292 cancelar reuniao PRESERVA o credito, repontando antes de apagar', { skip: dbGated ? false : skipMsg }, async () => {
  const f = await corpo('_cleanup_cancelled_event_attendance');

  const iUpdate = f.prosrc.search(/UPDATE\s+public\.gamification_points/i);
  const iDelete = f.prosrc.search(/DELETE\s+FROM\s+public\.attendance/i);

  assert.ok(iUpdate >= 0, 'o credito precisa ser repontado para o evento antes do cancelamento levar a presenca');
  assert.ok(iDelete >= 0, 'o trigger continua apagando a presenca do evento cancelado');
  // ORDEM: depois do DELETE nao existe mais o vinculo credito->evento, que so passa pela
  // linha de presenca. Um repoint depois do delete nao acha nada e falha em silencio.
  assert.ok(iUpdate < iDelete,
    'o repoint precisa vir ANTES do DELETE — depois dele o vinculo credito->evento ja nao existe');
});

test('#2292 limpar presenca ESTORNA o credito, e nunca o apaga', { skip: dbGated ? false : skipMsg }, async () => {
  const f = await corpo('clear_member_attendance');

  // O ledger e append-only (#1087 onda 3). A primeira versao deste conserto APAGAVA a linha —
  // que e a direcao que a propria issue #2292 propunha — e o guard
  // 1087-wave3-ledger-append-only reprovou. O estorno da o mesmo efeito no placar e mantem a
  // historia, que e o motivo de a invariante existir.
  assert.doesNotMatch(f.prosrc, /DELETE\s+FROM\s+public\.gamification_points/i,
    'gamification_points e ledger append-only: estorne, nao apague (o carve-out de DELETE e so Art. 18 da LGPD)');
  assert.match(f.prosrc, /INSERT\s+INTO\s+public\.gamification_points/i,
    'o estorno e uma linha NOVA de pontos negativos, no molde de revoke_agenda_block_xp');
  assert.match(f.prosrc, /-\s*s\.pts/,
    'a linha de estorno precisa carregar o saldo NEGADO, nao um valor fixo');
  // Os dois formatos historicos de ref_id precisam entrar no saldo, ou o estorno deixa de
  // fora justamente a linha que a de-duplicacao nao consegue resolver.
  assert.match(f.prosrc, /COALESCE\s*\(\s*a2\.event_id\s*,\s*gp\.ref_id\s*\)/i,
    'o saldo precisa resolver os DOIS formatos de ref_id');
  // A presenca em si continua sendo apagada: e a tabela de presenca que afirma o fato.
  assert.match(f.prosrc, /DELETE\s+FROM\s+public\.attendance/i,
    'a linha de presenca continua sendo removida');
});

test('#2292 a de-duplicacao olha o SALDO, nao a existencia de linha', { skip: dbGated ? false : skipMsg }, async () => {
  const f = await corpo('_sync_attendance_points_worker');

  // Com o ledger append-only, um credito estornado deixa +N e -N. Um EXISTS leria "ja tem
  // credito" e recusaria PARA SEMPRE re-creditar alguem cuja presenca foi removida por engano
  // e depois re-adicionada. O SUM > 0 e o que torna o estorno reversivel.
  assert.match(f.prosrc, /HAVING\s+SUM\s*\(\s*gp\.points\s*\)\s*>\s*0/i,
    'a de-duplicacao precisa ser por SALDO positivo, senao o estorno vira porta de mao unica');
});

test('#2292 a EF nao carrega uma segunda copia da regra', { skip: false }, async () => {
  const { readFileSync, existsSync } = await import('node:fs');
  const src = readFileSync('supabase/functions/sync-attendance-points/index.ts', 'utf-8');

  assert.match(src, /_sync_attendance_points_worker/, 'a EF precisa delegar ao worker');
  assert.doesNotMatch(src, /from\('gamification_points'\)/,
    'a EF voltou a falar com gamification_points direto — e essa a segunda implementacao');
  assert.ok(!existsSync('supabase/functions/_shared/attendance-xp.ts'),
    'POINTS_PER_ATTENDANCE era a segunda fonte do valor; o catalogo gamification_rules e a primeira');
});
