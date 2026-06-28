-- =====================================================================================
-- #806 — create_external_speaker_engagement: partner-reuse guard + initiative
-- metadata.partner_entity_id parity; admin_manage_partner_entity: 'pmi_global' enum +
-- valid-list in error; data-fix for the Detroit origin-FK residue; drop duplicate index.
--
-- Grounding (live, 2026-06-28): the FK `initiatives.origin_partner_entity_id` ALREADY
-- exists and create_external_speaker_engagement ALREADY persists it — the 2026-06-19
-- "Detroit" incident was OPERATOR error (the LIM partner UUID 8bb97295 passed for the
-- PMI Global Summit congress), faithfully persisted with no guard. Confirmed residue:
-- partner 8bb97295 is still origin-linked to 2 active initiatives (LIM + Detroit) while
-- Detroit's metadata.partner_entity_id was already backfilled to the correct a57ce406.
--
-- This migration:
--   1. DATA-FIX  : correct Detroit's origin_partner_entity_id (8bb97295 -> a57ce406).
--   2. DROP INDEX: remove the duplicate idx_initiatives_origin_partner (keep ix_*).
--   3. DROP+CREATE create_external_speaker_engagement (signature changes — new trailing
--      param p_allow_partner_reuse): fail-closed reuse guard (a partner already linked to
--      an active initiative blocks creation unless explicitly overridden — a chapter may
--      legitimately host multiple congresses) + write metadata.partner_entity_id on the
--      initiative (parity with the lead/co engagement metadata + the manually-set LIM row).
--   4. CREATE OR REPLACE admin_manage_partner_entity: add 'pmi_global' to the entity_type
--      allow-list (1 live row already uses it; its absence forced the Detroit partner to be
--      mislabelled 'association') + surface the valid values in the invalid_entity_type error.
-- =====================================================================================

-- ── 1. DATA-FIX: Detroit origin FK was the LIM partner; metadata already correct ──
UPDATE public.initiatives
SET origin_partner_entity_id = 'a57ce406-37ae-42b4-836c-91a446febaf8'
WHERE id = '0b7cbe35-5d7f-4d40-b9f5-0a8eaa486f0d'
  AND origin_partner_entity_id = '8bb97295-4e8e-4e19-98a4-37b72d3305b8';

-- ── 2. Drop the duplicate partial index (keep ix_initiatives_origin_partner) ──
DROP INDEX IF EXISTS public.idx_initiatives_origin_partner;

-- ── 3. create_external_speaker_engagement: reuse guard + metadata parity ──
DROP FUNCTION IF EXISTS public.create_external_speaker_engagement(uuid, uuid, text, uuid, text, text, jsonb, text, text, text, text, uuid);

CREATE FUNCTION public.create_external_speaker_engagement(
  p_partner_entity_id uuid,
  p_lead_person_id uuid,
  p_initiative_title text,
  p_co_person_id uuid DEFAULT NULL::uuid,
  p_initiative_kind text DEFAULT 'congress'::text,
  p_initiative_description text DEFAULT NULL::text,
  p_deadlines jsonb DEFAULT '[]'::jsonb,
  p_whatsapp_url text DEFAULT NULL::text,
  p_meeting_link text DEFAULT NULL::text,
  p_drive_folder_url text DEFAULT NULL::text,
  p_board_domain_key text DEFAULT 'publications_submissions'::text,
  p_org_id uuid DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  p_allow_partner_reuse boolean DEFAULT false
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

  -- ─── #806 partner-reuse guard (fail-closed) ───
  -- One partner per active initiative is a convention, not an invariant; the 2026-06-19
  -- Detroit incident reused the LIM partner with nothing to catch it. Block reuse unless
  -- the caller explicitly overrides (a chapter may legitimately host multiple congresses).
  IF NOT p_allow_partner_reuse AND EXISTS (
    SELECT 1 FROM public.initiatives i
    WHERE i.origin_partner_entity_id = p_partner_entity_id
      AND i.status = 'active'
  ) THEN
    RETURN jsonb_build_object(
      'error', 'partner already linked to an active initiative',
      'code', 'partner_already_linked',
      'partner_entity_id', p_partner_entity_id,
      'partner_name', v_partner_name,
      'existing_initiatives', (
        SELECT jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title) ORDER BY i.title)
        FROM public.initiatives i
        WHERE i.origin_partner_entity_id = p_partner_entity_id AND i.status = 'active'
      ),
      'hint', 'pass allow_partner_reuse=true to override (one partner per event is a convention)'
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
      'created_by_person', v_caller_person_id::text,
      'partner_entity_id', p_partner_entity_id::text
    ))
  )
  RETURNING id INTO v_initiative_id;

  -- ─── Step 2: project_board (global scope) ───
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

REVOKE EXECUTE ON FUNCTION public.create_external_speaker_engagement(uuid, uuid, text, uuid, text, text, jsonb, text, text, text, text, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_external_speaker_engagement(uuid, uuid, text, uuid, text, text, jsonb, text, text, text, text, uuid, boolean) TO authenticated, service_role;

-- ── 4. admin_manage_partner_entity: add 'pmi_global' + valid-list in the error ──
CREATE OR REPLACE FUNCTION public.admin_manage_partner_entity(
  p_action text,
  p_id uuid DEFAULT NULL::uuid,
  p_name text DEFAULT NULL::text,
  p_entity_type text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_partnership_date date DEFAULT NULL::date,
  p_cycle_code text DEFAULT 'cycle3-2026'::text,
  p_contact_name text DEFAULT NULL::text,
  p_contact_email text DEFAULT NULL::text,
  p_status text DEFAULT 'active'::text,
  p_notes text DEFAULT NULL::text,
  p_chapter text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_new_id uuid;
  v_allowed_entity_types text[] := ARRAY['academia', 'academic', 'governo', 'empresa', 'pmi_chapter', 'pmi_global', 'outro', 'community', 'research', 'association'];
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'authentication_required');
  END IF;

  -- V4 gate (Opção B reuse manage_partner — same precedent as ADR-0031/0032)
  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF p_action IN ('create', 'update') AND p_entity_type IS NOT NULL THEN
    IF NOT (p_entity_type = ANY(v_allowed_entity_types)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_entity_type', 'allowed', to_jsonb(v_allowed_entity_types));
    END IF;
  END IF;
  IF p_action IN ('create', 'update') AND p_status IS NOT NULL THEN
    IF p_status NOT IN ('active', 'prospect', 'inactive', 'contact', 'negotiation', 'churned') THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_status');
    END IF;
  END IF;

  CASE p_action
    WHEN 'create' THEN
      IF p_name IS NULL OR p_entity_type IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'missing_required_fields');
      END IF;
      INSERT INTO public.partner_entities (name, entity_type, description, partnership_date, cycle_code, contact_name, contact_email, status, notes, chapter, updated_at)
      VALUES (p_name, p_entity_type, p_description, COALESCE(p_partnership_date, CURRENT_DATE), p_cycle_code, p_contact_name, p_contact_email, p_status, p_notes, p_chapter, now())
      RETURNING id INTO v_new_id;
      RETURN jsonb_build_object('success', true, 'id', v_new_id);
    WHEN 'update' THEN
      IF p_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'missing_id');
      END IF;
      UPDATE public.partner_entities SET
        name = COALESCE(p_name, name),
        entity_type = COALESCE(p_entity_type, entity_type),
        description = COALESCE(p_description, description),
        partnership_date = COALESCE(p_partnership_date, partnership_date),
        cycle_code = COALESCE(p_cycle_code, cycle_code),
        contact_name = COALESCE(p_contact_name, contact_name),
        contact_email = COALESCE(p_contact_email, contact_email),
        status = COALESCE(p_status, status),
        notes = COALESCE(p_notes, notes),
        chapter = COALESCE(p_chapter, chapter),
        updated_at = now()
      WHERE id = p_id;
      RETURN jsonb_build_object('success', true);
    WHEN 'delete' THEN
      IF p_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'missing_id');
      END IF;
      DELETE FROM public.partner_entities WHERE id = p_id;
      RETURN jsonb_build_object('success', true);
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'invalid_action');
  END CASE;
END;
$function$;

NOTIFY pgrst, 'reload schema';
