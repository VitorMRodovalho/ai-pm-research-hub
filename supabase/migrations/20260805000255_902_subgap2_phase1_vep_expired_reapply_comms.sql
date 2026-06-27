-- #902 sub-gap 2 — Fase 1: comms de re-aplicação para candidatura com prazo VEP expirado (DORMENTE)
-- SPEC: docs/specs/SPEC_902_SUBGAP2_VEP_REAPPLICATION.md  ·  RUNBOOK: docs/runbooks/RUNBOOK_VEP_EXPIRED_REAPPLICATION.md
-- Decisão PM 2026-06-26: Fase 1 = comms + runbook; bucket Expired/OfferExpired SOMENTE (Withdrawn excluído,
--   OfferNotExtended = review GP caso-a-caso); SEM auto-aprovar, SEM transferência de score, SEM gate de filiação.
-- Re-ancoragem ratificada: o score anterior é CONTEXTO para o GP, nunca herança automática de aprovação.
-- Aditiva e DORMENTE: a RPC default p_dry_run=true e NÃO há cron agendado. Nada envia até que (a) exista um
--   próximo ciclo (cycle5) com URL de re-aplicação e (b) alguém agende/chame com p_dry_run=false + p_reapply_url.
-- Reframing aterrado (workflow wf_cc1ab601-977, 2026-06-26): cutoff_approved_email = passe objetivo + convite de
--   entrevista, NÃO admissão; só 1/7 da coorte entrevistou. Por isso o invite NÃO promete aprovação.
-- Council: legal-counsel + security-engineer + data-architect + product-leader = CONDITIONAL; requisitos aplicados.
-- Padrão de reuso: D7 (20260805000209) — template trilíngue + RPC single-fire + ADR-0028 cron bypass.
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.process_pending_vep_expired_reapply_invites(boolean, text);
--   DELETE FROM public.sla_policies WHERE policy_key='reapply_invite_grace';
--   DELETE FROM public.campaign_templates WHERE slug='selection_vep_expired_reapply_invite';
--   ALTER TABLE public.selection_applications DROP COLUMN IF EXISTS vep_expired_reapply_email_sent_at;

-- ===== 1. Coluna de idempotência single-fire (padrão cutoff_approved_email_sent_at / vep_offer_reminder_sent_at) =====
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS vep_expired_reapply_email_sent_at timestamptz;

COMMENT ON COLUMN public.selection_applications.vep_expired_reapply_email_sent_at IS
'Quando o convite de re-aplicação (#902 sub-gap 2 Fase 1) foi enviado a um candidato cuja aplicacao/oferta VEP '
'expirou apos passar a triagem objetiva (vep_status_raw Expired/OfferExpired, status rejected). Single-fire '
'(NULL=ainda nao enviado). Carimbado por process_pending_vep_expired_reapply_invites apos envio real. '
'Bucket Expired/OfferExpired SOMENTE (decisao PM 2026-06-26).';

-- ===== 2. Janela SLA configurável (reusa tabela + UI admin do J4) =====
-- Ancorada em COALESCE(vep_expired_at, updated_at) na RPC — robusta a vep_expired_at NULL (so popula no
-- proximo ingest do worker pmi-vep-sync, PR #903 pos-merge).
INSERT INTO public.sla_policies (policy_key, value_interval, category, description)
VALUES (
  'reapply_invite_grace',
  '2 days',
  'sla',
  'Prazo apos a expiracao VEP (vep_expired_at, fallback updated_at) antes de o candidato Expired/OfferExpired '
  'receber o convite de re-aplicacao (#902 sub-gap 2). Evita corrida com o polling do worker. Single-fire.'
)
ON CONFLICT (policy_key) DO NOTHING;

-- ===== 3. Template trilíngue: selection_vep_expired_reapply_invite =====
-- Restrições legal-counsel aplicadas: linguagem CONDICIONAL (nunca promete aprovacao); transparencia Art.9
-- (dados de avaliacao anteriores poderao ser reutilizados); canal de direitos Art.18; opt-out + rodape de
-- controlador/finalidade (Art.7 II). DRAFT para revisao do PM — editavel via ON CONFLICT DO UPDATE.
INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, variables, category, target_audience, created_at, updated_at)
VALUES (
  'selection_vep_expired_reapply_invite',
  'Selection — VEP-expired re-apply invite (#902 sub-gap 2, single-fire)',
  jsonb_build_object(
    'pt', 'Seu prazo VEP expirou, {{first_name}} — você pode se recandidatar ao Núcleo IA',
    'en', 'Your VEP deadline expired, {{first_name}} — you can re-apply to Núcleo IA',
    'es', 'Tu plazo VEP expiró, {{first_name}} — puedes volver a postularte a Núcleo IA'
  ),
  jsonb_build_object(
    'pt', '<p>Olá {{first_name}},</p>' ||
          '<p>Sua candidatura havia <strong>avançado em nosso processo seletivo</strong>, mas a sua aplicação/oferta no portal VEP do PMI <strong>expirou por prazo</strong> antes da conclusão. Isso é uma questão administrativa de prazo — <strong>não foi uma rejeição por mérito</strong>.</p>' ||
          '<p>Você é bem-vindo(a) a <strong>se recandidatar</strong> no próximo ciclo de seleção:</p>' ||
          '<p><a href="{{reapply_url}}">{{reapply_url}}</a></p>' ||
          '<p>Caso sua nova candidatura seja <strong>aceita pela coordenação (GP)</strong>, os resultados da etapa que você já concluiu <strong>poderão ser considerados</strong> — isso será decidido caso a caso pela GP, e este e-mail <strong>não garante aprovação automática</strong>.</p>' ||
          '<p style="color:#666;font-size:13px;">Transparência (LGPD Art. 9): ao se recandidatar, os <strong>dados da sua avaliação anterior</strong> poderão ser reutilizados para apoiar a nova análise. Para exercer seus direitos de titular (acesso, correção, eliminação — LGPD Art. 18), responda este e-mail.</p>' ||
          '<p style="color:#666;font-size:13px;">Se preferir não se recandidatar, é só ignorar este e-mail ou responder &quot;não tenho interesse&quot; — não enviaremos novas comunicações sobre o processo seletivo.</p>' ||
          '<p>Obrigado!<br/>Núcleo IA &amp; GP</p>' ||
          '<p style="color:#888;font-size:12px;border-top:1px solid #eee;padding-top:8px;">Este e-mail foi enviado pelo <strong>Núcleo IA — capítulo voluntário do PMI</strong> porque sua candidatura avançou no processo seletivo e o prazo VEP expirou. Finalidade: convidá-lo(a) a se recandidatar. Dúvidas ou direitos do titular: responda este e-mail.</p>',
    'en', '<p>Hello {{first_name}},</p>' ||
          '<p>Your application had <strong>advanced in our selection process</strong>, but your VEP application/offer on the PMI portal <strong>expired by deadline</strong> before completion. This is an administrative deadline matter — <strong>not a merit-based rejection</strong>.</p>' ||
          '<p>You are welcome to <strong>re-apply</strong> in the next selection cycle:</p>' ||
          '<p><a href="{{reapply_url}}">{{reapply_url}}</a></p>' ||
          '<p>If your new application is <strong>accepted by the coordination (GP)</strong>, the results of the stage you already completed <strong>may be considered</strong> — this is decided case by case by the GP, and this email <strong>does not guarantee automatic approval</strong>.</p>' ||
          '<p style="color:#666;font-size:13px;">Transparency (LGPD Art. 9): if you re-apply, the <strong>data from your prior evaluation</strong> may be reused to support the new analysis. To exercise your data-subject rights (access, correction, deletion — LGPD Art. 18), reply to this email.</p>' ||
          '<p style="color:#666;font-size:13px;">If you prefer not to re-apply, simply ignore this email or reply &quot;not interested&quot; — we will not send further communications about the selection process.</p>' ||
          '<p>Thank you!<br/>Núcleo IA &amp; GP</p>' ||
          '<p style="color:#888;font-size:12px;border-top:1px solid #eee;padding-top:8px;">This email was sent by <strong>Núcleo IA — a PMI volunteer chapter</strong> because your application advanced in the selection process and the VEP deadline expired. Purpose: to invite you to re-apply. Questions or data-subject rights: reply to this email.</p>',
    'es', '<p>Hola {{first_name}},</p>' ||
          '<p>Tu candidatura había <strong>avanzado en nuestro proceso de selección</strong>, pero tu aplicación/oferta en el portal VEP del PMI <strong>expiró por plazo</strong> antes de concluir. Es una cuestión administrativa de plazo — <strong>no fue un rechazo por mérito</strong>.</p>' ||
          '<p>Eres bienvenido(a) a <strong>volver a postularte</strong> en el próximo ciclo de selección:</p>' ||
          '<p><a href="{{reapply_url}}">{{reapply_url}}</a></p>' ||
          '<p>Si tu nueva candidatura es <strong>aceptada por la coordinación (GP)</strong>, los resultados de la etapa que ya completaste <strong>podrán ser considerados</strong> — esto lo decide caso por caso la GP, y este correo <strong>no garantiza aprobación automática</strong>.</p>' ||
          '<p style="color:#666;font-size:13px;">Transparencia (LGPD Art. 9): si vuelves a postularte, los <strong>datos de tu evaluación anterior</strong> podrán ser reutilizados para apoyar el nuevo análisis. Para ejercer tus derechos de titular (acceso, corrección, eliminación — LGPD Art. 18), responde este correo.</p>' ||
          '<p style="color:#666;font-size:13px;">Si prefieres no volver a postularte, simplemente ignora este correo o responde &quot;sin interés&quot; — no enviaremos más comunicaciones sobre el proceso de selección.</p>' ||
          '<p>¡Gracias!<br/>Núcleo IA &amp; GP</p>' ||
          '<p style="color:#888;font-size:12px;border-top:1px solid #eee;padding-top:8px;">Este correo fue enviado por <strong>Núcleo IA — capítulo voluntario del PMI</strong> porque tu candidatura avanzó en el proceso de selección y el plazo VEP expiró. Finalidad: invitarte a volver a postularte. Dudas o derechos del titular: responde este correo.</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}},\n\nSua candidatura havia avançado em nosso processo seletivo, mas a sua aplicação/oferta no portal VEP do PMI EXPIROU por prazo antes da conclusão. Isso é uma questão administrativa de prazo — NÃO foi uma rejeição por mérito.\n\nVocê é bem-vindo(a) a se recandidatar no próximo ciclo:\n{{reapply_url}}\n\nCaso sua nova candidatura seja aceita pela coordenação (GP), os resultados da etapa que você já concluiu poderão ser considerados — decidido caso a caso pela GP. Este e-mail NÃO garante aprovação automática.\n\nLGPD Art. 9: ao se recandidatar, os dados da sua avaliação anterior poderão ser reutilizados. Direitos do titular (Art. 18): responda este e-mail.\n\nSe preferir não se recandidatar, ignore este e-mail ou responda "não tenho interesse".\n\nNúcleo IA & GP\n---\nEnviado pelo Núcleo IA (capítulo voluntário do PMI). Finalidade: convite a se recandidatar após expiração de prazo VEP.',
    'en', 'Hello {{first_name}},\n\nYour application had advanced in our selection process, but your VEP application/offer on the PMI portal EXPIRED by deadline before completion. This is an administrative deadline matter — NOT a merit-based rejection.\n\nYou are welcome to re-apply in the next cycle:\n{{reapply_url}}\n\nIf your new application is accepted by the coordination (GP), the results of the stage you already completed may be considered — decided case by case by the GP. This email does NOT guarantee automatic approval.\n\nLGPD Art. 9: if you re-apply, the data from your prior evaluation may be reused. Data-subject rights (Art. 18): reply to this email.\n\nIf you prefer not to re-apply, ignore this email or reply "not interested".\n\nNúcleo IA & GP\n---\nSent by Núcleo IA (a PMI volunteer chapter). Purpose: invitation to re-apply after VEP deadline expiry.',
    'es', 'Hola {{first_name}},\n\nTu candidatura había avanzado en nuestro proceso de selección, pero tu aplicación/oferta en el portal VEP del PMI EXPIRÓ por plazo antes de concluir. Es una cuestión administrativa de plazo — NO fue un rechazo por mérito.\n\nEres bienvenido(a) a volver a postularte en el próximo ciclo:\n{{reapply_url}}\n\nSi tu nueva candidatura es aceptada por la coordinación (GP), los resultados de la etapa que ya completaste podrán ser considerados — decidido caso por caso por la GP. Este correo NO garantiza aprobación automática.\n\nLGPD Art. 9: si vuelves a postularte, los datos de tu evaluación anterior podrán ser reutilizados. Derechos del titular (Art. 18): responde este correo.\n\nSi prefieres no volver a postularte, ignora este correo o responde "sin interés".\n\nNúcleo IA & GP\n---\nEnviado por Núcleo IA (capítulo voluntario del PMI). Finalidad: invitación a volver a postularte tras la expiración del plazo VEP.'
  ),
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true),
    'reapply_url', jsonb_build_object('type', 'text', 'required', true)
  ),
  'operational',
  jsonb_build_object('audience', 'selection_candidate'),
  now(),
  now()
)
ON CONFLICT (slug) DO UPDATE SET
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables,
  updated_at = now();

-- ===== 4. RPC dormente: process_pending_vep_expired_reapply_invites(p_dry_run, p_reapply_url) =====
-- DORMENTE por design: p_dry_run DEFAULT true; sem p_reapply_url => força dry-run (não há destino válido).
-- NÃO agenda cron. Ativação (quando cycle5 existir): agendar/chamar com p_dry_run=false + p_reapply_url do
-- próximo ciclo. Bucket Expired/OfferExpired SOMENTE. Auth: comms-only => manage_member OU cron (ADR-0028),
-- espelha o gate do D7 (NÃO é manage_platform; isto não toca ciclo de vida, só envia e-mail).
CREATE OR REPLACE FUNCTION public.process_pending_vep_expired_reapply_invites(
  p_dry_run boolean DEFAULT true,
  p_reapply_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $func$
DECLARE
  v_app record;
  v_grace interval;
  v_first_name text;
  v_dry boolean := p_dry_run;
  v_sent int := 0;
  v_would_send int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_candidates jsonb := '[]'::jsonb;
BEGIN
  -- Auth: cron (sem JWT / service_role) passa; usuário real exige manage_member (ADR-0028, espelha D7).
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: requires manage_member or service_role';
    END IF;
  END IF;

  -- Sem URL de destino não há envio possível -> força dry-run (trava de dormência).
  IF p_reapply_url IS NULL OR length(trim(p_reapply_url)) = 0 THEN
    v_dry := true;
  END IF;

  SELECT value_interval INTO v_grace FROM public.sla_policies WHERE policy_key = 'reapply_invite_grace';
  v_grace := COALESCE(v_grace, interval '2 days');

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.first_name, a.email
    FROM public.selection_applications a
    WHERE a.cutoff_approved_email_sent_at IS NOT NULL          -- passou a triagem objetiva + convite
      AND a.status = 'rejected'                                -- flipado por expiração (não withdrawn)
      AND a.vep_status_raw IN ('Expired', 'OfferExpired')      -- bucket ratificado (exclui OfferNotExtended/Withdrawn)
      AND a.vep_expired_reapply_email_sent_at IS NULL          -- single-fire
      AND a.email IS NOT NULL
      AND COALESCE(a.vep_expired_at, a.updated_at) < now() - v_grace
  LOOP
    v_would_send := v_would_send + 1;
    v_first_name := COALESCE(NULLIF(v_app.first_name, ''), split_part(v_app.applicant_name, ' ', 1));

    -- LGPD: payload de retorno carrega só IDs/contagens, nunca nome/e-mail.
    v_candidates := v_candidates || jsonb_build_object('application_id', v_app.id);

    IF v_dry THEN
      CONTINUE;
    END IF;

    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'selection_vep_expired_reapply_invite',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object('first_name', v_first_name, 'reapply_url', p_reapply_url),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_vep_expired_reapply_invites',
          'application_id', v_app.id,
          'language', 'pt'
        )
      );

      UPDATE public.selection_applications
      SET vep_expired_reapply_email_sent_at = now()
      WHERE id = v_app.id;

      v_sent := v_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object('application_id', v_app.id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', v_dry,
    'would_send', v_would_send,
    'sent', v_sent,
    'candidates', v_candidates,
    'errors', v_errors,
    'run_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.process_pending_vep_expired_reapply_invites(boolean, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_pending_vep_expired_reapply_invites(boolean, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.process_pending_vep_expired_reapply_invites(boolean, text) IS
'#902 sub-gap 2 Fase 1 (DORMENTE): convida candidatos cujo prazo VEP expirou (Expired/OfferExpired, status '
'rejected, passaram a triagem objetiva) a se recandidatar. DORMENTE: p_dry_run DEFAULT true e sem p_reapply_url '
'forca dry-run; NAO ha cron agendado. Single-fire (vep_expired_reapply_email_sent_at). NAO aprova nada, nao '
'transfere score — so comms. Auth: manage_member ou cron (ADR-0028). NUNCA promete aprovacao (copy condicional). '
'Bucket Expired/OfferExpired SOMENTE (Withdrawn/OfferNotExtended fora). Ativacao: ver RUNBOOK_VEP_EXPIRED_REAPPLICATION.';

NOTIFY pgrst, 'reload schema';
