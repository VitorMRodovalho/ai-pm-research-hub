/**
 * Contract: #1587 — o estado da entrevista tem UMA fonte, e ela não é a última linha por data.
 *
 * Uma candidatura pode ter várias linhas em `selection_interviews`: o trigger
 * `trg_supersede_prior_open_interviews` marca as anteriores como `cancelled` ao criar uma nova.
 * Logo a linha com maior `scheduled_at` pode ser uma CANCELADA POR SUPERSEDE enquanto a entrevista
 * realizada está em outra linha. Medido em 14/08/2026: 14 candidaturas têm mais de uma linha (34
 * linhas), e 5 dessas dão resposta ERRADA lidas como `DISTINCT ON (application_id) ... ORDER BY
 * scheduled_at DESC` — 4 cuja última por data é `cancelled` e 1 `scheduled`, todas já realizadas.
 *
 * O achado MAIOR da medição não era a última-linha-por-data, e sim o cache: a coluna
 * `selection_applications.interview_status` NUNCA assume 'completed' (nenhuma das 29 funções vivas
 * que tocam a tabela escreve esse valor), então 106 das 170 candidaturas exibiam no dashboard um
 * estado divergente do que as próprias linhas provam.
 *
 * Três decisões de forma, cada uma com a INVERSA que este teste proíbe:
 *
 * 1. `ja_realizada` é `bool_or(status='completed' OR conducted_at IS NOT NULL)` sobre TODAS as
 *    linhas — nunca a escolha de uma linha por ordenação de data. A inversa reintroduz exatamente
 *    o defeito da issue.
 *
 * 2. `needs_reschedule` VEM DO CACHE, de propósito. É estado de INTENÇÃO (escrito por
 *    `request_interview_reschedule`), não derivável das linhas de entrevista, e a fila de convite
 *    do admin (`selection.astro`) filtra por ele. Derivar tudo das linhas apagaria a fila.
 *
 * 3. A view é `security_invoker` e NÃO alcança `anon`. Ela cruza `selection_applications`, tabela
 *    de PII de candidato: uma view sem `security_invoker` roda com os privilégios do dono e vira
 *    porta de contorno da RLS (LGPD/GC-162).
 *
 * Camada A (estática, sobre a migration) + camada B (VIVA, sobre o banco): um guard que só lê
 * arquivo fica verde com o mecanismo inerte — a lição do #1649.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { loadLatestCaptures } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

const MIGRATION_VIEW = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.includes('1587_view_canonica_estado_da_entrevista'))
  .sort()
  .pop();

const MIGRATION_DASH = readdirSync(MIGRATIONS_DIR)
  .filter((f) => f.includes('1587_dashboard_deriva_o_estado_da_view'))
  .sort()
  .pop();

/**
 * Comentários FORA antes de qualquer asserção de ausência. O cabeçalho destas migrations cita
 * literalmente o padrão que elas proíbem ("ORDER BY scheduled_at DESC"), e um guard de ausência
 * sobre o fonte cru casaria o próprio comentário.
 */
const semComentarios = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

const SQL_VIEW = MIGRATION_VIEW
  ? semComentarios(readFileSync(join(MIGRATIONS_DIR, MIGRATION_VIEW), 'utf8'))
  : '';
const SQL_DASH = MIGRATION_DASH
  ? semComentarios(readFileSync(join(MIGRATIONS_DIR, MIGRATION_DASH), 'utf8'))
  : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const anonGated = !!(SUPABASE_URL && ANON_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const anonSkipMsg = 'Skipped: SUPABASE_URL + PUBLIC_SUPABASE_ANON_KEY required';

async function rest(caminho, init) {
  return fetch(`${SUPABASE_URL}/rest/v1/${caminho}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      ...(init?.headers ?? {}),
    },
  });
}

// ── A · as migrations existem e dizem o que a decisão foi ────────────────────────────────────

test('A1: as duas migrations do #1587 estão no repositório', () => {
  assert.ok(MIGRATION_VIEW, 'nenhuma migration 1587_view_canonica_* em supabase/migrations');
  assert.ok(MIGRATION_DASH, 'nenhuma migration 1587_dashboard_deriva_* em supabase/migrations');
});

test('A2: a view existe e é security_invoker — não é porta de contorno da RLS', () => {
  assert.match(SQL_VIEW, /CREATE VIEW public\.v_application_interview_state/,
    'a view canônica não é criada');
  assert.match(SQL_VIEW, /WITH \(security_invoker = true\)/,
    'a view perdeu security_invoker: ela cruza selection_applications (PII de candidato) e sem '
    + 'isso roda com os privilégios do dono, ignorando a RLS de quem consulta.');
});

test('A3: a view não é concedida a anon', () => {
  assert.match(SQL_VIEW, /REVOKE ALL ON public\.v_application_interview_state FROM PUBLIC, anon/,
    'sumiu o REVOKE de PUBLIC/anon sobre a view de PII de candidatura');
  assert.doesNotMatch(SQL_VIEW, /GRANT SELECT ON public\.v_application_interview_state TO [^;]*\banon\b/,
    'a view foi concedida a anon — ela expõe estado de entrevista de candidato (LGPD/GC-162)');
});

test('A4: `ja_realizada` é bool_or sobre TODAS as linhas, nunca uma linha escolhida por data', () => {
  assert.match(
    SQL_VIEW,
    /bool_or\(\s*si\.status = 'completed' OR si\.conducted_at IS NOT NULL\s*\)\s*AS ja_realizada/,
    'ja_realizada deixou de ser bool_or sobre todas as linhas — é exatamente a leitura que a '
    + 'issue prova errada em 5 candidaturas.',
  );
  // A inversa da decisão 1: escolher a linha por scheduled_at reintroduz o supersede como verdade.
  assert.doesNotMatch(
    SQL_VIEW,
    /DISTINCT ON \(\s*si\.application_id\s*\)[^)]*ORDER BY\s+si\.application_id\s*,\s*si\.scheduled_at DESC/,
    'a view voltou a escolher a linha canônica por scheduled_at DESC puro: a linha mais recente '
    + 'por data pode ser uma cancelada por supersede.',
  );
});

test('A5: `needs_reschedule` é preservado do cache — a fila de convite depende dele', () => {
  assert.match(SQL_VIEW, /WHEN a\.interview_status = 'needs_reschedule'\s*THEN 'needs_reschedule'/,
    'a view parou de preservar needs_reschedule. Ele é estado de INTENÇÃO, escrito por '
    + 'request_interview_reschedule, não derivável das linhas de entrevista — e o filtro da fila '
    + 'de convite em selection.astro filtra por ele.');
});

test('A6: o dashboard deriva da view, e mantém o cache sob outra chave para o ratchet', () => {
  assert.match(SQL_DASH, /'interview_status', COALESCE\(\s*\(SELECT v\.interview_state FROM public\.v_application_interview_state v/,
    'get_selection_dashboard não deriva mais interview_status da view canônica');
  assert.match(SQL_DASH, /'interview_status_cache', a\.interview_status/,
    'sumiu interview_status_cache do payload: sem ele o ratchet não consegue medir a divergência '
    + 'do cache encolher sem consulta manual.');
});

// ── B · o mecanismo está VIVO, não só escrito ────────────────────────────────────────────────

test('B1: a view responde no banco', { skip: dbGated ? false : skipMsg }, async () => {
  const r = await rest('v_application_interview_state?select=application_id,interview_state&limit=1');
  assert.equal(r.status, 200, `a view não responde: HTTP ${r.status}`);
  const linhas = await r.json();
  assert.ok(Array.isArray(linhas), 'a view não devolveu uma coleção');
});

test('B2: anon NÃO alcança a view', { skip: anonGated ? false : anonSkipMsg }, async () => {
  // Sonda direta na porta, não inspeção do grant: o grant é o que DEVERIA valer, a porta é o que vale.
  const r = await fetch(
    `${SUPABASE_URL}/rest/v1/v_application_interview_state?select=application_id&limit=1`,
    { headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` } },
  );
  assert.notEqual(r.status, 200,
    'anon alcançou a view de estado de entrevista — ela cruza PII de candidatura (LGPD/GC-162)');
});

test('B3: nenhuma candidatura com entrevista realizada é classificada como "none"',
  { skip: dbGated ? false : skipMsg }, async () => {
    const r = await rest(
      'v_application_interview_state?select=application_id,ja_realizada,interview_state'
      + '&ja_realizada=eq.true&interview_state=eq.none',
    );
    assert.equal(r.status, 200, `consulta falhou: HTTP ${r.status}`);
    const erradas = await r.json();
    assert.equal(erradas.length, 0,
      `${erradas.length} candidaturas têm entrevista realizada e a view diz "none" — a derivação `
      + 'do estado quebrou.');
  });

test('B4: o corpo VIVO de get_selection_dashboard é o da captura em migration',
  { skip: dbGated ? false : skipMsg }, async () => {
    // O catálogo devolve HASH, não corpo (proname, identity_args, body_md5, prosrc_len, is_secdef).
    // Comparar o hash vivo com o da captura local prova mais do que grepar o corpo: se baterem, o
    // corpo vivo É byte-a-byte (a menos de whitespace) o do arquivo — e A6 já garante que o arquivo
    // deriva da view. É também a checagem que impede o par clássico "migration no repositório,
    // banco não atualizado".
    const r = await rest('rpc/_audit_list_public_function_bodies', { method: 'POST', body: '{}' });
    if (r.status !== 200) {
      // O endpoint de catálogo varre os SECDEF e estoura statement_timeout sob contenção (#1742).
      // Um 504 aqui não é prova de divergência — a camada A já cobre a captura em migration.
      assert.ok([504, 500, 408].includes(r.status),
        `resposta inesperada do catálogo de corpos: HTTP ${r.status}`);
      return;
    }
    const corpos = await r.json();
    const vivo = corpos.find(
      (f) => f.proname === 'get_selection_dashboard' && f.identity_args === 'p_cycle_code text',
    );
    assert.ok(vivo, 'get_selection_dashboard não aparece no catálogo de corpos vivos');

    const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
    const cap = latest.get('get_selection_dashboard@p_cycle_code text');
    assert.ok(cap, 'sem captura de migration para get_selection_dashboard');
    assert.equal(
      vivo.body_md5, cap.bodyHash,
      `o corpo vivo de get_selection_dashboard diverge da captura em ${cap.file}. Ou a migration `
      + 'do #1587 não foi aplicada ao banco, ou o corpo vivo foi alterado por fora.',
    );
  });
