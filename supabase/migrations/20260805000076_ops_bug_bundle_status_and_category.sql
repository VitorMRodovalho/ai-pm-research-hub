-- Ops-bug bundle (p277) — meeting decisions (#450) + offboarding (#449)
--
-- #450: register_decision + create_action_item(kind='decision') hardcoded status='completed',
--       which is NOT in meeting_action_items_status_check = {open,done,cancelled,carried_over}.
--       Every decision-registration call failed at runtime (SQLSTATE 23514). Live evidence:
--       0 rows with kind='decision' and 0 with status='completed' ever persisted (path 100% dead).
--       Fix: 'completed' -> 'done' (the valid terminal status for an already-made decision).
--
-- #449: _offboarding_create_stub inferred reason_category_code from free-text via ILIKE heuristics
--       and fell through to NULL when none matched, but reason_category_code is NOT NULL + FK to
--       offboarding_reason_categories(code). Free-text reasons matching no heuristic failed the
--       whole offboard (SQLSTATE 23502), rolling back the member_status flip.
--       Fix: coalesce(v_inferred_category, 'other') ('other' is a valid active category code).
--
-- All three: minimum-diff CREATE OR REPLACE (signature, SECURITY DEFINER, search_path='' preserved;
-- privileges preserved on REPLACE). Only the offending literal changes.
--
-- Rollback: re-apply the prior bodies (register_decision/create_action_item with 'completed';
--           _offboarding_create_stub with bare v_inferred_category). Not recommended — restores the bugs.

-- ── #450a ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_decision(p_event_id uuid, p_decision_text text, p_decision_maker_id uuid, p_rationale text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_member_id uuid;
  v_action_item_id uuid;
begin
  -- Resolve current member
  select id into v_member_id from public.members where auth_id = auth.uid();
  if v_member_id is null then
    raise exception 'Not authenticated as a member';
  end if;

  -- Insert decision as a special action item
  insert into public.meeting_action_items (
    event_id, description, kind, status, assignee_id, created_by, rationale
  ) values (
    p_event_id, p_decision_text, 'decision', 'done', p_decision_maker_id, v_member_id, p_rationale
  ) returning id into v_action_item_id;

  return v_action_item_id;
end;
$function$;

-- ── #450b ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_action_item(p_event_id uuid, p_description text, p_assignee_id uuid, p_due_date date, p_board_item_id uuid, p_checklist_item_id uuid, p_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_member_id uuid;
  v_action_item_id uuid;
begin
  select id into v_member_id from public.members where auth_id = auth.uid();
  if v_member_id is null then
    raise exception 'Not authenticated as a member';
  end if;

  insert into public.meeting_action_items (
    event_id, description, kind, status, assignee_id, due_date, board_item_id, checklist_item_id, created_by
  ) values (
    p_event_id, p_description, coalesce(p_kind, 'task'),
    case when p_kind = 'decision' then 'done' else 'open' end,
    p_assignee_id, p_due_date, p_board_item_id, p_checklist_item_id, v_member_id
  ) returning id into v_action_item_id;

  return v_action_item_id;
end;
$function$;

-- ── #449 ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._offboarding_create_stub(p_member_id uuid, p_reason text, p_reason_category_code text, p_initiated_by uuid, p_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_record_id uuid;
  v_inferred_category text;
begin
  -- Infer category from free-text reason when no explicit code supplied
  v_inferred_category := case
    when p_reason_category_code is not null then p_reason_category_code
    when p_reason ilike '%mudança%' or p_reason ilike '%mudou%' then 'relocation'
    when p_reason ilike '%tempo%' or p_reason ilike '%disponib%' then 'time_constraints'
    when p_reason ilike '%trabalho%' or p_reason ilike '%emprego%' then 'career_change'
    else null
  end;

  insert into public.member_offboarding_records (
    member_id, reason, reason_category_code, status, initiated_by, notes, offboarded_at
  ) values (
    p_member_id, p_reason, coalesce(v_inferred_category, 'other'), 'completed', p_initiated_by, p_notes, now()
  ) returning id into v_record_id;

  return v_record_id;
end;
$function$;
