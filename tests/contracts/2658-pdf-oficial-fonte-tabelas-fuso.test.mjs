/**
 * #2658 — guard ESTÁTICO do PDF oficial da cadeia de ratificação (ChainPDFDocument.tsx) e do DOCX.
 *
 * O QUE ESTE GUARD AFIRMA (o teste de fidelidade, 2658-pdf-oficial-fidelidade.test.mjs, mede o
 * efeito no PDF gerado; este amarra o mecanismo no código):
 *   A. a fonte Unicode auto-hospedada é registrada com os quatro estilos, e os arquivos e a
 *      licença existem em public/fonts/dejavu;
 *   B. o estilo-base da página usa essa família, e nenhum estilo volta a pedir Helvetica;
 *   C. linha e célula de tabela não têm wrap={false} (era o que empurrava a linha inteira para a
 *      página seguinte ou a cortava), e o cabeçalho do topo é `fixed`;
 *   D. o formatador de data usa timeZone 'America/Sao_Paulo' e acrescenta o rótulo, e as duas
 *      exportações (PDF e DOCX) passam por ele, sem toLocale* solto.
 *
 * Asserções amarram CONDIÇÃO ao RESULTADO dentro do bloco que decide, com comentários mascarados.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => maskJsComments(readFileSync(resolve(ROOT, p), 'utf8'));
const doc = read('src/components/governance/ChainPDFDocument.tsx');
const docx = read('src/components/governance/ChainDocxExportIsland.tsx');
const time = read('src/components/governance/brasiliaTime.ts');

/** Trecho entre duas âncoras (a segunda é a declaração seguinte no arquivo). */
function between(src, a, b) {
  const i = src.indexOf(a);
  const j = src.indexOf(b, i + a.length);
  assert.ok(i !== -1 && j !== -1, `âncoras ausentes: ${a} / ${b}`);
  return src.slice(i, j);
}

/** Recorta do início de `start` até o fechamento balanceado do primeiro `open` depois dele. */
function block(src, start, open = '{', close = '}') {
  const at = src.indexOf(start);
  assert.notEqual(at, -1, `âncora ausente: ${start}`);
  const from = src.indexOf(open, at);
  let depth = 0;
  for (let i = from; i < src.length; i += 1) {
    if (src[i] === open) depth += 1;
    else if (src[i] === close && --depth === 0) return src.slice(at, i + 1);
  }
  throw new Error(`bloco sem fechamento: ${start}`);
}

test('A. Font.register da DejaVu Sans auto-hospedada, quatro estilos, arquivos e licença', () => {
  assert.match(doc, /export const PDF_FONT_FAMILY = 'DejaVuSans';/);
  assert.match(doc, /const PDF_FONT_DIR = '\/fonts\/dejavu\/';/);
  const reg = block(doc, 'Font.register(', '(', ')');
  assert.match(reg, /family:\s*PDF_FONT_FAMILY/);
  const variants = [
    ['DejaVuSans.ttf', 'normal', 'normal'],
    ['DejaVuSans-Bold.ttf', 'bold', 'normal'],
    ['DejaVuSans-Oblique.ttf', 'normal', 'italic'],
    ['DejaVuSans-BoldOblique.ttf', 'bold', 'italic'],
  ];
  for (const [file, weight, style] of variants) {
    const re = new RegExp(`\\{\\s*src:\\s*fontSrc\\('${file.replace('.', '\\.')}'\\),\\s*fontWeight:\\s*'${weight}',\\s*fontStyle:\\s*'${style}'\\s*\\}`);
    assert.match(reg, re, `variante ${file} (${weight}/${style}) não registrada`);
    assert.ok(existsSync(resolve(ROOT, 'public/fonts/dejavu', file)), `public/fonts/dejavu/${file} ausente`);
  }
  assert.ok(existsSync(resolve(ROOT, 'public/fonts/dejavu/LICENSE')), 'licença da fonte ausente');
  // A fonte é buscada pelo navegador contra o origin, como o logo (connect-src 'self').
  assert.match(between(doc, 'const fontSrc', 'Font.register('), /new URL\(PDF_FONT_DIR \+ file, window\.location\.href\)\.href/);
});

test('B. o estilo-base da página usa a família embutida; Helvetica não volta', () => {
  const styles = block(doc, 'const styles = StyleSheet.create(', '(', ')');
  assert.match(styles, /\bpage:\s*\{[^}]*fontFamily:\s*PDF_FONT_FAMILY[^}]*\}/);
  assert.doesNotMatch(doc, /fontFamily:\s*'Helvetica/);
});

test('C. linha e célula de tabela quebram entre páginas; cabeçalho do topo repete', () => {
  const table = between(doc, 'function renderTable(', 'function renderNode(');
  const row = table.slice(table.indexOf('<View\n          key={`r-'), table.indexOf('{row.cells.map'));
  assert.ok(row.length > 0, 'elemento da linha não encontrado');
  assert.doesNotMatch(row, /wrap=\{false\}/, 'linha de tabela com wrap={false}');
  assert.match(row, /fixed=\{ri < headerRows\}/, 'cabeçalho do topo não é fixed');
  const cell = table.slice(table.indexOf('{row.cells.map'));
  assert.doesNotMatch(cell, /wrap=\{false\}/, 'célula de tabela com wrap={false}');
  // headerRows conta só as linhas de cabeçalho do TOPO
  assert.match(table, /const leadingHeaderCount = n\.rows\.findIndex\(\(r\) => !r\.isHeader\);/);
  // blockquote e gate de assinaturas também não podem ser atômicos (perdiam o que passasse de 1 página)
  assert.match(doc, /<View key=\{`bq-\$\{i\}`\} style=\{styles\.blockquoteWrapper\}>/);
  assert.match(doc, /<View key=\{gate\.kind\} style=\{styles\.gateBlock\}>/);
});

test('C2. token longo (URL) ganha pontos de quebra; palavra comum não', () => {
  const fn = block(doc, 'export function splitLongToken(');
  assert.match(fn, /if \(word\.length <= LONG_TOKEN\) return \[word\];/);
  assert.match(fn, /if \('\/\.\?&=_#'\.includes\(ch\) \|\| current\.length >= LONG_TOKEN_CHUNK\) \{\s*parts\.push\(current\);/);
  assert.match(doc, /Font\.registerHyphenationCallback\(splitLongToken\);/);
});

test('D. data em America/Sao_Paulo com rótulo, usada pelo PDF e pelo DOCX', () => {
  assert.match(time, /export const BRASILIA_TIME_ZONE = 'America\/Sao_Paulo';/);
  assert.match(time, /export const BRASILIA_LABEL = 'horário de Brasília';/);
  const fmt = block(time, 'export function fmtBrasilia(');
  assert.match(fmt, /const text = d\.toLocaleString\('pt-BR', \{[^}]*timeZone: BRASILIA_TIME_ZONE,[^}]*\}\);/);
  assert.match(fmt, /return `\$\{text\} \(\$\{BRASILIA_LABEL\}\)`;/);
  assert.match(doc, /const fmtDate = fmtBrasilia;/);
  assert.doesNotMatch(doc, /toLocale(Date|Time)?String/, 'PDF formata data fora do fmtBrasilia');
  assert.match(docx, /Lacrado em: \$\{escapeHtml\(fmtBrasilia\(data\.version\.locked_at\)\)\}/);
  assert.match(docx, /Cadeia aberta em: \$\{escapeHtml\(fmtBrasilia\(data\.opened_at\)\)\}/);
  assert.doesNotMatch(docx, /toLocale(Date|Time)?String/, 'DOCX formata data fora do fmtBrasilia');
});
