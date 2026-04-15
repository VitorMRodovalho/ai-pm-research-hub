-- ============================================================================
-- CR-051: Initiative Page Foundation
-- Creates committee infrastructure: kinds, initiatives, boards linkage,
-- engagement seeds, and RPCs for /initiative/[id] page.
--
-- ROLLBACK:
--   DELETE FROM engagements WHERE metadata->>'source' = 'committee_seed';
--   UPDATE project_boards SET initiative_id = NULL WHERE id IN (
--     'a6b78238-11aa-476a-b7e2-a674d224fd79',
--     '86a8959c-ddd0-4a7f-b45f-bf828230f949',
--     '75df916d-cc19-4d42-a58d-6017eb710a24');
--   DELETE FROM initiatives WHERE kind = 'committee';
--   DELETE FROM engagement_kind_permissions WHERE kind IN ('committee_member','committee_coordinator');
--   DELETE FROM engagement_kinds WHERE slug IN ('committee_member','committee_coordinator');
--   DELETE FROM initiative_kinds WHERE slug = 'committee';
--   DROP FUNCTION IF EXISTS get_initiative_detail(uuid);
--   DROP FUNCTION IF EXISTS manage_initiative_engagement(uuid, uuid, text, text, text);
-- ============================================================================

-- ─── 1a. New engagement_kinds ───────────────────────────────────────────────

INSERT INTO engagement_kinds (
  slug, display_name, description, legal_basis,
  requires_agreement, requires_vep, requires_selection,
  initiative_kinds_allowed, is_initiative_scoped, organization_id
) VALUES
  ('committee_member', 'Membro de Comite',
   'Participante de comite operacional (comunicacao, publicacoes, curadoria). Sem processo seletivo ou termo formal.',
   'legitimate_interest', false, false, false,
   ARRAY['committee'], true, '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_coordinator', 'Coordenador de Comite',
   'Membro com papel de coordenacao em comite operacional (curador, co-GP, liaison). Acesso de supervisao.',
   'legitimate_interest', false, false, false,
   ARRAY['committee'], true, '2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (slug) DO NOTHING;

-- ─── 1b. New initiative_kind: committee ─────────────────────────────────────

INSERT INTO initiative_kinds (
  slug, display_name, description, icon,
  has_board, has_meeting_notes, has_deliverables, has_attendance, has_certificate,
  allowed_engagement_kinds, required_engagement_kinds,
  lifecycle_states, default_duration_days, max_concurrent_per_org, organization_id
) VALUES (
  'committee', 'Comite / Frente Operacional',
  'Grupo permanente de trabalho operacional (comunicacao, publicacoes, curadoria).',
  'users-round',
  true, true, true, false, false,
  ARRAY['committee_member', 'committee_coordinator', 'observer', 'guest'],
  ARRAY['committee_member'],
  ARRAY['draft','active','concluded','archived'],
  NULL, 10, '2b4f58ab-7c45-4170-8718-b77ee69ff906'
) ON CONFLICT (slug) DO NOTHING;

-- ─── 1c. canV4 permissions for committee roles ──────────────────────────────

INSERT INTO engagement_kind_permissions (kind, role, action, scope, description, organization_id) VALUES
  -- committee_member/leader: full management of own committee
  ('committee_member', 'leader', 'write', 'initiative', 'Committee leader can create/edit', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_member', 'leader', 'write_board', 'initiative', 'Committee leader can manage board', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_member', 'leader', 'manage_member', 'initiative', 'Committee leader can add/remove members', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_member', 'leader', 'manage_event', 'initiative', 'Committee leader can manage events', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_member', 'leader', 'view_pii', 'initiative', 'Committee leader can see contacts', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  -- committee_member/participant: board access
  ('committee_member', 'participant', 'write_board', 'initiative', 'Committee member can use board', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  -- committee_coordinator: oversight + board access
  ('committee_coordinator', 'coordinator', 'write', 'initiative', 'Coordinator can create/edit', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_coordinator', 'coordinator', 'write_board', 'initiative', 'Coordinator can manage board', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_coordinator', 'coordinator', 'view_pii', 'initiative', 'Coordinator can see contacts', '2b4f58ab-7c45-4170-8718-b77ee69ff906');

-- ─── 1d. Create committee initiatives ───────────────────────────────────────

DO $seed$
DECLARE
  v_comms_id uuid;
  v_pubs_id uuid;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  -- Person IDs (validated from persons table)
  v_mayanna  uuid := 'cb6e40ad-b89d-4a6a-a3db-f8e668e74d0d';
  v_leticia  uuid := '85cdcc97-a1f8-4160-b155-84f13d6077d8';
  v_mluiza   uuid := 'a2b474bd-b6ec-45d4-a75d-ab3e29a2426d';
  v_fabricio uuid := '199b0514-6868-41fc-a1bb-a189399e94b3';
  v_roberto  uuid := '6d804770-8caa-4095-9b6a-196c525bd511';
  v_sarah    uuid := 'a1966b77-ff29-4ea9-b965-4c85a3bb17ac';
BEGIN
  -- Validate all persons exist
  IF NOT EXISTS (SELECT 1 FROM persons WHERE id = v_mayanna) THEN
    RAISE EXCEPTION 'Missing persons record for Mayanna (%)' , v_mayanna;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM persons WHERE id = v_leticia) THEN
    RAISE EXCEPTION 'Missing persons record for Leticia (%)' , v_leticia;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM persons WHERE id = v_mluiza) THEN
    RAISE EXCEPTION 'Missing persons record for Maria Luiza (%)' , v_mluiza;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM persons WHERE id = v_fabricio) THEN
    RAISE EXCEPTION 'Missing persons record for Fabricio (%)' , v_fabricio;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM persons WHERE id = v_roberto) THEN
    RAISE EXCEPTION 'Missing persons record for Roberto (%)' , v_roberto;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM persons WHERE id = v_sarah) THEN
    RAISE EXCEPTION 'Missing persons record for Sarah (%)' , v_sarah;
  END IF;

  -- Create initiatives (idempotent — check by title+kind)
  SELECT id INTO v_comms_id FROM initiatives WHERE title = 'Hub de Comunicacao' AND kind = 'committee';
  IF v_comms_id IS NULL THEN
    INSERT INTO initiatives (id, title, kind, status, description, organization_id)
    VALUES (gen_random_uuid(), 'Hub de Comunicacao', 'committee', 'active',
            'Frente de comunicacao: redes sociais, campanhas, divulgacao.', v_org_id)
    RETURNING id INTO v_comms_id;
  END IF;

  SELECT id INTO v_pubs_id FROM initiatives WHERE title = 'Publicacoes & Submissoes' AND kind = 'committee';
  IF v_pubs_id IS NULL THEN
    INSERT INTO initiatives (id, title, kind, status, description, organization_id)
    VALUES (gen_random_uuid(), 'Publicacoes & Submissoes', 'committee', 'active',
            'Curadoria e submissao de publicacoes PMI e academicas.', v_org_id)
    RETURNING id INTO v_pubs_id;
  END IF;

  RAISE NOTICE 'Comms initiative: %, Publications initiative: %', v_comms_id, v_pubs_id;

  -- ─── 1e. Link boards ───────────────────────────────────────────────────────
  UPDATE project_boards SET initiative_id = v_comms_id
    WHERE id = 'a6b78238-11aa-476a-b7e2-a674d224fd79' AND initiative_id IS NULL;

  UPDATE project_boards SET initiative_id = v_pubs_id
    WHERE id = '86a8959c-ddd0-4a7f-b45f-bf828230f949' AND initiative_id IS NULL;

  -- Link CPMAI board to existing CPMAI study_group initiative
  UPDATE project_boards SET initiative_id = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19'
    WHERE id = '75df916d-cc19-4d42-a58d-6017eb710a24' AND initiative_id IS NULL;

  -- ─── 1f. Seed engagements (idempotent — skip if active engagement exists) ──
  -- Hub de Comunicacao
  -- Mayanna = leader (comms_leader)
  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_mayanna AND initiative_id = v_comms_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_mayanna, v_comms_id, 'committee_member', 'leader', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:comms_leader"}'::jsonb, v_org_id);
  END IF;

  -- Leticia = participant (comms_member)
  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_leticia AND initiative_id = v_comms_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_leticia, v_comms_id, 'committee_member', 'participant', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:comms_member"}'::jsonb, v_org_id);
  END IF;

  -- Maria Luiza = participant (comms_member)
  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_mluiza AND initiative_id = v_comms_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_mluiza, v_comms_id, 'committee_member', 'participant', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:comms_member"}'::jsonb, v_org_id);
  END IF;

  -- Fabricio, Roberto, Sarah = coordinators (curator/co_gp/liaison oversight)
  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_fabricio AND initiative_id = v_comms_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_fabricio, v_comms_id, 'committee_coordinator', 'coordinator', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:curator,co_gp"}'::jsonb, v_org_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_roberto AND initiative_id = v_comms_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_roberto, v_comms_id, 'committee_coordinator', 'coordinator', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:curator,chapter_liaison"}'::jsonb, v_org_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_sarah AND initiative_id = v_comms_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_sarah, v_comms_id, 'committee_coordinator', 'coordinator', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:curator,founder"}'::jsonb, v_org_id);
  END IF;

  -- Publicacoes & Submissoes (same oversight team — curators handle both)
  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_fabricio AND initiative_id = v_pubs_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_fabricio, v_pubs_id, 'committee_coordinator', 'coordinator', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:curator"}'::jsonb, v_org_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_roberto AND initiative_id = v_pubs_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_roberto, v_pubs_id, 'committee_coordinator', 'coordinator', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:curator"}'::jsonb, v_org_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM engagements WHERE person_id = v_sarah AND initiative_id = v_pubs_id AND status = 'active') THEN
    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, metadata, organization_id)
    VALUES (v_sarah, v_pubs_id, 'committee_coordinator', 'coordinator', 'active', 'legitimate_interest',
            '{"source":"committee_seed","migrated_from":"designation:curator"}'::jsonb, v_org_id);
  END IF;

END $seed$;

-- ─── 1g. RPC: get_initiative_detail ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_initiative_detail(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_initiative record;
  v_kind_config jsonb;
  v_board_id uuid;
  v_leader jsonb;
  v_member_count integer;
  v_engagement_summary jsonb;
  v_user_engagement jsonb;
  v_caller_person_id uuid;
BEGIN
  -- Resolve caller's person_id
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  -- Fetch initiative
  SELECT i.id, i.title, i.kind, i.status, i.description,
         i.legacy_tribe_id, i.created_at
  INTO v_initiative
  FROM initiatives i
  WHERE i.id = p_initiative_id;

  IF v_initiative IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  -- Fetch kind config (feature flags)
  SELECT jsonb_build_object(
    'slug', ik.slug,
    'display_name', ik.display_name,
    'icon', ik.icon,
    'has_board', ik.has_board,
    'has_meeting_notes', ik.has_meeting_notes,
    'has_deliverables', ik.has_deliverables,
    'has_attendance', ik.has_attendance,
    'has_certificate', ik.has_certificate,
    'allowed_engagement_kinds', ik.allowed_engagement_kinds
  ) INTO v_kind_config
  FROM initiative_kinds ik
  WHERE ik.slug = v_initiative.kind;

  -- Fetch linked board
  SELECT pb.id INTO v_board_id
  FROM project_boards pb
  WHERE pb.initiative_id = p_initiative_id AND pb.is_active = true
  LIMIT 1;

  -- Fetch leader (engagement with role='leader')
  SELECT jsonb_build_object(
    'person_id', p.id,
    'name', COALESCE(p.name, m.name),
    'photo_url', m.photo_url,
    'role', e.role
  ) INTO v_leader
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  LEFT JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id
    AND e.status = 'active'
    AND e.role = 'leader'
  LIMIT 1;

  -- Member count
  SELECT count(*) INTO v_member_count
  FROM engagements e
  WHERE e.initiative_id = p_initiative_id AND e.status = 'active';

  -- Engagement summary (grouped by kind + role)
  SELECT coalesce(jsonb_agg(row_to_json(s)), '[]'::jsonb) INTO v_engagement_summary
  FROM (
    SELECT e.kind, e.role, count(*) as count
    FROM engagements e
    WHERE e.initiative_id = p_initiative_id AND e.status = 'active'
    GROUP BY e.kind, e.role
    ORDER BY e.kind, e.role
  ) s;

  -- Caller's own engagement (null if not a participant)
  IF v_caller_person_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'engagement_id', e.id,
      'kind', e.kind,
      'role', e.role,
      'status', e.status,
      'start_date', e.start_date
    ) INTO v_user_engagement
    FROM engagements e
    WHERE e.initiative_id = p_initiative_id
      AND e.person_id = v_caller_person_id
      AND e.status = 'active'
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'initiative', jsonb_build_object(
      'id', v_initiative.id,
      'title', v_initiative.title,
      'kind', v_initiative.kind,
      'status', v_initiative.status,
      'description', v_initiative.description,
      'legacy_tribe_id', v_initiative.legacy_tribe_id,
      'created_at', v_initiative.created_at
    ),
    'kind_config', v_kind_config,
    'board_id', v_board_id,
    'leader', v_leader,
    'member_count', v_member_count,
    'engagement_summary', v_engagement_summary,
    'user_engagement', v_user_engagement
  );
END;
$$;

-- ─── 1h. RPC: manage_initiative_engagement ──────────────────────────────────

CREATE OR REPLACE FUNCTION manage_initiative_engagement(
  p_initiative_id uuid,
  p_person_id uuid,
  p_kind text,
  p_role text DEFAULT 'participant',
  p_action text DEFAULT 'add'  -- 'add' | 'remove' | 'update_role'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_person_id uuid;
  v_initiative record;
  v_engagement record;
  v_result jsonb;
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
BEGIN
  -- Resolve caller
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Gate: must have manage_member permission for this initiative
  IF NOT can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member permission');
  END IF;

  -- Validate initiative exists
  SELECT i.id, i.kind, i.status INTO v_initiative
  FROM initiatives i WHERE i.id = p_initiative_id;

  IF v_initiative IS NULL THEN
    RETURN jsonb_build_object('error', 'Initiative not found');
  END IF;

  IF v_initiative.status NOT IN ('active', 'draft') THEN
    RETURN jsonb_build_object('error', 'Initiative is not active');
  END IF;

  -- Validate engagement_kind is allowed for this initiative_kind
  IF NOT EXISTS (
    SELECT 1 FROM engagement_kinds ek
    WHERE ek.slug = p_kind
      AND v_initiative.kind = ANY(ek.initiative_kinds_allowed)
  ) THEN
    RETURN jsonb_build_object('error',
      format('Engagement kind "%s" not allowed for initiative kind "%s"', p_kind, v_initiative.kind));
  END IF;

  IF p_action = 'add' THEN
    -- Check person exists
    IF NOT EXISTS (SELECT 1 FROM persons WHERE id = p_person_id) THEN
      RETURN jsonb_build_object('error', 'Person not found');
    END IF;

    -- Check not already engaged
    IF EXISTS (
      SELECT 1 FROM engagements e
      WHERE e.person_id = p_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active'
    ) THEN
      RETURN jsonb_build_object('error', 'Person already has active engagement in this initiative');
    END IF;

    INSERT INTO engagements (person_id, initiative_id, kind, role, status, legal_basis, granted_by, metadata, organization_id)
    VALUES (p_person_id, p_initiative_id, p_kind, p_role, 'active', 'consent',
            v_caller_person_id,
            jsonb_build_object('source', 'manage_initiative_engagement', 'added_by', v_caller_person_id::text),
            v_org_id)
    RETURNING * INTO v_engagement;

    RETURN jsonb_build_object('ok', true, 'action', 'added', 'engagement_id', v_engagement.id);

  ELSIF p_action = 'remove' THEN
    UPDATE engagements SET
      status = 'revoked',
      revoked_at = now(),
      revoked_by = v_caller_person_id,
      revoke_reason = 'Removed via manage_initiative_engagement',
      updated_at = now()
    WHERE person_id = p_person_id
      AND initiative_id = p_initiative_id
      AND status = 'active'
    RETURNING * INTO v_engagement;

    IF v_engagement IS NULL THEN
      RETURN jsonb_build_object('error', 'No active engagement found for this person');
    END IF;

    RETURN jsonb_build_object('ok', true, 'action', 'removed', 'engagement_id', v_engagement.id);

  ELSIF p_action = 'update_role' THEN
    UPDATE engagements SET
      role = p_role,
      updated_at = now()
    WHERE person_id = p_person_id
      AND initiative_id = p_initiative_id
      AND status = 'active'
    RETURNING * INTO v_engagement;

    IF v_engagement IS NULL THEN
      RETURN jsonb_build_object('error', 'No active engagement found for this person');
    END IF;

    RETURN jsonb_build_object('ok', true, 'action', 'role_updated', 'engagement_id', v_engagement.id, 'new_role', p_role);

  ELSE
    RETURN jsonb_build_object('error', format('Unknown action: %s', p_action));
  END IF;
END;
$$;

-- ─── 1i. Fix get_initiative_member_contacts for non-tribe initiatives ───────

CREATE OR REPLACE FUNCTION get_initiative_member_contacts(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_person_id uuid;
  v_can_view_pii boolean;
  v_result jsonb;
BEGIN
  -- Resolve caller
  SELECT p.id INTO v_caller_person_id
  FROM persons p WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  -- Check PII access: either org-level or initiative-level
  v_can_view_pii := can(v_caller_person_id, 'view_pii', 'initiative', p_initiative_id);

  IF NOT v_can_view_pii THEN
    RETURN '{}'::jsonb;
  END IF;

  -- Return contacts for all active engagements in this initiative
  SELECT jsonb_object_agg(
    m.id::text,
    jsonb_build_object(
      'email', m.email,
      'phone', m.phone,
      'share_whatsapp', m.share_whatsapp
    )
  ) INTO v_result
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  JOIN members m ON m.id = p.legacy_member_id
  WHERE e.initiative_id = p_initiative_id
    AND e.status = 'active';

  RETURN coalesce(v_result, '{}'::jsonb);
END;
$$;

-- ─── Notify PostgREST ───────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
