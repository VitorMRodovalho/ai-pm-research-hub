/**
 * Funções SECURITY DEFINER seguem a política das tabelas (lote 2b, decisões do GP em 05/10/2026).
 *
 * O QUE ESTE GUARD AFIRMA, na captura VIGENTE de cada função (latestFunctionCapture, #1932):
 *   A. Quem gerencia uma submissão é decidido num só lugar, _can_manage_publication_submission:
 *      autor principal, quem criou, gestão (manage_platform) e liderança de Publicações & Submissões
 *      (líder ou coordenador vigente no grupo de trabalho dono do quadro de publicações). As três
 *      funções de escrita chamam essa regra antes de escrever.
 *   B. list_webinars_v2 segue a política de webinars: confirmados e concluídos para quem tem login,
 *      o resto e o card ligado só para membro com vínculo vigente.
 *   C. Gamificação: sem vínculo vigente, só a própria estatística e o ranking sem papel nem
 *      designações; quem saiu do ranking só aparece para si e para quem gere membros.
 *   D. Entrega: a função de permissão não é executável por anônimo.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = (name) => maskLineComments(latestFunctionCapture(ROOT, name).block);

test('A1: a regra de quem gerencia uma submissão', () => {
  const b = cap('_can_manage_publication_submission');
  assert.match(b, /WHERE m\.auth_id = auth\.uid\(\)\s+AND m\.is_active IS TRUE/, 'só membro ativo, pelo login');
  assert.match(b, /ps\.primary_author_id = m\.id\s+OR ps\.created_by = m\.id\s+OR public\.can_by_member\(m\.id, 'manage_platform'\)/, 'autor principal, quem criou, gestão');
  assert.match(
    b,
    /e\.status = 'active'\s+AND \(e\.end_date IS NULL OR e\.end_date >= CURRENT_DATE\)\s+AND e\.role IN \('leader', 'coordinator'\)\s+AND i\.kind = 'workgroup'\s+AND EXISTS \(\s+SELECT 1 FROM public\.project_boards pb\s+WHERE pb\.initiative_id = i\.id\s+AND pb\.domain_key = 'publications_submissions'/,
    'liderança vigente do grupo de trabalho dono do quadro de publicações',
  );
  assert.doesNotMatch(b, /curate_content|'write'/, 'curadoria e escrita genérica não entram (decisão do GP)');
});

for (const [name, param, escrita] of [
  ['add_publication_submission_author', 'p_submission_id', 'INSERT INTO public.publication_submission_authors'],
  ['remove_publication_submission_author', 'p_submission_id', 'DELETE FROM public.publication_submission_authors'],
  ['update_publication_submission', 'p_id', 'UPDATE public.publication_submissions SET'],
]) {
  test(`A2: ${name} checa quem gerencia antes de escrever`, () => {
    const b = cap(name);
    const g = b.search(new RegExp(`IF public\\._request_is_rest_caller\\(\\) AND NOT public\\._can_manage_publication_submission\\(${param}\\) THEN\\s+RAISE EXCEPTION`));
    assert.ok(g >= 0, 'a regra existe e recusa');
    assert.ok(b.indexOf(escrita) > g, 'a regra vem antes da escrita');
  });
}

test('B1: list_webinars_v2 segue a política de webinars', () => {
  const b = cap('list_webinars_v2');
  assert.match(b, /v_full boolean := NOT public\._request_is_rest_caller\(\) OR public\.rls_is_authoritative_member\(\);/, 'v_full é a regra da tabela');
  assert.match(b, /AND \(v_full OR w\.status IN \('confirmed', 'completed'\)\)/, 'sem vínculo vigente, só confirmados e concluídos');
  assert.match(b, /CASE WHEN v_full THEN bi\.title END AS board_item_title,\s+CASE WHEN v_full THEN bi\.status END AS board_item_status/, 'o card ligado só com vínculo vigente');
});

test('C1: get_member_gamification_stats filtra antes de calcular', () => {
  const b = cap('get_member_gamification_stats');
  const g = b.search(/IF public\._request_is_rest_caller\(\) THEN\s+p_member_ids := ARRAY\(\s+SELECT DISTINCT mid FROM unnest\(p_member_ids\) mid\s+WHERE mid = v_caller_id\s+OR \(public\.rls_is_authoritative_member\(\)\s+AND \(public\.can_by_member\(v_caller_id, 'manage_member'\)\s+OR NOT EXISTS \(SELECT 1 FROM public\.members mo WHERE mo\.id = mid AND mo\.gamification_opt_out IS TRUE\)\)\)/);
  assert.ok(g >= 0, 'a própria, ou com vínculo vigente respeitando quem saiu do ranking');
  assert.ok(b.indexOf('FROM public.cycles c WHERE c.is_current') > g, 'o filtro vem antes do cálculo');
});

test('C2: get_gamification_leaderboard tira papel e designações sem vínculo vigente e respeita quem saiu', () => {
  const b = cap('get_gamification_leaderboard');
  assert.match(b, /v_full boolean := NOT public\._request_is_rest_caller\(\) OR public\.rls_is_authoritative_member\(\);/, 'v_full é a regra da tabela');
  assert.match(b, /CASE WHEN v_full THEN m\.operational_role END, CASE WHEN v_full THEN m\.designations END,/, 'papel e designações condicionados');
  assert.equal((b.match(/WHERE m\.gamification_opt_out = false/g) || []).length, 2, 'quem saiu do ranking segue fora, nas duas consultas');
});

test('D1: a função de permissão não é executável por anônimo', () => {
  const dir = join(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  const mig = files.map((f) => maskLineComments(readFileSync(join(dir, f), 'utf8'))).find((s) => /FUNCTION public\._can_manage_publication_submission\(/.test(s));
  assert.ok(mig, 'a migration que cria a função existe');
  assert.match(mig, /REVOKE ALL ON FUNCTION public\._can_manage_publication_submission\(uuid\) FROM PUBLIC, anon;/, 'sem EXECUTE para PUBLIC e anon');
});
