-- #3110: o aviso de filiacao pendente que ja existe passa a alcancar quem tem o portao fechado.
--
-- Fatia 4 da consolidacao dos fluxos de filiacao. Decisao do GP (20/11/2026): "se a regra nao encontrou filiacao, o
-- caminho e pedir a pessoa que se filie, reaproveitando o que ja existe"; o aviso sai por e-mail imediato, como ja
-- esta catalogado (entry_chapter_action_needed => transactional_immediate em _delivery_mode_for).
--
-- Antes: nudge_entry_chapter_cohort(p_cycle_id, p_dry_run) tinha os textos certos, mas nenhum chamador (nenhum cron,
-- funcao SQL, tela, EF ou ferramenta MCP; rodou uma vez, em 09/07/2026, com 6 avisos). A coorte era "aprovado no ciclo
-- de selecao ativo com entry_chapter_code nulo", lida de get_entry_chapter_diagnosis.
--
-- Agora:
--   - coorte = affiliation_needs_review (#3105): vinculo ativo que exige termo E affiliation_gate fechado;
--   - o texto sai do motivo do portao e do balde do snapshot (affiliation_vep_snapshot, #3107):
--       entry_chapter_required                       => 'ambiguous'      (escolher o capitulo de entrada)
--       not_affiliated                               => 'not_affiliated' (confirmar a filiacao PMI)
--       unknown, snapshot profile_private            => 'profile_private'
--       unknown, sem snapshot ou snapshot no_fetch   => 'no_fetch'
--       unknown, snapshot resolved ou ambiguous      => NAO AVISA: a VEP mostra filiacao e o portao nao abriu; o
--                                                       problema nao e da pessoa e ela fica na fila da Diretoria;
--   - titulos e corpos identicos aos da captura 20260925222502; o mesmo tipo, link e dedupe de 30 dias;
--   - a assinatura perde p_cycle_id (a coorte nao e mais de ciclo): DROP + CREATE (p_dry_run boolean DEFAULT true),
--     mesmos grants, mesmo portao de chamador (manage_platform, ou cron/service_role pelo GUC de role, #684);
--   - NENHUM agendamento aqui (decisao do GP, 20/11/2026: ver a lista antes do primeiro disparo). O cron diario vai na
--     migration curta 20261120150500_3110_cron_do_aviso_de_filiacao, aplicada so depois do OK do GP.
--
-- get_entry_chapter_diagnosis fica sem chamador nesta migration (era lida so por esta funcao); nao e removida aqui
-- porque guards (1224, 1801) a exercitam. Decisao de aposenta-la fica registrada na PR.
--
-- Rollback: DROP FUNCTION public.nudge_entry_chapter_cohort(boolean); recriar a antiga pela captura 20260925222502
-- com os grants da 20260805000387.

DROP FUNCTION IF EXISTS public.nudge_entry_chapter_cohort(uuid, boolean);

CREATE FUNCTION public.nudge_entry_chapter_cohort(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rec       record;
  v_variant   text;
  v_title     text;
  v_body      text;
  v_sent      int := 0;
  v_skipped   int := 0;
  v_internal  int := 0;
  v_plan      jsonb := '[]'::jsonb;
BEGIN
  -- manage_platform, or service_role/postgres (cron/tests) — same gate as before (#684).
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires manage_platform';
    END IF;
  ELSIF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires authentication';
  END IF;

  FOR v_rec IN
    SELECT m.id AS member_id,
           public.affiliation_gate(m.id) ->> 'reason' AS reason,
           public.affiliation_vep_snapshot(m.id) ->> 'bucket' AS bucket
    FROM public.members m
    WHERE m.member_status = 'active'
      AND public.affiliation_needs_review(m.id)
    ORDER BY m.id
  LOOP
    v_variant := CASE
      WHEN v_rec.reason = 'entry_chapter_required' THEN 'ambiguous'
      WHEN v_rec.reason = 'not_affiliated'         THEN 'not_affiliated'
      WHEN v_rec.bucket = 'profile_private'        THEN 'profile_private'
      WHEN v_rec.bucket IS NULL OR v_rec.bucket = 'no_fetch' THEN 'no_fetch'
      ELSE NULL  -- a VEP mostra filiacao e o portao nao abriu: trabalho da Diretoria, nao da pessoa
    END;

    IF v_variant IS NULL THEN
      v_internal := v_internal + 1;
      CONTINUE;
    END IF;

    v_title := CASE v_variant
      WHEN 'ambiguous'       THEN 'Escolha seu capítulo de entrada no Núcleo'
      WHEN 'profile_private' THEN 'Deixe seu perfil PMI público para confirmarmos seu capítulo'
      WHEN 'no_fetch'        THEN 'Vincule seu perfil PMI para definir seu capítulo de entrada'
      ELSE                        'Confirme sua filiação PMI para definir seu capítulo de entrada'
    END;
    v_body := CASE v_variant
      WHEN 'ambiguous' THEN
        'Encontramos mais de um capítulo PMI ativo na sua filiação. Escolha por qual capítulo você entra no Núcleo para ajustarmos a governança e os indicadores do seu capítulo. Leva um clique no seu perfil.'
      WHEN 'profile_private' THEN
        'Seu perfil no community.pmi.org está com a visibilidade privada, então não conseguimos ler seus capítulos para definir seu capítulo de entrada no Núcleo. Acesse community.pmi.org, deixe seu perfil público (ao menos a seção de capítulos) e nós atualizamos automaticamente.'
      WHEN 'no_fetch' THEN
        'Ainda não localizamos seu perfil no community.pmi.org. Se você tem filiação PMI, confira se o perfil está criado e público em community.pmi.org para confirmarmos seu capítulo de entrada no Núcleo automaticamente.'
      ELSE
        'Não conseguimos confirmar uma filiação PMI ativa no seu perfil do community.pmi.org. Para registrarmos seu capítulo de entrada no Núcleo, verifique se sua filiação PMI está ativa e se o capítulo aparece no seu perfil em community.pmi.org. Assim que estiver regular, atualizamos automaticamente.'
    END;

    -- O plano leva so o id opaco e a variante: o ensaio nao expoe nome.
    v_plan := v_plan || jsonb_build_object('member_id', v_rec.member_id, 'variant', v_variant);

    IF p_dry_run THEN
      CONTINUE;
    END IF;

    -- Dedup: do not re-fire if this member already got the nudge in the last 30 days.
    IF EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = v_rec.member_id
        AND n.type = 'entry_chapter_action_needed'
        AND n.created_at > now() - interval '30 days'
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    PERFORM public.create_notification(
      v_rec.member_id,
      'entry_chapter_action_needed',
      v_title,
      v_body,
      '/profile#entry-chapter-card'
    );
    v_sent := v_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'candidates', jsonb_array_length(v_plan),
    'internal_only', v_internal,
    'sent', v_sent,
    'skipped_recent', v_skipped,
    'plan', v_plan
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.nudge_entry_chapter_cohort(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nudge_entry_chapter_cohort(boolean) TO authenticated, service_role;

-- pos-condicao: o ensaio nao envia, cobre a coorte inteira e bate com affiliation_needs_review
DO $postcondition$
DECLARE
  v_ensaio jsonb;
  v_coorte int;
BEGIN
  v_ensaio := public.nudge_entry_chapter_cohort(true);
  SELECT count(*) INTO v_coorte FROM public.members m
  WHERE m.member_status = 'active' AND public.affiliation_needs_review(m.id);
  IF (v_ensaio ->> 'sent')::int <> 0
     OR (v_ensaio ->> 'candidates')::int + (v_ensaio ->> 'internal_only')::int <> v_coorte THEN
    RAISE EXCEPTION '#3110: ensaio inesperado (coorte %): %', v_coorte, v_ensaio;
  END IF;
  IF has_function_privilege('anon', 'public.nudge_entry_chapter_cohort(boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3110: anon executa o aviso';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE command ~ 'nudge_entry_chapter_cohort') THEN
    RAISE EXCEPTION '#3110: esta migration nao agenda o aviso; o cron vai na migration a parte, depois do OK do GP';
  END IF;
  RAISE NOTICE '#3110 ok: coorte %, candidatos %, so internos %', v_coorte, v_ensaio ->> 'candidates', v_ensaio ->> 'internal_only';
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
