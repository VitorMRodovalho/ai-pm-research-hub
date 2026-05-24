/**
 * Contract: MCP operator surface for p238b LGPD Art. 18 §IV retroactive RPCs
 * (p239b #332 close — operator path unblock).
 *
 * Origin: p238b shipped infrastructure RPCs (`lgpd_record_retroactive_notification`
 * + `lgpd_execute_retroactive_deletion`) via migration 20260805000023. Both gate
 * on `can_by_member('manage_member')` which reads `auth.uid()` to resolve caller.
 * The service-role MCP exec_sql path cannot satisfy this gate (auth.uid() = NULL),
 * so PM had no authenticated channel to invoke the RPCs.
 *
 * p239b ships +2 MCP tools wrapping the RPCs so PM invokes from authenticated
 * MCP-Claude session (the nucleo-mcp EF routes through PM's JWT; auth.uid()
 * resolves correctly inside the RPC body):
 *   - lgpd_record_retroactive_notification — audit-row only, no confirm gate
 *   - lgpd_execute_retroactive_deletion — destructive, ADR-0018 W1 confirm gate
 *
 * Both add JS-layer canV4('manage_member') defense-in-depth (convention match
 * with analyze_application_video p199-a) — even if a downstream change removes
 * the SQL gate, the MCP layer still rejects.
 *
 * Static-only (no DB, no live HTTP). Verifies source-code invariants that survive
 * refactors: tool registrations, gate presence, confirm pattern compliance,
 * version bump consistency, and matrix coverage.
 *
 * Cross-ref:
 *   - GH #332 (operator-path enablement)
 *   - GH #221 + #218 (parent umbrella, decomposed p236)
 *   - Migration: supabase/migrations/20260805000023_p238_332_lgpd_art18_retroactive_deletion_log.sql
 *   - Sibling test: tests/contracts/lgpd-art-18-retroactive-deletion.test.mjs
 *   - ADR-0018 W1 (destructive write confirm gate)
 *   - ADR-0007 (canV4 as MCP layer V4 authority)
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const EF_PATH = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const MATRIX_JSON_PATH = resolve(ROOT, 'docs/reference/mcp-tool-matrix.json');
const MATRIX_MD_PATH = resolve(ROOT, 'docs/reference/MCP_TOOL_MATRIX.md');

const EF = readFileSync(EF_PATH, 'utf8');

// Pull the full text of an mcp.tool block by name (greedy across multiline body).
// Stops at the matching closing `});` at the same depth.
function toolBlock(name) {
  const start = EF.indexOf(`mcp.tool("${name}"`);
  if (start < 0) return null;
  // Walk forward counting balanced parens to find the closer.
  let depth = 0;
  let i = start;
  let seenOpen = false;
  while (i < EF.length) {
    const ch = EF[i];
    if (ch === '(') {
      depth++;
      seenOpen = true;
    } else if (ch === ')') {
      depth--;
      if (seenOpen && depth === 0) {
        // Look for the trailing semicolon after `})`
        const semi = EF.indexOf(';', i);
        return EF.slice(start, semi >= 0 ? semi + 1 : i + 1);
      }
    }
    i++;
  }
  return null;
}

// ─── 1. Tool registrations exist ─────────────────────────────────────────────

test('p239b #332: mcp.tool("lgpd_record_retroactive_notification") is registered', () => {
  const block = toolBlock('lgpd_record_retroactive_notification');
  assert.ok(block, 'expected mcp.tool block for lgpd_record_retroactive_notification');
  assert.match(
    block,
    /lgpd_art_18_retroactive_notification/i,
    'tool description must mention the canonical context literal'
  );
});

test('p239b #332: mcp.tool("lgpd_execute_retroactive_deletion") is registered', () => {
  const block = toolBlock('lgpd_execute_retroactive_deletion');
  assert.ok(block, 'expected mcp.tool block for lgpd_execute_retroactive_deletion');
  assert.match(
    block,
    /lgpd_art_18_deletion_executed|deletion_artifacts/i,
    'tool description must mention deletion_artifacts / canonical context'
  );
});

// ─── 2. canV4('manage_member') defense-in-depth gate ─────────────────────────

test('p239b #332: lgpd_record_retroactive_notification gates on canV4(manage_member)', () => {
  const block = toolBlock('lgpd_record_retroactive_notification');
  assert.match(
    block,
    /canV4\(\s*sb\s*,\s*member\.id\s*,\s*'manage_member'\s*\)/,
    'expected JS-layer canV4(manage_member) gate'
  );
});

test('p239b #332: lgpd_execute_retroactive_deletion gates on canV4(manage_member)', () => {
  const block = toolBlock('lgpd_execute_retroactive_deletion');
  assert.match(
    block,
    /canV4\(\s*sb\s*,\s*member\.id\s*,\s*'manage_member'\s*\)/,
    'expected JS-layer canV4(manage_member) gate'
  );
});

// ─── 3. Zod input schemas correct ────────────────────────────────────────────

test('p239b #332: notification tool declares 5 params with correct Zod shapes', () => {
  const block = toolBlock('lgpd_record_retroactive_notification');
  assert.match(block, /p_application_id:\s*z\.string\(\)/);
  assert.match(block, /p_template_version:\s*z\.string\(\)/);
  assert.match(block, /p_lang:\s*z\.string\(\)/);
  assert.match(
    block,
    /p_notification_method:\s*z\.enum\(\[\s*"email"\s*,\s*"whatsapp"\s*,\s*"in_person"\s*,\s*"other"\s*\]\)\.optional\(\)/,
    'p_notification_method must be z.enum optional matching RPC CHECK'
  );
  assert.match(
    block,
    /p_dispatched_at:\s*z\.string\(\)\.optional\(\)/,
    'p_dispatched_at must be optional ISO string'
  );
});

test('p239b #332: deletion tool declares 5 params (including confirm) with correct Zod shapes', () => {
  const block = toolBlock('lgpd_execute_retroactive_deletion');
  assert.match(block, /p_application_id:\s*z\.string\(\)/);
  assert.match(block, /p_video_id:\s*z\.string\(\)/);
  assert.match(block, /p_deletion_reason:\s*z\.string\(\)/);
  assert.match(block, /p_drive_deletion_ref:\s*z\.string\(\)\.optional\(\)/);
  assert.match(
    block,
    /confirm:\s*z\.boolean\(\)\.optional\(\)/,
    'confirm param required for ADR-0018 W1 destructive gate'
  );
});

// ─── 4. ADR-0018 confirm gate behavior ───────────────────────────────────────

test('p239b #332: deletion tool implements ADR-0018 W1 confirm gate (preview default; execute on confirm=true)', () => {
  const block = toolBlock('lgpd_execute_retroactive_deletion');
  // Must branch on params.confirm !== true → preview return.
  assert.match(
    block,
    /if\s*\(\s*params\.confirm\s*!==\s*true\s*\)/,
    'must check params.confirm !== true before executing'
  );
  // Must log result_kind="preview" on the preview branch.
  assert.match(
    block,
    /logUsage\([\s\S]*?"lgpd_execute_retroactive_deletion"[\s\S]*?"preview"/,
    'preview branch must log result_kind=preview to mcp_usage_log'
  );
  // Preview must surface impact + cross_app_check for evaluator inspection.
  assert.match(block, /preview:\s*true/, 'preview envelope must declare preview:true');
  assert.match(block, /will_clear_transcription/, 'preview must surface will_clear_transcription');
  assert.match(block, /cross_app_check/, 'preview must surface cross-app validation');
  // Must include next_call hint with confirm:true for operator UX.
  assert.match(block, /next_call:[\s\S]*?confirm:\s*true/, 'preview must hint next_call with confirm:true');
});

test('p239b #332: notification tool does NOT include a confirm gate (audit-row insert, not destructive)', () => {
  const block = toolBlock('lgpd_record_retroactive_notification');
  // The notification tool MUST NOT include a `confirm` Zod schema field — adding one
  // would imply destructive scope and conflict with ADR-0018 W1 boundary.
  assert.doesNotMatch(
    block,
    /confirm:\s*z\.boolean/,
    'notification tool is audit-write only — must not include confirm gate (keeps ADR-0018 W1 scope clean)'
  );
});

// ─── 5. Deletion reason length guard mirrored at JS layer ────────────────────

test('p239b #332: deletion tool JS layer guards p_deletion_reason >= 8 chars (mirrors RPC sanity)', () => {
  const block = toolBlock('lgpd_execute_retroactive_deletion');
  assert.match(
    block,
    /p_deletion_reason[\s\S]*?trim\(\)[\s\S]*?length\s*<\s*8/,
    'JS layer must guard p_deletion_reason >= 8 chars before RPC dispatch'
  );
});

// ─── 6. UUID validation at JS layer for both tools ───────────────────────────

test('p239b #332: both tools validate UUID params via isUUID helper before RPC call', () => {
  const rec = toolBlock('lgpd_record_retroactive_notification');
  const del = toolBlock('lgpd_execute_retroactive_deletion');
  assert.match(rec, /isUUID\(params\.p_application_id\)/);
  assert.match(del, /isUUID\(params\.p_application_id\)/);
  assert.match(del, /isUUID\(params\.p_video_id\)/);
});

// ─── 7. Version + tool count bump consistency ────────────────────────────────

test('p239b #332: nucleo-ia-hub MCP server bumped to 2.79.0 (was 2.78.1 pre-p239b)', () => {
  assert.match(
    EF,
    /name:\s*"nucleo-ia-hub"\s*,\s*version:\s*"2\.79\.0"/,
    'nucleo-ia-hub must declare version 2.79.0 in McpServer constructor'
  );
});

test('p239b #332: ef_version bumped to 2.80.0 (was 2.79.1 pre-p239b)', () => {
  assert.match(EF, /ef_version:\s*"2\.80\.0"/, '/health must report ef_version 2.80.0');
});

test('p239b #332: /health surface declares /mcp tools: 301 + version 2.79.0', () => {
  assert.match(
    EF,
    /"\/mcp":\s*\{\s*server:\s*"nucleo-ia-hub"\s*,\s*version:\s*"2\.79\.0"\s*,\s*tools:\s*301\s*\}/,
    '/health surface report must show 301 tools + version 2.79.0 on /mcp'
  );
});

// ─── 8. Header changelog entry references this work ──────────────────────────

test('p239b #332: header changelog mentions v2.80.0 + p239b #332 LGPD provenance', () => {
  assert.match(EF, /v2\.80\.0\s*\(p239b\s*#332\s*W3\s*LGPD/i, 'header must include v2.80.0 changelog entry for p239b #332');
  assert.match(EF, /lgpd_record_retroactive_notification/, 'header must name the notification tool');
  assert.match(EF, /lgpd_execute_retroactive_deletion/, 'header must name the deletion tool');
});

// ─── 9. Matrix coverage (regen'd via scripts/audit-mcp-tool-matrix.mjs) ──────

test('p239b #332: mcp-tool-matrix.json lists both new tools', () => {
  assert.ok(existsSync(MATRIX_JSON_PATH), 'matrix json must exist (re-run audit script if missing)');
  const matrix = JSON.parse(readFileSync(MATRIX_JSON_PATH, 'utf8'));
  const tools = Array.isArray(matrix) ? matrix : (matrix.tools || []);
  const names = new Set(tools.map((t) => t.name));
  assert.ok(names.has('lgpd_record_retroactive_notification'), 'matrix must include lgpd_record_retroactive_notification');
  assert.ok(names.has('lgpd_execute_retroactive_deletion'), 'matrix must include lgpd_execute_retroactive_deletion');
});

test('p239b #332: MCP_TOOL_MATRIX.md header reflects new total (302 → 304 = 301 /mcp + 3 /semantic)', () => {
  assert.ok(existsSync(MATRIX_MD_PATH), 'matrix md must exist');
  const md = readFileSync(MATRIX_MD_PATH, 'utf8');
  // The script generates "MCP 304-Tool Contract Matrix" in the H1 + "Total tools (static parser): 304".
  assert.match(md, /MCP\s+304-Tool\s+Contract\s+Matrix/i, 'matrix MD H1 must reflect new 304 total (301 /mcp + 3 /semantic)');
  // Markdown bold `**Total tools (static parser):**` — allow optional ** between : and the count.
  assert.match(md, /Total tools \(static parser\):\**\s*304/i, 'matrix MD summary must declare 304 total');
});

// ─── 10. Forward-defense: future PRs cannot silently drop either tool ────────

test('p239b #332: forward-defense — both tool names must remain present in index.ts', () => {
  // This guards against accidental removal via blanket refactor. To intentionally
  // remove either tool, the offending PR must update both this assertion AND
  // file an ADR documenting the operator path migration.
  assert.match(EF, /mcp\.tool\(\s*"lgpd_record_retroactive_notification"/);
  assert.match(EF, /mcp\.tool\(\s*"lgpd_execute_retroactive_deletion"/);
});
