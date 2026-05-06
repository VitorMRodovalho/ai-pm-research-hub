-- p95 #97 W3 G4: orchestrate Partnership→Initiative journey atomically
-- ====================================================================
-- Closes #97 W3 G4: replaces the manual SQL playbook used in W1 (LATAM LIM 2026)
-- with a single RPC that creates the entire tree atomically:
--
--   partner_entity (existing) →
--     initiative (kind=congress, origin_partner_entity_id=partner)
--     project_board (board_scope=global, domain_key=publications_submissions)
--     speaker engagements (lead + optional co; metadata.presenter_role per G2)
--     board_items (1 per deadline; source_type=external_partner per G3)
--     partner_interaction (type=initiative_created)
--     partner_entities.last_interaction_at update
--
-- Auth: caller must have manage_partner OR manage_member at organization scope.
-- Both are admin-class permissions appropriate for a Partnership→Initiative trigger.
--
-- Validations:
--   - partner_entity exists in target org
--   - lead_person exists; co_person (if any) exists and differs from lead
--   - initiative_kind allows speaker engagements (research_tribe|study_group|congress|workshop)
--   - initiative_title not empty
--
-- All work is wrapped in implicit transaction (plpgsql RPC) — any failure rolls back
-- the entire tree. No partial state.
--
-- Speaker conventions (matching W1 LATAM LIM precedent):
--   role='lead_presenter' + metadata.presenter_role='lead'
--   role='co_presenter' + metadata.presenter_role='co'
--
-- p_deadlines jsonb shape: array of objects with keys:
--   { "title": text, "due_date": YYYY-MM-DD, "baseline_date"?: YYYY-MM-DD,
--     "description"?: text, "status"?: text (default todo),
--     "tags"?: [text], "is_portfolio_item"?: bool }
--
-- Returns jsonb with all created IDs + counts. Caller can chain follow-ups.

CREATE OR REPLACE FUNCTION public.create_external_speaker_engagement(
  p_partner_entity_id uuid,
  p_lead_person_id uuid,
  p_initiative_title text,
  p_co_person_id uuid DEFAULT NULL,
  p_initiative_kind text DEFAULT 'congress',
  p_initiative_description text DEFAULT NULL,
  p_deadlines jsonb DEFAULT '[]'::jsonb,
  p_whatsapp_url text DEFAULT NULL,
  p_meeting_link text DEFAULT NULL,
  p_drive_folder_url text DEFAULT NULL,
  p_board_domain_key text DEFAULT 'publications_submissions',
  p_org_id uuid DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_caller_member_id uuid;
  v_initiative_id uuid;
  v_board_id uuid;
  v_lead_engagement_id uuid;
  v_co_engagement_id uuid;
  v_interaction_id uuid;
  v_board_items_count int := 0;
  v_deadline jsonb;
  v_partner_name text;
  v_lead_exists boolean;
  v_co_exists boolean;
  v_position int := 1;
BEGIN
  -- ─── Auth resolution ───
  SELECT p.id INTO v_caller_person_id
  FROM public.persons p WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  -- v_caller_member_id may be NULL if caller is auth-only (no member record);
  -- partner_interactions.actor_member_id and board_items.created_by accept NULL.

  -- ─── Authorization ───
  IF NOT (
    public.can(v_caller_person_id, 'manage_partner', 'organization', p_org_id)
    OR public.can(v_caller_person_id, 'manage_member', 'organization', p_org_id)
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Unauthorized: requires manage_partner or manage_member at organization scope'
    );
  END IF;

  -- ─── Validate inputs ───
  IF p_initiative_title IS NULL OR length(trim(p_initiative_title)) = 0 THEN
    RETURN jsonb_build_object('error', 'initiative_title is required');
  END IF;

  SELECT pe.name INTO v_partner_name
  FROM public.partner_entities pe
  WHERE pe.id = p_partner_entity_id AND pe.organization_id = p_org_id;

  IF v_partner_name IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'partner_entity not found in this organization',
      'partner_entity_id', p_partner_entity_id
    );
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.persons WHERE id = p_lead_person_id) INTO v_lead_exists;
  IF NOT v_lead_exists THEN
    RETURN jsonb_build_object('error', 'lead_person not found', 'lead_person_id', p_lead_person_id);
  END IF;

  IF p_co_person_id IS NOT NULL THEN
    IF p_co_person_id = p_lead_person_id THEN
      RETURN jsonb_build_object('error', 'co_person must differ from lead_person');
    END IF;
    SELECT EXISTS(SELECT 1 FROM public.persons WHERE id = p_co_person_id) INTO v_co_exists;
    IF NOT v_co_exists THEN
      RETURN jsonb_build_object('error', 'co_person not found', 'co_person_id', p_co_person_id);
    END IF;
  END IF;

  -- speaker kind must be allowed for this initiative kind (FK + matrix check)
  IF NOT EXISTS (
    SELECT 1 FROM public.engagement_kinds
    WHERE slug = 'speaker'
      AND p_initiative_kind = ANY(initiative_kinds_allowed)
  ) THEN
    RETURN jsonb_build_object(
      'error', format('speaker engagements not allowed for initiative_kind "%s"', p_initiative_kind),
      'hint', 'Allowed kinds: research_tribe, study_group, congress, workshop'
    );
  END IF;

  -- ─── Step 1: initiative ───
  INSERT INTO public.initiatives (
    kind, organization_id, title, description, status, origin_partner_entity_id, metadata
  )
  VALUES (
    p_initiative_kind,
    p_org_id,
    p_initiative_title,
    p_initiative_description,
    'active',
    p_partner_entity_id,
    jsonb_strip_nulls(jsonb_build_object(
      'whatsapp_url', p_whatsapp_url,
      'meeting_link', p_meeting_link,
      'drive_folder_url', p_drive_folder_url,
      'source', 'create_external_speaker_engagement',
      'created_by_person', v_caller_person_id::text
    ))
  )
  RETURNING id INTO v_initiative_id;

  -- ─── Step 2: project_board (global scope per enforce_project_board_taxonomy
  --             — congress has no legacy_tribe_id) ───
  INSERT INTO public.project_boards (
    board_name, source, board_scope, domain_key, initiative_id, organization_id, created_by
  )
  VALUES (
    p_initiative_title || ' — Milestones',
    'manual',
    'global',
    p_board_domain_key,
    v_initiative_id,
    p_org_id,
    v_caller_member_id
  )
  RETURNING id INTO v_board_id;

  -- ─── Step 3: lead speaker engagement ───
  INSERT INTO public.engagements (
    person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id
  )
  VALUES (
    p_lead_person_id, v_initiative_id, 'speaker', 'lead_presenter', 'active', 'consent',
    v_caller_person_id,
    jsonb_build_object(
      'presenter_role', 'lead',
      'source', 'create_external_speaker_engagement',
      'partner_entity_id', p_partner_entity_id::text
    ),
    p_org_id
  )
  RETURNING id INTO v_lead_engagement_id;

  -- ─── Step 4: co speaker engagement (optional) ───
  IF p_co_person_id IS NOT NULL THEN
    INSERT INTO public.engagements (
      person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id
    )
    VALUES (
      p_co_person_id, v_initiative_id, 'speaker', 'co_presenter', 'active', 'consent',
      v_caller_person_id,
      jsonb_build_object(
        'presenter_role', 'co',
        'source', 'create_external_speaker_engagement',
        'partner_entity_id', p_partner_entity_id::text
      ),
      p_org_id
    )
    RETURNING id INTO v_co_engagement_id;
  END IF;

  -- ─── Step 5: board_items from p_deadlines ───
  IF p_deadlines IS NOT NULL AND jsonb_typeof(p_deadlines) = 'array'
     AND jsonb_array_length(p_deadlines) > 0 THEN
    FOR v_deadline IN SELECT * FROM jsonb_array_elements(p_deadlines)
    LOOP
      IF v_deadline ->> 'title' IS NULL THEN
        RAISE EXCEPTION 'deadlines[%].title is required', v_position - 1;
      END IF;
      IF v_deadline ->> 'due_date' IS NULL THEN
        RAISE EXCEPTION 'deadlines[%].due_date is required (YYYY-MM-DD)', v_position - 1;
      END IF;

      INSERT INTO public.board_items (
        board_id, title, description, status, due_date, baseline_date,
        tags, source_type, source_partner_id, is_portfolio_item, position,
        organization_id, created_by
      )
      VALUES (
        v_board_id,
        v_deadline ->> 'title',
        v_deadline ->> 'description',
        COALESCE(v_deadline ->> 'status', 'todo'),
        (v_deadline ->> 'due_date')::date,
        COALESCE((v_deadline ->> 'baseline_date')::date, (v_deadline ->> 'due_date')::date),
        COALESCE(
          ARRAY(SELECT jsonb_array_elements_text(v_deadline -> 'tags')),
          '{}'::text[]
        ),
        'external_partner',
        p_partner_entity_id,
        COALESCE((v_deadline ->> 'is_portfolio_item')::boolean, false),
        v_position,
        p_org_id,
        v_caller_member_id
      );
      v_board_items_count := v_board_items_count + 1;
      v_position := v_position + 1;
    END LOOP;
  END IF;

  -- ─── Step 6: partner_interaction log (type='note' per CHECK constraint) ───
  -- partner_interactions.interaction_type CHECK = ANY(email|whatsapp|linkedin|call|meeting|note|status_change)
  -- Use 'note' with summary prefix "Initiative created" to preserve semantic intent.
  INSERT INTO public.partner_interactions (
    partner_id, interaction_type, summary, details, actor_member_id
  )
  VALUES (
    p_partner_entity_id,
    'note',
    format('Initiative created: "%s"', p_initiative_title),
    format(
      'initiative_id=%s; kind=%s; lead_person_id=%s%s; board_items=%s; via=create_external_speaker_engagement',
      v_initiative_id::text,
      p_initiative_kind,
      p_lead_person_id::text,
      CASE WHEN p_co_person_id IS NOT NULL THEN '; co_person_id=' || p_co_person_id::text ELSE '' END,
      v_board_items_count::text
    ),
    v_caller_member_id
  )
  RETURNING id INTO v_interaction_id;

  -- ─── Step 7: bump partner last_interaction_at ───
  UPDATE public.partner_entities
  SET last_interaction_at = now(), updated_at = now()
  WHERE id = p_partner_entity_id;

  -- ─── Return summary ───
  RETURN jsonb_build_object(
    'ok', true,
    'initiative_id', v_initiative_id,
    'board_id', v_board_id,
    'lead_engagement_id', v_lead_engagement_id,
    'co_engagement_id', v_co_engagement_id,
    'partner_interaction_id', v_interaction_id,
    'board_items_count', v_board_items_count,
    'partner_name', v_partner_name
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_external_speaker_engagement(uuid, uuid, text, uuid, text, text, jsonb, text, text, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_external_speaker_engagement(uuid, uuid, text, uuid, text, text, jsonb, text, text, text, text, uuid) TO authenticated;

COMMENT ON FUNCTION public.create_external_speaker_engagement IS
  'p95 #97 W3 G4: orchestrates Partnership→Initiative journey atomically. Creates initiative (origin_partner_entity_id linked per G1) + global project_board + speaker engagements with metadata.presenter_role per G2 + board_items with source_type=external_partner per G3 + partner_interaction log. Auth: manage_partner OR manage_member at organization scope. All work in single transaction — any failure rolls back the entire tree. Returns IDs of all created entities. p_deadlines shape: [{title, due_date, baseline_date?, description?, status?, tags?, is_portfolio_item?}].';

NOTIFY pgrst, 'reload schema';
