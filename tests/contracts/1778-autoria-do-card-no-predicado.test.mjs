/**
 * #1778 — o dono do trabalho pode gerir as atividades do proprio card.
 *
 * A policy de escrita de `board_item_checklists` decide so por capacidade
 * (`rls_is_superadmin() OR rls_can('write') OR rls_can('write_board')`) e nunca olha o card. A UI
 * escrevia a tabela DIRETO (o unico acesso direto do dominio inteiro), entao a policy era o portao
 * — e o autor do proprio card era recusado. As RPCs `add/update/delete_checklist_item` ja tinham a
 * regra de recurso, com tres redacoes diferentes e sem a nocao de autor/contribuidor.
 *
 * Este patch: um predicado unico (`can_manage_card_checklist`), as quatro RPCs chamando, a UI
 * re-roteada para elas, e o fail-fast do MCP lendo o MESMO predicado (antes era
 * `canV4('write_board')`, mais estrito que a RPC que ele chama).
 *
 * Exercido em 15/08/2026 por impersonacao em transacao abortada, com uma pessoa ativa REAL,
 * nao superadmin, sem `write` e sem `write_board`, responsavel por um card:
 *
 *   | ato                                            | resultado |
 *   |------------------------------------------------|-----------|
 *   | INSERT direto na tabela (o caminho antigo da UI)| 42501 RLS |
 *   | mesma pessoa, mesma linha, pela RPC             | passa     |
 *   | quem nao tem vinculo com o card, pela RPC       | P0001     |
 *   | anon nas 5 RPCs + no predicado (PostgREST)      | HTTP 404  |
 *
 * E o buraco que o guard do #785 apontou no meio do caminho, tambem exercido: com write_board e
 * SEM enxergar a iniciativa confidencial, a RPC escrevia no card dela (SECDEF contorna a RLS).
 * Antes do gate: passava. Depois: P0001.
 *
 * A medicao da populacao mudou no meio do caminho e a licao fica registrada: contar "barrados" por
 * `can_by_member('write_board')` deu 3, mas a policy tem TRES ramos — 2 das 3 pessoas passavam por
 * `rls_is_superadmin()`. Barrado de verdade: 1.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const MIG = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260815133147_1778_autoria_do_card_vira_predicado_unico_do_checklist.sql'),
  'utf8',
);
// o predicado ganhou o gate do #785 numa migration seguinte, depois que o guard
// 785-secdef-reader-confidential-gate acusou (corretamente) o leitor SECDEF sem gate
const MIG_GATE = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260815140508_1778_o_predicado_do_checklist_carrega_o_gate_785.sql'),
  'utf8',
);
// #1932: `MIG` e `MIG_GATE` afirmam sobre o ATO daquelas migrations e seguem lendo os arquivos.
// Esta constante e a definicao VIGENTE do predicado, que e sobre o que o invariante de corpo fala:
// fixar o caminho faria este guard afirmar sobre um corpo que a producao nao executa mais.
// A chamada tem de ficar na forma canonica `latestFunctionCapture(ROOT, 'nome')`: o scanner do
// #1932 reconhece a divida como RESOLVIDA por regex, e `process.cwd()` no lugar de ROOT nao casa.
const ROOT_1778 = process.cwd();
const PREDICADO_VIGENTE = latestFunctionCapture(ROOT_1778, 'can_manage_card_checklist').block;

const CARD_DETAIL = readFileSync(resolve(process.cwd(), 'src/components/board/CardDetail.tsx'), 'utf8');
const EF = readFileSync(resolve(process.cwd(), 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

const RPCS = ['add_checklist_item', 'update_checklist_item', 'delete_checklist_item', 'assign_checklist_item'];

test('#1778 mig: o predicado olha o RECURSO, e nao so a capacidade', () => {
  assert.match(MIG, /CREATE OR REPLACE FUNCTION public\.can_manage_card_checklist\(p_member_id uuid, p_card_id uuid\)/i);
  // capacidade
  // #1953: a pergunta passou a levar o card. A forma sem recurso nao pode voltar.
  assert.match(PREDICADO_VIGENTE, /_can_write_board_item\(p_member_id, p_card_id\)/);
  assert.doesNotMatch(PREDICADO_VIGENTE, /can_by_member\(\s*p_member_id\s*,\s*'write_board'\s*\)/);
  // responsavel
  assert.match(MIG, /board_items bi\s+WHERE bi\.id = p_card_id AND bi\.assignee_id = p_member_id/);
  // autor/contribuidor — a nocao que faltava, e o motivo desta issue
  assert.match(MIG, /board_item_assignments ba[\s\S]{0,200}ba\.role IN \('author', 'contributor'\)/);
});

test('#1778/#785 mig: o predicado exige que o chamador ENXERGUE o card', () => {
  // SECURITY DEFINER contorna a RLS: sem esta linha, quem tem write_board e nao enxerga a
  // iniciativa confidencial escrevia atividade nos cards dela pela RPC (medido antes do patch).
  assert.match(MIG_GATE, /AND public\.rls_can_see_item\(p_card_id\)/);
  assert.match(MIG_GATE, /CREATE OR REPLACE FUNCTION public\.can_manage_card_checklist/i);
});

test('#1778 mig: as quatro RPCs chamam o predicado, e nenhuma reescreve a regra', () => {
  for (const fn of RPCS) {
    const bloco = MIG.slice(MIG.indexOf(`FUNCTION public.${fn}(`));
    const corpo = bloco.slice(0, bloco.indexOf('$function$;') + 11);
    assert.match(corpo, /can_manage_card_checklist\(/, `${fn} precisa chamar o predicado`);
    assert.doesNotMatch(
      corpo, /can_by_member\([^)]*'write_board'\)/,
      `${fn} nao pode reimplementar a regra: a duplicacao foi a causa de as tres redacoes divergirem`,
    );
  }
});

test('#1778 mig: complete_checklist_item fica de fora (a regra dele ja e mais larga)', () => {
  assert.doesNotMatch(MIG, /FUNCTION public\.complete_checklist_item\(/i);
});

test('#1778 mig: a deriva de EXECUTE para anon nas RPCs de escrita e revogada', () => {
  for (const fn of RPCS) {
    assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([^)]*\\) FROM PUBLIC, anon`, 'i'), `${fn} precisa revogar anon`);
  }
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.can_manage_card_checklist\(uuid, uuid\) FROM PUBLIC, anon/i);
  // o predicado e lido pelo MCP com o JWT do chamador
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.can_manage_card_checklist\(uuid, uuid\) TO authenticated, service_role/i);
});

test('#1778 UI: CardDetail nao escreve mais board_item_checklists direto', () => {
  const escritaDireta = /from\('board_item_checklists'\)\s*[\s\S]{0,80}?\.(insert|delete|update|upsert)\(/g;
  const achados = CARD_DETAIL.match(escritaDireta) || [];
  assert.deepEqual(achados, [], 'a escrita tem de passar pela RPC, que e onde a regra de autoria vive');
  // e continua LENDO direto, que e legitimo (a policy de leitura nao e o problema)
  assert.match(CARD_DETAIL, /from\('board_item_checklists'\)\s*[\s\S]{0,40}?\.select\(/);
});

test('#1778 UI: recusa do banco nao pode parecer sucesso na tela', () => {
  // TODAS as chamadas, nao a primeira: a migracao JSON→tabela tambem chama add_checklist_item,
  // e foi justamente ela que passou despercebida na primeira versao deste guard.
  for (const trecho of ['add_checklist_item', 'delete_checklist_item', 'complete_checklist_item']) {
    const indices = [];
    for (let i = CARD_DETAIL.indexOf(`rpc('${trecho}'`); i !== -1; i = CARD_DETAIL.indexOf(`rpc('${trecho}'`, i + 1)) indices.push(i);
    assert.ok(indices.length > 0, `${trecho} precisa ser chamada pela UI`);
    for (const i of indices) {
      const janela = CARD_DETAIL.slice(i, i + 700);
      // o erro tem de ser CAPTURADO e testado (o nome da variavel e livre: error, cErr, ...)
      assert.match(janela, /if \(\s*\w*(error|Err)\w*/i, `${trecho} (offset ${i}): o erro precisa ser tratado`);
      assert.match(janela, /toast\?\./, `${trecho} (offset ${i}): o erro precisa chegar ao usuario`);
      // e o caminho de sucesso tem de ser distinto do de recusa
      assert.match(janela, /(return;|break;|else)/, `${trecho} (offset ${i}): o estado local nao pode avancar apos recusa`);
    }
  }
});

test('#1778 MCP: o fail-fast do card_checklist le o predicado, nao write_board puro', () => {
  const i = EF.indexOf('"card_checklist"');
  const bloco = EF.slice(i, EF.indexOf('"card_write"', i));
  assert.match(bloco, /rpc\("can_manage_card_checklist"/, 'o semantico precisa ler o mesmo predicado do SQL');
  assert.doesNotMatch(
    bloco.slice(0, bloco.indexOf('const { data, error } = await sb.rpc(rpc!')),
    /canV4\(sb, member\.id, "write_board"\)/,
    'o canV4 puro tornava o MCP mais estrito que a RPC que ele chama',
  );
  assert.match(bloco, /gate_checked: params\.action === "complete" \? [^:]+: "rls_can_see_item \+ can_manage_card_checklist"/);
});

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1778 DB: o predicado concede a quem tem vinculo com o card e nega a quem nao tem', { skip: dbGated ? false : skipMsg }, async () => {
  const c = sb();
  // um card com responsavel: o responsavel passa
  const { data: cards, error: e1 } = await c.from('board_items').select('id, assignee_id').not('assignee_id', 'is', null).limit(1);
  assert.ifError(e1);
  assert.ok(cards?.length, 'precisa existir ao menos um card com responsavel');
  const { id: cardId, assignee_id: dono } = cards[0];

  const { data: podeDono, error: e2 } = await c.rpc('can_manage_card_checklist', { p_member_id: dono, p_card_id: cardId });
  assert.ifError(e2);
  assert.equal(podeDono, true, 'o responsavel pelo card precisa poder gerir as atividades dele');

  // nulos nao viram permissao
  const { data: podeNulo } = await c.rpc('can_manage_card_checklist', { p_member_id: null, p_card_id: cardId });
  assert.equal(podeNulo, false, 'member nulo nao pode');
  const { data: podeSemCard } = await c.rpc('can_manage_card_checklist', { p_member_id: dono, p_card_id: null });
  assert.equal(podeSemCard, false, 'card nulo nao pode');
});

test('#1778 DB: autor/contribuidor sem write_board passa a poder — e e por isso que a issue existe', { skip: dbGated ? false : skipMsg }, async () => {
  const c = sb();
  const { data: papeis, error } = await c
    .from('board_item_assignments')
    .select('item_id, member_id, role')
    .in('role', ['author', 'contributor'])
    .limit(200);
  assert.ifError(error);
  assert.ok(papeis?.length, 'precisa existir papel de autor/contribuidor para exercer a regra');

  // pega um par (autor, card) em que o autor NAO e o responsavel do card
  let alvo = null;
  for (const p of papeis) {
    const { data: card } = await c.from('board_items').select('assignee_id').eq('id', p.item_id).maybeSingle();
    if (card && card.assignee_id !== p.member_id) { alvo = p; break; }
  }
  assert.ok(alvo, 'precisa existir autor/contribuidor que nao seja o responsavel do card');

  const { data: pode, error: e2 } = await c.rpc('can_manage_card_checklist', { p_member_id: alvo.member_id, p_card_id: alvo.item_id });
  assert.ifError(e2);
  assert.equal(pode, true, 'autor/contribuidor precisa poder gerir as atividades daquele card');
});

test('#1778 DB: ninguem com trabalho atribuido continua sem caminho para registra-lo', { skip: dbGated ? false : skipMsg }, async () => {
  const c = sb();
  // responsaveis de cards vivos: o predicado tem de conceder a TODOS, por vinculo com o recurso
  const { data: cards, error } = await c.from('board_items').select('id, assignee_id, status').not('assignee_id', 'is', null).neq('status', 'archived').limit(150);
  assert.ifError(error);
  assert.ok(cards?.length);
  const amostra = cards.slice(0, 25);
  const negados = [];
  for (const card of amostra) {
    // o predicado agora carrega o gate do #785, e service_role (sem auth.uid()) nao enxerga
    // card de iniciativa confidencial — esse caso e materia do #1784, nao deste guard
    const { data: visivel } = await c.rpc('rls_can_see_item', { p_item_id: card.id });
    if (visivel !== true) continue;
    const { data: pode } = await c.rpc('can_manage_card_checklist', { p_member_id: card.assignee_id, p_card_id: card.id });
    if (pode !== true) negados.push(card.id);
  }
  assert.deepEqual(negados, [], 'responsavel por card vivo nao pode ficar sem caminho para registrar o proprio trabalho');
});
