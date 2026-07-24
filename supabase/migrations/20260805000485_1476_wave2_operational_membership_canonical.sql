-- #1476 Onda 2 — pertencimento OPERACIONAL por engagement (canonical), não pelo cache operational_role.
--
-- Continuação da Onda 1 (tribe-scoped, mig 484). Aqui as superfícies org-wide / write-path que também
-- usavam `members.operational_role IN (...)` como proxy de pertencimento operacional. Mesmo bug de fundo:
-- quem acumula ponto focal de capítulo (chapter_board) + pesquisador de tribo (volunteer/researcher) tem o
-- cache resolvido para 'chapter_liaison' pela escada "governança vence" (sync_operational_role_cache) e é
-- apagado das coortes operacionais, apesar de engagement volunteer ativo. Fonte de verdade = engagement.
--
-- DECISÃO DE OWNER (2026-07-23): o KPI publicado `v_operational_members` (#1437/ADR-0126) NÃO é rebaseado —
-- fica 69 (governança-vence deliberado; é métrica de COMPOSIÇÃO onde o dual-hat conta como stakeholder de
-- governança). Este canonical amplo é SÓ para as superfícies de INTERVENÇÃO OPERACIONAL (attendance seal,
-- summaries, dropout, cohort-health, credly), onde apagar um pesquisador ativo é dano real (no-show falso,
-- some da lista de intervenção). Divergência intencional, documentada. NÃO tocar v_operational_members.
--
-- Design (data-architect consult 2x, #1476): NÃO uma view flat de pertencimento — os 8 consumidores têm
-- tier-sets diferentes (seal/summaries/dropout = {researcher,tribe_leader,manager}; cohort-health/overview =
-- {researcher,tribe_leader}; credly = +{deputy_manager}). Uma view flat corromperia silenciosamente a coorte
-- no-manager. Logo: junction view por-membro-por-tier `v_member_operational_tiers` (multi-hat, uma linha por
-- (membro, tier derivado de engagement)); cada consumidor faz semi-join EXISTS ao SEU próprio subconjunto e
-- mantém o SEU próprio base-filter (is_active / +current_cycle_active / member_status — eixo de lifecycle de
-- MEMBRO, distinto do eixo de engagement que a view já filtra via is_authoritative).
--
-- Escopo do CASE = tiers operacionais da escada MENOS a sub-cláusula committee/workgroup: essa foi dobrada em
-- 'researcher' para autoridade via canFor() (p164, mig 20260662000000), NUNCA para elegibilidade de presença.
-- O gate `kind='volunteer'` no JOIN exclui committee/workgroup na fonte. Isso mantém FORA da coorte de escrita
-- um sponsor ou diretor de capítulo cujo único vínculo "researcher" é assento de comitê (materialidade: seal
-- materializa AUSÊNCIA para eventos geral/kickoff org-wide).
--
-- Deltas aterrados ao vivo 2026-07-23 (before -> after, todos +2 os MESMOS dual-hat das tribos 1 e 7, 0 drops):
--   seal / get_attendance_engagement_summary / get_attendance_reliability_summary / get_dropout_risk_members: 69 -> 71
--   get_gp_cohort_health / get_cycle_attendance_overview: 67 -> 69   (tier-set sem manager)
--   _credly_health_rows: 69 -> 71
-- Regressão probe (população member_status='active'): membros committee-only que sairiam = 0.
--
-- FORA desta migration: #1477 check_my_tcv_readiness (gate INVERSO de isenção, impacto comportamental mais
-- amplo — avaliar em onda curta separada); v_operational_members (#1437, decisão de owner acima).

-- ============================================================================
-- 1) Junction canônica: (membro, tier operacional) derivado de engagement volunteer autoritativo
-- ============================================================================
-- Consumido SOMENTE dentro de funções SECURITY DEFINER (owner=postgres, rolbypassrls). security_invoker=on
-- + REVOKE de anon/authenticated é LOAD-BEARING: pg_default_acl auto-concede DML a anon/authenticated em toda
-- relação nova (lição #1422). Se um futuro consumidor NÃO for owned by postgres, precisará de GRANT SELECT
-- explícito nesta view. is_authoritative já implica engagement status='active' (não precisa base-filter aqui).
-- Lista de papéis declarada UMA vez (via LATERAL) — evitar o anti-padrão de predicado duplicado (o próprio
-- que gerou o bug de ~16 funções). DISTINCT (member, tier): um dual-hat gera legitimamente 2 linhas; TODO
-- consumidor usa EXISTS (semi-join), nunca JOIN+COUNT (senão dupla contagem — (A) do consult).
CREATE OR REPLACE VIEW public.v_member_operational_tiers AS
SELECT DISTINCT
  m.id        AS member_id,
  m.person_id,
  tier.operational_tier
FROM public.members m
JOIN public.auth_engagements ae
  ON ae.person_id = m.person_id
 AND ae.is_authoritative = true
 AND ae.kind = 'volunteer'
CROSS JOIN LATERAL (
  SELECT CASE
    WHEN ae.role IN ('manager','co_gp')      THEN 'manager'
    WHEN ae.role = 'deputy_manager'          THEN 'deputy_manager'
    WHEN ae.role IN ('leader','comms_leader') THEN 'tribe_leader'
    WHEN ae.role IN ('researcher','facilitator','communicator','curator') THEN 'researcher'
  END AS operational_tier
) tier
WHERE tier.operational_tier IS NOT NULL;

ALTER VIEW public.v_member_operational_tiers SET (security_invoker = on);
REVOKE ALL ON public.v_member_operational_tiers FROM PUBLIC, anon, authenticated;

COMMENT ON VIEW public.v_member_operational_tiers IS
  'Canonical (member, operational tier) junction by engagement — SSOT for operational cohort belonging (#1476 Onda 2). '
  'One row per (member, engagement-derived tier); multi-hat members produce >1 row, so consumers MUST semi-join (EXISTS), never JOIN+COUNT. '
  'Tiers = ladder operational tiers (manager/deputy_manager/tribe_leader/researcher) via volunteer-kind engagements ONLY '
  '(committee/workgroup folded into researcher for canFor authority per p164, NOT for attendance eligibility — excluded by kind=volunteer gate). '
  'No member-activity filter by design: is_authoritative implies engagement status=active; each consumer owns its own is_active/current_cycle_active/member_status filter. '
  'CONSUMED BY A DESTRUCTIVE WRITE PATH (seal_event_attendance materializes absence rows): any predicate change must re-ground the live count + audit the delta set by name before merge. '
  'security_invoker=on + REVOKE from anon/authenticated is load-bearing (#1422 pg_default_acl auto-grant). '
  'Deliberately distinct from v_operational_members (#1437/ADR-0126, governance-wins KPI, stays 69) — this is operational intervention, not the composition headline.';

-- ============================================================================
-- 2) seal_event_attendance — WRITE-PATH (maior materialidade): coorte elegível via junction canônica
-- ============================================================================
CREATE OR REPLACE FUNCTION public.seal_event_attendance(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_type      text;
  v_status    text;
  v_date      date;
  v_title     text;
  v_org       uuid;
  v_sealed_at timestamptz;
  v_eligible  int := 0;
  v_sealed    int := 0;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado: requer manage_event');
  END IF;

  SELECT e.type, e.status, e.date, e.title, e.organization_id, e.roster_sealed_at
    INTO v_type, v_status, v_date, v_title, v_org, v_sealed_at
  FROM public.events e WHERE e.id = p_event_id;

  IF v_type IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento não encontrado', 'event_id', p_event_id);
  END IF;
  IF v_type NOT IN ('geral','kickoff','tribo','lideranca') THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Tipo de evento não elegível para presença (' || v_type || ')', 'event_id', p_event_id);
  END IF;
  IF v_status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento cancelado não pode ser selado', 'event_id', p_event_id);
  END IF;
  IF v_date > CURRENT_DATE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Evento futuro não pode ser selado', 'event_id', p_event_id);
  END IF;

  -- eligible operational cohort for THIS event (canonical eligibility only — SPEC §3b)
  -- #1476 Onda 2: coorte operacional por engagement (junction), não pelo cache operational_role.
  SELECT count(*) INTO v_eligible
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
    AND EXISTS (
      SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
    );

  -- materialize an absent row for every eligible no-show (no existing row) — idempotent, non-destructive
  INSERT INTO public.attendance (event_id, member_id, present, excused, organization_id, notes, registered_by, marked_by, checked_in_at)
  SELECT p_event_id, m.id, false, false, v_org,
         '[roster_seal] no-show materializado (PR11 seal track)', v_caller_id, v_caller_id, NULL
  FROM public.members m
  WHERE m.is_active = true AND m.current_cycle_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
    AND EXISTS (
      SELECT 1 FROM public._attendance_eligible_events(m.id, NULL) ee WHERE ee.event_id = p_event_id
    )
  ON CONFLICT (event_id, member_id) DO NOTHING;
  GET DIAGNOSTICS v_sealed = ROW_COUNT;

  UPDATE public.events SET roster_sealed_at = COALESCE(roster_sealed_at, now())
  WHERE id = p_event_id
  RETURNING roster_sealed_at INTO v_sealed_at;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_title,
    'event_type', v_type,
    'event_date', v_date,
    'eligible_cohort_n', v_eligible,
    'sealed_absent_count', v_sealed,
    'already_recorded_count', GREATEST(v_eligible - v_sealed, 0),
    'roster_sealed_at', v_sealed_at
  );
END;
$function$;

-- ============================================================================
-- 3) get_attendance_engagement_summary — coorte global/tribe via junction (branch chapter intocado)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_attendance_engagement_summary(p_scope text DEFAULT 'global'::text, p_scope_id integer DEFAULT NULL::integer, p_cycle_start date DEFAULT NULL::date, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE CASE
      WHEN p_scope = 'chapter' THEN (m.member_status = 'active' AND m.chapter = p_chapter)
      ELSE (
        m.is_active = true AND m.current_cycle_active = true
        AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                    WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
        AND (
          p_scope = 'global'
          OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
        )
      )
    END
  ),
  rates AS (
    SELECT c.id, public.get_attendance_engagement_rate(c.id, p_cycle_start) AS rate
    FROM cohort c
  ),
  totals AS (
    SELECT
      count(*) FILTER (WHERE att.present = true)        AS present_total,
      count(*) FILTER (WHERE att.excused IS NOT TRUE)   AS expected_total,
      count(*) FILTER (WHERE att.excused = true)        AS excused_total
    FROM cohort c
    CROSS JOIN LATERAL public._attendance_eligible_events(c.id, p_cycle_start) el
    LEFT JOIN public.attendance att ON att.member_id = c.id AND att.event_id = el.event_id
  )
  SELECT jsonb_build_object(
    'scope', p_scope,
    'scope_id', p_scope_id,
    'cohort_n', (SELECT count(*) FROM rates WHERE rate IS NOT NULL),
    'avg_rate', (SELECT ROUND(AVG(rate), 4) FROM rates WHERE rate IS NOT NULL),
    'at_risk_count', (SELECT count(*) FROM rates WHERE rate IS NOT NULL AND rate < 0.50),
    'present_total', (SELECT present_total FROM totals),
    'expected_total', (SELECT expected_total FROM totals),
    'excused_total', (SELECT excused_total FROM totals),
    'coverage_flag', CASE WHEN (SELECT count(*) FROM rates WHERE rate IS NOT NULL) = 0 THEN 'no_data' ELSE 'ok' END
  );
$function$;

-- ============================================================================
-- 4) get_attendance_reliability_summary — coorte global/tribe via junction (branch chapter intocado)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_attendance_reliability_summary(p_scope text DEFAULT 'global'::text, p_scope_id integer DEFAULT NULL::integer, p_cycle_start date DEFAULT NULL::date, p_chapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH cohort AS (
    SELECT m.id
    FROM public.members m
    WHERE CASE
      WHEN p_scope = 'chapter' THEN (m.member_status = 'active' AND m.chapter = p_chapter)
      ELSE (
        m.is_active = true AND m.current_cycle_active = true
        AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                    WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
        AND (
          p_scope = 'global'
          OR (p_scope = 'tribe' AND public.get_member_tribe(m.id) = p_scope_id)
        )
      )
    END
  ),
  rates AS (
    SELECT c.id, public.get_attendance_rate(c.id, p_cycle_start) AS rate
    FROM cohort c
  ),
  recorded AS (
    SELECT
      count(*) FILTER (WHERE att.present = true)                          AS present_total,
      count(*) FILTER (WHERE att.present = false AND att.excused IS NOT TRUE) AS absent_total,
      count(*) FILTER (WHERE att.excused = true)                          AS excused_total
    FROM cohort c
    JOIN public.attendance att ON att.member_id = c.id
    JOIN public.events e ON e.id = att.event_id
    WHERE e.date >= COALESCE(p_cycle_start, (SELECT cy.cycle_start FROM public.cycles cy WHERE cy.is_current = true LIMIT 1))
      AND e.date <= CURRENT_DATE
      AND e.status IS DISTINCT FROM 'cancelled'
      AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
  ),
  elig AS (
    SELECT count(*) AS eligible_total
    FROM cohort c
    CROSS JOIN LATERAL public._attendance_eligible_events(c.id, p_cycle_start) el
  )
  SELECT jsonb_build_object(
    'scope', p_scope,
    'scope_id', p_scope_id,
    'cohort_n', (SELECT count(*) FROM rates WHERE rate IS NOT NULL),
    'avg_rate', (SELECT ROUND(AVG(rate), 4) FROM rates WHERE rate IS NOT NULL),
    'present_total', (SELECT present_total FROM recorded),
    'absent_total', (SELECT absent_total FROM recorded),
    'excused_total', (SELECT excused_total FROM recorded),
    'eligible_total', (SELECT eligible_total FROM elig),
    'coverage_flag', CASE
      WHEN (SELECT eligible_total FROM elig) = 0 THEN 'no_data'
      WHEN ((SELECT present_total + absent_total + excused_total FROM recorded))::numeric / NULLIF((SELECT eligible_total FROM elig), 0) >= 0.90 THEN 'complete'
      WHEN ((SELECT present_total + absent_total + excused_total FROM recorded))::numeric / NULLIF((SELECT eligible_total FROM elig), 0) >= 0.50 THEN 'partial'
      ELSE 'sparse'
    END
  );
$function$;

-- ============================================================================
-- 5) get_dropout_risk_members — coorte at-risk via junction (SET search_path '' — qualificar tudo)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_dropout_risk_members(p_threshold integer DEFAULT 3)
 RETURNS TABLE(member_id uuid, member_name text, tribe_id integer, tribe_name text, operational_role text, last_attendance_date date, days_since_last bigint, missed_events integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH active_members AS (
    SELECT m.id, m.name, m.tribe_id, t.name AS tname, m.operational_role
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager'))
  ),
  -- canonical eligible events per member; excused removed (D1 neutral); most-recent-first rank
  member_eligible AS (
    SELECT am.id AS mid, el.event_date AS edate,
           (att.present IS TRUE) AS was_present,
           ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY el.event_date DESC, el.event_id DESC) AS rn
    FROM active_members am
    CROSS JOIN LATERAL public._attendance_eligible_events(am.id, NULL) el
    LEFT JOIN public.attendance att ON att.event_id = el.event_id AND att.member_id = am.id
    WHERE att.excused IS NOT TRUE
  ),
  -- of the last p_threshold non-excused eligible events, how many were absent (no present row)
  member_recent AS (
    SELECT me.mid, count(*) FILTER (WHERE NOT me.was_present) AS missed
    FROM member_eligible me
    WHERE me.rn <= p_threshold
    GROUP BY me.mid
  ),
  -- most recent present attendance over the member's full eligible set
  member_last AS (
    SELECT me.mid, max(me.edate) FILTER (WHERE me.was_present) AS last_date
    FROM member_eligible me
    GROUP BY me.mid
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
         ml.last_date,
         (CURRENT_DATE - COALESCE(ml.last_date, DATE '2025-01-01'))::bigint,
         mr.missed::integer
  FROM active_members am
  JOIN member_recent mr ON mr.mid = am.id
  LEFT JOIN member_last ml ON ml.mid = am.id
  WHERE mr.missed >= p_threshold
  ORDER BY ml.last_date ASC NULLS FIRST;
END;
$function$;

-- ============================================================================
-- 6) get_gp_cohort_health — coorte {researcher,tribe_leader} via junction (SEM manager)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_gp_cohort_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_cycle record;
  v_kickoff uuid;
  v_result jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL
          OR NOT (public.can_by_member(v_caller, 'manage_member')
                  OR public.can_by_member(v_caller, 'view_internal_analytics'))) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or view_internal_analytics');
  END IF;

  SELECT cycle_code, cycle_label, cycle_start INTO v_cycle
  FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1;

  -- kickoff da coorte corrente: derivado (NAO hardcoded) — type='kickoff' OU titulo ILIKE '%kick%',
  -- primeiro evento nao-cancelado dentro da janela do ciclo. Em C4 o kickoff foi registrado como
  -- type='geral' com "Kick-off" no titulo, dai o OR por titulo.
  SELECT id INTO v_kickoff
  FROM public.events
  WHERE (type = 'kickoff' OR title ILIKE '%kick%')
    AND date >= v_cycle.cycle_start
    AND status IS DISTINCT FROM 'cancelled'
  ORDER BY date ASC LIMIT 1;

  WITH cohort AS (
    SELECT m.id, m.name, m.chapter,
      EXISTS (SELECT 1 FROM public.v_initiative_roster r
              JOIN public.initiatives i2 ON i2.id = r.initiative_id
              WHERE r.member_id = m.id AND i2.kind = 'research_tribe') AS has_tribe,
      -- #1291: curador / membro de comite (engagement ativo em iniciativa kind='committee') —
      -- tribelessness legitima, nao conta como "sem tribo em risco".
      EXISTS (SELECT 1 FROM public.engagements e
              JOIN public.initiatives ic ON ic.id = e.initiative_id
              WHERE e.person_id = m.person_id AND e.status = 'active' AND ic.kind = 'committee') AS is_committee,
      EXISTS (SELECT 1 FROM public.attendance a
              WHERE a.member_id = m.id AND a.event_id = v_kickoff AND a.present = true) AS at_kickoff,
      EXISTS (SELECT 1 FROM public.gamification_points gp
              WHERE gp.member_id = m.id AND COALESCE(gp.occurred_at, gp.created_at) >= v_cycle.cycle_start) AS has_activity
    FROM public.members m
    WHERE m.member_status = 'active'
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader'))
  ),
  cohort_p AS (
    SELECT c.*, (c.has_tribe OR c.is_committee) AS placed FROM cohort c
  )
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object('code', v_cycle.cycle_code, 'label', v_cycle.cycle_label),
    'kickoff_event_id', v_kickoff,
    'cohort_summary', jsonb_build_object(
      'total',            (SELECT count(*) FROM cohort_p),
      'with_tribe',       (SELECT count(*) FROM cohort_p WHERE has_tribe),
      'committee_members',(SELECT count(*) FROM cohort_p WHERE is_committee),
      'without_tribe',    (SELECT count(*) FROM cohort_p WHERE NOT placed),
      'at_kickoff',       (SELECT count(*) FROM cohort_p WHERE at_kickoff),
      'no_kickoff',       (SELECT count(*) FROM cohort_p WHERE NOT at_kickoff),
      'no_activity',      (SELECT count(*) FROM cohort_p WHERE NOT has_activity)
    ),
    'at_risk_members', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'member_id', c.id, 'name', c.name, 'chapter', c.chapter,
        'is_committee', c.is_committee,
        'no_tribe', NOT c.placed,
        'no_kickoff', NOT c.at_kickoff,
        'no_activity', NOT c.has_activity,
        'risk_count', (CASE WHEN NOT c.placed THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                     + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END)
      ) ORDER BY (CASE WHEN NOT c.placed THEN 1 ELSE 0 END
                + CASE WHEN NOT c.at_kickoff THEN 1 ELSE 0 END
                + CASE WHEN NOT c.has_activity THEN 1 ELSE 0 END) DESC, c.name), '[]'::jsonb)
      FROM cohort_p c
      WHERE NOT c.placed OR NOT c.at_kickoff OR NOT c.has_activity
    ),
    'pending_leader_approvals', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'invitation_id', ii.id,
        'requester_member_id', ii.invitee_member_id,
        'requester_name', rm.name,
        'tribe', init.title,
        'legacy_tribe_id', init.legacy_tribe_id,
        'requested_at', ii.created_at,
        'expires_at', ii.expires_at,
        'days_waiting', EXTRACT(day FROM now() - ii.created_at)::int
      ) ORDER BY ii.created_at), '[]'::jsonb)
      FROM public.initiative_invitations ii
      JOIN public.initiatives init ON init.id = ii.initiative_id
      JOIN public.members rm ON rm.id = ii.invitee_member_id
      WHERE ii.status = 'pending' AND init.kind = 'research_tribe'
        AND ii.invitee_member_id = ii.inviter_member_id
        AND ii.expires_at > now()
    ),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 7) get_cycle_attendance_overview — coorte {researcher,tribe_leader} via junction (ciclo corrente; branch snapshot intocado)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_cycle_attendance_overview(p_cycle_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_is_service boolean;
  v_cycle record;
  v_result jsonb;
BEGIN
  v_is_service := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ) = 'service_role';
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT coalesce(v_is_service, false)
     AND (v_caller IS NULL
          OR NOT (public.can_by_member(v_caller, 'manage_member')
                  OR public.can_by_member(v_caller, 'view_internal_analytics'))) THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member or view_internal_analytics');
  END IF;

  SELECT cycle_code, cycle_label, cycle_start,
         COALESCE(cycle_end, CURRENT_DATE) AS cycle_end_eff, is_current
  INTO v_cycle
  FROM public.cycles
  WHERE cycle_code = COALESCE(p_cycle_code,
    (SELECT cycle_code FROM public.cycles WHERE is_current = true ORDER BY cycle_start DESC LIMIT 1));

  IF v_cycle.cycle_code IS NULL THEN
    RETURN jsonb_build_object('error', 'Cycle not found: ' || COALESCE(p_cycle_code, '(current)'));
  END IF;

  -- coorte: ciclo corrente -> membros ativos; ciclo passado -> snapshot em member_cycle_history
  -- (#1104 governa o roll-forward). attendance espelha a janela/tipos do get_tribe_gamification:
  -- eventos nao-cancelados em ('geral','kickoff','tribo','lideranca'); denominador exclui excused.
  -- #1476 Onda 2: coorte do ciclo corrente por engagement (junction {researcher,tribe_leader}), nao pelo cache.
  WITH cohort AS (
    SELECT m.id AS member_id, m.name, m.chapter, m.tribe_id
    FROM public.members m
    WHERE v_cycle.is_current AND m.member_status = 'active'
      AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                  WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader'))
    UNION
    SELECT mch.member_id, mch.member_name_snapshot, mch.chapter, mch.tribe_id
    FROM public.member_cycle_history mch
    WHERE NOT v_cycle.is_current AND mch.cycle_code = v_cycle.cycle_code AND mch.is_active
  ),
  att AS (
    SELECT a.member_id,
      count(*) FILTER (WHERE a.present = true) AS present_count,
      count(*) FILTER (WHERE a.present IS NOT TRUE AND a.excused IS NOT TRUE) AS absent_count,
      count(*) FILTER (WHERE a.excused = true) AS excused_count,
      count(*) FILTER (WHERE a.excused IS NOT TRUE) AS eligible_count
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
    WHERE e.date >= v_cycle.cycle_start AND e.date <= v_cycle.cycle_end_eff
      AND e.status IS DISTINCT FROM 'cancelled'
      AND e.type IN ('geral', 'kickoff', 'tribo', 'lideranca')
    GROUP BY a.member_id
  )
  SELECT jsonb_build_object(
    'cycle', jsonb_build_object('code', v_cycle.cycle_code, 'label', v_cycle.cycle_label,
       'start', v_cycle.cycle_start, 'end', v_cycle.cycle_end_eff, 'is_current', v_cycle.is_current),
    'total_members', (SELECT count(*) FROM cohort),
    'members', coalesce(jsonb_agg(jsonb_build_object(
       'member_id', c.member_id, 'name', c.name, 'chapter', c.chapter, 'tribe_id', c.tribe_id,
       'present', coalesce(att.present_count, 0),
       'absent', coalesce(att.absent_count, 0),
       'excused', coalesce(att.excused_count, 0),
       'eligible', coalesce(att.eligible_count, 0),
       'attendance_rate', CASE WHEN coalesce(att.eligible_count, 0) > 0
          THEN round(att.present_count::numeric / att.eligible_count, 2) ELSE NULL END
     ) ORDER BY coalesce(att.present_count, 0) ASC, c.name), '[]'::jsonb),
    'generated_at', now()
  ) INTO v_result
  FROM cohort c
  LEFT JOIN att ON att.member_id = c.member_id;

  RETURN v_result;
END;
$function$;

-- ============================================================================
-- 8) _credly_health_rows — coorte {researcher,tribe_leader,manager,deputy_manager} via junction
-- ============================================================================
CREATE OR REPLACE FUNCTION public._credly_health_rows()
 RETURNS TABLE(kind text, member_id uuid, member_name text, papel text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT 'missing_link'::text, m.id, m.name, m.operational_role
  FROM public.members m
  WHERE m.is_active = true
    AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
                WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader','manager','deputy_manager'))
    AND (m.credly_url IS NULL OR m.credly_url = '')
  UNION ALL
  SELECT 'never_verified'::text, m.id, m.name, m.operational_role
  FROM public.members m
  WHERE m.is_active = true AND m.credly_url IS NOT NULL AND m.credly_url <> ''
    AND m.credly_verified_at IS NULL
  UNION ALL
  SELECT 'no_badges'::text, m.id, m.name, m.operational_role
  FROM public.members m
  WHERE m.is_active = true AND m.credly_url IS NOT NULL AND m.credly_url <> ''
    AND m.credly_verified_at IS NOT NULL
    AND (m.credly_badges IS NULL OR jsonb_typeof(m.credly_badges) <> 'array' OR jsonb_array_length(m.credly_badges) = 0);
$function$;

-- ============================================================================
-- 9) admin_get_anomaly_report — Rule 7 (BAIXA): coorte sem-tribo via junction {researcher,tribe_leader}
--    (as demais Rules intocadas; communicator/facilitator eram literais mortos do cache -> mapeiam a researcher)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_get_anomaly_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_live_anomalies jsonb := '[]'::jsonb;
  v_count int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'Unauthorized'); END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Rule 1: Active members without current cycle tag
  SELECT count(*) INTO v_count FROM members
  WHERE is_active = true AND current_cycle_active = true
  AND (cycles IS NULL OR array_length(cycles, 1) IS NULL OR NOT ('cycle3-2026' = ANY(cycles)));
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'active_without_cycle', 'severity', 'warning',
      'description', v_count || ' membros ativos sem tag cycle3-2026', 'count', v_count);
  END IF;

  -- Rule 2: Orphan tribe_id
  SELECT count(*) INTO v_count FROM members m
  WHERE m.is_active = true AND m.tribe_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tribes t WHERE t.id = m.tribe_id);
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'orphan_tribe_id', 'severity', 'critical',
      'description', v_count || ' membros com tribe_id inexistente', 'count', v_count);
  END IF;

  -- Rule 3: Events without attendance (exclude interviews/1on1, only >3 days old)
  SELECT count(*) INTO v_count FROM events e
  WHERE e.date < current_date - 3 AND e.date >= '2026-01-01'
  AND e.type NOT IN ('entrevista', '1on1')
  AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.event_id = e.id);
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'events_no_attendance', 'severity', 'warning',
      'description', v_count || ' eventos (tribo/geral) sem registro de presença', 'count', v_count);
  END IF;

  -- Rule 4: Duplicate emails
  SELECT count(*) INTO v_count FROM (
    SELECT lower(email) FROM members WHERE email IS NOT NULL GROUP BY lower(email) HAVING count(*) > 1
  ) sub;
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'duplicate_emails', 'severity', 'critical',
      'description', v_count || ' emails duplicados na tabela members', 'count', v_count);
  END IF;

  -- Rule 5: Active but offboarded
  SELECT count(*) INTO v_count FROM members WHERE is_active = true AND offboarded_at IS NOT NULL;
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'active_but_offboarded', 'severity', 'critical',
      'description', v_count || ' membros ativos com data de offboarding', 'count', v_count);
  END IF;

  -- Rule 6: Stale partner follow-ups
  SELECT count(*) INTO v_count FROM partner_entities
  WHERE follow_up_date IS NOT NULL AND follow_up_date < current_date - 7
  AND status NOT IN ('active', 'declined', 'inactive');
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'stale_partner_followups', 'severity', 'info',
      'description', v_count || ' parceiros com follow-up vencido >7 dias', 'count', v_count);
  END IF;

  -- Rule 7: Members without tribe assignment (operational roles only)
  -- #1476 Onda 2: coorte operacional por engagement (junction {researcher,tribe_leader}), nao pelo cache.
  SELECT count(*) INTO v_count FROM members m
  WHERE m.is_active = true AND m.current_cycle_active = true AND m.tribe_id IS NULL
  AND EXISTS (SELECT 1 FROM public.v_member_operational_tiers vt
              WHERE vt.member_id = m.id AND vt.operational_tier IN ('researcher','tribe_leader'));
  IF v_count > 0 THEN
    v_live_anomalies := v_live_anomalies || jsonb_build_object(
      'rule', 'no_tribe_assigned', 'severity', 'warning',
      'description', v_count || ' pesquisadores/líderes ativos sem tribo atribuída', 'count', v_count);
  END IF;

  SELECT jsonb_build_object(
    'live_detection', v_live_anomalies,
    'pending', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', d.id, 'anomaly_type', d.anomaly_type, 'severity', d.severity,
        'description', d.description, 'context', d.context, 'detected_at', d.detected_at
      ) ORDER BY CASE d.severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END, d.detected_at DESC)
      FROM public.data_anomaly_log d WHERE d.auto_fixed = false
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total_live', jsonb_array_length(v_live_anomalies),
      'total_logged_pending', (SELECT count(*) FROM public.data_anomaly_log WHERE auto_fixed = false),
      'total_fixed', (SELECT count(*) FROM public.data_anomaly_log WHERE auto_fixed = true)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
