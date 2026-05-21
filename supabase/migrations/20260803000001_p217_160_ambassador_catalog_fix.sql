-- Migration: p217 #160 — engagement_kinds catalog reconciliation for `ambassador`
-- Date: 2026-05-21
-- Session: p217
-- Issue: #160 (permissions: resolve Herlon study_group_owner authority state)
-- Path: A' (PM-picked 2026-05-21 — see decision log entry DECISION-160)
--
-- WHAT
-- Sets engagement_kinds.requires_agreement = false WHERE slug = 'ambassador'.
--
-- WHY
-- The catalog row for `ambassador` is internally contradictory:
--   - description: "Reconhecimento honorário / mérito. Sem termo obrigatório."
--   - legal_basis: consent
--   - requires_agreement: TRUE  ← contradicts description + legal_basis + ADR-0006/0008
--   - agreement_template: NULL  ← no template even defined
-- ADR-0006 line 55 is canonical:
--   `kind=ambassador, status=active, legal_basis=consent, end_date=null, agreement=null`
--                                                                       ^^^^^^^^^^^^
-- ADR-0008 §lifecycle table (line 25) is the operational source of truth:
--   `ambassador (mérito, Herlon) | Nomeação → Sem termo → Indefinido (revogável) → Delete on request | Consent`
--                                                  ^^^^^^^^^^^
--
-- HISTORY (pre-existing migration acknowledgment)
-- Migration 20260419010000 (lines 99-104) explicitly re-set requires_agreement=true
-- for ambassador with the rationale "Formal external role: keep consent, require
-- agreement". That reasoning conflated two distinct uses of "consent": (a) LGPD
-- Art. 7 I consent as legal basis for data processing (which requires written
-- documentation per Art. 8), vs (b) consent in the colloquial sense of accepting
-- a merit recognition (no written instrument required). Per ADR-0008 line 25,
-- ambassador uses (b) — "Nomeação → Sem termo". This migration overrides the
-- 20260419010000 decision and aligns the catalog with the canonical ADR position.
--
-- Surfaced during p217 issue #160 investigation: 12 of 16 "pending agreement"
-- engagements were ambassadors that the design never required termo for.
--
-- IMPACT
-- After this UPDATE:
--   - 12 ambassador engagements (8 distinct members) flip to
--     auth_engagements.is_authoritative=true automatically via the view's
--     `OR NOT COALESCE(ek.requires_agreement, false)` branch.
--   - Real termo-needing backlog drops 16 → 4 engagements / 3 members
--     (Herlon SGO + Fernando SGP + Vitor volunteer x2).
--   - ZERO V4 capability side-effects: engagement_kind_permissions WHERE
--     kind='ambassador' has 0 rows. Ambassadors gain authoritative status
--     but no new actions/scopes — their kind grants nothing in the V4 matrix.
--
-- PRE-STATE EVIDENCE (live 2026-05-21 via execute_sql, pre-migration)
--   ambassador.requires_agreement: TRUE
--   ambassador.legal_basis: consent
--   ambassador.description: "Reconhecimento honorário / mérito. Sem termo obrigatório."
--   ambassador.agreement_template: NULL
--   ambassador capability rows (engagement_kind_permissions): 0
--   pending engagements (ambassador, requires_agreement=true, no cert): 12
--   distinct affected members: 8
--
-- POST-STATE EXPECTED
--   ambassador.requires_agreement: FALSE
--   pending agreement backlog total: 16 → 4
--   ambassador in get_pending_agreement_engagements() output: 0
--   check_schema_invariants(): 19 rows, all violation_count=0 (unchanged)
--
-- ROLLBACK
--   UPDATE public.engagement_kinds SET requires_agreement = true WHERE slug = 'ambassador';
--   -- Would re-add the 12 engagements to the pending queue. Idempotent — no rows depend on this flag's value beyond view evaluation.
--   -- Note: no need to revoke any certificates (none were issued). No audit log
--   -- needed since this is a catalog correction, not a member-state transition.
--
-- KNOWN FALSE-POSITIVE (post-fix)
-- `public.validate_privacy_policy_consistency()` (migration 20260418010000,
-- lines 268-276) flags any kind with `legal_basis='consent' AND NOT requires_agreement`
-- as severity='error' with message "Consent-based kind does not require agreement.
-- LGPD Art. 8 requires explicit consent documentation." Post-fix, ambassador will
-- trip this branch. This is a FALSE POSITIVE — the validator's assumption that
-- consent always means LGPD Art. 7 I + Art. 8 is overly strict for merit-recognition
-- kinds where "consent" is the colloquial acceptance of a title. Currently dormant
-- in production (RPC is not exposed via MCP and is not called from any page or
-- test), so no live breakage. Documented to prevent a future session from "fixing"
-- ambassador back to requires_agreement=true based on the validator alert.
-- Follow-up: P162 WATCH-217.A (consider is_merit_only column or RPC exemption).
--
-- ADR cross-ref:
--   - ADR-0006 line 55 (canonical engagement_kind row shape for ambassador)
--   - ADR-0008 line 25 (lifecycle table — "Nomeação → Sem termo" for ambassador)
--   - ADR-0006 §"Reconciliação de catálogo" 2026-05-21 (this fix in narrative form)
-- Decision log: docs/audit/P162_GAP_OPPORTUNITY_LOG.md DECISION-160 + RESOLVED-160.A
-- Forward-defense test: tests/contracts/engagement-kinds-catalog-invariants.test.mjs

BEGIN;

UPDATE public.engagement_kinds
SET
  requires_agreement = false,
  updated_at = now()
WHERE slug = 'ambassador'
  AND requires_agreement = true;  -- idempotent guard

-- Sanity-check inside transaction: confirm exactly one row updated (or zero if re-run)
-- and that ambassador is now false. RAISE if invariant violated.
DO $$
DECLARE
  v_requires_agreement boolean;
BEGIN
  SELECT requires_agreement INTO v_requires_agreement
  FROM public.engagement_kinds
  WHERE slug = 'ambassador';

  IF v_requires_agreement IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'p217 #160 catalog fix failed: ambassador.requires_agreement = %, expected false', v_requires_agreement;
  END IF;
END;
$$;

COMMIT;
