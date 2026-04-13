-- ============================================================================
-- V4 Phase 6 — Migration 4/5: CPMAI Data Migration to Initiatives
-- ADR: ADR-0009 (Config-Driven Initiative Kinds)
-- Depends on: 20260413620000_v4_phase6_custom_fields_validation.sql
-- Rollback: DROP TABLE IF EXISTS public.initiative_member_progress CASCADE;
--           DELETE FROM public.initiatives WHERE metadata->>'cpmai_legacy_course_id' IS NOT NULL;
--           -- Restore get_cpmai_course_dashboard to read from cpmai_* tables (see git history)
-- ============================================================================

-- ── 1. Generic initiative_member_progress table ─────────────────────────────
-- Replaces cpmai_progress + cpmai_mock_scores. Works for ANY initiative kind.

CREATE TABLE public.initiative_member_progress (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  initiative_id   uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  person_id       uuid NOT NULL REFERENCES public.persons(id) ON DELETE CASCADE,
  progress_type   text NOT NULL
                  CHECK (progress_type IN ('module_completion', 'mock_score', 'session_attendance', 'milestone', 'custom')),
  payload         jsonb NOT NULL DEFAULT '{}',
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                  REFERENCES public.organizations(id) ON DELETE RESTRICT
);

COMMENT ON TABLE public.initiative_member_progress IS
  'V4 Phase 6: Generic progress tracking for any initiative kind. Replaces cpmai_progress/cpmai_mock_scores (ADR-0009).';

CREATE INDEX idx_imp_initiative ON public.initiative_member_progress(initiative_id);
CREATE INDEX idx_imp_person ON public.initiative_member_progress(person_id);
CREATE INDEX idx_imp_type ON public.initiative_member_progress(progress_type);

-- RLS
ALTER TABLE public.initiative_member_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "imp_select_authenticated"
  ON public.initiative_member_progress FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "imp_org_scope"
  ON public.initiative_member_progress AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = public.auth_org());

CREATE POLICY "imp_insert_write"
  ON public.initiative_member_progress FOR INSERT TO authenticated
  WITH CHECK (
    public.can_by_member(
      (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()),
      'write'
    )
  );

-- ── 2. Migrate cpmai_courses → initiatives ──────────────────────────────────
-- 1 course → 1 initiative of kind 'study_group'

INSERT INTO public.initiatives (kind, organization_id, title, description, status, metadata)
SELECT
  'study_group',
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  c.title,
  c.description,
  CASE c.status
    WHEN 'draft' THEN 'draft'
    WHEN 'enrollment_open' THEN 'active'
    WHEN 'in_progress' THEN 'active'
    WHEN 'concluded' THEN 'concluded'
    ELSE 'draft'
  END,
  jsonb_build_object(
    'max_enrollment', c.max_capacity,
    'exam_date', c.end_date,
    'min_mock_score', c.min_mock_score,
    'min_attendance_pct', c.min_attendance_pct,
    'enrollment_deadline', c.enrollment_deadline,
    'start_date', c.start_date,
    'end_date', c.end_date,
    'cpmai_legacy_course_id', c.id,
    'domains', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', d.id,
        'domain_number', d.domain_number,
        'name_pt', d.name_pt,
        'name_en', d.name_en,
        'name_es', d.name_es,
        'weight_pct', d.weight_pct,
        'sort_order', d.sort_order
      ) ORDER BY d.domain_number), '[]'::jsonb)
      FROM cpmai_domains d WHERE d.course_id = c.id
    )
  )
FROM cpmai_courses c;

-- ── 3. Join initiative RPC (generic enrollment) ─────────────────────────────

CREATE OR REPLACE FUNCTION public.join_initiative(
  p_initiative_id uuid,
  p_motivation text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_person_id uuid;
  v_member_id uuid;
  v_initiative record;
  v_kind_row record;
  v_default_engagement_kind text;
  v_engagement_id uuid;
  v_current_count integer;
BEGIN
  -- Get caller identity
  SELECT m.id, m.person_id INTO v_member_id, v_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated or no person record' USING ERRCODE = 'P0002';
  END IF;

  -- Get initiative + kind config
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN
    RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = v_initiative.kind;

  -- Check capacity (via metadata max_enrollment if set)
  IF (v_initiative.metadata->>'max_enrollment') IS NOT NULL THEN
    SELECT count(*) INTO v_current_count
    FROM public.engagements
    WHERE initiative_id = p_initiative_id
      AND status IN ('active', 'onboarding');

    IF v_current_count >= (v_initiative.metadata->>'max_enrollment')::integer THEN
      RAISE EXCEPTION 'Initiative is at capacity' USING ERRCODE = 'P0005';
    END IF;
  END IF;

  -- Check not already enrolled
  IF EXISTS (
    SELECT 1 FROM public.engagements
    WHERE person_id = v_person_id AND initiative_id = p_initiative_id AND status IN ('active', 'onboarding')
  ) THEN
    RAISE EXCEPTION 'Already enrolled in this initiative' USING ERRCODE = 'P0009';
  END IF;

  -- Pick default engagement kind: first allowed that is NOT in required (those are for leaders)
  -- If only one allowed kind, use it
  IF array_length(v_kind_row.allowed_engagement_kinds, 1) = 1 THEN
    v_default_engagement_kind := v_kind_row.allowed_engagement_kinds[1];
  ELSE
    -- Pick first allowed that is not required (participant role)
    SELECT ek INTO v_default_engagement_kind
    FROM unnest(v_kind_row.allowed_engagement_kinds) ek
    WHERE ek != ALL(v_kind_row.required_engagement_kinds)
    LIMIT 1;
    -- Fallback to first allowed
    IF v_default_engagement_kind IS NULL THEN
      v_default_engagement_kind := v_kind_row.allowed_engagement_kinds[1];
    END IF;
  END IF;

  -- Create engagement
  INSERT INTO public.engagements (
    person_id, initiative_id, kind, role, status,
    metadata, organization_id
  ) VALUES (
    v_person_id, p_initiative_id, v_default_engagement_kind, 'participant', 'active',
    jsonb_build_object('motivation', p_motivation) || p_metadata,
    public.auth_org()
  )
  RETURNING id INTO v_engagement_id;

  RETURN v_engagement_id;
END;
$$;

COMMENT ON FUNCTION public.join_initiative(uuid, text, jsonb) IS
  'V4 Phase 6: Generic initiative enrollment — picks engagement kind from config, checks capacity';

GRANT EXECUTE ON FUNCTION public.join_initiative(uuid, text, jsonb) TO authenticated;

-- ── 4. Rewrite get_cpmai_course_dashboard to read from initiatives ──────────
-- Returns the SAME JSON shape for frontend compatibility.

CREATE OR REPLACE FUNCTION public.get_cpmai_course_dashboard(
  p_course_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_initiative_id uuid;
  v_initiative record;
  v_result jsonb;
BEGIN
  SELECT m.id, m.person_id INTO v_member_id, v_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;

  -- Resolve initiative (find study_group by legacy course id or latest)
  IF p_course_id IS NOT NULL THEN
    SELECT * INTO v_initiative FROM public.initiatives
    WHERE metadata->>'cpmai_legacy_course_id' = p_course_id::text
      AND kind = 'study_group';
  ELSE
    SELECT * INTO v_initiative FROM public.initiatives
    WHERE kind = 'study_group' AND status != 'archived'
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_initiative IS NULL THEN RETURN jsonb_build_object('error', 'No course found'); END IF;
  v_initiative_id := v_initiative.id;

  SELECT jsonb_build_object(
    'course', jsonb_build_object(
      'id', v_initiative.id,
      'title', v_initiative.title,
      'description', v_initiative.description,
      'status', v_initiative.status,
      'max_capacity', (v_initiative.metadata->>'max_enrollment')::integer,
      'enrollment_deadline', v_initiative.metadata->>'enrollment_deadline',
      'start_date', v_initiative.metadata->>'start_date',
      'end_date', v_initiative.metadata->>'end_date',
      'min_attendance_pct', (v_initiative.metadata->>'min_attendance_pct')::numeric,
      'min_mock_score', (v_initiative.metadata->>'min_mock_score')::numeric
    ),
    'domains', COALESCE(v_initiative.metadata->'domains', '[]'::jsonb),
    'my_enrollment', (
      SELECT jsonb_build_object(
        'id', e.id,
        'status', e.status,
        'enrolled_at', e.start_date,
        'completed_at', e.end_date,
        'certificate_issued_at', NULL
      )
      FROM public.engagements e
      WHERE e.initiative_id = v_initiative_id
        AND e.person_id = v_person_id
        AND e.kind IN ('study_group_participant', 'study_group_owner')
      LIMIT 1
    ),
    'my_progress', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'module_id', p.payload->>'module_id',
        'status', p.payload->>'status',
        'completed_at', p.payload->>'completed_at'
      ))
      FROM public.initiative_member_progress p
      WHERE p.initiative_id = v_initiative_id
        AND p.person_id = v_person_id
        AND p.progress_type = 'module_completion'
    ), '[]'::jsonb),
    'my_mock_scores', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'score_pct', (p.payload->>'score_pct')::numeric,
        'total_questions', (p.payload->>'total_questions')::integer,
        'correct_answers', (p.payload->>'correct_answers')::integer,
        'mock_source', p.payload->>'mock_source',
        'taken_at', p.recorded_at
      ) ORDER BY p.recorded_at DESC)
      FROM public.initiative_member_progress p
      WHERE p.initiative_id = v_initiative_id
        AND p.person_id = v_person_id
        AND p.progress_type = 'mock_score'
    ), '[]'::jsonb),
    'upcoming_sessions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ev.id,
        'title', ev.title,
        'session_type', ev.event_type,
        'scheduled_at', ev.date,
        'duration_minutes', ev.duration_minutes,
        'external_url', ev.meeting_link,
        'recording_url', NULL,
        'domain_id', NULL
      ) ORDER BY ev.date)
      FROM public.events ev
      WHERE ev.initiative_id = v_initiative_id
        AND ev.date >= now() - interval '1 day'
    ), '[]'::jsonb),
    'enrollment_count', (
      SELECT count(*)
      FROM public.engagements
      WHERE initiative_id = v_initiative_id
        AND kind IN ('study_group_participant', 'study_group_owner')
        AND status IN ('active', 'offboarded')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cpmai_course_dashboard(uuid) TO authenticated;

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
