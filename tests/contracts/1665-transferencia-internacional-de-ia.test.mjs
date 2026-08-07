// tests/contracts/1665-transferencia-internacional-de-ia.test.mjs
//
// #1665 — a seção de transferência internacional se declarava "conforme Art. 33" e listava 6
// destinatários, nenhum deles os TRÊS subprocessadores de IA sediados nos EUA que recebem dado de
// candidato: Google (Gemini), Anthropic (Claude) e OpenAI (Whisper). Os três apareciam na seção de
// compartilhamento e sumiam na de transferência.
//
// A ASSERÇÃO QUE IMPORTA É DE COERÊNCIA ENTRE DOIS TEXTOS
// Ao corrigir, a política passou a fundamentar as transferências de IA no art. 33, VIII. Esse
// inciso não é só "consentimento": é consentimento específico e destacado **com informação prévia
// sobre o caráter internacional da operação**. Ou seja, a base legal declarada na política SÓ se
// sustenta se a tela de consentimento disser que os provedores estão fora do Brasil.
//
// São dois arquivos, dois times, dois momentos — e é exatamente assim que um deles muda sozinho e
// a base legal vira afirmação vazia sem ninguém perceber. O teste amarra os dois.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const DICTS = {
  'pt-BR': 'src/i18n/pt-BR.ts',
  'en-US': 'src/i18n/en-US.ts',
  'es-LATAM': 'src/i18n/es-LATAM.ts',
};
const PRIVACY_PAGE = 'src/pages/privacy.astro';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

/**
 * Escapa TODO metacaractere, não só o ponto. Fica em UM lugar de propósito: na primeira versão
 * deste arquivo o escape completo estava em `dictValue` e uma versão parcial (`replace(/\./g,…)`)
 * aparecia três linhas adiante, no teste da página. O CodeQL pegou a segunda
 * (`js/incomplete-sanitization`). Duas cópias de um escapador é uma cópia a mais.
 */
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function dictValue(src, key) {
  const re = new RegExp(`^\\s*'${escapeRe(key)}':\\s*'((?:[^'\\\\]|\\\\.)*)'`, 'm');
  return src.match(re)?.[1] ?? null;
}

// "está fora do Brasil", por idioma. É a informação que o art. 33, VIII exige como prévia.
const CARATER_INTERNACIONAL = {
  'pt-BR': /Estados Unidos/i,
  'en-US': /United States/i,
  'es-LATAM': /Estados Unidos/i,
};

describe('#1665 — os três subprocessadores de IA entram na transferência internacional', () => {
  for (const [lang, path] of Object.entries(DICTS)) {
    const src = read(path);

    for (const [chave, quem] of [
      ['privacy.s5int.googleAi', /Google/],
      ['privacy.s5int.anthropicAi', /Anthropic/],
      ['privacy.s5int.openaiWhisper', /OpenAI/],
    ]) {
      it(`${lang}: ${chave} existe e nomeia o destinatário`, () => {
        const v = dictValue(src, chave);
        assert.ok(v, `${lang}: ${chave} não encontrada`);
        assert.match(v, quem);
        assert.match(v, /EUA|USA|EE\.UU\./, `${lang}: ${chave} não diz o país de destino`);
      });
    }

    it(`${lang}: as salvaguardas SEPARAM as duas bases legais`, () => {
      const v = dictValue(src, 'privacy.s5int.safeguards');
      assert.ok(v, `${lang}: safeguards não encontrada`);
      // Infra continua em legítimo interesse; IA passa a consentimento. Colapsar as duas numa só
      // seria repetir o defeito do #1642, que era invocar bases incompatíveis para uma operação.
      assert.match(v, /33,?\s*IX/, `${lang}: a base da infraestrutura sumiu`);
      assert.match(v, /33,?\s*VIII/, `${lang}: a base das transferências de IA sumiu`);
    });
  }

  it('a página renderiza as três linhas novas (chave órfã não informa ninguém)', () => {
    const page = read(PRIVACY_PAGE);
    for (const k of ['privacy.s5int.googleAi', 'privacy.s5int.anthropicAi', 'privacy.s5int.openaiWhisper']) {
      assert.match(page, new RegExp(escapeRe(k)), `${k} não é exibida`);
    }
  });
});

describe('#1665 — a política invoca o art. 33, VIII; então a TELA tem de informar o caráter internacional', () => {
  for (const [lang, path] of Object.entries(DICTS)) {
    it(`${lang}: o texto de consentimento diz que os provedores estão fora do Brasil`, () => {
      const src = read(path);
      const safeguards = dictValue(src, 'privacy.s5int.safeguards') ?? '';
      if (!/33,?\s*VIII/.test(safeguards)) {
        // Se um dia a política deixar de invocar o inciso VIII, esta exigência cai junto — e o
        // teste tem de dizer isso alto, em vez de continuar cobrando por inércia.
        console.log(`[1665] ${lang}: política não invoca art. 33, VIII — exigência não se aplica`);
        return;
      }
      const consent = dictValue(src, 'pmi.onboarding.consentBody');
      assert.ok(consent, `${lang}: consentBody não encontrada`);
      assert.match(
        consent,
        CARATER_INTERNACIONAL[lang],
        `${lang}: a política se apoia no art. 33, VIII, que exige informação prévia sobre a ` +
          'transferência internacional, e a tela de consentimento não a dá',
      );
    });
  }
});
