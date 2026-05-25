import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p257 Wave 1b first leaf — synthetic-chain backfill + V invariant activation.
// Spec: #367 (Step 1-6) + #315 P0-Q6 + handoff_p256 convention RATIFICADA.
//
// Two migrations cover the leaf:
//   M1: 20260805000038_p257_315_w1b_legacy_chain_backfill.sql
//     - 7 synthetic chains (status=active, gates[0].kind=member_ratification, threshold=1)
//     - 7 synthetic signoffs (signoff_type=acknowledge, content_snapshot.legacy_migration=true,
//       content_snapshot.role=migration_attestation, content_snapshot.p257_migration_marker=true)
//     - 7 governance_documents UPDATEs (closing_gate_signoff_id + approved_at;
//       current_ratified_* populated by trg_sync_ratification_cache auto-fire)
//     - 7 admin_audit_log rows (action=governance.legacy_chain_synthesized)
//     - 1 placeholder document_version for Termo Voluntariado (Classe 2, Sub-decision A)
//     - 3 triggers disabled+re-enabled (approval_signoff_xp + trg_approval_signoff_notify
//       + trg_artia_sync_on_govdoc_ratified) to suppress XP/notification/Artia side-effects
//   M2: 20260805000039_p257_315_w1b_v_invariant_activation.sql
//     - CREATE OR REPLACE FUNCTION check_schema_invariants() with V appended
//     - V_status_chain_coherence: status IN (approved,active) AND
//       current_ratified_chain_id IS NULL → violation
//     - COMMENT bumped 20 → 21
//     - Sanity DO RAISES if V violation_count != 0
//
// Forward-defense regressions locked:
//   - V body MUST NOT contain `metadata.legacy_pre_chain` (PM Q1=C rejected carve-out)
//   - V body MUST NOT contain `metadata.legacy_migration` (legacy_migration lives on
//     signoffs/chains, NOT on governance_documents; V scopes on gd.status + chain_id only)
//   - Signoff signoff_type MUST be 'acknowledge' NOT 'approval' (preserves semantic
//     distinction "migration attestation" vs "content approval" per PM convention)
//   - Chain gates[0].kind MUST be 'member_ratification' (1 member ratifies legacy migration
//     for invariant V coherence; preserves chain.gates allowlist + signoff.gate_kind UNIQUE)

const M1_PATH = 'supabase/migrations/20260805000038_p257_315_w1b_legacy_chain_backfill.sql';
const M2_PATH = 'supabase/migrations/20260805000039_p257_315_w1b_v_invariant_activation.sql';
const M1_SQL = readFileSync(M1_PATH, 'utf8');
const M2_SQL = readFileSync(M2_PATH, 'utf8');

// Strip `--` line comments to build CODE for forward-defense regex matching on
// LIVE SQL only — keeps ROLLBACK examples + KNOWN REGRESSION headers from
// triggering false positives. Block comments (/* ... */) are preserved (none
// in these migrations).
function stripLineComments(sql) {
  return sql.split('\n').map(l => {
    const idx = l.indexOf('--');
    return idx >= 0 ? l.slice(0, idx) : l;
  }).join('\n');
}

const M1_CODE = stripLineComments(M1_SQL);
const M2_CODE = stripLineComments(M2_SQL);

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;

// Canonical 7 legacy doc ids per #367 + PM convention
const LEGACY_DOC_IDS = [
  '3bff9307-c47a-4ec7-9502-c97a2d27ee53',
  '04e3e894-5155-4ac8-b844-fcac4c9de431',
  'ac5b5cb5-8dab-45eb-81d0-a1707fbc8ddb',
  'c32b174d-bf32-4692-afc6-34a27cebbf99',
  '9a0e5000-0000-0000-0000-000000000000',
  '7a8d47a1-e733-4cda-ad1c-cf35334931cf',
  'a78311fd-cf87-4bee-b0f1-e117a36095c5'
];

describe('p257 #367 Wave 1b first leaf — synthetic-chain backfill + V invariant activation', () => {
  describe('Migration file existence + header cross-refs', () => {
    it('M1 (20260805000038) file exists at canonical timestamp', () => {
      assert.ok(existsSync(M1_PATH), `M1 file missing at ${M1_PATH}`);
      assert.ok(M1_SQL.length > 0);
    });

    it('M2 (20260805000039) file exists at canonical timestamp', () => {
      assert.ok(existsSync(M2_PATH), `M2 file missing at ${M2_PATH}`);
      assert.ok(M2_SQL.length > 0);
    });

    it('M1 header documents WHAT / WHY / SPEC / SCOPE LOCK / CLASSIFICATION / SUB-DECISION / TRIGGER HANDLING / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(M1_SQL, /-- WHAT: Wave 1b first leaf/);
      assert.match(M1_SQL, /-- WHY:/);
      assert.match(M1_SQL, /-- SPEC:/);
      assert.match(M1_SQL, /-- SCOPE LOCK/);
      assert.match(M1_SQL, /-- CLASSIFICATION/);
      assert.match(M1_SQL, /-- SUB-DECISION A/);
      assert.match(M1_SQL, /-- TRIGGER HANDLING:/);
      assert.match(M1_SQL, /-- ROLLBACK/);
      assert.match(M1_SQL, /-- INVARIANTS:/);
      assert.match(M1_SQL, /-- CROSS-REF:/);
    });

    it('M2 header documents WHAT / WHY / SPEC / SCOPE LOCK / ORDERING / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(M2_SQL, /-- WHAT: Wave 1b first leaf/);
      assert.match(M2_SQL, /-- WHY:/);
      assert.match(M2_SQL, /-- SPEC:/);
      assert.match(M2_SQL, /-- SCOPE LOCK/);
      assert.match(M2_SQL, /-- ORDERING:/);
      assert.match(M2_SQL, /-- ROLLBACK/);
      assert.match(M2_SQL, /-- INVARIANTS:/);
      assert.match(M2_SQL, /-- CROSS-REF:/);
    });

    it('Both M1 and M2 cite #367 + #315 + Wave 1b for traceability', () => {
      assert.match(M1_SQL, /#367/);
      assert.match(M1_SQL, /#315/);
      assert.match(M1_SQL, /Wave 1b/);
      assert.match(M2_SQL, /#367/);
      assert.match(M2_SQL, /#315/);
      assert.match(M2_SQL, /Wave 1b/);
    });
  });

  describe('M1 — placeholder document_version (Classe 2 Sub-decision A)', () => {
    it('INSERTs placeholder version with canonical label gov-br-template-ciclo3-legacy-placeholder', () => {
      assert.match(M1_CODE, /INSERT INTO public\.document_versions/);
      assert.match(M1_CODE, /'gov-br-template-ciclo3-legacy-placeholder'/);
    });

    it('placeholder locked_at = now() (so invariant J is preserved when current_version_id is updated)', () => {
      // The INSERT VALUES sets locked_at to now(). Inline comment preserved in M1_SQL only.
      assert.match(M1_SQL, /now\(\),\s+-- locked_at \(locked from inception/);
    });

    it('targets Termo Voluntariado a78311fd-... document_id', () => {
      // Inline comment is on the value row in SELECT (preserved in M1_SQL only)
      assert.match(M1_SQL, /'a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid,\s*-- document_id/);
    });

    it('idempotent — WHERE NOT EXISTS clause guards against duplicate INSERT', () => {
      assert.match(M1_CODE, /WHERE NOT EXISTS \(\s*SELECT 1 FROM public\.document_versions\s+WHERE document_id='a78311fd[^']*'::uuid\s+AND version_label='gov-br-template-ciclo3-legacy-placeholder'\s*\)/);
    });

    it('UPDATE governance_documents sets Termo current_version_id to placeholder (idempotent on NULL current)', () => {
      assert.match(M1_CODE, /UPDATE public\.governance_documents\s+SET current_version_id = \(\s*SELECT id FROM public\.document_versions\s+WHERE document_id='a78311fd[^']*'::uuid\s+AND version_label='gov-br-template-ciclo3-legacy-placeholder'\s*\),/);
      assert.match(M1_CODE, /WHERE id='a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid\s+AND current_version_id IS NULL/);
    });
  });

  describe('M1 — trigger disable/re-enable bracket (3 triggers)', () => {
    it('DISABLEs exactly 3 side-effecting triggers BEFORE backfill', () => {
      const m1DisableSection = M1_CODE.split('DO $migration$')[0];
      assert.match(m1DisableSection, /ALTER TABLE public\.approval_signoffs DISABLE TRIGGER approval_signoff_xp;/);
      assert.match(m1DisableSection, /ALTER TABLE public\.approval_signoffs DISABLE TRIGGER trg_approval_signoff_notify;/);
      assert.match(m1DisableSection, /ALTER TABLE public\.governance_documents DISABLE TRIGGER trg_artia_sync_on_govdoc_ratified;/);
    });

    it('ENABLEs the same 3 triggers AFTER backfill DO block (re-enable ordering preserved)', () => {
      const m1AfterDo = M1_CODE.split('END $migration$;')[1] || '';
      assert.match(m1AfterDo, /ALTER TABLE public\.approval_signoffs ENABLE TRIGGER approval_signoff_xp;/);
      assert.match(m1AfterDo, /ALTER TABLE public\.approval_signoffs ENABLE TRIGGER trg_approval_signoff_notify;/);
      assert.match(m1AfterDo, /ALTER TABLE public\.governance_documents ENABLE TRIGGER trg_artia_sync_on_govdoc_ratified;/);
    });

    it('does NOT touch trg_approval_signoff_immutable (BEFORE UPDATE only — INSERTs not affected)', () => {
      assert.doesNotMatch(M1_CODE, /DISABLE TRIGGER trg_approval_signoff_immutable/);
      assert.doesNotMatch(M1_CODE, /ENABLE TRIGGER trg_approval_signoff_immutable/);
    });
  });

  describe('M1 — synthetic chain shape (status=active, member_ratification gate)', () => {
    it('INSERT approval_chains uses status=active (triggers trg_sync_ratification_cache cache fill)', () => {
      const insertChainsBlock = M1_CODE.match(/INSERT INTO public\.approval_chains[\s\S]{0,4000}?ON CONFLICT/);
      assert.ok(insertChainsBlock, 'INSERT approval_chains block must be present');
      assert.match(insertChainsBlock[0], /'active'/);
    });

    it('chain gates[0].kind = member_ratification (PM convention single-member ratification)', () => {
      assert.match(M1_CODE, /'kind',\s*'member_ratification'/);
    });

    it('chain gates[0] threshold = 1 (single signoff sufficient)', () => {
      assert.match(M1_CODE, /'threshold',\s*1/);
    });

    it('chain notes flagged with [p257 #367 Wave 1b first leaf] marker for ROLLBACK lookup', () => {
      assert.match(M1_CODE, /'\[p257 #367 Wave 1b first leaf\] Synthetic legacy chain/);
    });

    it('chain ON CONFLICT (document_id, version_id) DO NOTHING for idempotency', () => {
      assert.match(M1_CODE, /ON CONFLICT \(document_id, version_id\) DO NOTHING/);
    });
  });

  describe('M1 — synthetic signoff shape (acknowledge + migration_attestation)', () => {
    it('signoff_type = acknowledge (NOT approval — preserves semantic distinction per PM convention)', () => {
      // Signoff INSERT must use acknowledge
      assert.match(M1_CODE, /'acknowledge'/);
    });

    it('FORWARD-DEFENSE: signoff_type literal MUST NOT be \'approval\' in INSERT approval_signoffs block', () => {
      // Slice the M1 signoff INSERT body and assert NO 'approval' literal appears as signoff_type
      const sigInsertMatch = M1_CODE.match(/INSERT INTO public\.approval_signoffs[\s\S]{0,4000}?ON CONFLICT/);
      assert.ok(sigInsertMatch, 'INSERT approval_signoffs block must be present');
      // Within the signoff INSERT body, the only signoff_type value should be 'acknowledge'.
      // approval_signoffs.signoff_type CHECK allows: 'approval','acknowledge','abstain','rejection'.
      // If a future regression changes to 'approval', this assertion catches it.
      assert.doesNotMatch(sigInsertMatch[0], /signoff_type[^,]*,\s*'approval'/);
      // ...and the 4th positional value (signoff_type) in VALUES (... , 'member_ratification', v_pm_id, 'X', ...) should be 'acknowledge'
      assert.match(sigInsertMatch[0], /'member_ratification',\s+v_pm_id,\s+'acknowledge'/);
    });

    it('content_snapshot includes legacy_migration=true + role=<class-specific> + p257_migration_marker=true + invariant_anchor', () => {
      assert.match(M1_CODE, /'legacy_migration',\s*true/);
      assert.match(M1_CODE, /'role',\s*v_role/);
      assert.match(M1_CODE, /'p257_migration_marker',\s*true/);
      assert.match(M1_CODE, /'invariant_anchor',\s*'V_status_chain_coherence'/);
    });

    it('signature_hash uses deterministic md5(chain_id || legacy-attestation-p257-issue-367)', () => {
      assert.match(M1_CODE, /md5\(v_chain_id::text\s*\|\|\s*'-legacy-attestation-p257-issue-367'\)/);
    });

    it('per-class role detection — Classe 1 docusign / Classe 2 interim_external_template / Classe 3 internal_attestation', () => {
      assert.match(M1_CODE, /v_role := 'migration_attestation'/);
      assert.match(M1_CODE, /v_role := 'interim_external_template'/);
      assert.match(M1_CODE, /v_source_ev := 'docusign'/);
      assert.match(M1_CODE, /v_source_ev := 'gov_br_template'/);
      assert.match(M1_CODE, /v_source_ev := 'internal_attestation'/);
    });
  });

  describe('M1 — governance_documents UPDATE + admin_audit_log per-doc', () => {
    it('UPDATE governance_documents sets closing_gate_signoff_id + approved_at (cache trigger handles ratified_*)', () => {
      assert.match(M1_CODE, /UPDATE public\.governance_documents\s+SET closing_gate_signoff_id = v_signoff_id,\s+approved_at = v_doc\.created_at/);
    });

    it('admin_audit_log uses canonical action governance.legacy_chain_synthesized + metadata.migration cite', () => {
      assert.match(M1_CODE, /'governance\.legacy_chain_synthesized'/);
      assert.match(M1_CODE, /'migration',\s*'20260805000038_p257_315_w1b_legacy_chain_backfill'/);
    });

    it('admin_audit_log target_type = governance_document + target_id = doc_id', () => {
      assert.match(M1_CODE, /'governance_document',\s*\n?\s*v_doc\.id/);
    });
  });

  describe('M1 — sanity DO + idempotency', () => {
    it('sanity DO RAISES if any of 7 docs lacks current_ratified_chain_id post-backfill', () => {
      // Quantifier widened (~2000 chars) because the WHERE IN list of 7 UUIDs +
      // surrounding SELECT body sits between "Sanity DO" header and the RAISE.
      assert.match(M1_SQL, /Sanity DO[\s\S]{0,2000}?RAISE EXCEPTION 'p257 #367 backfill sanity FAIL: % docs ainda têm current_ratified_chain_id IS NULL/);
    });

    it('sanity DO asserts chain count = 7 (synthetic chains only)', () => {
      assert.match(M1_SQL, /IF v_chain_count <> 7 THEN/);
    });

    it('sanity DO asserts signoff count = 7 (acknowledge + member_ratification + p257_migration_marker)', () => {
      assert.match(M1_SQL, /IF v_signoff_count <> 7 THEN/);
    });

    it('sanity DO asserts audit count = 7', () => {
      assert.match(M1_SQL, /IF v_audit_count <> 7 THEN/);
    });

    it('NOTIFY pgrst, reload schema at end (cache invalidation)', () => {
      assert.match(M1_CODE, /NOTIFY pgrst,\s*'reload schema'/);
    });
  });

  describe('M2 — V invariant activation + COMMENT bump', () => {
    it('CREATE OR REPLACE FUNCTION public.check_schema_invariants() with same signature (RETURNS TABLE)', () => {
      assert.match(M2_CODE, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants\(\)/);
      assert.match(M2_CODE, /RETURNS TABLE\(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid\[\]\)/);
    });

    it('V invariant uses EXACT name V_status_chain_coherence', () => {
      assert.match(M2_CODE, /'V_status_chain_coherence'::text/);
    });

    it('V invariant body checks status IN (approved, active) AND current_ratified_chain_id IS NULL', () => {
      // Find the V invariant WITH drift AS block — find the labelled SELECT and walk backwards
      const labelIdx = M2_CODE.indexOf("'V_status_chain_coherence'::text");
      assert.ok(labelIdx > 0, 'V_status_chain_coherence label not found in M2 body');
      const upToLabel = M2_CODE.slice(0, labelIdx);
      const withIdx = upToLabel.lastIndexOf('WITH drift AS (');
      assert.ok(withIdx > 0, 'V WITH drift AS ( block not found');
      const vBody = M2_CODE.slice(withIdx, labelIdx);
      assert.match(vBody, /gd\.status IN\s*\(\s*'approved',\s*'active'\s*\)/);
      assert.match(vBody, /gd\.current_ratified_chain_id IS NULL/);
    });

    it('V invariant tagged high severity', () => {
      const vLabelIdx = M2_CODE.indexOf("'V_status_chain_coherence'::text");
      const after = M2_CODE.slice(vLabelIdx, vLabelIdx + 800);
      assert.match(after, /'high'::text/);
    });

    it('V invariant description references #315 P0-Q6 + #367 Wave 1b + NO carve-out + migration 20260805000038', () => {
      const vLabelIdx = M2_CODE.indexOf("'V_status_chain_coherence'::text");
      const after = M2_CODE.slice(vLabelIdx, vLabelIdx + 800);
      assert.match(after, /#315 P0-Q6/);
      assert.match(after, /#367 Wave 1b first leaf/);
      assert.match(after, /NO carve-out/);
      assert.match(after, /20260805000038/);
    });

    it('V invariant comes AFTER V_prime in body ordering (alphabetical preservation)', () => {
      const vPrimeIdx = M2_CODE.indexOf("'V_prime_pending_proposer_consent_no_open_chain'");
      const vIdx = M2_CODE.indexOf("'V_status_chain_coherence'");
      assert.ok(vPrimeIdx > 0, 'V_prime must still be present (no regression)');
      assert.ok(vIdx > vPrimeIdx, 'V must appear after V_prime');
    });

    it('COMMENT ON FUNCTION cites 21 schema invariants + Wave 1b/V/#367/#315', () => {
      const commentMatch = M2_CODE.match(/COMMENT ON FUNCTION public\.check_schema_invariants\(\)\s+IS\s+'([^']+)'/);
      assert.ok(commentMatch, 'COMMENT ON FUNCTION must be present in M2');
      const body = commentMatch[1];
      assert.match(body, /21 schema invariants/);
      assert.match(body, /V_status_chain_coherence/);
      assert.match(body, /Wave 1b/);
      assert.match(body, /#367/);
      assert.match(body, /#315/);
      assert.match(body, /20260805000038/);
    });

    it('sanity DO RAISES if V violation_count != 0 OR V absent', () => {
      assert.match(M2_SQL, /Sanity DO[\s\S]{0,500}?RAISE EXCEPTION 'p257 #367 V activation sanity FAIL/);
      assert.match(M2_SQL, /V_status_chain_coherence not present in result set/);
      assert.match(M2_SQL, /V returned % violations \(expected 0\)/);
    });

    it('NOTIFY pgrst at end', () => {
      assert.match(M2_CODE, /NOTIFY pgrst,\s*'reload schema'/);
    });
  });

  describe('M2 — FORWARD-DEFENSE: NO carve-out via metadata flags', () => {
    it('V body MUST NOT contain `metadata.legacy_pre_chain` (PM Q1=C rejected this shortcut)', () => {
      // Extract V invariant body (WITH drift AS + the SELECT after)
      const vLabelIdx = M2_CODE.indexOf("'V_status_chain_coherence'::text");
      const upToLabel = M2_CODE.slice(0, vLabelIdx);
      const withIdx = upToLabel.lastIndexOf('WITH drift AS (');
      const fromLabelEnd = M2_CODE.slice(vLabelIdx, vLabelIdx + 1500);
      const vBlock = M2_CODE.slice(withIdx, vLabelIdx + 1500);
      // The V block MUST NOT mention legacy_pre_chain (which would imply a carve-out filter)
      assert.doesNotMatch(vBlock, /metadata\.legacy_pre_chain/);
      assert.doesNotMatch(vBlock, /metadata->>'legacy_pre_chain'/);
      assert.doesNotMatch(vBlock, /legacy_pre_chain/);
    });

    it('V body MUST NOT scope on `metadata.legacy_migration` (legacy_migration lives on signoffs/chains, not on gd)', () => {
      const vLabelIdx = M2_CODE.indexOf("'V_status_chain_coherence'::text");
      const upToLabel = M2_CODE.slice(0, vLabelIdx);
      const withIdx = upToLabel.lastIndexOf('WITH drift AS (');
      const vBlockBody = M2_CODE.slice(withIdx, vLabelIdx);
      // The WHERE clause of V's drift CTE must NOT reference metadata.legacy_migration
      // (V only filters on gd.status + gd.current_ratified_chain_id — no carve-out)
      assert.doesNotMatch(vBlockBody, /metadata->>'legacy_migration'/);
      assert.doesNotMatch(vBlockBody, /metadata\.legacy_migration/);
    });

    it('V drift CTE filters ONLY on status + current_ratified_chain_id (no other conditions)', () => {
      const vLabelIdx = M2_CODE.indexOf("'V_status_chain_coherence'::text");
      const upToLabel = M2_CODE.slice(0, vLabelIdx);
      const withIdx = upToLabel.lastIndexOf('WITH drift AS (');
      const vBlockBody = M2_CODE.slice(withIdx, vLabelIdx);
      // The WHERE clause should have exactly 2 conditions joined by AND
      const whereMatch = vBlockBody.match(/WHERE\s+([\s\S]+?)\)\s*SELECT/);
      assert.ok(whereMatch, 'WHERE clause of V drift CTE not parseable');
      const whereBody = whereMatch[1];
      // Allow only `gd.status IN (...)` and `gd.current_ratified_chain_id IS NULL`
      // (joined by single AND).
      const conditions = whereBody.split(/\bAND\b/i).map(s => s.trim()).filter(Boolean);
      assert.equal(conditions.length, 2,
        `V drift CTE WHERE must have exactly 2 conditions (status + chain_id). Got: ${conditions.length}\n${whereBody}`);
      assert.ok(conditions.some(c => /gd\.status IN/.test(c)));
      assert.ok(conditions.some(c => /gd\.current_ratified_chain_id IS NULL/.test(c)));
    });
  });

  describe('DB-gated — live invariant table state (post-M1+M2)', () => {
    it('check_schema_invariants() returns 21 rows (V activated as 21st)', async (t) => {
      if (!sb) { t.skip('SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set'); return; }
      const { data, error } = await sb.rpc('check_schema_invariants');
      assert.equal(error, null, `RPC error: ${error?.message}`);
      assert.equal(data.length, 21,
        `Expected 21 invariants, got ${data.length}. Body: ${data.map(r => r.invariant_name).join(', ')}`);
    });

    it('V_status_chain_coherence present + violation_count = 0', async (t) => {
      if (!sb) { t.skip('SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set'); return; }
      const { data, error } = await sb.rpc('check_schema_invariants');
      assert.equal(error, null);
      const v = data.find(r => r.invariant_name === 'V_status_chain_coherence');
      assert.ok(v, 'V_status_chain_coherence must be present in result set');
      assert.equal(v.violation_count, 0,
        `V_status_chain_coherence must return 0 violations post-backfill. Got: ${v.violation_count}, sample_ids: ${JSON.stringify(v.sample_ids)}`);
    });

    it('all 7 canonical legacy docs have current_ratified_chain_id NOT NULL', async (t) => {
      if (!sb) { t.skip('SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set'); return; }
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, current_ratified_chain_id, closing_gate_signoff_id')
        .in('id', LEGACY_DOC_IDS);
      assert.equal(error, null);
      assert.equal(data.length, 7, `Expected 7 docs, got ${data.length}`);
      for (const row of data) {
        assert.ok(row.current_ratified_chain_id, `Doc ${row.id} missing current_ratified_chain_id`);
        assert.ok(row.closing_gate_signoff_id, `Doc ${row.id} missing closing_gate_signoff_id`);
      }
    });
  });
});
