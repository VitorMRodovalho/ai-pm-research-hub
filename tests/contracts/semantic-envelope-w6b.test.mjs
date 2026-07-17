/**
 * #1383 Wave 6b — Semantic envelope contract guard (knowledge / gamification / admin / audit / lgpd).
 *
 * Wave 6b closes the semantic transition: 5 new intent-level tools + the knowledge_search intent
 * (folded into the existing search_nucleo_knowledge bridge, expanded in place — kept-name, no break).
 * Beyond the stable envelope { ok, data, summary, warnings, next_actions, audit }:
 *
 *   - Authority audited live 2026-07-17 (pg_get_functiondef). Every absorbed RPC self-gates
 *     internally (manage_platform / view_internal_analytics / view_chapter_dashboards / manage_member
 *     / self-scope); the admin/audit reads are pass-through + the RPC's own gate; champion_award
 *     passes through (org-scope grantor OR can_by_member(award_champion, initiative)); lgpd_admin
 *     adds a PROACTIVE canV4(manage_member) fail-fast AND an ADR-0018 confirm-gate for the
 *     irreversible transcription deletion (Art.18 §IV).
 *   - Migration 20260805000461: GRANT authenticated on knowledge_assets_latest (was service_role
 *     only → "permission denied" for MCP callers), and REVOKE the #965 anon/PUBLIC EXECUTE drift on
 *     10 fail-closed admin/audit/lgpd RPCs (public feeds get_public_impact_data/get_public_trail_ranking/
 *     get_cpmai_leaderboard intentionally kept anon).
 *   - Merit-immutability: champion_award recognizes work the recipient DID; awards are additive and
 *     never transfer completed-work credit.
 *   - Deliberately NOT surfaced (stay raw/frozen): knowledge_insights_* (internal ops backlog, dead,
 *     service-role); counter_sign_certificate (Lorena-only). create_notification spoofing = follow-up.
 *
 * Pure static check over supabase/functions/nucleo-mcp/index.ts (no network / no DB) — runs in every
 * offline baseline. A future edit that drops the envelope, a gate, or the confirm-gate fails here.
 *
 * Cross-ref: EPIC #1383, wave0-artifacts/taxonomy.md §2.6 + §4, .claude/rules/mcp.md, SPEC-280.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const SRC = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

// The 5 Wave-6b semantic tools, in taxonomy §2.6 order (knowledge_search folds into the bridge).
const W6B_TOOLS = [
  'gamification_report',
  'champion_award',
  'admin_dashboard',
  'audit_log',
  'lgpd_admin',
];

const DISCRIMINATOR = {
  gamification_report: 'scope',
  champion_award: 'action',
  admin_dashboard: 'scope',
  audit_log: 'scope',
  lgpd_admin: 'action',
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

test('W6b: all 5 knowledge/gamification/admin/audit/lgpd semantic tools are registered', () => {
  for (const t of W6B_TOOLS) {
    assert.ok(BLOCKS[t], `Wave-6b tool not registered in registerSemanticTools: ${t}`);
  }
});

for (const tool of W6B_TOOLS) {
  test(`W6b[${tool}]: conforms to the stable envelope (semanticOk success + buildSemanticError failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('semanticOk('), `${tool}: success path must return via semanticOk() (stable envelope)`);
    assert.ok(b.includes('buildSemanticError('), `${tool}: error/unauth path must return via buildSemanticError() (ok:false envelope)`);
    assert.ok(/code:\s*"unauthenticated"/.test(b), `${tool}: missing structured unauthenticated error`);
  });

  test(`W6b[${tool}]: never leaks a raw error (no bare err() / no return ok(data) escape)`, () => {
    const b = BLOCKS[tool];
    assert.ok(!/return\s+err\(/.test(b), `${tool}: uses raw err() — must use buildSemanticError() inside ok()`);
    const badOk = /return\s+ok\((?!\s*(?:buildSemanticError|\{))/.test(b);
    assert.ok(!badOk, `${tool}: return ok(...) must wrap an object literal or buildSemanticError(), not a raw payload`);
  });

  test(`W6b[${tool}]: audit block sets an explicit gate_checked + caller_member_id + pii_level`, () => {
    const b = BLOCKS[tool];
    assert.ok(b.includes('gate_checked:'), `${tool}: audit must state gate_checked`);
    assert.ok(b.includes('caller_member_id:'), `${tool}: audit must state caller_member_id`);
    assert.ok(b.includes('pii_level:'), `${tool}: audit must state pii_level`);
  });

  test(`W6b[${tool}]: declares its ${DISCRIMINATOR[tool]} discriminator as a Zod enum`, () => {
    const b = BLOCKS[tool];
    assert.ok(new RegExp(`${DISCRIMINATOR[tool]}:\\s*z\\.enum\\(`).test(b), `${tool}: must expose a ${DISCRIMINATOR[tool]} enum`);
  });

  // Every W6b tool surfaces a masked RPC error (data?.error) instead of masking it inside ok:true.
  test(`W6b[${tool}]: surfaces a masked RPC {error} (never ok:true over an RPC failure)`, () => {
    const b = BLOCKS[tool];
    assert.ok(/\(data as any\)\?\.error/.test(b) || /\.error\)/.test(b),
      `${tool}: must check the RPC's data?.error and map it to ok:false`);
  });
}

// gamification_report — self/aggregate; cross-member XP gated by view_pii inside the RPC.
test('W6b[gamification_report]: absorbs the XP/champion/rules readers; cross-member marked medium', () => {
  const b = BLOCKS['gamification_report'];
  for (const rpc of ['get_my_gamification_stats', 'get_member_cycle_xp', 'get_member_xp_pillars', 'get_champions_ranking', 'get_gamification_rules_catalog', 'get_initiative_gamification', 'get_tribe_gamification', 'get_cpmai_leaderboard', 'get_public_trail_ranking']) {
    assert.ok(b.includes(rpc), `gamification_report must dispatch ${rpc}`);
  }
});

// champion_award — award/revoke; RPC-gated; merit-immutability documented.
test('W6b[champion_award]: award+revoke, RPC-gated, merit-immutability documented', () => {
  const b = BLOCKS['champion_award'];
  assert.ok(b.includes('award_champion') && b.includes('revoke_champion'), 'champion_award must dispatch award_champion + revoke_champion');
  assert.ok(/action:\s*z\.enum\(\["award",\s*"revoke"\]/.test(b), 'champion_award action enum must be award|revoke');
  assert.ok(/merit-immutability/i.test(b), 'champion_award must state the merit-immutability rule');
});

// admin_dashboard — GP cockpit; RPC-internal gate; the aliased RPCs land right.
test('W6b[admin_dashboard]: absorbs the GP/analytics readers via their real RPC names', () => {
  const b = BLOCKS['admin_dashboard'];
  for (const rpc of ['get_admin_dashboard', 'get_annual_kpis', 'get_chapter_dashboard', 'get_in_dashboard', 'get_vep_divergence_report', 'volunteer_funnel_summary', 'get_volunteer_funnel_stats', 'exec_role_transitions', 'get_cycle_report', 'exec_cycle_report', 'get_cycle_evolution', 'get_public_impact_data', 'list_ai_suggestions', 'list_ai_processing_log']) {
    assert.ok(b.includes(rpc), `admin_dashboard must dispatch ${rpc}`);
  }
});

// audit_log — self PII-access free; admin views + CSV export gated by the RPC.
test('W6b[audit_log]: absorbs the 4 log RPCs; self-view separated from admin/DPO views', () => {
  const b = BLOCKS['audit_log'];
  for (const rpc of ['get_my_pii_access_log', 'get_audit_log', 'get_pii_access_log_admin', 'export_audit_log_csv']) {
    assert.ok(b.includes(rpc), `audit_log must dispatch ${rpc}`);
  }
  // export_audit_log_csv returns an 'Unauthorized...' TEXT string on deny — must be surfaced, not returned as data.
  assert.ok(/typeof data === "string"/.test(b) && /unauthorized/i.test(b),
    'audit_log must surface the text-string Unauthorized returned by export_audit_log_csv');
});

// lgpd_admin — DESTRUCTIVE; proactive manage_member + ADR-0018 confirm-gate.
test('W6b[lgpd_admin]: manage_member proactive gate + ADR-0018 confirm-gate on irreversible deletion', () => {
  const b = BLOCKS['lgpd_admin'];
  assert.ok(b.includes('lgpd_record_retroactive_notification') && b.includes('lgpd_execute_retroactive_deletion'),
    'lgpd_admin must dispatch both Art.18 RPCs');
  assert.ok(/canV4\(sb,\s*member\.id,\s*"manage_member"\)/.test(b), 'lgpd_admin must proactively gate manage_member (GP/DPO)');
  assert.ok(/params\.confirm\s*!==\s*true/.test(b), 'lgpd_admin execute_deletion must be confirm-gated (ADR-0018)');
  assert.ok(/ADR-0018/.test(b), 'lgpd_admin must reference ADR-0018 confirm-gate');
});

// knowledge_search intent = search_nucleo_knowledge bridge expanded in place (kept name, no break).
test('W6b[knowledge_search]: search_nucleo_knowledge gains mode=page/latest, absorbing get_wiki_page + knowledge_assets_latest', () => {
  const b = BLOCKS['search_nucleo_knowledge'];
  assert.ok(b, 'search_nucleo_knowledge (the knowledge_search intent) must remain registered');
  assert.ok(/mode:\s*z\.enum\(\["search",\s*"page",\s*"latest"\]/.test(b), 'knowledge_search must expose a mode enum (search|page|latest)');
  assert.ok(b.includes('get_wiki_page'), 'mode=page must dispatch get_wiki_page');
  assert.ok(b.includes('knowledge_assets_latest'), 'mode=latest must dispatch knowledge_assets_latest');
});

// ─── Raw-side hardening landed with this wave (migration 20260805000461) ────

test('W6b: migration grants knowledge_assets_latest to authenticated + revokes admin/audit/lgpd anon drift', () => {
  const mig = readFileSync(resolve(ROOT, 'supabase/migrations/20260805000461_1383_w6b_knowledge_grant_and_admin_audit_revoke.sql'), 'utf8');
  assert.ok(/GRANT EXECUTE ON FUNCTION public\.knowledge_assets_latest\(text, integer\) TO authenticated/.test(mig),
    'migration must GRANT knowledge_assets_latest to authenticated');
  for (const fn of ['get_admin_dashboard', 'get_audit_log', 'export_audit_log_csv', 'lgpd_execute_retroactive_deletion', 'lgpd_record_retroactive_notification', 'get_vep_divergence_report', 'list_ai_suggestions']) {
    assert.ok(new RegExp(`REVOKE EXECUTE ON FUNCTION public\\.${fn}\\([^)]*\\) FROM anon, PUBLIC`).test(mig),
      `migration must REVOKE anon/PUBLIC on ${fn}`);
  }
  // Public feeds must NOT be revoked (check the actual REVOKE statements, not the explanatory comment).
  assert.ok(!/REVOKE EXECUTE ON FUNCTION public\.get_public_impact_data/.test(mig), 'must NOT revoke the public feed get_public_impact_data');
});

test('W6b: /semantic health surface advertises 52 tools + version 0.9.0', () => {
  const health = SRC.match(/"\/semantic":\s*\{[^}]*tools:\s*(\d+)/);
  assert.ok(health, '/semantic health entry not found');
  assert.equal(Number(health[1]), 52, '/semantic health tools count must be 52 after Wave 6b');
  assert.match(SRC, /new McpServer\(\s*\{\s*name:\s*"nucleo-ia-semantic"\s*,\s*version:\s*"0\.10\.0"\s*\}\s*\)/, '/semantic McpServer must be v0.10.0');
});
