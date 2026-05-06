-- p95 #130 — webinar proposals workflow
-- Spinoff #89 Frente 3 (split p95 per PM decision 3A).
-- Discussão Ana ↔ Vitor ↔ Fabricio (20-21/Abr) sobre storytelling de webinar séries acontece em WhatsApp sem trail.
-- Backend portion only — frontend wizard deferred to PM browser session.
--
-- Spec correction: quadrant_anchor is integer (not uuid as in issue body), since quadrants.id is integer.
--
-- State machine: draft → submitted → review → approved → converted_to_webinar
--                                  ↘             ↘ rejected
-- v1 simplification: create() defaults to 'submitted' (líder skips draft).
--
-- Authority:
-- - create/update own: any active member (proposer)
-- - review (approve/reject): manage_event (comitê)
-- - convert: manage_event (comitê)
-- - list: any active member sees own; manage_event sees all
--
-- Rollback:
--   DROP TABLE IF EXISTS public.webinar_proposals CASCADE;
--   DROP FUNCTION IF EXISTS public.create_webinar_proposal(text,text,integer,uuid,text[],uuid[],integer,text);
--   DROP FUNCTION IF EXISTS public.update_webinar_proposal(uuid,text,text,integer,uuid,text[],uuid[],integer,text);
--   DROP FUNCTION IF EXISTS public.review_webinar_proposal(uuid,text,text,text);
--   DROP FUNCTION IF EXISTS public.convert_proposal_to_webinar(uuid,timestamptz,text,integer,uuid);
--   DROP FUNCTION IF EXISTS public.list_webinar_proposals(text);

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.webinar_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proposed_title text NOT NULL,
  proposed_by_tribe_id integer,
  proposer_member_id uuid NOT NULL REFERENCES public.members(id),
  format_type text NOT NULL CHECK (format_type IN ('palestra','painel','dupla','lightning','workshop')),
  proposed_speakers uuid[],
  themes text[],
  quadrant_anchor integer REFERENCES public.quadrants(id),
  series_id uuid REFERENCES public.publication_series(id),
  status text NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('draft','submitted','review','approved','rejected','converted_to_webinar')),
  webinar_id uuid REFERENCES public.webinars(id),
  rejection_reason text,
  reviewed_by uuid REFERENCES public.members(id),
  reviewed_at timestamptz,
  notes text,
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid REFERENCES public.organizations(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS webinar_proposals_status_idx ON public.webinar_proposals(status);
CREATE INDEX IF NOT EXISTS webinar_proposals_proposer_idx ON public.webinar_proposals(proposer_member_id);
CREATE INDEX IF NOT EXISTS webinar_proposals_series_idx ON public.webinar_proposals(series_id) WHERE series_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS webinar_proposals_webinar_idx ON public.webinar_proposals(webinar_id) WHERE webinar_id IS NOT NULL;

COMMENT ON TABLE public.webinar_proposals IS
  'Webinar proposals workflow (#130 / #89 Frente 3). Líder propõe, comitê (manage_event) review, convert para webinars row when approved. Audit via admin_audit_log.';

-- ============================================================
-- TRIGGERS
-- ============================================================
CREATE OR REPLACE FUNCTION public.webinar_proposals_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS webinar_proposals_updated_at_trg ON public.webinar_proposals;
CREATE TRIGGER webinar_proposals_updated_at_trg
BEFORE UPDATE ON public.webinar_proposals
FOR EACH ROW EXECUTE FUNCTION public.webinar_proposals_set_updated_at();

-- ============================================================
-- RLS — deny-all; SECDEF RPCs handle access
-- ============================================================
ALTER TABLE public.webinar_proposals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS webinar_proposals_deny_all ON public.webinar_proposals;
CREATE POLICY webinar_proposals_deny_all ON public.webinar_proposals
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- ============================================================
-- create_webinar_proposal
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_webinar_proposal(
  p_proposed_title text,
  p_format_type text,
  p_proposed_by_tribe_id integer DEFAULT NULL,
  p_series_id uuid DEFAULT NULL,
  p_themes text[] DEFAULT NULL,
  p_proposed_speakers uuid[] DEFAULT NULL,
  p_quadrant_anchor integer DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_proposal_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_proposed_title IS NULL OR length(trim(p_proposed_title)) = 0 THEN
    RAISE EXCEPTION 'proposed_title is required';
  END IF;
  IF p_format_type IS NULL OR p_format_type NOT IN ('palestra','painel','dupla','lightning','workshop') THEN
    RAISE EXCEPTION 'format_type must be one of: palestra, painel, dupla, lightning, workshop';
  END IF;

  INSERT INTO public.webinar_proposals (
    proposed_title, proposed_by_tribe_id, proposer_member_id, format_type,
    proposed_speakers, themes, quadrant_anchor, series_id, notes, status
  )
  VALUES (
    trim(p_proposed_title), p_proposed_by_tribe_id, v_caller_id, p_format_type,
    p_proposed_speakers, p_themes, p_quadrant_anchor, p_series_id, p_notes, 'submitted'
  )
  RETURNING id INTO v_proposal_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'create_webinar_proposal', 'webinar_proposal', v_proposal_id,
    jsonb_build_object(
      'title', p_proposed_title, 'format', p_format_type,
      'tribe_id', p_proposed_by_tribe_id, 'series_id', p_series_id,
      'quadrant_anchor', p_quadrant_anchor
    ),
    jsonb_build_object('source','mcp','issue','#130')
  );

  RETURN jsonb_build_object('success', true, 'proposal_id', v_proposal_id, 'status', 'submitted');
END; $function$;

GRANT EXECUTE ON FUNCTION public.create_webinar_proposal(text,text,integer,uuid,text[],uuid[],integer,text) TO authenticated;

-- ============================================================
-- update_webinar_proposal — proposer or comitê edit (only pre-approval states)
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_webinar_proposal(
  p_proposal_id uuid,
  p_proposed_title text DEFAULT NULL,
  p_format_type text DEFAULT NULL,
  p_proposed_by_tribe_id integer DEFAULT NULL,
  p_series_id uuid DEFAULT NULL,
  p_themes text[] DEFAULT NULL,
  p_proposed_speakers uuid[] DEFAULT NULL,
  p_quadrant_anchor integer DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_proposer uuid;
  v_status text;
  v_is_committee boolean;
  v_updated text[] := '{}';
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT proposer_member_id, status INTO v_proposer, v_status
  FROM public.webinar_proposals WHERE id = p_proposal_id;
  IF v_proposer IS NULL THEN RAISE EXCEPTION 'Proposal not found: %', p_proposal_id; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');

  IF v_caller_id <> v_proposer AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: only proposer or comitê can edit';
  END IF;

  IF v_status NOT IN ('draft','submitted','review') THEN
    RAISE EXCEPTION 'Cannot edit proposal in status %: only draft/submitted/review allowed', v_status;
  END IF;

  IF p_proposed_title IS NOT NULL THEN
    UPDATE public.webinar_proposals SET proposed_title = trim(p_proposed_title) WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'proposed_title');
  END IF;
  IF p_format_type IS NOT NULL THEN
    IF p_format_type NOT IN ('palestra','painel','dupla','lightning','workshop') THEN
      RAISE EXCEPTION 'invalid format_type %', p_format_type;
    END IF;
    UPDATE public.webinar_proposals SET format_type = p_format_type WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'format_type');
  END IF;
  IF p_proposed_by_tribe_id IS NOT NULL THEN
    UPDATE public.webinar_proposals SET proposed_by_tribe_id = p_proposed_by_tribe_id WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'proposed_by_tribe_id');
  END IF;
  IF p_series_id IS NOT NULL THEN
    UPDATE public.webinar_proposals SET series_id = p_series_id WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'series_id');
  END IF;
  IF p_themes IS NOT NULL THEN
    UPDATE public.webinar_proposals SET themes = p_themes WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'themes');
  END IF;
  IF p_proposed_speakers IS NOT NULL THEN
    UPDATE public.webinar_proposals SET proposed_speakers = p_proposed_speakers WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'proposed_speakers');
  END IF;
  IF p_quadrant_anchor IS NOT NULL THEN
    UPDATE public.webinar_proposals SET quadrant_anchor = p_quadrant_anchor WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'quadrant_anchor');
  END IF;
  IF p_notes IS NOT NULL THEN
    UPDATE public.webinar_proposals SET notes = p_notes WHERE id = p_proposal_id;
    v_updated := array_append(v_updated, 'notes');
  END IF;

  IF array_length(v_updated, 1) IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'no fields provided');
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'update_webinar_proposal', 'webinar_proposal', p_proposal_id,
    jsonb_build_object('updated_fields', to_jsonb(v_updated), 'status_at_edit', v_status),
    jsonb_build_object('source','mcp','issue','#130','as_committee', v_is_committee AND v_caller_id <> v_proposer)
  );

  RETURN jsonb_build_object('success', true, 'proposal_id', p_proposal_id, 'updated_fields', to_jsonb(v_updated));
END; $function$;

GRANT EXECUTE ON FUNCTION public.update_webinar_proposal(uuid,text,text,integer,uuid,text[],uuid[],integer,text) TO authenticated;

-- ============================================================
-- review_webinar_proposal — comitê approve/reject
-- ============================================================
CREATE OR REPLACE FUNCTION public.review_webinar_proposal(
  p_proposal_id uuid,
  p_decision text,           -- 'approve' | 'reject' | 'mark_review'
  p_rejection_reason text DEFAULT NULL,
  p_review_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_status text;
  v_new_status text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event (comitê)';
  END IF;

  IF p_decision NOT IN ('approve','reject','mark_review') THEN
    RAISE EXCEPTION 'decision must be approve | reject | mark_review';
  END IF;

  SELECT status INTO v_status FROM public.webinar_proposals WHERE id = p_proposal_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Proposal not found: %', p_proposal_id; END IF;

  IF v_status NOT IN ('submitted','review') THEN
    RAISE EXCEPTION 'Cannot review proposal in status %: only submitted/review allowed', v_status;
  END IF;

  IF p_decision = 'reject' AND (p_rejection_reason IS NULL OR length(trim(p_rejection_reason)) = 0) THEN
    RAISE EXCEPTION 'rejection_reason is required when decision=reject';
  END IF;

  v_new_status := CASE p_decision
                    WHEN 'approve' THEN 'approved'
                    WHEN 'reject'  THEN 'rejected'
                    WHEN 'mark_review' THEN 'review'
                  END;

  UPDATE public.webinar_proposals
     SET status = v_new_status,
         reviewed_by = v_caller_id,
         reviewed_at = now(),
         rejection_reason = CASE WHEN p_decision = 'reject' THEN trim(p_rejection_reason) ELSE rejection_reason END,
         notes = COALESCE(p_review_notes, notes)
   WHERE id = p_proposal_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'review_webinar_proposal', 'webinar_proposal', p_proposal_id,
    jsonb_build_object(
      'decision', p_decision,
      'from_status', v_status,
      'to_status', v_new_status,
      'rejection_reason', p_rejection_reason
    ),
    jsonb_build_object('source','mcp','issue','#130')
  );

  RETURN jsonb_build_object(
    'success', true, 'proposal_id', p_proposal_id,
    'from_status', v_status, 'to_status', v_new_status
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.review_webinar_proposal(uuid,text,text,text) TO authenticated;

-- ============================================================
-- convert_proposal_to_webinar — only when status=approved
-- ============================================================
CREATE OR REPLACE FUNCTION public.convert_proposal_to_webinar(
  p_proposal_id uuid,
  p_scheduled_at timestamptz,
  p_chapter_code text,
  p_duration_min integer DEFAULT 60,
  p_initiative_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_proposal record;
  v_webinar_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  SELECT * INTO v_proposal FROM public.webinar_proposals WHERE id = p_proposal_id;
  IF v_proposal IS NULL THEN RAISE EXCEPTION 'Proposal not found: %', p_proposal_id; END IF;

  IF v_proposal.status <> 'approved' THEN
    RAISE EXCEPTION 'Cannot convert proposal in status %: must be approved', v_proposal.status;
  END IF;
  IF v_proposal.webinar_id IS NOT NULL THEN
    RAISE EXCEPTION 'Proposal already converted (webinar_id=%)', v_proposal.webinar_id;
  END IF;
  IF p_scheduled_at IS NULL THEN RAISE EXCEPTION 'scheduled_at is required'; END IF;
  IF p_chapter_code IS NULL OR length(trim(p_chapter_code)) = 0 THEN
    RAISE EXCEPTION 'chapter_code is required';
  END IF;

  INSERT INTO public.webinars (
    title, scheduled_at, duration_min, status, chapter_code,
    organizer_id, created_by, format_type, series_id, tribe_anchors, initiative_id
  )
  VALUES (
    v_proposal.proposed_title, p_scheduled_at, p_duration_min, 'planned', p_chapter_code,
    v_proposal.proposer_member_id, auth.uid(), v_proposal.format_type,
    v_proposal.series_id,
    CASE WHEN v_proposal.proposed_by_tribe_id IS NOT NULL THEN ARRAY[v_proposal.proposed_by_tribe_id] ELSE NULL END,
    p_initiative_id
  )
  RETURNING id INTO v_webinar_id;

  UPDATE public.webinar_proposals
     SET status = 'converted_to_webinar', webinar_id = v_webinar_id
   WHERE id = p_proposal_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'convert_proposal_to_webinar', 'webinar_proposal', p_proposal_id,
    jsonb_build_object(
      'webinar_id', v_webinar_id,
      'scheduled_at', p_scheduled_at,
      'chapter_code', p_chapter_code,
      'duration_min', p_duration_min,
      'title', v_proposal.proposed_title
    ),
    jsonb_build_object('source','mcp','issue','#130')
  );

  RETURN jsonb_build_object(
    'success', true,
    'proposal_id', p_proposal_id,
    'webinar_id', v_webinar_id,
    'status', 'converted_to_webinar'
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.convert_proposal_to_webinar(uuid,timestamptz,text,integer,uuid) TO authenticated;

-- ============================================================
-- list_webinar_proposals — read view (any active member sees own; comitê sees all)
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_webinar_proposals(
  p_status_filter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_committee boolean;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      wp.id,
      wp.proposed_title,
      wp.format_type,
      wp.status,
      wp.proposed_by_tribe_id,
      wp.proposer_member_id,
      mp.name AS proposer_name,
      wp.series_id,
      COALESCE(ps.title_i18n->>'pt-BR', ps.slug) AS series_title,
      wp.quadrant_anchor,
      q.key AS quadrant_key,
      q.name_pt AS quadrant_name,
      wp.themes,
      wp.proposed_speakers,
      wp.notes,
      wp.rejection_reason,
      wp.reviewed_by,
      mr.name AS reviewer_name,
      wp.reviewed_at,
      wp.webinar_id,
      wp.created_at,
      wp.updated_at
    FROM public.webinar_proposals wp
    LEFT JOIN public.members mp ON mp.id = wp.proposer_member_id
    LEFT JOIN public.members mr ON mr.id = wp.reviewed_by
    LEFT JOIN public.publication_series ps ON ps.id = wp.series_id
    LEFT JOIN public.quadrants q ON q.id = wp.quadrant_anchor
    WHERE (p_status_filter IS NULL OR wp.status = p_status_filter)
      AND (v_is_committee OR wp.proposer_member_id = v_caller_id)
    ORDER BY wp.created_at DESC
  ) r;

  RETURN jsonb_build_object(
    'proposals', v_result,
    'count', jsonb_array_length(v_result),
    'is_committee', v_is_committee
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.list_webinar_proposals(text) TO authenticated;
