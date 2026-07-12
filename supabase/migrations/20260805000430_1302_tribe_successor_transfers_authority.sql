-- #1302 — Tribe leader succession must transfer V4 AUTHORITY, not just the pointer.
--
-- Background (V4_AUTHORITY_MODEL.md, ADR-0007): leader authority is an engagement grant
-- (volunteer x leader scoped to the tribe's initiative), NOT the operational_role cache.
-- The old admin_change_tribe_leader only wrote members.operational_role (a cache the
-- trg_sync_role_cache trigger recomputes from engagements) + the tribes.leader_member_id
-- pointer. It never touched the engagements layer, so:
--   * the successor got the label but no real can_by_member() authority (and the label
--     reverted to the derived value on the next engagement recompute);
--   * the outgoing leader kept their volunteer x leader engagement and thus retained real
--     leader authority on the initiative (symmetric bug).
--
-- This makes the swap mutate the engagement layer (source of truth) and lets the trigger
-- own operational_role. Decisions (PM 2026-07-12):
--   A1 — successor without a signed volunteer term: create a non-authoritative engagement
--        and report authority_pending_agreement=true (do NOT bypass the term gate).
--   B1 — outgoing leader: demote engagement leader->researcher (stays in the tribe).
--
-- Shared swap fixed here => covers both direct admin swaps and place_tribe_successor (#1296),
-- which reuses this RPC.
--
-- Two pre-existing latent bugs, exposed while wiring B1, are bundled because the succession
-- cannot complete without them:
--   * the outgoing-leader guard used `v_old_leader IS NOT NULL` (a composite-record test that
--     is FALSE when any member column is NULL), so the whole outgoing-leader block silently
--     no-op'd. Fixed to `v_old_leader.id IS NOT NULL` (PK test).
--   * member_cycle_history has UNIQUE(member_id, cycle_code); a mid-cycle succession collides
--     with the successor's / outgoing leader's existing current-cycle row. Both history writes
--     now ON CONFLICT DO UPDATE the snapshot instead of raising.

CREATE OR REPLACE FUNCTION public.admin_change_tribe_leader(p_tribe_id integer, p_new_leader_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_person_id uuid;
  v_caller_name text;
  v_tribe record;
  v_old_leader record;
  v_old_leader_name text;
  v_new_leader record;
  v_cycle record;
  v_initiative_id uuid;
  v_new_person_id uuid;
  v_existing_eng uuid;
  v_eng_applied boolean := false;
  v_authority_pending boolean := false;
BEGIN
  SELECT id, name, person_id INTO v_caller_id, v_caller_name, v_caller_person_id
    FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'permission_denied: manage_member required';
  END IF;

  SELECT * INTO v_tribe FROM public.tribes WHERE id = p_tribe_id;
  IF v_tribe IS NULL THEN RAISE EXCEPTION 'Tribe not found: %', p_tribe_id; END IF;

  SELECT * INTO v_new_leader FROM public.members WHERE id = p_new_leader_id;
  IF v_new_leader IS NULL THEN RAISE EXCEPTION 'New leader member not found: %', p_new_leader_id; END IF;
  v_new_person_id := v_new_leader.person_id;

  SELECT * INTO v_cycle FROM public.cycles WHERE is_current = true LIMIT 1;

  -- #1302: resolve the tribe's initiative (V4 authority is scoped to it).
  SELECT i.id INTO v_initiative_id
    FROM public.initiatives i
   WHERE i.legacy_tribe_id = p_tribe_id AND i.kind = 'research_tribe'
   ORDER BY i.id LIMIT 1;

  -- ===================== OUTGOING LEADER =====================
  IF v_tribe.leader_member_id IS NOT NULL THEN
    SELECT * INTO v_old_leader FROM public.members WHERE id = v_tribe.leader_member_id;

    IF v_old_leader.id IS NOT NULL THEN
      v_old_leader_name := v_old_leader.name;
      INSERT INTO public.member_cycle_history (
        member_id, cycle_code, cycle_label, cycle_start, cycle_end,
        operational_role, designations, tribe_id, tribe_name,
        chapter, is_active, member_name_snapshot, notes
      ) VALUES (
        v_old_leader.id,
        COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
        COALESCE(v_cycle.cycle_start, now()::date), now()::date,
        v_old_leader.operational_role, v_old_leader.designations,
        v_old_leader.tribe_id, v_tribe.name,
        v_old_leader.chapter, true, v_old_leader.name,
        'LEADER_REMOVED: Replaced by ' || v_new_leader.name || '. Reason: ' || p_reason || '. By: ' || v_caller_name
      )
      ON CONFLICT (member_id, cycle_code) DO UPDATE SET
        cycle_label = EXCLUDED.cycle_label, cycle_end = EXCLUDED.cycle_end,
        operational_role = EXCLUDED.operational_role, designations = EXCLUDED.designations,
        tribe_id = EXCLUDED.tribe_id, tribe_name = EXCLUDED.tribe_name,
        chapter = EXCLUDED.chapter, is_active = EXCLUDED.is_active,
        member_name_snapshot = EXCLUDED.member_name_snapshot, notes = EXCLUDED.notes;

      -- #1302 (B1): demote the outgoing leader's engagement so real authority is removed;
      -- they stay in the tribe as a researcher. trg_sync_role_cache recomputes the cache.
      IF v_initiative_id IS NOT NULL AND v_old_leader.person_id IS NOT NULL THEN
        UPDATE public.engagements
           SET role = 'researcher', updated_at = now()
         WHERE person_id = v_old_leader.person_id
           AND initiative_id = v_initiative_id
           AND status = 'active'
           AND kind = 'volunteer'
           AND role IN ('leader', 'comms_leader');
      END IF;

      -- fallback cache write (kept for tribes without a mapped initiative)
      UPDATE public.members SET operational_role = 'researcher'
      WHERE id = v_old_leader.id AND operational_role = 'tribe_leader';

      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (v_caller_id, 'role.demoted', 'member', v_old_leader.id,
        jsonb_build_object('old_role', 'tribe_leader', 'new_role', 'researcher',
          'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));
    END IF;
  END IF;

  -- ===================== INCOMING LEADER =====================
  -- pointer / dual-write partner (kept)
  UPDATE public.members SET tribe_id = p_tribe_id WHERE id = p_new_leader_id;

  IF v_initiative_id IS NOT NULL AND v_new_person_id IS NOT NULL THEN
    -- #1302: grant leader authority via the engagement layer (source of truth). Promote an
    -- existing active engagement on this initiative (preserves the signed term), otherwise
    -- create a fresh volunteer x leader engagement.
    SELECT e.id INTO v_existing_eng
      FROM public.engagements e
     WHERE e.person_id = v_new_person_id
       AND e.initiative_id = v_initiative_id
       AND e.status = 'active'
     ORDER BY (e.kind = 'volunteer') DESC, e.created_at DESC
     LIMIT 1;

    IF v_existing_eng IS NOT NULL THEN
      UPDATE public.engagements SET role = 'leader', updated_at = now() WHERE id = v_existing_eng;
    ELSE
      INSERT INTO public.engagements (person_id, initiative_id, kind, role, status,
        legal_basis, granted_by, metadata, organization_id, start_date)
      VALUES (v_new_person_id, v_initiative_id, 'volunteer', 'leader', 'active',
        'consent', v_caller_person_id,
        jsonb_build_object('source', 'admin_change_tribe_leader', 'granted_by', v_caller_person_id::text),
        COALESCE(v_tribe.organization_id, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid),
        CURRENT_DATE);
    END IF;

    v_eng_applied := true;

    -- volunteer engagements require a signed term to be authoritative. If the successor has
    -- not signed, authority is pending and we must NOT fake the tribe_leader cache label.
    SELECT NOT COALESCE(bool_or(ae.is_authoritative), false) INTO v_authority_pending
      FROM public.auth_engagements ae
     WHERE ae.person_id = v_new_person_id
       AND ae.initiative_id = v_initiative_id
       AND ae.role = 'leader';

    IF NOT v_authority_pending THEN
      UPDATE public.members SET operational_role = 'tribe_leader'
      WHERE id = p_new_leader_id AND operational_role IS DISTINCT FROM 'tribe_leader';
    END IF;
  ELSE
    -- legacy fallback: no initiative mapped -> keep prior cache-only behavior.
    UPDATE public.members SET operational_role = 'tribe_leader' WHERE id = p_new_leader_id;
  END IF;

  UPDATE public.tribes SET leader_member_id = p_new_leader_id WHERE id = p_tribe_id;

  INSERT INTO public.member_cycle_history (
    member_id, cycle_code, cycle_label, cycle_start, cycle_end,
    operational_role, designations, tribe_id, tribe_name,
    chapter, is_active, member_name_snapshot, notes
  ) VALUES (
    p_new_leader_id,
    COALESCE(v_cycle.cycle_code, 'cycle_3'), COALESCE(v_cycle.cycle_label, 'Ciclo 3'),
    COALESCE(v_cycle.cycle_start, now()::date), NULL,
    'tribe_leader', v_new_leader.designations, p_tribe_id, v_tribe.name,
    v_new_leader.chapter, true, v_new_leader.name,
    'LEADER_ASSIGNED: Promoted to leader of ' || v_tribe.name || '. Reason: ' || p_reason || '. By: ' || v_caller_name
  )
  ON CONFLICT (member_id, cycle_code) DO UPDATE SET
    cycle_label = EXCLUDED.cycle_label, cycle_end = EXCLUDED.cycle_end,
    operational_role = EXCLUDED.operational_role, designations = EXCLUDED.designations,
    tribe_id = EXCLUDED.tribe_id, tribe_name = EXCLUDED.tribe_name,
    chapter = EXCLUDED.chapter, is_active = EXCLUDED.is_active,
    member_name_snapshot = EXCLUDED.member_name_snapshot, notes = EXCLUDED.notes;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'role.promoted', 'member', p_new_leader_id,
    jsonb_build_object('old_role', v_new_leader.operational_role, 'new_role', 'tribe_leader',
      'tribe_id', p_tribe_id, 'tribe_name', v_tribe.name, 'reason', p_reason));

  RETURN jsonb_build_object(
    'success', true, 'tribe', v_tribe.name,
    'old_leader', COALESCE(v_old_leader_name, 'N/A'),
    'new_leader', v_new_leader.name, 'reason', p_reason,
    'initiative_id', v_initiative_id,
    'authority_granted', v_eng_applied AND NOT v_authority_pending,
    'authority_pending_agreement', v_authority_pending
  );
END;
$function$;
