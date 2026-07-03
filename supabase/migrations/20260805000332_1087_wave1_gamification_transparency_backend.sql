-- =====================================================================================
-- #1087 Wave 1 — Gamification transparency backend: rules catalog + member statement API
--   + ledger actor provenance (granted_by).
--   Spec: docs/strategy/gamification_transparency_audit_and_spec.md (audit 2026-07-03).
--
-- 1) gamification_points.granted_by uuid NULL (additive, forward-only, NO backfill):
--    actor provenance per ledger row. NULL = system/cron flow (explicit semantics).
--    FK → members(id) ON DELETE SET NULL (LGPD erasure keeps the row, drops the pointer).
-- 2) _grant_auto_xp gains p_granted_by uuid DEFAULT NULL → DROP+CREATE (signature change).
--    Actor resolution: explicit param wins; else auth.uid() → members.id (trigger and
--    rpc_callback flows run inside the acting user's session); else NULL = system.
--    All 9 existing callers (8 trg_*_xp triggers + register_event_showcase) keep working
--    unchanged via the DEFAULT — verified live 2026-07-03 (pg_proc prosrc scan).
-- 3) award_champion: the ledger mirror INSERT now records granted_by = v_caller.id (the
--    grantor). Same signature → CREATE OR REPLACE (ACL preserved: authenticated keeps
--    EXECUTE; all authority checks unchanged).
-- 4) get_gamification_rules_catalog(): SSOT catalog for UI + MCP (ADR-0081 Pattern 47
--    extended to the frontend — no screen may repeat rule values). Active rules (latest
--    effective row per slug — same semantics as _grant_auto_xp), champion criteria
--    catalog, and level thresholds (moved from hardcoded gamification.astro getLevel()
--    tiers into platform_settings).
-- 5) get_my_points_statement(): member-scoped per-transaction statement via auth.uid()
--    (pattern get_my_meetings — no caller-supplied member id → no IDOR). Enriched with
--    rule display name/pillar, champion attribution (awarder + justification + criteria),
--    granted_by actor, and a reversal flag (points < 0; wave 3 makes reversals real).
--
-- GRANTS: catalog + statement → authenticated only (REVOKE public/anon).
--         _grant_auto_xp stays internal (postgres/service_role only — NO authenticated),
--         matching its pre-change ACL {postgres,service_role}.
-- =====================================================================================

-- ── 1) Ledger actor provenance ───────────────────────────────────────────────────────

ALTER TABLE public.gamification_points
  ADD COLUMN granted_by uuid REFERENCES public.members(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.gamification_points.granted_by IS
  'Actor provenance (#1087 wave 1): member who credited this row (grantor/acting user). NULL = system/cron flow. Forward-only — historical rows deliberately not backfilled.';

CREATE INDEX idx_gamification_points_granted_by
  ON public.gamification_points (granted_by)
  WHERE granted_by IS NOT NULL;

-- ── Level thresholds config (was hardcoded in gamification.astro getLevel()) ─────────

INSERT INTO public.platform_settings (key, value, description, change_reason)
VALUES (
  'gamification_level_thresholds',
  '[{"slug":"explorer","emoji":"🌱","min_points":0,"max_points":30},{"slug":"practitioner","emoji":"⚡","min_points":31,"max_points":90},{"slug":"expert","emoji":"🔥","min_points":91,"max_points":200},{"slug":"master","emoji":"💎","min_points":201,"max_points":400},{"slug":"legend","emoji":"🏆","min_points":401,"max_points":null}]'::jsonb,
  'Gamification level tiers (SSOT). Consumed by get_gamification_rules_catalog(); display names stay as i18n keys keyed by slug. Was hardcoded in gamification.astro getLevel() — #1087 wave 1.',
  '#1087 wave 1: move level tiers from frontend hardcode to config'
)
ON CONFLICT (key) DO NOTHING;

-- ── 2) _grant_auto_xp: actor param (DROP+CREATE — signature change) ──────────────────

DROP FUNCTION public._grant_auto_xp(text, uuid, uuid, text, boolean);

CREATE FUNCTION public._grant_auto_xp(
  p_slug text,
  p_recipient_id uuid,
  p_ref_id uuid,
  p_reason text,
  p_on_time boolean DEFAULT NULL::boolean,
  p_granted_by uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_rule gamification_rules%ROWTYPE;
  v_org_id uuid;
  v_points int;
  v_reason text;
  v_granted_by uuid;
BEGIN
  IF p_recipient_id IS NULL THEN
    RETURN; -- silently skip if no recipient (NULL assignee/author)
  END IF;

  SELECT organization_id INTO v_org_id FROM members WHERE id = p_recipient_id;
  IF v_org_id IS NULL THEN
    RETURN; -- recipient member not found
  END IF;

  SELECT * INTO v_rule
  FROM gamification_rules
  WHERE slug = p_slug
    AND organization_id = v_org_id
    AND active = true
    AND effective_from <= now()
  ORDER BY effective_from DESC LIMIT 1;
  IF v_rule.slug IS NULL THEN
    RETURN; -- rule disabled or missing
  END IF;

  -- Idempotency: skip if already paid for this ref_id + category
  IF EXISTS (
    SELECT 1 FROM gamification_points
    WHERE ref_id = p_ref_id AND category = p_slug AND member_id = p_recipient_id
  ) THEN
    RETURN;
  END IF;

  -- On-time BONUS policy: base always; add on_time_bonus_points only when the caller asserts
  -- on-time (p_on_time IS TRUE) AND the rule configures a bonus. NULL/false → base only (no penalty).
  v_points := v_rule.base_points;
  v_reason := p_reason;
  IF p_on_time IS TRUE AND COALESCE(v_rule.on_time_bonus_points, 0) > 0 THEN
    v_points := v_points + v_rule.on_time_bonus_points;
    v_reason := p_reason || ' (no prazo +' || v_rule.on_time_bonus_points || ')';
  END IF;

  -- Actor provenance (#1087 wave 1): explicit param wins; else the acting user's member row
  -- (trigger/rpc_callback flows run in the acting user session); else NULL = system/cron.
  v_granted_by := p_granted_by;
  IF v_granted_by IS NULL THEN
    SELECT id INTO v_granted_by FROM members WHERE auth_id = auth.uid();
  END IF;

  INSERT INTO gamification_points (member_id, points, reason, category, ref_id, organization_id, granted_by)
  VALUES (p_recipient_id, v_points, v_reason, v_rule.slug, p_ref_id, v_org_id, v_granted_by);
END;
$function$;

REVOKE ALL ON FUNCTION public._grant_auto_xp(text, uuid, uuid, text, boolean, uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._grant_auto_xp(text, uuid, uuid, text, boolean, uuid) TO service_role;

-- ── 3) award_champion: mirror INSERT records the grantor (same signature → OR REPLACE) ─

CREATE OR REPLACE FUNCTION public.award_champion(p_recipient_id uuid, p_surface text, p_context_kind text, p_context_id uuid, p_criteria_met text[], p_justification text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller members%ROWTYPE;
  v_org_id uuid;
  v_target_init_id uuid;
  v_event events%ROWTYPE;
  v_deliv tribe_deliverables%ROWTYPE;
  v_artifact meeting_artifacts%ROWTYPE;
  v_attendance_present boolean;
  v_per_event_count int;
  v_per_grantor_count int;
  v_per_cycle_count int;
  v_per_event_cap int;
  v_per_cycle_cap int;
  v_rule gamification_rules%ROWTYPE;
  v_points int;
  v_champion_id uuid;
  v_org_authority boolean;
  v_soft_cap_warning boolean := false;
  v_recipient_org uuid;
  v_invalid_criteria text[];
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error','not_authenticated');
  END IF;
  v_org_id := v_caller.organization_id;

  IF p_surface NOT IN ('general','tribe','deliverable') THEN
    RETURN jsonb_build_object('error','invalid_surface');
  END IF;
  IF p_context_kind NOT IN ('event','deliverable','artifact') THEN
    RETURN jsonb_build_object('error','invalid_context_kind');
  END IF;
  IF p_recipient_id = v_caller.id THEN
    RETURN jsonb_build_object('error','self_award_not_allowed');
  END IF;
  IF p_criteria_met IS NULL OR cardinality(p_criteria_met) < 1 OR cardinality(p_criteria_met) > 4 THEN
    RETURN jsonb_build_object('error','invalid_criteria_count','detail','must have 1-4 criteria');
  END IF;
  IF length(trim(p_justification)) < 50 THEN
    RETURN jsonb_build_object('error','justification_too_short','detail','must be >= 50 chars');
  END IF;

  -- p171 #8: Validate each criterion slug ∈ champion_criteria_catalog
  SELECT array_agg(c) INTO v_invalid_criteria
  FROM unnest(p_criteria_met) AS c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.champion_criteria_catalog cat
    WHERE cat.surface = p_surface
      AND cat.slug = c
      AND cat.active = true
      AND cat.organization_id = v_org_id
  );
  IF v_invalid_criteria IS NOT NULL AND cardinality(v_invalid_criteria) > 0 THEN
    RETURN jsonb_build_object(
      'error','invalid_criteria',
      'detail','unknown criterion slug(s) for surface ' || p_surface || ': ' || array_to_string(v_invalid_criteria, ', ')
    );
  END IF;

  IF p_surface = 'general' THEN
    IF p_context_kind != 'event' THEN
      RETURN jsonb_build_object('error','surface_context_kind_mismatch','detail','general requires event');
    END IF;
    SELECT * INTO v_event FROM events WHERE id = p_context_id;
    IF v_event.id IS NULL THEN
      RETURN jsonb_build_object('error','event_not_found');
    END IF;
    IF v_event.type NOT IN ('geral','lideranca') THEN
      RETURN jsonb_build_object('error','event_type_invalid_for_general','detail','expected type IN (geral, lideranca)');
    END IF;
    SELECT present INTO v_attendance_present FROM attendance
    WHERE event_id = p_context_id AND member_id = p_recipient_id;
    IF v_attendance_present IS NULL OR v_attendance_present = false THEN
      RETURN jsonb_build_object('error','recipient_not_present_at_event');
    END IF;
    v_target_init_id := NULL;

  ELSIF p_surface = 'tribe' THEN
    IF p_context_kind != 'event' THEN
      RETURN jsonb_build_object('error','surface_context_kind_mismatch','detail','tribe requires event');
    END IF;
    SELECT * INTO v_event FROM events WHERE id = p_context_id;
    IF v_event.id IS NULL THEN
      RETURN jsonb_build_object('error','event_not_found');
    END IF;
    IF v_event.type NOT IN ('tribo','1on1') THEN
      RETURN jsonb_build_object('error','event_type_invalid_for_tribe','detail','expected type IN (tribo, 1on1)');
    END IF;
    IF v_event.initiative_id IS NULL THEN
      RETURN jsonb_build_object('error','event_missing_initiative');
    END IF;
    SELECT present INTO v_attendance_present FROM attendance
    WHERE event_id = p_context_id AND member_id = p_recipient_id;
    IF v_attendance_present IS NULL OR v_attendance_present = false THEN
      RETURN jsonb_build_object('error','recipient_not_present_at_event');
    END IF;
    v_target_init_id := v_event.initiative_id;

  ELSIF p_surface = 'deliverable' THEN
    IF p_context_kind = 'deliverable' THEN
      SELECT * INTO v_deliv FROM tribe_deliverables WHERE id = p_context_id;
      IF v_deliv.id IS NULL THEN
        RETURN jsonb_build_object('error','deliverable_not_found');
      END IF;
      IF v_deliv.assigned_member_id IS NULL THEN
        RETURN jsonb_build_object('error','deliverable_no_assignee');
      END IF;
      IF v_deliv.assigned_member_id != p_recipient_id THEN
        RETURN jsonb_build_object('error','recipient_not_deliverable_assignee');
      END IF;
      v_target_init_id := v_deliv.initiative_id;
    ELSIF p_context_kind = 'artifact' THEN
      SELECT * INTO v_artifact FROM meeting_artifacts WHERE id = p_context_id;
      IF v_artifact.id IS NULL THEN
        RETURN jsonb_build_object('error','artifact_not_found');
      END IF;
      IF NOT v_artifact.is_published THEN
        RETURN jsonb_build_object('error','artifact_not_published');
      END IF;
      IF v_artifact.created_by IS NULL OR v_artifact.created_by != p_recipient_id THEN
        RETURN jsonb_build_object('error','recipient_not_artifact_creator');
      END IF;
      v_target_init_id := v_artifact.initiative_id;
    ELSE
      RETURN jsonb_build_object('error','surface_context_kind_mismatch','detail','deliverable surface requires context_kind IN (deliverable, artifact)');
    END IF;
  END IF;

  IF p_surface = 'general' THEN
    SELECT EXISTS (
      SELECT 1 FROM auth_engagements ae
      JOIN engagement_kind_permissions ekp
        ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = 'award_champion'
      WHERE ae.legacy_member_id = v_caller.id
        AND ae.status = 'active'
        AND ekp.scope = 'organization'
    ) INTO v_org_authority;
    IF NOT v_org_authority THEN
      RETURN jsonb_build_object('error','not_authorized','detail','general surface requires org-scope grantor');
    END IF;
  ELSE
    IF NOT public.can_by_member(v_caller.id, 'award_champion'::text, 'initiative'::text, v_target_init_id) THEN
      RETURN jsonb_build_object('error','not_authorized','detail','no award_champion grant for this initiative');
    END IF;
  END IF;

  v_per_event_cap := CASE p_surface
    WHEN 'general' THEN 3
    WHEN 'tribe' THEN 2
    WHEN 'deliverable' THEN 1
  END;
  SELECT count(*) INTO v_per_event_count
  FROM champions_awarded
  WHERE context_id = p_context_id
    AND surface = p_surface
    AND status = 'active';
  IF v_per_event_count >= v_per_event_cap THEN
    RETURN jsonb_build_object('error','per_event_cap_reached','detail',
      format('max %s champion(s) per %s context', v_per_event_cap, p_surface));
  END IF;

  SELECT count(*) INTO v_per_grantor_count
  FROM champions_awarded
  WHERE context_id = p_context_id
    AND awarded_by = v_caller.id
    AND status = 'active';
  IF v_per_grantor_count >= 3 THEN
    RETURN jsonb_build_object('error','per_grantor_cap_reached','detail','grantor max 3 champions per context');
  END IF;

  v_per_cycle_cap := CASE p_surface
    WHEN 'general' THEN 5
    WHEN 'tribe' THEN 8
    WHEN 'deliverable' THEN 3
  END;
  SELECT count(*) INTO v_per_cycle_count
  FROM champions_awarded ca
  JOIN cycles c ON c.is_current = true
  WHERE ca.recipient_id = p_recipient_id
    AND ca.surface = p_surface
    AND ca.status = 'active'
    AND ca.created_at >= c.cycle_start::timestamptz
    AND (c.cycle_end IS NULL OR ca.created_at < (c.cycle_end + interval '1 day')::timestamptz);
  IF v_per_cycle_count >= v_per_cycle_cap THEN
    v_soft_cap_warning := true;
  END IF;

  SELECT * INTO v_rule
  FROM gamification_rules
  WHERE slug = 'champion_' || p_surface
    AND organization_id = v_org_id
    AND active = true
    AND effective_from <= now()
  ORDER BY effective_from DESC
  LIMIT 1;
  IF v_rule.slug IS NULL THEN
    RETURN jsonb_build_object('error','rule_not_found','detail','no active rule for champion_' || p_surface);
  END IF;
  v_points := v_rule.base_points + (v_rule.bonus_per_criterion * cardinality(p_criteria_met));
  IF v_rule.cap_points IS NOT NULL AND v_points > v_rule.cap_points THEN
    v_points := v_rule.cap_points;
  END IF;

  INSERT INTO champions_awarded (
    recipient_id, awarded_by, surface, context_kind, context_id,
    criteria_met, justification, points_awarded, organization_id, initiative_id
  ) VALUES (
    p_recipient_id, v_caller.id, p_surface, p_context_kind, p_context_id,
    p_criteria_met, p_justification, v_points, v_org_id, v_target_init_id
  ) RETURNING id INTO v_champion_id;

  SELECT organization_id INTO v_recipient_org FROM members WHERE id = p_recipient_id;

  -- #1087 wave 1: ledger mirror carries actor provenance (granted_by = grantor)
  INSERT INTO gamification_points (member_id, points, reason, category, ref_id, organization_id, granted_by)
  VALUES (
    p_recipient_id,
    v_points,
    'Champion ' || p_surface || ': ' || substring(p_justification FROM 1 FOR 80),
    'champion_' || p_surface,
    v_champion_id,
    coalesce(v_recipient_org, v_org_id),
    v_caller.id
  );

  RETURN jsonb_build_object(
    'success', true,
    'champion_id', v_champion_id,
    'points_awarded', v_points,
    'soft_cap_warning', v_soft_cap_warning,
    'recipient_id', p_recipient_id,
    'surface', p_surface,
    'criteria_count', cardinality(p_criteria_met),
    'rule_slug', v_rule.slug
  );
END;
$function$;

-- ── 4) get_gamification_rules_catalog: SSOT catalog for UI + MCP ─────────────────────

CREATE FUNCTION public.get_gamification_rules_catalog()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_org_id uuid;
BEGIN
  SELECT m.organization_id INTO v_org_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  RETURN jsonb_build_object(
    'rules', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'slug', r.slug,
        'pillar', r.pillar,
        'display_name_i18n', r.display_name_i18n,
        'description_i18n', r.description_i18n,
        'base_points', r.base_points,
        'bonus_per_criterion', r.bonus_per_criterion,
        'cap_points', r.cap_points,
        'on_time_bonus_points', r.on_time_bonus_points,
        'trigger_source', r.trigger_source,
        'effective_from', r.effective_from
      ) ORDER BY r.pillar, r.base_points DESC, r.slug)
      FROM (
        -- latest effective row per slug — same resolution semantics as _grant_auto_xp
        SELECT DISTINCT ON (gr.slug) gr.*
        FROM public.gamification_rules gr
        WHERE gr.organization_id = v_org_id
          AND gr.active = true
          AND gr.effective_from <= now()
        ORDER BY gr.slug, gr.effective_from DESC
      ) r
    ), '[]'::jsonb),
    'champion_criteria', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'surface', c.surface,
        'slug', c.slug,
        'display_name_i18n', c.display_name_i18n,
        'description_i18n', c.description_i18n,
        'sort_order', c.sort_order
      ) ORDER BY c.surface, c.sort_order, c.slug)
      FROM public.champion_criteria_catalog c
      WHERE c.organization_id = v_org_id
        AND c.active = true
    ), '[]'::jsonb),
    'level_thresholds', COALESCE((
      SELECT ps.value
      FROM public.platform_settings ps
      WHERE ps.key = 'gamification_level_thresholds'
    ), '[]'::jsonb)
  );
END;
$function$;

COMMENT ON FUNCTION public.get_gamification_rules_catalog() IS
  '#1087 wave 1: SSOT catalog of active gamification rules + champion criteria + level thresholds. UI and MCP derive all displayed values from here (ADR-0081 Pattern 47 extended to the frontend).';

REVOKE ALL ON FUNCTION public.get_gamification_rules_catalog() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_gamification_rules_catalog() TO authenticated;

-- ── 5) get_my_points_statement: member-scoped per-transaction statement ──────────────

CREATE FUNCTION public.get_my_points_statement(
  p_scope text DEFAULT 'cycle',
  p_category text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_member_id uuid;
  v_org_id uuid;
  v_limit integer;
  v_offset integer;
  v_cycle_code text;
  v_from timestamptz;
  v_to timestamptz;
BEGIN
  SELECT m.id, m.organization_id INTO v_member_id, v_org_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF p_scope NOT IN ('cycle','lifetime') THEN
    RAISE EXCEPTION 'invalid scope: % (must be cycle or lifetime)', p_scope;
  END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  IF p_scope = 'cycle' THEN
    -- current-cycle window: same convention as get_member_xp_pillars / award_champion
    SELECT c.cycle_code, c.cycle_start::timestamptz,
           CASE WHEN c.cycle_end IS NULL THEN NULL
                ELSE (c.cycle_end + interval '1 day')::timestamptz END
      INTO v_cycle_code, v_from, v_to
    FROM public.cycles c
    WHERE c.is_current = true
    LIMIT 1;
  END IF;
  -- lifetime (or no current cycle): v_from/v_to stay NULL → no window filter when lifetime;
  -- cycle scope with no current cycle yields an empty statement (v_from NULL fails the >=).

  RETURN (
    WITH filtered AS (
      SELECT gp.id, gp.created_at, gp.points, gp.category, gp.reason, gp.ref_id, gp.granted_by,
             r.pillar, r.display_name_i18n
      FROM public.gamification_points gp
      LEFT JOIN LATERAL (
        SELECT gr.pillar, gr.display_name_i18n
        FROM public.gamification_rules gr
        WHERE gr.organization_id = gp.organization_id
          AND gr.slug = gp.category
        ORDER BY gr.effective_from DESC
        LIMIT 1
      ) r ON true
      WHERE gp.member_id = v_member_id
        AND gp.organization_id = v_org_id
        AND (
          p_scope = 'lifetime'
          OR (gp.created_at >= v_from AND (v_to IS NULL OR gp.created_at < v_to))
        )
        AND (p_category IS NULL OR gp.category = p_category)
    )
    SELECT jsonb_build_object(
      'member_id', v_member_id,
      'scope', p_scope,
      'cycle_code', CASE WHEN p_scope = 'cycle' THEN v_cycle_code END,
      'category_filter', p_category,
      'total_count', (SELECT count(*) FROM filtered),
      'total_points', COALESCE((SELECT sum(f.points) FROM filtered f), 0),
      'limit', v_limit,
      'offset', v_offset,
      'entries', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', e.id,
          'created_at', e.created_at,
          'points', e.points,
          'category', e.category,
          'pillar', e.pillar,
          'rule_display_name_i18n', e.display_name_i18n,
          'reason', e.reason,
          'ref_id', e.ref_id,
          'granted_by', e.granted_by,
          'granted_by_name', e.granted_by_name,
          'is_reversal', e.is_reversal,
          'champion', e.champion
        ) ORDER BY e.created_at DESC, e.id DESC)
        FROM (
          SELECT f.*, gm.name AS granted_by_name,
                 (f.points < 0) AS is_reversal,
                 CASE WHEN f.category LIKE 'champion\_%' THEN (
                   SELECT jsonb_build_object(
                     'awarded_by_name', am.name,
                     'justification', ca.justification,
                     'criteria_met', ca.criteria_met,
                     'status', ca.status
                   )
                   FROM public.champions_awarded ca
                   LEFT JOIN public.members am ON am.id = ca.awarded_by
                   WHERE ca.id = f.ref_id
                 ) END AS champion
          FROM filtered f
          LEFT JOIN public.members gm ON gm.id = f.granted_by
          ORDER BY f.created_at DESC, f.id DESC
          LIMIT v_limit OFFSET v_offset
        ) e
      ), '[]'::jsonb)
    )
  );
END;
$function$;

COMMENT ON FUNCTION public.get_my_points_statement(text, text, integer, integer) IS
  '#1087 wave 1: member-scoped per-transaction points statement (auth.uid pattern — no IDOR). Enriched with rule pillar/display name, champion attribution, granted_by actor, reversal flag. Paginated (limit clamp [1,200]).';

REVOKE ALL ON FUNCTION public.get_my_points_statement(text, text, integer, integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_my_points_statement(text, text, integer, integer) TO authenticated;
