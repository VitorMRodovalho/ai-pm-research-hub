/**
 * Contract: #1945 — `write_board` e perguntado COM o board, nao no vacuo.
 *
 * A classe. Uma pergunta de capacidade sem o recurso concreto nao distingue o board proprio do
 * alheio: um grant de escopo `initiative` casa qualquer iniciativa. E a mesma forma que o #1728
 * fechou em presenca e o #1383 em evento, agora em `write_board`.
 *
 * A correcao e `_can_write_board(member, board)`, no molde do `_manage_event_scope_ok`:
 * escopo `organization`/`global` vale para qualquer board (desenho dos seeds), escopo `initiative`
 * vale so para a iniciativa DAQUELE board. Seis RPCs passam a usa-lo.
 *
 * ⚠️ `board_write_authority` NAO serve como substituto: ele e mais amplo (lider de tribo, comms,
 * lider de iniciativa) e trocar um pelo outro ALARGARIA a autoridade das 6. O guard abaixo afirma
 * o helper estreito, de proposito.
 *
 * Camadas: A estatica sobre a captura DERIVADA, com a INVERSA de cada afirmacao (a forma sem
 * recurso nao pode sobrar, senao um segundo ramo reabre o alcance cruzado com este teste verde);
 * A' md5 do corpo vivo contra a captura, para as 7 funcoes; C o helper DISCRIMINA no vivo — uma
 * camada estatica nao percebe um helper que passou a devolver true para tudo, que e exatamente
 * como o alcance cruzado voltaria sem tocar em nenhuma das 6.
 *
 * Migration: 20260823222639_c_onda_a_write_board_helper_na_convencao_can.sql (renomeia o helper do 20260823221554 para a convencao `_can_*`, que e como o guard do ADR-0011 reconhece autoridade V4)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody, md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

const HELPER = '_can_write_board@p_member_id uuid, p_board_id uuid';

/** As 6 RPCs do lote, com o argumento de board que cada uma passa ao helper. */
const ALVOS = [
  ['create_board_item',      'create_board_item@p_board_id uuid, p_title text, p_description text, p_assignee_id uuid, p_tags text[], p_due_date date, p_status text', 'p_board_id'],
  ['delete_board_item',      'delete_board_item@p_item_id uuid, p_reason text',                      'v_board_id'],
  ['duplicate_board_item',   'duplicate_board_item@p_item_id uuid, p_target_board_id uuid',          'v_board_id'],
  ['move_board_item',        'move_board_item@p_item_id uuid, p_new_status text, p_new_position integer, p_reason text', 'v_board_id'],
  ['update_card_forecast',   'update_card_forecast@p_board_item_id uuid, p_new_forecast date, p_justification text',     'v_board_id'],
  ['convert_action_to_card', 'convert_action_to_card@p_action_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_due_date date', 'p_board_id'],
];

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function capturaMaisRecente(chave) {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(chave);
  assert.ok(cap, `sem captura de migration para ${chave}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === chave);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${chave}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b). */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

const headers = { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` };
async function rpc(nome, corpo) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, { method: 'POST', headers, body: JSON.stringify(corpo ?? {}) });
  assert.ok(res.ok, `${nome} devia responder 2xx (veio ${res.status})`);
  return res.json();
}
async function tabela(caminho) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${caminho}`, { headers });
  assert.ok(res.ok, `leitura de ${caminho} devia responder 2xx (veio ${res.status})`);
  return res.json();
}

// ── A ────────────────────────────────────────────────────────────────────────────────────

for (const [proname, chave, argBoard] of ALVOS) {
  test(`#1945 A: ${proname} pergunta write_board COM o board (${argBoard})`, () => {
    const { body, file } = capturaMaisRecente(chave);
    const codigo = achatado(body);

    assert.match(
      codigo,
      new RegExp(`public\\._can_write_board\\(\\s*[\\w.]+\\s*,\\s*${argBoard}\\s*\\)`, 'i'),
      `${file}: ${proname} nao passa ${argBoard} ao helper escopado`,
    );

    // A INVERSA, que e o defeito. Nao basta a forma nova ESTAR la: a forma sem recurso nao pode
    // sobrar, porque ela e permissiva e um segundo ramo com ela devolve o alcance cruzado inteiro
    // com este teste verde.
    assert.doesNotMatch(
      codigo,
      /can_by_member\s*\(\s*[\w.]+\s*,\s*'write_board'\s*(?:::\s*text\s*)?\)/i,
      `${file}: ${proname} voltou a perguntar write_board sem passar o board`,
    );
  });
}

test('#1945 A: o helper é o ESTREITO, não board_write_authority', () => {
  const { body, file } = capturaMaisRecente(HELPER);
  const codigo = achatado(body);

  assert.match(codigo, /can_org_by_member\(\s*p_member_id\s*,\s*'write_board'\s*\)/i,
    `${file}: o helper perdeu o ramo de escopo organization — quem tem write_board global para de escrever`);
  assert.match(codigo, /can_by_member\(\s*p_member_id\s*,\s*'write_board'\s*,\s*'initiative'\s*,\s*pb\.initiative_id\s*\)/i,
    `${file}: o helper perdeu o ramo escopado à iniciativa DO board`);

  // p_resource_type nao pode ser NULL nem 'tribe': com NULL o ramo legado casta o UUID para
  // integer e ESTOURA, justamente no caminho de negacao.
  assert.doesNotMatch(codigo, /can_by_member\(\s*p_member_id\s*,\s*'write_board'\s*,\s*(NULL|'tribe')/i,
    `${file}: resource_type NULL ou 'tribe' faz can() lançar em vez de responder false`);

  // O helper NAO pode virar board_write_authority: aquele e mais amplo e alargaria as 6.
  assert.doesNotMatch(codigo, /board_write_authority/i,
    `${file}: o helper passou a delegar para board_write_authority, que é MAIS amplo que o ramo substituído`);
});

// ── A' ───────────────────────────────────────────────────────────────────────────────────

for (const [proname, chave] of [[ '_can_write_board', HELPER ], ...ALVOS.map(([p, c]) => [p, c])]) {
  test(`#1945 A': o corpo VIVO de ${proname} == a captura mais recente`, {
    skip: dbGated ? false : skipMsg,
  }, async () => {
    const { bodyHash, file } = capturaMaisRecente(chave);
    const linhas = await rpc('_audit_function_source', { p_proname: proname });
    assert.equal(linhas.length, 1, `esperado exatamente 1 ${proname} em pg_proc`);
    assert.equal(md5(normalizeBody(linhas[0].prosrc)), bodyHash,
      `corpo vivo de ${proname} divergente de ${file}: a mudança está só num dos dois lados`);
  });
}

// ── C ────────────────────────────────────────────────────────────────────────────────────

test('#1945 C: o helper DISCRIMINA no vivo — próprio board sim, board alheio não', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // Uma camada estatica fica verde se o helper passar a devolver true para tudo, que e como o
  // alcance cruzado voltaria sem tocar em nenhuma das 6 RPCs. Aqui a pergunta e outra: ele ainda
  // separa o board proprio do alheio?
  const boards = await tabela('project_boards?select=id,initiative_id&is_active=eq.true&initiative_id=not.is.null&order=id&limit=8');
  assert.ok(boards.length >= 2, 'sem dois boards de iniciativa para exercer o helper');
  // Amostra pequena de proposito: a suite roda na faixa serializada do banco (#1908), e esta
  // camada custa uma chamada por par. 5 x 8 basta para provar que o helper separa.

  const pesquisadores = await tabela('members?select=id,tribe_id&is_active=eq.true&operational_role=eq.researcher&limit=5');
  assert.ok(pesquisadores.length > 0, 'sem pesquisador ativo para exercer o helper');

  let discriminou = 0;
  for (const m of pesquisadores) {
    const veredito = [];
    for (const b of boards) {
      veredito.push(await rpc('_can_write_board', { p_member_id: m.id, p_board_id: b.id }));
    }
    const sim = veredito.filter(Boolean).length;
    // O que NAO pode acontecer: passar em TODOS os boards. Isso e o gate inerte.
    assert.notEqual(sim, boards.length,
      `helper devolveu true em TODOS os ${boards.length} boards para um pesquisador — gate inerte, o alcance cruzado voltou`);
    if (sim > 0 && sim < boards.length) discriminou++;
  }

  assert.ok(discriminou > 0,
    'nenhum pesquisador passou em ALGUM board e falhou em outro: ou os seeds mudaram, ou o helper virou constante');
});

test('#1945 C: quem tem write_board de escopo organization passa em qualquer board', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // A inversa do teste acima: estreitar nao pode ter derrubado quem tem autoridade global.
  const boards = await tabela('project_boards?select=id&is_active=eq.true&order=id&limit=5');
  const gp = await tabela('members?select=id&is_active=eq.true&operational_role=eq.manager&limit=1');
  assert.equal(gp.length, 1, 'sem GP ativo para exercer o controle positivo');

  for (const b of boards) {
    const v = await rpc('_can_write_board', { p_member_id: gp[0].id, p_board_id: b.id });
    assert.equal(v, true, `GP foi NEGADO no board ${b.id}: o estreitamento passou do ponto`);
  }
});

test('#1945 C: o helper não executa como anon', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  const linhas = await rpc('_audit_function_execute_acl', { p_names: ['_can_write_board'] });
  assert.equal(linhas.length, 1, 'esperado o helper no audit de ACL');
  assert.equal(linhas[0].anon_exec, false, 'helper de autoridade executável por anon');
  assert.equal(linhas[0].authenticated_exec, true, 'helper sem EXECUTE para authenticated: as 6 RPCs quebram');
});
