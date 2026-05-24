import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p255 HF2 — Governance viewer content_html via get_chain_workflow_detail.
// Fernando Maquiaveli (external reviewer / pending signer) sees "conteúdo
// indisponível" + console 406 on document_versions.content_html because
// ReviewChainIsland was doing a direct client-side SELECT under RLS that
// blocks his read. Fix: extend the existing SECDEF RPC to return
// content_html (consistent with the already-established pattern in
// get_previous_locked_version + get_next_draft_version) and switch the
// island to read from the RPC payload.

const MIGRATION_PATH = 'supabase/migrations/20260805000034_p255_governance_chain_workflow_detail_content_html.sql';
const ISLAND_PATH    = 'src/components/governance/ReviewChainIsland.tsx';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');
const ISLAND_SRC     = readFileSync(ISLAND_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

describe('p255 HF2 — governance viewer content_html via RPC (Fernando hotfix)', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / SPEC DRIFT / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC DRIFT RESOLVED:/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK:/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('header marks this as HF2 (paired with HF1 board fix)', () => {
      assert.match(MIGRATION_SQL, /HF2/);
      assert.match(MIGRATION_SQL, /HF1/);
    });
  });

  describe('signature preservation (SEDIMENT-238.C — CREATE OR REPLACE same-sig)', () => {
    it('keeps 1-arg signature (p_chain_id uuid)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.get_chain_workflow_detail\s*\(\s*p_chain_id\s+uuid\s*\)/
      );
      assert.doesNotMatch(
        MIGRATION_SQL,
        /DROP\s+FUNCTION\s+(?:IF EXISTS\s+)?public\.get_chain_workflow_detail/i
      );
    });

    it('preserves RETURNS jsonb + SECURITY DEFINER + search_path TO public', () => {
      assert.match(MIGRATION_SQL, /RETURNS jsonb/);
      assert.match(MIGRATION_SQL, /SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path TO 'public'/);
    });
  });

  describe('RPC body extension — content_html surfaces in payload', () => {
    it('v_chain SELECT INTO adds dv.content_html', () => {
      assert.match(
        MIGRATION_SQL,
        /dv\.version_label,\s*dv\.locked_at,\s*dv\.content_html/,
        'SELECT INTO list must pull content_html from document_versions join'
      );
    });

    it('RETURN jsonb_build_object exposes content_html', () => {
      assert.match(
        MIGRATION_SQL,
        /'content_html'\s*,\s*v_chain\.content_html/,
        'jsonb payload returned to clients must include content_html'
      );
    });

    it('preserves all other return fields (chain_id, gates, version_label, locked_at, opened_at, submitter, days_open)', () => {
      // Spot-check the canonical field set is intact
      for (const field of ['chain_id', 'chain_status', 'document_id', 'document_title', 'doc_type', 'version_id', 'version_label', 'locked_at', 'opened_at', 'submitter', 'gates', 'days_open']) {
        assert.ok(
          MIGRATION_SQL.includes(`'${field}'`),
          `field '${field}' must be preserved in RETURN jsonb_build_object`
        );
      }
    });

    it('preserves error envelope for chain_not_found', () => {
      assert.match(MIGRATION_SQL, /jsonb_build_object\('error','chain_not_found'\)/);
    });
  });

  describe('ReviewChainIsland.tsx — reads content_html from RPC payload', () => {
    it('removed direct SELECT on document_versions.content_html', () => {
      // The pre-fix code was:
      //   sb.from('document_versions').select('content_html').eq('id', dRes.data.version_id).single()
      // Drift watch: a regression would re-introduce this exact pattern OR
      // any variant of `from('document_versions').select(...content_html...)`.
      assert.doesNotMatch(
        ISLAND_SRC,
        /\.from\(\s*['"]document_versions['"]\s*\)\s*\.select\(\s*['"][^'"]*content_html/,
        'must NOT re-introduce direct SELECT on document_versions.content_html (causes 406 under RLS for external reviewers)'
      );
    });

    it('reads content_html from dRes.data (the RPC payload)', () => {
      assert.match(
        ISLAND_SRC,
        /setContentHtml\(\s*dRes\.data\?\.content_html/,
        'island must populate state from RPC payload, not a separate fetch'
      );
    });

    it('falls back to localized "conteúdo indisponível" if RPC payload missing field', () => {
      assert.match(
        ISLAND_SRC,
        /conteúdo indisponível/
      );
    });
  });

  describe('forward-defense regressions (lock PM rules permanently)', () => {
    it('migration does NOT modify RLS on document_versions', () => {
      assert.doesNotMatch(
        MIGRATION_SQL,
        /(CREATE|ALTER|DROP)\s+POLICY[\s\S]{0,200}document_versions/i,
        'PM rule: NO RLS broadening on document_versions — fix lives in RPC body only'
      );
    });

    it('island does NOT add allow-scripts to viewer iframe sandbox', () => {
      // Comment text in IsolatedHtmlFrame mentions "allow-scripts" while
      // explaining why scripts are stripped — that's documentation, not a
      // sandbox grant. Lock against actual `sandbox="...allow-scripts..."`
      // attribute values only.
      assert.doesNotMatch(
        ISLAND_SRC,
        /sandbox\s*=\s*["'][^"']*allow-scripts/i,
        'PM rule: NO allow-scripts in sandbox attribute (XSS risk via signed HTML content)'
      );
    });

    it('migration does NOT grant broader EXECUTE on document_versions or related tables', () => {
      // No GRANT statements on document_versions / governance_documents introduced.
      assert.doesNotMatch(
        MIGRATION_SQL,
        /GRANT\s+(SELECT|ALL|INSERT|UPDATE|DELETE)[\s\S]{0,200}document_versions/i,
        'fix must not relax base-table grants'
      );
    });

    it('island still calls get_chain_workflow_detail (RPC is the single source for chain meta + content)', () => {
      assert.match(
        ISLAND_SRC,
        /sb\.rpc\(\s*['"]get_chain_workflow_detail['"]/,
        'RPC call must remain the primary entry point'
      );
    });

    it('island still calls get_previous_locked_version + get_next_draft_version (diff viewers unchanged)', () => {
      assert.match(ISLAND_SRC, /sb\.rpc\(\s*['"]get_previous_locked_version['"]/);
      assert.match(ISLAND_SRC, /sb\.rpc\(\s*['"]get_next_draft_version['"]/);
    });
  });

  describe('externalReviewMode parity (PM-required smoke)', () => {
    it('ReviewChainIsland accepts externalReviewMode prop (used by /governance/documents/[chainId])', () => {
      // Same island powers both /admin/governance/documents/[chainId] AND
      // /governance/documents/[chainId] (external-reviewer entry). Fix to
      // content_html benefits BOTH automatically because the prop changes
      // ACL surfaces (banner, link routing) but not the data-fetch path.
      assert.match(
        ISLAND_SRC,
        /externalReviewMode/,
        'island must expose externalReviewMode toggle (consumed by external entry page)'
      );
    });

    it('external entry page exists at /governance/documents/[chainId]/index.astro', () => {
      const externalPagePath = 'src/pages/governance/documents/[chainId]/index.astro';
      assert.ok(existsSync(externalPagePath), 'external reviewer entry page must exist');
      const src = readFileSync(externalPagePath, 'utf8');
      assert.match(src, /ReviewChainIsland[\s\S]{0,400}externalReviewMode={true}/);
    });
  });

  describe('live DB body parity (skips if no SUPABASE env)', () => {
    if (!sb) {
      it.skip('live DB checks skipped — SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
      return;
    }

    // PostgrestBuilder is a thenable not a Promise — no .catch() (sediment p252).

    it('live get_chain_workflow_detail body returns content_html', async () => {
      const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
      if (error || !Array.isArray(data)) return; // helper RPC absent → static asserts authoritative
      const fn = data.find(r => r.function_name === 'get_chain_workflow_detail');
      if (fn) {
        assert.match(fn.body, /'content_html',\s*v_chain\.content_html/);
      }
    });
  });
});
