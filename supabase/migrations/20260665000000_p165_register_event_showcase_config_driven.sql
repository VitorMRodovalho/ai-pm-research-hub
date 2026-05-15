-- p165 Item #2 — register_event_showcase config-driven via gamification_rules (showcase_<subtype>)
-- Refs: ADR-0081 (config-driven), handoff_p165 Tier A backlog item #2
--
-- Previous behavior: RPC hardcoded XP per showcase_type (case_study=25, tool_review=20,
-- prompt_week=20, quick_insight=15, awareness=15). All slugs collapsed onto single rule
-- 'showcase' (base_points=20) — admin couldn't tune per type without code deploy.
-- Forward-only ADR-0081 semantics broken: gamification_rules.showcase.base_points was ignored.
--
-- New behavior: 5 dedicated slugs `showcase_<subtype>` with per-type base_points seeded.
-- RPC resolves slug = 'showcase_' || p_showcase_type, looks up rule via _grant_auto_xp
-- helper (idempotent, org-scoped, forward-only). Slug 'showcase' remains active for
-- historical FK integrity (12 existing gamification_points rows reference it) but new
-- writes flow through the per-subtype slugs.
--
-- Forward-only consistent with ADR-0081 backfill decision (p162): 21 existing event_showcases
-- preserve their original points; new event_showcases get awarded via per-subtype rule.
--
-- Rollback: DELETE 5 new rules + restore previous RPC body (see prior migration).

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 1 — Seed 5 per-subtype showcase rules
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.gamification_rules
  (slug, display_name_i18n, description_i18n, base_points, pillar, trigger_source, active, organization_id)
SELECT
  n.slug,
  n.display_name_i18n,
  n.description_i18n,
  n.base_points,
  'producao'::text,
  'rpc_callback'::text,
  true,
  org.organization_id
FROM (
  VALUES
    ('showcase_case_study',
     '{"pt-BR":"Showcase: Case de Sucesso","en-US":"Showcase: Success Case","es-LATAM":"Showcase: Caso de Éxito"}'::jsonb,
     '{"pt-BR":"Apresentação de case de sucesso aplicando AI em PM.","en-US":"Presentation of an AI-in-PM success case.","es-LATAM":"Presentación de caso de éxito aplicando IA en PM."}'::jsonb,
     25),
    ('showcase_tool_review',
     '{"pt-BR":"Showcase: Review de Ferramenta","en-US":"Showcase: Tool Review","es-LATAM":"Showcase: Reseña de Herramienta"}'::jsonb,
     '{"pt-BR":"Apresentação de review de ferramenta de AI/PM.","en-US":"Tool review presentation.","es-LATAM":"Presentación de reseña de herramienta."}'::jsonb,
     20),
    ('showcase_prompt_week',
     '{"pt-BR":"Showcase: Prompt da Semana","en-US":"Showcase: Prompt of the Week","es-LATAM":"Showcase: Prompt de la Semana"}'::jsonb,
     '{"pt-BR":"Apresentação de prompt destacado da semana.","en-US":"Featured prompt of the week.","es-LATAM":"Presentación del prompt destacado de la semana."}'::jsonb,
     20),
    ('showcase_quick_insight',
     '{"pt-BR":"Showcase: Insight Rápido","en-US":"Showcase: Quick Insight","es-LATAM":"Showcase: Insight Rápido"}'::jsonb,
     '{"pt-BR":"Insight rápido em formato breve (≤ 5 min).","en-US":"Quick insight short-form presentation.","es-LATAM":"Insight rápido en formato breve."}'::jsonb,
     15),
    ('showcase_awareness',
     '{"pt-BR":"Showcase: Sensibilização","en-US":"Showcase: Awareness","es-LATAM":"Showcase: Sensibilización"}'::jsonb,
     '{"pt-BR":"Pauta de sensibilização sobre AI/PM.","en-US":"AI/PM awareness topic.","es-LATAM":"Pauta de sensibilización sobre IA/PM."}'::jsonb,
     15)
) AS n(slug, display_name_i18n, description_i18n, base_points)
CROSS JOIN (
  SELECT DISTINCT organization_id
  FROM public.gamification_rules
  WHERE slug = 'showcase'
  LIMIT 1
) AS org
ON CONFLICT (organization_id, slug) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 2 — Replace register_event_showcase with config-driven body
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.register_event_showcase(uuid, uuid, text, text, text, integer);

CREATE OR REPLACE FUNCTION public.register_event_showcase(
  p_event_id uuid,
  p_member_id uuid,
  p_showcase_type text,
  p_title text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_duration_min integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_showcase_id uuid;
  v_rule public.gamification_rules%ROWTYPE;
  v_org_id uuid;
  v_count int;
  v_type_label text;
  v_slug text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_event'::text) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id) THEN
    RETURN jsonb_build_object('error', 'Member must be present at the event');
  END IF;

  SELECT count(*) INTO v_count FROM public.event_showcases
  WHERE event_id = p_event_id AND member_id = p_member_id;
  IF v_count >= 2 THEN
    RETURN jsonb_build_object('error', 'Maximum 2 showcases per member per meeting');
  END IF;

  SELECT organization_id INTO v_org_id FROM public.members WHERE id = p_member_id;
  IF v_org_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Member organization not found');
  END IF;

  -- Config-driven lookup: rule slug is 'showcase_' || subtype
  v_slug := 'showcase_' || p_showcase_type;
  SELECT * INTO v_rule
  FROM public.gamification_rules
  WHERE slug = v_slug
    AND organization_id = v_org_id
    AND active = true
    AND effective_from <= now()
  ORDER BY effective_from DESC
  LIMIT 1;
  IF v_rule.slug IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'showcase_type_not_configured',
      'expected_slug', v_slug
    );
  END IF;

  v_type_label := CASE p_showcase_type
    WHEN 'case_study'    THEN 'Case de Sucesso'
    WHEN 'tool_review'   THEN 'Review de Ferramenta'
    WHEN 'prompt_week'   THEN 'Prompt da Semana'
    WHEN 'quick_insight' THEN 'Insight Rápido'
    WHEN 'awareness'     THEN 'Sensibilização'
    ELSE p_showcase_type
  END;

  -- Persist showcase row
  INSERT INTO public.event_showcases (
    event_id, member_id, showcase_type, title, notes, duration_min, registered_by, xp_awarded
  )
  VALUES (
    p_event_id, p_member_id, p_showcase_type, p_title, p_notes,
    p_duration_min::smallint, v_caller.id, v_rule.base_points
  )
  RETURNING id INTO v_showcase_id;

  -- Award XP via shared helper (idempotency + forward-only lookup + org-scope)
  PERFORM public._grant_auto_xp(
    v_rule.slug,
    p_member_id,
    v_showcase_id,
    'Showcase: ' || v_type_label || COALESCE(' — ' || p_title, '')
  );

  RETURN jsonb_build_object(
    'id', v_showcase_id,
    'member_id', p_member_id,
    'showcase_type', p_showcase_type,
    'rule_slug', v_rule.slug,
    'xp_awarded', v_rule.base_points
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.register_event_showcase(uuid, uuid, text, text, text, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
