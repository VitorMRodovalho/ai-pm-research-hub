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
 * Lote 2 (#1953): mais 8 RPCs, que chegam pelo CARD. Helper irmao `_can_write_board_item`, que
 * resolve o board do card e DELEGA -- a regra de escopo continua num lugar so.
 *
 * Migration: 20260823222639_c_onda_a_write_board_helper_na_convencao_can.sql
 *            20260824094756_c_write_board_lote2_repassa_recurso_via_card.sql (renomeia o helper do 20260823221554 para a convencao `_can_*`, que e como o guard do ADR-0011 reconhece autoridade V4)
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
const HELPER_ITEM = '_can_write_board_item@p_member_id uuid, p_item_id uuid';

/** As 6 RPCs do lote, com o argumento de board que cada uma passa ao helper. */
const H_BOARD = 'public._can_write_board';
const H_ITEM  = 'public._can_write_board_item';

const ALVOS = [
  // lote 1 (#1945): board ja em maos
  ['create_board_item',      'create_board_item@p_board_id uuid, p_title text, p_description text, p_assignee_id uuid, p_tags text[], p_due_date date, p_status text', 'p_board_id', H_BOARD],
  ['delete_board_item',      'delete_board_item@p_item_id uuid, p_reason text',                      'v_board_id', H_BOARD],
  ['duplicate_board_item',   'duplicate_board_item@p_item_id uuid, p_target_board_id uuid',          'v_board_id', H_BOARD],
  ['move_board_item',        'move_board_item@p_item_id uuid, p_new_status text, p_new_position integer, p_reason text', 'v_board_id', H_BOARD],
  ['update_card_forecast',   'update_card_forecast@p_board_item_id uuid, p_new_forecast date, p_justification text',     'v_board_id', H_BOARD],
  ['convert_action_to_card', 'convert_action_to_card@p_action_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_due_date date', 'p_board_id', H_BOARD],
  // lote 2 (#1953): chegam pelo card
  ['can_manage_card_checklist',  'can_manage_card_checklist@p_member_id uuid, p_card_id uuid', 'p_card_id', H_ITEM],
  ['delete_card_comment',        'delete_card_comment@p_comment_id uuid',                      'v_comment.board_item_id', H_ITEM],
  ['register_card_drive_file',   'register_card_drive_file@p_board_item_id uuid, p_drive_file_id text, p_drive_file_url text, p_filename text, p_mime_type text, p_size_bytes bigint, p_uploaded_via text', 'p_board_item_id', H_ITEM],
  ['update_card_during_meeting', 'update_card_during_meeting@p_card_id uuid, p_event_id uuid, p_new_status text, p_fields jsonb, p_note text', 'p_card_id', H_ITEM],
  ['create_card_comment',        'create_card_comment@p_board_item_id uuid, p_body text, p_parent_comment_id uuid, p_mentioned_member_ids uuid[]', 'p_board_item_id', H_ITEM],
  ['update_board_item',          'update_board_item@p_item_id uuid, p_fields jsonb',           'p_item_id', H_ITEM],
  // lote 2, mas com o board ja resolvido no corpo: usam o helper de BOARD
  ['create_mirror_card',      'create_mirror_card@p_source_item_id uuid, p_target_board_id uuid, p_target_status text, p_notes text', 'p_target_board_id', H_BOARD],
  ['complete_checklist_item', 'complete_checklist_item@p_checklist_item_id uuid, p_completed boolean',                                'v_card.board_id',   H_BOARD],
];

/**
 * Escapa metacaracteres ao transformar um identificador (`v_comment.board_item_id`) em regex.
 *
 * A primeira versao escapava SO o ponto (`/[.]/g`), e o CodeQL a marcou como
 * `js/incomplete-sanitization` de severidade alta: escapamento que nao trata a barra invertida e
 * incompleto por construcao. Aqui a entrada vem da tabela ALVOS deste mesmo arquivo, entao nao
 * havia exploracao possivel -- mas o padrao errado num arquivo de guard e o tipo de coisa que
 * alguem copia para um lugar onde a entrada NAO e literal. Escapa-se o conjunto inteiro.
 */
const rx = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

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

for (const [proname, chave, argBoard, helper] of ALVOS) {
  test(`#1945 A: ${proname} pergunta write_board COM o recurso (${argBoard})`, () => {
    const { body, file } = capturaMaisRecente(chave);
    const codigo = achatado(body);

    assert.match(
      codigo,
      new RegExp(`${rx(helper)}\\(\\s*[\\w.]+\\s*,\\s*${rx(argBoard)}\\s*\\)`, 'i'),
      `${file}: ${proname} nao passa ${argBoard} a ${helper}`,
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

test('#1953 A: o helper de CARD delega, em vez de reimplementar a regra', () => {
  const { body, file } = capturaMaisRecente(HELPER_ITEM);
  const codigo = achatado(body);

  assert.match(codigo, /public\._can_write_board\(/i,
    `${file}: o helper de card parou de delegar para _can_write_board`);
  assert.match(codigo, /FROM\s+public\.board_items\s+bi\s+WHERE\s+bi\.id\s*=\s*p_item_id/i,
    `${file}: o helper de card nao resolve o board a partir do item`);

  // SSOT: a regra de escopo vive num corpo so. Se estes aparecerem aqui, houve duplicacao, e os
  // dois helpers vao divergir com o tempo.
  assert.doesNotMatch(codigo, /can_org_by_member/i,
    `${file}: o helper de card reimplementou o ramo de escopo organization`);
  assert.doesNotMatch(codigo, /engagement_kind_permissions/i,
    `${file}: o helper de card foi ao catalogo por conta propria`);
});

// ── A' ───────────────────────────────────────────────────────────────────────────────────

for (const [proname, chave] of [[ '_can_write_board', HELPER ], [ '_can_write_board_item', HELPER_ITEM ], ...ALVOS.map(([p, c]) => [p, c])]) {
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

test('#1953 C: o helper de CARD discrimina — card PROPRIO sim, card ALHEIO nao', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // Amostra CONSTRUIDA, nao sorteada: a primeira versao deste teste pegou 8 cards por ordem de id,
  // nenhum caiu na tribo dos pesquisadores amostrados, e o helper devolveu false em todos --
  // indistinguivel de um gate inerte ao contrario. Aqui o par proprio/alheio e montado de proposito.
  const inits  = await tabela('initiatives?select=id,legacy_tribe_id&legacy_tribe_id=not.is.null&limit=200');
  const boards = await tabela('project_boards?select=id,initiative_id&is_active=eq.true&initiative_id=not.is.null&limit=200');
  const pesqs  = await tabela('members?select=id,tribe_id&is_active=eq.true&operational_role=eq.researcher&tribe_id=not.is.null&limit=40');

  const initPorTribo = new Map(inits.map(i => [i.legacy_tribe_id, i.id]));
  const boardPorInit = new Map();
  for (const b of boards) if (!boardPorInit.has(b.initiative_id)) boardPorInit.set(b.initiative_id, b.id);

  let exercidos = 0;
  for (const m of pesqs) {
    const initProprio = initPorTribo.get(m.tribe_id);
    const boardProprio = initProprio && boardPorInit.get(initProprio);
    const boardAlheio = boards.find(b => b.initiative_id !== initProprio)?.id;
    if (!boardProprio || !boardAlheio) continue;

    const [cp] = await tabela(`board_items?select=id&board_id=eq.${boardProprio}&limit=1`);
    const [ca] = await tabela(`board_items?select=id&board_id=eq.${boardAlheio}&limit=1`);
    if (!cp || !ca) continue;

    const proprio = await rpc('_can_write_board_item', { p_member_id: m.id, p_item_id: cp.id });
    const alheio  = await rpc('_can_write_board_item', { p_member_id: m.id, p_item_id: ca.id });

    assert.equal(proprio, true,
      `pesquisador NEGADO em card da propria tribo (${m.tribe_id}) — o estreitamento passou do ponto`);
    assert.equal(alheio, false,
      `pesquisador AUTORIZADO em card de outra iniciativa — o alcance cruzado voltou`);
    exercidos++;
    if (exercidos >= 3) break;
  }

  assert.ok(exercidos > 0,
    'nenhum par (card proprio, card alheio) pode ser montado: os seeds mudaram e este guard virou vacuo');

  // Controle negativo: card que nao existe resolve board NULL. Quem e escopado a iniciativa NAO
  // pode virar autorizado por um id invalido.
  const semOrg = pesqs[0];
  const inexistente = await rpc('_can_write_board_item', {
    p_member_id: semOrg.id, p_item_id: '00000000-0000-0000-0000-000000000000',
  });
  assert.equal(inexistente, false,
    'card inexistente autorizou quem so tem escopo de iniciativa — id invalido virou passe livre');
});
