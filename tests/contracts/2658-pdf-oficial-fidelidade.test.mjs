/**
 * #2658 — FIDELIDADE do PDF oficial da cadeia de ratificação, medida no PDF GERADO.
 *
 * O guard estático (2658-pdf-oficial-fonte-tabelas-fuso.test.mjs) lê o código; este renderiza o
 * componente real (ChainPDFDocument.tsx) com uma fixture SINTÉTICA, extrai o texto do PDF e
 * afirma sobre o que sai, porque é aí que os três defeitos aparecem:
 *   A. a fonte está EMBUTIDA, é a DejaVu Sans, e nenhuma fonte-padrão WinAnsi sobra para o texto;
 *   B. ≥ → ≠ ≈ ① ② ③ ✓ saem como os caracteres originais (com Helvetica, ≥ virava "e");
 *   C. nenhuma linha de tabela perde conteúdo: TODA frase de TODA célula está no PDF, inclusive a
 *      célula mais alta que uma página, e a palavra-sentinela do fim de cada célula também;
 *   D. a URL longa chega inteira (a quebra de linha só acrescenta o hífen de fim de linha), e
 *      nenhum trecho visível passa da margem direita (sem ponto de quebra, a URL era cortada ali);
 *   E. a hora sai em Brasília com rótulo, com o processo rodando em OUTRO fuso.
 *
 * Offline e sem banco: o servidor HTTP é local e só serve public/. Extração por
 * tests/helpers/pdf-text-extract.mjs (node:zlib), sem dependência nova e sem pdftotext no CI.
 */
process.env.TZ = 'Asia/Tokyo'; // UTC+9: se o fuso vier do processo, a hora sai errada

import test from 'node:test';
import assert from 'node:assert/strict';
import { extractPdfText, extractPdfRuns, pdfFonts } from '../helpers/pdf-text-extract.mjs';
import {
  renderChainPdf, CELLS, SYMBOLS, LONG_URL, EXPECTED_SIGNED,
} from '../helpers/chain-pdf-render.mjs';

const { official, draft } = await renderChainPdf();
const rawText = extractPdfText(official);
const draftText = extractPdfText(draft);
// A quebra de linha cai entre quaisquer duas palavras: normaliza espaço antes de procurar frase.
const flat = (t) => t.replace(/\s+/g, ' ');
const text = flat(rawText);

test('A. fonte DejaVu Sans embutida; nenhuma fonte-padrão WinAnsi no texto', () => {
  const fonts = pdfFonts(official);
  assert.equal(fonts.embedded, true, 'o PDF não embute nenhuma fonte TrueType (/FontFile2)');
  const names = fonts.all.map((f) => f.baseFont);
  assert.ok(names.some((n) => /\+DejaVuSans$/.test(n)), `DejaVu Sans regular ausente: ${names}`);
  assert.ok(names.some((n) => /\+DejaVuSans-Bold$/.test(n)), `DejaVu Sans Bold ausente: ${names}`);
  // Courier fica só nos hashes/ids (ASCII). Helvetica/Times não podem sobrar.
  const standard = names.filter((n) => /^(Helvetica|Times)/.test(n));
  assert.deepEqual(standard, [], `fonte-padrão WinAnsi ainda usada: ${standard}`);
});

test('B. símbolos fora do WinAnsi saem como os caracteres originais', () => {
  for (const s of SYMBOLS) assert.ok(text.includes(s), `símbolo ${s} ausente do PDF`);
  assert.ok(text.includes('Quorum ≥75% dos votos; fluxo A → B; valor ≠ zero; custo ≈ 10; etapas ① ② ③'),
    'a frase de símbolos não saiu intacta');
  assert.ok(!text.includes('�'), 'há glifo sem mapeamento Unicode no PDF');
  // ✅ não existe na fonte (emoji colorido): é trocado pelo dingbat equivalente, não some.
  assert.ok(text.includes('conferido ✓ e ✔'), '✅ deveria sair como ✔');
});

test('C. nenhuma linha de tabela perde conteúdo entre páginas', () => {
  let total = 0;
  for (const [tag, n] of CELLS) {
    for (let i = 1; i <= n; i += 1) {
      const id = `Frase ${tag}s${String(i).padStart(2, '0')} descreve`;
      assert.ok(text.includes(id), `frase perdida: ${id}`);
      total += 1;
    }
    assert.ok(text.includes(`fim${tag}sentinela`), `sentinela do fim da célula ${tag} ausente`);
  }
  assert.ok(text.includes('fimtabelasentinela'), 'o parágrafo depois da tabela sumiu');
  assert.equal(total, CELLS.reduce((a, [, n]) => a + n, 0));
});

test('D. a URL longa chega inteira, no corpo e na célula', () => {
  // O react-pdf marca cada quebra dentro de um token com hífen no fim da linha; desfeito isso,
  // a URL tem de aparecer completa. Quebra só acontece em espaço ou nos pontos do splitLongToken.
  const joined = rawText.replace(/-\n/g, '').replace(/\n/g, '');
  const count = joined.split(LONG_URL).length - 1;
  assert.equal(count, 2, `URL longa encontrada ${count} vez(es), esperado 2 (corpo + célula)`);
});

test('D2. nenhum trecho visível ultrapassa a margem direita da página', () => {
  const PAGE_PADDING = 40; // styles.page.padding
  const runs = extractPdfRuns(official).filter((r) => r.inside);
  assert.ok(runs.length > 100, 'extração de trechos vazia: o teste não discrimina');
  const right = runs[0].box[2] - PAGE_PADDING + 0.5;
  const over = runs.filter((r) => r.x1 > right).map((r) => `${r.text.slice(0, 40)}… termina em x=${r.x1.toFixed(1)}`);
  assert.deepEqual(over, [], `trecho além da margem direita (${right.toFixed(1)}): ${over.join(' | ')}`);
});

test('E. hora em Brasília com rótulo, independente do fuso do processo', () => {
  assert.equal(new Date('2026-03-13T16:15:00Z').getHours(), 1, 'o processo não está em UTC+9: o teste não discrimina');
  assert.ok(text.includes(`Cadeia aprovada em ${EXPECTED_SIGNED}`), 'hora da aprovação sem Brasília/rótulo');
  assert.ok(text.includes(`Notificação lida em ${EXPECTED_SIGNED}`), 'hora da notificação sem Brasília/rótulo');
  assert.ok(text.includes(`Gerado em ${EXPECTED_SIGNED}`), 'hora de geração sem Brasília/rótulo');
  assert.ok(flat(draftText).includes(`Rascunho gerado em ${EXPECTED_SIGNED}`), 'rascunho sem Brasília/rótulo');
});
