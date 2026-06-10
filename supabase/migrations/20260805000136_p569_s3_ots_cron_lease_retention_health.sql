-- Migration: 20260805000136_p569_s3_ots_cron_lease_retention_health
-- Issue: #569 Slice 3 — pg_cron scheduling + claim lease + registry retention + pipeline health
-- ADR: ADR-0101 (Slice 3; resolves open items at ADR lines 63-64)
-- Refs: doc7 Cl.4.1 ("eficácia = confirmed"); doc1 2.5.6 (registry slice only — the FULL retention
--       program is #572's scope); #618 (vault service_role_key ≠ EF-injected key, proven live 2026-06-10).
--
-- WHAT
--   1. CLAIM LEASE — `_ots_claim_unstamped_assets` becomes an UPDATE-based lease (new column
--      `pi_exclusion_assets.claimed_at`, 10-minute window, FOR UPDATE SKIP LOCKED on the picker).
--      RATIONALE: the ADR open item said "FOR UPDATE SKIP LOCKED", but a lock on a plain SELECT
--      releases at transaction commit — and over PostgREST each RPC call IS its own transaction,
--      so two EF invocations seconds apart would still double-claim. The lease survives across
--      transactions (covers the EF's 150s wall-clock with margin); SKIP LOCKED additionally
--      protects two exactly-simultaneous claims. Cron non-overlap (below) remains scheduled
--      discipline; the lease makes it defense-in-depth instead of a correctness requirement.
--   2. RETENTION — `_ots_retention_pass(p_retention)` eliminates assets (digest + .ots bytea) of
--      declarations REVOKED longer than the window (default 5 years = the platform's vínculo+5y
--      standard, same as the LGPD anonymize cron), then the asset-free revoked declarations.
--      SCOPE GUARD: 'error' assets of ACTIVE declarations are NOT touched — they are
--      declarant-entered Anexo I rows surfaced by export_anexo_i; auto-deleting them would be
--      silent data loss. The full doc1 2.5.6 program (institutional retention) belongs to #572.
--   3. HEALTH — `get_ots_pipeline_health()` in the get_lgpd_cron_health mould (ADR-0101 line 25):
--      per-status counts, retry exhaustion (stamp_attempts >= 5 falls out of the claim filter
--      SILENTLY — this tool is what makes that visible), oldest-work ages, cron snapshots, and a
--      green/yellow/red signal. Gate: can_by_member('view_internal_analytics'); aggregates only.
--   4. CRON — 3 jobs: ots-stamp-daily 02:10 UTC + ots-upgrade-daily 02:40 UTC (30-min spacing =
--      non-overlap discipline; EF batches finish in seconds-to-minutes) + ots-retention-monthly
--      (1st, 05:30 UTC). EF calls authenticate with the DEDICATED low-scope secret
--      `vault.ots_cron_secret` ⇄ EF env OTS_CRON_SECRET (#618: the vault service_role_key copy
--      does NOT match the EF-injected key — proven 403 live; the dedicated secret also survives
--      future service-key rotations). The EF gates accept service-role OR cron secret, FAIL-CLOSED.
--
-- PREREQS (done 2026-06-10, this session): EF env OTS_CRON_SECRET set (supabase secrets set) +
--   vault secret 'ots_cron_secret' created + both EFs redeployed with the widened gate + the exact
--   vault→net.http_post→EF path smoked 200 ({"success":true,"claimed":0,...}).
--
-- ROLLBACK
--   SELECT cron.unschedule('ots-stamp-daily');
--   SELECT cron.unschedule('ots-upgrade-daily');
--   SELECT cron.unschedule('ots-retention-monthly');
--   DROP FUNCTION public.get_ots_pipeline_health();
--   DROP FUNCTION public._ots_retention_pass(interval);
--   -- restore the SELECT-only claim body from 20260805000135 (lines 398-415), then:
--   ALTER TABLE public.pi_exclusion_assets DROP COLUMN claimed_at;
--
-- After apply: NOTIFY pgrst, 'reload schema'.

-- ============================================================================
-- 1. Claim lease — column + UPDATE-based claim with FOR UPDATE SKIP LOCKED
-- ============================================================================

ALTER TABLE public.pi_exclusion_assets
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

COMMENT ON COLUMN public.pi_exclusion_assets.claimed_at IS
  '#569 S3 claim lease: set by _ots_claim_unstamped_assets; rows with a lease younger than 10 minutes are skipped by subsequent claims (covers the stamp EF 150s wall-clock; expired leases are reclaimed). NULL = never claimed.';

-- Same signature/return as 20260805000135 → CREATE OR REPLACE preserves ACL (service_role-only).
CREATE OR REPLACE FUNCTION public._ots_claim_unstamped_assets(p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  -- UPDATE-based lease (NOT a bare SELECT ... FOR UPDATE: PostgREST RPC = one transaction,
  -- so a row lock alone releases before the EF processes anything). SKIP LOCKED guards the
  -- simultaneous-claim race; the 10-minute lease guards the overlapping-processing race.
  WITH picked AS (
    SELECT id FROM public.pi_exclusion_assets
    WHERE ots_status = 'unstamped'
      AND stamp_attempts < 5
      AND (claimed_at IS NULL OR claimed_at < now() - interval '10 minutes')
    ORDER BY created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.pi_exclusion_assets a
    SET claimed_at = now()
    FROM picked
    WHERE a.id = picked.id
    RETURNING a.id, a.sha256, a.created_at
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'sha256', sha256) ORDER BY created_at), '[]'::jsonb)
  INTO v_result
  FROM claimed;
  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 2. Retention pass — revoked-declaration assets + asset-free revoked declarations
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

  RETURN jsonb_build_object(
    'success', true,
    'retention_window', p_retention::text,
    'assets_deleted', v_assets_deleted,
    'declarations_deleted', v_decls_deleted,
    'ran_at', now()
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._ots_retention_pass(interval) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._ots_retention_pass(interval) TO service_role;

-- ============================================================================
-- 3. Pipeline health — get_lgpd_cron_health mould (aggregates only, no PII)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_ots_pipeline_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_caller_member_id uuid;
  v_decls jsonb;
  v_assets jsonb;
  v_exhausted integer;
  v_oldest_unstamped_h numeric;
  v_oldest_pending_h numeric;
  v_jobs jsonb;
  v_stale_days integer;
  v_failed_runs integer;
  v_backlog integer;
  v_health text;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Not authorized: requires view_internal_analytics');
  END IF;

  SELECT COALESCE(jsonb_object_agg(status, n), '{}'::jsonb) INTO v_decls
  FROM (SELECT status, count(*) AS n FROM public.pi_exclusion_declarations GROUP BY status) s;

  SELECT COALESCE(jsonb_object_agg(ots_status, n), '{}'::jsonb) INTO v_assets
  FROM (SELECT ots_status, count(*) AS n FROM public.pi_exclusion_assets GROUP BY ots_status) s;

  -- Retry exhaustion: still 'unstamped' but past the claim filter (stamp_attempts >= 5).
  -- These rows are INVISIBLE to the pipeline (claim skips them) — only this tool surfaces them.
  SELECT count(*) INTO v_exhausted
  FROM public.pi_exclusion_assets
  WHERE ots_status = 'unstamped' AND stamp_attempts >= 5;

  SELECT round(extract(epoch FROM (now() - min(created_at))) / 3600, 1) INTO v_oldest_unstamped_h
  FROM public.pi_exclusion_assets WHERE ots_status = 'unstamped';

  SELECT round(extract(epoch FROM (now() - min(updated_at))) / 3600, 1) INTO v_oldest_pending_h
  FROM public.pi_exclusion_assets WHERE ots_status = 'pending';

  SELECT jsonb_object_agg(jobname, snapshot) INTO v_jobs
  FROM (
    SELECT j.jobname,
      jsonb_build_object(
        'jobid', j.jobid,
        'schedule', j.schedule,
        'active', j.active,
        'last_run_at', (SELECT max(start_time) FROM cron.job_run_details d WHERE d.jobid = j.jobid),
        'last_status', (SELECT status FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY start_time DESC LIMIT 1),
        'days_since_last_run', (
          SELECT round((extract(epoch FROM (now() - max(start_time))) / 86400)::numeric, 2)
          FROM cron.job_run_details d WHERE d.jobid = j.jobid
        ),
        'failed_runs_last_90d', (
          SELECT count(*) FROM cron.job_run_details d
          WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time >= now() - interval '90 days'
        )
      ) AS snapshot
    FROM cron.job j
    WHERE j.jobname IN ('ots-stamp-daily', 'ots-upgrade-daily', 'ots-retention-monthly')
  ) sub;

  -- Staleness across the 2 DAILY jobs (NULL = never ran → 999; retention is monthly, judged
  -- only via failed_runs). #618 lesson baked in: cron 'succeeded' does NOT mean the EF call
  -- succeeded — net._http_response retention (~6h) is too short to join here, so a stale/failed
  -- DAILY job OR pipeline work not draining is the red signal, not the cron status alone.
  SELECT max(COALESCE(days, 999))::integer INTO v_stale_days
  FROM (
    SELECT extract(epoch FROM (now() - max(d.start_time))) / 86400 AS days
    FROM cron.job j
    LEFT JOIN cron.job_run_details d ON d.jobid = j.jobid
    WHERE j.jobname IN ('ots-stamp-daily', 'ots-upgrade-daily')
    GROUP BY j.jobid
  ) t;

  SELECT count(*) INTO v_failed_runs
  FROM cron.job_run_details d
  JOIN cron.job j ON j.jobid = d.jobid
  WHERE j.jobname IN ('ots-stamp-daily', 'ots-upgrade-daily', 'ots-retention-monthly')
    AND d.status = 'failed' AND d.start_time >= now() - interval '90 days';

  -- Work waiting on the pipeline (claim-eligible unstamped + pending upgrades).
  SELECT count(*) INTO v_backlog
  FROM public.pi_exclusion_assets
  WHERE (ots_status = 'unstamped' AND stamp_attempts < 5) OR ots_status = 'pending';

  -- red: silently-dropped work (exhausted) | cron-level failures | work waiting with stale daily jobs.
  -- yellow: newly scheduled with nothing to do yet | oldest pending un-anchored for > 7 days (168h).
  v_health := CASE
    WHEN v_exhausted > 0 THEN 'red'
    WHEN v_failed_runs > 0 THEN 'red'
    WHEN v_backlog > 0 AND v_stale_days > 2 THEN 'red'
    WHEN v_backlog = 0 AND v_stale_days = 999 THEN 'yellow'
    WHEN v_oldest_pending_h IS NOT NULL AND v_oldest_pending_h > 168 THEN 'yellow'
    ELSE 'green'
  END;

  RETURN jsonb_build_object(
    'declarations_by_status', v_decls,
    'assets_by_ots_status', v_assets,
    'exhausted_unstamped_attempts_ge_5', v_exhausted,
    'claim_eligible_backlog', v_backlog,
    'oldest_unstamped_age_hours', v_oldest_unstamped_h,
    'oldest_pending_age_hours', v_oldest_pending_h,
    'cron_jobs', COALESCE(v_jobs, '{}'::jsonb),
    'max_days_since_daily_job_ran', v_stale_days,
    'failed_cron_runs_last_90d', v_failed_runs,
    'health_signal', v_health,
    'notes', 'eficácia probatória plena (doc7 Cl.4.1) = confirmed; pending = aguardando âncora Bitcoin; exhausted = fora do claim (stamp_attempts >= 5) — requer intervenção. Cron succeeded != EF 200 (#618): cruzar com net._http_response (TTL ~6h) ao investigar.',
    'generated_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_ots_pipeline_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ots_pipeline_health() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ots_pipeline_health() TO service_role;

-- ============================================================================
-- 4. Cron jobs — stamp daily 02:10, upgrade daily 02:40 (non-overlap), retention monthly
-- ============================================================================

SELECT cron.unschedule('ots-stamp-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ots-stamp-daily');

SELECT cron.schedule(
  'ots-stamp-daily',
  '10 2 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/ots-stamp',
    body := '{"source": "pg_cron", "limit": 10}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'ots_cron_secret' LIMIT 1)
    )
  );
  $cron$
);

SELECT cron.unschedule('ots-upgrade-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ots-upgrade-daily');

SELECT cron.schedule(
  'ots-upgrade-daily',
  '40 2 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/ots-upgrade',
    body := '{"source": "pg_cron", "limit": 25}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'ots_cron_secret' LIMIT 1)
    )
  );
  $cron$
);

SELECT cron.unschedule('ots-retention-monthly')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ots-retention-monthly');

SELECT cron.schedule(
  'ots-retention-monthly',
  '30 5 1 * *',
  'SELECT public._ots_retention_pass();'
);

NOTIFY pgrst, 'reload schema';
