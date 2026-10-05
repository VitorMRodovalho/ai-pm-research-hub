/**
 * Funções de leitura SECURITY DEFINER seguem a política de leitura das tabelas que leem.
 *
 * Desde 20260805000246 (e 20260925183649 para colunas de events), as tabelas de cards, presença,
 * reuniões e submissões só deixam ler, pela API, membro com vínculo vigente
 * (rls_is_authoritative_member()), com as exceções de linha própria da própria política. Uma função
 * SECURITY DEFINER ignora a RLS, então cada uma destas aplica a mesma regra a quem chama pela API
 * (public._request_is_rest_caller(), #684); chamadas internas seguem iguais.
 *
 * O QUE ESTE GUARD AFIRMA, na captura VIGENTE de cada função (latestFunctionCapture, #1932):
 *   - a regra existe e vem ANTES da primeira leitura de dado;
 *   - as exceções são as da política da tabela: autor principal da submissão, os próprios eventos
 *     próximos (ou quem gere membros), e a lista de eventos sem ata, notas e convidados externos para
 *     quem tem cadastro de membro sem vínculo vigente.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (name) => maskLineComments(latestFunctionCapture(ROOT, name).block);
const REGRA = String.raw`public\._request_is_rest_caller\(\) AND NOT public\.rls_is_authoritative_member\(\)`;

/** A regra (com o retorno indicado) aparece antes do marcador da primeira leitura. */
function gateBefore(name, gate, firstRead) {
  const b = cap(name);
  const g = b.search(gate);
  const r = b.indexOf(firstRead);
  assert.ok(g >= 0, `${name}: a regra com o retorno de recusa está no corpo`);
  assert.ok(r > g, `${name}: a regra vem antes de "${firstRead.slice(0, 40)}"`);
}

const CASOS = [
  ['get_card_detail', new RegExp(`IF ${REGRA} THEN RETURN NULL; END IF;`), 'SELECT * INTO v_card FROM board_items'],
  ['get_item_assignments', new RegExp(`IF ${REGRA} THEN RETURN '\\[\\]'::jsonb; END IF;`), 'SELECT EXISTS(SELECT 1 FROM board_item_assignments'],
  ['list_card_comments', new RegExp(`IF ${REGRA} THEN\\s+RETURN jsonb_build_object\\('error', 'Card not found'\\);`), 'IF NOT EXISTS (SELECT 1 FROM public.board_items'],
  ['get_portfolio_dashboard', new RegExp(`IF ${REGRA} THEN\\s+RETURN NULL;`), 'SELECT jsonb_agg(row_to_json(sub.*)'],
  ['get_meeting_detail', new RegExp(`IF ${REGRA} THEN\\s+RETURN jsonb_build_object\\('error', 'Event not found'\\);`), 'IF NOT public.rls_can_see_initiative((SELECT e.initiative_id'],
  ['get_initiative_stats', new RegExp(`IF ${REGRA} THEN\\s+RETURN NULL;`), 'v_tribe_id := public.resolve_tribe_id'],
];

for (const [name, gate, firstRead] of CASOS) {
  test(`${name}: aplica a regra da tabela antes de ler`, () => gateBefore(name, gate, firstRead));
}

test('get_publication_submission_detail: vínculo vigente ou autor principal, antes de ler', () => {
  gateBefore(
    'get_publication_submission_detail',
    new RegExp(`IF ${REGRA}\\s+AND NOT EXISTS \\(\\s+SELECT 1 FROM public\\.publication_submissions ps0\\s+JOIN public\\.members m0 ON m0\\.id = ps0\\.primary_author_id\\s+WHERE ps0\\.id = p_submission_id AND m0\\.auth_id = auth\\.uid\\(\\)\\s+\\) THEN\\s+RETURN NULL;`),
    'SELECT jsonb_build_object(',
  );
});

test('get_publication_submissions: a lista só traz o que a política deixa ler', () => {
  const b = cap('get_publication_submissions');
  assert.match(
    b,
    /AND \(NOT public\._request_is_rest_caller\(\) OR public\.rls_is_authoritative_member\(\)\s+OR ps\.primary_author_id IN \(SELECT m2\.id FROM public\.members m2 WHERE m2\.auth_id = auth\.uid\(\)\)\)/,
    'filtro: chamada interna, vínculo vigente ou autor principal',
  );
});

test('get_near_events: pela API, só os próprios eventos ou quem gere membros', () => {
  gateBefore(
    'get_near_events',
    /IF public\._request_is_rest_caller\(\) THEN\s+SELECT m\.id INTO v_caller FROM public\.members m WHERE m\.auth_id = auth\.uid\(\) LIMIT 1;\s+IF v_caller IS NULL OR \(p_member_id IS DISTINCT FROM v_caller AND NOT public\.can_by_member\(v_caller, 'manage_member'\)\) THEN\s+RETURN;/,
    'RETURN QUERY',
  );
});

test('get_tribe_stats: o resultado só sai quando a regra permite', () => {
  const b = cap('get_tribe_stats');
  assert.match(b, new RegExp(`WITH gate AS \\(SELECT \\(NOT public\\._request_is_rest_caller\\(\\) OR public\\.rls_is_authoritative_member\\(\\)\\) AS ok\\)`), 'a regra é a primeira CTE');
  assert.match(b, /\)\s+FROM gate WHERE gate\.ok;\s*\$function\$/, 'o SELECT final só devolve linha com gate.ok');
});

test('get_events_with_attendance: sem cadastro, nada; ata, notas e externos só com vínculo vigente', () => {
  const b = cap('get_events_with_attendance');
  assert.match(b, new RegExp(`SELECT \\(NOT public\\._request_is_rest_caller\\(\\) OR public\\.rls_is_authoritative_member\\(\\)\\) AS full_read,\\s+\\(NOT public\\._request_is_rest_caller\\(\\) OR public\\.rls_is_member\\(\\)\\) AS any_member`), 'as duas regras');
  for (const col of ['minutes_text', 'notes', 'external_attendees']) {
    assert.match(b, new RegExp(`CASE WHEN g\\.full_read THEN e\\.${col} END`), `${col} só com vínculo vigente`);
    assert.doesNotMatch(b, new RegExp(`^\\s*e\\.${col},`, 'm'), `${col} não sai solto`);
  }
  assert.match(b, /CROSS JOIN g\s+LEFT JOIN public\.initiatives i ON i\.id = e\.initiative_id\s+WHERE g\.any_member\s+AND/, 'sem cadastro de membro, nenhuma linha');
});
