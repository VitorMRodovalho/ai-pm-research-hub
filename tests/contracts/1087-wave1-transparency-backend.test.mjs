/**
 * #1087 Wave 1 — Gamification transparency backend (SSOT catalog + member statement + granted_by).
 *
 * Migration 20260805000332 adds:
 *   - gamification_points.granted_by (actor provenance, forward-only, FK → members ON DELETE SET NULL);
 *   - _grant_auto_xp p_granted_by param (DROP+CREATE; actor = explicit param → auth.uid() → NULL=system);
 *   - award_champion ledger mirror records granted_by = grantor;
 *   - get_gamification_rules_catalog() (SSOT: rules + champion criteria + level thresholds — ADR-0081
 *     Pattern 47 extended to the frontend);
 *   - get_my_points_statement() (member-scoped extrato via auth.uid(), no IDOR, champion attribution).
 * MCP wiring: the two new RPCs + get_member_xp_pillars exposed as tools; recalculate_cycle_rankings
 * description corrected (operates on selection_ranking_snapshots, NOT the gamification leaderboard).
 *
 * Source-contract assertions run offline (no DB env needed).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIG = readFileSync(
  fileURLToPath(new URL('../../supabase/migrations/20260805000332_1087_wave1_gamification_transparency_backend.sql', import.meta.url)),
  'utf8',
);
const MCP = readFileSync(
  fileURLToPath(new URL('../../supabase/functions/nucleo-mcp/index.ts', import.meta.url)),
  'utf8',
);

test('1087: granted_by column is additive with FK → members ON DELETE SET NULL (LGPD-safe)', () => {
  assert.match(MIG, /ALTER TABLE public\.gamification_points\s+ADD COLUMN granted_by uuid REFERENCES public\.members\(id\) ON DELETE SET NULL/, 'column + FK');
  assert.doesNotMatch(MIG, /UPDATE public\.gamification_points/, 'forward-only — no backfill of historical rows');
  assert.match(MIG, /COMMENT ON COLUMN public\.gamification_points\.granted_by/, 'semantics documented (NULL = system/cron)');
});

test('1087: _grant_auto_xp gains actor param via DROP+CREATE and stays internal-only', () => {
  assert.match(MIG, /DROP FUNCTION public\._grant_auto_xp\(text, uuid, uuid, text, boolean\);/, 'old signature dropped (signature change = DROP+CREATE)');
  assert.match(MIG, /p_granted_by uuid DEFAULT NULL::uuid/, 'actor param with DEFAULT — all 9 existing callers keep working unchanged');
  assert.match(MIG, /SELECT id INTO v_granted_by FROM members WHERE auth_id = auth\.uid\(\);/, 'fallback actor = acting user session');
  assert.match(MIG, /INSERT INTO gamification_points \(member_id, points, reason, category, ref_id, organization_id, granted_by\)/, 'ledger INSERT carries granted_by');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._grant_auto_xp\(text, uuid, uuid, text, boolean, uuid\) FROM public, anon, authenticated;/, 'internal-only ACL preserved (no authenticated)');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\._grant_auto_xp\(text, uuid, uuid, text, boolean, uuid\) TO service_role;/, 'service_role only');
});

test('1087: award_champion ledger mirror records the grantor', () => {
  const mirror = MIG.match(/-- #1087 wave 1: ledger mirror carries actor provenance[\s\S]{0,600}/)?.[0] ?? '';
  assert.match(mirror, /INSERT INTO gamification_points \(member_id, points, reason, category, ref_id, organization_id, granted_by\)/, 'mirror INSERT has granted_by column');
  assert.match(mirror, /v_caller\.id\s*\n?\s*\);/, 'granted_by = v_caller.id (the grantor)');
});

test('1087: rules catalog derives everything from SSOT tables (no literal point values)', () => {
  assert.match(MIG, /CREATE FUNCTION public\.get_gamification_rules_catalog\(\)/, 'catalog RPC defined');
  assert.match(MIG, /FROM public\.gamification_rules gr/, 'rules from gamification_rules');
  assert.match(MIG, /SELECT DISTINCT ON \(gr\.slug\) gr\.\*/, 'latest effective row per slug — same semantics as _grant_auto_xp');
  assert.match(MIG, /FROM public\.champion_criteria_catalog c/, 'champion criteria from catalog table');
  assert.match(MIG, /WHERE ps\.key = 'gamification_level_thresholds'/, 'level thresholds from platform_settings');
  assert.match(MIG, /RAISE EXCEPTION 'Forbidden: authentication required'/, 'fail-closed for non-members');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.get_gamification_rules_catalog\(\) FROM public, anon;/, 'revoke public/anon');
  assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.get_gamification_rules_catalog\(\) TO authenticated;/, 'grant authenticated');
});

test('1087: level tiers seeded in config match the values previously hardcoded in gamification.astro', () => {
  assert.match(MIG, /'gamification_level_thresholds'/, 'seed key present');
  for (const min of [0, 31, 91, 201, 401]) {
    assert.match(MIG, new RegExp(`"min_points":${min}[,}]`), `tier min_points ${min} preserved`);
  }
  assert.match(MIG, /ON CONFLICT \(key\) DO NOTHING/, 'idempotent seed');
});

test('1087: statement is member-scoped via auth.uid() (no p_member_id → no IDOR, fail-closed)', () => {
  assert.match(MIG, /CREATE FUNCTION public\.get_my_points_statement\(/, 'statement RPC defined');
  const stmt = MIG.slice(MIG.indexOf('CREATE FUNCTION public.get_my_points_statement('));
  assert.match(stmt, /WHERE m\.auth_id = auth\.uid\(\)/, 'caller derived from auth.uid()');
  assert.doesNotMatch(stmt, /p_member_id/, 'no p_member_id param → no IDOR surface');
  assert.match(stmt, /RAISE EXCEPTION 'Forbidden: authentication required'/, 'fail-closed for non-members');
  assert.match(stmt, /LEAST\(GREATEST\(COALESCE\(p_limit, 50\), 1\), 200\)/, 'limit clamped [1,200]');
  assert.match(stmt, /FROM public\.champions_awarded ca/, 'champion attribution joined via ref_id');
  assert.match(stmt, /'is_reversal', e\.is_reversal/, 'reversal flag exposed (wave 3 makes reversals real)');
  assert.match(stmt, /REVOKE ALL ON FUNCTION public\.get_my_points_statement\(text, text, integer, integer\) FROM public, anon;/, 'revoke public/anon');
  assert.match(stmt, /GRANT EXECUTE ON FUNCTION public\.get_my_points_statement\(text, text, integer, integer\) TO authenticated;/, 'grant authenticated');
});

test('1087: MCP exposes the transparency tools (web/agent parity)', () => {
  assert.match(MCP, /mcp\.tool\("get_gamification_rules_catalog"/, 'catalog tool registered');
  assert.match(MCP, /mcp\.tool\("get_my_points_statement"/, 'statement tool registered');
  assert.match(MCP, /mcp\.tool\("get_member_xp_pillars"/, 'xp pillars tool registered');
  const stmtTool = MCP.slice(MCP.indexOf('mcp.tool("get_my_points_statement"'), MCP.indexOf('mcp.tool("get_member_xp_pillars"'));
  assert.doesNotMatch(stmtTool, /member_id: z\./, 'statement tool declares NO member_id param (self-only by construction)');
  assert.doesNotMatch(stmtTool, /p_member_id/, 'statement tool dispatch passes NO member id to the RPC');
});

test('1087: recalculate_cycle_rankings MCP description no longer misleads (selection, not gamification)', () => {
  const toolIdx = MCP.indexOf('mcp.tool("recalculate_cycle_rankings"');
  const desc = MCP.slice(toolIdx, toolIdx + 700);
  assert.match(desc, /selection_ranking_snapshots/, 'names the real target table');
  assert.match(desc, /NOT the gamification leaderboard/, 'explicitly disclaims the gamification leaderboard');
});
