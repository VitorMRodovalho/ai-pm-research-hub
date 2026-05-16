-- p172 #5 — Engagement seed templates + onboarding RPC
--
-- P162 backlog #5 — ADR-0080 mencionou PMO capítulo affected mas não há
-- template canônico pra criar engagements no onboarding. Hoje: 26 INSERT
-- INTO engagements diferentes em migrations (one-off seeds pra pessoas
-- específicas). Drift garantido quando Núcleo expandir (PMI-CE, PMI-GO).
--
-- Solução: catalog DB-driven (config-not-code ADR-0009) com 12 templates
-- canônicos + RPC idempotent.
--
-- Templates seedados:
-- 1. researcher       — default volunteer onboarding (27 active hoje)
-- 2. tribe_leader     — single-tribe leader (7 active)
-- 3. co_leader        — multi-leader p172 #21
-- 4. manager          — chapter GP (15 actions)
-- 5. deputy_manager   — chapter co-GP (15 actions)
-- 6. co_gp            — founder co-manager (15 actions)
-- 7. comms_leader     — communications lead (6 actions)
-- 8. sponsor          — chapter sponsor (4 actions)
-- 9. ambassador       — chapter ambassador
-- 10. chapter_liaison — PMI chapter liaison (4 actions)
-- 11. chapter_board_member — PMI board observer (2 actions)
-- 12. observer        — read-only pre-volunteer (no agreement signed)
--
-- Docs: docs/reference/ENGAGEMENT_SEED_TEMPLATES.md
--
-- Rollback:
--   DROP FUNCTION public.seed_member_engagement_by_role(uuid, text, uuid);
--   DROP TABLE public.engagement_seed_templates;

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 1 — Table + RLS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.engagement_seed_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL,
  display_name_i18n jsonb NOT NULL,
  description_i18n jsonb,
  engagements jsonb NOT NULL,  -- array of {kind, role, scope}
  active boolean NOT NULL DEFAULT true,
  organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT engagement_seed_templates_slug_org_unique
    UNIQUE (organization_id, slug)
);

COMMENT ON TABLE public.engagement_seed_templates IS
  'p172 #5 — Catalog canônico de templates de engagement para onboarding. organization_id NULL = template global (aplica a todas orgs). Per-org override possível (same slug + org_id non-null). ADR-0009 config-not-code.';

COMMENT ON COLUMN public.engagement_seed_templates.engagements IS
  'jsonb array of {kind, role, scope}. scope IN (initiative, organization). RPC seed_member_engagement_by_role consome para INSERT em engagements table.';

ALTER TABLE public.engagement_seed_templates ENABLE ROW LEVEL SECURITY;

-- Read: any authenticated (templates are public catalog)
CREATE POLICY engagement_seed_templates_read_auth ON public.engagement_seed_templates
  FOR SELECT TO authenticated
  USING (organization_id IS NULL OR organization_id = public.auth_org());

-- Write: manage_platform only (catalog mutations rare + risky)
CREATE POLICY engagement_seed_templates_write_manage_platform ON public.engagement_seed_templates
  FOR ALL TO authenticated
  USING (public.rls_can('manage_platform'))
  WITH CHECK (public.rls_can('manage_platform'));

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 2 — Seed 12 canonical templates (organization_id NULL = global)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.engagement_seed_templates (slug, display_name_i18n, description_i18n, engagements, organization_id)
VALUES
  ('researcher',
   '{"pt-BR":"Pesquisador (default volunteer)","en-US":"Researcher (default volunteer)","es-LATAM":"Investigador (voluntario default)"}'::jsonb,
   '{"pt-BR":"Member aprovado no VEP/selection sem cargo específico. 27 active hoje.","en-US":"VEP/selection-approved member without specific role. 27 active today."}'::jsonb,
   '[{"kind":"volunteer","role":"researcher","scope":"initiative"}]'::jsonb,
   NULL),
  ('tribe_leader',
   '{"pt-BR":"Líder de Tribo (single)","en-US":"Tribe Leader (single)","es-LATAM":"Líder de Tribu"}'::jsonb,
   '{"pt-BR":"Líder responsável por 1 iniciativa. 7 actions: award_champion + manage_board_admin + manage_event + sign_chain_leader + view_pii + write + write_board.","en-US":"Leader of 1 initiative. 7 V4 actions."}'::jsonb,
   '[{"kind":"volunteer","role":"leader","scope":"initiative"}]'::jsonb,
   NULL),
  ('co_leader',
   '{"pt-BR":"Co-líder de Tribo","en-US":"Tribe Co-Leader","es-LATAM":"Co-líder de Tribu"}'::jsonb,
   '{"pt-BR":"Co-líder paralelo ao leader principal. Recebe digest semanal (p172 #21).","en-US":"Parallel co-leader. Receives weekly digest."}'::jsonb,
   '[{"kind":"volunteer","role":"co_leader","scope":"initiative"}]'::jsonb,
   NULL),
  ('manager',
   '{"pt-BR":"GP do Capítulo (Manager)","en-US":"Chapter Manager (GP)","es-LATAM":"Gerente del Capítulo"}'::jsonb,
   '{"pt-BR":"Gerente do programa. Org-wide authority (15 actions).","en-US":"Program manager. Org-wide authority (15 V4 actions)."}'::jsonb,
   '[{"kind":"volunteer","role":"manager","scope":"organization"}]'::jsonb,
   NULL),
  ('deputy_manager',
   '{"pt-BR":"Co-GP / Deputy Manager","en-US":"Deputy Manager","es-LATAM":"Co-Gerente"}'::jsonb,
   '{"pt-BR":"Vice-gerente. Mesmas 15 actions que manager.","en-US":"Vice-manager. Same 15 V4 actions as manager."}'::jsonb,
   '[{"kind":"volunteer","role":"deputy_manager","scope":"organization"}]'::jsonb,
   NULL),
  ('co_gp',
   '{"pt-BR":"Founder co-GP","en-US":"Founder co-GP","es-LATAM":"Co-GP Fundador"}'::jsonb,
   '{"pt-BR":"Founder com gestão (Fabricio). 15 actions.","en-US":"Founder with management role (Fabricio). 15 V4 actions."}'::jsonb,
   '[{"kind":"volunteer","role":"co_gp","scope":"organization"}]'::jsonb,
   NULL),
  ('comms_leader',
   '{"pt-BR":"Líder de Comunicações","en-US":"Communications Lead","es-LATAM":"Líder de Comunicaciones"}'::jsonb,
   '{"pt-BR":"Líder de comms. 6 actions: award_champion + manage_comms + manage_event + sign_chain_leader + write + write_board.","en-US":"Communications lead. 6 V4 actions."}'::jsonb,
   '[{"kind":"volunteer","role":"comms_leader","scope":"organization"}]'::jsonb,
   NULL),
  ('sponsor',
   '{"pt-BR":"Sponsor do Capítulo","en-US":"Chapter Sponsor","es-LATAM":"Patrocinador del Capítulo"}'::jsonb,
   '{"pt-BR":"Patrocinador. 4 actions: manage_finance + manage_partner + view_chapter_dashboards + view_internal_analytics.","en-US":"Sponsor. 4 V4 actions."}'::jsonb,
   '[{"kind":"sponsor","role":"sponsor","scope":"organization"}]'::jsonb,
   NULL),
  ('ambassador',
   '{"pt-BR":"Embaixador do Capítulo","en-US":"Chapter Ambassador","es-LATAM":"Embajador del Capítulo"}'::jsonb,
   '{"pt-BR":"Embaixador. Founders frequentemente têm este engagement (Vitor, Fabricio).","en-US":"Ambassador. Founders often hold this engagement."}'::jsonb,
   '[{"kind":"ambassador","role":"ambassador","scope":"organization"}]'::jsonb,
   NULL),
  ('chapter_liaison',
   '{"pt-BR":"PMI Chapter Liaison","en-US":"PMI Chapter Liaison","es-LATAM":"Enlace PMI Chapter"}'::jsonb,
   '{"pt-BR":"Liaison com PMI Latam/Brasil/etc. 4 actions: manage_partner + participate_in_governance_review + view_chapter_dashboards + view_internal_analytics.","en-US":"PMI chapter liaison. 4 V4 actions."}'::jsonb,
   '[{"kind":"chapter_board","role":"liaison","scope":"organization"}]'::jsonb,
   NULL),
  ('chapter_board_member',
   '{"pt-BR":"PMI Board Observer","en-US":"PMI Board Observer","es-LATAM":"Observador del Board PMI"}'::jsonb,
   '{"pt-BR":"Observer não-votante do PMI chapter board. 2 actions: view_chapter_dashboards + view_pii.","en-US":"Non-voting observer of PMI chapter board. 2 V4 actions."}'::jsonb,
   '[{"kind":"chapter_board","role":"board_member","scope":"organization"}]'::jsonb,
   NULL),
  ('observer',
   '{"pt-BR":"Observer (pré-volunteer)","en-US":"Observer (pre-volunteer)","es-LATAM":"Observador (pre-voluntario)"}'::jsonb,
   '{"pt-BR":"Pessoa em discovery sem volunteer agreement assinado. Read-only.","en-US":"Person in discovery without signed volunteer agreement. Read-only."}'::jsonb,
   '[{"kind":"observer","role":"observer","scope":"organization"}]'::jsonb,
   NULL)
ON CONFLICT (organization_id, slug) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 3 — RPC seed_member_engagement_by_role (idempotent, validated)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.seed_member_engagement_by_role(
  p_person_id uuid,
  p_template_slug text,
  p_initiative_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_person_id uuid;
  v_caller_org uuid;
  v_target_org uuid;
  v_template engagement_seed_templates%ROWTYPE;
  v_engagement_spec jsonb;
  v_kind text;
  v_role text;
  v_scope text;
  v_target_initiative_id uuid;
  v_new_id uuid;
  v_created_ids uuid[] := ARRAY[]::uuid[];
  v_skipped_count int := 0;
  v_invalid_kinds_roles text[] := ARRAY[]::text[];
BEGIN
  -- Auth: caller manage_member
  SELECT id, person_id, organization_id INTO v_caller_id, v_caller_person_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'unauthorized', 'detail', 'requires manage_member');
  END IF;

  -- Validate target person same-org
  SELECT m.organization_id INTO v_target_org
  FROM public.members m WHERE m.person_id = p_person_id;
  IF v_target_org IS NULL THEN
    -- Try persons table directly (member may not exist yet but person can)
    SELECT organization_id INTO v_target_org
    FROM public.persons WHERE id = p_person_id;
  END IF;
  IF v_target_org IS NULL THEN
    RETURN jsonb_build_object('error', 'person_not_found');
  END IF;
  IF v_target_org != v_caller_org THEN
    RETURN jsonb_build_object('error', 'person_not_in_caller_org');
  END IF;

  -- Resolve template (per-org override prefer global)
  SELECT * INTO v_template
  FROM public.engagement_seed_templates t
  WHERE t.slug = p_template_slug
    AND t.active = true
    AND (t.organization_id = v_caller_org OR t.organization_id IS NULL)
  ORDER BY t.organization_id NULLS LAST  -- per-org first
  LIMIT 1;

  IF v_template.id IS NULL THEN
    RETURN jsonb_build_object('error', 'template_not_found', 'detail', 'no active template with slug: ' || p_template_slug);
  END IF;

  -- Iterate template engagements
  FOR v_engagement_spec IN SELECT * FROM jsonb_array_elements(v_template.engagements)
  LOOP
    v_kind := v_engagement_spec->>'kind';
    v_role := v_engagement_spec->>'role';
    v_scope := v_engagement_spec->>'scope';

    -- Validate scope + initiative_id alignment
    IF v_scope = 'initiative' AND p_initiative_id IS NULL THEN
      RETURN jsonb_build_object(
        'error', 'initiative_id_required',
        'detail', format('template item kind=%s role=%s scope=initiative requires p_initiative_id', v_kind, v_role)
      );
    END IF;

    v_target_initiative_id := CASE
      WHEN v_scope = 'initiative' THEN p_initiative_id
      ELSE NULL  -- organization-scope: initiative_id NULL
    END;

    -- Validate kind+role combination has permissions seeded
    IF NOT EXISTS (
      SELECT 1 FROM public.engagement_kind_permissions
      WHERE kind = v_kind AND role = v_role
    ) THEN
      v_invalid_kinds_roles := array_append(v_invalid_kinds_roles, v_kind || '/' || v_role);
      CONTINUE;
    END IF;

    -- Idempotency: skip if active engagement exists
    IF EXISTS (
      SELECT 1 FROM public.engagements
      WHERE person_id = p_person_id
        AND kind = v_kind
        AND role = v_role
        AND status = 'active'
        AND (
          (v_target_initiative_id IS NULL AND initiative_id IS NULL)
          OR initiative_id = v_target_initiative_id
        )
    ) THEN
      v_skipped_count := v_skipped_count + 1;
      CONTINUE;
    END IF;

    -- Insert new engagement
    INSERT INTO public.engagements (
      person_id, organization_id, initiative_id, kind, role, status,
      start_date, legal_basis, granted_by, metadata
    ) VALUES (
      p_person_id, v_caller_org, v_target_initiative_id,
      v_kind, v_role, 'active',
      CURRENT_DATE, 'contract_volunteer', v_caller_person_id,
      jsonb_build_object(
        'seeded_via', 'seed_member_engagement_by_role',
        'template_slug', p_template_slug,
        'template_id', v_template.id,
        'seeded_at', now()
      )
    ) RETURNING id INTO v_new_id;

    v_created_ids := array_append(v_created_ids, v_new_id);
  END LOOP;

  IF cardinality(v_invalid_kinds_roles) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'invalid_template_items',
      'detail', 'kind/role combos sem permissions seeded: ' || array_to_string(v_invalid_kinds_roles, ', '),
      'engagements_created', cardinality(v_created_ids),
      'engagement_ids', to_jsonb(v_created_ids)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'template_slug', p_template_slug,
    'template_id', v_template.id,
    'engagements_created', cardinality(v_created_ids),
    'engagements_skipped', v_skipped_count,
    'engagement_ids', to_jsonb(v_created_ids)
  );
END;
$function$;

COMMENT ON FUNCTION public.seed_member_engagement_by_role(uuid, text, uuid) IS
  'p172 #5 — Seed engagements pra um person via template canônico. Auth: manage_member. Idempotent (skip duplicates active). Validates template engagement kind+role tem permissions seeded em engagement_kind_permissions. Returns jsonb com engagements_created + engagements_skipped + engagement_ids.';

GRANT EXECUTE ON FUNCTION public.seed_member_engagement_by_role(uuid, text, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
