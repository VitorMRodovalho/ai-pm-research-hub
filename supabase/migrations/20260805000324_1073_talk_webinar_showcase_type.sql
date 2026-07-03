-- #1073: reward members who deliver a talk / webinar / panel (mesa redonda) FOR the
-- Núcleo. No new pillar: a delivered talk is knowledge production, so it becomes a new
-- `event_showcases` subtype `talk` scored under the `producao` pillar (25 XP, top of the
-- showcase tier, = case_study). Attribution to the Núcleo is enforced by the existing
-- register_event_showcase gates (manage_event coordinator + the speaker present at a
-- Núcleo event); an external talk only counts if a Núcleo event exists for it (i.e. under
-- an agreement). Scope + mechanism ratified by the owner 2026-07-02.

-- 1) Allow the new subtype on the showcase table.
ALTER TABLE public.event_showcases DROP CONSTRAINT event_showcases_showcase_type_check;
ALTER TABLE public.event_showcases ADD CONSTRAINT event_showcases_showcase_type_check
  CHECK (showcase_type = ANY (ARRAY['case_study'::text, 'tool_review'::text, 'prompt_week'::text, 'quick_insight'::text, 'awareness'::text, 'talk'::text]));

-- 2) Config-driven scoring rule (slug convention: 'showcase_' || subtype). Org-scoped,
--    mirrors showcase_case_study (producao / rpc_callback / 25). Idempotent on (org, slug).
INSERT INTO public.gamification_rules (
  id, slug, pillar, display_name_i18n, description_i18n,
  base_points, bonus_per_criterion, cap_points, on_time_bonus_points,
  trigger_source, active, effective_from, organization_id
)
VALUES (
  gen_random_uuid(), 'showcase_talk', 'producao',
  '{"pt-BR":"Showcase: Palestra / Webinar / Mesa","en-US":"Showcase: Talk / Webinar / Panel","es-LATAM":"Showcase: Charla / Webinar / Mesa"}'::jsonb,
  '{"pt-BR":"Palestra, webinar ou mesa redonda conduzida pelo membro em evento do Núcleo (ou externo sob acordo).","en-US":"A talk, webinar or panel delivered by the member at a Núcleo event (or external under agreement).","es-LATAM":"Charla, webinar o mesa redonda conducida por el miembro en un evento del Núcleo (o externo bajo acuerdo)."}'::jsonb,
  25, 0, NULL, NULL,
  'rpc_callback', true, TIMESTAMPTZ '2026-07-02 00:00:00+00', '2b4f58ab-7c45-4170-8718-b77ee69ff906'
)
ON CONFLICT (organization_id, slug) DO NOTHING;

-- 3) Add the 'talk' human label to register_event_showcase (only the v_type_label CASE
--    gains a branch; the slug lookup already resolves 'showcase_talk' generically).
CREATE OR REPLACE FUNCTION public.register_event_showcase(p_event_id uuid, p_member_id uuid, p_showcase_type text, p_title text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_duration_min integer DEFAULT NULL::integer)
 RETURNS jsonb
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
    WHEN 'talk'          THEN 'Palestra / Webinar / Mesa'
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
$function$
