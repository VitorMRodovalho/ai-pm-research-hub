-- #1063 — SECDEF reader guard: close the events/initiatives blind spot (#785/#932 F-05).
--
-- Problem: _audit_secdef_initiative_reader_gates() detected reads over initiative-linked
-- tables via a regex that only covered BOARD tables. A SECURITY DEFINER reader that
-- aggregates `events` or `initiatives` WITHOUT touching a board table escaped detection —
-- it fell into neither the flagged list nor the ALLOWLIST, blinding the #785/#932
-- recurrence guard (the concrete #932 instance was _artia_safe_event_summary, guarded only
-- by a static assertion). This migration:
--   1. Extends the detection regex to also match `events` / `initiatives` (word boundaries).
--   2. Closes the confidential leaks surfaced by the newly-widened guard:
--      - 2 REVOKEs (internal `_`-prefixed helpers that were needlessly RPC-exposed to
--        anon/authenticated and leaked confidential rows);
--      - 2 real gates on the public readers get_tribe_event_roster / get_meeting_notes_compliance.
-- The 53 structurally-safe newly-flagged readers are justified in the guard's ALLOWLIST
-- (tests/contracts/785-secdef-reader-confidential-gate.test.mjs).
--
-- Grounding (live, 2026-07-11, project ldrfrvwhxsmgaabwmaik): 1 confidential initiative
-- (GP × Presidência, legacy_tribe_id=NULL) with 10 events. Extended regex flags 57 new
-- SECDEF authenticated readers; triage = 2 active leaks + 2 latent + 53 safe.

-- ---------------------------------------------------------------------------
-- 1. Extend the audit RPC regex to cover events / initiatives (word boundaries).
--    Based on the LIVE body (pg_get_functiondef); only the reads_initiative_table
--    predicate changes. \m..\M are POSIX word boundaries so `events` does not match
--    inside board_lifecycle_events / event_* and `initiatives` matches the table word.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._audit_secdef_initiative_reader_gates()
 RETURNS TABLE(proname text, identity_args text, reads_initiative_table boolean, is_writer boolean, exec_authenticated boolean, references_gate boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT
    p.proname::text,
    pg_catalog.pg_get_function_identity_arguments(p.oid)::text,
    (p.prosrc ~ '(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)'
      OR p.prosrc ~ '\mevents\M' OR p.prosrc ~ '\minitiatives\M'),
    (upper(p.prosrc) ~ '(INSERT |UPDATE |DELETE )'),
    pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'),
    (p.prosrc ~ 'rls_can_see_(initiative|board|item)|confidential')
  FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.prokind = 'f'
    AND p.prosecdef
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    )
  ORDER BY p.proname, p.oid;
$function$;

-- ---------------------------------------------------------------------------
-- 2. REVOKE — internal helpers that were needlessly executable by anon/authenticated.
--    Both are `_`-prefixed, called ONLY by internal SECURITY DEFINER functions (which
--    run as owner, unaffected by this REVOKE): _v4_active_initiatives_with_leaders by
--    generate_weekly_leader_digest_cron; _recurrence_stockout_rows by
--    detect_operational_alerts / detect_recurrence_stockout_cron / get_recurrence_stockout.
--    Direct RPC exposure leaked the confidential initiative (title/id/kind and 1on1
--    schedule) to any anon/authenticated caller. Removing them from the RPC surface both
--    closes the leak and drops them from the guard's flagged set (exec_authenticated=false).
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public._v4_active_initiatives_with_leaders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._recurrence_stockout_rows(integer) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. get_tribe_event_roster — add the confidential visibility gate (ADR-0105).
--    Based on the LIVE body; only the new IF gate is added. manage_event is NOT the
--    confidentiality boundary: a non-engaged manage_event holder passing a confidential
--    event id hit the `initiative_id IS NOT NULL AND v_event_tribe_id IS NULL` branch and
--    received the confidential initiative's engaged-member roster + attendance (the 1on1
--    events resolve to a NULL tribe, so the tribe_leader scope check does not fire).
--    rls_can_see_initiative returns true for NULL/standard initiatives, so non-confidential
--    events are byte-unaffected.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_tribe_event_roster(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller RECORD;
  v_event  RECORD;
  v_event_tribe_id int;
  v_result JSON;
  v_has_attendance boolean;
  v_event_cancelled boolean;
BEGIN
  SELECT m.* INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;

  v_event_tribe_id := public.resolve_tribe_id(v_event.initiative_id);
  v_event_cancelled := (v_event.status = 'cancelled');

  -- Access control: V4 baseline manage_event + residual tribe scope for tribe_leader
  IF NOT public.can_by_member(v_caller.id, 'manage_event') THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;
  IF v_caller.operational_role = 'tribe_leader'
     AND v_event_tribe_id IS NOT NULL
     AND v_event_tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;

  -- #1063: confidential initiative visibility gate (ADR-0105). manage_event is not the
  -- confidentiality boundary; block reads of a confidential initiative's event roster for
  -- callers who are not engaged in it (and not GP/manage_platform).
  IF v_event.initiative_id IS NOT NULL
     AND NOT public.rls_can_see_initiative(v_event.initiative_id) THEN
    RETURN json_build_object('error', 'Access denied');
  END IF;

  SELECT EXISTS(SELECT 1 FROM attendance WHERE event_id = p_event_id) INTO v_has_attendance;

  SELECT json_agg(row_to_json(q) ORDER BY q.name) INTO v_result
  FROM (
    SELECT
      m.id, m.name, m.photo_url, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations) AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter,
      COALESCE(a.present, false) AS present,
      a.corrected_by IS NOT NULL AS was_corrected,
      v_event_cancelled AS event_cancelled
    FROM public.members m
    LEFT JOIN public.attendance a
      ON a.event_id = p_event_id AND a.member_id = m.id
    WHERE
      m.operational_role != 'guest'
      AND (
        CASE WHEN v_event.initiative_id IS NOT NULL AND v_event_tribe_id IS NULL THEN
          m.id IN (
            SELECT mm.id FROM members mm
            JOIN engagements eng ON eng.person_id = mm.person_id
            WHERE eng.initiative_id = v_event.initiative_id AND eng.status = 'active'
          )
          OR a.id IS NOT NULL

        WHEN v_event.type IN ('1on1', 'entrevista', 'parceria') AND v_has_attendance THEN
          a.id IS NOT NULL

        ELSE
          CASE COALESCE(v_event.audience_level, 'all')
            WHEN 'tribe' THEN
              m.current_cycle_active = true
              AND m.tribe_id = v_event_tribe_id
            WHEN 'leadership' THEN
              -- p276 fix: align with event_audience_rules (manager + tribe_leader + deputy_manager + co_gp)
              m.operational_role IN ('manager','tribe_leader')
              OR 'deputy_manager' = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'          = ANY(COALESCE(m.designations, '{}'))
            WHEN 'curators' THEN
              'curator' = ANY(COALESCE(m.designations, '{}'))
            ELSE
              m.current_cycle_active = true
              OR m.operational_role = 'manager'
              OR 'sponsor'    = ANY(COALESCE(m.designations, '{}'))
              OR 'ambassador' = ANY(COALESCE(m.designations, '{}'))
              OR 'curator'    = ANY(COALESCE(m.designations, '{}'))
              OR 'co_gp'      = ANY(COALESCE(m.designations, '{}'))
          END
        END
      )
  ) q;

  RETURN COALESCE(v_result, '[]'::json);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. get_meeting_notes_compliance — exclude confidential initiatives from the
--    platform-wide compliance rollup. Based on the LIVE body; only the WHERE gains the
--    exclusion. It groups ALL events by COALESCE(initiatives.title,...), so the confidential
--    initiative surfaced as a by_tribe entry (masked today only by the incidental recorded>0
--    filter — a data coincidence, not scope). `IS DISTINCT FROM` keeps NULL-initiative
--    (org-level) events. The word 'confidential' in the body marks it gated for the guard.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_meeting_notes_compliance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  WITH stats AS (
    SELECT
      i.legacy_tribe_id AS t_id,
      COALESCE(i.title, 'Gerais/sem tribo') AS group_name,
      count(*) FILTER (WHERE e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL) AS recorded,
      count(*) FILTER (
        WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
          AND e.minutes_text IS NOT NULL
          AND length(trim(e.minutes_text)) >= 20
          AND lower(trim(e.minutes_text)) NOT IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      ) AS with_minutes
    FROM events e
    LEFT JOIN initiatives i ON i.id = e.initiative_id
    WHERE e.date <= current_date
      AND (i.visibility IS DISTINCT FROM 'confidential')  -- #1063: exclude confidential initiatives from the rollup
    GROUP BY i.legacy_tribe_id, COALESCE(i.title, 'Gerais/sem tribo')
  )
  SELECT jsonb_build_object(
    'by_tribe', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'tribe_id', s.t_id, 'tribe_name', s.group_name,
          'recorded', s.recorded, 'with_minutes', s.with_minutes,
          'pct', CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END
        ) ORDER BY CASE WHEN s.recorded > 0 THEN round(100.0 * s.with_minutes / s.recorded) ELSE 100 END ASC
      ) FROM stats s WHERE s.recorded > 0
    ), '[]'::jsonb),
    'total_recorded', (SELECT sum(recorded) FROM stats),
    'total_with_minutes', (SELECT sum(with_minutes) FROM stats),
    'overall_pct', CASE
      WHEN (SELECT sum(recorded) FROM stats) > 0
      THEN round(100.0 * (SELECT sum(with_minutes) FROM stats) / (SELECT sum(recorded) FROM stats))
      ELSE 100
    END
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
