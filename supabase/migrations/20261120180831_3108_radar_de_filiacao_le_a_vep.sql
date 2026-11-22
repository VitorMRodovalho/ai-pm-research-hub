-- #3108: o radar de filiacao le o vencimento do snapshot VEP, nao so da verificacao manual.
--
-- Fatia 3 da consolidacao dos fluxos de filiacao. Decisao do GP (20/11/2026): o lote vep_sync fica, so como "forcar
-- nova leitura"; deixa de ser a forma de alimentar o radar.
--
-- Antes: v4_notify_expiring_affiliations so percorria a ultima linha de member_affiliation_verifications. A faixa C
-- (#2152) avisava a Diretoria quando a VEP contradizia a verificacao. Medido em 20/11/2026 (ensaio, p_dry_run = true):
-- d30 = 2, d7 = 0, vencidas = 8, obsoletas = 0, divergentes = 5. Os voluntarios com filiacao validada so pela VEP, sem
-- verificacao manual, nao entravam em faixa nenhuma (17, medido na auditoria do mesmo dia).
--
-- Agora:
--   - vencimento efetivo por pessoa = o maior expiryDate ('DD Mon YYYY') de capitulo participante (resolve_br_chapter_code
--     em chapter_registry ativo) no snapshot VEP mais recente, lido por affiliation_vep_snapshot (#3107, a mesma funcao do
--     portao). Sem vencimento da VEP, a ultima verificacao manual, como antes (so conta se membership_active);
--   - faixas A (D-30, D-7, vencida) sobre o vencimento efetivo, mesmos textos, mesmos tipos, mesmos dedupes;
--   - faixa B (verificacao obsoleta, > 330 dias) so para quem depende da verificacao manual;
--   - faixa C sai: com o radar lendo a VEP nao ha contradicao entre as duas copias para medir. O tipo
--     affiliation_vep_divergence fica no catalogo (_delivery_mode_for) por causa das linhas antigas;
--   - populacao: membros ativos com vinculo ativo de tipo que exige termo (a mesma de affiliation_needs_review, #3105);
--   - links da Diretoria para /admin/filiacao (o filtro ?filter=affiliation de /admin/members nao existe);
--   - retorno: sai candidates_vep_divergent; entram from_vep, from_manual e without_source. expiry_unparseable conta
--     expiryDate de capitulo participante fora do formato.
--
-- v4_notify_expiring_affiliations: corpo = captura 20260903022128 (md5 do corpo normalizado conferido contra o vivo em
-- 20/11/2026), reescrito no LATERAL de origem e nas faixas acima. Assinatura e grants nao mudam.
--
-- Visibilidade (regra do GP, 20/11/2026: toda automacao visivel no front): o vencimento efetivo e a fonte saem de UMA
-- funcao, affiliation_effective_expiry(member_id), lida pelo radar e pela linha da fila de /admin/filiacao. A fila
-- (get_affiliation_verification_queue) e recriada pela captura 20261120151945 (#3105) com a chave nova
-- 'affiliation_expiry' em cada linha; nada mais muda nela.
--
-- Rollback: recriar o radar pela captura 20260903022128 e a fila pela captura 20261120151945; DROP FUNCTION
-- public.affiliation_effective_expiry(uuid).

-- O vencimento efetivo da filiacao de uma pessoa, e de onde ele vem. Interna: quem le e o radar e a fila.
CREATE FUNCTION public.affiliation_effective_expiry(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH snap AS (
    -- o snapshot VEP mais recente da pessoa, pela mesma funcao do portao (#3107)
    SELECT public.affiliation_vep_snapshot(p_member_id) -> 'pmi_memberships' AS pm
  ),
  vep AS (
    -- o maior vencimento de capitulo participante no snapshot; o formato e guardado (#2152) e o resto, contado
    SELECT max(CASE WHEN e.elem->>'expiryDate' ~ '^\d{1,2} [A-Za-z]{3} \d{4}$'
                    THEN to_date(e.elem->>'expiryDate', 'DD Mon YYYY') END) AS vep_expira,
           count(*) FILTER (WHERE e.elem->>'expiryDate' IS NOT NULL
                              AND e.elem->>'expiryDate' !~ '^\d{1,2} [A-Za-z]{3} \d{4}$') AS vep_unparseable
    FROM snap
    CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(snap.pm) = 'array' THEN snap.pm ELSE '[]'::jsonb END) AS e(elem)
    JOIN public.chapter_registry cr
      ON cr.chapter_code = public.resolve_br_chapter_code(e.elem->>'chapterName') AND cr.is_active
    WHERE jsonb_typeof(e.elem) = 'object'
  ),
  man AS (
    -- a ultima verificacao manual (a trilha e append-only): so vale quando a VEP nao da vencimento
    SELECT mav.membership_active, mav.membership_expires_on, mav.created_at
    FROM public.member_affiliation_verifications mav
    WHERE mav.member_id = p_member_id
    ORDER BY mav.created_at DESC
    LIMIT 1
  )
  SELECT jsonb_build_object(
    'expires_on', COALESCE(vep.vep_expira, CASE WHEN man.membership_active THEN man.membership_expires_on END),
    'source', CASE WHEN vep.vep_expira IS NOT NULL THEN 'vep'
                   WHEN man.created_at IS NOT NULL THEN 'manual' END,
    'vep_unparseable', COALESCE(vep.vep_unparseable, 0),
    'manual_verified_at', man.created_at
  )
  FROM vep LEFT JOIN man ON true;
$function$;

REVOKE ALL ON FUNCTION public.affiliation_effective_expiry(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_effective_expiry(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.v4_notify_expiring_affiliations(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count_d30  int := 0;
  v_count_d7   int := 0;
  v_count_stale int := 0;
  v_count_expired int := 0;
  v_count_expiry_unparseable int := 0;
  v_from_vep int := 0;
  v_from_manual int := 0;
  v_without_source int := 0;
  v_sent       int := 0;
  v_filiacao_member_id uuid;
  r            record;
BEGIN
  -- Diretora de Filiação (sede) — destinatária de awareness quando não-dry-run.
  SELECT m.id INTO v_filiacao_member_id
  FROM public.members m
  WHERE m.is_active = true AND 'filiacao_director' = ANY(m.designations)
  LIMIT 1;

  FOR r IN
    SELECT x.member_id, x.member_name,
           (x.ex ->> 'vep_unparseable')::int AS vep_unparseable,
           (x.ex ->> 'manual_verified_at')::timestamptz AS man_created_at,
           COALESCE(x.ex ->> 'source', 'none') AS fonte,
           (x.ex ->> 'expires_on')::date AS expira
    FROM (
      SELECT m.id AS member_id, m.name AS member_name,
             -- #3108: vencimento efetivo e fonte, pela mesma funcao que a fila de /admin/filiacao mostra
             public.affiliation_effective_expiry(m.id) AS ex
      FROM public.members m
      WHERE m.is_active = true
        AND EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.engagement_kinds ek ON ek.slug = e.kind AND ek.requires_agreement IS TRUE
          WHERE e.person_id = m.person_id AND e.status = 'active'
        )
    ) x
  LOOP
    IF r.fonte = 'vep' THEN v_from_vep := v_from_vep + 1;
    ELSIF r.fonte = 'manual' THEN v_from_manual := v_from_manual + 1;
    ELSE v_without_source := v_without_source + 1;
    END IF;
    v_count_expiry_unparseable := v_count_expiry_unparseable + r.vep_unparseable;

    -- (A) Expiração D-30
    IF r.expira IS NOT NULL AND (r.expira - CURRENT_DATE) BETWEEN 8 AND 30 THEN
      v_count_d30 := v_count_d30 + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_d30'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '7 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_d30',
          'Sua filiação PMI vence em 30 dias',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI vence em ' || r.expira ||
          '. O Termo de Voluntariado exige filiação PMI ativa — renove em pmi.org. '
          'Para parar estes lembretes, ajuste em /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_d30'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (A) Expiração D-7 URGENTE
    IF r.expira IS NOT NULL AND (r.expira - CURRENT_DATE) BETWEEN 0 AND 7 THEN
      v_count_d7 := v_count_d7 + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_d7_urgent'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '7 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_d7_urgent',
          'URGENTE: sua filiação PMI vence em 7 dias',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI vence em ' || r.expira ||
          '. Renove imediatamente em pmi.org para manter seu Termo de Voluntariado vigente. '
          'Para ajustar lembretes, acesse /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_d7_urgent'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (A) VENCIDA (#1855). Dedupe de 30 dias: a faixa e ilimitada no tempo.
    IF r.expira IS NOT NULL AND r.expira < CURRENT_DATE THEN
      v_count_expired := v_count_expired + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_expired'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '30 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_expired',
          'Sua filiação PMI venceu',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI venceu em ' || r.expira ||
          '. O Termo de Voluntariado exige filiação PMI ativa. Renove em pmi.org. '
          'Para parar estes lembretes, ajuste em /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_expired'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (B) Verificação obsoleta > 11 meses, só para quem depende da verificação manual (a VEP se renova sozinha).
    IF r.fonte = 'manual' AND (CURRENT_DATE - r.man_created_at::date) > 330 THEN
      v_count_stale := v_count_stale + 1;
      IF NOT p_dry_run AND v_filiacao_member_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = v_filiacao_member_id AND n.type = 'affiliation_verification_stale'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '30 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (v_filiacao_member_id, 'affiliation_verification_stale',
          'Re-verificar filiação: ' || r.member_name,
          r.member_name || ' não tem verificação de filiação há ' || (CURRENT_DATE - r.man_created_at::date) ||
          ' dias, e a VEP não informa o vencimento. Re-verifique na fila de /admin/filiacao.',
          '/admin/filiacao', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_verification_stale'));
        v_sent := v_sent + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'candidates_d30', v_count_d30,
    'candidates_d7', v_count_d7,
    'candidates_expired', v_count_expired,
    'candidates_stale', v_count_stale,
    'expiry_unparseable', v_count_expiry_unparseable,
    'from_vep', v_from_vep,
    'from_manual', v_from_manual,
    'without_source', v_without_source,
    'notifications_sent', v_sent,
    'run_at', now());
END;
$function$;

-- pos-condicao: o ensaio bate com uma consulta independente, e a funcao segue interna
-- A fila de /admin/filiacao: corpo = captura 20261120151945 (#3105) mais a chave 'affiliation_expiry'. Grants iguais
-- (CREATE OR REPLACE os preserva).
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
      -- #3108: vencimento efetivo e fonte (VEP ou manual), a mesma funcao que o radar le
      'affiliation_expiry', public.affiliation_effective_expiry(c.member_id),
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

DO $postcondition$
DECLARE
  v_ensaio jsonb;
  v_d30 int; v_d7 int; v_venc int; v_vep int;
BEGIN
  IF has_function_privilege('authenticated', 'public.v4_notify_expiring_affiliations(boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.v4_notify_expiring_affiliations(boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3108: o radar ficou executavel por anon ou authenticated';
  END IF;

  v_ensaio := public.v4_notify_expiring_affiliations(true);
  IF has_function_privilege('anon', 'public.affiliation_effective_expiry(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_effective_expiry(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3108: affiliation_effective_expiry ficou executavel por anon ou authenticated';
  END IF;
  IF (v_ensaio ->> 'notifications_sent')::int <> 0 OR v_ensaio ? 'candidates_vep_divergent' THEN
    RAISE EXCEPTION '#3108: ensaio inesperado: %', v_ensaio;
  END IF;

  WITH pop AS (
    SELECT m.id, m.email FROM public.members m
    WHERE m.is_active = true
      AND EXISTS (SELECT 1 FROM public.engagements e JOIN public.engagement_kinds ek ON ek.slug = e.kind AND ek.requires_agreement IS TRUE
                  WHERE e.person_id = m.person_id AND e.status = 'active')
  ), snap AS (
    SELECT p.id, (SELECT sa.pmi_memberships FROM public.selection_applications sa
                  WHERE sa.pmi_data_fetched_at IS NOT NULL
                    AND (lower(sa.email) = lower(p.email)
                         OR lower(sa.email) IN (SELECT lower(me.email) FROM public.member_emails me WHERE me.member_id = p.id))
                  ORDER BY sa.pmi_data_fetched_at DESC LIMIT 1) AS pm
    FROM pop p
  ), ve AS (
    SELECT s.id, (SELECT max(to_date(x->>'expiryDate', 'DD Mon YYYY'))
                  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(s.pm) = 'array' THEN s.pm ELSE '[]'::jsonb END) x
                  JOIN public.chapter_registry cr ON cr.chapter_code = public.resolve_br_chapter_code(x->>'chapterName') AND cr.is_active
                  WHERE jsonb_typeof(x) = 'object' AND x->>'expiryDate' ~ '^\d{1,2} [A-Za-z]{3} \d{4}$') AS vexp
    FROM snap s
  ), ef AS (
    SELECT ve.id, ve.vexp,
           COALESCE(ve.vexp, (SELECT CASE WHEN mav.membership_active THEN mav.membership_expires_on END
                              FROM public.member_affiliation_verifications mav WHERE mav.member_id = ve.id
                              ORDER BY mav.created_at DESC LIMIT 1)) AS exp
    FROM ve
  )
  SELECT count(*) FILTER (WHERE exp - CURRENT_DATE BETWEEN 8 AND 30),
         count(*) FILTER (WHERE exp - CURRENT_DATE BETWEEN 0 AND 7),
         count(*) FILTER (WHERE exp < CURRENT_DATE),
         count(*) FILTER (WHERE vexp IS NOT NULL)
    INTO v_d30, v_d7, v_venc, v_vep
  FROM ef;

  IF v_d30 <> (v_ensaio ->> 'candidates_d30')::int OR v_d7 <> (v_ensaio ->> 'candidates_d7')::int
     OR v_venc <> (v_ensaio ->> 'candidates_expired')::int OR v_vep <> (v_ensaio ->> 'from_vep')::int THEN
    RAISE EXCEPTION '#3108: o ensaio (%) diverge da consulta independente (d30 %, d7 %, vencidas %, vep %)',
      v_ensaio, v_d30, v_d7, v_venc, v_vep;
  END IF;
  RAISE NOTICE '#3108 ok: %', v_ensaio;
END
$postcondition$;
