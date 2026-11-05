/**
 * #2880: home, bloco "Vagas abertas" dentro de "Faça parte" (#join). Decisão do GP em 31/10/2026: quais vagas do VEP
 * aparecem é uma marcação POR VAGA no banco (vep_opportunities.home_listing, que nasce 'hidden'), nunca um id no código.
 *
 * O QUE ESTE GUARD AFIRMA:
 *   M. na captura vigente de get_public_home_openings(): a marcação nasce desligada e só aceita três valores; a
 *      função devolve só campos públicos; vaga de iniciativa confidencial nunca sai (ADR-0105); link e prazo só de
 *      vaga 'open', e vaga 'open' só sai com URL pública do VEP e prazo ainda não vencido; anon executa, PUBLIC não.
 *   F. a home: o loader descarta vaga aberta sem link público ou sem prazo; o bloco só aparece com vaga marcada; o
 *      link do cartão vem do banco; nenhum id de vaga no componente; as linhas de requisito só aparecem quando a vaga
 *      a que se referem está aberta.
 *   L. no banco (só com credencial): o que a RPC devolve é exatamente o conjunto que a tabela, lida à parte, diz que
 *      deve sair. Os dois lados são calculados de forma independente, então o teste reprova nos dois sentidos.
 *   R. rótulo de exibição (GP 03/11/2026, V2): uma migration só cria vep_opportunities.home_label, nulo por padrão e
 *      nunca em branco, e o preenche só na 76625, com a contagem conferida; a RPC o devolve, e o loader o prefere,
 *      com o corte do sufixo como reserva quando ele é nulo; nenhum id de vaga no loader.
 *      M1 lê a migration que criou a marcação (20261031185042), porque é ali que ela nasceu; o resto de M lê a captura
 *      vigente, que desde a V2 é outra migration (DROP e CREATE, porque o RETURNS TABLE mudou).
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO no bloco que decide, com comentários mascarados.
 * Efeito colateral: nenhum. A camada viva só lê.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { maskLineComments, maskJsComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const CAP = latestFunctionCapture(ROOT, 'get_public_home_openings');
const ORIG = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', '20261031185042_home_vagas_abertas.sql'), 'utf8'));
const FILE = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', CAP.file), 'utf8'));
const BLOCK = maskLineComments(CAP.block);
const BODY = maskLineComments(CAP.body);
const SELECT_LIST = BODY.slice(0, BODY.search(/\bFROM\s+public\.vep_opportunities\b/));
const WHERE = BODY.slice(BODY.search(/\bWHERE\b/), BODY.search(/\bORDER BY\b/));

// ── M. migration ────────────────────────────────────────────────────────────────────────────────────

test('M1. a marcação por vaga nasce desligada e só aceita hidden, open e soon', () => {
  assert.match(ORIG, /ALTER TABLE public\.vep_opportunities\s+ADD COLUMN home_listing text NOT NULL DEFAULT 'hidden',/);
  assert.match(ORIG, /ADD CONSTRAINT vep_opportunities_home_listing_check CHECK \(home_listing IN \('hidden', 'open', 'soon'\)\)/);
  assert.match(ORIG, /ADD COLUMN application_deadline date,/);
});

test('M2. a função devolve só campos públicos', () => {
  const ret = BLOCK.match(/RETURNS TABLE\(([\s\S]*?)\)\s+LANGUAGE/);
  assert.ok(ret, 'RETURNS TABLE não encontrado');
  const cols = ret[1].split(',').map((c) => c.trim().split(/\s+/)[0]);
  assert.deepEqual(cols, ['opportunity_id', 'title', 'role_default', 'listing', 'vep_url', 'application_deadline',
    'start_date', 'time_commitment', 'line_title', 'home_label']);
  assert.match(BLOCK, /STABLE SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
});

test('M3. vaga de iniciativa confidencial nunca sai (ADR-0105)', () => {
  assert.match(WHERE, /AND \(o\.initiative_id IS NULL\s+OR \(coalesce\(i\.visibility, 'standard'\) <> 'confidential' AND public\.rls_can_see_initiative\(i\.id\)\)\)/);
  assert.match(BODY, /LEFT JOIN public\.initiatives i ON i\.id = o\.initiative_id\s+WHERE/);
});

test('M4. só a marcação decide quem entra, e link e prazo saem só de vaga aberta', () => {
  assert.match(WHERE, /^WHERE o\.home_listing IN \('open', 'soon'\)\s+AND/);
  assert.match(SELECT_LIST, /CASE WHEN o\.home_listing = 'open' THEN o\.vep_url END,/);
  assert.match(SELECT_LIST, /CASE WHEN o\.home_listing = 'open' THEN o\.application_deadline END,/);
  assert.match(SELECT_LIST, /CASE WHEN i\.kind = 'research_tribe' THEN i\.title END/);
});

test('M5. vaga aberta só sai com URL pública do VEP e prazo ainda não vencido', () => {
  assert.match(WHERE, /AND \(o\.home_listing = 'soon'\s+OR \(o\.vep_url LIKE 'https:\/\/volunteer\.pmi\.org\/opportunities\/%'\s+AND o\.application_deadline > \(now\(\) AT TIME ZONE 'America\/Sao_Paulo'\)::date\)\)/);
});

test('M6. anon executa, PUBLIC não', () => {
  assert.match(FILE, /REVOKE ALL ON FUNCTION public\.get_public_home_openings\(\) FROM PUBLIC;/);
  assert.match(FILE, /GRANT EXECUTE ON FUNCTION public\.get_public_home_openings\(\) TO anon, authenticated, service_role;/);
});

// ── F. home ─────────────────────────────────────────────────────────────────────────────────────────

const LOADER = maskJsComments(readFileSync(join(ROOT, 'src/lib/publicHomeData.ts'), 'utf8'));
const LOAD_FN = LOADER.slice(LOADER.indexOf('export async function loadHomeOpenings'));
const JOIN = maskJsComments(readFileSync(join(ROOT, 'src/components/sections/JoinSection.astro'), 'utf8'));

test('F1. o loader lê a RPC e descarta vaga aberta sem link público do VEP ou sem prazo', () => {
  assert.match(LOAD_FN, /rowsOf\(await rpc<unknown>\('get_public_home_openings'\)\)/);
  assert.match(LOADER, /const VEP_PUBLIC_URL = \/\^https:\\\/\\\/volunteer\\\.pmi\\\.org\\\/opportunities\\\/\\d\+\$\/;/);
  assert.match(LOAD_FN, /url: isText\(r\.vep_url\) && VEP_PUBLIC_URL\.test\(r\.vep_url\) \? r\.vep_url : null,/);
  assert.match(LOAD_FN, /\.filter\(\(o\) => o\.listing === 'soon' \|\| \(o\.url !== null && o\.deadline !== null\)\);/);
});

test('F2. o bloco só aparece com vaga marcada, e o link do cartão vem do banco', () => {
  assert.match(JOIN, /const open = openings\.filter\(\(o\) => o\.listing === 'open'\);/);
  assert.match(JOIN, /const soon = openings\.filter\(\(o\) => o\.listing === 'soon'\);/);
  assert.match(JOIN, /\{\(open\.length > 0 \|\| soon\.length > 0\) && \(\s*<div id="vagas"/);
  assert.match(JOIN, /\{o\.url && \(\s*<a href=\{o\.url\} target="_blank" rel="noopener noreferrer"/);
  assert.doesNotMatch(JOIN, /\b(?:6[0-9]|7[0-9])\d{3}\b/, 'id de vaga no componente: a seleção é pela marcação no banco');
});

test('F3. cada linha de requisito só aparece quando a vaga a que se refere está aberta', () => {
  assert.match(JOIN, /const hasLine = open\.some\(\(o\) => o\.line !== null\);/);
  assert.match(JOIN, /const hasLeader = open\.some\(\(o\) => o\.role === 'leader'\);/);
  assert.match(JOIN, /\{hasLine && <li>\{t\('homeV2\.join\.openings\.levelLine', lang\)\}<\/li>\}/);
  assert.match(JOIN, /\{hasLeader && <li>\{t\('homeV2\.join\.openings\.levelLeader', lang\)\}<\/li>\}/);
});

// ── R. rótulo de exibição (V2) ───────────────────────────────────────────────────────────────────────

const LABEL_MIGS = readdirSync(join(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => [f, maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', f), 'utf8'))])
  .filter(([, sql]) => /\bADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?home_label\b/i.test(sql));

test('R1. uma migration só cria home_label, nulo por padrão e nunca em branco, e o preenche só na 76625', () => {
  assert.equal(LABEL_MIGS.length, 1, `migrations que criam home_label: ${JSON.stringify(LABEL_MIGS.map(([f]) => f))}`);
  const sql = LABEL_MIGS[0][1];
  assert.match(sql,
    /ALTER TABLE public\.vep_opportunities\s+ADD COLUMN home_label text,\s+ADD CONSTRAINT vep_opportunities_home_label_check CHECK \(home_label IS NULL OR btrim\(home_label\) <> ''\);/);
  assert.match(sql,
    /UPDATE public\.vep_opportunities\s+SET home_label = 'Embaixador\(a\)'\s+WHERE opportunity_id = '76625';\s*GET DIAGNOSTICS v_n = ROW_COUNT;\s*IF v_n <> 1 THEN\s*RAISE EXCEPTION/);
  const setters = LABEL_MIGS.length === 1 ? [...sql.matchAll(/SET\s+home_label\s*=/gi)].length : -1;
  assert.equal(setters, 1, 'home_label é gravado em mais de um comando da migration');
});

test('R2. a RPC devolve o home_label da própria vaga, no fim da lista', () => {
  assert.match(SELECT_LIST, /CASE WHEN i\.kind = 'research_tribe' THEN i\.title END,\s*o\.home_label\s*$/);
});

test('R3. o loader prefere o home_label e usa o corte do sufixo só quando ele é nulo, sem id de vaga', () => {
  assert.match(LOAD_FN,
    /const own = isText\(r\.home_label\) \? r\.home_label\.trim\(\) : '';\s*const cut = r\.title\.search\(\/\\s\+-\\s\+Núcleo\\b\/\);\s*return \{\s*id: r\.opportunity_id,\s*label: own \|\| \(cut > 0 \? r\.title\.slice\(0, cut\) : r\.title\)\.trim\(\),/);
  assert.doesNotMatch(LOAD_FN, /\b(?:6[0-9]|7[0-9])\d{3}\b/, 'id de vaga no loader: o rótulo é um campo da vaga no banco');
});

// ── L. banco ────────────────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const skip = SUPABASE_URL && SUPABASE_KEY ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('L1. a RPC devolve exatamente as vagas que a tabela, lida à parte, manda mostrar', { skip }, async () => {
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  const { data: vagas, error: e1 } = await sb.from('vep_opportunities')
    .select('opportunity_id, home_listing, vep_url, application_deadline, initiative_id, home_label');
  assert.ifError(e1);
  const { data: inis, error: e2 } = await sb.from('initiatives').select('id, visibility');
  assert.ifError(e2);
  const confidenciais = new Set((inis ?? []).filter((i) => i.visibility === 'confidential').map((i) => i.id));
  const hoje = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date());

  const esperado = (vagas ?? []).filter((v) =>
    ['open', 'soon'].includes(v.home_listing)
    && !(v.initiative_id && confidenciais.has(v.initiative_id))
    && (v.home_listing === 'soon'
      || (/^https:\/\/volunteer\.pmi\.org\/opportunities\//.test(v.vep_url ?? '') && (v.application_deadline ?? '') > hoje)))
    .map((v) => `${v.opportunity_id}:${v.home_listing}`).sort();

  const { data: rpc, error: e3 } = await sb.rpc('get_public_home_openings');
  assert.ifError(e3);
  const obtido = (rpc ?? []).map((r) => `${r.opportunity_id}:${r.listing}`).sort();
  assert.deepEqual(obtido, esperado);
  const rotulo = new Map((vagas ?? []).map((v) => [String(v.opportunity_id), v.home_label ?? null]));
  for (const r of rpc ?? []) {
    if (r.listing === 'soon') assert.equal(r.vep_url, null, `${r.opportunity_id}: vaga em breve não leva link`);
    assert.equal(r.home_label ?? null, rotulo.get(String(r.opportunity_id)), `${r.opportunity_id}: home_label diferente da tabela`);
  }
});
