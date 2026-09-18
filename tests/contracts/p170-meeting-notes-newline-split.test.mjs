/**
 * Contract: #170 — a rota de ata nao pode picar prosa em bullets por virgula, nem persistir
 * marcador de corrupcao de serializacao.
 *
 * Causa raiz: a tool montava o conteudo com String(params.decisions).split(",") e
 * String(params.action_items).split(","), um bullet por segmento entre virgulas. Ata em
 * portugues usa virgula dentro da clausula e em lista de responsaveis ("Fabrício, Fernando e
 * Sávio"), entao decisoes/acoes unicas eram estilhacadas em bullets fragmentados — corrompeu
 * 7 linhas de ata guardada. Conserto: dividir so por NEWLINE (nunca por bare ","), mais uma
 * quarentena pre-escrita que recusa marcador de corrupcao ANTES da escrita, para que um payload
 * ruim nunca chegue em events.minutes_text.
 *
 * ⚠️ ALVO MUDOU EM 17/09 (#2351). As duas protecoes viviam dentro de `create_meeting_notes`.
 * A #2351 retirou aquela tool do registro porque era rota DUPLICADA de
 * `meeting_minutes action='write'` — e a ambiguidade de rota era metade do defeito. Ao mudar
 * o alvo, a medicao foi feita, nao suposta:
 *   - a divisao por NEWLINE JA existia na rota canonica;
 *   - a quarentena NAO existia. Foi portada na mesma PR.
 * Sem essa medicao, remover a tool teria custado metade do #170 em silencio — e este guard
 * teria sido "consertado" apagando as asserções que ficaram sem alvo.
 *
 * Este guard afirma sobre o CORPO MASCARADO (sem comentario): o anti-padrao e o nome do
 * marcador aparecem no comentario que os explica, e casar comentario e verde falso
 * (CLAUDE.md, secao de 17/09).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const EF = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const raw = existsSync(EF) ? readFileSync(EF, 'utf8') : '';

/** Recorta o ramo action='write' de meeting_minutes — do discriminador ate o proximo ramo. */
function writeBranch(src) {
  const tool = src.indexOf('"meeting_minutes"');
  if (tool < 0) return '';
  const start = src.indexOf('params.action === "write"', tool);
  if (start < 0) return '';
  const end = src.indexOf('params.action === "close"', start);
  return src.slice(start, end < 0 ? undefined : end);
}

const branch = writeBranch(raw);
const code = maskJsComments(branch); // comentario neutralizado, offsets preservados

test('#170: a rota canonica de escrita de ata (meeting_minutes action=write) existe', () => {
  assert.ok(branch.length > 0, 'ramo action=write de meeting_minutes encontrado');
  assert.match(code, /sb\.rpc\(\s*"upsert_event_minutes"/, 'o ramo escreve via upsert_event_minutes');
});

test('#170: decisions/action_items sao divididos por NEWLINE, nunca por bare comma', () => {
  assert.match(code, /params\.decisions\)\.split\(\/\\r\?\\n\/\)/, 'decisions divide por /\\r?\\n/');
  assert.match(code, /params\.action_items\)\.split\(\/\\r\?\\n\/\)/, 'action_items divide por /\\r?\\n/');
  assert.doesNotMatch(code, /\.split\(","\)/, 'nenhum .split(",") no ramo de escrita');
});

test('#170: a quarentena de marcador de corrupcao dispara ANTES da escrita no banco', () => {
  // CONDICAO amarrada ao RESULTADO: as duas deteccoes tem de ser o predicado do if que RECUSA.
  // Afirmar so a presenca de `hasObjectArtifact` ficaria verde com a recusa removida.
  // O arquivo carrega o CARACTERE U+FFFD literal (como o corpo original carregava), nao a
  // sequencia de escape — por isso a classe casa o caractere, e o teste falharia se alguem
  // trocasse a deteccao por uma string qualquer.
  assert.match(
    code,
    /const hasReplacementChar\s*=\s*text\.includes\(\s*"[�]"\s*\)/,
    'detecta o replacement character U+FFFD no texto que vai ser gravado',
  );
  assert.match(
    code,
    // No fonte o marcador vive DENTRO de um literal de regex, entao os colchetes vem escapados
    // (`\[object Object\]`), e a ancora `^…$` com a flag `m` e o que o prende a LINHA inteira.
    /const hasObjectArtifact\s*=\s*\/\^[^\n]*\\\[object Object\\\][^\n]*\$\/m\.test\(\s*text\s*\)/,
    'detecta a LINHA inteira "[object Object]" (ancorada, para nao acusar prosa que cite o termo)',
  );
  assert.match(
    code,
    /if\s*\(\s*hasReplacementChar\s*\|\|\s*hasObjectArtifact\s*\)\s*\{[\s\S]{0,400}?return\s+invalid\(/,
    'ao detectar o marcador, o ramo tem de RECUSAR — deteccao sem recusa nao protege nada',
  );

  // Falhar ANTES da escrita: a recusa nao vale se o upsert ja aconteceu.
  const gateIdx = code.indexOf('hasObjectArtifact');
  const upsertIdx = code.indexOf('upsert_event_minutes');
  assert.ok(gateIdx > 0, 'quarentena presente no ramo de escrita');
  assert.ok(upsertIdx > gateIdx, 'a quarentena precede a chamada de upsert_event_minutes');
});

test('#170: a orientacao dos parametros e uma-por-linha nos DOIS campos', () => {
  const tool = raw.indexOf('"meeting_minutes"');
  const schema = raw.slice(tool, raw.indexOf('async (params', tool));
  const onePerLine = schema.match(/one per line/gi) ?? [];
  assert.ok(onePerLine.length >= 2, `ambos os params descritos como um-por-linha (achei ${onePerLine.length})`);
  assert.doesNotMatch(schema, /\(comma-separated\)/i, 'sem resquicio de orientacao "(comma-separated)"');
});

test('#170: a tool duplicada nao volta — create_meeting_notes segue fora do registro (#2351)', () => {
  assert.doesNotMatch(
    raw,
    /mcp\.tool\(\s*\n?\s*"create_meeting_notes"/,
    'create_meeting_notes foi absorvida por meeting_minutes; re-registra-la recria a rota ambigua ' +
      'e uma segunda superficie que precisaria carregar estas mesmas protecoes',
  );
});
