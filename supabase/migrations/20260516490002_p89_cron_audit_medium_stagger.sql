-- p89 cron audit MEDIUM — stagger timing collisions (low risk hygiene)
--
-- Findings from /audit cron 23 jobs:
--   (a) 3am UTC daily collision: drive-discover-atas-daily + v4_engagement_expiration ambos at 3:00
--   (b) Hourly :00 collision: expire-stale-invitations-hourly + retry-pending-ai-analyses ambos at minute 0
--
-- Fix: stagger one job in each cluster by minutes-of-hour.
--   - v4_engagement_expiration: 3:00 → 3:05 (5 min after drive-discover-atas)
--   - retry-pending-ai-analyses: :00 → :07 (7 min after expire-stale-invitations)
--
-- Anonymize unification investigation: BOTH KEPT.
--   anonymize_inactive_members (legacy): member-level, list_anonymization_candidates(p_years), members table direto
--   anonymize_by_engagement_kind (V4): person-level via engagement_kinds.anonymization_policy + retention_days_after_end
--   Diferentes abstrações; V4 não subsume legacy ainda. Future: migrate quando engagement_kinds cobrir todos casos.
--
-- Sunday 4-5am Cloudflare↔Supabase collision: indep infrastructure, accepted.

-- ============================================================================
-- Stagger v4_engagement_expiration (avoid 3:00 collision com drive-discover-atas-daily)
-- ============================================================================
SELECT cron.alter_job(
  job_id := (SELECT jobid FROM cron.job WHERE jobname = 'v4_engagement_expiration'),
  schedule := '5 3 * * *'
);

-- ============================================================================
-- Stagger retry-pending-ai-analyses (avoid hourly :00 spike com expire-stale-invitations-hourly)
-- ============================================================================
SELECT cron.alter_job(
  job_id := (SELECT jobid FROM cron.job WHERE jobname = 'retry-pending-ai-analyses'),
  schedule := '7 * * * *'
);

-- ============================================================================
-- Audit log entry
-- ============================================================================
INSERT INTO public.admin_audit_log (
  actor_id, action, target_type, changes, metadata
)
SELECT
  m.id,
  'cron.audit_p89_medium_stagger',
  'cron_job',
  jsonb_build_object(
    'staggered', jsonb_build_array(
      jsonb_build_object(
        'job', 'v4_engagement_expiration',
        'old_schedule', '0 3 * * *',
        'new_schedule', '5 3 * * *',
        'reason', 'avoid 3:00 collision com drive-discover-atas-daily'
      ),
      jsonb_build_object(
        'job', 'retry-pending-ai-analyses',
        'old_schedule', '0 * * * *',
        'new_schedule', '7 * * * *',
        'reason', 'avoid hourly :00 spike com expire-stale-invitations-hourly'
      )
    ),
    'unification_investigation', jsonb_build_object(
      'lgpd_anonymize_inactive_monthly', 'KEPT (legacy LGPD member-level pattern)',
      'v4_anonymize_by_kind_monthly', 'KEPT (V4 person-level via engagement_kinds.anonymization_policy)',
      'rationale', 'Different abstractions: legacy targets members table direto via list_anonymization_candidates(p_years), V4 targets persons joined com engagement_kinds.anonymization_policy+retention_days_after_end. V4 não subsume legacy ainda; manter ambos até engagement_kinds cobrir todos casos.'
    ),
    'cf_collision_accepted', jsonb_build_object(
      'crons', '[backup-to-r2-weekly Sunday 4:00 UTC, pmi-vep-sync Cloudflare daily 4:00 UTC]',
      'rationale', 'Independent infrastructure (Supabase pg_cron vs Cloudflare Worker) — no shared resources'
    ),
    'deferred_low_priority', jsonb_build_array(
      'sync-credly-all (3:00 every 5d) + sync-attendance-points (3:15 every 5d) — low frequency, partial stagger acceptable',
      'Sunday 4:00 + 5:00 + 5:30 cluster — auto-archive + sync-artia + backup all sequential, no overlap risk'
    )
  ),
  jsonb_build_object(
    'session', 'p89',
    'audit_skill', '/audit cron MEDIUM cleanup',
    'reference', 'sediment from p89 cron audit (commit ef314fd) follow-up'
  )
FROM public.members m
WHERE m.is_superadmin = true AND m.auth_id IS NOT NULL
ORDER BY m.created_at LIMIT 1;
