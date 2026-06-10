/**
 * Contract: #569 Slice 4a+4c — PI-exclusion MCP surface + Art. 18 portability + lifecycle.
 *
 * 4c (migration 20260805000139, ADR-0101 deferred L57-58):
 *   - export_my_data() gains the 'pi_exclusion' section (declarant's declarations + Anexo I
 *     metadata; the .ots bytea is NOT inlined — presence flag only; the proof artifact is
 *     export_anexo_i's job). Body regenerated from LIVE prosrc (documented drift history).
 *   - create_exclusion_declaration() audits the create (admin_audit_log) and PRESERVES its
 *     live DEFAULT NULL on p_title (SEDIMENT-238.C — the first apply attempt 42P13'd on a
 *     dropped default; this test locks the signature).
 *   - NEW revoke_exclusion_declaration(): 'revoked' was UNREACHABLE (no RPC set it — the
 *     retention pass purged a dead path). Owner-only, terminal, idempotent, audited; assets
 *     KEPT through the retention window (mig 137 eliminates 5y post-revocation).
 *
 * 4a: 6 MCP tools (list/get/create/register/revoke/export_anexo_i) — self-service family,
 *     RPCs self-gate on declarant ownership; revoke carries the ADR-0018 W1 confirm/preview.
 *
 * Live smokes recorded in the PR: create→export(sees section)→revoke→idempotent re-revoke;
 * owner gate denies non-owner; 2 audit rows; smoke rows cleaned (tables back to 0/0).
 *
 * Cross-ref: #569, ADR-0101, LGPD Art. 18 II, #572 (retention program), mig 137 (retention).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG_PATH = 'supabase/migrations/20260805000139_p569_s4c_export_my_data_pi_exclusion_audit_revoke.sql';
const MIG = readFileSync(MIG_PATH, 'utf8');
const MIG140_PATH = 'supabase/migrations/20260805000140_p569_s4_council_folds_revoked_at.sql';
const MIG140 = readFileSync(MIG140_PATH, 'utf8');
const MCP_INDEX = readFileSync('supabase/functions/nucleo-mcp/index.ts', 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

function fnBody(name, src = MIG140) {
  const m = src.match(new RegExp(
    `CREATE OR REPLACE FUNCTION public\\.${name}\\([^)]*\\)[\\s\\S]*?AS \\$function\\$([\\s\\S]*?)\\$function\\$;`
  ));
  return m ? m[1] : '';
}
// All 3 bodies were re-captured in 140 (council folds: FOR UPDATE, revoked_at, legal-basis
// retention note, eficacia_plena, dead-var drop) — the LATEST capture must match live.
const EXPORT_BODY = fnBody('export_my_data');
const CREATE_BODY = fnBody('create_exclusion_declaration');
const REVOKE_BODY = fnBody('revoke_exclusion_declaration');

function toolBlock(name) {
  const parts = MCP_INDEX.split(`mcp.tool("${name}"`);
  return parts.length > 1 ? parts[1].split('mcp.tool(')[0] : '';
}

describe('p569-s4 — migration presence + header', () => {
  it('migration exists with the slice cross-refs', () => {
    assert.ok(existsSync(MIG_PATH));
    assert.match(MIG, /#569/);
    assert.match(MIG, /ADR-0101/);
    assert.match(MIG, /Art\. 18/);
    assert.match(MIG, /#572/);
    assert.match(MIG, /NOTIFY pgrst, 'reload schema';/);
  });
});

describe('p569-s4 — 4c.1 export_my_data portability section', () => {
  it("adds the 'pi_exclusion' section filtered to the declarant", () => {
    assert.match(EXPORT_BODY, /'pi_exclusion', COALESCE\(\(/);
    assert.match(EXPORT_BODY, /FROM public\.pi_exclusion_declarations d WHERE d\.declarant_member_id = v_member_id/);
  });

  it('exports Anexo I metadata incl. anchor + proof PRESENCE flag', () => {
    assert.match(EXPORT_BODY, /'sha256', a\.sha256/);
    assert.match(EXPORT_BODY, /'prova_ots', \(a\.ots_proof IS NOT NULL\)/);
    assert.match(EXPORT_BODY, /'ancoragem', CASE WHEN a\.ots_status = 'confirmed'/);
    assert.match(EXPORT_BODY, /'eficacia_plena', COALESCE\(\(/, 'doc7 Cl.4.1 surfaced per declaration (legal fold)');
    assert.match(EXPORT_BODY, /'revoked_at', d\.revoked_at/);
  });

  it('forward-defense: the .ots bytea is never inlined into the JSON export', () => {
    assert.ok(!/'ots_proof',\s*a\.ots_proof/.test(EXPORT_BODY), 'raw bytea must not be a JSON value');
    assert.ok(!/encode\(\s*a?\.?ots_proof/.test(EXPORT_BODY), 'no base64/hex inlining of the proof either — the artifact export is export_anexo_i');
  });

  it('every pre-existing export section survives the regeneration (drift-history guard)', () => {
    for (const key of ['profile','person','engagements','attendance','gamification','notifications',
                       'board_assignments','cycle_history','certificates','selection_applications',
                       'onboarding','consent_records','exported_at']) {
      assert.match(EXPORT_BODY, new RegExp(`'${key}',`), `section '${key}' must survive`);
    }
  });
});

describe('p569-s4 — 4c.2 create audit + signature lock', () => {
  it('preserves the live DEFAULT NULL on p_title (SEDIMENT-238.C)', () => {
    assert.match(MIG140, /CREATE OR REPLACE FUNCTION public\.create_exclusion_declaration\(p_title text DEFAULT NULL::text\)/,
      'dropping a parameter default 42P13s on CREATE OR REPLACE — probe pg_get_function_arguments BEFORE migrating');
  });

  it('audits the create into admin_audit_log', () => {
    assert.match(CREATE_BODY, /'pi_exclusion\.declaration_created'/);
    assert.match(CREATE_BODY, /COALESCE\(p_title, '\[sem título\]'\)/, 'audit trail stays human-readable without a title (legal fold)');
    assert.match(CREATE_BODY, /INSERT INTO public\.admin_audit_log/);
  });
});

describe('p569-s4 — 4c.3 revoke lifecycle', () => {
  it('serializes concurrent revokes (FOR UPDATE — no phantom audit rows) and stamps revoked_at', () => {
    assert.match(REVOKE_BODY, /FROM public\.pi_exclusion_declarations WHERE id = p_declaration_id\s+FOR UPDATE;/,
      'council security fold: the loser of a dual-revoke must re-read revoked and take the idempotent path');
    assert.match(REVOKE_BODY, /SET status = 'revoked', revoked_at = now\(\)/,
      'revoked_at = immutable retention anchor (LGPD Art. 6º III)');
  });

  it('retention note states the legal basis (Art. 7º IX as the Art. 18 VI exception) + DPO contact', () => {
    assert.match(REVOKE_BODY, /Art\. 7º, IX da LGPD/);
    assert.match(REVOKE_BODY, /Art\. 18, VI/);
    assert.match(REVOKE_BODY, /dpo@pmigo\.org\.br/);
  });

  it('owner-only: non-declarant is raised out', () => {
    assert.match(REVOKE_BODY, /IF v_owner <> v_member_id THEN/);
    assert.match(REVOKE_BODY, /only the declarant can revoke/);
  });

  it('terminal + idempotent: draft|active → revoked; re-revoke short-circuits', () => {
    assert.match(REVOKE_BODY, /WHERE id = p_declaration_id AND status IN \('draft', 'active'\)/);
    assert.match(REVOKE_BODY, /'already_revoked', true/);
  });

  it('audits the revocation with from/to status', () => {
    assert.match(REVOKE_BODY, /'pi_exclusion\.declaration_revoked'/);
    assert.match(REVOKE_BODY, /jsonb_build_object\('from', v_status, 'to', 'revoked'\)/);
  });

  it('forward-defense: revoke never deletes assets (evidence kept through retention)', () => {
    assert.ok(!/DELETE FROM/.test(REVOKE_BODY),
      'asset elimination belongs to _ots_retention_pass (mig 137, 5y window) — never to revoke');
    assert.match(REVOKE_BODY, /'assets_kept', v_assets/);
  });

  it('ACL: anon revoked, authenticated granted (RPC self-gates on ownership)', () => {
    assert.match(MIG, /REVOKE ALL ON FUNCTION public\.revoke_exclusion_declaration\(uuid\) FROM PUBLIC, anon;/);
    assert.match(MIG, /GRANT EXECUTE ON FUNCTION public\.revoke_exclusion_declaration\(uuid\) TO authenticated;/);
  });
});

describe('p569-s4 — 4a MCP surface (6 tools)', () => {
  const TOOLS = ['list_my_exclusion_declarations', 'get_exclusion_declaration', 'create_exclusion_declaration',
                 'register_exclusion_asset', 'revoke_exclusion_declaration', 'export_anexo_i'];

  for (const t of TOOLS) {
    it(`${t}: registered with the logUsage pattern`, () => {
      const block = toolBlock(t);
      assert.ok(block.length > 0, `tool ${t} registered`);
      assert.match(block, new RegExp(`logUsage\\(sb, null, "${t}", false, "Not authenticated", start\\)`));
      assert.match(block, new RegExp(`logUsage\\(sb, member\\.id, "${t}", true, undefined, start\\)`));
    });
  }

  it('revoke tool carries the ADR-0018 W1 confirm/preview gate', () => {
    const block = toolBlock('revoke_exclusion_declaration');
    assert.match(block, /confirm: z\.boolean\(\)\.optional\(\)/);
    assert.match(block, /if \(!params\.confirm\) \{/);
    assert.match(block, /action: "revoke_exclusion_declaration",\s+preview: true/, 'ADR-0018 W1 envelope shape: action + preview');
    assert.match(block, /target: preview/, 'live-fetched object goes under target: (shape parity with the other 5 destructive tools)');
    assert.match(block, /next_call: \{ declaration_id: params\.declaration_id, confirm: true \}/);
    assert.match(block, /REVOGAÇÃO É TERMINAL/);
    assert.match(block, /logUsage\(sb, member\.id, "revoke_exclusion_declaration", true, undefined, start, "preview"\)/,
      'preview logs resultKind=preview — NOT errorMsg=preview (council ai-engineer MEDIUM)');
  });

  it('register tool forwards all 8 RPC params (optionals as null)', () => {
    const block = toolBlock('register_exclusion_asset');
    for (const p of ['p_declaration_id','p_title','p_sha256','p_nature','p_author_label','p_work_created_on','p_source_ref','p_reinforcement']) {
      assert.match(block, new RegExp(p), `param ${p} forwarded`);
    }
  });

  it('sha256 param carries a Zod-level format guard (fail before the RPC round-trip)', () => {
    const block = toolBlock('register_exclusion_asset');
    assert.match(block, /sha256: z\.string\(\)\.regex\(\/\^\[0-9a-fA-F\]\{64\}\$\//);
  });

  it('export_anexo_i description teaches the fiscalization audit (pii_access_log) + eficácia semantics', () => {
    assert.match(MCP_INDEX, /pii_access_log, LGPD Art\. 37/);
    assert.match(MCP_INDEX, /all_confirmed flag \(eficácia probatória plena requires ALL assets confirmed/);
  });
});

describe('p569-s4 — DB-gated (skip without env)', () => {
  it('live bodies match the migration captures (Phase-C md5, 3 fns)', { skip: !sb }, async () => {
    const { createHash } = await import('node:crypto');
    const localMd5 = (b) => createHash('md5').update(b.replace(/\s+/g, ' ')).digest('hex');
    const expected = {
      export_my_data: localMd5(EXPORT_BODY),
      create_exclusion_declaration: localMd5(CREATE_BODY),
      revoke_exclusion_declaration: localMd5(REVOKE_BODY),
    };
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) { console.warn(`[p569-s4] helper unavailable: ${error.message}`); return; }
    for (const [name, md5] of Object.entries(expected)) {
      const fn = (data ?? []).find((f) => f.proname === name);
      assert.ok(fn, `${name} exists live`);
      assert.equal(fn.is_secdef, true, `${name} is SECURITY DEFINER`);
      assert.equal(fn.body_md5, md5, `${name} live body drifted from the migration capture`);
    }
  });

  it('live create_exclusion_declaration keeps its p_title DEFAULT (identity check)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
    if (error) { console.warn(`[p569-s4] helper unavailable: ${error.message}`); return; }
    const fn = (data ?? []).find((f) => f.proname === 'create_exclusion_declaration');
    assert.ok(fn, 'fn exists');
    assert.equal(fn.identity_args, 'p_title text', 'single text param (identity args drop defaults — locked via the static signature test)');
  });

  it('migration 20260805000139 registered once (no wall-clock shadow)', { skip: !sb }, async () => {
    const { data, error } = await sb.rpc('_audit_list_schema_migrations');
    if (error) { console.warn(`[p569-s4] helper unavailable: ${error.message}`); return; }
    const rows = (data ?? []).filter((r) => r.name === 'p569_s4c_export_my_data_pi_exclusion_audit_revoke');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].version, '20260805000139');
  });
});
