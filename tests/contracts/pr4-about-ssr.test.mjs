// PR4 A6 (GP 25/10/2026): o /about chega renderizado do servidor, como a home.
//
// Medido em 25/10/2026, antes desta mudança: um GET sem JavaScript em /about, /about?lang=en-US e /about?lang=es-LATAM
// devolvia só o texto de carregamento, sem número, capítulo, linha, história nem publicação. É o que veem o buscador,
// a prévia de link do WhatsApp e do LinkedIn e quem abre a página pela primeira vez com o navegador lento.
//
// O QUE ESTE GUARD AFIRMA
//   A. A página começa a ler get_public_impact_data no servidor antes das outras leituras, uma falha vira null (nunca
//      500), e a ilha recebe o resultado.
//   B. O leitor (loadImpactData), EXERCIDO com fetch simulado: vai pela via da home (uma leitura boa vale 60 s), copia
//      para a página só os campos que ela mostra (chave nova da RPC não chega ao HTML), mantém null onde a RPC esconde
//      a contagem abaixo de 3 pessoas, e devolve null para erro da API, rede caída, contador ausente e lista fora do
//      formato, que é quando a página volta a buscar no navegador.
//   C. A ilha, RENDERIZADA pelo renderToString do React (o renderizador que o Astro usa no servidor): com dados, o HTML
//      leva contadores, capítulos, linhas, história e publicações, sem o texto de carregamento e sem o formulário; sem
//      dados, leva o texto de carregamento e nenhum contador.
//   D. No código da ilha: a busca no navegador só roda sem os dados do servidor, o contador só volta a 0 fora da tela,
//      e o formulário espera o cliente do navegador.
//
// Hermético: nada aqui fala com o banco. O endereço do leitor é um host .invalid e o fetch é simulado.
import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { buildSync } from 'esbuild';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => maskJsComments(readFileSync(join(ROOT, p), 'utf8'));
const PAGE = read('src/pages/about.astro');
const DATA = read('src/lib/publicHomeData.ts');
const ISLAND = read('src/components/islands/ImpactPageIsland.tsx');
const between = (src, start, end) => {
  const i = src.indexOf(start);
  if (i === -1) return '';
  const j = src.indexOf(end, i + start.length);
  return j === -1 ? '' : src.slice(i, j + end.length);
};

const TMP = mkdtempSync(join(tmpdir(), 'pr4-about-ssr-'));
after(() => rmSync(TMP, { recursive: true, force: true }));
const requireHere = createRequire(import.meta.url);

/** Empacota um ponto de entrada com o esbuild (o TSX vira JS) e devolve o caminho do módulo CommonJS. */
function bundle(name, contents, env = {}) {
  const outfile = join(TMP, `${name}.cjs`);
  buildSync({
    stdin: { contents, resolveDir: ROOT, loader: 'tsx', sourcefile: `${name}-entry.tsx` },
    bundle: true, platform: 'node', format: 'cjs', outfile, jsx: 'automatic', logLevel: 'silent',
    define: { 'process.env.NODE_ENV': '"production"', 'import.meta.env': JSON.stringify(env) },
  });
  return outfile;
}
/** Carrega o módulo de novo a cada chamada: o cache de 60 s do leitor não passa de um caso para o outro. */
const fresh = (file) => { delete requireHere.cache[file]; return requireHere(file); };

// O nome das variáveis é montado, e não escrito, porque o classificador da suíte lê o conteúdo do arquivo e trataria
// este teste como teste de banco.
const ENV = { [['PUBLIC', 'SUPABASE', 'URL'].join('_')]: 'https://stub.invalid', [['PUBLIC', 'SUPABASE', 'ANON', 'KEY'].join('_')]: 'anon-stub' };
const LOADER = bundle('loader', "export { loadImpactData } from './src/lib/publicHomeData.ts';", ENV);
const RENDER = bundle('island', [
  "import { renderToString } from 'react-dom/server';",
  "import { createElement } from 'react';",
  "import Island from './src/components/islands/ImpactPageIsland.tsx';",
  'export const render = (props) => renderToString(createElement(Island, props));',
].join('\n'));

// A resposta da RPC com chaves que a página não mostra (inclusive as que saíram no DB-4), para ver o que o leitor copia.
const RESPOSTA = {
  chapters: 41, active_members: 977, tribes: 23, articles_published: 61, impact_hours: 4321.4, impact_hours_since: 2025,
  webinars: 6, partner_count: 11, chapters_signed: 5, total_events: 99, leader_name: 'X',
  recent_publications: [{ title: 'Artigo de teste', platform: 'Revista', publication_date: '2026-10-01', external_url: 'https://example.org/a', authors: ['X'] }],
  tribes_summary: [{ id: 7, name: 'Linha pt', quadrant_name: 'Quadrant en', member_count: 9, leader_name: 'X' }],
  chapters_summary: [{ chapter: 'PMI-XX', member_count: 7 }, { chapter: 'PMI-YY', member_count: null }],
  timeline: [{ year: 'Out 2026', title: 'PMI Global Summit 2026', description: 'Linha da história', sponsor: 'X' }],
};
const PROJETADO = {
  chapters: 41, active_members: 977, tribes: 23, articles_published: 61, impact_hours: 4321.4, impact_hours_since: 2025,
  recent_publications: [{ title: 'Artigo de teste', platform: 'Revista', publication_date: '2026-10-01', external_url: 'https://example.org/a' }],
  tribes_summary: [{ id: 7, name: 'Linha pt', quadrant_name: 'Quadrant en', member_count: 9 }],
  chapters_summary: [{ chapter: 'PMI-XX', member_count: 7 }, { chapter: 'PMI-YY', member_count: null }],
  timeline: [{ year: 'Out 2026', title: 'PMI Global Summit 2026', description: 'Linha da história' }],
};

/** Roda o leitor num módulo novo, com o fetch trocado. Devolve o resultado e os endereços pedidos. */
async function runLoader(fakeFetch, calls = 1) {
  const realFetch = globalThis.fetch;
  const urls = [];
  globalThis.fetch = async (input, init) => { urls.push(String(input?.url ?? input)); return fakeFetch(input, init); };
  try {
    const { loadImpactData } = fresh(LOADER);
    const results = [];
    for (let i = 0; i < calls; i++) results.push(await loadImpactData());
    return { result: results[0], results, urls };
  } finally {
    globalThis.fetch = realFetch;
  }
}
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

describe('PR4 A6: o /about renderizado do servidor', () => {
  it('A: a leitura começa antes das outras, falha vira null, e a ilha recebe o resultado', () => {
    const start = PAGE.indexOf('const impactRead = loadImpactData().catch(() => null);');
    assert.ok(start > -1, 'about.astro não começa a leitura com a falha virando null');
    const firstAwait = PAGE.indexOf('await ', PAGE.indexOf('---'));
    assert.ok(start < firstAwait, 'a leitura do impacto começa depois de outra leitura, e as duas não correm juntas');
    assert.match(PAGE, /const impact = await impactRead;\s*---/);
    assert.match(PAGE, /<ImpactPageIsland client:load lang=\{lang\} lineNames=\{lineNames\} text=\{text\} initialData=\{impact\} \/>/);
    assert.match(PAGE, /import \{ loadResearchLines, loadImpactData \} from '\.\.\/lib\/publicHomeData';/);
  });

  it('B1: copia só o que a página mostra, pela RPC pública, e o tipo da ilha tem os mesmos campos', async () => {
    const { result, urls } = await runLoader(() => json(RESPOSTA));
    assert.deepEqual(result, PROJETADO);
    assert.deepEqual(urls, ['https://stub.invalid/rest/v1/rpc/get_public_impact_data']);
    const tipo = between(ISLAND, 'export interface ImpactData {', '\n}');
    const campos = [...tipo.matchAll(/^ {2}(\w+): /gm)].map((m) => m[1]).sort();
    assert.deepEqual(campos, Object.keys(PROJETADO).sort(), 'o tipo da ilha e o que o leitor copia divergiram');
  });

  it('B2: uma leitura boa vale 60 s no módulo, como na home: duas páginas seguidas, uma chamada', async () => {
    const { results, urls } = await runLoader(() => json(RESPOSTA), 2);
    assert.deepEqual(results[1], PROJETADO);
    assert.equal(urls.length, 1, `o leitor chamou a RPC ${urls.length} vezes em duas leituras seguidas`);
  });

  it('B3: abaixo de 3 pessoas a contagem continua null, sem número inventado', async () => {
    const { result } = await runLoader(() => json(RESPOSTA));
    assert.equal(result.chapters_summary.find((c) => c.chapter === 'PMI-YY').member_count, null);
  });

  it('B4: erro da API, rede caída, contador ausente ou lista fora do formato devolvem null', async () => {
    const semContador = { ...RESPOSTA }; delete semContador.active_members;
    const casos = [
      ['erro 404 da API', () => json({ code: 'PGRST202', message: 'not found' }, 404)],
      ['rede caída', () => { throw new TypeError('fetch failed'); }],
      ['contador ausente', () => json(semContador)],
      ['timeline fora do formato', () => json({ ...RESPOSTA, timeline: null })],
      ['linha sem contagem', () => json({ ...RESPOSTA, tribes_summary: [{ id: 7, name: 'Linha' }] })],
      ['capítulo com contagem em texto', () => json({ ...RESPOSTA, chapters_summary: [{ chapter: 'PMI-XX', member_count: '7' }] })],
    ];
    for (const [nome, fake] of casos) {
      const { result } = await runLoader(fake);
      assert.equal(result, null, `${nome}: o leitor não devolveu null`);
    }
  });

  it('C1: com os dados do servidor, o HTML da ilha já é a página, nas 3 línguas', () => {
    const { render } = fresh(RENDER);
    const LINGUAS = {
      'pt-BR': { h1: 'Transformando o Gerenciamento de Projetos', members: 'Colaboradores Ativos', loading: 'Carregando dados de impacto...' },
      'en-US': { h1: 'Transforming Project Management', members: 'Active Contributors', loading: 'Loading impact data...' },
      'es-LATAM': { h1: 'Transformando la Gestión de Proyectos', members: 'Colaboradores Activos', loading: 'Cargando datos de impacto...' },
    };
    for (const [lang, w] of Object.entries(LINGUAS)) {
      const html = render({ lang, initialData: PROJETADO, lineNames: { 7: { name: `Linha ${lang}`, quadrantName: 'Q' } }, text: { relation: 'R', privacy: 'P', memberOne: 'M' } })
        .replace(/<!-- -->/g, '');
      assert.match(html, new RegExp(`<h1 [^>]*>${w.h1}`), `${lang}: o título`);
      const contadores = between(html, '<section class="grid grid-cols-2 md:grid-cols-5 gap-6 text-center">', '</section>');
      for (const [valor, rotulo] of [['41', null], ['977+', w.members], ['23', null], ['61+', null], ['4321+', null]]) {
        const alvo = `<div class="text-4xl md:text-5xl font-black text-teal">${valor.replace('+', '\\+')}</div><div [^>]*>${rotulo ?? '[^<]+'}</div>`;
        assert.match(contadores, new RegExp(alvo), `${lang}: o contador ${valor} não está no HTML`);
      }
      assert.match(html, /<div class="font-bold text-sm text-\[var\(--text-primary\)\]">PMI-XX<\/div><div [^>]*>7<\/div>/, `${lang}: o card do capítulo com contagem`);
      assert.match(html, /<div class="font-bold text-sm text-\[var\(--text-primary\)\]">PMI-YY<\/div><\/div>/, `${lang}: o capítulo sem contagem fica sem número`);
      assert.match(html, new RegExp(`<div class="font-bold text-sm text-\\[var\\(--text-primary\\)\\] mb-2">Linha ${lang}</div>`), `${lang}: a linha na língua da página`);
      assert.match(html, /<div class="font-bold text-\[var\(--text-primary\)\]">PMI Global Summit 2026<\/div>/, `${lang}: a linha do Summit`);
      assert.match(html, /<div class="font-semibold text-sm text-\[var\(--text-primary\)\]">Artigo de teste<\/div>/, `${lang}: a publicação`);
      assert.ok(!html.includes(w.loading), `${lang}: o texto de carregamento está no HTML com os dados do servidor`);
      assert.ok(!html.includes('id="lead-form"'), `${lang}: o formulário entrou no HTML do servidor, onde não funciona`);
    }
  });

  it('C2: sem os dados do servidor, a ilha mostra o carregamento e nenhum contador (a reserva de antes)', () => {
    const { render } = fresh(RENDER);
    const html = render({ lang: 'en-US', initialData: null });
    assert.equal(html, '<div class="text-center py-20 text-[var(--text-muted)]">Loading impact data...</div>');
  });

  it('D1: a busca no navegador só roda sem os dados do servidor', () => {
    assert.match(ISLAND, /const \[data, setData\] = useState<ImpactData \| null>\(initialData\);\s+const \[loading, setLoading\] = useState\(!initialData\);/);
    const i = ISLAND.indexOf("sb.rpc('get_public_impact_data')");
    const efeito = ISLAND.slice(ISLAND.lastIndexOf('useEffect(() => {', i), i);
    assert.match(efeito, /^useEffect\(\(\) => \{\s+if \(initialData\) return;\s+let cancelled = false;/);
  });

  it('D2: o contador nasce no número real e só volta a 0 fora da tela', () => {
    const contador = between(ISLAND, 'function AnimatedCounter(', '\n}');
    assert.match(contador, /const \[count, setCount\] = useState\(target\);/);
    assert.match(contador, /if \(box\.top < window\.innerHeight && box\.bottom > 0\) \{ animated\.current = true; setCount\(target\); return; \}\s+setCount\(0\);/);
    assert.equal(contador.split('setCount(0)').length - 1, 1, 'um segundo setCount(0) no contador');
  });

  it('D3: o formulário espera o cliente do navegador', () => {
    assert.match(ISLAND, /\{clientReady && <LeadCaptureForm l=\{l\} lang=\{lang\} privacyLabel=\{text\?\.privacy \?\? ''\} \/>\}/);
    assert.match(ISLAND, /const wait = \(\) => \{\s+if \(cancelled\) return;\s+if \(\(window as any\)\.navGetSb\?\.\(\)\) setClientReady\(true\);\s+else setTimeout\(wait, 300\);/);
  });
});
