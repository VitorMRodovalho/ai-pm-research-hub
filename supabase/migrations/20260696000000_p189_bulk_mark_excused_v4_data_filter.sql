-- p189 ADR-0011 V4 sweep — bulk_mark_excused data-filter refactor (P179 OPP P3)
--
-- Carries from p179 (out-of-scope at the time):
--   bulk_mark_excused had `can_by_member(v_caller_id, 'manage_event')` as PRIMARY
--   auth gate (already V4). Remaining V3 leftovers were data filters on
--   TARGET member's relationships:
--     1. v_caller_role = 'tribe_leader' AND v_caller_tribe != v_member_tribe
--        → hard-fail EXCEPTION for cross-tribe bulk
--     2. e.type = 'tribo' AND i.legacy_tribe_id = v_member_tribe
--        → tribo events only if member is in event's tribe (V3 single-value tribe_id)
--     3. e.type = 'lideranca' AND m.operational_role IN ('manager','deputy_manager','tribe_leader')
--        → lideranca events only if member is leader (V3 operational_role cache)
--
-- V4 replacements:
--   1. Hard-fail check via auth_engagements + engagement_kind_permissions scope inspection:
--      caller must have org-scope manage_event OR share at least one active initiative with target
--   2. e.type = 'tribo' AND EXISTS engagements where person=member, initiative=event, active
--   3. e.type = 'lideranca' AND can_by_member(p_member_id, 'manage_event') — broader semantic
--      but EMPIRICALLY identical population today (verified p189-boot: 0 inversions). Future
--      committee/workgroup leaders gaining manage_event would automatically be included, which
--      matches V4 model intent.
--
-- Empirical verification (p189-boot, 2026-05-18):
--   - 9 members with V3 leader operational_role; all have can_by_member('manage_event')=true
--   - 0 members with can_by_member('manage_event')=true who aren't V3 leader (no inversions)
--   - 0 'comms' events in DB; 0 attendance for comms (type IN clause has comms but no matching
--     OR condition — harmless dead code, preserved to keep scope tight; carry as backlog OPP)
--
-- Semantic effect (intended):
--   - Behavior IDENTICAL to V3 today for all 9 V3 leader members + admins
--   - Tribe leader cross-tribe bulk → still hard-fails (preserved)
--   - Member's tribe membership now sourced from V4 engagements (single source of truth)
--   - Leader data filter future-proof: new committee/workgroup leaders auto-included
--
-- Rollback: revert to body in 20260684000000 (Phase B drift capture). No data ops.

DROP FUNCTION IF EXISTS public.bulk_mark_excused(uuid, date, date, text, boolean);
CREATE FUNCTION public.bulk_mark_excused(
  p_member_id uuid,
  p_date_from date,
  p_date_to date,
  p_reason text DEFAULT NULL::text,
  p_override_existing boolean DEFAULT false
) RETURNS json
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_person_id uuid;
  v_member_person_id uuid;
  v_caller_has_org_scope boolean;
  v_count int := 0;
  v_skipped int := 0;
BEGIN
  -- Resolve caller (members table — attendance.member_id FK still members)
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- Caller's V4 person_id for engagement lookups
  SELECT person_id INTO v_caller_person_id FROM public.members WHERE id = v_caller_id;

  -- Top gate (already V4 in p178/p179): caller must have manage_event somewhere
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
  END IF;

  -- Resolve target's V4 person_id (for engagement-based data filtering)
  SELECT person_id INTO v_member_person_id FROM public.members WHERE id = p_member_id;
  IF v_member_person_id IS NULL THEN RAISE EXCEPTION 'Member not found'; END IF;

  -- V4 scope check (preserves V3 hard-fail semantics):
  -- If caller has org-scope manage_event, unrestricted. Otherwise, caller is
  -- initiative-scoped only and must share at least one active initiative with target.
  SELECT EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = 'manage_event'
    WHERE ae.person_id = v_caller_person_id
      AND ae.is_authoritative
      AND ekp.scope IN ('organization', 'global')
  ) INTO v_caller_has_org_scope;

  IF NOT v_caller_has_org_scope THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.auth_engagements ae_c
      JOIN public.engagement_kind_permissions ekp
        ON ekp.kind = ae_c.kind AND ekp.role = ae_c.role AND ekp.action = 'manage_event'
      JOIN public.engagements eg_t ON eg_t.initiative_id = ae_c.initiative_id
      WHERE ae_c.person_id = v_caller_person_id
        AND ae_c.is_authoritative
        AND ekp.scope = 'initiative'
        AND eg_t.person_id = v_member_person_id
        AND eg_t.status = 'active'
        AND eg_t.revoked_at IS NULL
    ) THEN
      RAISE EXCEPTION 'Unauthorized: caller can only manage members of own initiative';
    END IF;
  END IF;

  -- Diagnostic count: how many events match criteria but already have non-excused attendance
  -- (would be skipped unless override=true). When p_override_existing=true,
  -- v_skipped stays at 0 (initialized at decl) — semantically "N/A in override
  -- mode" because override forces upsert of ALL matching events without skipping.
  -- Callers that display events_skipped should interpret 0 in override mode
  -- as informational-only, not as "nothing was skipped".
  IF NOT p_override_existing THEN
    SELECT COUNT(*) INTO v_skipped
    FROM public.events e
    WHERE e.date >= p_date_from AND e.date <= p_date_to
      AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
      AND (
        -- All-org events apply to everyone
        e.type IN ('geral', 'kickoff')
        -- Tribo events: only if target has active engagement on the event's initiative (V4 source)
        OR (e.type = 'tribo' AND EXISTS (
          SELECT 1 FROM public.engagements eg
          WHERE eg.person_id = v_member_person_id
            AND eg.initiative_id = e.initiative_id
            AND eg.status = 'active'
            AND eg.revoked_at IS NULL
        ))
        -- Lideranca events: only if target has any leader-tier engagement (V4 catalog-driven)
        OR (e.type = 'lideranca' AND public.can_by_member(p_member_id, 'manage_event'))
      )
      AND EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false);
  END IF;

  -- Apply: insert excused attendance for all qualifying events
  INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
  SELECT e.id, p_member_id, false, true, p_reason
  FROM public.events e
  WHERE e.date >= p_date_from AND e.date <= p_date_to
    AND e.type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms')
    AND (
      e.type IN ('geral', 'kickoff')
      OR (e.type = 'tribo' AND EXISTS (
        SELECT 1 FROM public.engagements eg
        WHERE eg.person_id = v_member_person_id
          AND eg.initiative_id = e.initiative_id
          AND eg.status = 'active'
          AND eg.revoked_at IS NULL
      ))
      OR (e.type = 'lideranca' AND public.can_by_member(p_member_id, 'manage_event'))
    )
    AND (
      p_override_existing
      OR NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id AND a.member_id = p_member_id AND a.excused = false)
    )
  ON CONFLICT (event_id, member_id) DO UPDATE SET
    present = false,
    excused = true,
    excuse_reason = p_reason,
    updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'events_marked', v_count,
    'events_skipped', v_skipped,
    'date_from', p_date_from,
    'date_to', p_date_to,
    'override_used', p_override_existing
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
