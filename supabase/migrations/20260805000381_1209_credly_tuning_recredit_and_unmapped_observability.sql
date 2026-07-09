-- #1209: Credly keyword tuning (Tier 1/2) — deterministic recredit + unmapped-badge observability + monthly cron.
--
-- Context: classifyBadge() falls back to category 'badge' (10 XP) for any Credly badge that matches no
-- keyword. The fallback is SILENT: the badge scores 10, is filtered out of the members.credly_badges
-- display cache, and nobody is told. That is the class that hid Pedro Henrique's CPMAI at 0 XP (#1149).
--
-- This migration ships the #1209 backlog (P4 of #1149), GP-approved 2026-07-08 (Tier 1 + Tier 2):
--   (a) Deterministic recredit of the badges the new keywords promote — mirrors the classify-badge.ts
--       keyword additions in the same PR, so the live rows match the forward path immediately (does not
--       wait for the next sync). Points DERIVE from gamification_rules (SSOT / Pattern 47), not hardcoded.
--   (b) _credly_unmapped_rows() + get_credly_unmapped_badges() — the GP can list what is still in the
--       fallback and decide, per badge, whether it warrants a new keyword. Never a silent reclassification.
--   (c) A 'credly_unmapped_badges' block folded into detect_operational_alerts (consumed by the admin
--       panel + MCP get_operational_alerts), severity low.
--   (d) detect_credly_unmapped_cron() + monthly cron ('credly-unmapped-monthly', day 1, 09:00 UTC) that
--       notifies manage_platform holders when the fallback bucket is non-empty (25-day dedup = monthly).
--
-- Grounded via execute_sql read-only (2026-07-08, this worktree):
--   fallback bucket = 91 rows / 27 members / 910 XP.
--   Recredit target = 15 rows / 10 members / +140 XP (course 7×+5, specialization 5×+15, knowledge 3×+10).
--   Kept at badge/10 = 76 rows (participation/recognition + out-of-domain certs: Oracle, OneTrust, PPP,
--   construction, DevOps, OKR — deliberately 10, the núcleo is AI + PM).
--   Non-regression check: the only already-recognized badges matching a new keyword are the 3 "Enterprise
--   Design Thinking" ones, already knowledge_ai_pm → no change.
--
-- Rollback: revert the recredit is NOT auto-reversible (points changed); the observability side rolls back
-- via DROP FUNCTION get_credly_unmapped_badges/_credly_unmapped_rows/detect_credly_unmapped_cron +
-- cron.unschedule('credly-unmapped-monthly') + restore detect_operational_alerts without the #1209 block.

-- ── (a) Deterministic recredit — mirrors classify-badge.ts (#1209); prices from gamification_rules SSOT ──
DO $$
DECLARE
  v_updated integer := 0;
BEGIN
  WITH recl AS (
    SELECT gp.id,
      CASE
        WHEN lower(gp.reason) LIKE '%pmi essentials%' OR lower(gp.reason) LIKE '%m.o.r.e%'
          OR lower(gp.reason) LIKE '%citizen developer%' OR lower(gp.reason) LIKE '%hybrid project management%'
          THEN 'course'
        WHEN lower(gp.reason) LIKE '%scaled professional scrum%' OR lower(gp.reason) LIKE '%green project manager%'
          OR lower(gp.reason) LIKE '%sustainable project professional%' OR lower(gp.reason) LIKE '%cloud essentials%'
          OR lower(gp.reason) LIKE '%well-architected%'
          THEN 'specialization'
        WHEN lower(gp.reason) LIKE '%data visualization%' OR lower(gp.reason) LIKE '%big data%'
          OR lower(gp.reason) LIKE '%design thinking%'
          THEN 'knowledge_ai_pm'
      END AS newcat
    FROM public.gamification_points gp
    WHERE gp.category = 'badge' AND gp.reason ILIKE 'Credly:%'
  )
  UPDATE public.gamification_points gp
  SET category = recl.newcat,
      points   = r.base_points
  FROM recl
  JOIN public.gamification_rules r ON r.slug = recl.newcat
  WHERE gp.id = recl.id AND recl.newcat IS NOT NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'migration.credly_tuning_recredit_1209', 'system_event', NULL,
    jsonb_build_object('rows_recredited', v_updated, 'expected_rows', 15, 'expected_delta_xp', 140),
    jsonb_build_object('source', 'migration_1209', 'tiers', 'Tier1+Tier2', 'approved_by', 'GP 2026-07-08')
  );

  RAISE NOTICE '#1209 recredit: % rows promoted from badge/10 to specific category (expected 15).', v_updated;
END $$;

-- ── (b) helper: current fallback bucket, grouped by badge name (PUBLIC revoked) ──
CREATE OR REPLACE FUNCTION public._credly_unmapped_rows()
 RETURNS TABLE(badge_name text, occurrences integer, members integer)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT regexp_replace(gp.reason, '^Credly:\s*', '') AS badge_name,
         count(*)::int AS occurrences,
         count(DISTINCT gp.member_id)::int AS members
  FROM public.gamification_points gp
  WHERE gp.category = 'badge' AND gp.reason ILIKE 'Credly:%'
  GROUP BY 1
  ORDER BY count(*) DESC, 1;
$function$;

REVOKE EXECUTE ON FUNCTION public._credly_unmapped_rows() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._credly_unmapped_rows() TO service_role;

-- ── (b) consumer RPC: get_credly_unmapped_badges (gated manage_platform) ─────
CREATE OR REPLACE FUNCTION public.get_credly_unmapped_badges()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
  v_total integer;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.occurrences DESC, r.badge_name), '[]'::jsonb),
         coalesce(sum(r.occurrences), 0)
  INTO v_rows, v_total
  FROM public._credly_unmapped_rows() r;

  RETURN jsonb_build_object(
    'unmapped',        v_rows,
    'distinct_badges', jsonb_array_length(v_rows),
    'total_rows',      v_total,
    'note',            'Badges no fallback badge/10. Promover = adicionar keyword em _shared/classify-badge.ts + recredit (ver #1209).',
    'checked_at',      now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_credly_unmapped_badges() TO authenticated, service_role;

-- ── (d) monthly cron detector — notifies manage_platform when the fallback bucket is non-empty ──
CREATE OR REPLACE FUNCTION public.detect_credly_unmapped_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_distinct integer := 0;
  v_total    integer := 0;
  v_inserted integer := 0;
BEGIN
  SELECT count(*)::int, coalesce(sum(occurrences), 0)::int
  INTO v_distinct, v_total
  FROM public._credly_unmapped_rows();

  IF v_distinct > 0 THEN
    -- 25-day dedup = monthly reminder (no double-fire within a month). digest_weekly batches it.
    INSERT INTO public.notifications (recipient_id, type, title, body, delivery_mode, created_at)
    SELECT m.id,
           'credly_unmapped_badges',
           format('%s badge(s) Credly não-mapeado(s) para revisão', v_distinct),
           format('%s badge(s) Credly distinto(s) (%s atribuições) estão pontuando no fallback de 10 XP. Revise se algum merece categoria específica (curso/certificação/especialização) e, em caso positivo, adicione a keyword em classify-badge.ts. Ver get_credly_unmapped_badges (#1209).', v_distinct, v_total),
           'digest_weekly',
           now()
    FROM public.members m
    WHERE m.is_active = true
      AND public.can_by_member(m.id, 'manage_platform')
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'credly_unmapped_badges'
          AND n.created_at >= now() - interval '25 days'
      );
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_credly_unmapped_run', 'system_event', NULL,
      jsonb_build_object('distinct_badges', v_distinct, 'total_rows', v_total, 'managers_notified', v_inserted),
      jsonb_build_object('source', 'cron_detect_credly_unmapped')
    );
  END IF;

  RETURN jsonb_build_object(
    'distinct_badges',        v_distinct,
    'total_rows',             v_total,
    'notifications_inserted', v_inserted,
    'run_at',                 now()
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.detect_credly_unmapped_cron() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.detect_credly_unmapped_cron() TO service_role;

-- cron.schedule upserts by job name → idempotent on re-apply.
SELECT cron.schedule('credly-unmapped-monthly', '0 9 1 * *', 'SELECT public.detect_credly_unmapped_cron();');

-- ── (c) fold credly_unmapped_badges into the computed ops-alerts dashboard ───
-- Body = the live detect_operational_alerts verbatim (captured 2026-07-08) + one aggregate #1209 block
-- before RETURN. CREATE OR REPLACE preserves grants/owner.
CREATE OR REPLACE FUNCTION public.detect_operational_alerts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_alerts jsonb := '[]'::jsonb;
  v_tmp jsonb;
  v_cycle_start date;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission';
  END IF;

  SELECT cycle_start::date INTO v_cycle_start FROM cycles WHERE is_current = true LIMIT 1;
  IF v_cycle_start IS NULL THEN v_cycle_start := current_date - 90; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', CASE WHEN sub.last_in_cycle IS NULL THEN 'medium' ELSE 'high' END,
    'type', 'tribe_no_meeting',
    'tribe_id', sub.id, 'tribe_name', sub.name, 'days_since', sub.days_since,
    'message', CASE
      WHEN sub.last_in_cycle IS NULL THEN sub.name || ' sem reunião registrada neste ciclo'
      ELSE sub.name || ' sem reunião há ' || sub.days_since || ' dias'
    END
  ))
  INTO v_tmp
  FROM (
    SELECT t.id, t.name,
      MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) as last_in_cycle,
      EXTRACT(DAY FROM now() - MAX(e.date) FILTER (WHERE e.date >= v_cycle_start)::timestamp)::int as days_since
    FROM tribes t
    LEFT JOIN initiatives i ON i.legacy_tribe_id = t.id
    LEFT JOIN events e ON e.initiative_id = i.id
    WHERE t.is_active = true
    GROUP BY t.id, t.name
    HAVING MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) < current_date - 14
       OR MAX(e.date) FILTER (WHERE e.date >= v_cycle_start) IS NULL
  ) sub;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium', 'type', 'member_absence_streak',
    'member_name', m.name, 'tribe_name', t.name,
    'message', m.name || ' ausente em últimas reuniões da ' || t.name
  ))
  INTO v_tmp
  FROM members m JOIN tribes t ON t.id = m.tribe_id
  WHERE m.is_active AND m.tribe_id IS NOT NULL
  AND m.id NOT IN (
    SELECT DISTINCT a.member_id FROM attendance a
    JOIN events e ON e.id = a.event_id
    LEFT JOIN initiatives i2 ON i2.id = e.initiative_id
    WHERE i2.legacy_tribe_id = m.tribe_id AND e.date >= current_date - 21 AND a.present = true
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'medium', 'type', 'tribe_stagnant_production',
    'tribe_id', t.id, 'tribe_name', t.name,
    'message', t.name || ' sem movimentação de cards em 14+ dias'
  ))
  INTO v_tmp
  FROM tribes t WHERE t.is_active = true
  AND t.id NOT IN (
    SELECT DISTINCT i3.legacy_tribe_id
    FROM board_lifecycle_events ble
    JOIN board_items bi ON bi.id = ble.item_id
    JOIN project_boards pb ON pb.id = bi.board_id
    JOIN initiatives i3 ON i3.id = pb.initiative_id
    WHERE ble.created_at >= now() - interval '14 days' AND i3.legacy_tribe_id IS NOT NULL
  );
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'low', 'type', 'onboarding_overdue',
    'member_name', sa.applicant_name, 'step', op.step_key,
    'message', sa.applicant_name || ' atrasou ' || op.step_key
  ))
  INTO v_tmp
  FROM onboarding_progress op
  JOIN selection_applications sa ON sa.id = op.application_id
  WHERE op.status = 'overdue';
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'high', 'type', 'kpi_at_risk',
    'kpi_name', pkt.metric_key, 'target_value', pkt.target_value,
    'message', pkt.metric_key || ' abaixo de 50% da meta'
  ))
  INTO v_tmp
  FROM portfolio_kpi_targets pkt
  WHERE pkt.target_value > 0 AND pkt.critical_threshold > 0
  AND pkt.critical_threshold < (pkt.target_value * 0.5);
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'severity', CASE WHEN e.type IN ('geral', 'kickoff', 'lideranca') THEN 'high' ELSE 'medium' END,
    'type', 'recorded_event_without_minutes',
    'event_id', e.id, 'event_title', e.title, 'event_type', e.type, 'event_date', e.date,
    'has_youtube', e.youtube_url IS NOT NULL,
    'has_recording', e.recording_url IS NOT NULL,
    'message', 'Evento gravado sem ata: ' || e.title || ' (' || e.date || ')'
  ))
  INTO v_tmp
  FROM events e
  WHERE (e.youtube_url IS NOT NULL OR e.recording_url IS NOT NULL)
    AND (
      e.minutes_text IS NULL
      OR trim(e.minutes_text) = ''
      OR lower(trim(e.minutes_text)) IN ('teste', 'teste teste', 'test', 'placeholder', '-')
      OR length(trim(e.minutes_text)) < 20
    )
    AND e.date >= v_cycle_start
    AND e.date <= current_date;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- #415: recurring series running out of future events (recently active + low buffer).
  SELECT jsonb_agg(jsonb_build_object(
    'severity', 'high', 'type', 'recurrence_stockout',
    'recurrence_group', r.recurrence_group, 'event_type', r.event_type,
    'last_date', r.last_date, 'modal_gap_days', r.modal_gap_days, 'next_expected', r.next_expected,
    'message', 'Série recorrente (' || r.event_type || ') no fim do estoque: última em ' || r.last_date || ', próxima esperada ~' || r.next_expected
  ))
  INTO v_tmp
  FROM public._recurrence_stockout_rows(30) r;
  IF v_tmp IS NOT NULL THEN v_alerts := v_alerts || v_tmp; END IF;

  -- #1209: Credly badges stuck in the fallback 'badge'/10 bucket — promotion candidates. One aggregate
  -- alert (not one per badge). Never a silent reclassification; the GP reviews via get_credly_unmapped_badges.
  SELECT jsonb_build_object(
    'severity', 'low',
    'type', 'credly_unmapped_badges',
    'distinct_badges', count(*),
    'total_rows', coalesce(sum(u.occurrences), 0),
    'message', count(*) || ' badge(s) Credly em fallback (10 XP), ' || coalesce(sum(u.occurrences), 0)
               || ' atribuição(ões) — revisar em get_credly_unmapped_badges p/ possível promoção de categoria'
  )
  INTO v_tmp
  FROM public._credly_unmapped_rows() u;
  IF v_tmp IS NOT NULL AND (v_tmp->>'distinct_badges')::int > 0 THEN
    v_alerts := v_alerts || v_tmp;
  END IF;

  RETURN jsonb_build_object(
    'alerts', v_alerts,
    'total', jsonb_array_length(v_alerts),
    'by_severity', jsonb_build_object(
      'high', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'high'),
      'medium', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'medium'),
      'low', (SELECT COUNT(*) FROM jsonb_array_elements(v_alerts) x WHERE x->>'severity' = 'low')
    ),
    'checked_at', now()
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
