-- #886: allow authenticated members to read the comms editorial calendar embed URL.
-- Non-PII (a public Google Calendar embed URL). Mirrors the existing key-allowlist
-- pattern in site_config_read_authenticated. Without this the comms team gets 0 rows
-- -> PostgREST 406 on the .maybeSingle() read on /admin/comms.
--
-- SECURITY INVARIANT: this allowlist is the ONLY thing protecting sensitive site_config
-- rows from every authenticated user. NEVER add a secret/credential key here (e.g.
-- arm116_calendar_webhook_secret) — those must stay readable by superadmin/manage_member
-- only. Add a key ONLY when its value is non-sensitive and meant for broad member read.
DROP POLICY IF EXISTS site_config_read_authenticated ON public.site_config;
CREATE POLICY site_config_read_authenticated ON public.site_config
  FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR (key = ANY (ARRAY[
      'whatsapp_gp'::text,
      'general_meeting_link'::text,
      'group_term'::text,
      'attendance_risk_threshold'::text,
      'attendance_weight_geral'::text,
      'attendance_weight_tribo'::text,
      'comms_calendar_embed_url'::text
    ]))
  );
