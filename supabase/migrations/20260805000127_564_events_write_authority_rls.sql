-- #564 Security: tighten events write authority (RLS) + companion timezone coerce on the edit RPCs
--
-- BEFORE: public.events had ONE write-capable policy `events_v4_org_scope`:
--   cmd=ALL, roles={public}, USING/CHECK = (organization_id = auth_org() OR organization_id IS NULL)
--   => any authenticated org member could INSERT / UPDATE / DELETE event rows directly via PostgREST
--      (sb.from('events').update(...)), bypassing the can_by_member('manage_event') authority gate
--      enforced by create_event / update_event. The frontend gates editing (canEdit) and the RPCs gate
--      in-body, but the table-level RLS did not -- a crafted API call from any member's JWT could mutate
--      or delete events. (events.organization_id is NOT NULL, so the `IS NULL` arm is already dead for
--      real rows; it is preserved verbatim only to keep read parity on SELECT.)
--
-- AFTER: split the blanket ALL policy into per-command policies.
--   * SELECT keeps the IDENTICAL org-scope read predicate, TO public => zero read regression (it is
--     OR'd, as a permissive policy, with the pre-existing events_read_anon / events_read_authenticated).
--   * INSERT / UPDATE / DELETE are scoped TO authenticated (anon has no write policy => denied by
--     default; service_role + the SECURITY DEFINER RPCs bypass RLS as before).
--   * UPDATE / DELETE are gated on rls_can_write_event(initiative_id, created_by), a SECURITY DEFINER
--     predicate that returns the SAME boolean as the update_event RPC authority gate:
--        member AND ( event-author OR (manage_event AND NOT tribe_leader-reaching-across-tribes) ).
--
--   Correctness invariant: if the update_event RPC would succeed for a given caller+event, the matching
--   direct .update() also passes RLS -- so NO legitimate editor/creator path regresses, while the
--   "any org member" write bypass is closed.
--
-- Out of RLS scope (intentionally unaffected, all bypass RLS): the SECURITY DEFINER event RPCs
--   (create_event, update_event, update_future_events_in_group) run as owner postgres; service_role
--   writers (import-calendar-legacy EF, scripts/calendar_event_importer.ts) use the service key. Only
--   direct user-JWT PostgREST writes are now authority-gated.
--
-- Companion (#564): update_event + update_future_events_in_group gain p_timezone with the same
--   pg_timezone_names coerce as create_event (NULL/'' = keep existing; unknown IANA name ->
--   'America/Sao_Paulo'), so the edit path no longer relies solely on the events_timezone_check column
--   CHECK + the client isValidTimeZone guard, and future-sibling timezone propagation runs through the
--   SECDEF RPC (bypasses RLS -> no silent partial-update) instead of a direct multi-row .update().
--
-- Hardening (security wave): the DROP+CREATE'd event write RPCs (update_event,
--   update_future_events_in_group) and the new helper are REVOKE'd from anon (ADR-0038/0041 pattern);
--   they previously inherited PUBLIC execute. Bodies remain fail-closed for NULL auth.uid().
--
-- Rollback:
--   DROP POLICY events_select_org_scope, events_insert_authority, events_update_authority,
--     events_delete_authority ON public.events;
--   DROP FUNCTION public.rls_can_write_event(uuid, uuid);
--   CREATE POLICY events_v4_org_scope ON public.events FOR ALL TO public
--     USING ((organization_id = auth_org()) OR (organization_id IS NULL))
--     WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));
--   -- restore update_event / update_future_events_in_group without p_timezone (DROP + recreate prior
--   -- signatures) and re-GRANT EXECUTE ... TO anon if the prior anon-callable posture is desired.

-- ───────────────────────────────────────────────────────────────────────────────────────────────
-- 1) Authority predicate for DIRECT event writes -- mirrors the update_event RPC gate exactly.
--    Caller must have a members row (parity with update_event's `IF v_caller IS NULL THEN Unauthorized`,
--    which also closes the ghost-creator edge). operational_role compared with IS NOT DISTINCT FROM so a
--    NULL role is treated as "not a tribe leader" (matches plpgsql `IF role = 'tribe_leader'`).
--    resolve_tribe_id is resolved once via the CTE.
-- ───────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rls_can_write_event(p_initiative_id uuid, p_created_by uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH t AS (SELECT public.resolve_tribe_id(p_initiative_id) AS tribe_id)
  SELECT EXISTS (
    SELECT 1
    FROM public.members m, t
    WHERE m.auth_id = auth.uid()
      AND (
        -- event-author carve-out (events.created_by FK -> auth.users(id) = auth.uid())
        (p_created_by IS NOT NULL AND p_created_by = auth.uid())
        OR (
          public.can_by_member(m.id, 'manage_event')
          -- residual tribe scope: a tribe_leader may not reach across tribes (parity with update_event)
          AND NOT (
            m.operational_role IS NOT DISTINCT FROM 'tribe_leader'
            AND t.tribe_id IS NOT NULL
            AND t.tribe_id IS DISTINCT FROM m.tribe_id
          )
        )
      )
  );
$function$;

COMMENT ON FUNCTION public.rls_can_write_event(uuid, uuid) IS
  '#564 RLS write-authority predicate for public.events direct (PostgREST) UPDATE/DELETE. Returns the same boolean as the update_event RPC gate: member AND (event-author OR (manage_event AND NOT tribe_leader-cross-tribe)). SECURITY DEFINER, returns boolean only (no PII).';

-- Supabase default privileges auto-GRANT EXECUTE to anon on new public functions, so REVOKE from
-- both PUBLIC and anon explicitly (parity with the sibling RLS helpers / ADR-0038/0041 pattern).
REVOKE EXECUTE ON FUNCTION public.rls_can_write_event(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rls_can_write_event(uuid, uuid) TO authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────────────────────────
-- 2) Replace the blanket cmd=ALL policy with per-command policies.
-- ───────────────────────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS events_v4_org_scope ON public.events;

-- SELECT: identical org-scope read predicate (zero read regression).
CREATE POLICY events_select_org_scope ON public.events
  FOR SELECT TO public
  USING ((organization_id = auth_org()) OR (organization_id IS NULL));

-- INSERT: authenticated + org + manage_event. Defensive-only -- the app creates events via the
-- create_event RPC (SECURITY DEFINER, bypasses RLS). Coarse rls_can('manage_event') (not
-- rls_can_write_event) is sufficient here: the tribe-scope refinement is enforced inside create_event.
CREATE POLICY events_insert_authority ON public.events
  FOR INSERT TO authenticated
  WITH CHECK (
    ((organization_id = auth_org()) OR (organization_id IS NULL))
    AND public.rls_can('manage_event')
  );

-- UPDATE: authenticated + org + write authority on BOTH the existing row (USING) and the result (CHECK).
CREATE POLICY events_update_authority ON public.events
  FOR UPDATE TO authenticated
  USING (
    ((organization_id = auth_org()) OR (organization_id IS NULL))
    AND public.rls_can_write_event(initiative_id, created_by)
  )
  WITH CHECK (
    ((organization_id = auth_org()) OR (organization_id IS NULL))
    AND public.rls_can_write_event(initiative_id, created_by)
  );

-- DELETE: authenticated + org + write authority.
CREATE POLICY events_delete_authority ON public.events
  FOR DELETE TO authenticated
  USING (
    ((organization_id = auth_org()) OR (organization_id IS NULL))
    AND public.rls_can_write_event(initiative_id, created_by)
  );

-- ───────────────────────────────────────────────────────────────────────────────────────────────
-- 3) Companion: update_event gains p_timezone (DROP + CREATE -- param count changes, GC-097).
--    Byte-faithful to the prior body except: deterministic caller select (ORDER BY created_at DESC
--    LIMIT 1, multi-membership safety), the new p_timezone param, v_safe_tz coerce, and the timezone
--    column in the UPDATE SET.
-- ───────────────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.update_event(uuid, text, date, time without time zone, integer, text, text, boolean, text, text, text, text, text, text[]);

CREATE OR REPLACE FUNCTION public.update_event(
  p_event_id uuid,
  p_title text DEFAULT NULL::text,
  p_date date DEFAULT NULL::date,
  p_time_start time without time zone DEFAULT NULL::time without time zone,
  p_duration_minutes integer DEFAULT NULL::integer,
  p_meeting_link text DEFAULT NULL::text,
  p_youtube_url text DEFAULT NULL::text,
  p_is_recorded boolean DEFAULT NULL::boolean,
  p_recording_url text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_type text DEFAULT NULL::text,
  p_nature text DEFAULT NULL::text,
  p_audience_level text DEFAULT NULL::text,
  p_external_attendees text[] DEFAULT NULL::text[],
  p_timezone text DEFAULT NULL::text
)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_event record;
  v_event_tribe_id int;
  v_safe_type text;
  v_safe_nature text;
  v_safe_audience text;
  v_safe_tz text;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid() ORDER BY created_at DESC LIMIT 1;
  IF v_caller IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Event not found');
  END IF;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);

  -- Permission check (V4 baseline + residual tribe scope; preserves event-author
  -- carve-out so card creators can edit their own events).
  IF NOT public.can_by_member(v_caller.id, 'manage_event')
     AND v_event.created_by IS DISTINCT FROM auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_event_tribe_id IS NOT NULL
     AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id
     AND v_event.created_by IS DISTINCT FROM auth.uid() THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient permissions');
  END IF;

  v_safe_type := CASE
    WHEN p_type IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN p_type
    ELSE NULL END;
  v_safe_nature := CASE
    WHEN p_nature IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN p_nature
    ELSE NULL END;
  v_safe_audience := CASE
    WHEN p_audience_level IN ('all','leadership','tribe','curators') THEN p_audience_level
    ELSE NULL END;
  -- #564: coerce timezone (NULL/'' = keep existing; unknown IANA name -> BRT default; parity with create_event).
  v_safe_tz := CASE
    WHEN p_timezone IS NULL OR p_timezone = '' THEN NULL
    WHEN EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN p_timezone
    ELSE 'America/Sao_Paulo' END;

  UPDATE public.events SET
    title              = COALESCE(p_title, title),
    date               = COALESCE(p_date, date),
    time_start         = COALESCE(p_time_start, time_start),
    duration_minutes   = COALESCE(p_duration_minutes, duration_minutes),
    meeting_link       = COALESCE(p_meeting_link, meeting_link),
    youtube_url        = COALESCE(p_youtube_url, youtube_url),
    is_recorded        = COALESCE(p_is_recorded, is_recorded),
    recording_url      = COALESCE(p_recording_url, recording_url),
    notes              = COALESCE(p_notes, notes),
    type               = COALESCE(v_safe_type, type),
    nature             = COALESCE(v_safe_nature, nature),
    audience_level     = COALESCE(v_safe_audience, audience_level),
    external_attendees = COALESCE(p_external_attendees, external_attendees),
    timezone           = COALESCE(v_safe_tz, timezone),
    updated_at         = now()
  WHERE id = p_event_id;

  RETURN json_build_object('success', true);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_event(uuid, text, date, time without time zone, integer, text, text, boolean, text, text, text, text, text, text[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_event(uuid, text, date, time without time zone, integer, text, text, boolean, text, text, text, text, text, text[], text) TO authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────────────────────────
-- 4) Companion: update_future_events_in_group gains p_timezone (DROP + CREATE -- param count changes).
--    Routes future-sibling timezone propagation through this SECDEF RPC (bypasses RLS) instead of the
--    former direct multi-row .update() in attendance.astro, which would have silently dropped sibling
--    rows whose initiative_id drifted to another tribe for a tribe_leader caller. Body faithful to the
--    prior version except: the new p_timezone param + v_safe_tz coerce + the timezone column in the SET,
--    and hardening parity with update_event (search_path pg_temp + ORDER BY created_at DESC LIMIT 1 on
--    the caller select, for multi-membership safety).
-- ───────────────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.update_future_events_in_group(uuid, time without time zone, integer, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.update_future_events_in_group(
  p_event_id uuid,
  p_new_time_start time without time zone DEFAULT NULL::time without time zone,
  p_duration_minutes integer DEFAULT NULL::integer,
  p_meeting_link text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_visibility text DEFAULT NULL::text,
  p_type text DEFAULT NULL::text,
  p_nature text DEFAULT NULL::text,
  p_timezone text DEFAULT NULL::text
)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_tribe int;
  v_event_tribe int;
  v_event_date date;
  v_rec_group uuid;
  v_updated_count int;
  v_safe_tz text;
BEGIN
  SELECT id, operational_role, tribe_id INTO v_caller_id, v_caller_role, v_caller_tribe
  FROM public.members WHERE auth_id = auth.uid() ORDER BY created_at DESC LIMIT 1;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT i.legacy_tribe_id, e.date, e.recurrence_group
    INTO v_event_tribe, v_event_date, v_rec_group
  FROM public.events e
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_event_id;
  IF v_event_date IS NULL THEN RAISE EXCEPTION 'Event not found'; END IF;
  IF v_rec_group IS NULL THEN RAISE EXCEPTION 'Event is not part of a recurring series'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;
  IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
    RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
  END IF;

  IF p_type IS NOT NULL AND p_type NOT IN ('geral','tribo','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar') THEN
    RAISE EXCEPTION 'Invalid event type: %', p_type;
  END IF;
  IF p_nature IS NOT NULL AND p_nature NOT IN ('kickoff','recorrente','avulsa','encerramento','workshop','entrevista_selecao') THEN
    RAISE EXCEPTION 'Invalid event nature: %', p_nature;
  END IF;

  -- #564: coerce timezone (NULL/'' = keep existing; unknown IANA name -> BRT default; parity with create_event).
  v_safe_tz := CASE
    WHEN p_timezone IS NULL OR p_timezone = '' THEN NULL
    WHEN EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN p_timezone
    ELSE 'America/Sao_Paulo' END;

  WITH updated AS (
    UPDATE public.events SET
      time_start = COALESCE(p_new_time_start, time_start),
      duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
      meeting_link = COALESCE(p_meeting_link, meeting_link),
      notes = COALESCE(p_notes, notes),
      visibility = COALESCE(p_visibility, visibility),
      type = COALESCE(p_type, type),
      nature = COALESCE(p_nature, nature),
      timezone = COALESCE(v_safe_tz, timezone),
      updated_at = now()
    WHERE recurrence_group = v_rec_group AND date >= v_event_date
    RETURNING id
  )
  SELECT count(*) INTO v_updated_count FROM updated;

  RETURN json_build_object('success', true, 'recurrence_group', v_rec_group, 'anchor_date', v_event_date, 'updated_count', v_updated_count);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.update_future_events_in_group(uuid, time without time zone, integer, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_future_events_in_group(uuid, time without time zone, integer, text, text, text, text, text, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
