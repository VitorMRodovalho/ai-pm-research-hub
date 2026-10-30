// #2553 PR 2, a virada: a home pública passa à v2 aprovada pelo GP em 19 e 20/10/2026.
//
// O guard afirma, no código que a home RENDERIZA (a árvore que index.astro desce, não os arquivos soltos):
//   A. a ordem das seções e a saída das seções de membro (ranking, mosaico, regras, recursos, braços);
//   B. D3: nenhuma leitura de nome de pessoa na home (public_members, leaderboard, ranking da trilha);
//   C. D1 e D2: "Candidatar-me" abre o formulário de interesse, sem vaga do VEP; B4 (GP 26/10): o interesse é
//      contínuo e a entrada é por turma, depois do workshop de onboarding;
//   D. D11: a frase da relação com o PMI é a versão A aprovada, nos 3 idiomas; a do problema e a de PDUs não têm número;
//   E. D8: o filtro por campo só aparece com vínculo cadastrado; a linha cheia diz "completa"; e, pela emenda à D3
//      (GP 26/10/2026), a liderança da linha só vem da leitora com consentimento (get_public_line_leaders), sem contato;
//      B3 (GP 26/10): a linha que só tem a liderança diz "em formação", sem contagem de vagas;
//   F. as âncoras da home antiga levam a um alvo que existe;
//   G. toda chave de texto que as seções novas usam existe nos 3 dicionários.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const PAGES = ['src/pages/index.astro', 'src/pages/en/index.astro', 'src/pages/es/index.astro'];
const DICTS = { 'pt-BR': read('src/i18n/pt-BR.ts'), 'en-US': read('src/i18n/en-US.ts'), 'es-LATAM': read('src/i18n/es-LATAM.ts') };
const S = (name) => maskAstro(read(`src/components/sections/${name}`));

/** Os arquivos que uma página renderiza, descendo pelos .astro (import resolvido E tag usada). */
function renderedTree(pagePath) {
  const out = new Map();
  const walk = (file) => {
    const src = maskAstro(readFileSync(file, 'utf8'));
    const [, fm = '', tpl = ''] = src.split(/^---$/m);
    for (const m of fm.matchAll(/^import\s+(\w+)\s+from\s+'([^']+)'/gm)) {
      if (!new RegExp(`<${m[1]}[\\s/>]`).test(tpl)) continue;
      const base = resolve(dirname(file), m[2]);
      const f = [base, `${base}.astro`, `${base}.tsx`].find((x) => existsSync(x) && /\.(astro|tsx)$/.test(x));
      if (!f || out.has(f)) continue;
      out.set(f, m[1]);
      if (f.endsWith('.astro')) walk(f);
    }
  };
  walk(join(ROOT, pagePath));
  return out;
}
const ORDER = ['HomepageHero', 'OutputsSection', 'ResearchLinesSection', 'ChaptersSection', 'JoinSection', 'WeeklyScheduleSection',
  'TeamSummarySection', 'LadderSection', 'KpiSection', 'FollowSection', 'LegacyHomeAnchors'];
const GONE = ['ModelSection', 'VerticalsSection', 'PlatformStatsSection', 'RouterSection', 'PartnersSection', 'TeamSection', 'TribesSection',
  'OperationalArmsSection', 'RulesSection', 'TrailRankingSection', 'ResourcesSection', 'NucleoSection'];
const APPROVED_RELATION = {
  'pt-BR': 'Iniciativa voluntária de cooperação entre capítulos do PMI, sediada no PMI Goiás, com o qual os capítulos firmam seus acordos. Não é um programa do PMI, Inc.',
  'en-US': 'A volunteer cooperation initiative among PMI chapters, hosted by PMI Goiás, with which participating chapters sign their agreements. It is not a program of PMI, Inc.',
  'es-LATAM': 'Iniciativa voluntaria de cooperación entre capítulos del PMI, con sede en PMI Goiás, con el cual los capítulos firman sus acuerdos. No es un programa del PMI, Inc.',
};
const value = (dict, key) => dict.match(new RegExp(`^  '${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}': '((?:[^'\\\\]|\\\\.)*)',$`, 'm'))?.[1];

describe('#2553 a virada da home', () => {
  for (const page of PAGES) {
    it(`A: ${page}: as seções na ordem da v2, e nenhuma seção de membro`, () => {
      const tpl = maskAstro(read(page)).split(/^---$/m)[2] ?? '';
      const tags = [...tpl.matchAll(/^\s*<(\w+Section|HomepageHero|LegacyHomeAnchors)\b/gm)].map((m) => m[1]);
      assert.deepEqual(tags, ORDER);
      const rendered = [...renderedTree(page).values()];
      for (const gone of GONE) assert.ok(!rendered.includes(gone), `${page} ainda renderiza ${gone}`);
    });
  }

  it('B: D3: as seções da home não leem nome de pessoa', () => {
    // o menu (contagem para membro logado) e a camada de apresentação (admin) não são seções do visitante
    const files = [...renderedTree(PAGES[0]).keys()].filter((f) => f.includes('/src/components/sections/'));
    assert.ok(files.length >= 12, `seções da home não lidas (${files.length})`);
    const offenders = files.filter((f) => /public_members|get_public_leaderboard|get_public_trail_ranking|get_operational_arms/.test(maskAstro(readFileSync(f, 'utf8'))));
    assert.deepEqual(offenders.map((f) => f.replace(`${ROOT}/`, '')), []);
  });

  it('C: D1 e D2: as três portas abrem o formulário de interesse, cada uma com o seu papel; B4: entrada por turma', () => {
    const join = S('JoinSection.astro');
    for (const role of ['researcher', 'chapter', 'partner']) {
      assert.match(join, new RegExp(`<ApplyInterest client:visible roleInterest="${role}" source="home-join"`), role);
    }
    assert.match(join, /<article id="join-institutions"[^>]*data-door="chapter">/);
    assert.doesNotMatch(join, /volunteer\.pmi\.org/);
    assert.match(read('src/lib/interestPayload.ts'), /export type InterestRole = 'researcher' \| 'leader' \| 'chapter' \| 'partner';/);
    // B4 (GP 26/10/2026) substitui o "Entrada contínua" de D2: não há prazo para manifestar interesse, mas a entrada
    // é por turma, depois do workshop de onboarding (decisão da gestão de 05/10). O mesmo status nos 3 idiomas.
    const COHORT = {
      'pt-BR': /^Interesse contínuo: não há prazo para se candidatar\. A entrada é por turma, depois do workshop de onboarding\.$/,
      'en-US': /^Ongoing interest: there is no deadline to apply\. People join in cohorts, after the onboarding workshop\.$/,
      'es-LATAM': /^Interés continuo: no hay plazo para postularse\. El ingreso es por cohorte, después del taller de onboarding\.$/,
    };
    for (const [lang, dict] of Object.entries(DICTS)) {
      assert.match(value(dict, 'homeV2.join.subtitle') ?? '', COHORT[lang], `${lang}: status de entrada por turma ausente`);
    }
  });

  it('D: D11: relação com o PMI na versão A, e problema e PDUs sem número', () => {
    const hero = S('HomepageHero.astro');
    assert.match(hero, /\{t\('homeV2\.hero\.problem', lang\)\}[\s\S]*?\{t\('homeV2\.hero\.relation', lang\)\}/);
    for (const [lang, dict] of Object.entries(DICTS)) {
      assert.equal(value(dict, 'homeV2.hero.relation'), APPROVED_RELATION[lang], `${lang}: relação com o PMI`);
      assert.doesNotMatch((value(dict, 'homeV2.hero.problem') ?? '').replace('2024', ''), /\d/, `${lang}: número na frase do problema`);
      assert.match(value(dict, 'homeV2.hero.problem') ?? '', /\(RAND, 2024\)\.$/, `${lang}: fonte da frase do problema`);
      assert.doesNotMatch(value(dict, 'homeV2.join.researcher.pdus') ?? 'x1', /\d/, `${lang}: número na frase de PDUs`);
    }
    assert.match(S('JoinSection.astro'), /const CCR_HANDBOOK = 'https:\/\/www\.pmi\.org\/[^']+ccr-certification-requirements-handbook\.pdf';/);
  });

  it('E: D8 e vagas: filtro por campo só com vínculo; linha cheia diz "completa"; só a liderança diz "em formação"', () => {
    const lines = S('ResearchLinesSection.astro');
    assert.match(lines, /const fields = pairs\.length > 0 \? verticals : \[\];/);
    assert.match(lines, /const full = l\.capacity > 0 && l\.members >= l\.capacity;/);
    assert.match(lines, /const forming = l\.members <= 1;/);
    assert.match(lines, /\{\(forming \|\| l\.capacity > 0\) && \(/, 'B3: a linha em formação mostra o selo mesmo sem capacidade');
    assert.match(lines, /\{forming \? t\('homeV2\.lines\.forming', lang\) : full \? t\('homeV2\.lines\.full', lang\) : t\('homeV2\.lines\.seats', lang\)/);
    assert.match(lines, /\{when \? `\$\{when\} \(\$\{t\('homeV2\.lines\.brt', lang\)\}\)` : t\('homeV2\.lines\.noSchedule', lang\)\}/);
    // Emenda à D3 (GP 26/10/2026): a liderança aparece, só pela leitora com o consentimento da Cláusula 11, e o
    // vídeo é um link para fora (clique para tocar, decisão V de 20/10), nunca um player embutido
    assert.match(lines, /^import \{[^}]*\bloadLineLeaders\b[^}]*\} from '\.\.\/\.\.\/lib\/publicHomeData';$/m);
    assert.match(lines, /const leadersPending = loadLineLeaders\(\);\n[^\n]*\nconst leadersByLine = await leadersPending;/);
    assert.doesNotMatch(lines, /linkedin|e-?mail|phone|whatsapp|<iframe|navGetSb|\.rpc\(|\.from\(/i, 'D3 emendada: a liderança só vem de get_public_line_leaders');
    assert.match(lines, /<a href=\{pitch\} target="_blank" rel="noopener" data-line-video\b/);
    assert.match(read('src/lib/publicHomeData.ts'), /export async function loadLineLeaders\(\): Promise<Map<number, LineLeader\[\]>> \{\s+const rows = await rpc<unknown\[\]>\('get_public_line_leaders'\);/);
  });

  it('F: as âncoras da home antiga levam a um alvo que existe', () => {
    const legacy = S('LegacyHomeAnchors.astro');
    const map = [...legacy.matchAll(/^\s+'#([\w-]+)': (?:'#([\w-]+)'|`\$\{langPrefix\}\/([\w-]+)`),$/gm)];
    assert.ok(map.length >= 8, `mapa de âncoras não lido (${map.length})`);
    const ids = new Set([...renderedTree(PAGES[0]).keys()].flatMap((f) => [...maskAstro(readFileSync(f, 'utf8')).matchAll(/\bid="([\w-]+)"/g)].map((m) => m[1])));
    for (const [, from, toId, toRoute] of map) {
      if (toId) assert.ok(ids.has(toId), `#${from} -> #${toId}, que a home não renderiza`);
      else for (const pre of ['', 'en/', 'es/']) assert.ok(existsSync(join(ROOT, `src/pages/${pre}${toRoute}.astro`)), `#${from} -> /${pre}${toRoute}, rota inexistente`);
      assert.ok(!ids.has(from), `#${from} ainda é id renderizado: não precisa de desvio`);
    }
  });

  it('G: toda chave de texto das seções novas existe nos 3 dicionários', () => {
    const files = ['HomepageHero.astro', 'OutputsSection.astro', 'ResearchLinesSection.astro', 'ChaptersSection.astro', 'JoinSection.astro',
      'TeamSummarySection.astro', 'FollowSection.astro', 'KpiSection.astro', 'LadderSection.astro'];
    const keys = new Set(files.flatMap((f) => [...S(f).matchAll(/\bt\('([\w.]+)'/g)].map((m) => m[1])));
    for (const m of read('src/lib/navigation.config.ts').matchAll(/labelKey: '(nav\.v2\.\w+)'/g)) keys.add(m[1]);
    assert.ok([...keys].filter((k) => k.startsWith('homeV2.')).length >= 60, 'chaves homeV2 não lidas');
    for (const [lang, dict] of Object.entries(DICTS)) {
      const missing = [...keys].filter((k) => !new RegExp(`^  '${k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}': `, 'm').test(dict));
      assert.deepEqual(missing, [], `${lang}: chaves ausentes`);
    }
  });

  it('H: SESTEC nunca entra na home como webinar', () => {
    const files = [...renderedTree(PAGES[0]).keys()].concat([join(ROOT, 'src/lib/publicHomeData.ts')]);
    assert.deepEqual(files.filter((f) => /jYWuKBh0Bpg|sestec/i.test(readFileSync(f, 'utf8'))).map((f) => f.replace(`${ROOT}/`, '')), []);
    assert.match(read('src/lib/publicHomeData.ts'), /\.filter\(\(r\) => r\.status === 'completed' && typeof r\.title === 'string' && \/\^https:\\\/\\\/\/\.test\(String\(r\.youtube_url \?\? ''\)\)\)/);
  });

  it('I: o capítulo-sede leva os dois rótulos, fundador e sede, e o selo mostra a lista inteira (GP 23/10/2026)', () => {
    const chap = S('ChaptersSection.astro');
    assert.match(chap, /const labels = \[\s*\.\.\.\(c\.is_contracting \? \[t\('homeV2\.chapters\.founder', lang\), t\('homeV2\.chapters\.host', lang\)\] : \[\]\),/);
    assert.match(chap, /\{labels\.length > 0 && \(\s*<div[^>]*>\{labels\.join\(' · '\)\}<\/div>/);
  });
});
