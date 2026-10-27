// B2 (GP 26/10/2026): o subtítulo do /cpmai dizia "para a certificação PMI-CPMAI™, em fase piloto", o que soa
// como curso preparatório, e a home diz que não é. O texto aprovado tira essa contradição e deixa o preço de fora
// do subtítulo. Em inglês e espanhol, o subtítulo diz que o piloto é em português (GP, 26/10/2026). O guard fixa o
// texto aprovado nos 3 idiomas e o texto de reserva do componente.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');

const APPROVED = {
  'pt-BR': 'Grupo de estudos do Núcleo IA & GP sobre a metodologia CPMAI, à luz dos padrões do PMI. Não é curso preparatório para a prova.',
  'en-US': 'AI & PM Research Hub study group on the CPMAI methodology, in light of PMI standards. It is not an exam prep course. The pilot runs in Portuguese.',
  'es-LATAM': 'Grupo de estudio del Núcleo IA & GP sobre la metodología CPMAI, a la luz de los estándares del PMI. No es un curso preparatorio para el examen. El piloto se realiza en portugués.',
};

const subtitleOf = (src) => src.match(/^  'cpmai\.subtitle': "([^"]*)",$/m)?.[1];

test('B2: o subtítulo do /cpmai é o texto aprovado nos 3 idiomas, sem preço', () => {
  for (const [lang, expected] of Object.entries(APPROVED)) {
    const got = subtitleOf(read(`src/i18n/${lang}.ts`));
    assert.equal(got, expected, `${lang}: cpmai.subtitle diverge do texto aprovado em 26/10`);
    assert.doesNotMatch(got, /\bpag[oa]\b|\bpaid\b|\bpagado\b|gratuit|\bfree\b/i, `${lang}: o subtítulo não fala de preço`);
  }
});

test('B2: o texto de reserva do componente é o mesmo do dicionário pt-BR', () => {
  const landing = maskJsComments(read('src/components/cpmai/CpmaiLanding.tsx'));
  const fallback = landing.match(/\{t\('cpmai\.subtitle', '([^']*)'\)\}/)?.[1];
  assert.equal(fallback, APPROVED['pt-BR'], 'CpmaiLanding: o texto de reserva diverge do aprovado');
});
