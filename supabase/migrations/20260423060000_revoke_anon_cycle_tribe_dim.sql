-- ═══════════════════════════════════════════════════════════════
-- Revoke anon access to cycle_tribe_dim materialized view
-- Why: leader_name + leader_photo are borderline PII and the only
-- consumers (/teams, /tribe/[id]) require authentication. Closes
-- the materialized_view_in_api WARN from Supabase advisor.
-- Rollback: GRANT SELECT ON public.cycle_tribe_dim TO anon;
-- ═══════════════════════════════════════════════════════════════

REVOKE SELECT ON public.cycle_tribe_dim FROM anon;
