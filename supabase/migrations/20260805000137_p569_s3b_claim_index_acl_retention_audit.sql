-- Migration: 20260805000137_p569_s3b_claim_index_acl_retention_audit
-- Issue: #569 Slice 3 — council folds on draft review (wf_d1f15a73: 4/4 GO_W_FIXES, 0 blocker)
-- ADR: ADR-0101. Predecessor: 20260805000136 (Slice 3 core).
--
-- WHAT (3 council must-folds)
--   1. INDEX (data-architect MEDIUM): composite partial index so the claim filter
--      (claimed_at lease + stamp_attempts) is index-navigable — without it every unstamped
--      row is heap-fetched to evaluate the lease predicate; cheap NOW, before data volume.
--   2. ACL RESTATE (security MEDIUM): _ots_claim_unstamped_assets was rewritten in 000136 via
--      CREATE OR REPLACE relying on ACL inheritance from 000135 — correct, but fragile on
--      partial restores and invisible to a single-file audit. Made explicit + idempotent.
--   3. RETENTION AUDIT TRAIL (security MEDIUM): _ots_retention_pass deletes legal-evidence
--      artifacts irreversibly; its JSON return dies with the cron response (~6h TTL). It now
--      writes an admin_audit_log row (actor_id NULL = system; action 'ots.retention_pass')
--      whenever anything was deleted, so "when was X eliminated and under which window?" has
--      a durable answer. No-op passes (0/0) do NOT log (monthly noise).
--      + revoked_at forward-guard comment (data/security LOW): if a revoked_at column is ever
--      added to pi_exclusion_declarations, the window anchor must move to it (#572 scope).
--
-- ROLLBACK
--   DROP INDEX IF EXISTS public.idx_pi_excl_assets_claim;
--   -- restore _ots_retention_pass body from 20260805000136 (no audit insert);
--   -- ACL restate is idempotent — nothing to roll back.
--
-- After apply: NOTIFY pgrst, 'reload schema'.

-- ============================================================================
-- 1. Claim-filter index (partial, matches the lease predicate exactly)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_pi_excl_assets_claim
  ON public.pi_exclusion_assets (claimed_at, stamp_attempts)
  WHERE ots_status = 'unstamped';

-- Trigger-interaction note folded into the column comment (data-architect LOW): the claim
-- UPDATE bumps updated_at via trg_pi_excl_asset_updated_at — harmless today (_ots_list_pending
-- reads only 'pending'; ages use created_at) but future readers of updated_at must know.
COMMENT ON COLUMN public.pi_exclusion_assets.claimed_at IS
  '#569 S3 claim lease: set by _ots_claim_unstamped_assets; rows with a lease younger than 10 minutes are skipped by subsequent claims (covers the stamp EF 150s wall-clock; expired leases are reclaimed). NULL = never claimed. NOTE: the updated_at trigger fires on the claim UPDATE — updated_at on unstamped rows reflects claim time, not registration; use created_at for age math.';

-- ============================================================================
-- 2. Explicit ACL on the rewritten claim fn (restate from 000135 — idempotent)
-- ============================================================================

REVOKE EXECUTE ON FUNCTION public._ots_claim_unstamped_assets(integer) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._ots_claim_unstamped_assets(integer) TO service_role;

-- ============================================================================
-- 3. Retention pass + durable audit trail
-- ============================================================================

CREATE OR REPLACE FUNCTION public._ots_retention_pass(p_retention interval DEFAULT interval '5 years')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_assets_deleted integer := 0;
  v_decls_deleted  integer := 0;
BEGIN
  -- Floor the window at 1 year: a fat-fingered manual call ('1 day') must not mass-purge
  -- evidence. doc1 2.5.6 institutional windows are >= vínculo+5y; 5y is the default.
  IF p_retention < interval '1 year' THEN
    RAISE EXCEPTION '_ots_retention_pass: retention window % is below the 1-year safety floor', p_retention;
  END IF;

  -- 2a. Assets (digest + .ots bytea) of declarations revoked longer than the window.
  --     declarations have no revoked_at column; status is terminal once 'revoked' and every
  --     UPDATE touches updated_at, so updated_at >= revocation time (window is conservative).
  --     FORWARD-GUARD (#572): if a revoked_at column is ever added, anchor the window on it
  --     instead — the updated_at proxy is only safe while no post-revocation writes happen.
  WITH gone AS (
    DELETE FROM public.pi_exclusion_assets a
    USING public.pi_exclusion_declarations d
    WHERE a.declaration_id = d.id
      AND d.status = 'revoked'
      AND d.updated_at < now() - p_retention
    RETURNING a.id
  )
  SELECT count(*) INTO v_assets_deleted FROM gone;

  -- 2b. The now asset-free revoked declarations themselves (eliminação irreversível).
  WITH gone AS (
    DELETE FROM public.pi_exclusion_declarations d
    WHERE d.status = 'revoked'
      AND d.updated_at < now() - p_retention
      AND NOT EXISTS (SELECT 1 FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id)
    RETURNING d.id
  )
  SELECT count(*) INTO v_decls_deleted FROM gone;

  -- NOTE: 'error' assets of draft/active declarations are intentionally NOT touched — they are
  -- declarant-entered Anexo I rows (export_anexo_i surfaces them); deleting them here would be
  -- silent data loss. They leave via declarant re-registration or declaration revocation + window.

  -- Durable audit trail (council security MEDIUM): the JSON return below dies with the cron
  -- response TTL; irreversible elimination of evidence artifacts must leave a permanent row.
  -- actor_id NULL = system/cron actor. No-op passes do not log.
  IF v_assets_deleted > 0 OR v_decls_deleted > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL,
      'ots.retention_pass',
      'pi_exclusion_registry',
      NULL,
      jsonb_build_object(
        'assets_deleted', v_assets_deleted,
        'declarations_deleted', v_decls_deleted
      ),
      jsonb_build_object(
        'source', '_ots_retention_pass',
        'retention_window', p_retention::text,
        'ran_at', now()
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'retention_window', p_retention::text,
    'assets_deleted', v_assets_deleted,
    'declarations_deleted', v_decls_deleted,
    'ran_at', now()
  );
END;
$function$;

-- ACL unchanged but restated for single-file auditability (same rationale as section 2).
REVOKE EXECUTE ON FUNCTION public._ots_retention_pass(interval) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._ots_retention_pass(interval) TO service_role;

NOTIFY pgrst, 'reload schema';
