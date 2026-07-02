-- #1026 Fatia C — frontend reader for the Drive-teardown panel (/admin/members/drive-teardown).
--
-- Per-member rollup over offboarded members: their drive_offboarding_audit queue counts + the latest
-- drive_teardown_scans attestation, bucketed into needs_action / attested_clean / not_scanned. This is the
-- ONE new RPC the panel needs; the per-grant drill-down reuses admin_list_drive_revocation_audit and the
-- (still manual, Fatia A) approve action reuses approve_drive_revocation / bulk_approve_drive_revocations.
--
-- Gate mirrors admin_list_drive_revocation_audit: auth.uid() -> member -> can_by_member('manage_member'),
-- REVOKE anon, GRANT authenticated+service_role, SECURITY DEFINER, + log_pii_access_batch (Art.37; returns
-- offboarded member NAMES). Returns counts only per member — no email/file detail (that is the drill-down).
CREATE OR REPLACE FUNCTION public.get_drive_teardown_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_members jsonb;
  v_member_ids uuid[];
  v_summary jsonb;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: manage_member required';
  END IF;

  WITH offboarded AS (
    SELECT m.id AS member_id, m.name, m.member_status, m.offboarded_at
    FROM public.members m
    WHERE m.member_status IN ('alumni','inactive') AND m.offboarded_at IS NOT NULL
  ),
  queue AS (
    SELECT member_id,
      count(*) FILTER (WHERE status = 'pending_revoke') AS pending_revoke,
      count(*) FILTER (WHERE status = 'approved')       AS approved,
      count(*) FILTER (WHERE status = 'revoked')        AS revoked,
      count(*) FILTER (WHERE status = 'already_absent') AS already_absent,
      count(*) FILTER (WHERE status = 'failed')         AS failed,
      count(*) FILTER (WHERE status = 'skipped')        AS skipped
    FROM public.drive_offboarding_audit
    GROUP BY member_id
  ),
  latest_scan AS (
    SELECT DISTINCT ON (member_id) member_id, scanned_at, grants_found, scan_source
    FROM public.drive_teardown_scans
    WHERE member_id IS NOT NULL
    ORDER BY member_id, scanned_at DESC
  ),
  rows AS (
    SELECT
      o.member_id, o.name, o.member_status, o.offboarded_at,
      ls.scanned_at AS latest_scan_at, ls.grants_found AS latest_grants_found, ls.scan_source AS latest_scan_source,
      coalesce(q.pending_revoke, 0) AS pending_revoke,
      coalesce(q.approved, 0)       AS approved,
      coalesce(q.revoked, 0)        AS revoked,
      coalesce(q.already_absent, 0) AS already_absent,
      coalesce(q.failed, 0)         AS failed,
      coalesce(q.skipped, 0)        AS skipped,
      (coalesce(q.pending_revoke,0) + coalesce(q.approved,0) + coalesce(q.failed,0)) AS open_count,
      (ls.member_id IS NOT NULL) AS scanned,
      (ls.member_id IS NOT NULL AND (coalesce(q.pending_revoke,0) + coalesce(q.approved,0) + coalesce(q.failed,0)) = 0) AS verified_clean
    FROM offboarded o
    LEFT JOIN queue q ON q.member_id = o.member_id
    LEFT JOIN latest_scan ls ON ls.member_id = o.member_id
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'member_id', member_id, 'name', name, 'member_status', member_status, 'offboarded_at', offboarded_at,
      'latest_scan_at', latest_scan_at, 'latest_grants_found', latest_grants_found, 'latest_scan_source', latest_scan_source,
      'pending_revoke', pending_revoke, 'approved', approved, 'revoked', revoked,
      'already_absent', already_absent, 'failed', failed, 'skipped', skipped,
      'open_count', open_count, 'scanned', scanned, 'verified_clean', verified_clean,
      'verified_clean_at', CASE WHEN verified_clean THEN latest_scan_at ELSE NULL END,
      'bucket', CASE WHEN open_count > 0 THEN 'needs_action'
                     WHEN verified_clean THEN 'attested_clean'
                     ELSE 'not_scanned' END
    ) ORDER BY (open_count > 0) DESC, offboarded_at DESC), '[]'::jsonb),
    coalesce(array_agg(DISTINCT member_id), ARRAY[]::uuid[])
  INTO v_members, v_member_ids
  FROM rows;

  SELECT jsonb_build_object(
    'total_offboarded', jsonb_array_length(v_members),
    'attested_clean', (SELECT count(*) FROM jsonb_array_elements(v_members) e WHERE (e->>'bucket') = 'attested_clean'),
    'needs_action',   (SELECT count(*) FROM jsonb_array_elements(v_members) e WHERE (e->>'bucket') = 'needs_action'),
    'not_scanned',    (SELECT count(*) FROM jsonb_array_elements(v_members) e WHERE (e->>'bucket') = 'not_scanned'),
    'open_pending',   (SELECT coalesce(sum((e->>'pending_revoke')::int), 0) FROM jsonb_array_elements(v_members) e),
    'open_approved',  (SELECT coalesce(sum((e->>'approved')::int), 0) FROM jsonb_array_elements(v_members) e),
    'open_failed',    (SELECT coalesce(sum((e->>'failed')::int), 0) FROM jsonb_array_elements(v_members) e)
  ) INTO v_summary;

  -- LGPD Art.37: GP read of offboarded member names for the teardown panel.
  IF cardinality(v_member_ids) > 0 THEN
    PERFORM public.log_pii_access_batch(v_member_ids, ARRAY['name'],
      'get_drive_teardown_overview', 'GP review of Drive teardown status per offboarded member');
  END IF;

  RETURN jsonb_build_object('summary', v_summary, 'members', v_members);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_drive_teardown_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_drive_teardown_overview() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
