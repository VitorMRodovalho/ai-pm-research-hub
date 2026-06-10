-- Migration: 20260805000141_p618_retire_backup_to_r2_cron
-- Issue: #618 — backup architecture consolidation (PM decision 2026-06-10: Option C)
--
-- WHAT
--   Unschedules pg_cron job 12 (`backup-to-r2-weekly`). The EF it invoked (`backup-to-r2`)
--   is RETIRED in the same PR:
--   * it had been failing 500 weekly ("R2 credentials not configured") with pg_cron
--     reporting 'succeeded' (net.http_post is async — #618);
--   * its auth gate was broken-open (any non-empty bearer passed when BACKUP_SECRET unset);
--   * its dump was NOT restore-grade: a hardcoded 28-table JSON allowlist, stale vs the
--     live schema (missing the entire V4 domain — engagements/persons/initiatives,
--     selection_*, pi_exclusion_*, consent_records, ...). Fixing it would mean
--     re-implementing pg_dump badly, forever chasing schema drift.
--
--   Replacement (same PR): the GREEN GitHub Actions weekly backup (real pg_dump 17 via the
--   session pooler) gains an OFFSITE upload step to Cloudflare R2 (S3 API). Final
--   architecture: Supabase platform daily backups (7d) + weekly pg_dump → GitHub artifact
--   (8 copies, 60d) + the SAME dump → R2 (offsite, outside the GitHub provider basket).
--
-- ROLLBACK
--   Re-create the cron from the original definition (see git history of this file's
--   predecessor migration that scheduled it) — NOT recommended; the EF is gone.

SELECT cron.unschedule('backup-to-r2-weekly')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'backup-to-r2-weekly');
