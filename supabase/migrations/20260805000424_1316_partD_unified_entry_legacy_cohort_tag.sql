-- #1316 Parte D — Modelo de entrada unificado (Ciclo 1/2 Goias+Ceara -> PMI-GO sede)
--
-- Decisao de governanca (owner 2026-07-11, AskUserQuestion):
--   (a) Origem e sede sao EIXOS INDEPENDENTES. `members.entry_chapter_code` = capitulo de
--       ORIGEM (variado; escolha de governanca do membro, ADR-0104). A sede contratante e
--       constante: `chapter_registry.is_contracting_chapter` = PMI-GO (o unico contratante;
--       o Termo de Voluntariado sempre contrata com PMI-GO). entry_chapter_code NUNCA e
--       sobrescrito para 'GO'.
--   (b) SEM backfill forcado de entry_chapter_code: os NULLs remanescentes sao multi-capitulo
--       ambiguos (precisam do desempate do proprio membro -- nudge #1224) ou 'Outro' honesto
--       (zero afiliacao / perfil privado). Forcar GO violaria ADR-0104 ("entrada e escolha,
--       nao ordem de array"). Verificado ao vivo 2026-07-11: 0 ativos-nao-alumni com entry
--       NULL tem afiliacao unica -> nenhum backfill mecanico legitimo.
--
-- Este migration e DATA-ONLY. Ele carimba de forma duravel a proveniencia de entrada legada
-- (Ciclo 1/2) nos engagements dos membros que entraram pelo mirror legado
-- (volunteer_applications) e nunca ganharam uma linha moderna em selection_applications
-- (selection_application_id IS NULL), para que a coorte seja legivel sem re-join no mirror.
-- Chave jsonb ADITIVA (`metadata || ...`); nunca clobbera metadata existente. Idempotente
-- (WHERE NOT (metadata ? 'legacy_cohort')). Deriva os ids do mirror (sem ids hardcoded).
--
-- Documentacao: ADR-0104 (Amendment: Unified entry model, Part D #1316) + ADR-0076
-- (Principio 1 corrigido: chapter de ENTRADA vive em members.entry_chapter_code, nao mais em
-- selection_applications.chapter).
--
-- Triggers em engagements (verificado 2026-07-11): os bridges de dual-write
-- (trg_sync_tribe_id_from_engagement OF status,kind; trg_sync_member_initiative_from_engagement
-- OF status,initiative_id) sao column-scoped e NAO disparam num UPDATE que toca so metadata.
-- trg_clamp_expired_engagement_end_date so age quando status='expired' (nenhuma linha alvo).
-- trg_sync_role_cache recomputa operational_role de forma idempotente (QA rolled-back: 4/4
-- inalterados).

WITH cohort AS (
  SELECT va.member_id,
         min(va.cycle) AS entry_cycle,
         (array_agg(va.opportunity_id ORDER BY va.cycle))[1] AS entry_opportunity_id
  FROM public.volunteer_applications va
  WHERE va.cycle IN (1,2) AND va.member_id IS NOT NULL
  GROUP BY va.member_id
)
UPDATE public.engagements e
SET metadata = COALESCE(e.metadata,'{}'::jsonb) || jsonb_build_object(
      'legacy_cohort', jsonb_build_object(
        'cycle', c.entry_cycle,
        'vep_opportunity_id', c.entry_opportunity_id,
        'source', 'volunteer_applications_mirror',
        'sede', 'PMI-GO',
        'backfilled_by', '#1316_partD',
        'note', 'Entrada legada Ciclo 1/2 (Goias/Ceara) sob PMI-GO sede; sem selection_applications moderna. Coorte derivada do mirror legado volunteer_applications.'
      )),
    updated_at = now()
FROM cohort c
JOIN public.members m ON m.id = c.member_id
WHERE e.person_id = m.person_id
  AND e.kind IN ('volunteer','researcher')
  AND e.selection_application_id IS NULL
  AND NOT (COALESCE(e.metadata,'{}'::jsonb) ? 'legacy_cohort');
