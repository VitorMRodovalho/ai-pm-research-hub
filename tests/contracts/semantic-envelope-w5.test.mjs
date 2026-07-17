/**
 * #1383 Wave 5 — Semantic envelope contract guard (governance / documents / certificates).
 *
 * Wave 5 adds 7 intent-level tools over the governance domain (the worst-failure domain in the
 * 180d window). Beyond the stable envelope { ok, data, summary, warnings, next_actions, audit }:
 *
 *   - Every absorbed raw RPC self-gates INTERNALLY (audited live 2026-07-17 via pg_get_functiondef):
 *     the governance READ RPCs enforce the visibility_class ceiling (get_document_detail /
 *     get_version_diff / get_governance_document_reader — migrations 450/451); version writes require
 *     manage_member; the manual-version 2-of-N + change-request writes require manage_platform /
 *     curate_content; the certificate + ip-exclusion RPCs resolve the caller and self-gate. All are
 *     FAIL-CLOSED for anon. Migration 20260805000459 REVOKEd the dead anon/PUBLIC EXECUTE drift on
 *     the write set and clamped submit_change_request priority (critical→high was a hard CHECK fail).
 *   - The semantic layer passes through and surfaces the RPC's own {error}/RAISE in ok:false; the
 *     version-write tool adds a proactive canV4() fail-fast (manage_member / manage_platform).
 *   - Enum contracts are CORRECTED here: document_comment uses the RPC-validated visibility enum
 *     (curator_only|submitter_only|change_notes — the raw tool's public/signers_only/private were
 *     rejected on EVERY call, masked as ok:true); change_request uses cr_type
 *     (editorial|operational|structural|emergency — the raw manual_edit/gc_override/policy_update
 *     were likewise always rejected); certificate_manage validates issue inputs before dispatch
 *     (title required, type/language enums, cycle int) — the root cause of the 18/27 failures.
 *   - Destructive actions are confirm-gated (ADR-0018) with a preview: document_version_write
 *     delete + confirm_manual; certificate_manage issue + update; ip_exclusion revoke.
 *   - Deliberately NOT surfaced (stay raw): counter_sign_certificate (Dir. de Voluntariados'
 *     exclusive act — never automated); review_change_request / approve_change_request (open
 *     CR-authority finding — V3 fallback reaches 'implement', bypassing the 2-of-N flow).
 *
 * Pure static check over supabase/functions/nucleo-mcp/index.ts (no network / no DB) — runs in every
 * offline baseline. A future edit that drops the envelope, a gate, the confirm-gate, or reintroduces
 * a wrong enum fails CI here.
 *
 * Cross-ref: EPIC #1383, wave0-artifacts/taxonomy.md §2.5 + §4, .claude/rules/mcp.md, SPEC-280.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The 7 Wave-5 semantic tools, in taxonomy §2.5 order.
const W5_TOOLS = [
  'document_get',
  'document_version_write',
  'document_comment',
  'change_request',
  'signature_flow',
  'certificate_manage',
  'ip_exclusion',
];

// Tools that expose an action/mode discriminator.
const DISCRIMINATOR = {
  document_get: 'mode',
  document_version_write: 'action',
  document_comment: 'action',
  change_request: 'action',
  signature_flow: 'action',
  certificate_manage: 'action',
  ip_exclusion: 'action',
};

/** Isolate the registerSemanticTools(...) function body (ends right before the /actions comment). */
function semanticBody(src) {
  const start = src.indexOf('function registerSemanticTools(');
  assert.ok(start !== -1, 'registerSemanticTools() not found');
  const end = src.indexOf('// #1377 — /actions overflow surface.', start);
  assert.ok(end !== -1, 'end sentinel (/actions comment) not found after registerSemanticTools');
  return src.slice(start, end);
}

/** Split the body into per-tool blocks keyed by tool name (first string arg of mcp.tool(). */
function toolBlocks(body) {
  const idxs = [];
  const re = /mcp\.tool\(\s*\n?\s*"([a-zA-Z0-9_]+)"/g;
  let m;
  while ((m = re.exec(body)) !== null) idxs.push({ name: m[1], at: m.index });
  const blocks = {};
  for (let i = 0; i < idxs.length; i++) {
    const from = idxs[i].at;
    const to = i + 1 < idxs.length ? idxs[i + 1].at : body.length;
    blocks[idxs[i].name] = body.slice(from, to);
  }
  return blocks;
}

const BODY = semanticBody(SRC);
const BLOCKS = toolBlocks(BODY);

test('W5: all 7 governance semantic tools are registered', () => {
  for (const t of W5_TOOLS) {
    assert.ok(BLOCKS[t], `Wave-5 tool not registered in registerSemanticTools: ${t}`);
  }
});

for (const tool of W5_TOOLS) {
  test(`W5[${tool}]: conforms to the stable envelope (semanticOk success + buildSemanticError failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('semanticOk('), `${tool}: success path must return via semanticOk() (stable envelope)`);
    assert.ok(b.includes('buildSemanticError('), `${tool}: error/unauth path must return via buildSemanticError() (ok:false envelope)`);
    assert.ok(/code:\s*"unauthenticated"/.test(b), `${tool}: missing structured unauthenticated error`);
  });

  test(`W5[${tool}]: never leaks a raw error (no bare err() / no return ok(data) escape)`, () => {
    const b = BLOCKS[tool];
    assert.ok(!/return\s+err\(/.test(b), `${tool}: uses raw err() — must use buildSemanticError() inside ok()`);
    const badOk = /return\s+ok\((?!\s*(?:buildSemanticError|\{))/.test(b);
    assert.ok(!badOk, `${tool}: return ok(...) must wrap an object literal or buildSemanticError(), not a raw payload`);
  });

  test(`W5[${tool}]: audit block sets an explicit gate_checked + caller_member_id + pii_level`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('gate_checked:'), `${tool}: audit must state gate_checked`);
    assert.ok(b.includes('caller_member_id:'), `${tool}: audit must state caller_member_id`);
    assert.ok(b.includes('pii_level:'), `${tool}: audit must state pii_level`);
  });

  test(`W5[${tool}]: declares its ${DISCRIMINATOR[tool]} discriminator as a Zod enum`, () => {
    const b = BLOCKS[tool];
    assert.ok(new RegExp(`${DISCRIMINATOR[tool]}:\\s*z\\.enum\\(`).test(b), `${tool}: must expose a ${DISCRIMINATOR[tool]} enum`);
  });
}

// document_version_write proactively mirrors each RPC's internal gate via canV4() fail-fast.
test('W5[document_version_write]: proactively gates each action via canV4 (manage_member/manage_platform)', () => {
  const b = BLOCKS['document_version_write'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*need\)/.test(b), 'document_version_write must fail-fast via canV4(need) before dispatch');
  for (const perm of ['manage_member', 'manage_platform']) {
    assert.ok(b.includes(perm), `document_version_write GATE map must cover ${perm}`);
  }
});

test('W5[document_version_write]: delete + confirm_manual are confirm-gated (ADR-0018) with a preview', () => {
  const b = BLOCKS['document_version_write'];
  assert.ok(/params\.confirm\s*!==\s*true/.test(b), 'must require confirm=true for destructive actions');
  assert.ok(/preview:\s*true/.test(b), 'must return a preview when not confirmed');
  for (const rpc of ['upsert_document_version', 'lock_document_version', 'delete_document_version_draft', 'confirm_manual_version']) {
    assert.ok(b.includes(rpc), `document_version_write must dispatch ${rpc}`);
  }
});

// document_get is read-only and dispatches the ceiling-gated readers.
test('W5[document_get]: read-only; absorbs the ceiling-gated document readers, no write gate', () => {
  const b = BLOCKS['document_get'];
  for (const rpc of ['get_document_detail', 'get_governance_document_reader', 'get_version_diff', 'list_document_versions', 'get_governance_change_log']) {
    assert.ok(b.includes(rpc), `document_get must dispatch ${rpc}`);
  }
  assert.ok(!/canV4\(sb,\s*member\.id,\s*"manage_/.test(b), 'document_get is read-only — no manage_* write gate');
});

// document_comment uses the RPC-validated visibility enum (fixes the always-fail raw enum).
test('W5[document_comment]: uses the corrected visibility enum + dispatches create_document_comment', () => {
  const b = BLOCKS['document_comment'];
  assert.ok(/visibility:\s*z\.enum\(\["curator_only",\s*"submitter_only",\s*"change_notes"\]/.test(b),
    'document_comment visibility must be the RPC-validated enum (curator_only|submitter_only|change_notes)');
  assert.ok(!/"public"|"signers_only"|"private"/.test(b), 'document_comment must NOT expose the always-rejected legacy visibility values');
  assert.ok(b.includes('create_document_comment'), 'document_comment add must dispatch create_document_comment (not the nonexistent add_document_comment RPC)');
});

// change_request uses the correct cr_type enum; review/approve are now absorbed (#1397 remediated),
// and the retired unilateral 'implement' action must NOT be reachable through the semantic surface.
test('W5[change_request]: correct cr_type enum; surfaces review/approve; implement retired (#1397)', () => {
  const b = BLOCKS['change_request'];
  assert.ok(/cr_type:\s*z\.enum\(\["editorial",\s*"operational",\s*"structural",\s*"emergency"\]/.test(b),
    'change_request cr_type must be the RPC-validated enum (editorial|operational|structural|emergency)');
  assert.ok(!/"manual_edit"|"gc_override"|"policy_update"/.test(b), 'change_request must NOT expose the always-rejected legacy cr_type values');
  assert.ok(b.includes('submit_change_request') && b.includes('get_change_requests'), 'change_request must dispatch submit + list');
  assert.ok(/sb\.rpc\(\s*"review_change_request"/.test(b) && /sb\.rpc\(\s*"approve_change_request"/.test(b),
    'change_request must absorb review + approve (post-#1397 hardening)');
  // #1397: 'implement' was retired from review_change_request — the review_action enum must not offer it,
  // so the approved->implemented transition stays single-sourced to the 2-of-N Manual flow (ADR-0044).
  assert.ok(/review_action:\s*z\.enum\(\["approve",\s*"reject",\s*"request_changes",\s*"withdraw",\s*"resubmit"\]/.test(b),
    'review_action enum must be exactly approve|reject|request_changes|withdraw|resubmit (no implement)');
  assert.ok(!/"implement"/.test(b), 'change_request must NOT offer the retired implement action');
  // approve path is the sponsor-quorum vote.
  assert.ok(/vote:\s*z\.enum\(\["approved",\s*"rejected",\s*"abstained"\]/.test(b),
    'approve vote enum must be approved|rejected|abstained');
});

// certificate_manage never automates countersign, and confirm-gates issue/update.
test('W5[certificate_manage]: NO countersign; issue/update confirm-gated; validates issue inputs', () => {
  const b = BLOCKS['certificate_manage'];
  assert.ok(!/sb\.rpc\(\s*"counter_sign_certificate"/.test(b),
    'counter_sign_certificate is the Dir. de Voluntariados exclusive act — must never be dispatched via MCP');
  assert.ok(/params\.confirm\s*!==\s*true/.test(b), 'issue/update must be confirm-gated (ADR-0018)');
  for (const rpc of ['issue_certificate', 'update_certificate', 'verify_certificate']) {
    assert.ok(b.includes(rpc), `certificate_manage must dispatch ${rpc}`);
  }
  assert.ok(/a non-empty title/.test(b), 'certificate_manage must validate a non-empty title before dispatch (null-title crash fix)');
});

// signature_flow absorbs the alias sign_ratification_gate → sign_ip_ratification.
test('W5[signature_flow]: dispatches sign_ip_ratification (absorbs the sign_ratification_gate alias)', () => {
  const b = BLOCKS['signature_flow'];
  for (const rpc of ['sign_ip_ratification', 'get_pending_ratifications', 'get_my_signatures', 'get_chain_audit_report']) {
    assert.ok(b.includes(rpc), `signature_flow must dispatch ${rpc}`);
  }
});

// ip_exclusion confirm-gates the terminal revoke and validates the sha256 digest.
test('W5[ip_exclusion]: revoke confirm-gated; add_asset validates the sha256 digest', () => {
  const b = BLOCKS['ip_exclusion'];
  assert.ok(/params\.confirm\s*!==\s*true/.test(b), 'revoke must be confirm-gated (terminal, ADR-0018)');
  assert.ok(/\[0-9a-fA-F\]\{64\}/.test(b), 'add_asset must validate a 64-hex SHA-256 digest');
  for (const rpc of ['create_exclusion_declaration', 'register_exclusion_asset', 'revoke_exclusion_declaration', 'export_anexo_i']) {
    assert.ok(b.includes(rpc), `ip_exclusion must dispatch ${rpc}`);
  }
});

test('W5: /semantic health surface advertises 52 tools (4 bridge + 8 W1 + 9 W2 + 6 W3 + 6 W4 + 7 W5 + 7 W6a)', () => {
  const health = SRC.match(/"\/semantic":\s*\{[^}]*tools:\s*(\d+)/);
  assert.ok(health, '/semantic health entry not found');
  assert.equal(Number(health[1]), 52, '/semantic health tools count must be 52 after Wave 6a');
});

test('W5: nucleo-ia-semantic version bumped to 0.9.0 (Wave 6a)', () => {
  assert.match(SRC, /new McpServer\(\s*\{\s*name:\s*"nucleo-ia-semantic"\s*,\s*version:\s*"0\.10\.0"\s*\}\s*\)/,
    '/semantic McpServer must be v0.9.0 at Wave 6a');
});
