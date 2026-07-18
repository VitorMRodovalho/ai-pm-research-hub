/**
 * #1402 — MCP tool annotations on the /semantic surface (Refs #1383).
 *
 * The standard MCP annotation hints (readOnlyHint / destructiveHint / idempotentHint / openWorldHint)
 * are what an MCP HOST reads to badge a read-only tool or warn a user before a destructive call —
 * distinct from our own `audit` envelope block (pii_level / permission / gate_checked), which the
 * host does not read. Before #1402 the /semantic surface set ZERO annotations.
 *
 * This guard proves, as a pure static check over supabase/functions/nucleo-mcp/index.ts (no network,
 * no DB — runs in every offline baseline):
 *   1. Every tool actually registered inside registerSemanticTools() has an entry in the
 *      SEMANTIC_TOOL_ANNOTATIONS map (no drift in either direction — a new semantic tool without an
 *      annotation entry fails here, matching the runtime console.warn + no-op).
 *   2. Every annotation carries all four boolean hints.
 *   3. openWorldHint is false for ALL tools (server invariant: only ever touches its own Núcleo DB/Drive).
 *   4. Read-only tools: readOnlyHint true + destructiveHint false. Write tools: readOnlyHint false.
 *   5. The known-destructive set (action set includes an ADR-0018 confirm-gated irreversible/removal
 *      verb) carries destructiveHint true; a read-only tool never does.
 *   6. The wrapper is wired (applySemanticAnnotations called at the top of registerSemanticTools).
 *
 * Cross-ref: EPIC #1383, docs/reference/SEMANTIC_TOOL_CATALOG.md, .claude/rules/mcp.md, SDK 1.29.0
 * ToolAnnotations (RegisteredTool.update({annotations})).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

/** Isolate registerSemanticTools(...) — its tools are the only ones this guard governs. */
function semanticBody(src) {
  const start = src.indexOf('function registerSemanticTools(');
  assert.ok(start !== -1, 'registerSemanticTools() not found');
  const end = src.indexOf('// #1377 — /actions overflow surface.', start);
  assert.ok(end !== -1, 'end sentinel (/actions comment) not found after registerSemanticTools');
  return src.slice(start, end);
}

/** All tool names registered inside registerSemanticTools(). */
function registeredSemanticTools(body) {
  const re = /mcp\.tool\(\s*\n?\s*"([a-zA-Z0-9_]+)"/g;
  const names = [];
  let m;
  while ((m = re.exec(body)) !== null) names.push(m[1]);
  return names;
}

/** Parse the SEMANTIC_TOOL_ANNOTATIONS literal into { name -> alias }. */
function annotationMap(src) {
  const start = src.indexOf('const SEMANTIC_TOOL_ANNOTATIONS: Record<string, SemanticAnnotation> = {');
  assert.ok(start !== -1, 'SEMANTIC_TOOL_ANNOTATIONS map not found');
  const end = src.indexOf('\n};', start);
  assert.ok(end !== -1, 'end of SEMANTIC_TOOL_ANNOTATIONS map not found');
  const block = src.slice(start, end);
  const re = /([a-zA-Z0-9_]+):\s*(SEM_RO|SEM_WRITE_IDEMPOTENT|SEM_WRITE|SEM_DESTRUCTIVE)\b/g;
  const map = {};
  let m;
  while ((m = re.exec(block)) !== null) map[m[1]] = m[2];
  return map;
}

/** Parse the SEM_* alias definitions into { alias -> {hint:bool} }. */
function aliasDefs(src) {
  const defs = {};
  for (const alias of ['SEM_RO', 'SEM_WRITE', 'SEM_WRITE_IDEMPOTENT', 'SEM_DESTRUCTIVE']) {
    const re = new RegExp(`const ${alias}: SemanticAnnotation = \\{([^}]+)\\}`);
    const m = SRC.match(re);
    assert.ok(m, `alias ${alias} not defined`);
    const obj = {};
    for (const pair of m[1].split(',')) {
      const mm = pair.match(/(\w+):\s*(true|false)/);
      if (mm) obj[mm[1]] = mm[2] === 'true';
    }
    defs[alias] = obj;
  }
  return defs;
}

const BODY = semanticBody(SRC);
const REGISTERED = registeredSemanticTools(BODY);
const MAP = annotationMap(SRC);
const ALIASES = aliasDefs(SRC);
const HINTS = ['readOnlyHint', 'destructiveHint', 'idempotentHint', 'openWorldHint'];

// Ground-truth read-only + destructive sets (independent of the map, so a mis-classification is caught).
const READ_ONLY = new Set([
  'get_my_context', 'search_nucleo_knowledge', 'get_board_or_initiative_context', 'get_operational_status',
  'card_search', 'card_get', 'board_overview', 'platform_context', 'portfolio_report',
  'member_search', 'member_get', 'initiative_roster', 'initiative_directory', 'initiative_report', 'my_status',
  'event_search', 'attendance_report', 'selection_dashboard', 'application_get', 'document_get',
  'comms_report', 'gamification_report', 'admin_dashboard', 'audit_log',
]);
const DESTRUCTIVE = new Set([
  'card_write', 'engagement_write', 'event_write', 'member_lifecycle',
  'selection_decide', 'document_version_write', 'ip_exclusion', 'lgpd_admin',
]);

test('#1402: the semantic surface still has exactly 52 registered tools', () => {
  assert.equal(REGISTERED.length, 52, `expected 52 semantic tools, got ${REGISTERED.length}`);
});

test('#1402: applySemanticAnnotations is wired into registerSemanticTools', () => {
  assert.match(BODY, /applySemanticAnnotations\(mcp\)/, 'wrapper not called at top of registerSemanticTools');
  assert.match(SRC, /reg\.update\(\{ annotations: ann \}\)/, 'annotations must be applied via RegisteredTool.update');
});

test('#1402: every registered semantic tool has an annotation entry (no missing)', () => {
  const missing = REGISTERED.filter((t) => !MAP[t]);
  assert.equal(missing.length, 0, `semantic tools without an annotation entry: ${missing.join(', ')}`);
});

test('#1402: the annotation map has no stale entries (no extra)', () => {
  const reg = new Set(REGISTERED);
  const extra = Object.keys(MAP).filter((t) => !reg.has(t));
  assert.equal(extra.length, 0, `annotation entries for non-registered tools: ${extra.join(', ')}`);
});

test('#1402: every alias carries all four boolean hints', () => {
  for (const [alias, obj] of Object.entries(ALIASES)) {
    for (const h of HINTS) {
      assert.equal(typeof obj[h], 'boolean', `${alias}.${h} must be a boolean`);
    }
  }
});

test('#1402: openWorldHint is false for ALL tools (server-scoped invariant)', () => {
  for (const t of REGISTERED) {
    assert.equal(ALIASES[MAP[t]].openWorldHint, false, `${t}: openWorldHint must be false`);
  }
});

test('#1402: read-only tools are readOnlyHint:true + destructiveHint:false', () => {
  for (const t of READ_ONLY) {
    assert.ok(MAP[t], `read-only tool ${t} not in map`);
    const a = ALIASES[MAP[t]];
    assert.equal(a.readOnlyHint, true, `${t}: expected readOnlyHint true`);
    assert.equal(a.destructiveHint, false, `${t}: read-only tool must not be destructive`);
  }
});

test('#1402: destructive tools are readOnlyHint:false + destructiveHint:true', () => {
  for (const t of DESTRUCTIVE) {
    assert.ok(MAP[t], `destructive tool ${t} not in map`);
    const a = ALIASES[MAP[t]];
    assert.equal(a.readOnlyHint, false, `${t}: destructive tool cannot be read-only`);
    assert.equal(a.destructiveHint, true, `${t}: expected destructiveHint true`);
  }
});

test('#1402: write tools (not read-only) are readOnlyHint:false', () => {
  for (const t of REGISTERED) {
    if (READ_ONLY.has(t)) continue;
    assert.equal(ALIASES[MAP[t]].readOnlyHint, false, `${t}: write tool must be readOnlyHint false`);
  }
});

test('#1402: no tool is both readOnly and destructive (mutually exclusive)', () => {
  for (const t of REGISTERED) {
    const a = ALIASES[MAP[t]];
    assert.ok(!(a.readOnlyHint && a.destructiveHint), `${t}: cannot be both readOnly and destructive`);
  }
});
