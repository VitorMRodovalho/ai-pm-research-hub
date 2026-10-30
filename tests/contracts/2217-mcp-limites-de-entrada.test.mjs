// tests/contracts/2217-mcp-limites-de-entrada.test.mjs
//
// #2217 (30/10/2026) — dois limites de entrada da nucleo-mcp que a subida do SDK 1.30.0 -> 1.32.2 e do
// zod 4.3.6 -> 4.6.7 ligou, e que nada mais impede de desligar em silêncio:
//
// 1. `maxToolInputElements` nas três superfícies (/mcp, /semantic, /actions). A opção é do SDK 1.32.0 e vem
//    DESLIGADA por padrão. Ligada, uma chamada de ferramenta com mais elementos que o teto volta `isError`
//    antes de o zod validar. Medido num run local da EF: 10.001 elementos em `list_initiative_events`
//    voltaram "more than the maximum of 10000 elements" na 1.32.2 e chegaram ao handler na 1.30.0.
// 2. O piso de segurança do zod. GHSA-mrhx-c7xc-m3w5 (high): zod < 4.6.6 pode esgotar memória ao validar
//    coleção grande com restrição, e esta EF valida argumento vindo de cliente MCP externo.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(process.cwd(), 'supabase/functions');
const EF = readFileSync(join(ROOT, 'nucleo-mcp/index.ts'), 'utf8');
const SURFACES = ['nucleo-ia-hub', 'nucleo-ia-semantic', 'nucleo-ia-actions'];
const ZOD_FLOOR = [4, 6, 6];

/** Cada `new McpServer(...)` com o texto dos argumentos, lido do código com comentários mascarados. */
function servers(src) {
  const code = maskJsComments(src);
  const out = [];
  for (const m of code.matchAll(/new McpServer\(/g)) {
    let i = m.index + m[0].length, depth = 1;
    while (i < code.length && depth > 0) {
      if (code[i] === '(') depth++;
      else if (code[i] === ')') depth--;
      i++;
    }
    const args = code.slice(m.index + m[0].length, i - 1);
    const name = (args.match(/name:\s*"([^"]+)"/) || [])[1] ?? null;
    out.push({ name, args });
  }
  return out;
}

/** Valor do teto, se declarado como literal numérico finito. */
function cap(src) {
  const m = maskJsComments(src).match(/const MAX_TOOL_INPUT_ELEMENTS\s*=\s*([0-9_]+)\s*;/);
  return m ? Number(m[1].replace(/_/g, '')) : null;
}

function capFindings(src) {
  const findings = [];
  const v = cap(src);
  if (!(Number.isFinite(v) && v >= 1)) findings.push(`MAX_TOOL_INPUT_ELEMENTS não é um número finito >= 1 (${v})`);
  const all = servers(src);
  for (const s of all) {
    if (!/,\s*\{[^}]*\bmaxToolInputElements:\s*MAX_TOOL_INPUT_ELEMENTS\b[^}]*\}\s*$/.test(s.args)) {
      findings.push(`new McpServer(${s.name ?? '?'}) sem maxToolInputElements: MAX_TOOL_INPUT_ELEMENTS`);
    }
  }
  for (const name of SURFACES) {
    const n = all.filter((s) => s.name === name).length;
    if (n !== 1) findings.push(`superfície ${name}: ${n} construção(ões), esperada 1`);
  }
  return findings;
}

test('#2217: as três superfícies constroem o McpServer com o teto de elementos', (t) => {
  t.diagnostic(`MAX_TOOL_INPUT_ELEMENTS = ${cap(EF)}; ${servers(EF).length} construção(ões) de McpServer`);
  assert.deepEqual(capFindings(EF), []);
});

const CAP_MUTATIONS = [
  ['sem o teto em /actions', (s) => s.replace(
    /(new McpServer\(\{ name: "nucleo-ia-actions"[^}]*\}), \{ maxToolInputElements: MAX_TOOL_INPUT_ELEMENTS \}\)/, '$1)')],
  ['teto só num comentário em /mcp', (s) => s.replace(
    /(new McpServer\(\{ name: "nucleo-ia-hub"[^}]*\}), \{ maxToolInputElements: MAX_TOOL_INPUT_ELEMENTS \}\)/,
    '$1 /* , { maxToolInputElements: MAX_TOOL_INPUT_ELEMENTS } */)')],
  ['teto infinito', (s) => s.replace(/const MAX_TOOL_INPUT_ELEMENTS\s*=\s*[0-9_]+;/, 'const MAX_TOOL_INPUT_ELEMENTS = Infinity;')],
  ['quarta superfície sem teto', (s) => s.replace(
    'Deno.serve(', 'const extra = new McpServer({ name: "nucleo-ia-extra", version: "0.0.1" });\nDeno.serve(')],
];

for (const [label, mutate] of CAP_MUTATIONS) {
  test(`#2217: mutação reprova — ${label}`, () => {
    const mutated = mutate(EF);
    assert.notEqual(mutated, EF, 'a mutação não mudou o texto');
    assert.notDeepEqual(capFindings(mutated), []);
  });
}

// ── piso do zod ──────────────────────────────────────────────────────────────────────────────────

function tsFiles(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return f === 'node_modules' ? [] : tsFiles(p);
    return /\.(ts|tsx|mjs|js)$/.test(f) ? [p] : [];
  });
}

function zodBelowFloor(files) {
  const low = [];
  for (const [path, src] of files) {
    for (const m of src.matchAll(/["']npm:zod@(\d+)\.(\d+)\.(\d+)/g)) {
      const v = m.slice(1, 4).map(Number);
      const below = v[0] !== ZOD_FLOOR[0] ? v[0] < ZOD_FLOOR[0]
        : v[1] !== ZOD_FLOOR[1] ? v[1] < ZOD_FLOOR[1] : v[2] < ZOD_FLOOR[2];
      if (below) low.push(`${path.slice(ROOT.length + 1)}: zod ${v.join('.')}`);
    }
  }
  return low;
}

test('#2217: nenhuma Edge Function importa zod abaixo de 4.6.6 (GHSA-mrhx-c7xc-m3w5)', (t) => {
  const files = tsFiles(ROOT).map((p) => [p, readFileSync(p, 'utf8')]);
  const pins = files.flatMap(([, s]) => [...s.matchAll(/["']npm:zod@[^"']+/g)]).length;
  t.diagnostic(`${pins} import(s) de npm:zod em ${files.length} arquivo(s)`);
  assert.ok(pins >= 1, 'nenhum import de npm:zod achado: o recorte não está lendo o diretório certo');
  assert.deepEqual(zodBelowFloor(files), []);
});

test('#2217: mutação reprova — zod 4.6.5, 4.3.6 e 3.25.0 ficam abaixo do piso; 4.6.6 e 5.0.0 passam', () => {
  const at = (v) => [[join(ROOT, 'x/index.ts'), `import { z } from "npm:zod@${v}";`]];
  for (const v of ['4.6.5', '4.3.6', '3.25.0']) assert.equal(zodBelowFloor(at(v)).length, 1, v);
  for (const v of ['4.6.6', '4.6.7', '5.0.0']) assert.equal(zodBelowFloor(at(v)).length, 0, v);
});
