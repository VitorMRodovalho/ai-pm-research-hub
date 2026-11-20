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
-- Rollback: recriar a funcao pela captura 20260903022128.

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
    SELECT x.member_id, x.member_name, x.vep_expira, x.vep_unparseable,
           x.man_active, x.man_expira, x.man_created_at,
           CASE WHEN x.vep_expira IS NOT NULL THEN 'vep'
                WHEN x.man_created_at IS NOT NULL THEN 'manual'
                ELSE 'none' END AS fonte,
           COALESCE(x.vep_expira, CASE WHEN x.man_active THEN x.man_expira END) AS expira
    FROM (
      SELECT m.id AS member_id, m.name AS member_name,
             vep.vep_expira, COALESCE(vep.vep_unparseable, 0) AS vep_unparseable,
             man.membership_active AS man_active, man.membership_expires_on AS man_expira, man.created_at AS man_created_at
      FROM public.members m
      -- #3108: o snapshot VEP mais recente da pessoa, pela mesma funcao do portao (#3107)
      LEFT JOIN LATERAL (
        SELECT public.affiliation_vep_snapshot(m.id) -> 'pmi_memberships' AS pmi_memberships
      ) snap ON true
      -- o maior vencimento de capitulo participante no snapshot; o formato e guardado (#2152) e o resto, contado
      LEFT JOIN LATERAL (
        SELECT max(CASE WHEN e.elem->>'expiryDate' ~ '^\d{1,2} [A-Za-z]{3} \d{4}$'
                        THEN to_date(e.elem->>'expiryDate', 'DD Mon YYYY') END) AS vep_expira,
               count(*) FILTER (WHERE e.elem->>'expiryDate' IS NOT NULL
                                  AND e.elem->>'expiryDate' !~ '^\d{1,2} [A-Za-z]{3} \d{4}$') AS vep_unparseable
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(snap.pmi_memberships) = 'array'
                                       THEN snap.pmi_memberships ELSE '[]'::jsonb END) AS e(elem)
        JOIN public.chapter_registry cr
          ON cr.chapter_code = public.resolve_br_chapter_code(e.elem->>'chapterName') AND cr.is_active
        WHERE jsonb_typeof(e.elem) = 'object'
      ) vep ON true
      -- a ultima verificacao manual (a trilha e append-only): so vale quando a VEP nao da vencimento
      LEFT JOIN LATERAL (
        SELECT mav.membership_active, mav.membership_expires_on, mav.created_at
        FROM public.member_affiliation_verifications mav
        WHERE mav.member_id = m.id
        ORDER BY mav.created_at DESC
        LIMIT 1
      ) man ON true
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
