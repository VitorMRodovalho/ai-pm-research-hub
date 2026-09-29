/**
 * Contract #2495 — tela /wiki do piloto do wiki vivo (ADR-0129, emenda 2).
 *
 * A tela oferece ler, escrever, decidir e auditar. O limite de autoridade continua no banco (RLS de
 * wiki_pages e as RPCs do piloto); o que este guard prende é o que a tela acrescentou:
 *   - a página nova só nasce no espaço de caminhos da PRÓPRIA tribo (antes, um pesquisador da tribo 1
 *     podia ocupar nucleo/tribes/tribo-5 e trancar a tribo 5 fora do próprio caminho);
 *   - as duas leituras novas aplicam o portão de membro ativo, o de iniciativa confidencial e a
 *     mesma regra de leitura de versão de wiki_get_version;
 *   - o aviso aponta para a versão;
 *   - todo markdown renderizado atravessa o sanitizador (texto de pessoa, e o marked não sanitiza).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { renderWikiMarkdown, resolveWikiPath } from '../../src/lib/wiki-render.ts';

const ROOT = process.cwd();
const body = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);
const migFile = (name) =>
  maskLineComments(readFileSync(resolve(ROOT, 'supabase/migrations', latestFunctionCapture(ROOT, name).file), 'utf8'));
const PAGE_RAW = readFileSync(resolve(ROOT, 'src/pages/wiki.astro'), 'utf8');
const SCRIPT = maskJsComments(PAGE_RAW.slice(PAGE_RAW.indexOf('<script>')));

// ── caminho por tribo ───────────────────────────────────────────────────────────────────────────
test('#2495 tela: a página nova só nasce no espaço da própria tribo, com fronteira na barra', () => {
  const b = body('wiki_save_draft');
  assert.match(b,
    /v_prefix := public\._wiki_initiative_path_prefix\(p_initiative_id\);\s+IF p_page_path <> v_prefix AND NOT starts_with\(p_page_path, v_prefix \|\| '\/'\) THEN\s+RAISE EXCEPTION/);
  // a trava vem ANTES da gravação: depois do INSERT ela não protegeria nada
  assert.ok(b.indexOf('_wiki_initiative_path_prefix(p_initiative_id)') < b.indexOf('INSERT INTO public.wiki_page_versions'));
  assert.match(body('_wiki_initiative_path_prefix'),
    /CASE WHEN i\.kind = 'research_tribe' AND i\.legacy_tribe_id IS NOT NULL\s+THEN 'nucleo\/tribes\/tribo-' \|\| i\.legacy_tribe_id\s+WHEN i\.kind = 'research_tribe' THEN 'nucleo\/tribes\/' \|\| i\.id::text\s+ELSE 'nucleo\/iniciativas\/' \|\| i\.id::text END/);
});

test('#2495 tela: o aviso leva à versão, não à raiz do wiki', () => {
  assert.match(body('_wiki_notify'),
    /create_notification\(v_id, p_type, p_title, p_body, '\/wiki\?version=' \|\| p_version::text,\s+'wiki_page_version', p_version\)/);
});

// ── leituras novas ──────────────────────────────────────────────────────────────────────────────
test('#2495 tela: as duas leituras novas exigem membro ativo', () => {
  for (const fn of ['wiki_authoring_context', 'wiki_page_history']) {
    assert.match(body(fn),
      /IF v_caller IS NULL OR NOT public\.rls_is_authoritative_member\(\) THEN\s+RAISE EXCEPTION 'wiki: requer membro ativo'/, fn);
  }
});

test('#2495 tela: o contexto de autoria lista só iniciativa com página, visível, em que a pessoa escreve', () => {
  assert.match(body('wiki_authoring_context'),
    /WHERE public\._wiki_domain_for_kind\(i\.kind\) IS NOT NULL\s+AND public\.rls_can_see_initiative\(i\.id\)\s+AND public\._wiki_can_author\(v_caller, i\.id\)\)/);
});

test('#2495 tela: o histórico aplica o portão confidencial e a regra de leitura de versão', () => {
  const b = body('wiki_page_history');
  assert.match(b, /IF v_init IS NULL OR NOT public\.rls_can_see_initiative\(v_init\) THEN\s+RETURN jsonb_build_object\([^;]*'versions', '\[\]'::jsonb\);/);
  assert.match(b,
    /WHERE v\.page_path = p_page_path\s+AND \(v\.status IN \('published', 'superseded'\)\s+OR v\.author_id = v_caller OR v_is_leader OR v_is_committee\)\)/);
  // a mesma regra que wiki_get_version aplica a uma versão só
  assert.match(body('wiki_get_version'),
    /OR NOT \(v_ver\.status IN \('published', 'superseded'\)\s+OR v_ver\.author_id = v_caller\s+OR public\._wiki_is_initiative_leader\(v_caller, v_ver\.initiative_id\)\s+OR public\.can_by_member\(v_caller, 'curate_content'\)\)/);
});

test('#2495 tela: auxiliar sem EXECUTE de cliente; leituras sem anon', () => {
  const m = migFile('wiki_page_history');
  assert.match(m, /REVOKE ALL ON FUNCTION public\._wiki_initiative_path_prefix\(uuid\) FROM PUBLIC, anon, authenticated;/);
  assert.match(m, /REVOKE ALL ON FUNCTION public\.wiki_authoring_context\(\) FROM PUBLIC, anon;/);
  assert.match(m, /REVOKE ALL ON FUNCTION public\.wiki_page_history\(text\) FROM PUBLIC, anon;/);
});

// ── renderização ────────────────────────────────────────────────────────────────────────────────
const LINKS = { page: (p) => `/wiki?page=${encodeURIComponent(p)}`, search: (q) => `/wiki?q=${encodeURIComponent(q)}` };

test('#2495 tela: o markdown renderizado não executa script', () => {
  // Um payload por parágrafo: na mesma linha de um bloco HTML o markdown não interpreta o link, e o
  // teste passaria por um texto inerte em vez de provar que o link virou <a> sem destino.
  const html = renderWikiMarkdown(
    ['<script>alert(1)</script>', '<img src="x" onerror="alert(2)">', '[a](javascript:alert(3))',
      '<iframe src="https://x"></iframe>', '<a href="java\tscript:alert(4)">b</a>'].join('\n\n'),
    'tribes/README.md', LINKS);
  assert.doesNotMatch(html, /<script|<iframe/i);
  assert.doesNotMatch(html, /\son[a-z]+\s*=/i, 'nenhum atributo de evento sobrevive');
  assert.doesNotMatch(html, /(href|src)\s*=\s*"[^"]*script\s*:/i, 'nenhum destino javascript:');
  // controle positivo: o link markdown foi interpretado e ficou sem destino, não sobrou como texto
  assert.match(html, /<a[^>]*>a<\/a>/);
  assert.doesNotMatch(html, /\[a\]\(/);
});

test('#2495 tela: link relativo do vault vira rota da tela; wikilink vira busca; código fica intacto', () => {
  const html = renderWikiMarkdown('[T1](tribo-1-radar.md) [G](../governance/x.md#sec) [[Radar|o radar]] `[[literal]]`', 'tribes/README.md', LINKS);
  assert.match(html, /href="\/wiki\?page=tribes%2Ftribo-1-radar\.md"/);
  assert.match(html, /href="\/wiki\?page=governance%2Fx\.md#sec"/);
  assert.match(html, /<a href="\/wiki\?q=Radar"[^>]*>o radar<\/a>/);
  assert.match(html, /<code>\[\[literal\]\]<\/code>/);
  assert.equal(resolveWikiPath('../../fora.md', 'tribes/README.md'), null);
  assert.equal(resolveWikiPath('https://a.b/x.md', 'tribes/README.md'), null);
});

test('#2495 tela: todo conteúdo de página passa pelo renderizador ou pelo escape', () => {
  assert.doesNotMatch(SCRIPT, /from 'marked'/, 'a tela não chama o marked direto');
  const uses = [...SCRIPT.matchAll(/\b(row|v|base\?)\.content\b/g)].map((m) => SCRIPT.slice(Math.max(0, m.index - 20), m.index));
  assert.ok(uses.length >= 4, `esperava ao menos 4 usos de .content, achou ${uses.length}`);
  // assistantMarkdown monta o texto CRU para colar no assistente: é aceito só porque vai para a área de
  // transferência, nunca para o HTML (afirmado logo abaixo).
  for (const before of uses) assert.match(before, /(renderMd\(|E\(|assistantMarkdown\()$/, `uso de .content sem renderMd/E: "${before}"`);
  const calls = [...SCRIPT.matchAll(/assistantMarkdown\(/g)].map((m) => SCRIPT.slice(Math.max(0, m.index - 30), m.index));
  assert.equal(calls.length, 2, 'assistantMarkdown: a definição e uma chamada');
  assert.match(calls[0], /function $/, 'a primeira ocorrência é a definição');
  assert.match(calls[1], /navigator\.clipboard\.writeText\($/, 'o texto cru só vai para a área de transferência');
  // o trecho da busca vem de ts_headline sobre o conteúdo: vira texto puro e passa pelo escape (B1)
  assert.match(SCRIPT, /\$\{highlight\(snippet, q\)\}/, 'o trecho da busca passa pelo escape');
  assert.match(SCRIPT, /return renderWikiMarkdown\(dropLeadingTitle\(md\), path, LINKS\);/);
});

test('#2495 tela: a tela não escreve em wiki_pages direto', () => {
  assert.doesNotMatch(SCRIPT, /from\('wiki_pages'\)[^;]*\.(insert|update|upsert|delete)\(/);
});

// ── rota, menu e i18n ───────────────────────────────────────────────────────────────────────────
test('#2495 tela: rota nos 3 idiomas e entrada de menu para membro', () => {
  for (const f of ['src/pages/wiki.astro', 'src/pages/en/wiki.astro', 'src/pages/es/wiki.astro']) assert.ok(existsSync(resolve(ROOT, f)), f);
  assert.match(readFileSync(resolve(ROOT, 'src/pages/en/wiki.astro'), 'utf8'), /url=\/wiki\?lang=en-US/);
  assert.match(readFileSync(resolve(ROOT, 'src/pages/es/wiki.astro'), 'utf8'), /url=\/wiki\?lang=es-LATAM/);
  assert.match(readFileSync(resolve(ROOT, 'src/lib/navigation.config.ts'), 'utf8'),
    /\{ key: 'wiki',\s+labelKey: 'nav\.wiki',\s+href: '\/wiki',\s+minTier: 'member', requiresAuth: true,/);
});

test('#2495 tela: toda chave de i18n que a tela usa existe nos 3 dicionários', () => {
  const used = new Set([...PAGE_RAW.matchAll(/'(wiki\.[A-Za-z0-9_.]*[A-Za-z0-9_])'/g)].map((m) => m[1]));
  const dynamic = {
    docType: ['tutorial', 'how_to', 'reference', 'explanation'],
    docTypeHint: ['tutorial', 'how_to', 'reference', 'explanation'],
    goal: ['tutorial', 'how_to', 'reference', 'explanation'],
    domain: ['tribes', 'initiatives', 'research', 'governance', 'platform', 'partnerships', 'onboarding'],
    kind: ['workgroup', 'study_group', 'community_vertical'],
    event: ['submitted', 'returned', 'published', 'audited_kept', 'altered', 'unpublished', 'audit_overdue'],
    status: ['draft', 'pending_leader', 'pending_committee', 'returned', 'published', 'superseded', 'unpublished'],
  };
  for (const [g, vals] of Object.entries(dynamic)) {
    assert.match(PAGE_RAW, new RegExp(`\`wiki\\.${g}\\.\\$\\{`), `a tela monta wiki.${g}.*`);
    for (const v of vals) used.add(`wiki.${g}.${v}`);
  }
  // os valores dinâmicos de evento e estado são os que o banco admite
  const pilot = readFileSync(resolve(ROOT, 'supabase/migrations/20260927212811_wiki_piloto_versoes_e_auditoria.sql'), 'utf8');
  for (const v of dynamic.status) assert.match(pilot, new RegExp(`'${v}'`));
  for (const v of dynamic.event) assert.match(pilot, new RegExp(`'${v}'`));
  used.add('nav.wiki');
  assert.ok(used.size > 100, `esperava mais de 100 chaves, achou ${used.size}`);
  for (const f of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(resolve(ROOT, `src/i18n/${f}.ts`), 'utf8');
    const missing = [...used].filter((k) => !dict.includes(`'${k}':`));
    assert.deepEqual(missing, [], `${f} sem: ${missing.join(', ')}`);
  }
});

// ── fase A da descoberta (27/09): encontrar vem antes de cadastrar ────────────────────────────────
const fnBody = (name) => {
  const i = SCRIPT.indexOf(`function ${name}(`);
  assert.ok(i >= 0, `função ${name} existe`);
  return SCRIPT.slice(i, SCRIPT.indexOf('\n  }\n', i));
};

test('#2495 descoberta: o tipo por objetivo vem da tag diataxis-<tipo> e só vale se for um dos 4', () => {
  const b = fnBody('typeOf');
  assert.match(b, /\/\^diataxis-\//, 'lê a tag com o prefixo diataxis-');
  assert.match(b, /return DOC_TYPES\.includes\(typ\) \? typ : null;/, 'tipo fora dos 4 não vira atalho');
  assert.match(SCRIPT, /\.select\('path,title,summary,domain,tags,/, 'a lista de páginas traz as tags');
});

test('#2495 descoberta: o destaque da sugestão escapa as três partes do texto', () => {
  const b = fnBody('highlight');
  assert.match(b, /if \(i < 0\) return E\(text\);/);
  assert.match(b, /`\$\{E\(text\.slice\(0, i\)\)\}<mark>\$\{E\(text\.slice\(i, i \+ k\.length\)\)\}<\/mark>\$\{E\(text\.slice\(i \+ k\.length\)\)\}`/);
});

test('#2495 descoberta: o atalho "/" não rouba digitação nem o Ctrl+K da busca global', () => {
  const i = SCRIPT.indexOf("if (e.key !== '/'");
  assert.ok(i > 0, 'atalho de busca pela barra');
  const b = SCRIPT.slice(i, SCRIPT.indexOf('});', i));
  assert.match(b, /e\.ctrlKey \|\| e\.metaKey \|\| e\.altKey\) return;/, 'combinação com modificador segue para o site');
  assert.match(b, /isContentEditable \|\| \/\^\(INPUT\|TEXTAREA\|SELECT\)\$\/\.test\(el\.tagName\)\)\) return;/, 'quem está digitando não perde o "/"');
});

test('#2495 descoberta: "versão antiga" só marca página de tribo vinda do repositório', () => {
  assert.match(SCRIPT, /const isOldTribePage = \(p: any\) => p\?\.domain === 'tribes' && p\?\.source_repo !== 'plataforma';/);
  assert.match(SCRIPT, /: isOldTribePage\(row\) \? `<div class="wk-seal">\$\{E\(T\('wiki\.oldSeal'\)\)\}<\/div>` : '';/,
    'o selo de versão antiga aparece na leitura da página de tribo do repositório');
});

test('#2495 descoberta: quem não entrou vê o botão de entrar; membro inativo vê só a explicação', () => {
  assert.match(SCRIPT, /login\.classList\.toggle\('hidden', !canLogin\);/);
  assert.match(SCRIPT, /document\.getElementById\('nav-login-btn'\)/, 'o botão aciona o login do próprio site');
  assert.match(SCRIPT, /deny\(\/requer membro ativo\/\.test\(err\.message \|\| ''\) \? T\('wiki\.activeOnly'\) : T\('wiki\.loadError'\), false\)/,
    'membro inativo não recebe o botão de entrar');
  assert.match(SCRIPT, /deny\(T\('wiki\.loginRequired'\), true\);/, 'sem sessão, o botão aparece');
});

// ── banco vivo ──────────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

test('#2495 tela db: as leituras recusam quem não é membro; o prefixo da tribo 1 é nucleo/tribes/tribo-1',
  { skip: dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required' }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    // service_role não tem auth.uid(): o portão tem de recusar, e não devolver lista vazia
    for (const [fn, args] of [['wiki_authoring_context', {}], ['wiki_page_history', { p_page_path: 'nucleo/tribes/tribo-1' }]]) {
      const r = await sb.rpc(fn, args);
      assert.ok(r.error, `${fn} sem membro autenticado precisa falhar`);
      assert.match(r.error.message, /requer membro ativo/, fn);
    }
    // controle positivo do auxiliar: ele tem de conseguir dizer algo concreto
    const { data: tribe, error } = await sb.from('initiatives').select('id').eq('kind', 'research_tribe').eq('legacy_tribe_id', 1).single();
    assert.ifError(error);
    const p = await sb.rpc('_wiki_initiative_path_prefix', { p_initiative: tribe.id });
    assert.ifError(p.error);
    assert.equal(p.data, 'nucleo/tribes/tribo-1');
  });
