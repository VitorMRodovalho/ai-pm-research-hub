/**
 * Contract #2738 (parte C): quem chega à home por uma área de atuação descobre que já há linha de pesquisa
 * ativa e que outras verticais podem abrir.
 *
 * DEFEITO, medido em 19/10/2026 como visitante anônimo em EN: o card de Construction ou de PMO dizia
 * "Forming" e levava à vaga no VEP, mas não levava às linhas de pesquisa que já existem para essas áreas
 * (ficam mais abaixo, em Research Streams), e nada dizia que uma área nova pode ser proposta.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. A frase montada pelo componente é, nas três línguas, o texto que o GP aprovou em 19/10/2026,
 *      palavra por palavra. Mudar o texto é mudar este guard, de propósito.
 *   B. A frase liga o trecho do meio a #tribes e o e-mail a um mailto, dentro do mesmo parágrafo.
 *   C. #tribes é um id da TribesSection, e as três home pages renderizam a TribesSection.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const SRC = maskJsComments(read('src/components/sections/VerticalsSection.tsx'));

const APPROVED = {
  'pt-BR': 'Algumas verticais já têm linha de pesquisa ativa: veja Linhas de Pesquisa abaixo. Sua área não está aqui? Novas verticais abrem quando profissionais as propõem: escreva para nucleoia@pmigo.org.br.',
  'en-US': "Some verticals already have an active research stream: see Research Streams below. Don't see your field? New verticals open when practitioners propose them: write to nucleoia@pmigo.org.br.",
  'es-LATAM': 'Algunas verticales ya tienen una línea de investigación activa: mira Líneas de Investigación abajo. ¿No ves tu área? Se abren nuevas verticales cuando profesionales las proponen: escribe a nucleoia@pmigo.org.br.',
};

/** O bloco de rótulos de uma língua, dentro de LABELS. */
function labelBlock(lang) {
  const m = SRC.match(new RegExp(`^  '${lang}': \\{\\n([\\s\\S]*?)^  \\},`, 'm'));
  assert.ok(m, `bloco de rótulos ${lang} encontrado`);
  return m[1];
}

/** Valor de uma chave de rótulo, entre aspas simples ou duplas. */
function label(block, key) {
  const m = block.match(new RegExp(`^\\s+${key}: (?:'([^']*)'|"([^"]*)"),$`, 'm'));
  assert.ok(m, `rótulo ${key} presente`);
  return m[1] ?? m[2];
}

for (const lang of Object.keys(APPROVED)) {
  test(`A: ${lang}: a frase montada é o texto aprovado`, () => {
    const block = labelBlock(lang);
    const email = SRC.match(/^const CONTACT_EMAIL = '([^']+)';$/m);
    assert.ok(email, 'CONTACT_EMAIL definido');
    const sentence = label(block, 'morePre') + label(block, 'moreLink') + label(block, 'moreMid') + email[1] + label(block, 'moreEnd');
    assert.equal(sentence, APPROVED[lang]);
  });
}

test('B: o parágrafo liga o trecho do meio a #tribes e o e-mail ao mailto, nessa ordem', () => {
  assert.match(
    SRC,
    /<p [^>]*>\s*\{l\.morePre\}<a href="#tribes"[^>]*>\{l\.moreLink\}<\/a>\{l\.moreMid\}<a href=\{`mailto:\$\{CONTACT_EMAIL\}`\}[^>]*>\{CONTACT_EMAIL\}<\/a>\{l\.moreEnd\}\s*<\/p>/,
  );
});

test('C: #tribes existe e as três home pages renderizam a seção de linhas (#2553 PR 2: ResearchLinesSection)', () => {
  assert.match(maskJsComments(read('src/components/sections/ResearchLinesSection.astro')), /<section [^>]*id="tribes"/);
  for (const page of ['src/pages/index.astro', 'src/pages/en/index.astro', 'src/pages/es/index.astro']) {
    assert.match(maskJsComments(read(page)), /^\s*<ResearchLinesSection [^>]*\/>/m, `${page} renderiza a ResearchLinesSection`);
  }
});
