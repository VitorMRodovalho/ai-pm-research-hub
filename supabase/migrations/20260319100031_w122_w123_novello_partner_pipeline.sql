-- ============================================================================
-- W122: Carlos Novello Recognition Seed (in get_public_impact_data)
-- W123: Partner Pipeline Management — schema changes, RPCs, data seeding
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- W123 STEP 1: ALTER TABLE partner_entities — add missing columns + expand status
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.partner_entities
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS chapter text;

-- Backfill updated_at for existing rows
UPDATE public.partner_entities SET updated_at = created_at WHERE updated_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- W123 STEP 2: Update admin_manage_partner_entity to accept new status + entity_type values
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.admin_manage_partner_entity(text, uuid, text, text, text, date, text, text, text, text);

CREATE OR REPLACE FUNCTION public.admin_manage_partner_entity(
  p_action text,
  p_id uuid DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_entity_type text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_partnership_date date DEFAULT NULL,
  p_cycle_code text DEFAULT 'cycle3-2026',
  p_contact_name text DEFAULT NULL,
  p_contact_email text DEFAULT NULL,
  p_status text DEFAULT 'active',
  p_notes text DEFAULT NULL,
  p_chapter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_is_admin boolean;
  v_designations text[];
  v_new_id uuid;
BEGIN
  SELECT operational_role, is_superadmin, designations
  INTO v_role, v_is_admin, v_designations
  FROM public.members WHERE auth_id = auth.uid();

  IF NOT (
    v_is_admin
    OR v_role IN ('manager', 'deputy_manager')
    OR v_designations && ARRAY['sponsor', 'chapter_liaison']
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  -- Validate entity_type (expanded)
  IF p_action IN ('create', 'update') AND p_entity_type IS NOT NULL THEN
    IF p_entity_type NOT IN ('academia', 'academic', 'governo', 'empresa', 'pmi_chapter', 'outro', 'community', 'research', 'association') THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_entity_type');
    END IF;
  END IF;

  -- Validate status (expanded with pipeline stages)
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
$$;

GRANT EXECUTE ON FUNCTION public.admin_manage_partner_entity(text, uuid, text, text, text, date, text, text, text, text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- W122: Update get_public_impact_data() — add recognitions array
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_public_impact_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
    'active_members', (SELECT COUNT(*) FROM members WHERE is_active = true AND current_cycle_active = true),
    'tribes', (SELECT COUNT(*) FROM tribes),
    'articles_published', (SELECT COUNT(*) FROM public_publications WHERE is_published = true),
    'articles_approved', (
      SELECT COUNT(*) FROM board_lifecycle_events WHERE action = 'curation_review' AND new_status = 'approved'
    ),
    'total_events', (SELECT COUNT(*) FROM events WHERE date >= '2026-03-01'),
    'total_attendance_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
      WHERE e.date >= '2026-03-01'
    ),
    'impact_hours', (
      SELECT COALESCE(SUM(e.duration_minutes / 60.0), 0)
      FROM attendance a JOIN events e ON e.id = a.event_id
    ),
    'webinars', (SELECT COUNT(*) FROM events WHERE type = 'webinar'),
    'ia_pilots', (SELECT COUNT(*) FROM ia_pilots WHERE status IN ('active','completed')),
    'partner_count', (SELECT COUNT(*) FROM partner_entities WHERE status = 'active'),
    'courses_count', (SELECT COUNT(*) FROM courses),
    'recent_publications', COALESCE((
      SELECT jsonb_agg(sub ORDER BY sub.publication_date DESC NULLS LAST)
      FROM (SELECT title, authors, external_platform AS platform, publication_date, external_url
            FROM public_publications WHERE is_published = true
            ORDER BY publication_date DESC NULLS LAST LIMIT 5) sub
    ), '[]'::jsonb),
    'tribes_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'quadrant_name', t.quadrant_name,
        'member_count', (SELECT COUNT(*) FROM members m WHERE m.tribe_id = t.id AND m.is_active),
        'leader_name', (SELECT name FROM members WHERE id = t.leader_member_id)
      ) ORDER BY t.id)
      FROM tribes t
    ), '[]'::jsonb),
    'chapters_summary', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'chapter', m.chapter,
        'member_count', COUNT(*),
        'sponsor', (SELECT ms.name FROM members ms WHERE ms.chapter = m.chapter AND 'sponsor' = ANY(ms.designations) AND ms.is_active LIMIT 1)
      ))
      FROM members m WHERE m.is_active AND m.chapter IS NOT NULL
      GROUP BY m.chapter
    ), '[]'::jsonb),
    'partners', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'type', entity_type, 'status', status))
      FROM partner_entities WHERE status = 'active'
    ), '[]'::jsonb),
    'recognitions', jsonb_build_array(
      jsonb_build_object(
        'title', 'Finalista — Prêmio "Carlos Novello" Voluntário do Ano',
        'organization', 'PMI LATAM Excellence Awards 2025',
        'recipient', 'Vitor Maia Rodovalho (GP)',
        'date', '2026-02-26',
        'category', 'Volunteer of the Year — LATAM Brasil',
        'description', 'Nomeado pelo PMI Goiás pelo trabalho à frente do Núcleo de IA & GP'
      )
    ),
    'timeline', jsonb_build_array(
      jsonb_build_object('year', '2024', 'title', 'Fase Piloto', 'description', 'Concepção pelo PMI-GO. Patrocínio Ivan Lourenço. Experimentação e lições aprendidas.'),
      jsonb_build_object('year', '2025.1', 'title', 'Oficialização', 'description', 'Parceria PMI-GO + PMI-CE. 7 artigos submetidos ao ProjectManagement.com. 1º Webinar.'),
      jsonb_build_object('year', '2025.2', 'title', 'Amadurecimento', 'description', 'Manual de Governança R2. 13 pesquisadores selecionados. Expansão para PMI-DF, PMI-MG, PMI-RS.'),
      jsonb_build_object('year', '2026', 'title', 'Escala', 'description', '44+ colaboradores, 8 tribos, 5 capítulos PMI. Plataforma digital própria. Processo seletivo estruturado.')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_impact_data() TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- W123: get_partner_pipeline() — pipeline data with stale alerts
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_partner_pipeline()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  -- Auth: GP/DM/superadmin + sponsors + liaisons
  SELECT id INTO v_caller_id FROM members
  WHERE auth_id = auth.uid()
  AND (is_superadmin
    OR operational_role IN ('manager','deputy_manager')
    OR 'chapter_liaison' = ANY(designations)
    OR 'sponsor' = ANY(designations));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  SELECT jsonb_build_object(
    'pipeline', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pe.id,
        'name', pe.name,
        'entity_type', pe.entity_type,
        'status', pe.status,
        'contact_name', pe.contact_name,
        'contact_email', pe.contact_email,
        'chapter', pe.chapter,
        'partnership_date', pe.partnership_date,
        'notes', pe.notes,
        'days_in_stage', EXTRACT(DAY FROM now() - COALESCE(pe.updated_at, pe.created_at))::int,
        'updated_at', COALESCE(pe.updated_at, pe.created_at)
      ) ORDER BY
        CASE pe.status
          WHEN 'negotiation' THEN 1
          WHEN 'contact' THEN 2
          WHEN 'prospect' THEN 3
          WHEN 'active' THEN 4
          WHEN 'inactive' THEN 5
          WHEN 'churned' THEN 6
        END, pe.updated_at DESC)
      FROM partner_entities pe
    ), '[]'::jsonb),
    'by_status', COALESCE((
      SELECT jsonb_object_agg(status, cnt)
      FROM (SELECT status, COUNT(*)::int as cnt FROM partner_entities GROUP BY status) sub
    ), '{}'::jsonb),
    'by_type', COALESCE((
      SELECT jsonb_object_agg(entity_type, cnt)
      FROM (SELECT entity_type, COUNT(*)::int as cnt FROM partner_entities GROUP BY entity_type) sub
    ), '{}'::jsonb),
    'total', (SELECT COUNT(*)::int FROM partner_entities),
    'active', (SELECT COUNT(*)::int FROM partner_entities WHERE status = 'active'),
    'stale', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pe.id, 'name', pe.name, 'status', pe.status,
        'days_stale', EXTRACT(DAY FROM now() - COALESCE(pe.updated_at, pe.created_at))::int
      ))
      FROM partner_entities pe
      WHERE pe.status IN ('prospect','contact','negotiation')
      AND COALESCE(pe.updated_at, pe.created_at) < now() - interval '30 days'
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_pipeline() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- W123: admin_update_partner_status() — forward-only pipeline transitions
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_update_partner_status(
  p_partner_id uuid,
  p_new_status text,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_current_status text;
  v_current_notes text;
  v_status_order jsonb := '{"prospect":1,"contact":2,"negotiation":3,"active":4,"inactive":5,"churned":6}'::jsonb;
  v_current_rank int;
  v_new_rank int;
BEGIN
  -- Auth: GP/DM/superadmin + sponsors + liaisons
  SELECT id INTO v_caller_id FROM members
  WHERE auth_id = auth.uid()
  AND (is_superadmin
    OR operational_role IN ('manager','deputy_manager')
    OR 'chapter_liaison' = ANY(designations)
    OR 'sponsor' = ANY(designations));
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;

  -- Get current status
  SELECT status, notes INTO v_current_status, v_current_notes
  FROM partner_entities WHERE id = p_partner_id;

  IF v_current_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'partner_not_found');
  END IF;

  -- Validate new status
  IF p_new_status NOT IN ('prospect','contact','negotiation','active','inactive','churned') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_status');
  END IF;

  -- Forward-only check (except: any status can go to inactive/churned)
  v_current_rank := (v_status_order->>v_current_status)::int;
  v_new_rank := (v_status_order->>p_new_status)::int;

  IF p_new_status NOT IN ('inactive', 'churned') AND v_new_rank <= v_current_rank THEN
    RETURN jsonb_build_object('success', false, 'error', 'backward_transition_blocked',
      'detail', 'Cannot move from ' || v_current_status || ' to ' || p_new_status);
  END IF;

  -- Update status + append notes with timestamp
  UPDATE partner_entities SET
    status = p_new_status,
    notes = CASE
      WHEN p_notes IS NOT NULL THEN
        COALESCE(v_current_notes || E'\n', '') || to_char(now(), 'YYYY-MM-DD') || ': [' || v_current_status || ' → ' || p_new_status || '] ' || p_notes
      ELSE
        COALESCE(v_current_notes || E'\n', '') || to_char(now(), 'YYYY-MM-DD') || ': Status alterado de ' || v_current_status || ' para ' || p_new_status
      END,
    updated_at = now(),
    partnership_date = CASE WHEN p_new_status = 'active' AND partnership_date IS NULL THEN CURRENT_DATE ELSE partnership_date END
  WHERE id = p_partner_id;

  RETURN jsonb_build_object('success', true, 'old_status', v_current_status, 'new_status', p_new_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_partner_status(uuid, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- W123: Seed missing partners
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.partner_entities (name, entity_type, status, contact_name, contact_email, notes, chapter, partnership_date, updated_at)
VALUES ('PM AI Revolution', 'community', 'contact',
  'Sueli Barroso / Ricardo Vargas / Antonio Nieto-Rodriguez',
  'info@pmairevolution.com',
  '2026-02-11: Ambassador application submitted. 2026-02-13: Sueli confirmed forwarded to AIPM team. 2026-03-14: Follow-up sent.',
  NULL, CURRENT_DATE, now())
ON CONFLICT DO NOTHING;

INSERT INTO public.partner_entities (name, entity_type, status, contact_name, contact_email, chapter, notes, partnership_date, updated_at)
VALUES
  ('IFG — Instituto Federal de Goiás', 'academic', 'prospect', 'Prof. Sirlon Diniz', 'sirlon.carvalho@ifg.edu.br', 'PMI-GO', 'Contato via aplicação Ambassador', CURRENT_DATE, now()),
  ('FioCruz', 'research', 'prospect', NULL, NULL, NULL, 'Mencionado na aplicação Ambassador como parceria em negociação', CURRENT_DATE, now()),
  ('AI.Brasil', 'association', 'prospect', NULL, NULL, NULL, 'Associação brasileira de IA', CURRENT_DATE, now()),
  ('CEIA-UFG', 'academic', 'prospect', NULL, NULL, 'PMI-GO', 'Centro de Excelência em IA da UFG', CURRENT_DATE, now()),
  ('PMO-GA Community', 'community', 'prospect', NULL, NULL, NULL, 'Comunidade PMO Global Alliance', CURRENT_DATE, now())
ON CONFLICT DO NOTHING;
