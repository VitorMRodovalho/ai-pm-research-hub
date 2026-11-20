-- #3105: a fila de filiacao passa a ser o portao fechado.
--
-- Fatia 1 da consolidacao dos fluxos de filiacao (relatorio da lane arquitetura-filiacao, decisao do GP em 20/11/2026:
-- so pede confirmacao humana o que a regra de negocio nao validou).
--
-- Antes: get_affiliation_verification_queue (escopo padrao) e get_affiliation_chapter_rollup escolhiam a coorte por
-- "pre-onboarding OU pmi_id_verified = false OU nenhuma linha em member_affiliation_verifications". O portao do termo
-- (affiliation_gate) le outra coisa. Medido em 20/11/2026, entre os voluntarios com vinculo ativo: 18 com o portao
-- aberto estavam na fila (a VEP ja tinha validado; 17 so porque nunca tiveram verificacao manual), e 1 com o portao
-- fechado estava fora.
--
-- Esta migration:
--   1) cria affiliation_needs_review(member_id): vinculo ativo de um tipo que exige termo E affiliation_gate fechado.
--      O portao cru, nao o do primeiro termo: quem ja assinou e perdeu a filiacao verificada tambem precisa de olhar.
--      Nao cria regra de filiacao nova; so diz a quem o portao se aplica;
--   2) get_affiliation_verification_queue: corpo = captura 20261017171858 (md5 do corpo normalizado conferido contra o
--      vivo em 20/11/2026), com o predicado da coorte trocado pela funcao e o campo 'affiliation_gate' em cada linha.
--      O escopo 'all' nao muda;
--   3) get_affiliation_chapter_rollup: corpo = captura 20260805000436 (md5 conferido no mesmo dia), com in_queue pela
--      mesma funcao.
--
--   4) get_volunteers_with_closed_affiliation_gate (#3101) sai: a fila a absorve (mesma audiencia, mesmo portao cru,
--      agora com o motivo em cada linha). Ela nao tem chamador: o painel que a lia saiu da #3101 antes do merge
--      (f33b611e), e nenhuma funcao SQL, EF, worker ou script a chama (medido em 20/11/2026).
--
-- Rollback: recriar as duas funcoes pelas capturas 20261017171858 e 20260805000436, recriar
-- get_volunteers_with_closed_affiliation_gate pela captura da #3101 (20261120043026) com os grants de la, e DROP
-- FUNCTION public.affiliation_needs_review(uuid).

-- 1) quem precisa de verificacao humana, num lugar so
CREATE OR REPLACE FUNCTION public.affiliation_needs_review(p_member_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
           SELECT 1
           FROM public.members m
           JOIN public.engagements e ON e.person_id = m.person_id AND e.status = 'active'
           JOIN public.engagement_kinds ek ON ek.slug = e.kind AND ek.requires_agreement IS TRUE
           WHERE m.id = p_member_id
         )
     AND NOT COALESCE((public.affiliation_gate(p_member_id) ->> 'open')::boolean, false);
$function$;

-- Interna: le o portao de qualquer pessoa. So as leitoras SECURITY DEFINER (fila e rollup) a chamam.
REVOKE ALL ON FUNCTION public.affiliation_needs_review(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_needs_review(uuid) TO service_role;

-- 2) a fila
CREATE OR REPLACE FUNCTION public.get_affiliation_verification_queue(p_scope text DEFAULT 'queue'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_result              jsonb;
  v_member_ids          uuid[];
  v_current_cycle_id    uuid;
  v_term_soon_days      int := 180;  -- ~one renewal cycle (cycle_4.cycle_end open); raw date also surfaced
BEGIN
  -- Auth-resolve + function-anchored gate (mirror verify_member_affiliation, mig 148).
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- Least-privilege: read audience == write audience (filiacao_director OR manage_member).
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  -- Current selection cycle, tied to the current operational cycle by number (dynamic — no hardcoded
  -- cycle_code; survives C4→C5). selection_cycles has no is_current column; two selection rows can be
  -- status='open' at once, so we anchor on cycles.is_current, then take the latest open_date.
  SELECT sc.id INTO v_current_cycle_id
  FROM public.selection_cycles sc
  WHERE regexp_replace(sc.cycle_code, '\D', '', 'g')
        LIKE (SELECT regexp_replace(c.cycle_code, '\D', '', 'g') FROM public.cycles c WHERE c.is_current LIMIT 1) || '%'
  ORDER BY sc.open_date DESC NULLS LAST
  LIMIT 1;

  WITH cohort AS (
    SELECT
      m.id  AS member_id,
      m.name,
      m.email,
      m.chapter,
      m.operational_role,
      m.pmi_id_verified,
      COALESCE(pre.flag, false)  AS is_pre_onboarding,
      vep.vep_status_raw,
      vep.vep_last_seen_at,
      vep.pmi_memberships,
      vep.pmi_id,
      vep.service_first_start_date,
      vep.service_latest_end_date,
      vep.service_history_count,
      vep.pmi_data_fetched_at,
      aff.created_at            AS aff_created_at,
      aff.membership_active     AS aff_membership_active,
      aff.membership_expires_on AS aff_membership_expires_on,
      aff.method                AS aff_method,
      aff.chapter_verified      AS aff_chapter_verified,
      -- #1129 cohort (by email set; current-cycle preferred)
      sel.sel_cycle_code,
      sel.sel_role,
      sel.sel_is_current,
      sel.has_selection,
      -- #1129 term validity
      term.term_end_date,
      term.term_signed,
      -- #1192 SSOT chapter read-through
      aff2.chapter_affiliations,
      -- #1995 jornada de onboarding (fatia 1)
      ob.onboarding,
      -- #1995 fatia 1b: tribo pela coluna que confere com o engajamento volunteer
      m.tribe_id,
      tr.name AS tribe_name
    FROM public.members m
    LEFT JOIN public.tribes tr ON tr.id = m.tribe_id
    -- VEP + PMI membership detail from the latest matching application (shape from admin_list_members).
    LEFT JOIN LATERAL (
      SELECT a.vep_status_raw, a.vep_last_seen_at, a.pmi_memberships,
             a.pmi_id, a.service_first_start_date, a.service_latest_end_date,
             a.service_history_count, a.pmi_data_fetched_at
      FROM public.selection_applications a
      WHERE lower(a.email) = lower(m.email)
        AND a.vep_status_raw IS NOT NULL
      ORDER BY a.vep_last_seen_at DESC NULLS LAST
      LIMIT 1
    ) vep ON true
    -- #625 C0 pre-onboarding flag — VERBATIM from admin_list_members (mig 148).
    LEFT JOIN LATERAL (
      SELECT (
        m.member_status = 'active'
        AND EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.engagement_kinds ek ON ek.slug = e.kind
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND (ek.requires_agreement IS NOT TRUE OR e.agreement_certificate_id IS NOT NULL)
        )
      ) AS flag
    ) pre ON true
    -- Latest verification from the append-only trail.
    LEFT JOIN LATERAL (
      SELECT mav.created_at, mav.membership_active, mav.membership_expires_on,
             mav.method, mav.chapter_verified
      FROM public.member_affiliation_verifications mav
      WHERE mav.member_id = m.id
      ORDER BY mav.created_at DESC
      LIMIT 1
    ) aff ON true
    -- #1129 cohort: most-relevant approved/converted selection application across the member's full
    -- email set (primary + member_emails), preferring the current cycle. NULL row ⇒ non_selection.
    LEFT JOIN LATERAL (
      SELECT sc.cycle_code                     AS sel_cycle_code,
             a.role_applied                    AS sel_role,
             (a.cycle_id = v_current_cycle_id) AS sel_is_current,
             true                              AS has_selection
      FROM public.selection_applications a
      JOIN public.selection_cycles sc ON sc.id = a.cycle_id
      WHERE a.status IN ('approved','converted')
        AND ( lower(a.email) = lower(m.email)
              OR lower(a.email) IN (SELECT lower(me.email) FROM public.member_emails me WHERE me.member_id = m.id) )
      ORDER BY (a.cycle_id = v_current_cycle_id) DESC, sc.open_date DESC NULLS LAST
      LIMIT 1
    ) sel ON true
    -- #1129 term boundary: the active agreement-requiring engagement's end_date (volunteer term).
    LEFT JOIN LATERAL (
      SELECT e.end_date AS term_end_date,
             -- #2720: o termo só conta como Vigente/Vencendo/Vencido quando está assinado
             (e.agreement_certificate_id IS NOT NULL) AS term_signed
      FROM public.engagements e
      JOIN public.engagement_kinds ek ON ek.slug = e.kind
      WHERE e.person_id = m.person_id
        AND e.status = 'active'
        AND ek.requires_agreement = true
      ORDER BY e.end_date DESC NULLS LAST,
               -- #2720: no empate de data, o vínculo assinado decide (em 17/10, 4 pessoas tinham um de cada, e a
               -- escolha sem desempate fazia o status mudar de uma chamada para outra)
               (e.agreement_certificate_id IS NOT NULL) DESC
      LIMIT 1
    ) term ON true
    -- #1192 chapter_affiliations: SSOT rows (member_chapter_affiliations × chapter_registry) with the
    -- matching raw membership's expiry paired via resolve_br_chapter_code, UNION raw names that resolve
    -- via the registry but have no SSOT row yet ('vep_raw', provisional). ALL name→code resolution runs
    -- here, in the one SSOT resolver — the client never re-parses names to decide anything.
    LEFT JOIN LATERAL (
      SELECT jsonb_agg(x.obj ORDER BY x.is_primary DESC, x.chapter_code) AS chapter_affiliations
      FROM (
        SELECT mca.chapter_code, mca.is_primary,
               jsonb_build_object(
                 'chapter_code', mca.chapter_code,
                 'chapter_label', cr.state,
                 'source', mca.source,
                 'verified_at', mca.verified_at,
                 'is_primary', mca.is_primary,
                 'raw_name', raw.raw_name,
                 'expiry', raw.expiry
               ) AS obj
        FROM public.member_chapter_affiliations mca
        JOIN public.chapter_registry cr
          ON cr.chapter_code = mca.chapter_code AND cr.is_active = true
        LEFT JOIN LATERAL (
          SELECT CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END AS raw_name,
                 CASE WHEN jsonb_typeof(e) = 'string' THEN NULL ELSE e->>'expiryDate' END AS expiry
          FROM jsonb_array_elements(COALESCE(vep.pmi_memberships, '[]'::jsonb)) e
          WHERE public.resolve_br_chapter_code(
                  CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END
                ) = mca.chapter_code
          LIMIT 1
        ) raw ON true
        WHERE mca.person_id = m.person_id
        UNION ALL
        SELECT rr.code, false,
               jsonb_build_object(
                 'chapter_code', rr.code,
                 'chapter_label', cr2.state,
                 'source', 'vep_raw',
                 'verified_at', NULL,
                 'is_primary', false,
                 'raw_name', rr.raw_name,
                 'expiry', rr.expiry
               )
        FROM (
          SELECT DISTINCT ON (t.code) t.code, t.raw_name, t.expiry
          FROM (
            SELECT public.resolve_br_chapter_code(CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END) AS code,
                   CASE WHEN jsonb_typeof(e) = 'string' THEN e #>> '{}' ELSE e->>'chapterName' END AS raw_name,
                   CASE WHEN jsonb_typeof(e) = 'string' THEN NULL ELSE e->>'expiryDate' END AS expiry
            FROM jsonb_array_elements(COALESCE(vep.pmi_memberships, '[]'::jsonb)) e
          ) t
          WHERE t.code IS NOT NULL
          ORDER BY t.code, (t.expiry IS NULL)
        ) rr
        JOIN public.chapter_registry cr2 ON cr2.chapter_code = rr.code AND cr2.is_active = true
        WHERE NOT EXISTS (
          SELECT 1 FROM public.member_chapter_affiliations mca2
          WHERE mca2.person_id = m.person_id AND mca2.chapter_code = rr.code)
      ) x
    ) aff2 ON true
    -- #1995 (fatia 1): a jornada de onboarding da pessoa e os sinais de trava medidos em 16/10/2026. X/Y usa o Y
    -- real da pessoa (o total de passos varia por papel) e só passos do catálogo (#2009); 'overdue' conta como
    -- pendente. Um sinal diz quando a etapa está pendente por dependência ou porque mede clique, não o fato.
    LEFT JOIN LATERAL (
      SELECT CASE WHEN count(*) = 0 THEN NULL ELSE jsonb_build_object(
        'total', count(*),
        'done', count(*) FILTER (WHERE op.status IN ('completed', 'skipped')),
        'pending', count(*) FILTER (WHERE op.status IN ('pending', 'overdue')),
        'stage', (array_agg(op.step_key ORDER BY s.step_order) FILTER (WHERE op.status IN ('pending', 'overdue')))[1],
        'stage_label', (array_agg(jsonb_build_object('pt-BR', s.label_pt, 'en-US', s.label_en, 'es-LATAM', s.label_es)
                          ORDER BY s.step_order) FILTER (WHERE op.status IN ('pending', 'overdue')))[1],
        'started_at', min(op.created_at),
        'last_progress_at', max(op.completed_at),
        'stalled_days', CASE WHEN count(*) FILTER (WHERE op.status IN ('pending', 'overdue')) > 0
                             THEN floor(extract(epoch FROM now() - COALESCE(max(op.completed_at), min(op.created_at))) / 86400)::int
                        END,
        'last_sign_in_at', (SELECT u.last_sign_in_at FROM auth.users u WHERE u.id = m.auth_id),
        'signals', to_jsonb(array_remove(ARRAY[
          -- "Conheça sua tribo" não fecha sem tribo: bloqueio por dependência, não atraso da pessoa
          CASE WHEN bool_or(op.step_key = 'meet_tribe' AND op.status IN ('pending', 'overdue')) AND m.tribe_id IS NULL
               THEN 'tribe_blocked_no_tribe' END,
          -- #2718: a etapa fecha pela presença numa reunião da própria tribo; aqui a pessoa tem tribo e já foi
          -- a reunião, mas nenhuma da tribo dela, então só o clique fecha
          CASE WHEN bool_or(op.step_key = 'meet_tribe' AND op.status IN ('pending', 'overdue')) AND m.tribe_id IS NOT NULL
                    AND EXISTS (SELECT 1 FROM public.attendance a WHERE a.member_id = m.id AND a.present)
                    AND NOT EXISTS (SELECT 1 FROM public.attendance a
                                    JOIN public.events e ON e.id = a.event_id
                                    JOIN public.initiatives i ON i.id = e.initiative_id
                                    WHERE a.member_id = m.id AND a.present AND i.legacy_tribe_id = m.tribe_id)
               THEN 'tribe_pending_but_attended' END,
          -- a trilha só fecha com badge do Credly sincronizado; sem Credly no perfil, a plataforma nunca vê o curso
          CASE WHEN bool_or(op.step_key = 'start_trail' AND op.status IN ('pending', 'overdue'))
                    AND NULLIF(btrim(COALESCE(m.credly_url, '')), '') IS NULL
               THEN 'trail_without_credly' END,
          -- o Código de Conduta só fecha por clique; a pessoa já assinou o Termo
          CASE WHEN bool_or(op.step_key = 'code_of_conduct' AND op.status IN ('pending', 'overdue'))
                    AND bool_or(op.step_key = 'volunteer_term' AND op.status = 'completed')
               THEN 'conduct_pending_term_signed' END,
          -- a detecção da primeira reunião funciona: aqui não há presença registrada em reunião nenhuma
          CASE WHEN bool_or(op.step_key = 'first_meeting' AND op.status IN ('pending', 'overdue'))
                    AND NOT EXISTS (SELECT 1 FROM public.attendance a WHERE a.member_id = m.id AND a.present)
               THEN 'never_present' END
        ], NULL))
      ) END AS onboarding
      FROM public.onboarding_progress op
      JOIN public.onboarding_steps s ON s.id = op.step_key
      WHERE op.member_id = m.id
        -- #2718 regra 4: só as etapas que valem para o papel da pessoa (o predicado de get_my_onboarding)
        AND public.onboarding_step_applies(s.applies_to_role, m.operational_role)
    ) ob ON true
    WHERE m.member_status = 'active'
      AND (
        p_scope = 'all'                                                -- #1364b full roster (verified + unverified)
        -- #3105: a fila e quem a regra NAO validou (portao fechado com vinculo que exige termo). Quem a VEP ja
        -- validou nao pede confirmacao humana.
        OR public.affiliation_needs_review(m.id)
      )
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'member_id', c.member_id,
      'name', c.name,
      'email', c.email,
      'chapter', c.chapter,
      'operational_role', c.operational_role,
      'is_pre_onboarding', c.is_pre_onboarding,
      -- #3105: o resultado do portao (caminho quando aberto, motivo quando fechado), a mesma regra do termo
      'affiliation_gate', public.affiliation_gate(c.member_id),
      'pmi_id_verified', COALESCE(c.pmi_id_verified, false),
      'vep_status_raw', c.vep_status_raw,
      'vep_last_seen_at', c.vep_last_seen_at,
      'pmi_memberships', COALESCE(c.pmi_memberships, '[]'::jsonb),
      -- #1192 SSOT chapter read-through (see lateral above)
      'chapter_affiliations', COALESCE(c.chapter_affiliations, '[]'::jsonb),
      'pmi_profile', CASE
        WHEN c.pmi_id IS NULL AND c.service_first_start_date IS NULL
             AND c.service_latest_end_date IS NULL AND c.service_history_count IS NULL
             AND c.pmi_data_fetched_at IS NULL
        THEN NULL
        ELSE jsonb_build_object(
          'pmi_id', c.pmi_id,
          'member_since', c.service_first_start_date,
          'member_until', c.service_latest_end_date,
          'volunteer_count', c.service_history_count,
          'last_sync', c.pmi_data_fetched_at
        )
      END,
      -- #1129 cohort + volunteer-term validity
      'cohort_class', CASE
        WHEN NOT COALESCE(c.has_selection, false) THEN 'non_selection'
        WHEN c.sel_is_current THEN 'current_selection'
        ELSE 'carryover'
      END,
      'cohort_cycle_code', c.sel_cycle_code,
      'cohort_role', c.sel_role,
      'term_end_date', c.term_end_date,
      'term_status', CASE
        WHEN c.term_signed IS NULL THEN 'none'
        -- #2720: engajamento que exige termo, sem o termo assinado: "Aguardando assinatura", qualquer que seja a data
        WHEN NOT c.term_signed THEN 'unsigned'
        WHEN c.term_end_date IS NULL THEN 'none'
        WHEN c.term_end_date < CURRENT_DATE THEN 'expired'
        WHEN c.term_end_date <= CURRENT_DATE + (v_term_soon_days || ' days')::interval THEN 'expiring'
        ELSE 'valid'
      END,
      -- #1995 (fatia 1)
      'onboarding', c.onboarding,
      -- #1995 (fatia 1b): null = sem tribo
      'tribe', CASE WHEN c.tribe_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.tribe_id, 'name', c.tribe_name) END,
      'latest_verification', CASE WHEN c.aff_created_at IS NULL THEN NULL ELSE jsonb_build_object(
        'created_at', c.aff_created_at,
        'membership_active', c.aff_membership_active,
        'membership_expires_on', c.aff_membership_expires_on,
        'method', c.aff_method,
        'chapter_verified', c.aff_chapter_verified
      ) END
    ) ORDER BY c.is_pre_onboarding DESC, c.name),
    '[]'::jsonb),
    ARRAY_AGG(c.member_id)
  INTO v_result, v_member_ids
  FROM cohort c;

  -- LGPD Art. 37 — nominal read of affiliation data by the office (SPEC §6.2.3(4)). cohort/term/
  -- chapter_affiliations are derived from selection/engagement/affiliation data the office already
  -- reads; no new raw identity column ('chapter' + 'membership_dates' cover the read-through).
  PERFORM public.log_pii_access_batch(
    v_member_ids,
    ARRAY['pmi_id','chapter','membership_status','membership_dates','onboarding_progress','last_sign_in'],
    'affiliation_verification_queue',
    'Diretoria de Filiação — leitura da fila de verificação de filiação');

  RETURN v_result;
END;
$function$;

-- 3) a reconciliacao por capitulo
CREATE OR REPLACE FUNCTION public.get_affiliation_chapter_rollup()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_result              jsonb;
BEGIN
  -- Same audience as get_affiliation_verification_queue: filiacao_director OR manage_member.
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  -- Per members.chapter (the roster axis, = /admin/members): total active + how many fall in the
  -- verification-queue cohort. #3105: in_queue le a MESMA funcao que a fila (affiliation_needs_review), em vez
  -- de copiar o predicado, para a reconciliacao nunca contradizer a fila.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'chapter', r.chapter,
    'total_active', r.total_active,
    'in_queue', r.in_queue,
    'verified_out', r.total_active - r.in_queue
  ) ORDER BY r.total_active DESC, r.chapter), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT m.chapter,
           count(*) AS total_active,
           count(*) FILTER (WHERE public.affiliation_needs_review(m.id)) AS in_queue
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.chapter IS NOT NULL
    GROUP BY m.chapter
  ) r;

  RETURN v_result;
END;
$function$;

-- 4) a lista da #3101, absorvida pela fila
DROP FUNCTION IF EXISTS public.get_volunteers_with_closed_affiliation_gate();

-- pos-condicao
DO $postcondition$
DECLARE
  v_msg text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace
             AND proname = 'get_volunteers_with_closed_affiliation_gate') THEN
    RAISE EXCEPTION '#3105: get_volunteers_with_closed_affiliation_gate continua no banco';
  END IF;
  IF has_function_privilege('authenticated', 'public.affiliation_needs_review(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3105: affiliation_needs_review ficou executavel por authenticated';
  END IF;
  BEGIN
    PERFORM public.get_affiliation_verification_queue('queue');
    RAISE EXCEPTION '#3105: a fila respondeu sem sessao';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'Forbidden: authentication required%' THEN
      RAISE EXCEPTION '#3105: recusa inesperada sem sessao: %', v_msg;
    END IF;
  END;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
