/**
 * O painel "Trilha PMI AI" em /gamification mostra o link de cada curso e diz como a conclusao e registrada.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a consulta dos cursos da trilha traz a coluna `url`, que e o que acende o botao "Acessar curso";
 *   B. o botao continua condicionado a `course.url`;
 *   C. a instrucao de registro aparece abaixo da lista e existe nos 3 dicionarios.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const PAGE = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/gamification.astro'), 'utf8'));
const FN = (PAGE.match(/async function loadMyTrailClarity\(\)[\s\S]*?\n  \}\n/) || [''])[0];

test('A. a consulta da trilha traz a url', () => {
  assert.match(FN, /sb\.from\('courses'\)\.select\('[^']*\burl\b[^']*'\)\.eq\('is_trail', true\)/);
});

test('B. o botao Acessar depende da url', () => {
  assert.match(FN, /const link = course\.url \? '<a href="' \+ escapeHtml\(course\.url\)/);
  assert.match(FN, /\+ statusLabel \+ '<\/span>'\s+\+ link/);
});

test('C. a instrucao aparece abaixo da lista e existe nos 3 idiomas', () => {
  assert.match(FN, /\+ '<div class="space-y-0">' \+ courseRows \+ '<\/div>'\s+\+ '<p[^']*>' \+ escapeHtml\(I\.trailHowTo\) \+ '<\/p>';/);
  assert.match(PAGE, /trailHowTo: t\('gamification\.trail\.howTo', lang\)/);
  for (const d of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = readFileSync(resolve(ROOT, `src/i18n/${d}.ts`), 'utf8');
    assert.match(src, /'gamification\.trail\.howTo': '[^']*Credly[^']*'/, `chave ausente em ${d}`);
  }
});
