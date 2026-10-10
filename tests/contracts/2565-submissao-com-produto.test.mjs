/**
 * #2565: create_publication_submission volta a registrar submissao (toda submissao com produto).
 *
 * Medido em 09/10: content_product_id e NOT NULL sem default desde a p265, e o INSERT da funcao nao o
 * preenchia (23502, exercido em transacao desfeita). As tres telas de submissao chamam esta funcao.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a submissao e gravada com o produto resolvido;
 *   B. com card: o card precisa ser visivel; usa o produto do card ou cria um 'board_item' e liga o card;
 *      sem card: cria um 'external' com a URI do destino;
 *   C. o produto segue o criterio do backfill da p265 (instrumento, modo de revisao, status);
 *   D. o portao de autoridade (write_board) continua antes de qualquer escrita.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const body = maskLineComments(latestFunctionCapture(process.cwd(), 'create_publication_submission').body);

test('A. a submissao e gravada com o produto resolvido', () => {
  assert.match(body,
    /INSERT INTO public\.publication_submissions \([^)]*\bcontent_product_id\s*\)\s+VALUES \([^;]*\bv_product_id\s*\)/);
  const prod = body.indexOf('INSERT INTO public.content_products');
  const sub = body.indexOf('INSERT INTO public.publication_submissions');
  assert.ok(prod !== -1 && prod < sub, 'o produto e resolvido antes da submissao');
});

test('B. com card: visibilidade, produto do card ou novo ligado ao card; sem card: externo', () => {
  assert.match(body,
    /IF p_board_item_id IS NOT NULL THEN\s+IF NOT public\.rls_can_see_item\(p_board_item_id\) THEN\s+RAISE EXCEPTION 'Board item not found';\s+END IF;\s+SELECT bi\.content_product_id INTO v_product_id FROM public\.board_items bi WHERE bi\.id = p_board_item_id;/);
  assert.match(body, /IF v_product_id IS NULL THEN\s+INSERT INTO public\.content_products/, 'so cria quando o card nao tem produto');
  assert.match(body, /CASE WHEN p_board_item_id IS NOT NULL THEN 'board_item' ELSE 'external' END::public\.content_product_source_kind,\s+p_board_item_id,/);
  assert.match(body, /CASE WHEN p_board_item_id IS NULL\s+THEN coalesce\(nullif\(btrim\(p_target_url\), ''\), nullif\(btrim\(p_target_name\), ''\), p_title\) END,/);
  assert.match(body, /IF p_board_item_id IS NOT NULL THEN\s+UPDATE public\.board_items SET content_product_id = v_product_id WHERE id = p_board_item_id;/);
});

test('C. o produto segue o criterio do backfill da p265', () => {
  assert.match(body, /p_target_type::text::public\.content_product_instrument,/);
  for (const [t, m] of [['pmi_global_conference', 'independent_blind'], ['pmi_chapter_event', 'sequential'], ['academic_journal', 'independent_blind'], ['academic_conference', 'independent_blind'], ['webinar', 'collaborative'], ['blog_post', 'sequential'], ['linkedin_newsletter', 'sequential']]) {
    assert.match(body, new RegExp(`WHEN '${t}'\\s+THEN '${m}'`), `${t} => ${m}`);
  }
  assert.match(body, /ELSE 'collaborative'\s+END::public\.review_mode,\s+'under_review'::public\.content_product_status,/);
});

test('D. o portao de autoridade vem antes de qualquer escrita', () => {
  const gate = body.indexOf("IF NOT public.can_by_member(v_member_id, 'write_board') THEN");
  const firstWrite = body.search(/\b(INSERT INTO|UPDATE) public\./);
  assert.ok(gate !== -1 && firstWrite !== -1 && gate < firstWrite);
});
