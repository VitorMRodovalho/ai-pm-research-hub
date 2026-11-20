-- #3110: o aviso de filiacao pendente que ja existe passa a alcancar quem tem o portao fechado, com liga/desliga,
-- previa e historico pela tela de /admin/filiacao.
--
-- Fatia 4 da consolidacao dos fluxos de filiacao. Decisoes do GP (20/11/2026):
--   - "se a regra nao encontrou filiacao, o caminho e pedir a pessoa que se filie, reaproveitando o que ja existe"; o
--     aviso sai por e-mail imediato, como ja esta catalogado (entry_chapter_action_needed => transactional_immediate);
--   - toda automacao com visibilidade, auditoria e controle pelo front, nao so por SQL ou MCP;
--   - o aviso nasce DESLIGADO; o GP ve a previa na tela e liga com um clique auditado;
--   - pausar e da audiencia da fila (filiacao_director ou manage_member); ligar, so de manage_platform, porque ligar
--     manda e-mail a voluntarios.
--
-- Antes: nudge_entry_chapter_cohort(p_cycle_id, p_dry_run) tinha os textos certos, mas nenhum chamador (nenhum cron,
-- funcao SQL, tela, EF ou ferramenta MCP; rodou uma vez, em 09/07/2026, com 6 avisos). A coorte era "aprovado no ciclo
-- de selecao ativo com entry_chapter_code nulo", lida de get_entry_chapter_diagnosis.
--
-- Agora:
--   - affiliation_nudge_plan(): o plano, num lugar so (quem e com qual variante). Coorte = affiliation_needs_review
--     (#3105). Variante pelo motivo do portao e pelo balde do snapshot (affiliation_vep_snapshot, #3107):
--       entry_chapter_required                       => 'ambiguous'      (escolher o capitulo de entrada)
--       not_affiliated                               => 'not_affiliated' (confirmar a filiacao PMI)
--       unknown, snapshot profile_private            => 'profile_private'
--       unknown, sem snapshot ou snapshot no_fetch   => 'no_fetch'
--       unknown, snapshot resolved ou ambiguous      => NULL: a VEP mostra filiacao e o portao nao abriu; o problema
--                                                       nao e da pessoa, e ela fica so na fila da Diretoria;
--   - affiliation_nudge_text(variante): titulo e corpo, identicos aos da captura 20260925222502;
--   - affiliation_nudge_enabled(): le a chave 'affiliation.action_needed_nudge' de platform_settings. Sem a chave, ou
--     com enabled diferente de true, o aviso fica desligado (falha fechada);
--   - nudge_entry_chapter_cohort(p_dry_run): le o plano; envia so com p_dry_run = false E o aviso ligado. Grava a
--     variante em source_type ('affiliation_nudge.<variante>'), para o historico. Mesmo tipo, link e dedupe de 30 dias.
--     A assinatura perde p_cycle_id: DROP + CREATE (p_dry_run boolean DEFAULT true), mesmos grants e mesmo portao de
--     chamador (manage_platform, ou cron/service_role pelo GUC de role, #684);
--   - set_affiliation_nudge_enabled(p_enabled, p_reason): liga (manage_platform) ou pausa (audiencia da fila), com
--     motivo obrigatorio e linha em admin_audit_log, no mesmo formato de admin_update_setting;
--   - get_affiliation_nudge_panel(): o que a tela mostra, para a audiencia da fila: estado da chave (quem, quando,
--     motivo), o agendamento, a previa (nome, variante, se o dedupe barra), o historico de envios (180 dias) e as
--     ultimas mudancas da chave;
--   - cron diario 'affiliation-action-needed-nudge-daily' as 12:30 UTC (09:30 em Brasilia). Com o aviso desligado ele
--     roda e nao envia nada.
--
-- get_entry_chapter_diagnosis fica sem chamador nesta migration (era lida so pela funcao antiga); nao e removida aqui
-- porque guards (1224, 1801) a exercitam.
--
-- Rollback: SELECT cron.unschedule('affiliation-action-needed-nudge-daily'); DROP FUNCTION
-- public.get_affiliation_nudge_panel(), public.set_affiliation_nudge_enabled(boolean, text),
-- public.nudge_entry_chapter_cohort(boolean), public.affiliation_nudge_enabled(), public.affiliation_nudge_text(text),
-- public.affiliation_nudge_plan(); DELETE FROM public.platform_settings WHERE key = 'affiliation.action_needed_nudge';
-- recriar a antiga pela captura 20260925222502 com os grants da 20260805000387.

-- 0) a chave, desligada
INSERT INTO public.platform_settings (key, value, description, change_reason)
VALUES (
  'affiliation.action_needed_nudge',
  '{"enabled": false}'::jsonb,
  'Aviso diario de filiacao pendente (entry_chapter_action_needed) a quem tem o portao de filiacao fechado. Liga: manage_platform; pausa: Diretoria de Filiacao. Tela: /admin/filiacao.',
  '#3110: criada desligada; o GP liga pela tela depois de ver a previa'
)
ON CONFLICT (key) DO NOTHING;

-- 1) o plano
CREATE FUNCTION public.affiliation_nudge_plan()
 RETURNS TABLE(member_id uuid, variant text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT x.member_id,
         CASE
           WHEN x.reason = 'entry_chapter_required'          THEN 'ambiguous'
           WHEN x.reason = 'not_affiliated'                  THEN 'not_affiliated'
           WHEN x.bucket = 'profile_private'                 THEN 'profile_private'
           WHEN x.bucket IS NULL OR x.bucket = 'no_fetch'    THEN 'no_fetch'
           ELSE NULL  -- a VEP mostra filiacao e o portao nao abriu: trabalho da Diretoria, nao da pessoa
         END AS variant
  FROM (
    SELECT m.id AS member_id,
           public.affiliation_gate(m.id) ->> 'reason' AS reason,
           public.affiliation_vep_snapshot(m.id) ->> 'bucket' AS bucket
    FROM public.members m
    WHERE m.member_status = 'active'
      AND public.affiliation_needs_review(m.id)
  ) x
  ORDER BY x.member_id;
$function$;

-- 2) os textos, por variante
CREATE FUNCTION public.affiliation_nudge_text(p_variant text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_variant
    WHEN 'ambiguous' THEN jsonb_build_object(
      'title', 'Escolha seu capítulo de entrada no Núcleo',
      'body',  'Encontramos mais de um capítulo PMI ativo na sua filiação. Escolha por qual capítulo você entra no Núcleo para ajustarmos a governança e os indicadores do seu capítulo. Leva um clique no seu perfil.')
    WHEN 'profile_private' THEN jsonb_build_object(
      'title', 'Deixe seu perfil PMI público para confirmarmos seu capítulo',
      'body',  'Seu perfil no community.pmi.org está com a visibilidade privada, então não conseguimos ler seus capítulos para definir seu capítulo de entrada no Núcleo. Acesse community.pmi.org, deixe seu perfil público (ao menos a seção de capítulos) e nós atualizamos automaticamente.')
    WHEN 'no_fetch' THEN jsonb_build_object(
      'title', 'Vincule seu perfil PMI para definir seu capítulo de entrada',
      'body',  'Ainda não localizamos seu perfil no community.pmi.org. Se você tem filiação PMI, confira se o perfil está criado e público em community.pmi.org para confirmarmos seu capítulo de entrada no Núcleo automaticamente.')
    WHEN 'not_affiliated' THEN jsonb_build_object(
      'title', 'Confirme sua filiação PMI para definir seu capítulo de entrada',
      'body',  'Não conseguimos confirmar uma filiação PMI ativa no seu perfil do community.pmi.org. Para registrarmos seu capítulo de entrada no Núcleo, verifique se sua filiação PMI está ativa e se o capítulo aparece no seu perfil em community.pmi.org. Assim que estiver regular, atualizamos automaticamente.')
  END;
$function$;

-- 3) a chave, lida num lugar so (falha fechada)
CREATE FUNCTION public.affiliation_nudge_enabled()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (SELECT (ps.value ->> 'enabled')::boolean IS TRUE
     FROM public.platform_settings ps WHERE ps.key = 'affiliation.action_needed_nudge'),
    false);
$function$;

REVOKE ALL ON FUNCTION public.affiliation_nudge_plan() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.affiliation_nudge_text(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.affiliation_nudge_enabled() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_plan() TO service_role;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_text(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_enabled() TO service_role;

-- 4) o aviso
DROP FUNCTION IF EXISTS public.nudge_entry_chapter_cohort(uuid, boolean);

CREATE FUNCTION public.nudge_entry_chapter_cohort(p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_enabled   boolean;
  v_rec       record;
  v_text      jsonb;
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

  v_enabled := public.affiliation_nudge_enabled();

  FOR v_rec IN SELECT p.member_id, p.variant FROM public.affiliation_nudge_plan() p LOOP
    IF v_rec.variant IS NULL THEN
      v_internal := v_internal + 1;
      CONTINUE;
    END IF;

    -- O plano leva so o id opaco e a variante: o ensaio nao expoe nome.
    v_plan := v_plan || jsonb_build_object('member_id', v_rec.member_id, 'variant', v_rec.variant);

    -- Nada sai em ensaio, nem com o aviso desligado (a chave e ligada e pausada pela tela de /admin/filiacao).
    IF p_dry_run OR NOT v_enabled THEN
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

    v_text := public.affiliation_nudge_text(v_rec.variant);
    PERFORM public.create_notification(
      v_rec.member_id,
      'entry_chapter_action_needed',
      v_text ->> 'title',
      v_text ->> 'body',
      '/profile#entry-chapter-card',
      'affiliation_nudge.' || v_rec.variant,
      NULL::uuid
    );
    v_sent := v_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'enabled', v_enabled,
    'paused', NOT p_dry_run AND NOT v_enabled,
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

-- 5) liga e pausa, pela tela
CREATE FUNCTION public.set_affiliation_nudge_enabled(p_enabled boolean, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_old                 jsonb;
  v_new                 jsonb;
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  IF p_enabled IS NULL THEN
    RAISE EXCEPTION 'p_enabled is required';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'Reason is required';
  END IF;

  IF p_enabled THEN
    -- ligar manda e-mail a voluntarios: so a gestao da plataforma
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Forbidden: turning the affiliation nudge on requires manage_platform';
    END IF;
  ELSE
    -- pausar e da audiencia da fila de filiacao
    IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
       AND NOT public.can_by_member(v_caller_id, 'manage_member')
       AND NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Forbidden: pausing the affiliation nudge requires filiacao_director or manage_member';
    END IF;
  END IF;

  SELECT ps.value INTO v_old FROM public.platform_settings ps
  WHERE ps.key = 'affiliation.action_needed_nudge' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Setting affiliation.action_needed_nudge is missing';
  END IF;
  v_new := COALESCE(v_old, '{}'::jsonb) || jsonb_build_object('enabled', p_enabled);

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'platform.setting_changed', 'setting', NULL,
    jsonb_build_object('previous_value', v_old, 'new_value', v_new),
    jsonb_build_object('setting_key', 'affiliation.action_needed_nudge', 'reason', p_reason)
  );

  UPDATE public.platform_settings
  SET value = v_new, changed_by = v_caller_id, changed_at = now(), change_reason = p_reason
  WHERE key = 'affiliation.action_needed_nudge';

  RETURN jsonb_build_object('success', true, 'enabled', p_enabled);
END;
$function$;

REVOKE ALL ON FUNCTION public.set_affiliation_nudge_enabled(boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_affiliation_nudge_enabled(boolean, text) TO authenticated, service_role;

-- 6) o que a tela mostra
CREATE FUNCTION public.get_affiliation_nudge_panel()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;
  -- a mesma audiencia da fila de filiacao
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director or manage_member';
  END IF;

  RETURN jsonb_build_object(
    'enabled', public.affiliation_nudge_enabled(),
    'setting', (
      SELECT jsonb_build_object('changed_at', ps.changed_at, 'changed_by', cm.name, 'reason', ps.change_reason)
      FROM public.platform_settings ps
      LEFT JOIN public.members cm ON cm.id = ps.changed_by
      WHERE ps.key = 'affiliation.action_needed_nudge'),
    'can_enable', public.can_by_member(v_caller_id, 'manage_platform'),
    'schedule', (
      SELECT jsonb_build_object('schedule', j.schedule, 'active', j.active)
      FROM cron.job j WHERE j.jobname = 'affiliation-action-needed-nudge-daily'),
    'preview', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'member_id', p.member_id,
               'name', m.name,
               'variant', p.variant,
               'blocked_by_dedupe', EXISTS (
                 SELECT 1 FROM public.notifications n
                 WHERE n.recipient_id = p.member_id AND n.type = 'entry_chapter_action_needed'
                   AND n.created_at > now() - interval '30 days'))
             ORDER BY p.variant NULLS LAST, m.name)
      FROM public.affiliation_nudge_plan() p
      JOIN public.members m ON m.id = p.member_id), '[]'::jsonb),
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'member_id', h.recipient_id,
               'name', h.name,
               'created_at', h.created_at,
               'variant', h.variant,
               'email_delivery_status', h.email_delivery_status,
               'email_sent_at', h.email_sent_at)
             ORDER BY h.created_at DESC)
      FROM (
        SELECT n.recipient_id, m.name, n.created_at, n.email_delivery_status, n.email_sent_at,
               -- a variante gravada no envio; nos envios antigos, a que tem o mesmo titulo
               COALESCE(substring(n.source_type FROM '^affiliation_nudge\.(.+)$'),
                        (SELECT v FROM unnest(ARRAY['ambiguous', 'not_affiliated', 'profile_private', 'no_fetch']) v
                         WHERE public.affiliation_nudge_text(v) ->> 'title' = n.title)) AS variant
        FROM public.notifications n
        LEFT JOIN public.members m ON m.id = n.recipient_id
        WHERE n.type = 'entry_chapter_action_needed'
          AND n.created_at > now() - interval '180 days'
        ORDER BY n.created_at DESC
        LIMIT 500
      ) h), '[]'::jsonb),
    'changes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'at', c.created_at,
               'by', c.name,
               'enabled', (c.changes -> 'new_value' ->> 'enabled')::boolean,
               'reason', c.reason)
             ORDER BY c.created_at DESC)
      FROM (
        SELECT a.created_at, am.name, a.changes, a.metadata ->> 'reason' AS reason
        FROM public.admin_audit_log a
        LEFT JOIN public.members am ON am.id = a.actor_id
        WHERE a.action = 'platform.setting_changed'
          AND a.metadata ->> 'setting_key' = 'affiliation.action_needed_nudge'
        ORDER BY a.created_at DESC
        LIMIT 20
      ) c), '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_affiliation_nudge_panel() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_affiliation_nudge_panel() TO authenticated, service_role;

-- 7) o agendamento. Com o aviso desligado, ele roda e nao envia nada.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'affiliation-action-needed-nudge-daily') THEN
    PERFORM cron.unschedule('affiliation-action-needed-nudge-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'affiliation-action-needed-nudge-daily',
  '30 12 * * *',  -- 09:30 em Brasilia; minuto livre (12:40 tem onboarding-auto-complete-daily)
  $cron$ SELECT public.nudge_entry_chapter_cohort(p_dry_run := false) $cron$
);

-- pos-condicao, com controle nos dois sentidos sem enviar nada
DO $postcondition$
DECLARE
  v_ensaio jsonb;
  v_real   jsonb;
  v_coorte int;
  v_avisos int;
BEGIN
  IF public.affiliation_nudge_enabled() THEN
    RAISE EXCEPTION '#3110: o aviso tem de nascer desligado';
  END IF;

  v_ensaio := public.nudge_entry_chapter_cohort(true);
  SELECT count(*) INTO v_coorte FROM public.members m
  WHERE m.member_status = 'active' AND public.affiliation_needs_review(m.id);
  IF (v_ensaio ->> 'sent')::int <> 0
     OR (v_ensaio ->> 'candidates')::int + (v_ensaio ->> 'internal_only')::int <> v_coorte THEN
    RAISE EXCEPTION '#3110: ensaio inesperado (coorte %): %', v_coorte, v_ensaio;
  END IF;

  -- a execucao real com o aviso desligado nao envia nada (o que o cron faz ate o GP ligar)
  SELECT count(*) INTO v_avisos FROM public.notifications WHERE type = 'entry_chapter_action_needed';
  v_real := public.nudge_entry_chapter_cohort(false);
  IF (v_real ->> 'sent')::int <> 0 OR NOT (v_real ->> 'paused')::boolean
     OR (SELECT count(*) FROM public.notifications WHERE type = 'entry_chapter_action_needed') <> v_avisos THEN
    RAISE EXCEPTION '#3110: com o aviso desligado, a execucao real enviou: %', v_real;
  END IF;

  IF has_function_privilege('anon', 'public.nudge_entry_chapter_cohort(boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.set_affiliation_nudge_enabled(boolean, text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_affiliation_nudge_panel()', 'EXECUTE') THEN
    RAISE EXCEPTION '#3110: anon executa uma funcao do aviso';
  END IF;
  IF has_function_privilege('authenticated', 'public.affiliation_nudge_plan()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_nudge_text(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_nudge_enabled()', 'EXECUTE') THEN
    RAISE EXCEPTION '#3110: uma funcao interna do aviso ficou exposta';
  END IF;

  IF (SELECT count(*) FROM cron.job WHERE command ~ 'nudge_entry_chapter_cohort') <> 1
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'affiliation-action-needed-nudge-daily' AND active
                    AND command ~ 'p_dry_run := false') THEN
    RAISE EXCEPTION '#3110: cron do aviso nao ficou como esperado';
  END IF;
  RAISE NOTICE '#3110 ok: coorte %, candidatos %, so internos %, desligado', v_coorte, v_ensaio ->> 'candidates', v_ensaio ->> 'internal_only';
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
