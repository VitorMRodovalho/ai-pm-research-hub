-- ============================================================================
-- #1813 — o alerta de consistencia da selecao ganha destinatario quando nao ha lead
-- ----------------------------------------------------------------------------
-- MEDIDO EM 16/08/2026:
--   ciclo aberto ......... 0 leads, 7 membros de comite (evaluator + observer)
--   3 ciclos fechados .... 3 leads no total
--   leads em ciclo em andamento (o predicado do alerta) .......... 0
--   membros ativos com manage_platform (a audiencia de fallback) . 2
--
-- _selection_consistency_cron grava o relatorio todo dia e, havendo anomalia de integridade,
-- notifica os leads do comite. Com zero leads em ciclo em andamento, o laco nao roda nenhuma
-- vez: o alerta dispara e nao chega a ninguem.
--
-- NAO E O MESMO BUG DO #1809. La, 'member' estava fora do dominio do CHECK e o predicado
-- 'lead' OR 'member' valia lead sozinho -- literal morto. Aqui 'lead' esta no dominio e o
-- predicado faz exatamente o que diz. O que falta e destinatario.
--
-- DECISAO DO PM (16/08): fallback ESTRUTURAL, nao nomeacao de lead. Nomear um lead resolve
-- hoje e volta a falhar calado no proximo ciclo que abrir sem lead -- contencao por dado nao
-- e contencao por estrutura.
--
-- DESENHO:
--   1. A resolucao do destinatario sai de dentro do cron e vira _selection_consistency_recipients():
--      leads dos ciclos em andamento; e, SO se esse conjunto for vazio, quem tem manage_platform.
--      Funcao propria porque assim o teste exerce a audiencia sem provocar notificacao.
--   2. A audiencia de fallback usa o padrao ja canonico da plataforma
--      (members.is_active AND can_by_member(id, 'manage_platform')), o mesmo de _alert_sweep_cron.
--   3. A entrega passa a ser FATO REGISTRADO: notified_count e notified_via entram na mesma
--      linha de admin_audit_log do relatorio. Sem isso, "alertou" e indistinguivel de "nao
--      tinha para quem alertar", que e exatamente como este defeito passou despercebido.
--
-- ROLLBACK:
--   DROP FUNCTION public._selection_consistency_recipients();
--   (e recriar _selection_consistency_cron a partir da captura de 20260816040023.)
-- ============================================================================

CREATE OR REPLACE FUNCTION public._selection_consistency_recipients()
RETURNS TABLE(member_id uuid, via text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH leads AS (
    -- #1805: ciclo em andamento e todo o que nao e rascunho nem fechado -- mesmo predicado
    -- do relatorio. Este ramo segue sendo o destinatario natural quando existe lead.
    SELECT DISTINCT sc.member_id AS id
    FROM public.selection_committee sc
    JOIN public.selection_cycles c ON c.id = sc.cycle_id
    WHERE c.status NOT IN ('draft','closed')
      AND sc.role = 'lead'
      AND sc.member_id IS NOT NULL
  )
  SELECT l.id, 'lead'::text FROM leads l
  UNION ALL
  -- Fallback: SO quando nao ha lead nenhum em ciclo em andamento. Padrao de audiencia de GP
  -- ja canonico na plataforma (o mesmo de _alert_sweep_cron).
  SELECT m.id, 'manage_platform'::text
  FROM public.members m
  WHERE NOT EXISTS (SELECT 1 FROM leads)
    AND m.is_active
    AND public.can_by_member(m.id, 'manage_platform');
$function$;

COMMENT ON FUNCTION public._selection_consistency_recipients() IS
  'Destinatarios do alerta diario de consistencia da selecao (#1813). Leads dos ciclos em '
  'andamento e, SO se esse conjunto for vazio, quem tem manage_platform. Existe como funcao '
  'propria por dois motivos: o teste exerce a audiencia sem provocar notificacao, e o predicado '
  'deixa de estar solto dentro do cron. Medido em 16/08/2026: 0 leads em ciclo em andamento e '
  '2 membros ativos com manage_platform -- o alerta ia para ninguem e passa a ir para 2.';

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
  v_audit_id uuid;
  v_notified int := 0;
  v_via text;
BEGIN
  v_report := public.selection_consistency_report(NULL);
  v_total := COALESCE((v_report->>'integrity_anomaly_total')::int, 0);

  -- always record the report (observability) — admin-scoped audit log
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    NULL, 'selection.consistency_check', 'system', NULL,
    jsonb_build_object('integrity_anomaly_total', v_total),
    v_report
  ) RETURNING id INTO v_audit_id;

  -- alert leads ONLY on high-confidence integrity anomalies (never on the dispatch gap)
  IF v_total > 0 THEN
    v_summary := v_total || ' anomalia(s) de integridade na pipeline de seleção '
      || '(candidato pontuado sem avançar / entrevista concluída com app atrás / '
      || 'fase de entrevista sem linha / linha órfã / agendamento sem match). '
      || 'Detalhes no relatório (admin_audit_log selection.consistency_check). Revise em /admin/selection.';

    -- #1813: a resolucao do destinatario vira funcao propria, com fallback estrutural.
    -- Antes era o predicado 'lead' cru aqui dentro: com zero leads em ciclo em andamento
    -- o laco nao rodava nenhuma vez e o alerta nao chegava a ninguem, calado.
    FOR v_lead IN
      SELECT r.member_id, r.via FROM public._selection_consistency_recipients() r
    LOOP
      v_via := v_lead.via;
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
      v_notified := v_notified + 1;
    END LOOP;
  END IF;

  -- A entrega vira fato registrado na MESMA linha do relatorio. Sem isto, "alertou" e
  -- indistinguivel de "nao tinha para quem alertar" -- que era o estado desta funcao.
  UPDATE public.admin_audit_log
     SET changes = changes || jsonb_build_object('notified_count', v_notified, 'notified_via', v_via)
   WHERE id = v_audit_id;

  RETURN v_report || jsonb_build_object(
    'alert_delivery', jsonb_build_object('notified_count', v_notified, 'via', v_via)
  );
END;
$function$;

-- CREATE FUNCTION concede EXECUTE a PUBLIC; a resolucao expoe ids de membro.
-- (_selection_consistency_cron ja e service_role-only desde 20260805000097 e CREATE OR REPLACE
-- de funcao EXISTENTE preserva as ACLs, entao so a funcao nova precisa da escada.)
REVOKE ALL ON FUNCTION public._selection_consistency_recipients() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_consistency_recipients() TO service_role;

NOTIFY pgrst, 'reload schema';
