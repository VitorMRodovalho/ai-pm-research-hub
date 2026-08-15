/**
 * #1779 — o log de ciclo de vida e as tarefas do board deixam de compartilhar nome.
 *
 * `get_board_activities` estava sobrecarregada com dois sentidos OPOSTOS:
 *
 *   (p_board_id, p_limit)                          o LOG de ciclo de vida
 *   (p_board_id, p_assignee, p_status, p_period)   as TAREFAS (atividades dos cards)
 *
 * O MCP chamava a primeira. A segunda so era alcancavel pelo frontend, entao nao havia porta
 * agregada de tarefas no semantico: para saber quem responde por que, e ate quando, era card a card.
 * A Fase 1 do #1780 varreu `pg_proc` e confirmou que era caso unico no schema.
 *
 * Este contrato trava as tres coisas que a correcao entregou:
 *
 *   1. o nome volta a significar UMA coisa (a contagem em pg_proc e 1)
 *   2. o log tem nome proprio, e a EF o chama por ele
 *   3. existe porta agregada de tarefas no semantico (board_overview scope='tasks')
 *
 * A contagem e o coracao do teste: foi a duplicidade, e nao a assinatura em si, que fez o MCP pegar
 * o log quando queria as tarefas. Uma resolucao silenciosa de sobrecarga nao levanta erro nenhum.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const EF = readFileSync(resolve(process.cwd(), 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');
const MANIFEST = JSON.parse(readFileSync(resolve(process.cwd(), 'src/lib/mcp-manifest.json'), 'utf8'));

test('#1779 EF: nenhuma chamada de RPC ao nome antigo com a assinatura do log', () => {
  // a assinatura do log e (p_board_id, p_limit); se sobrar uma chamada assim ao nome velho, ela
  // quebra no momento em que a migration que apaga a assinatura colidente rodar.
  const chamadasLog = [...EF.matchAll(/rpc\(\s*"get_board_activities"\s*,\s*\{[^}]*p_limit/g)];
  assert.equal(chamadasLog.length, 0, 'a EF nao pode mais chamar get_board_activities com p_limit');
  assert.match(EF, /rpc\(\s*"get_board_lifecycle_log"\s*,\s*\{[^}]*p_board_id[^}]*p_limit/,
    'a EF precisa chamar o log pelo nome proprio');
});

test('#1779 EF: a chamada que sobra ao nome antigo e a das TAREFAS, com os quatro filtros', () => {
  const m = EF.match(/rpc\(\s*"get_board_activities"\s*,\s*\{[\s\S]{0,400}?\}\s*\)/);
  assert.ok(m, 'a porta de tarefas precisa existir na EF');
  for (const p of ['p_board_id', 'p_assignee_filter', 'p_status_filter', 'p_period_filter']) {
    assert.match(m[0], new RegExp(p), `a chamada de tarefas precisa passar ${p}`);
  }
});

test('#1779 EF: board_overview ganhou scope tasks, dentro de uma tool que ja existia', () => {
  // acao nova em tool existente, de proposito: o conector cacheia tools/list, e uma tool NOVA so
  // apareceria depois de recarregar o catalogo.
  assert.match(EF, /scope:\s*z\.enum\(\["list", "board", "tasks", "initiative"\]\)/,
    'scope precisa aceitar tasks');
  assert.match(EF, /params\.scope === "tasks"/, 'board_overview precisa tratar scope=tasks');
  // o recorte precisa ser gateado como os irmaos (#785), nao so pela RPC
  const bloco = EF.slice(EF.indexOf('params.scope === "tasks"'));
  assert.match(bloco.slice(0, 1200), /canSee\(sb, "board", params\.board_id!\)/,
    'scope=tasks precisa do fail-fast de confidencial, como scope=board');
});

test('#1779 EF: o vocabulario da tool de board separa evento de ciclo de vida de atividade', () => {
  assert.match(EF, /recent_lifecycle_events:/, 'a chave do log no envelope de scope=board');
  assert.doesNotMatch(EF, /recent_activities:/, '"atividade" nao pode mais nomear o log');
});

test('#1779 manifesto: as duas descricoes apontam uma para a outra', () => {
  const tool = n => MANIFEST.tools.find(t => t.name === n);
  assert.match(tool('get_board_activities').description, /LIFECYCLE/i);
  assert.match(tool('get_board_activities').description, /scope='tasks'/);
  assert.match(tool('board_overview').description, /'tasks'/);
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1779 DB: get_board_activities voltou a ter UMA assinatura, e e a das tarefas', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
  assert.ifError(error);
  const homonimas = data.filter(f => f.proname === 'get_board_activities');
  assert.equal(homonimas.length, 1, `get_board_activities precisa significar UMA coisa (achadas ${homonimas.length})`);
  assert.match(homonimas[0].identity_args,
    /p_board_id uuid, p_assignee_filter uuid, p_status_filter text, p_period_filter text/,
    'a que fica e a das tarefas (os quatro filtros), nao a do log');
  const log = data.filter(f => f.proname === 'get_board_lifecycle_log');
  assert.equal(log.length, 1, 'o log precisa existir com nome proprio, e uma vez so');
});

test('#1779 DB: os dois envelopes sao distinguiveis, e o do log fala de evento', { skip: dbGated ? false : skipMsg }, async () => {
  // Derivado do catalogo, nao de uma chamada: as duas funcoes resolvem o chamador por auth.uid(),
  // e um cliente service_role sem JWT recebe {error: 'Not authenticated'} das DUAS. Uma asserção
  // sobre a chamada passaria a medir a ausencia de sessao, nao a forma do envelope.
  const c = sb();
  const { data: log, error: e1 } = await c.rpc('_audit_function_source', { p_proname: 'get_board_lifecycle_log' });
  assert.ifError(e1);
  assert.equal(log.length, 1, 'o log precisa existir uma vez so');
  assert.match(log[0].prosrc, /jsonb_build_object\(\s*'events'/, "o log devolve {events, count}");
  assert.doesNotMatch(log[0].prosrc, /'activities'/, '"activities" e das tarefas, nao do log');
  assert.equal(log[0].is_secdef, true, 'o log le linhas de varios boards: SECURITY DEFINER com gate dentro');
  assert.match(log[0].prosrc, /rls_can_see_board/, 'o gate do #785 precisa continuar dentro do corpo');

  const { data: tarefas, error: e2 } = await c.rpc('_audit_function_source', { p_proname: 'get_board_activities' });
  assert.ifError(e2);
  assert.equal(tarefas.length, 1, 'get_board_activities precisa significar UMA coisa');
  for (const k of ['activities', 'total', 'completed', 'pending']) {
    assert.match(tarefas[0].prosrc, new RegExp(`'${k}'`), `o envelope de tarefas precisa da chave ${k}`);
  }
  assert.match(tarefas[0].prosrc, /rls_can_see_board/, 'as tarefas mantem o gate do #785');
});

test('#1779 DB: o log nao e publicado para anon, e as tarefas tambem nao', { skip: dbGated ? false : skipMsg }, async () => {
  // CREATE FUNCTION nasce com EXECUTE para PUBLIC, e o log carrega nome de ator.
  const { data, error } = await sb().rpc('_audit_function_execute_acl', {
    p_names: ['get_board_lifecycle_log', 'get_board_activities'],
  });
  assert.ifError(error);
  assert.ok(data.length >= 2, 'as duas funcoes precisam aparecer na ACL');
  for (const f of data) {
    assert.equal(f.anon_exec, false, `${f.proname}(${f.identity_args}) nao pode ser executavel por anon`);
    assert.equal(f.authenticated_exec, true, `${f.proname}(${f.identity_args}) precisa servir o membro logado`);
  }
});
