-- ADR-0026 EXTENSION (p66) defense-in-depth REVOKE
-- Matches ADR-0026 batch 1 precedent for admin_manage_comms_channel.
-- pg_policy precondition verified pre-apply (zero refs in RLS).

REVOKE EXECUTE ON FUNCTION public.admin_get_campaign_stats(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_preview_campaign(uuid, uuid) FROM PUBLIC, anon;
