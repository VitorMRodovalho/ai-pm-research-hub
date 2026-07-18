/**
 * #1383 Wave 6a — Semantic envelope contract guard (comms / drive / partners long-tail).
 *
 * Wave 6a adds 7 intent-level tools over the comms/drive/partners tail. Beyond the stable envelope
 * { ok, data, summary, warnings, next_actions, audit }:
 *
 *   - Authority audited live 2026-07-17 (pg_get_functiondef). Reads gate on comms authority
 *     (manage_comms|manage_member|write_board) or view_partner; writes gate on manage_comms /
 *     manage_event / manage_partner / manage_platform per the raw RPC's own internal gate.
 *   - Migration 20260805000460 fixed the search_partner_cards #785 gap (rls_can_see_item on the
 *     board_item join) + granted it to authenticated (was unreachable), and REVOKEd the #965
 *     anon/PUBLIC EXECUTE drift on the webinar/idea write RPCs.
 *   - Enum contract CORRECTED: partner_crm interaction_type uses the LIVE CHECK
 *     (email|whatsapp|linkedin|call|meeting|note|status_change) — the raw log_partner_interaction
 *     advertised 'document'/'other', which fail the CHECK on every call. The raw tool schema was
 *     aligned to the same enum.
 *   - idea_pipeline enforces the publication_ideas source pair invariant (source_type XOR source_id
 *     rejected) before dispatch, and uses the live source_type/stage enums.
 *   - Deliberately NOT surfaced (stay raw): upload_text_to_drive_folder + create_drive_subfolder
 *     (Service-Account operations — but they GAINED an ownership gate here); provision_initiative_drive
 *     + reconcile_initiative_drive_access (multi-step SA orchestrations, #1376/ADR-0124).
 *
 * Pure static check over supabase/functions/nucleo-mcp/index.ts (no network / no DB) — runs in every
 * offline baseline. A future edit that drops the envelope, a gate, or reintroduces a wrong enum fails here.
 *
 * Cross-ref: EPIC #1383, wave0-artifacts/taxonomy.md §2.6 + §4, .claude/rules/mcp.md, SPEC-280.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The 7 Wave-6a semantic tools, in taxonomy §2.6 order.
const W6A_TOOLS = [
  'comms_report',
  'comms_post',
  'webinar_manage',
  'idea_pipeline',
  'drive_links',
  'drive_access_admin',
  'partner_crm',
];

// Tools that expose an action/scope discriminator.
const DISCRIMINATOR = {
  comms_report: 'scope',
  comms_post: 'action',
  webinar_manage: 'action',
  idea_pipeline: 'action',
  drive_links: 'action',
  drive_access_admin: 'action',
  partner_crm: 'action',
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

test('W6a: all 7 comms/drive/partners semantic tools are registered', () => {
  for (const t of W6A_TOOLS) {
    assert.ok(BLOCKS[t], `Wave-6a tool not registered in registerSemanticTools: ${t}`);
  }
});

for (const tool of W6A_TOOLS) {
  test(`W6a[${tool}]: conforms to the stable envelope (semanticOk success + buildSemanticError failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('semanticOk('), `${tool}: success path must return via semanticOk() (stable envelope)`);
    assert.ok(b.includes('buildSemanticError('), `${tool}: error/unauth path must return via buildSemanticError() (ok:false envelope)`);
    assert.ok(/code:\s*"unauthenticated"/.test(b), `${tool}: missing structured unauthenticated error`);
  });

  test(`W6a[${tool}]: never leaks a raw error (no bare err() / no return ok(data) escape)`, () => {
    const b = BLOCKS[tool];
    assert.ok(!/return\s+err\(/.test(b), `${tool}: uses raw err() — must use buildSemanticError() inside ok()`);
    const badOk = /return\s+ok\((?!\s*(?:buildSemanticError|\{))/.test(b);
    assert.ok(!badOk, `${tool}: return ok(...) must wrap an object literal or buildSemanticError(), not a raw payload`);
  });

  test(`W6a[${tool}]: audit block sets an explicit gate_checked + caller_member_id + pii_level`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('gate_checked:'), `${tool}: audit must state gate_checked`);
    assert.ok(b.includes('caller_member_id:'), `${tool}: audit must state caller_member_id`);
    assert.ok(b.includes('pii_level:'), `${tool}: audit must state pii_level`);
  });

  test(`W6a[${tool}]: declares its ${DISCRIMINATOR[tool]} discriminator as a Zod enum`, () => {
    const b = BLOCKS[tool];
    assert.ok(new RegExp(`${DISCRIMINATOR[tool]}:\\s*z\\.enum\\(`).test(b), `${tool}: must expose a ${DISCRIMINATOR[tool]} enum`);
  });
}

// comms_report is read-only; requires comms authority (manage_comms|manage_member|write_board).
test('W6a[comms_report]: read-only comms authority; absorbs the comms readers', () => {
  const b = BLOCKS['comms_report'];
  for (const perm of ['manage_comms', 'manage_member', 'write_board']) {
    assert.ok(b.includes(perm), `comms_report read gate must include ${perm}`);
  }
  for (const rpc of ['get_comms_dashboard_metrics', 'comms_metrics_latest_by_channel', 'get_comms_pipeline', 'webinars_pending_comms', 'get_member_comms_card', 'get_campaign_analytics', 'get_notifications_analytics']) {
    assert.ok(b.includes(rpc), `comms_report must dispatch ${rpc}`);
  }
});

// comms_post: schedule/cancel/list gate manage_comms; notify_tribe gates write; broadcasts via create_notification.
test('W6a[comms_post]: manage_comms for scheduling, write for notify_tribe, warns manual-only IG features', () => {
  const b = BLOCKS['comms_post'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_comms"\)/.test(b), 'comms_post schedule/cancel/list must gate manage_comms');
  assert.ok(/canV4\(sb,\s*member\.id,\s*"write"\)/.test(b), 'comms_post notify_tribe must gate write');
  for (const rpc of ['schedule_comms_post', 'cancel_scheduled_comms_post', 'list_scheduled_comms_posts', 'create_notification']) {
    assert.ok(b.includes(rpc), `comms_post must dispatch ${rpc}`);
  }
  assert.ok(/#1374/.test(b), 'comms_post must warn that IG collab/tags/story-stickers are manual-only (#1374)');
});

// webinar_manage: format enum; review/convert gate manage_event.
test('W6a[webinar_manage]: format enum; review/convert gate manage_event', () => {
  const b = BLOCKS['webinar_manage'];
  assert.ok(/format_type:\s*z\.enum\(\["palestra",\s*"painel",\s*"dupla",\s*"lightning",\s*"workshop"\]/.test(b),
    'webinar_manage format_type must be the RPC-validated enum');
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_event"\)/.test(b), 'review/convert must gate manage_event');
  for (const rpc of ['create_webinar_proposal', 'review_webinar_proposal', 'convert_proposal_to_webinar', 'update_webinar_comms_assets']) {
    assert.ok(b.includes(rpc), `webinar_manage must dispatch ${rpc}`);
  }
});

// idea_pipeline: source pairing invariant + live source_type/stage enums.
test('W6a[idea_pipeline]: enforces source_type XOR source_id + uses the live source_type/stage enums', () => {
  const b = BLOCKS['idea_pipeline'];
  assert.ok(/\(!!params\.source_type\)\s*!==\s*\(!!params\.source_id\)/.test(b),
    'idea_pipeline must reject a half-set (source_type XOR source_id) before dispatch');
  assert.ok(/source_type:\s*z\.enum\(\["meeting_action"/.test(b), 'idea_pipeline source_type must be a Zod enum of the live CHECK');
  assert.ok(/new_stage:\s*z\.enum\(\["draft"/.test(b), 'idea_pipeline new_stage must be a Zod enum of the live stage CHECK');
  for (const rpc of ['get_idea_pipeline', 'propose_publication_idea', 'advance_idea_stage', 'fork_idea_to_channel', 'link_idea_to_series', 'get_global_research_pipeline']) {
    assert.ok(b.includes(rpc), `idea_pipeline must dispatch ${rpc}`);
  }
});

// drive_links: dispatches the RPC-backed link/register actions; SA upload/subfolder stay raw.
test('W6a[drive_links]: absorbs the RPC-backed drive-link actions; SA upload/subfolder stay raw', () => {
  const b = BLOCKS['drive_links'];
  for (const rpc of ['link_initiative_to_drive', 'unlink_initiative_from_drive', 'get_initiative_drive_links', 'link_board_to_drive', 'register_card_drive_file', 'list_drive_discoveries']) {
    assert.ok(b.includes(rpc), `drive_links must dispatch ${rpc}`);
  }
  assert.ok(!b.includes('drive-upload-to-folder') && !b.includes('drive-create-subfolder'),
    'drive_links must NOT reimplement the Service-Account upload/subfolder EFs (they stay raw)');
});

// drive_access_admin: GP/DPO gate; provision/reconcile stay raw.
test('W6a[drive_access_admin]: gates manage_platform|manage_member; provision/reconcile stay raw', () => {
  const b = BLOCKS['drive_access_admin'];
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_platform"\)/.test(b) && /canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(b),
    'drive_access_admin must gate manage_platform OR manage_member');
  for (const rpc of ['admin_list_membership_drive_grants', 'get_membership_drive_grant_health', 'approve_drive_revocation', 'bulk_approve_drive_revocations']) {
    assert.ok(b.includes(rpc), `drive_access_admin must dispatch ${rpc}`);
  }
  assert.ok(!/sb\.rpc\(\s*"provision_initiative_drive"/.test(b) && !/reconcile-initiative-drive-access/.test(b),
    'provision_initiative_drive/reconcile stay raw (SA orchestrations) — must not be reimplemented here');
});

// partner_crm: view_partner reads / manage_partner writes; live interaction_type enum.
test('W6a[partner_crm]: view_partner reads, manage_partner writes, live interaction_type enum', () => {
  const b = BLOCKS['partner_crm'];
  assert.ok(b.includes('view_partner') && b.includes('manage_partner'), 'partner_crm must gate reads=view_partner, writes=manage_partner');
  assert.ok(/interaction_type:\s*z\.enum\(\["email",\s*"whatsapp",\s*"linkedin",\s*"call",\s*"meeting",\s*"note",\s*"status_change"\]/.test(b),
    'partner_crm interaction_type must be the LIVE CHECK enum');
  assert.ok(!/"document"/.test(b), 'partner_crm must NOT expose the always-rejected legacy interaction types (document/other)');
  for (const rpc of ['search_partner_cards', 'get_partner_pipeline', 'add_partner_interaction', 'admin_manage_partner_entity', 'link_partner_to_card']) {
    assert.ok(b.includes(rpc), `partner_crm must dispatch ${rpc}`);
  }
});

// ─── Raw-side hardening landed with this wave (outside the semantic block) ────

test('W6a: raw log_partner_interaction schema aligned to the live interaction_type CHECK enum', () => {
  assert.ok(/interaction_type:\s*z\.enum\(\["email",\s*"whatsapp",\s*"linkedin",\s*"call",\s*"meeting",\s*"note",\s*"status_change"\]/.test(SRC),
    'raw log_partner_interaction must use the live CHECK enum (not a free string advertising document/other)');
});

test('W6a: raw SA Drive writers gained an ownership gate (upload_text/create_subfolder)', () => {
  const upload = SRC.slice(SRC.indexOf('"upload_text_to_drive_folder"'), SRC.indexOf('"create_drive_subfolder"'));
  assert.ok(/canV4\(sb,\s*member\.id,\s*"write_board"\)/.test(upload) && /canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(upload),
    'upload_text_to_drive_folder must require write_board/manage_event/manage_member (ownership gate)');
});

test('W6a: /semantic health count is DERIVED (not a literal) + version 0.10.0 — #1392', () => {
  // #1392 retired the hardcoded literal; /health derives from the registrar. Authoritative count
  // lives in semantic-envelope-w6b (registerSemanticTools == 52).
  assert.match(SRC, /"\/semantic":\s*\{[^}]*tools:\s*SEMANTIC_TOOL_COUNT\b/, '/semantic health must derive from SEMANTIC_TOOL_COUNT');
  assert.match(SRC, /new McpServer\(\s*\{\s*name:\s*"nucleo-ia-semantic"\s*,\s*version:\s*"0\.10\.0"\s*\}\s*\)/, '/semantic McpServer must be v0.10.0');
});
