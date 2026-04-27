-- ADR-0038 p68 cleanup batch — defense-in-depth REVOKE FROM PUBLIC, anon
-- Matches ADR-0030..0037 pattern. Closes 3 SECDEF advisor entries.

REVOKE EXECUTE ON FUNCTION public.update_governance_document_status(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_event_duration(uuid, integer, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_dropout_risk_members(integer) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
