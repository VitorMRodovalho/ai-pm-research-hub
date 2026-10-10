/**
 * #2621 item 1: o MCP envia o card a curadoria, e quem decide quem pode enviar e a RPC.
 *
 * Medido em 08/10/2026: um lider de tribo pediu ao seu agente que enviasse um artigo a curadoria; o MCP
 * nao tinha rota de envio, o agente moveu o card para a coluna 'review' e o item nao entrou na fila.
 * 13 dos 14 lideres de tribo ativos nao tem `participate_in_governance_review`, e
 * `submit_for_curation` aceita `tribe_leader` (ADR-0041 "Path Y"). Um `canV4` de governanca no
 * TypeScript antes da chamada barraria justamente quem envia, e ficaria verde em todo teste feito
 * com o GP.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o helper chama a RPC e repassa o erro dela, sem portao de autoridade proprio;
 *   B. a ferramenta crua so faz o portao de VISIBILIDADE (#785) antes, nunca um canV4;
 *   C. o card_write leva a acao ao mesmo helper e a tira do portao write_board;
 *   D. o estado devolvido diz QUANTOS pareceristas, nunca quem (#2227);
 *   E. a ferramenta crua esta no /actions (fica depois do corte de 256 do /mcp);
 *   F. recusa da regra (P0001) e falha tecnica viram codigos diferentes do contrato do envelope;
 *   G. card_write action='move' para 'review' com o card em rascunho avisa que isso NAO envia.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SRC = maskJsComments(readFileSync(resolve(process.cwd(), 'supabase/functions/nucleo-mcp/index.ts'), 'utf8'));

function slice(startMarker, endMarker, label) {
  const start = SRC.indexOf(startMarker);
  assert.ok(start !== -1, `${label}: inicio ausente`);
  const end = SRC.indexOf(endMarker, start + startMarker.length);
  assert.ok(end !== -1, `${label}: fim ausente`);
  return SRC.slice(start, end + endMarker.length);
}

const helper = () => slice('async function submitForCurationAndReadState(', '\n}\n', 'helper');
const rawTool = () => slice('mcp.tool("submit_for_curation"', '\n  });\n', 'ferramenta crua');
const cardBranch = () => slice('if (params.action === "submit_for_curation") {', '\n      }\n', 'ramo do card_write');

test('A. o helper chama a RPC e devolve o erro dela como esta', () => {
  const h = helper();
  assert.match(h,
    /const \{ error \} = await sb\.rpc\("submit_for_curation", \{ p_item_id: itemId \}\);\s+if \(error\) return \{ error: error\.message, errorCode: curationSubmitErrorCode\(error\), warnings: \[\] \};/,
    'a recusa da RPC volta com a mensagem dela');
  assert.doesNotMatch(h, /canV4\(/, 'o helper nao tem portao de autoridade proprio');
});

test('B. a ferramenta crua so checa visibilidade antes de chamar, nunca canV4', () => {
  const t = rawTool();
  const call = t.indexOf('submitForCurationAndReadState(sb, params.item_id)');
  assert.ok(call !== -1, 'a ferramenta crua chama o helper');
  const before = t.slice(0, call);
  assert.doesNotMatch(before, /canV4\(/, 'nenhum canV4 antes da chamada (barraria os lideres de tribo)');
  assert.match(before,
    /if \(!\(await canSee\(sb, "item", params\.item_id\)\)\) \{[^}]*return err\(/,
    'card invisivel (confidencial) e recusado antes de chamar');
  assert.match(t.slice(call),
    /if \(res\.error\) \{ await logUsage\([^\n]*return err\(tgt\?\.saved \? `[^`]*` : res\.error\); \}/,
    'o erro da RPC e repassado ao agente (com a nota do destino gravado, #2621)');
});

test('C. o card_write leva a acao ao helper e a tira do portao write_board', () => {
  assert.match(SRC,
    /action: z\.enum\(\[[^\]]*"submit_for_curation"[^\]]*\]\)\.describe\("Card operation\."\)/,
    'a acao existe no enum do card_write');
  assert.match(SRC,
    /const RPC_DECIDES = new Set\(\[\.\.\.ROLE_ACTIONS, "submit_for_curation", "set_curation_target"\]\);\s+if \(!RPC_DECIDES\.has\(params\.action\) && !\(await canV4\(sb, member\.id, "write_board"\)\)\)/,
    'submit_for_curation nao passa pelo canV4(write_board)');
  const b = cardBranch();
  assert.match(b, /^if \(params\.action === "submit_for_curation"\) \{\s+const tgt = await setCurationTargetIfGiven\(sb, params\.card_id, params\.target_venue, params\.target_date\);\s+if \(tgt\?\.error\) \{[^}]*?return ok\(buildSemanticError\([^}]*\}\)\);\s+\}\s+const res = await submitForCurationAndReadState\(sb, params\.card_id\);/,
    'o ramo chama o helper (depois de gravar o prazo do destino, #2621)');
  assert.doesNotMatch(b, /canV4\(/, 'o ramo nao tem portao de autoridade proprio');
  assert.match(b, /if \(res\.error\) \{[\s\S]*?buildSemanticError\(\{ tool: "card_write", semantic_domain: dom, code: res\.errorCode!, message: res\.error,/,
    'a recusa da RPC volta com a mensagem e o codigo classificado');
  const gate = SRC.indexOf('if (!(await canSee(sb, gateKind, resourceId)))');
  assert.ok(gate !== -1 && gate < SRC.indexOf('if (params.action === "submit_for_curation") {'),
    'o portao de visibilidade do card_write vem antes do ramo');
  // o ramo vem antes do switch generico, que nao conhece a acao
  assert.ok(SRC.indexOf('if (params.action === "submit_for_curation") {') < SRC.indexOf('case "create": {\n          const tags = params.tags'),
    'o ramo intercepta antes do switch');
});

test('D. o estado devolvido diz quantos pareceristas, nunca quem', () => {
  const h = helper();
  assert.match(h,
    /sb\.from\("curation_reviewer_assignments"\)\.select\("review_round"\)\.eq\("board_item_id", itemId\)\.is\("released_at", null\)/,
    'so designacoes abertas, sem a coluna do parecerista');
  assert.doesNotMatch(h, /reviewer_id/, 'nenhuma identidade de parecerista');
  assert.match(h,
    /sb\.from\("board_items"\)\.select\("title, curation_status, curation_due_at"\)\.eq\("id", itemId\)/,
    'o card e relido depois do envio');
  assert.match(h, /curation_status: itemRes\.data\?\.curation_status \?\? null,[\s\S]*?reviewers_assigned: assignRes\.error \? null : current\.length,/,
    'status e contagem vao no estado; leitura falha = contagem desconhecida, nao zero');
});

test('E. a ferramenta crua esta no /actions', () => {
  const list = slice('const ACTIONS_ALLOWLIST: Set<string> = new Set([', ']);', 'ACTIONS_ALLOWLIST');
  assert.match(list, /^\s*"submit_for_curation",$/m);
});

test('F. recusa da regra (P0001) e falha tecnica viram codigos diferentes', () => {
  const f = slice('function curationSubmitErrorCode(', '\n}\n', 'classificador');
  assert.match(f, /if \(error\.code !== "P0001"\) return "internal_error";/, 'so RAISE da RPC e recusa da regra');
  assert.match(f, /if \(\/\^Requires \/\.test\(error\.message\)\) return "unauthorized";/, 'falta de autoridade');
  assert.match(f, /if \(\/not found\/i\.test\(error\.message\)\) return "not_found";\s+return "invalid_input";/, 'item ausente e regra de estado');
});

test('G. mover para review com o card em rascunho avisa que nao envia', () => {
  const m = slice('if (params.action === "move" && params.status === "review") {', '\n      }\n', 'aviso do move');
  assert.match(m,
    /if \(cur && \(cur\.curation_status === "draft" \|\| cur\.curation_status === "leader_review"\)\) \{\s+moveWarnings\.push\(`Mover para 'review' NAO envia o card a curadoria/,
    'o aviso so sai quando o envio ainda e possivel');
  assert.match(SRC, /warnings: moveWarnings,\s+next_actions: \[\.\.\.moveNext, "card_get: re-read the card"/,
    'o aviso e a acao seguinte chegam ao envelope');
});

test('H. as leituras de curadoria perguntam write_board em ALGUM lugar, como as RPCs (#1977)', () => {
  const helperAny = slice('async function canAnywhereV4(', '\n}\n', 'canAnywhereV4');
  assert.match(helperAny,
    /const \{ data, error \} = await sb\.rpc\("_can_anywhere_by_member", \{ p_member_id: memberId, p_action: action \}\);\s+if \(error\) return false;/,
    'mesma funcao da RPC, e falha fechada');
  for (const tool of ['get_curation_dashboard', 'get_curation_queue_state']) {
    const t = slice(`mcp.tool("${tool}"`, '\n  });\n', tool);
    const call = t.indexOf(`sb.rpc("${tool}"`);
    assert.ok(call !== -1, `${tool} chama a RPC`);
    const gate = t.slice(0, call);
    assert.match(gate, /\(await canAnywhereV4\(sb, member\.id, 'write_board'\)\)/, `${tool}: write_board em algum lugar`);
    assert.doesNotMatch(gate, /canV4\(sb, member\.id, 'write_board'\)/, `${tool}: sem a forma sem recurso`);
  }
});
