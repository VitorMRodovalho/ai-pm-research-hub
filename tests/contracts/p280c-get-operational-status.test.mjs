/**
 * SPEC-280.C contract test — wave-2 /semantic tool `get_operational_status`.
 *
 * A read-only composite ops-health summary for admins: alert counts by severity (incl. the #415
 * recurrence-stockout), the stockout resupply list, event-attendance health, and cron/sync health.
 * Composes only already-built + already-gated read RPCs via Promise.allSettled (graceful per-source
 * degradation), gated manage_platform, PII-clean.
 *
 * The generic /semantic surface contract (exactly-4 tools, names, Zod, envelope, audit fields, version
 * 0.2.0, /health=4) is asserted in mcp-semantic-gateway-bridge.test.mjs. This file guards the tool's
 * OWN design invariants — especially the PII redaction, which is the subtle, leak-prone part.
 *
 * Static-only (semantic tools are MCP-protocol tools, not PostgREST RPCs, so they are not service-role
 * callable; functional proof is the post-deploy live /semantic smoke — see SPEC-280.C §9).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const MCP = resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts');
const MATRIX_JSON = resolve(ROOT, 'docs/reference/mcp-tool-matrix.json');
const EF = readFileSync(MCP, 'utf8');

// Scope to the registerSemanticTools function body so we assert against THIS tool, not a same-named /mcp one.
function semanticBlock() {
  const start = EF.indexOf('function registerSemanticTools(');
  assert.notEqual(start, -1, 'registerSemanticTools not found');
  // walk to the next top-level `// MCP endpoint` marker after the function
  const end = EF.indexOf('// MCP endpoint', start);
  return EF.slice(start, end > 0 ? end : EF.length);
}
// Scope to the get_operational_status tool declaration specifically.
function toolBlock() {
  const b = semanticBlock();
  const start = b.indexOf('mcp.tool(\n    "get_operational_status"');
  assert.notEqual(start, -1, 'get_operational_status tool not found in semantic block (must be registered there)');
  return b.slice(start);
}

test('SPEC-280.C: get_operational_status is registered in the semantic block', () => {
  assert.match(semanticBlock(), /mcp\.tool\(\s*"get_operational_status"/, 'registered in registerSemanticTools (the /semantic surface)');
});

test('SPEC-280.C: gated manage_platform, fail-closed via buildSemanticError', () => {
  const t = toolBlock();
  assert.match(t, /canV4\(sb,\s*member\.id,\s*"manage_platform"\)/, 'gated on manage_platform');
  assert.match(t, /buildSemanticError\(\{[\s\S]*?code:\s*"unauthenticated"/, 'unauthenticated → buildSemanticError');
  assert.match(t, /buildSemanticError\(\{[\s\S]*?code:\s*"unauthorized"/, 'missing manage_platform → buildSemanticError');
});

test('SPEC-280.C: composes the documented source RPCs via Promise.allSettled', () => {
  const t = toolBlock();
  assert.match(t, /Promise\.allSettled\(/, 'uses Promise.allSettled (graceful per-source degradation)');
  for (const rpc of ['detect_operational_alerts', 'get_recurrence_stockout', 'get_event_attendance_health',
                     'get_digest_health', 'get_lgpd_cron_health', 'get_invitation_health']) {
    assert.match(t, new RegExp(`sb\\.rpc\\(\\s*"${rpc}"`), `composes ${rpc}`);
  }
});

test('SPEC-280.C: PII-clean — drops member fields AND redacts name-embedding alert messages', () => {
  const t = toolBlock();
  // structured PII fields dropped
  assert.match(t, /PII_FIELDS\s*=\s*\[[^\]]*"member_name"[^\]]*\]/, 'member_name in PII_FIELDS');
  // the two alert types that embed a member name in their message text are redacted (not just field-dropped)
  assert.match(t, /NAME_EMBEDDING\s*=\s*new Set\(\[[^\]]*"member_absence_streak"[^\]]*"onboarding_overdue"[^\]]*\]\)/, 'name-embedding types enumerated');
  assert.match(t, /out\.message\s*=\s*`[^`]*PII[^`]*`/, 'name-embedding messages are redacted');
  // audit advertises pii_level none (the redaction is what makes this honest)
  assert.match(t, /pii_level:\s*"none"/, 'audit declares pii_level none');
});

test('SPEC-280.C: bounded output + stable envelope', () => {
  const t = toolBlock();
  assert.match(t, /\.slice\(0,\s*50\)/, 'alert/stockout lists are bounded');
  for (const key of ['ok:', 'data,', 'summary,', 'warnings,', 'next_actions:', 'audit:']) {
    assert.ok(t.includes(key), `envelope key present: ${key}`);
  }
});

test('SPEC-280.C: matrix includes get_operational_status', () => {
  assert.ok(existsSync(MATRIX_JSON), 'matrix json present');
  const matrix = JSON.parse(readFileSync(MATRIX_JSON, 'utf8'));
  const tools = Array.isArray(matrix) ? matrix : (matrix.tools || []);
  assert.ok(tools.some((x) => x.name === 'get_operational_status'), 'matrix lists get_operational_status');
});
