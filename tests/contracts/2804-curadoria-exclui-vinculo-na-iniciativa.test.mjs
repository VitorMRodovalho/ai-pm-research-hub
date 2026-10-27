/**
 * #2804: conflito de interesse na curadoria. Em card de board de LINHA DE PESQUISA (initiatives.kind =
 * 'research_tribe'), quem tem vinculo ativo (qualquer papel) nessa linha nao recebe o card no sorteio, nao e
 * designado a mao e nao registra parecer sobre ele. Nas demais iniciativas vale a declaracao e a abstencao do
 * curador, fora da plataforma (decisao do GP, 27/10/2026: a regra larga deixava 5 iniciativas com menos de 2
 * curadores elegiveis). Base: Codigo de Etica e Conduta Profissional do PMI (ed. 2025), 4.3.1 e 4.3.2.
 *
 * Antes desta mudanca o sorteio (_curation_eligible_reviewers) so excluia o responsavel pelo card, o autor e
 * o colaborador. Lido no corpo vivo em 27/10/2026.
 *
 * O QUE ESTE GUARD AFIRMA, em cada uma das 3 funcoes (sorteio, designacao manual, parecer):
 *   1. o vinculo ativo da PESSOA na iniciativa do board tira a pessoa do card, no bloco que decide
 *      (reprova se a exclusao por vinculo sumir);
 *   2. essa exclusao so vale para linha de pesquisa: a condicao de kind esta DENTRO do mesmo bloco
 *      (reprova se a restricao de kind for removida e a regra ficar larga demais).
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const eligible = maskLineComments(latestFunctionCapture(ROOT, '_curation_eligible_reviewers').body);
const assign = maskLineComments(latestFunctionCapture(ROOT, 'assign_curation_reviewer').body);
const review = maskLineComments(latestFunctionCapture(ROOT, 'submit_curation_review').body);

/** O bloco que decide a lista: do FROM members ate o fim do corpo. */
function whereBlock(body) {
  const at = body.indexOf('FROM public.members m');
  assert.ok(at !== -1, 'o corpo ainda seleciona de public.members m');
  return body.slice(at);
}

// A condicao de kind e opcional em (1) e obrigatoria em (2): tirar so o kind reprova (2) e mantem (1).
const KIND = String.raw`\s+AND i\.kind = 'research_tribe'`;
const sorteio = (kind) => new RegExp(String.raw`AND NOT EXISTS \(SELECT 1\s+FROM public\.board_items bi\s+JOIN public\.project_boards pb ON pb\.id = bi\.board_id\s+JOIN public\.initiatives i ON i\.id = pb\.initiative_id\s+JOIN public\.engagements e ON e\.initiative_id = pb\.initiative_id\s+WHERE bi\.id = p_item_id` + (kind ? KIND : `(?:${KIND})?`) + String.raw`\s+AND e\.person_id = m\.person_id\s+AND e\.status = 'active'\)`);
const manual = (who, kind) => new RegExp(String.raw`IF EXISTS \(SELECT 1 FROM project_boards pb\s+JOIN initiatives i ON i\.id = pb\.initiative_id\s+JOIN engagements e ON e\.initiative_id = pb\.initiative_id\s+WHERE pb\.id = v_item\.board_id` + (kind ? KIND : `(?:${KIND})?`) + String.raw`\s+AND e\.person_id = ${who}\.person_id\s+AND e\.status = 'active'\) THEN\s+RAISE EXCEPTION '[^']*conflict of interest[^']*';`);

test('A1. o sorteio tira da lista quem tem vinculo ativo na iniciativa do board do card', () => {
  assert.match(whereBlock(eligible), sorteio(false), 'vinculo ativo da pessoa do membro exclui o membro');
});

test('A2. no sorteio, a exclusao por vinculo vale so para linha de pesquisa', () => {
  assert.match(whereBlock(eligible), sorteio(true), 'a condicao de kind esta dentro do NOT EXISTS que exclui');
});

test('B1. a designacao manual recusa o parecerista com vinculo, antes de gravar', () => {
  const m = assign.match(manual('v_reviewer', false));
  assert.ok(m, 'vinculo ativo do parecerista levanta erro');
  const write = assign.indexOf('INSERT INTO board_lifecycle_events');
  assert.ok(write !== -1 && m.index < write, 'a recusa vem antes da primeira escrita');
});

test('B2. na designacao manual, a recusa vale so para linha de pesquisa', () => {
  assert.match(assign, manual('v_reviewer', true), 'a condicao de kind esta dentro do IF EXISTS que recusa');
});

test('C1. o parecer recusa quem tem vinculo, antes de gravar', () => {
  const m = review.match(manual('v_caller', false));
  assert.ok(m, 'vinculo ativo de quem da o parecer levanta erro');
  const write = review.indexOf('INSERT INTO curation_review_log');
  assert.ok(write !== -1 && m.index < write, 'a recusa vem antes de gravar o parecer');
});

test('C2. no parecer, a recusa vale so para linha de pesquisa', () => {
  assert.match(review, manual('v_caller', true), 'a condicao de kind esta dentro do IF EXISTS que recusa');
});
