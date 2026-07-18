/**
 * #1418 — MCP tool annotations on the RAW tool surface (registerTools → /mcp AND /actions).
 *
 * Direct follow-up to #1402 (which annotated only /semantic). The standard MCP annotation hints
 * (readOnlyHint / destructiveHint / idempotentHint / openWorldHint) are what an MCP HOST reads to
 * badge a read-only tool or warn a user before a destructive call — distinct from our own `audit`
 * envelope block, which the host does not read. Before #1418 the raw catalog (consumed live via the
 * `/actions` overflow connector, #1377) set ZERO annotations on its destructive write tail.
 *
 * Unlike the consolidated /semantic tools (multi-action, hand-classified in SEMANTIC_TOOL_ANNOTATIONS),
 * every raw tool is a SINGLE verb, so classification is derived from the tool NAME by classifyRawTool():
 *   - read prefixes + a few explicit reads          → readOnlyHint (SEM_RO)
 *   - irreversible/removal verbs + explicit names    → destructiveHint (SEM_DESTRUCTIVE)
 *   - everything else                                → a plain write (SEM_WRITE)
 *
 * This guard is a pure static check over supabase/functions/nucleo-mcp/index.ts (no network, no DB —
 * runs in every offline baseline). It PARSES the classifier's own rule sets from source and re-derives
 * the classification, so it validates the live tool list against the source's rules (single source of
 * truth). Beyond parity it enforces a destructive-NAME safety net: any live tool whose name carries an
 * irreversible/removal segment MUST classify destructive — so a future `purge_*`/`revoke_*` tool that a
 * prefix rule alone would miss fails CI here, closing the silent-misclassification gap (a false readOnly
 * is the only UNSAFE error — it suppresses a confirmation the user should see).
 *
 * Cross-ref: EPIC #1383, #1402 (semantic annotations), #1377 (/actions overflow), .claude/rules/mcp.md,
 * SDK 1.29.0 ToolAnnotations (RegisteredTool.update({annotations})).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

/** Isolate registerTools(...) — its tools are the RAW catalog this guard governs. */
function registerToolsBody(src) {
  const start = src.indexOf('function registerTools(mcp: McpServer, sb: Sb) {');
  assert.ok(start !== -1, 'registerTools() not found');
  const end = src.indexOf('function buildSemanticError(', start);
  assert.ok(end !== -1, 'end sentinel (buildSemanticError) not found after registerTools');
  return src.slice(start, end);
}

/** All tool names registered inside registerTools() (name may be same line or the next). */
function registeredRawTools(body) {
  const re = /mcp\.tool\(\s*\n?\s*"([a-zA-Z0-9_]+)"/g;
  const names = [];
  let m;
  while ((m = re.exec(body)) !== null) names.push(m[1]);
  return names;
}

/** Parse a `["a_", "b_"]` string-array literal assigned to `const <name>`. */
function parseStringArray(src, constName) {
  const re = new RegExp(`const ${constName}\\s*=\\s*\\[([^\\]]*)\\]`);
  const m = src.match(re);
  assert.ok(m, `${constName} array not found`);
  return [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]);
}

/** Parse a `new Set<string>([...])` literal assigned to `const <name>`. */
function parseStringSet(src, constName) {
  const re = new RegExp(`const ${constName}\\s*=\\s*new Set<string>\\(\\[([^\\]]*)\\]\\)`);
  const m = src.match(re);
  assert.ok(m, `${constName} Set not found`);
  return new Set([...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]));
}

const BODY = registerToolsBody(SRC);
const REGISTERED = registeredRawTools(BODY);

// Rule sets parsed straight from the source under test (so the guard tracks the code, not a copy).
const READ_PREFIXES = parseStringArray(SRC, 'RAW_READ_PREFIXES');
const DESTRUCTIVE_PREFIXES = parseStringArray(SRC, 'RAW_DESTRUCTIVE_PREFIXES');
const READ_NAMES = parseStringSet(SRC, 'RAW_READ_NAMES');
const DESTRUCTIVE_NAMES = parseStringSet(SRC, 'RAW_DESTRUCTIVE_NAMES');

/** Mirror of index.ts classifyRawTool() — must stay byte-equivalent in ordering to the source. */
function classify(name) {
  if (DESTRUCTIVE_NAMES.has(name)) return 'DESTRUCTIVE';
  if (READ_NAMES.has(name)) return 'RO';
  if (DESTRUCTIVE_PREFIXES.some((p) => name.startsWith(p))) return 'DESTRUCTIVE';
  if (READ_PREFIXES.some((p) => name.startsWith(p))) return 'RO';
  return 'WRITE';
}

// Any tool name carrying one of these as a `_`-delimited segment is IRREVERSIBLE and must be
// classified destructive — independent of the prefix rules, so a new destructive verb can't slip
// through as a plain write. Deliberately excludes reversible verbs (cancel_/dismiss_/restore_).
const DESTRUCTIVE_SIGNAL = /(^|_)(delete|deletion|remove|purge|destroy|offboard|revoke|drop|withdraw|leave|archive|unlink)(_|$)/;

// Curated ground truth — a mis-edit of the rule sets that still parses is caught here.
const GROUND_TRUTH = {
  // reads
  get_my_profile: 'RO', list_boards: 'RO', search_members: 'RO', exec_cycle_report: 'RO',
  explain_pending_authority: 'RO', wiki_health_report: 'RO', knowledge_search_text: 'RO',
  member_list_emails: 'RO', member_resolve_email: 'RO', verify_certificate: 'RO', export_audit_log_csv: 'RO',
  // destructive (irreversible/removal — all in the /actions write tail or a delete verb)
  offboard_member: 'DESTRUCTIVE', revoke_champion: 'DESTRUCTIVE', delete_card: 'DESTRUCTIVE',
  archive_card: 'DESTRUCTIVE', leave_tribe: 'DESTRUCTIVE', withdraw_from_initiative: 'DESTRUCTIVE',
  drop_event_instance: 'DESTRUCTIVE', unlink_board_from_drive: 'DESTRUCTIVE',
  revoke_exclusion_declaration: 'DESTRUCTIVE', lgpd_execute_retroactive_deletion: 'DESTRUCTIVE',
  member_remove_alternate_email: 'DESTRUCTIVE', force_revoke_curation_drive_access: 'DESTRUCTIVE',
  // plain writes — incl. the reversible cousins that must NOT read as destructive
  create_board_card: 'WRITE', update_card_status: 'WRITE', restore_card: 'WRITE',
  force_grant_curation_drive_access: 'WRITE', cancel_tribe_request: 'WRITE', dismiss_onboarding: 'WRITE',
};

test('#1418: applyRawAnnotations is wired into registerTools + applies classifyRawTool', () => {
  assert.match(BODY, /applyRawAnnotations\(mcp\)/, 'wrapper not called at top of registerTools');
  assert.match(SRC, /reg\.update\(\{ annotations: classifyRawTool\(name\) \}\)/,
    'raw annotations must be applied via RegisteredTool.update({annotations: classifyRawTool(name)})');
});

test('#1418: classifyRawTool ordering matches this guard (destructive-name check precedes prefixes)', () => {
  // The source must check RAW_DESTRUCTIVE_NAMES before the prefix rules, else force_revoke_* / the
  // lgpd deletion / member_remove_* would fall to WRITE. Assert the textual order in source.
  const body = SRC.slice(SRC.indexOf('function classifyRawTool('));
  const iDestrName = body.indexOf('RAW_DESTRUCTIVE_NAMES.has');
  const iDestrPref = body.indexOf('RAW_DESTRUCTIVE_PREFIXES.some');
  const iReadPref = body.indexOf('RAW_READ_PREFIXES.some');
  assert.ok(iDestrName !== -1 && iDestrPref !== -1 && iReadPref !== -1, 'classifier rules missing');
  assert.ok(iDestrName < iDestrPref && iDestrPref < iReadPref, 'classifier rule order regressed');
});

test('#1418: raw catalog still has 342 registered tools (drift tripwire)', () => {
  assert.equal(REGISTERED.length, 342, `expected 342 raw tools, got ${REGISTERED.length}`);
});

test('#1418: every registered raw tool classifies to exactly one class', () => {
  const valid = new Set(['RO', 'WRITE', 'DESTRUCTIVE']);
  for (const t of REGISTERED) {
    assert.ok(valid.has(classify(t)), `${t}: unclassified`);
  }
});

test('#1418: destructive-name safety net — every irreversible-verb tool is destructive', () => {
  const leaked = REGISTERED.filter((t) => DESTRUCTIVE_SIGNAL.test(t) && classify(t) !== 'DESTRUCTIVE');
  assert.deepEqual(leaked, [], `irreversible-named tools not flagged destructive: ${leaked.join(', ')}`);
});

test('#1418: no read-prefixed tool is ever destructive (reads stay safe)', () => {
  for (const t of REGISTERED) {
    if (READ_PREFIXES.some((p) => t.startsWith(p))) {
      assert.notEqual(classify(t), 'DESTRUCTIVE', `${t}: a read-prefixed tool must not be destructive`);
    }
  }
});

test('#1418: curated ground-truth classifications hold', () => {
  for (const [name, expected] of Object.entries(GROUND_TRUTH)) {
    assert.ok(REGISTERED.includes(name), `ground-truth tool ${name} is no longer registered — update the guard`);
    assert.equal(classify(name), expected, `${name}: expected ${expected}, got ${classify(name)}`);
  }
});

test('#1418: the SEM_* aliases classifyRawTool returns keep openWorldHint false + RO⊕destructive', () => {
  // classifyRawTool reuses SEM_RO / SEM_WRITE / SEM_DESTRUCTIVE (the #1402 aliases). Re-assert their
  // shape here so a future edit to those literals can't silently flip a raw hint.
  for (const alias of ['SEM_RO', 'SEM_WRITE', 'SEM_DESTRUCTIVE']) {
    const m = SRC.match(new RegExp(`const ${alias}: SemanticAnnotation = \\{([^}]+)\\}`));
    assert.ok(m, `alias ${alias} not defined`);
    const obj = {};
    for (const pair of m[1].split(',')) {
      const mm = pair.match(/(\w+):\s*(true|false)/);
      if (mm) obj[mm[1]] = mm[2] === 'true';
    }
    assert.equal(obj.openWorldHint, false, `${alias}.openWorldHint must be false`);
    assert.ok(!(obj.readOnlyHint && obj.destructiveHint), `${alias}: cannot be both readOnly and destructive`);
  }
});
