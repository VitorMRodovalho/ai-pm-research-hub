-- ADR-0039 defense-in-depth REVOKE FROM PUBLIC, anon (4 fns)
REVOKE EXECUTE ON FUNCTION public.counter_sign_certificate(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_pending_countersign() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_volunteer_agreement_status() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.register_attendance_batch(uuid, uuid[], uuid) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
