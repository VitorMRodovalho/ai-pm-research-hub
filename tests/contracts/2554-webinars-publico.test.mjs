/**
 * #2554: a pagina publica /webinars le get_public_webinars(), que o visitante (anon) pode executar.
 *
 * A pagina chamava list_webinars_v2, sem EXECUTE para anon, e saia vazia para todo visitante. A correcao NAO abre
 * list_webinars_v2: aquela funcao devolve notas, organizador, co-gestores e o card ligado. Uma RPC publica propria
 * devolve so o que a pagina mostra.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a migration cria get_public_webinars como SECURITY DEFINER e filtra status confirmed/completed E iniciativa
 *      nao confidencial, na mesma clausula WHERE;
 *   B. o link de entrada e o do Sympla (W4) so saem com phase nao nula, e phase so existe para webinar confirmado, decidida por
 *      _meeting_window_phase ate scheduled_at + duration_min (antes acabava no inicio); gravacao e presentes, so para
 *      concluido;
 *   C. a lista de campos nao tem notas, organizador, co-gestores nem card;
 *   D. EXECUTE revogado de PUBLIC e concedido a anon;
 *   E. a pagina chama get_public_webinars e nao chama list_webinars_v2;
 *   G. a pagina so mostra o botao do Sympla quando o link vem, com a chave nos 3 dicionarios;
 *   F. (banco) como anon, a RPC devolve lista so de confirmados/concluidos, so com as chaves permitidas, e
 *      list_webinars_v2 segue negada a anon (controle: o instrumento sabe dizer nao).
 *
 * A, B e C leem a captura VIGENTE da funcao (latestFunctionCapture), porque a funcao mudou depois da 2554; D le a
 * migration 2554, que criou os grants (CREATE OR REPLACE os mantem).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskLineComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2554_webinars_publico\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
// O bloco que decide: a captura vigente da funcao, do CREATE ate o fim do $function$.
const FN = maskLineComments(latestFunctionCapture(ROOT, 'get_public_webinars').block);
const SELECT_LIST = (FN.match(/SELECT\s+w\.id,[\s\S]*?FROM public\.webinars w/) || [''])[0];
const WHERE = (FN.match(/WHERE w\.status[\s\S]*?\)\s*r;/) || [''])[0];
const PAGE = readFileSync(resolve(ROOT, 'src/pages/webinars.astro'), 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/^\s*\/\/.*$/gm, '');

const ALLOWED_KEYS = new Set([
  'id', 'title', 'description', 'scheduled_at', 'duration_min', 'status', 'chapter_code',
  'tribe_name', 'meeting_link', 'phase', 'sympla_event_url', 'youtube_url', 'attendee_count',
]);

test('A: uma migration, SECURITY DEFINER, filtro de status e de confidencial no mesmo WHERE', () => {
  assert.equal(files.length, 1, `uma migration <versao>_2554_webinars_publico.sql (achadas: ${files.length})`);
  assert.ok(FN, 'o corpo de get_public_webinars');
  assert.match(FN, /RETURNS jsonb\s+LANGUAGE sql\s+STABLE\s+SECURITY DEFINER/);
  assert.match(WHERE, /WHERE w\.status IN \('confirmed', 'completed'\)\s+AND NOT public\.is_confidential_initiative\(w\.initiative_id\)/);
});

test('B: link so com phase, phase so para confirmado ate o fim; gravacao e presentes so para concluido', () => {
  assert.match(SELECT_LIST, /CASE WHEN ph\.phase IS NOT NULL THEN w\.meeting_link END AS meeting_link,\s+ph\.phase,/);
  assert.match(
    FN,
    /CROSS JOIN LATERAL \(\s*SELECT CASE WHEN w\.status = 'confirmed'\s+THEN public\._meeting_window_phase\(w\.scheduled_at, w\.duration_min, now\(\)\)\s+END AS phase\s*\) ph\s+WHERE w\.status IN/,
    'phase vem do helper com inicio, duracao e now(), so para confirmado',
  );
  assert.match(SELECT_LIST, /CASE WHEN w\.status = 'completed' THEN w\.youtube_url END AS youtube_url/);
  assert.match(SELECT_LIST, /CASE WHEN w\.status = 'completed' THEN\s+\(SELECT count\(\*\) FROM public\.attendance a[^)]*\)\s+END AS attendee_count/);
  // nenhum outro caminho entrega o link
  assert.equal((SELECT_LIST.match(/meeting_link/g) || []).length, 2, 'meeting_link so dentro do CASE');
  // W4 (GP 11/11/2026): a inscricao opcional no Sympla segue a mesma regra do link de entrada
  assert.match(SELECT_LIST, /ph\.phase,\s+CASE WHEN ph\.phase IS NOT NULL THEN w\.sympla_event_url END AS sympla_event_url,/);
  assert.equal((SELECT_LIST.match(/sympla_event_url/g) || []).length, 2, 'sympla_event_url so dentro do CASE');
});

test('C: sem notas, organizador, co-gestores nem card', () => {
  assert.ok(SELECT_LIST, 'a lista de campos');
  for (const campo of ['notes', 'organizer', 'co_manager', 'board_item', 'members']) {
    assert.doesNotMatch(SELECT_LIST, new RegExp(campo), `${campo} fica fora da leitura publica`);
  }
});

test('D: EXECUTE revogado de PUBLIC e concedido a anon', () => {
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.get_public_webinars\(\) FROM PUBLIC;/);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.get_public_webinars\(\) TO anon, authenticated, service_role;/);
});

test('E: a pagina publica chama get_public_webinars e nao list_webinars_v2', () => {
  assert.match(PAGE, /sb\.rpc\('get_public_webinars'\)/);
  assert.doesNotMatch(PAGE, /list_webinars_v2/);
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;

test('G: o botao do Sympla so aparece com o link, e a chave existe nos 3 dicionarios (W4)', () => {
  assert.match(
    PAGE,
    /\{w\.sympla_event_url && \(\s*<a href=\{w\.sympla_event_url\} target="_blank" rel="noopener"[^>]*>\{t\('webinars\.symplaOptional', lang\)\}<\/a>\s*\)\}/,
  );
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(resolve(ROOT, `src/i18n/${loc}.ts`), 'utf8');
    assert.match(dict, /\n  'webinars\.symplaOptional': '[^']+',\n/, `webinars.symplaOptional em ${loc}`);
  }
});

test('F: como anon, a RPC publica responde e list_webinars_v2 segue negada', {
  skip: (!URL || !ANON) ? 'sem SUPABASE_URL + chave anon (baseline offline)' : false,
}, async () => {
  const call = (fn) => fetch(`${URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: `Bearer ${ANON}` },
    body: '{}',
  });
  const pub = await call('get_public_webinars');
  assert.equal(pub.status, 200, `get_public_webinars como anon (status ${pub.status})`);
  const rows = await pub.json();
  assert.ok(Array.isArray(rows), 'a resposta e uma lista');
  for (const r of rows) {
    assert.ok(['confirmed', 'completed'].includes(r.status), `status publico (veio ${r.status})`);
    for (const k of Object.keys(r)) assert.ok(ALLOWED_KEYS.has(k), `chave fora da leitura publica: ${k}`);
    if (r.status !== 'confirmed') assert.equal(r.meeting_link, null, 'link so para confirmado');
    assert.ok('phase' in r, 'a resposta traz phase (a funcao viva e a desta captura)');
    if (r.meeting_link !== null) assert.ok(['upcoming', 'live'].includes(r.phase), `link so com phase (veio ${r.phase})`);
    if (r.sympla_event_url != null) assert.ok(['upcoming', 'live'].includes(r.phase), `Sympla so com phase (veio ${r.phase})`);
  }
  const ctrl = await call('list_webinars_v2');
  assert.ok(ctrl.status === 401 || ctrl.status === 403 || ctrl.status === 404,
    `list_webinars_v2 continua fechada para anon (status ${ctrl.status})`);
});
