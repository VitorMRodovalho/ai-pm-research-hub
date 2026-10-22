// #2553 PR 2, movimento (decisão do GP em 20/10/2026, "Vídeo e movimento"): já na PR 2, os números do hero saem
// renderizados no servidor, uma regra global atende quem pediu menos movimento, e a home perde a animação infinita.
//
// Medido em 19/10/2026 (perf-live.json): 1 regra de prefers-reduced-motion em todo o src; os contadores do hero
// chegavam como "--" e só viravam número depois de 1,2 s de animação, para todo visitante.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const CSS = readFileSync('src/styles/global.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
const HERO = maskJsComments(readFileSync('src/components/sections/HomepageHero.astro', 'utf8'));
const INDEX = readFileSync('src/pages/index.astro', 'utf8');

// as seções que a home importa direto; animação de carregamento (spin) é estado, não enfeite
const homeSections = [...INDEX.matchAll(/^import \w+ from '\.\.\/components\/(sections|homepage)\/([\w.]+)';$/gm)]
  .map((m) => `src/components/${m[1]}/${m[2]}`);
const LOOP = /\banimate-(?:bounce|pulse|ping)\b|animation[^;{]*\binfinite\b/;

describe('#2553 movimento', () => {
  it('uma regra global: sob reduce, animação e transição terminam no primeiro quadro e nada repete', () => {
    const block = CSS.match(/@media \(prefers-reduced-motion: reduce\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
    assert.match(block, /\*, \*::before, \*::after \{[^}]*animation-duration: 0\.01ms !important;[^}]*animation-iteration-count: 1 !important;[^}]*transition-duration: 0\.01ms !important;/);
    assert.match(block, /html \{ scroll-behavior: auto; \}/);
  });

  it('cada número do hero sai no HTML com o valor final da fonte única', () => {
    for (const [id, field, suffix] of [['stat-members', 'members', ''], ['stat-tribes', 'tribes', ''], ['stat-chapters', 'chapters', ''], ['stat-hours', 'impactHours', ", 'h'"]]) {
      assert.match(HERO, new RegExp(`id="${id}" data-target=\\{stats\\?\\.${field} \\?\\? undefined\\}(?: data-suffix="h")?>\\{statText\\(stats\\?\\.${field}${suffix}\\)\\}</div>`), id);
    }
    assert.match(HERO, /const statText = \(n: number \| null \| undefined, suffix = ''\) => \(typeof n === 'number' \? `\$\{n\}\$\{suffix\}` : '--'\);/);
  });

  it('a contagem só roda para quem não pediu menos movimento', () => {
    assert.match(HERO, /const motionOk = window\.matchMedia\('\(prefers-reduced-motion: no-preference\)'\)\.matches;/);
    assert.match(HERO, /if \(motionOk && el\?\.dataset\.target !== undefined && Number\.isFinite\(target\)\) \{\s+animateCounter\(id, target, el\.dataset\.suffix \?\? ''\);/);
  });

  it('nenhuma seção da home anima em laço', () => {
    assert.ok(homeSections.length >= 10, `a lista de seções da home não foi lida (${homeSections.length})`);
    const offenders = homeSections.filter((f) => LOOP.test(readFileSync(f, 'utf8')));
    assert.deepEqual(offenders, [], `animação infinita em: ${offenders.join(', ')}`);
  });
});
