// tests/contracts/2023-politica-declara-a-custodia-do-termo.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2023 — a política de privacidade declara a entrega e a custódia da via assinada do Termo.
 *
 * POR QUE ISTO VEM ANTES DO CÓDIGO DE ENVIO. O parecer jurídico (27/08/2026) liberou a base legal
 * — Art. 7º, V para as partes signatárias, mais Art. 7º, IX para o arquivo institucional — mas
 * apontou que o TEXTO PÚBLICO negava, ao pé da letra, o que a plataforma passaria a fazer:
 * `privacy.s4.chapters` prometia aos capítulos "dados agregados por capítulo (sem PII individual)",
 * e o instrumento assinado carrega nome, endereço, telefone, nascimento e PMI ID.
 *
 * A distinção que faltava, e que este arquivo protege: **capítulo patrocinador** recebe
 * acompanhamento agregado; **capítulo contratante** guarda a via do contrato de que é PARTE. São
 * papéis diferentes e não podem ser descritos pela mesma frase.
 *
 * DESENHO (decisão do PM, 27/08): o voluntário recebe por e-mail — é a única parte para quem o
 * objetivo é a cópia sobreviver FORA de todo sistema institucional. As instituições acessam uma
 * pasta Drive restrita na conta do capítulo contratante, o que torna a retenção declarada
 * EXEQUÍVEL: um arquivo em pasta se apaga, uma cópia em caixa de e-mail não.
 *
 * Cross-ref: #2023, #2022 (o PDF precisava refletir as duas assinaturas antes de qualquer envio),
 * #2024 (o carimbo temporal precisava parar de depender de onde renderizou), #1642 (guard irmão:
 * a comunicação não pode negar a consequência).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const LANGS = ['pt-BR', 'en-US', 'es-LATAM'];
const dict = (lang) => readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
const page = readFileSync(resolve(ROOT, 'src/pages/privacy.astro'), 'utf8');

// Escapa TODOS os metacaracteres, não só o ponto. Escapar `.` e deixar `\` passar é a classe
// "incomplete string escaping" que o CodeQL aponta: aqui as chaves são literais do próprio arquivo,
// mas um escape parcial é errado como padrão e não custa nada consertar.
const escRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function value(src, key) {
  const m = src.match(new RegExp(`'${escRe(key)}':\\s*'((?:[^'\\\\]|\\\\.)*)'`));
  return m ? m[1] : null;
}

const NOVAS = [
  'privacy.s4.signedTerm',
  'privacy.s3.row12.purpose', 'privacy.s3.row12.data', 'privacy.s3.row12.basis',
  'privacy.s6ret.row13.data', 'privacy.s6ret.row13.retention', 'privacy.s6ret.row13.after',
];

test('#2023: as chaves novas existem nos TRÊS dicionários', () => {
  for (const lang of LANGS) {
    const src = dict(lang);
    for (const k of NOVAS) {
      assert.ok(value(src, k), `${lang}: falta ${k}`);
    }
  }
});

test('#2023: a linha dos capítulos patrocinadores não promete mais o que o termo contradiz', () => {
  // O texto tem de separar acompanhamento agregado (patrocinador) de custódia do instrumento
  // (contratante). Sem essa separação, a política nega ao pé da letra a operação.
  for (const lang of LANGS) {
    const v = value(dict(lang), 'privacy.s4.chapters');
    assert.ok(v, `${lang}: privacy.s4.chapters sumiu`);
    assert.match(v, /instrument|instrumento/i,
      `${lang}: a linha dos patrocinadores precisa dizer que o instrumento assinado NÃO vai neles`);
  }
});

test('#2023: a custódia é declarada como do capítulo CONTRATANTE, não como terceiro', () => {
  for (const lang of LANGS) {
    const v = value(dict(lang), 'privacy.s4.signedTerm');
    assert.match(v, /PMI Goi[áa]s/, `${lang}: a linha precisa nomear o capítulo contratante`);
    assert.match(v, /restrit|restrict|restring/i, `${lang}: precisa dizer que o acesso é restrito`);
  }
});

test('#2023: a base legal declarada é contrato, e legítimo interesse só para o arquivo', () => {
  for (const lang of LANGS) {
    const v = value(dict(lang), 'privacy.s3.row12.basis');
    assert.match(v, /Art\. 7, V/, `${lang}: falta a base de execução de contrato`);
    assert.match(v, /Art\. 7, IX/, `${lang}: falta o legítimo interesse do arquivo institucional`);
    // Consentimento seria ERRADO aqui: criaria direito de revogação sobre obrigação contratual
    // documental. Se alguém "corrigir" para consentimento, o guard morde.
    assert.doesNotMatch(v, /consentimento|consent|consentimiento/i,
      `${lang}: consentimento não é a base — a via do contrato não é revogável pelo signatário`);
  }
});

test('#2023: a retenção declarada é a mesma do voluntário, e é EXEQUÍVEL', () => {
  for (const lang of LANGS) {
    const src = dict(lang);
    const nova = value(src, 'privacy.s6ret.row13.retention');
    const volunt = value(src, 'privacy.s6ret.row12.retention');
    assert.equal(nova, volunt,
      `${lang}: a cópia arquivada tem de seguir o MESMO prazo do dado de voluntário (${volunt}), ` +
      `senão a política promete dois ciclos diferentes para o mesmo titular`);
    // "Exclusão do arquivo" e não "anonimização": não se anonimiza um contrato assinado — apaga-se.
    const depois = value(src, 'privacy.s6ret.row13.after');
    assert.match(depois, /exclus|delet|elimina/i,
      `${lang}: o desfecho tem de ser exclusão do arquivo — um instrumento assinado não se anonimiza`);
  }
});

test('#2023: a página RENDERIZA as linhas novas (senão o texto existe e ninguém lê)', () => {
  assert.match(page, /S3_ROWS = \[[^\]]*\b12\b[^\]]*\]/,
    'S3_ROWS não inclui a linha 12 — a finalidade ficaria só no dicionário');
  assert.match(page, /S6_ROWS = \[[^\]]*\b13\b[^\]]*\]/,
    'S6_ROWS não inclui a linha 13 — a retenção ficaria só no dicionário');
  assert.match(page, /privacy\.s4\.signedTerm/,
    'a página não lista a linha de custódia em S4');
});
