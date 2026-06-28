-- #301 / ADR-0108: enqueue functions + FSM triggers + assign_curation_reviewer extension.
-- Eager-on-handoff policy (PM 2026-06-27): on entry to curation_pending, queue a pending_grant
-- per (submitted artifact × curator). On exit, queue revokes (granted→pending_revoke) and cancel
-- never-executed grants (pending_grant→cancelled). The grant/revoke EF (drained by cron) does the
-- actual Drive call. Trigger fns are SECURITY DEFINER (owner) so the ledger INSERT bypasses RLS.

-- ===== Enqueue: committee handoff (eager → all curate_content holders) =====
CREATE OR REPLACE FUNCTION public.enqueue_curation_drive_grants(p_item_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE
  v_org uuid;
  v_inserted int := 0;
BEGIN
  v_org := (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1);
  IF v_org IS NULL THEN RETURN; END IF;

  WITH curators AS (
    SELECT m.id AS member_id, lower(m.email)::citext AS email
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.email IS NOT NULL AND m.email <> ''
      AND public.can_by_member(m.id, 'curate_content')
  ),
  ins AS (
    INSERT INTO public.drive_curation_grants (
      organization_id, board_item_id, drive_file_id, drive_file_url,
      grantee_member_id, permission_email, role, grant_reason, status
    )
    SELECT v_org, p_item_id, f.drive_file_id, f.drive_file_url,
           c.member_id, c.email, 'commenter', 'committee_handoff', 'pending_grant'
    FROM public.board_item_files f
    CROSS JOIN curators c
    WHERE f.board_item_id = p_item_id AND f.deleted_at IS NULL
    ON CONFLICT (drive_file_id, permission_email)
      WHERE status IN ('pending_grant','granted','pending_revoke')
    DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  IF v_inserted > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'curation_drive_grant_queued', 'drive_curation_grants', p_item_id, '{}'::jsonb,
            jsonb_build_object('queued', v_inserted, 'reason', 'committee_handoff'));
  END IF;
END;
$$;

-- ===== Enqueue: a single assigned reviewer (co_gp / curate_content) =====
CREATE OR REPLACE FUNCTION public.enqueue_curation_drive_grant_for_member(
  p_item_id uuid, p_member_id uuid, p_reason text DEFAULT 'reviewer_assignment'
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE
  v_org uuid;
  v_inserted int := 0;
BEGIN
  IF p_reason NOT IN ('committee_handoff','reviewer_assignment','manual') THEN
    p_reason := 'reviewer_assignment';
  END IF;
  v_org := (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1);
  IF v_org IS NULL THEN RETURN; END IF;

  WITH ins AS (
    INSERT INTO public.drive_curation_grants (
      organization_id, board_item_id, drive_file_id, drive_file_url,
      grantee_member_id, permission_email, role, grant_reason, status
    )
    SELECT v_org, p_item_id, f.drive_file_id, f.drive_file_url,
           m.id, lower(m.email)::citext, 'commenter', p_reason, 'pending_grant'
    FROM public.board_item_files f
    JOIN public.members m ON m.id = p_member_id
    WHERE f.board_item_id = p_item_id AND f.deleted_at IS NULL
      AND m.email IS NOT NULL AND m.email <> ''
    ON CONFLICT (drive_file_id, permission_email)
      WHERE status IN ('pending_grant','granted','pending_revoke')
    DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  IF v_inserted > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'curation_drive_grant_queued', 'drive_curation_grants', p_item_id, '{}'::jsonb,
            jsonb_build_object('queued', v_inserted, 'reason', p_reason, 'member_id', p_member_id));
  END IF;
END;
$$;

-- ===== Enqueue: revoke on leaving curation =====
-- granted rows → pending_revoke (Drive DELETE needed); never-executed pending_grant → cancelled.
CREATE OR REPLACE FUNCTION public.enqueue_curation_drive_revokes(p_item_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_revoke int := 0; v_cancel int := 0;
BEGIN
  WITH r AS (
    UPDATE public.drive_curation_grants
       SET status = 'pending_revoke', updated_at = now()
     WHERE board_item_id = p_item_id AND status = 'granted'
     RETURNING 1
  ) SELECT count(*) INTO v_revoke FROM r;

  WITH c AS (
    UPDATE public.drive_curation_grants
       SET status = 'cancelled', revoked_at = now(), updated_at = now()
     WHERE board_item_id = p_item_id AND status = 'pending_grant'
     RETURNING 1
  ) SELECT count(*) INTO v_cancel FROM c;

  IF v_revoke > 0 OR v_cancel > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'curation_drive_grant_revoke_queued', 'drive_curation_grants', p_item_id, '{}'::jsonb,
            jsonb_build_object('queued_revoke', v_revoke, 'cancelled', v_cancel));
  END IF;
END;
$$;

-- ===== FSM trigger on board_items.curation_status =====
CREATE OR REPLACE FUNCTION public.trg_curation_drive_grants_on_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
BEGIN
  IF NEW.curation_status = 'curation_pending'
     AND OLD.curation_status IS DISTINCT FROM 'curation_pending' THEN
    PERFORM public.enqueue_curation_drive_grants(NEW.id);
  ELSIF OLD.curation_status = 'curation_pending'
        AND NEW.curation_status IS DISTINCT FROM 'curation_pending' THEN
    PERFORM public.enqueue_curation_drive_revokes(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_curation_drive_grants ON public.board_items;
CREATE TRIGGER trg_curation_drive_grants
  AFTER UPDATE OF curation_status ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION public.trg_curation_drive_grants_on_status();

-- ===== Extend assign_curation_reviewer (full body re-create + reviewer enqueue) =====
-- board_lifecycle_events stores only the reviewer's NAME (in reason), not their id, so the assigned
-- reviewer cannot be derived from the event row — the enqueue must happen here where p_reviewer_id
-- is in scope. Full CREATE OR REPLACE carries the verbatim live body (body-hash drift gate) plus
-- the appended #301 enqueue.
CREATE OR REPLACE FUNCTION public.assign_curation_reviewer(p_item_id uuid, p_reviewer_id uuid, p_round integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller   members%rowtype;
  v_reviewer members%rowtype;
  v_item     board_items%rowtype;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  -- ADR-0041: strict V4 catalog (committee work)
  IF NOT public.can_by_member(v_caller.id, 'participate_in_governance_review') THEN
    RAISE EXCEPTION 'Requires participate_in_governance_review';
  END IF;

  SELECT * INTO v_reviewer FROM members WHERE id = p_reviewer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reviewer not found'; END IF;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content').
  -- Target-user check (reviewer, not caller). co_gp legacy path preserved as V3.
  IF NOT (
    public.can_by_member(p_reviewer_id, 'curate_content')
    OR 'co_gp' = ANY(coalesce(v_reviewer.designations, array[]::text[]))
  ) THEN
    RAISE EXCEPTION 'Reviewer must have curate_content authority or co_gp designation';
  END IF;

  SELECT * INTO v_item FROM board_items WHERE id = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;

  -- #785 PR-3: confidential gate (curator without engagement cannot act on confidential items)
  IF NOT public.rls_can_see_board(v_item.board_id) THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  IF p_reviewer_id = v_item.assignee_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM board_lifecycle_events
      WHERE item_id = p_item_id AND action = 'reviewer_assigned'
        AND review_round = p_round AND actor_member_id IS DISTINCT FROM p_reviewer_id
    ) THEN
      RAISE EXCEPTION 'Cannot designate item author as sole reviewer';
    END IF;
  END IF;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id, review_round)
  VALUES (v_item.board_id, p_item_id, 'reviewer_assigned',
    'Revisor designado: ' || v_reviewer.name, v_caller.id, p_round);

  -- #301 / ADR-0108: give the assigned reviewer temporary Drive access to the submitted artifacts
  -- (only while the item is actually in curation; otherwise the entry trigger covers the committee).
  IF v_item.curation_status = 'curation_pending' THEN
    PERFORM public.enqueue_curation_drive_grant_for_member(p_item_id, p_reviewer_id, 'reviewer_assignment');
  END IF;
END;
$function$;

NOTIFY pgrst, 'reload schema';
