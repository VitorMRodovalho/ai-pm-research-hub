-- Performance P3 Wave 2 / ADR-0058 mpp Class E batch 7
-- Merge multiple permissive SELECT policies on authenticated role into single
-- per-table policies. Auth surface preserved exactly (verified per-policy
-- predicate union). Closes 5 multiple_permissive_policies advisor WARNs.

-- 1. events SELECT (authenticated): merge events_read_ghost + events_read_members
DROP POLICY IF EXISTS events_read_ghost ON public.events;
DROP POLICY IF EXISTS events_read_members ON public.events;
CREATE POLICY events_read_authenticated ON public.events
  FOR SELECT TO authenticated
  USING (
    rls_is_member()
    OR type = ANY (ARRAY['geral'::text, 'webinar'::text])
  );

-- 2. webinars SELECT (authenticated): merge webinars_read_ghost + webinars_read_members
DROP POLICY IF EXISTS webinars_read_ghost ON public.webinars;
DROP POLICY IF EXISTS webinars_read_members ON public.webinars;
CREATE POLICY webinars_read_authenticated ON public.webinars
  FOR SELECT TO authenticated
  USING (
    rls_is_member()
    OR status = ANY (ARRAY['confirmed'::text, 'completed'::text])
  );

-- 3. broadcast_log SELECT (authenticated): merge admin + initiative + sender
DROP POLICY IF EXISTS broadcast_log_read_admin ON public.broadcast_log;
DROP POLICY IF EXISTS broadcast_log_read_initiative ON public.broadcast_log;
DROP POLICY IF EXISTS broadcast_log_read_sender ON public.broadcast_log;
CREATE POLICY broadcast_log_read_authenticated ON public.broadcast_log
  FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR rls_can_for_initiative('write'::text, initiative_id)
    OR sender_id = (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid() AS uid) LIMIT 1)
  );

-- 4. initiative_invitations SELECT (authenticated): merge admin + inviter + self
DROP POLICY IF EXISTS initiative_invitations_read_admin ON public.initiative_invitations;
DROP POLICY IF EXISTS initiative_invitations_read_inviter ON public.initiative_invitations;
DROP POLICY IF EXISTS initiative_invitations_read_self ON public.initiative_invitations;
CREATE POLICY initiative_invitations_read_authenticated ON public.initiative_invitations
  FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR inviter_member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid() AS uid))
    OR invitee_member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid() AS uid))
  );

-- 5. hub_resources SELECT (authenticated): merge select + select_manage
DROP POLICY IF EXISTS hub_resources_select ON public.hub_resources;
DROP POLICY IF EXISTS hub_resources_select_manage ON public.hub_resources;
CREATE POLICY hub_resources_select_authenticated ON public.hub_resources
  FOR SELECT TO authenticated
  USING (
    is_active = true
    OR can_manage_knowledge()
  );

-- 6. site_config SELECT (authenticated): merge admin_read + public_read
DROP POLICY IF EXISTS site_config_admin_read ON public.site_config;
DROP POLICY IF EXISTS site_config_public_read ON public.site_config;
CREATE POLICY site_config_read_authenticated ON public.site_config
  FOR SELECT TO authenticated
  USING (
    rls_is_superadmin()
    OR rls_can('manage_member'::text)
    OR key = ANY (ARRAY[
      'whatsapp_gp'::text,
      'general_meeting_link'::text,
      'group_term'::text,
      'attendance_risk_threshold'::text,
      'attendance_weight_geral'::text,
      'attendance_weight_tribo'::text
    ])
  );
