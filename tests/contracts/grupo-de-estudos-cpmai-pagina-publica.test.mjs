/**
 * /grupo-de-estudos-cpmai: página pública da 1ª turma do Grupo de Estudos PMI-CPMAI (decisão do GP, 19/11/2026).
 *
 * Hermético: lê a página, as duas páginas de língua, a configuração, os 3 dicionários, o menu e o sitemap.
 * Fixa (a) a paridade das chaves nas 3 línguas, (b) as regras de texto (sem travessão longo, sem preço, sem
 * "chancelado"/"endossado", sem PDU, e "curso" só para o curso do PMI), (c) os dois ramos da inscrição amarrados
 * a SYMPLA_URL, (d) página estática e indexável, fora do menu, e (e) /en e /es pelo meta refresh com ?lang=.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const LANGS = ['pt-BR', 'en-US', 'es-LATAM'];
const PAGE = maskJsComments(read('src/pages/grupo-de-estudos-cpmai.astro'));
const LIB = maskJsComments(read('src/lib/cpmaiStudyGroupPage.ts'));

function pageKeys(lang) {
  const out = new Map();
  for (const m of read(`src/i18n/${lang}.ts`).matchAll(/^  '(cpmaiGroupPage\.[^']+)': "([^"]*)",$/gm)) out.set(m[1], m[2]);
  return out;
}
const DICTS = Object.fromEntries(LANGS.map((l) => [l, pageKeys(l)]));

test('as 3 línguas têm exatamente as mesmas chaves cpmaiGroupPage.*, e nenhuma vazia', () => {
  const pt = [...DICTS['pt-BR'].keys()].sort();
  assert.ok(pt.length >= 30, `pt-BR tem só ${pt.length} chaves cpmaiGroupPage.*`);
  for (const l of LANGS) {
    assert.deepEqual([...DICTS[l].keys()].sort(), pt, `${l}: chaves divergem do pt-BR`);
    for (const [k, v] of DICTS[l]) assert.ok(v.trim().length > 0, `${l}: ${k} vazia`);
  }
});

test('toda chave do dicionário é usada pela página ou pela configuração, e toda usada existe', () => {
  const used = new Set([
    ...[...PAGE.matchAll(/\bk\('([^']+)'\)/g)].map((m) => `cpmaiGroupPage.${m[1]}`),
    ...[...PAGE.matchAll(/'(study\.item\d)'/g)].map((m) => `cpmaiGroupPage.${m[1]}`),
    ...[...LIB.matchAll(/labelKey: '([^']+)'/g)].map((m) => m[1]),
  ]);
  const dict = new Set(DICTS['pt-BR'].keys());
  for (const k of used) assert.ok(dict.has(k), `a página usa ${k}, que não está no dicionário`);
  for (const k of dict) assert.ok(used.has(k), `${k} está no dicionário e a página não usa`);
});

test('regras de texto: sem travessão longo, sem preço, sem chancela, sem PDU, e "curso" só para o curso do PMI', () => {
  const ALLOWED_COURSE = [/pacote de curso e exame/g, /curso oficial obrigatório/g, /course and exam bundle/g,
    /mandatory official course/g, /paquete de curso y examen/g, /curso oficial obligatorio/g];
  for (const l of LANGS) {
    for (const [k, v] of DICTS[l]) {
      assert.doesNotMatch(v, /—/, `${l}: ${k} tem travessão longo`);
      assert.doesNotMatch(v, /R\$|US\$|\$\s*\d|\d+[.,]\d{2}\b|\bBRL\b|\bUSD\b/, `${l}: ${k} cita preço`);
      assert.doesNotMatch(v, /chancel|endoss|endos[ao]|endors|respaldad|aval\b|avalad|\bPDUs?\b/i, `${l}: ${k} usa termo vetado`);
      assert.doesNotMatch(v, /\boficial do PMI\b|\bofficial PMI\b|\boficial del PMI\b/i, `${l}: ${k} chama o grupo de oficial`);
      const rest = ALLOWED_COURSE.reduce((s, re) => s.replace(re, ''), v);
      assert.doesNotMatch(rest, /\bcursos?\b|\bcourses?\b/i, `${l}: ${k} usa "curso" fora do curso do PMI`);
    }
    assert.match(DICTS[l].get('cpmaiGroupPage.footer.trademark'), /PMI® .*PMI-CPMAI™ .*Project Management Institute, Inc\./, l);
  }
});

test('inscrição: com SYMPLA_URL o botão leva ao Sympla; sem ela, só a data de abertura, sem botão', () => {
  assert.match(LIB, /^export const SYMPLA_URL: string \| null = /m);
  assert.match(
    PAGE,
    /\{SYMPLA_URL \? \(\s*<a\s+href=\{SYMPLA_URL\}[^>]*>\{k\('enroll\.cta'\)\}<\/a>\s*\) : \(\s*<p[^>]*>\{k\('enroll\.soon'\)\}<\/p>\s*\)\}/,
  );
  assert.equal((PAGE.match(/enroll\.cta/g) ?? []).length, 1, 'o botão só pode existir no ramo com SYMPLA_URL');
});

test('vagas de voluntariado: as quatro, no portal de voluntários do PMI', () => {
  const urls = [...LIB.matchAll(/href: '(https:\/\/volunteer\.pmi\.org\/opportunities\/\d+)'/g)].map((m) => m[1]);
  assert.deepEqual(urls.map((u) => u.split('/').pop()), ['76631', '76663', '76662', '76664']);
  assert.match(PAGE, /VOLUNTEER_OPENINGS\.map\(\(o\) => \([\s\S]*?href=\{o\.href\}/);
});

test('estática, indexável e fora do menu; o /cpmai continua fora do sitemap', () => {
  assert.doesNotMatch(PAGE, /supabase|createClient|\.rpc\(|fetch\(/i, 'a página não lê dados');
  assert.doesNotMatch(PAGE, /name="robots"/, 'a página pública não leva noindex');
  assert.match(PAGE, /alternates="query"/);
  const cfg = read('astro.config.mjs');
  const excluded = [...cfg.matchAll(/!page\.includes\('([^']+)'\)/g)].map((m) => m[1]);
  assert.ok(excluded.includes('/cpmai'), 'o painel /cpmai segue fora do sitemap');
  for (const p of ['/grupo-de-estudos-cpmai/', '/en/grupo-de-estudos-cpmai/', '/es/grupo-de-estudos-cpmai/']) {
    assert.ok(!excluded.some((e) => p.includes(e)), `${p} cairia fora do sitemap`);
  }
  assert.doesNotMatch(read('src/lib/navigation.config.ts'), /grupo-de-estudos-cpmai/);
});

test('/en e /es redirecionam para ?lang= da página em português', () => {
  for (const [dir, code] of [['en', 'en-US'], ['es', 'es-LATAM']]) {
    const p = `src/pages/${dir}/grupo-de-estudos-cpmai.astro`;
    assert.ok(existsSync(resolve(ROOT, p)), `${p} ausente`);
    assert.match(read(p), new RegExp(`const lang = '${code}' as const;[\\s\\S]*url=/grupo-de-estudos-cpmai\\?lang=${code}"`));
  }
});
