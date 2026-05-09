-- p126 E3 Migration 8/9 (reduced scope) — Issue C fix backfill
-- ADR-0076 Princípio 1 + Decision 8 implicit (active engagement = returning)
-- Wave 1 PM draft (E3 reduced scope p126; full E3 in next session)
--
-- Issue C (P1 from p125 pre-mortem): is_returning_member=false para João Coelho
-- (cycle 2 cohort active desde 2026-03-05) e outros candidatos active em Núcleo
-- que se candidatam novamente. Predicate atual só flag offboarded; este patch
-- estende para active engagement match.
--
-- DOES NOT patch import_vep_applications RPC body (deferred to E3 full scope p127+)
-- to keep this migration small. Risk: if /ingest re-runs antes do RPC patch,
-- novos imports retornam wrong flag para active returning candidates.
-- Mitigation: this backfill UPDATE catches existing rows; novo import irá precisar
-- run backfill manualmente OR await RPC patch.
--
-- Rollback: UPDATE selection_applications SET is_returning_member=false WHERE
--   id IN (SELECT id FROM ... originally false).

BEGIN;

-- ─── Backfill SQL: catch active-engagement returning candidates ─────────────
WITH backfill_targets AS (
  SELECT sa.id, sa.email, sa.applicant_name
  FROM public.selection_applications sa
  WHERE sa.is_returning_member = false
    AND EXISTS (
      SELECT 1
      FROM public.members m
      JOIN public.engagements e ON e.person_id = m.person_id
      WHERE lower(m.email) = lower(sa.email)
        AND e.status = 'active'
        AND e.kind LIKE 'volunteer%'
    )
)
UPDATE public.selection_applications sa
SET is_returning_member = true,
    updated_at = now()
FROM backfill_targets bt
WHERE sa.id = bt.id;

-- ─── Audit log entry for backfill (admin_audit_log) ─────────────────────────
DO $$
DECLARE
  v_count integer;
BEGIN
  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    NULL,
    'p126_e3_returning_member_backfill',
    'selection_applications',
    NULL,
    jsonb_build_object(
      'rows_updated', v_count,
      'predicate', 'active engagement match (kind LIKE volunteer%)',
      'source_migration', '20260518080000',
      'origin', 'p126 E3 reduced scope Issue C fix',
      'note', 'import_vep_applications RPC body NOT patched in this migration; full RPC patch in E3 next session'
    )
  );

  RAISE NOTICE '[p126 E3 backfill] is_returning_member updated true for % active-engagement returning candidates', v_count;
END $$;

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518080000
--   2. NO PostgREST reload (DML only)
--   3. Verify backfill: SELECT applicant_name, email, is_returning_member
--      FROM selection_applications WHERE applicant_name ILIKE '%João Coelho%';
--      Expected: is_returning_member = true for active members
--   4. RPC patch tracked as G-p126-1 (E3 full scope p127+)
