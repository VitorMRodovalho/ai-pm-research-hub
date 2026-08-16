-- #1805 — literal de estado fora do dominio do CHECK: o ramo nao erra, ele nunca casa.
--
-- Classe varrida a partir do CATALOGO (nao da lista da issue). A issue nomeava 3 funcoes; a
-- varredura sobre as 91 colunas de estado cujo NOME pertence a uma unica tabela em public achou
-- mais uma, `approve_selection_application`, que nao estava na lista de ninguem.
--
-- Por que so colunas de nome unico: a ambiguidade e sobre a TABELA, e o nome da coluna esta no
-- texto. Quando o nome pertence a uma unica tabela, alias nenhum muda a resposta. Para `status`,
-- que existe em ~50 tabelas com dominios proprios, a varredura textual NAO se sustenta (medido:
-- 58 candidatos, quase todos com o literal pertencendo a uma tabela vizinha) — por isso os dois
-- casos de `status` abaixo entram por LEITURA do corpo, nao por varredura, e ficam fora do ratchet.
--
-- Medido em 16/08/2026, no banco, com os 3 crons ATIVOS:
--
--   recompute_all_active_pert_cutoffs  (semanal, seg 13:00 UTC)
--     phase IN (..., 'open_apps') — 'open_apps' NAO existe; o valor real e 'applications_open'.
--     Efeito: ciclo com inscricoes abertas nunca tem os cortes PERT recalculados.
--
--   compute_ai_calibration_weekly      (semanal, seg 14:00 UTC)
--     status IN ('open','evaluating','decided','closed') — 'evaluating' e vocabulario de phase e
--     'decided' nao existe em dominio nenhum; 4 estados reais nunca casavam.
--     Efeito medido: 0 hoje, mas cycle4-2026 (45 candidaturas pontuadas) SAI da varredura assim
--     que o GP avancar o status de 'open' para 'evaluation'.
--
--   selection_consistency_report + _selection_consistency_cron  (diario, 13:30 UTC)
--     status IN ('open','active') — 'active' e literal morto, entao o predicado valia 'open'
--     sozinho, e o comentario vivo dizia querer "never alarm on closed cycles".
--     Efeito medido: 81 candidaturas vigiadas hoje, que iriam a 0 no mesmo avanco.
--
--   approve_selection_application
--     role_applied IN (..., 'coordinator', ...) — fora do dominio; ramo morto puro, sem efeito.
--
-- Decisao do PM (16/08): o predicado passa a exprimir a INTENCAO declarada no proprio codigo, e
-- nao a lista de estados de hoje — calibracao quer historico (tudo menos rascunho), consistencia
-- quer ciclo em andamento (tudo menos rascunho e fechado). Assim um estado novo no CHECK nasce
-- dentro da varredura, em vez de fora e calado, que e a classe inteira desta issue.

CREATE OR REPLACE FUNCTION public.recompute_all_active_pert_cutoffs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_cycle record;
  v_results jsonb := '[]'::jsonb;
  v_n int := 0;
  v_result_obj jsonb;
  v_result_le jsonb;
  v_result_fs_researcher jsonb;
  v_result_fs_leader jsonb;
BEGIN
  FOR v_cycle IN
    SELECT id, cycle_code, phase FROM public.selection_cycles
    -- #1805: era 'open_apps', que NAO existe no dominio do CHECK de phase
    -- (o valor real e 'applications_open'). O ramo nunca casava, calado, e um
    -- ciclo com inscricoes abertas nunca tinha os cortes PERT recalculados.
    WHERE phase IN ('evaluating', 'interviews', 'applications_open')
    ORDER BY created_at DESC
  LOOP
    v_result_obj := public._compute_pert_cutoff_core(v_cycle.id, 'researcher', true, 'objective_score_avg', NULL);
    v_result_le := public._compute_pert_cutoff_core(v_cycle.id, 'leader', true, 'leader_extra_pert_score', NULL);
    v_result_fs_researcher := public._compute_pert_cutoff_core(v_cycle.id, 'researcher', true, 'final_score', NULL);
    v_result_fs_leader := public._compute_pert_cutoff_core(v_cycle.id, 'leader', true, 'final_score', NULL);
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'cycle_code', v_cycle.cycle_code,
      'phase', v_cycle.phase,
      'objective_result', v_result_obj,
      'leader_extra_result', v_result_le,
      'final_score_researcher_result', v_result_fs_researcher,
      'final_score_leader_result', v_result_fs_leader
    ));
    v_n := v_n + 1;
  END LOOP;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'pert_cutoff_recompute_batch', 'selection_cycles', NULL,
    jsonb_build_object('cycles_processed', v_n, 'per_cycle', v_results),
    jsonb_build_object(
      'source', 'recompute_all_active_pert_cutoffs',
      'dimensions', jsonb_build_array('objective', 'leader_extra', 'final_score_researcher', 'final_score_leader')
    )
  );

  RETURN jsonb_build_object('success', true, 'cycles_processed', v_n, 'per_cycle', v_results);
END;
$$;

CREATE OR REPLACE FUNCTION public.compute_ai_calibration_weekly()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_cycle record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_total_cycles integer := 0;
  v_cron_context boolean;
BEGIN
  v_cron_context := (current_setting('role', true) IN ('service_role','postgres')
                     OR current_user IN ('postgres','supabase_admin'));

  IF NOT v_cron_context THEN
    RAISE EXCEPTION 'Unauthorized: cron-only (called by pg_cron)';
  END IF;

  FOR v_cycle IN
    SELECT id, cycle_code FROM public.selection_cycles
    -- #1805: a lista anterior misturava vocabulario de phase com o de status
    -- (dois literais nao existiam no dominio do CHECK de status), e por isso
    -- quatro estados reais nunca casavam. A intencao e historica -- calibrar
    -- todo ciclo que ja tenha candidatura pontuada, inclusive fechado --, entao
    -- o predicado passa a excluir apenas o rascunho, e sobrevive a crescimento
    -- do dominio. O gate real de escopo e o EXISTS abaixo.
    WHERE status <> 'draft'
      AND EXISTS (
        SELECT 1 FROM public.selection_applications a
        WHERE a.cycle_id = selection_cycles.id
          AND a.ai_triage_score IS NOT NULL
          AND a.final_score IS NOT NULL
      )
    ORDER BY created_at DESC
  LOOP
    v_result := public.compute_ai_calibration_stats(v_cycle.id, 2.0);
    v_results := v_results || jsonb_build_array(v_result);
    v_total_cycles := v_total_cycles + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'cycles_processed', v_total_cycles,
    'per_cycle', v_results,
    'ran_at', now()
  );
END;
$func$;

CREATE OR REPLACE FUNCTION public.selection_consistency_report(p_cycle_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_pre_interview text[] := ARRAY['submitted','screening','objective_eval','objective_cutoff'];
  v_decided text[] := ARRAY['final_eval','interview_done','approved','rejected','converted',
                            'withdrawn','cancelled','waitlist','interview_noshow'];
  v_a jsonb; v_b jsonb; v_c jsonb; v_d jsonb; v_e jsonb; v_disp jsonb;
  v_a_n int; v_b_n int; v_c_n int; v_d_n int; v_e_n int; v_disp_n int;
  v_distinct_apps int;  -- DISTINCT applications across A/B/C/D (B ⊆ D → a plain sum double-counts)
BEGIN
  -- Auth: authenticated callers need manage_platform; a no-JWT context
  -- (pg_cron / service_role) is the self-running path and is allowed.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: manage_platform required';
    END IF;
  END IF;

  -- Ciclos EM ANDAMENTO (ou o pedido), para nunca alarmar sobre ciclo fechado.
  -- #1805: o predicado era uma lista com o literal 'active', que nao existe no
  -- dominio do CHECK de status. Na pratica ele valia 'open' sozinho, e um ciclo
  -- avancado para evaluation/interview/decision saia INTEIRO do escopo -- o
  -- relatorio ficava cego justamente na fase em que a inconsistencia aparece.
  -- Medido em 16/08/2026: 81 candidaturas vigiadas, que iriam a 0 no avanco.
  -- a. scored but not advanced past a final/decided stage
  WITH oa AS (
    SELECT a.* FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status NOT IN ('draft','closed')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
  ),
  rows_a AS (
    SELECT a.id, a.applicant_name, a.status, a.interview_score
    FROM oa a
    WHERE a.interview_score IS NOT NULL
      AND a.status <> ALL (v_decided)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_a_n, v_a
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_a) r;

  -- b. completed/conducted interview row but app still pre-interview
  WITH rows_b AS (
    SELECT DISTINCT a.id, a.applicant_name, a.status
    FROM public.selection_interviews si
    JOIN public.selection_applications a ON a.id = si.application_id
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status NOT IN ('draft','closed')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND (si.status = 'completed' OR si.conducted_at IS NOT NULL)
      AND a.status = ANY (v_pre_interview)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_b_n, v_b
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_b) r;

  -- c. status interview_scheduled/interview_done but NO interview row
  --    (final_eval excluded — manual off-platform final is legitimate)
  WITH rows_c AS (
    SELECT a.id, a.applicant_name, a.status
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status NOT IN ('draft','closed')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND a.status IN ('interview_scheduled','interview_done')
      AND NOT EXISTS (SELECT 1 FROM public.selection_interviews si WHERE si.application_id = a.id)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_c_n, v_c
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_c) r;

  -- d. live interview row but app still pre-interview (orphan)
  WITH rows_d AS (
    SELECT DISTINCT a.id, a.applicant_name, a.status
    FROM public.selection_interviews si
    JOIN public.selection_applications a ON a.id = si.application_id
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status NOT IN ('draft','closed')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
      AND si.status NOT IN ('cancelled','noshow')
      AND a.status = ANY (v_pre_interview)
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.applicant_name) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_d_n, v_d
  FROM (SELECT *, row_number() OVER (ORDER BY applicant_name) AS rn FROM rows_d) r;

  -- e. calendar bookings that matched NO application in the last 7 days.
  --    #1611: isto contava LINHAS de admin_audit_log, e o webhook gravava uma
  --    linha por retentativa do Apps Script (5 em 5 min) — de modo que UMA
  --    reserva órfã inflava a manchete em milhares. Medido em 2026-08-05, antes
  --    da correção: integrity_anomaly_total = 3.278, com
  --    affected_applications_distinct = 0. A anomalia inteira era ruído de log.
  --    Passa a ler o contador por (evento, convidado) do #1609, e SÓ o desfecho
  --    acionável: `no_application`. Uma reserva recusada porque a candidatura já
  --    foi decidida (status_not_allowed) ou porque o ciclo fechou (cycle_closed)
  --    é a plataforma FUNCIONANDO — não é anomalia e não entra aqui.
  WITH rows_e AS (
    SELECT ba.calendar_event_id,
           ba.guest_email,
           ba.attempts,
           ba.first_seen_at,
           ba.last_seen_at AS created_at
    FROM public.selection_booking_attempts ba
    WHERE ba.last_outcome = 'no_application'
      AND ba.resolved_at IS NULL
      AND ba.last_seen_at >= now() - interval '7 days'
  )
  SELECT count(*), COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FILTER (WHERE r.rn <= 10), '[]'::jsonb)
  INTO v_e_n, v_e
  FROM (SELECT *, row_number() OVER (ORDER BY created_at DESC) AS rn FROM rows_e) r;

  -- DISTINCT affected applications across A/B/C/D — the human-facing "how many
  -- candidates are broken". The per-class counts above overlap (B ⊆ D: every
  -- completed/conducted row is also a live row), so summing them would double-count
  -- a single broken application. This recomputes the same predicates as a set.
  WITH oa AS (
    SELECT a.id, a.status, a.interview_score
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE c.status NOT IN ('draft','closed')
      AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
  ),
  iv AS (
    SELECT si.application_id,
           bool_or(si.status = 'completed' OR si.conducted_at IS NOT NULL) AS has_done,
           bool_or(si.status NOT IN ('cancelled','noshow'))                AS has_live
    FROM public.selection_interviews si
    GROUP BY si.application_id
  )
  SELECT count(DISTINCT o.id) INTO v_distinct_apps
  FROM oa o
  LEFT JOIN iv ON iv.application_id = o.id
  WHERE (o.interview_score IS NOT NULL AND o.status <> ALL (v_decided))                          -- A
     OR (COALESCE(iv.has_done, false) AND o.status = ANY (v_pre_interview))                       -- B
     OR (o.status IN ('interview_scheduled','interview_done') AND iv.application_id IS NULL)      -- C
     OR (COALESCE(iv.has_live, false) AND o.status = ANY (v_pre_interview));                      -- D

  -- dispatch gap — INFORMATIONAL ONLY (the campaign path bypasses dispatch_url_log).
  -- Scoped to interview_pending/interview_scheduled — the statuses where the link is
  -- still operationally needed; interview_done/final_eval are excluded because the
  -- interview already occurred so a missing dispatch row there is stale history.
  SELECT count(*) INTO v_disp_n
  FROM public.selection_applications a
  JOIN public.selection_cycles c ON c.id = a.cycle_id
  WHERE c.status NOT IN ('draft','closed')
    AND (p_cycle_id IS NULL OR a.cycle_id = p_cycle_id)
    AND a.status IN ('interview_pending','interview_scheduled')
    AND NOT EXISTS (SELECT 1 FROM public.selection_dispatch_url_log d WHERE d.application_id = a.id);
  v_disp := jsonb_build_object(
    'count', v_disp_n,
    'note', 'INFORMATIONAL — interview links may have gone out via the email campaign '
            || '(campaign_recipients/Resend), which does not write selection_dispatch_url_log. '
            || 'Not an alert; cross-check campaign delivery before acting.'
  );

  RETURN jsonb_build_object(
    'success', true,
    'scope', COALESCE(p_cycle_id::text, 'all running cycles (not draft/closed)'),
    'integrity_anomalies', jsonb_build_object(
      'scored_not_advanced',            jsonb_build_object('count', v_a_n, 'samples', v_a),
      'interview_completed_app_behind', jsonb_build_object('count', v_b_n, 'samples', v_b),
      'interview_phase_no_row',         jsonb_build_object('count', v_c_n, 'samples', v_c),
      'orphan_interview_row',           jsonb_build_object('count', v_d_n, 'samples', v_d),
      'unmatched_calendar_bookings_7d', jsonb_build_object('count', v_e_n, 'samples', v_e)
    ),
    'dispatch_gap_informational', jsonb_build_object('qualified_no_dispatch_log', v_disp),
    -- total = DISTINCT broken applications (A/B/C/D, deduplicated — B ⊆ D) + unmatched
    -- bookings (E, which are bookings, not applications, so additive). The per-class
    -- counts above are an overlapping breakdown; this is the non-double-counted headline.
    'affected_applications_distinct', v_distinct_apps,
    'integrity_anomaly_total', (v_distinct_apps + v_e_n),
    'has_integrity_anomaly', (v_distinct_apps + v_e_n) > 0
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public._selection_consistency_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_report jsonb;
  v_total int;
  v_lead record;
  v_summary text;
BEGIN
  v_report := public.selection_consistency_report(NULL);
  v_total := COALESCE((v_report->>'integrity_anomaly_total')::int, 0);

  -- always record the report (observability) — admin-scoped audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.consistency_check', 'system', NULL,
    jsonb_build_object('integrity_anomaly_total', v_total),
    v_report
  );

  -- alert leads ONLY on high-confidence integrity anomalies (never on the dispatch gap)
  IF v_total > 0 THEN
    v_summary := v_total || ' anomalia(s) de integridade na pipeline de seleção '
      || '(candidato pontuado sem avançar / entrevista concluída com app atrás / '
      || 'fase de entrevista sem linha / linha órfã / agendamento sem match). '
      || 'Detalhes no relatório (admin_audit_log selection.consistency_check). Revise em /admin/selection.';

    FOR v_lead IN
      SELECT DISTINCT sc.member_id
      FROM public.selection_committee sc
      JOIN public.selection_cycles c ON c.id = sc.cycle_id
      -- #1805: mesmo predicado do relatorio -- ciclo em andamento e todo o que
      -- nao e rascunho nem fechado. Antes, o literal morto 'active' fazia isto
      -- valer 'open' apenas, e nenhum lead era avisado de ciclo em avaliacao.
      WHERE c.status NOT IN ('draft','closed')
        AND sc.role = 'lead'
        AND sc.member_id IS NOT NULL
    LOOP
      -- 7-arg overload: (p_recipient_id, p_type, p_title, p_body, p_link, p_source_type, p_source_id)
      PERFORM public.create_notification(
        v_lead.member_id,
        'selection_consistency_anomaly',
        'Inconsistências detectadas na pipeline de seleção',
        v_summary,
        '/admin/selection',
        'system',
        NULL::uuid
      );
    END LOOP;
  END IF;

  RETURN v_report;
END;
$function$;

CREATE OR REPLACE FUNCTION public._audit_state_literal_domain()
RETURNS TABLE(funcao text, args text, coluna text, literal text, tabela_dona text, fora_do_dominio boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH allcols AS MATERIALIZED (
    SELECT c.oid AS reloid, c.relname::text AS tbl, a.attname::text AS col, a.attnum
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
  ),
  owners AS MATERIALIZED (
    SELECT col, min(reloid) AS reloid, min(tbl) AS tbl, min(attnum) AS attnum
    FROM allcols
    GROUP BY col
    HAVING count(*) = 1
  ),
  chk AS MATERIALIZED (
    SELECT o.col, min(o.tbl) AS tbl, string_agg(pg_get_constraintdef(ct.oid), ' ') AS def
    FROM owners o
    JOIN pg_constraint ct
      ON ct.conrelid = o.reloid AND ct.contype = 'c' AND ct.conkey = ARRAY[o.attnum]::int2[]
    WHERE pg_get_constraintdef(ct.oid) ~ '= ANY \(ARRAY\['
      AND pg_get_constraintdef(ct.oid) !~ '(jsonb|numeric|integer|->>|~)'
    GROUP BY o.col
  ),
  dom AS MATERIALIZED (
    SELECT col, (regexp_matches(def, '''([a-z_0-9-]+)''::text', 'g'))[1] AS allowed FROM chk
  ),
  fn AS MATERIALIZED (
    SELECT p.proname::text AS nm,
           pg_get_function_identity_arguments(p.oid) AS fargs,
           regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g') AS src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname <> '_audit_state_literal_domain'
  ),
  pairs AS MATERIALIZED (
    SELECT f.nm, f.fargs, (m)[1] AS col, (m)[2] AS lit
    FROM fn f, regexp_matches(f.src, '\y([a-z_][a-z0-9_]{0,62})\s*=\s*''([a-z_0-9-]{0,60})''', 'g') AS m
    UNION
    SELECT f.nm, f.fargs, (m)[1], (regexp_matches((m)[2], '''([a-z_0-9-]*)''', 'g'))[1]
    FROM fn f, regexp_matches(f.src, '\y([a-z_][a-z0-9_]{0,62})\s+IN\s*\(([^)]{0,250})\)', 'g') AS m
  )
  SELECT p.nm, p.fargs, p.col, p.lit, k.tbl,
         NOT EXISTS (SELECT 1 FROM dom d WHERE d.col = p.col AND d.allowed = p.lit)
  FROM pairs p
  JOIN chk k ON k.col = p.col
  WHERE p.lit <> ''
  ORDER BY 6 DESC, 1, 3, 4;
$function$;

COMMENT ON FUNCTION public._audit_state_literal_domain() IS
  'Ratchet do #1805. Acha literal de estado comparado a uma coluna cujo dominio e fixado por CHECK, quando o literal NAO esta no dominio: o ramo nao erra, ele nunca casa, calado. Derivado do catalogo, nao de lista de nomes. Cobre apenas colunas cujo NOME pertence a UMA UNICA tabela em public -- ai a pergunta "de qual tabela e esta coluna" nao existe, e alias nenhum muda a resposta. Colunas de nome compartilhado (status e o caso grande) ficam FORA de proposito: um texto nao diz de qual tabela e a coluna, e varrer por regex ali produz falso positivo em massa (medido: 58 candidatos, quase todos de tabela vizinha). Devolve TODOS os pares examinados, com fora_do_dominio, para que lista vazia seja distinguivel de guard cego.';

REVOKE ALL ON FUNCTION public._audit_state_literal_domain() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_state_literal_domain() TO service_role;
