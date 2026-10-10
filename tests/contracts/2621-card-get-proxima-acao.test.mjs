/**
 * #2621: card_get diz a proxima acao da curadoria em linguagem de acao.
 *
 * Coluna e status de curadoria sao estados independentes; no caso que abriu a issue, um agente leu
 * "Revisao" como "enviado". O card_get passa a nomear o envio quando o card e publicavel e ainda nao foi
 * enviado, e o prazo e quantos pareceristas quando ja esta em curadoria.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. as acoes da curadoria entram no envelope do card_get, antes das genericas;
 *   B. rascunho ou revisao do lider + artefato publicavel => o envio e nomeado; nao publicavel => nada;
 *   C. em curadoria => prazo e quantos pareceristas, sem identidade;
 *   D. leitura que falha vira aviso, nunca acao inventada.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SRC = maskJsComments(readFileSync(resolve(process.cwd(), 'supabase/functions/nucleo-mcp/index.ts'), 'utf8'));
function slice(a, b, label) {
  const i = SRC.indexOf(a); assert.ok(i !== -1, `${label}: inicio ausente`);
  const j = SRC.indexOf(b, i + a.length); assert.ok(j !== -1, `${label}: fim ausente`);
  return SRC.slice(i, j + b.length);
}
const helper = () => slice('async function curationNextActions(', '\n}\n', 'helper');

test('A. as acoes da curadoria entram no envelope do card_get', () => {
  const tool = slice('    "card_get",', '\n  );\n', 'card_get');
  assert.match(tool, /const curationNext = await curationNextActions\(sb, params\.card_id, d0\?\.card \?\? null, warnings\);/);
  assert.match(tool, /next_actions: \[\.\.\.curationNext, "card_write: mutate this card"/);
});

test('B. publicavel ainda nao enviado => o envio e nomeado', () => {
  const h = helper();
  assert.match(h,
    /if \(status === "draft" \|\| status === "leader_review"\) \{\s+const \{ data, error \} = await sb\.rpc\("get_artifact_classification", \{ p_item_id: cardId \}\);[\s\S]*?if \(data\?\.needs_curation !== true\) return \[\];\s+return \[`Este card é artefato publicável e AINDA NÃO foi enviado à curadoria\. A coluna 'review' não envia; só card_write action='submit_for_curation' card_id=\$\{cardId\} envia/);
});

test('C. em curadoria => prazo e quantos pareceristas, sem identidade', () => {
  const h = helper();
  assert.match(h,
    /if \(status === "curation_pending"\) \{\s+const head = [^\n]+\n\s+const \{ data, error \} = await sb\.from\("curation_reviewer_assignments"\)\.select\("review_round"\)\.eq\("board_item_id", cardId\)\.is\("released_at", null\);/);
  assert.doesNotMatch(h, /reviewer_id/, 'nenhuma identidade de parecerista');
  assert.match(h, /const n = rows\.filter\(\(r\) => r\.review_round === round\)\.length;/, 'conta so a rodada atual');
  assert.match(h, /if \(rows\.length === 0\) return \[`\$\{head\} Pareceristas designados não visíveis para você ou ainda não designados\./,
    'lista vazia (RLS ou sem designacao) nao vira "0 pareceristas"');
  assert.match(h, /\$\{n\} parecerista\(s\) na rodada \$\{round\}/);
});

test('D. leitura que falha vira aviso, nunca acao inventada', () => {
  const h = helper();
  assert.match(h, /if \(!card\) \{ warnings\.push\("curation: card não lido/, 'card ilegivel: aviso');
  assert.match(h, /if \(error\) \{ warnings\.push\(`curation: \$\{error\.message\}`\); return \[\]; \}\s+if \(data\?\.needs_curation/,
    'classificacao ilegivel: nenhuma acao de envio');
  assert.match(h, /if \(error\) \{ warnings\.push\(`curation: \$\{error\.message\}`\); return \[`\$\{head\} Pareceristas: não consegui ler\./,
    'designacoes ilegiveis: aviso e mensagem sem contagem');
});

test('E. o prazo sai como data no fuso de Brasilia, nao como timestamp cru', () => {
  assert.match(helper(), /new Date\(card\.curation_due_at\)\.toLocaleDateString\("pt-BR", \{ timeZone: "America\/Sao_Paulo" \}\)/);
});
