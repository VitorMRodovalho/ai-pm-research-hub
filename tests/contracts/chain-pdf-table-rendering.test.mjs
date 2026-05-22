/**
 * Forward-defense: Issue #273 — ChainPDFDocument supports <table> rendering.
 *
 * Origin: p220 session (2026-05-22), TAP CPMAI Ciclo 3 audit revealed 25 tables
 * in the document content would be dropped from the official PDF export because
 * ChainPDFDocument.tsx parseHtml only matched (h2|h3|h4|p|li). All structured
 * tabular data (header table, partes interessadas, equipe básica, orçamento,
 * critérios de sucesso, riscos, pool instrutores, análise competitiva) was
 * invisible in the downloadable PDF while rendering fine on the HTML page.
 *
 * Fix (p220): parser uses a masterRegex that matches BOTH <table> blocks AND
 * h2/h3/h4/p/li blocks in document order. Tables consume their inner content
 * so the block matcher cannot double-extract <p>/<li> nested in cells.
 * parseTable extracts rows (<tr>) and cells (<th>/<td>), classifying rows as
 * header when either inside <thead> or starting with a <th> cell.
 *
 * Cross-ref:
 *   - src/components/governance/ChainPDFDocument.tsx (parser + renderer)
 *   - src/components/governance/ChainPDFExportIsland.tsx (caller)
 *   - GH #273 (filed during p220 — Welma TAP audit)
 *
 * Static-only bundle (no DB env, no @react-pdf/renderer mount required):
 *   1. Table types declared (TableCell + TableRow + 'table' node variant)
 *   2. parseTable function defined
 *   3. masterRegex matches <table> tag explicitly
 *   4. Header row detection via <thead> OR <th> cell
 *   5. renderTable function uses View with tableContainer style
 *   6. Style sheet has table styles (container/row/headerRow/cell/cellText/cellHeader)
 *   7. Rows kept atomic via wrap=false (so rows don't split across pages)
 *   8. Empty cell rows filtered out (defensive)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SRC = readFileSync(
  resolve(process.cwd(), 'src/components/governance/ChainPDFDocument.tsx'),
  'utf8',
);

test('#273: TableCell + TableRow types declared', () => {
  assert.match(SRC, /type\s+TableCell\s*=\s*\{[^}]*segments:\s*Segment\[\][^}]*isHeader:\s*boolean[^}]*\}/,
    'TableCell type must declare segments + isHeader');
  assert.match(SRC, /type\s+TableRow\s*=\s*\{[^}]*cells:\s*TableCell\[\][^}]*isHeader:\s*boolean[^}]*\}/,
    'TableRow type must declare cells + isHeader');
});

test('#273: Node union includes table variant', () => {
  assert.match(SRC, /type\s+Node\s*=[\s\S]*?type:\s*['"]table['"][\s\S]*?rows:\s*TableRow\[\]/,
    'Node union must include { type: "table", rows: TableRow[], inQuote: boolean } variant');
});

test('#273: parseTable function declared', () => {
  assert.match(SRC, /function\s+parseTable\(tableInner:\s*string\):\s*TableRow\[\]/,
    'parseTable(tableInner: string): TableRow[] must be declared');
});

test('#273: parseTable detects header rows via <thead> OR <th> cell', () => {
  // Two distinct mechanisms must be present
  assert.match(SRC, /<thead\[?\^?\]?\*?>/i,
    'parseTable must reference <thead> tag detection');
  assert.match(SRC, /isHeader:\s*inThead\s*\|\|\s*rowHasTh/,
    'Row isHeader must be inThead OR rowHasTh (cell-level th detection)');
});

test('#273: parseHtml uses masterRegex matching both tables and blocks', () => {
  assert.match(SRC, /const\s+masterRegex\s*=/,
    'parseHtml must declare a masterRegex constant');
  assert.match(SRC, /masterRegex[\s\S]{0,200}<table/,
    'masterRegex must reference <table> tag');
  assert.match(SRC, /masterRegex[\s\S]{0,200}h\[234\]\|p\|li/,
    'masterRegex must include (h[234]|p|li) block alternative');
});

test('#273: parseHtml dispatches table vs block via masterRegex groups', () => {
  // Code structure: branch on match[1] (table inner) vs match[2] (block tag)
  assert.match(SRC, /if\s*\(\s*match\[1\]\s*!==\s*undefined\s*\)/,
    'parseHtml must check match[1] (table inner group) before block path');
  assert.match(SRC, /type:\s*['"]table['"]\s*,\s*rows\s*,\s*inQuote:/,
    'parseHtml table branch must push a { type: "table", rows, inQuote } node');
});

test('#273: renderTable function uses View + table styles', () => {
  assert.match(SRC, /function\s+renderTable\(/,
    'renderTable function must be declared');
  // Container, row, cell, header styles must be referenced in render path
  assert.match(SRC, /styles\.tableContainer/, 'tableContainer style applied');
  assert.match(SRC, /styles\.tableRow/, 'tableRow style applied');
  assert.match(SRC, /styles\.tableHeaderRow/, 'tableHeaderRow style applied (header background)');
  assert.match(SRC, /styles\.tableCell\b/, 'tableCell style applied');
  // Header text uses tableCellHeader; body uses tableCellText
  assert.match(SRC, /styles\.tableCellHeader/, 'tableCellHeader style applied for header rows');
  assert.match(SRC, /styles\.tableCellText/, 'tableCellText style applied for body rows');
});

test('#273: rows kept atomic via wrap={false}', () => {
  // Prevents a row from splitting across pages — crucial for readability
  assert.match(SRC, /wrap=\{false\}/,
    'renderTable must apply wrap={false} on each row to prevent mid-row page breaks');
});

test('#273: StyleSheet defines all table-related entries', () => {
  for (const styleName of ['tableContainer', 'tableRow', 'tableHeaderRow', 'tableCell', 'tableCellText', 'tableCellHeader']) {
    const re = new RegExp(`${styleName}\\s*:\\s*\\{`);
    assert.match(SRC, re, `StyleSheet must declare ${styleName}`);
  }
});

test('#273: renderNode dispatches table type before falling to block branch', () => {
  assert.match(SRC, /if\s*\(\s*n\.type\s*===\s*['"]table['"]\s*\)\s*\{\s*return\s+renderTable/,
    'renderNode must check n.type === "table" first and delegate to renderTable');
});

test('#273: empty table rows filtered out (defensive)', () => {
  // parseTable should continue past rows with 0 cells (avoids empty <View> in PDF)
  assert.match(SRC, /if\s*\(\s*cells\.length\s*===\s*0\s*\)\s*continue;/,
    'parseTable must skip rows with zero cells');
});
