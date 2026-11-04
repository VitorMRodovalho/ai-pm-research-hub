/**
 * Contract: #2393, fatia A4 (ADR-0134) — Minhas vagas no alfa da 76080, pelo que a auditoria da jornada achou.
 *
 *   L5: a faixa "Próximo passo" diz ao líder o que fazer agora;
 *   L3: no celular, cada candidatura é um cartão com o botão visível (a tabela fica do md para cima);
 *   L1, L2: "Outras informações" não repete uma resposta já mostrada nem lista campo vazio que a vaga não perguntou;
 *   L7: o detalhe não mostra o ciclo (D27: a vaga fica no ciclo 4, e a tela fala do período);
 *   R2: sem o e-mail, que o banco não devolve na candidatura piloto, a tela diz onde ele está;
 *   L9: a filiação declarada não aparece duas vezes.
 * Camada S (estática): cada asserção casa a condição com o resultado no trecho que decide.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const PAGINA = readFileSync(resolve(ROOT, 'src/pages/minhas-vagas.astro'), 'utf8');
const S = maskJsComments(PAGINA).replace(/\s+/g, ' ');

test('#2393j L5: a faixa "Próximo passo" está na entrada da tela', () => {
  assert.match(S, /<\/header> <!-- #2393 A4 \(L5\)[^>]*--> <div id="mv-next-step" class="[^"]*">\{MV_I18N\.nextStep\}<\/div>/, 'a faixa saiu ou mudou de lugar');
  assert.match(S, /nextStep: t\('myOpenings\.nextStep', lang\),/, 'o texto da faixa não chega à tela');
});

test('#2393j L3: no celular, cartões com o botão; a tabela só do md para cima', () => {
  const ini = S.indexOf('<ul class="md:hidden ');
  assert.ok(ini >= 0, 'os cartões do celular sumiram');
  const cartao = S.slice(ini, S.indexOf('</ul>', ini));
  assert.match(cartao,
    /^<ul class="md:hidden [^"]*">\$\{g\.itens\.map\(\(a\) => ` <li [^>]*> <div class="min-w-0"> <p class="font-semibold text-navy">\$\{esc\(a\.applicant_name\)\}<\/p> .*<button type="button" data-mv-app="\$\{esc\(a\.application_id\)\}"/,
    'o cartão do celular perdeu o nome ou o botão');
  assert.match(S, /<div class="hidden md:block overflow-x-auto"> <table class="w-full text-sm">/, 'a tabela voltou a aparecer no celular');
});

test('#2393j L1 e L2: "Outras informações" sem repetição e sem campo vazio que a vaga não perguntou', () => {
  assert.match(S, /const jaMostrados = new Set\(\[\.\.\.usados\]\.map\(\(campo\) => texto\(data\[campo\]\)\)\.filter\(Boolean\)\);/,
    'os textos já mostrados deixaram de vir das respostas da vaga');
  assert.match(S,
    /const outros = CAMPOS_OUTROS\.filter\(\(\[campo\]\) => !usados\.has\(campo\)\) \.filter\(\(\[campo\]\) => texto\(data\[campo\]\) !== '' && !jaMostrados\.has\(texto\(data\[campo\]\)\)\) \.map\(/,
    'a lista de outras informações voltou a repetir resposta ou a mostrar campo vazio');
});

test('#2393j L7: o detalhe não mostra o ciclo', () => {
  const cab = S.slice(S.indexOf('<h2 class="text-xl font-bold text-navy mt-1">'), S.indexOf('${esc(I.sectionContact)}'));
  assert.ok(cab.length > 0, 'o cabeçalho do detalhe não foi encontrado');
  assert.doesNotMatch(cab, /cycle_code|fieldCycle/, 'o ciclo voltou ao cabeçalho do detalhe');
});

test('#2393j R2: sem e-mail, a tela diz onde ele está; contato vazio é "Não informado"', () => {
  assert.match(S, /const temEmail = Boolean\(data\.email\);/, 'a condição do e-mail deixou de vir do dado');
  assert.match(S,
    /\$\{temEmail \? linha\(I\.fieldEmail, texto\(data\.email\)\) : `<div class="mb-3"><p [^>]*>\$\{esc\(I\.fieldEmail\)\}<\/p><p class="text-sm text-\[var\(--text-muted\)\]">\$\{esc\(I\.emailHidden\)\}<\/p><\/div>`\}/,
    'o e-mail ausente deixou de explicar onde ele está');
  for (const v of ['linkedin', 'credly'])
    assert.match(S, new RegExp(`\\$\\{esc\\(${v}\\)\\}</a>\` : \`<span class="text-\\[var\\(--text-muted\\)\\]">\\$\\{esc\\(I\\.notInformed\\)\\}</span>\``),
      `${v} vazio voltou a dizer "Sem resposta"`);
});

test('#2393j L9: a filiação declarada sai do Perfil quando já é resposta da vaga', () => {
  assert.match(S, /\$\{usados\.has\('chapter_affiliation'\) \? '' : linha\(I\.fieldChapterAffiliation, texto\(data\.chapter_affiliation\)\)\}/,
    'a filiação declarada voltou a aparecer duas vezes');
});

test('#2393j: as 3 chaves novas existem nos 3 dicionários e chegam à tela', () => {
  for (const k of ['nextStep', 'emailHidden', 'notInformed']) {
    assert.match(S, new RegExp(`${k}: t\\('myOpenings\\.${k}', lang\\),`), `${k} não chega à tela`);
    for (const lang of ['pt-BR', 'en-US', 'es-LATAM'])
      assert.match(readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8'), new RegExp(`\\n  'myOpenings\\.${k}': '[^'\\n]{8,}`), `${lang}: falta ${k}`);
  }
});
