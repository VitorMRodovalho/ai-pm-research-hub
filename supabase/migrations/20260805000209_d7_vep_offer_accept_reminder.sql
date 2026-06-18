-- D7 — Lembrete automático de aceite de oferta VEP (candidate-facing PUSH layer do Épico D)
-- SPEC: docs/specs/SPEC_D7_VEP_OFFER_REMINDER.md
-- Coorte viva (2026-06-18): 3 candidatos OfferExtended+approved no cycle4-2026 (Maria/Bruna/Rafael)
--   parados no topo do funil (oferta VEP estendida, nunca clicaram "Accept Position"). 1 histórico
--   OfferExpired já perdido — desfecho que o D7 previne.
-- Padrão de reuso: p92 process_pending_reschedule_nudges (RPC/cron/template) + p157
--   trg_vep_acceptance_on_active (trigger de transição de vep_status_raw).
-- Council: data-architect GO-w-changes (trigger BEFORE INSERT OR UPDATE, search_path '', re-offer reset,
--   grace 7d) + legal-counsel GO-w-changes (Art.7 II procedimento preliminar; controlador + finalidade +
--   opt-out no template). 0 blockers.
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_stamp_vep_offer_extended ON public.selection_applications;
--   DROP FUNCTION IF EXISTS public._stamp_vep_offer_extended();
--   DROP FUNCTION IF EXISTS public.process_pending_vep_offer_reminders();
--   SELECT cron.unschedule('nudge-vep-offer-accept-daily');
--   DELETE FROM public.sla_policies WHERE policy_key='offer_accept_grace';
--   DELETE FROM public.campaign_templates WHERE slug='vep_offer_accept_reminder';
--   ALTER TABLE public.selection_applications DROP COLUMN IF EXISTS vep_offer_extended_at,
--     DROP COLUMN IF EXISTS vep_offer_reminder_sent_at;

-- ===== 1. Colunas: âncora da oferta + idempotência single-fire =====
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS vep_offer_extended_at   timestamptz,
  ADD COLUMN IF NOT EXISTS vep_offer_reminder_sent_at timestamptz;

COMMENT ON COLUMN public.selection_applications.vep_offer_extended_at IS
'Quando a candidatura passou a vep_status_raw=OfferExtended (carimbado pelo trigger '
'trg_stamp_vep_offer_extended na transicao genuina, nao a cada poll do worker). Ancora da janela '
'offer_accept_grace usada por process_pending_vep_offer_reminders. D7 (2026-06-18).';

COMMENT ON COLUMN public.selection_applications.vep_offer_reminder_sent_at IS
'Quando o lembrete D7 de aceite de oferta VEP foi enviado. Single-fire (NULL=ainda nao enviado). '
'Resetado para NULL pelo trigger na transicao para OfferExtended (re-offer ganha lembrete fresco). D7.';

-- ===== 2. Trigger de stamp (BEFORE INSERT OR UPDATE OF vep_status_raw) =====
-- BEFORE (nao AFTER como p157) pois so toca a propria linha -> modifica NEW direto, sem 2o write/recursao.
-- INSERT OR UPDATE pois o worker pmi-vep-sync pode INSERIR linha ja em OfferExtended (script-mapper.ts:162).
-- WHEN so referencia NEW (Postgres proibe OLD no WHEN de trigger com INSERT); a distincao genuina vs
-- reescrita no-change a cada poll e feita no corpo via TG_OP/OLD.
CREATE OR REPLACE FUNCTION public._stamp_vep_offer_extended()
RETURNS trigger
LANGUAGE plpgsql
AS $func$
BEGIN
  IF TG_OP = 'INSERT' OR OLD.vep_status_raw IS DISTINCT FROM 'OfferExtended' THEN
    NEW.vep_offer_extended_at := now();
    NEW.vep_offer_reminder_sent_at := NULL;  -- re-offer reseta o single-fire (SPEC §5, Option A)
  END IF;
  RETURN NEW;
END;
$func$;

COMMENT ON FUNCTION public._stamp_vep_offer_extended() IS
'BEFORE trigger fn: carimba vep_offer_extended_at=now() e reseta vep_offer_reminder_sent_at=NULL na '
'transicao genuina de vep_status_raw para OfferExtended (TG_OP=INSERT ou OLD distinto). Suprime reescritas '
'no-change do worker pmi-vep-sync. Espelha o padrao p157. D7 (2026-06-18).';

DROP TRIGGER IF EXISTS trg_stamp_vep_offer_extended ON public.selection_applications;
CREATE TRIGGER trg_stamp_vep_offer_extended
BEFORE INSERT OR UPDATE OF vep_status_raw ON public.selection_applications
FOR EACH ROW
WHEN (NEW.vep_status_raw = 'OfferExtended')
EXECUTE FUNCTION public._stamp_vep_offer_extended();

-- ===== 3. Backfill dos existentes (sem disparar o trigger; UPDATE nao toca vep_status_raw) =====
-- COALESCE(cutoff_approved_email_sent_at, created_at): ambos timestamps reais no passado -> coorte viva
-- qualifica na 1a run. vep_reconciled_at NAO entra (timestamp administrativo manual, nao a hora da oferta).
UPDATE public.selection_applications
SET vep_offer_extended_at = COALESCE(cutoff_approved_email_sent_at, created_at)
WHERE vep_status_raw = 'OfferExtended'
  AND vep_offer_extended_at IS NULL;

-- ===== 4. Janela SLA configuravel (reusa tabela + UI admin do J4) =====
INSERT INTO public.sla_policies (policy_key, value_interval, category, description)
VALUES (
  'offer_accept_grace',
  '7 days',
  'sla',
  'Prazo apos a oferta VEP ser estendida (vep_offer_extended_at) sem aceite antes de o candidato receber '
  'o lembrete D7 (process_pending_vep_offer_reminders). Single-fire por candidatura.'
)
ON CONFLICT (policy_key) DO NOTHING;

-- ===== 5. Template do e-mail: vep_offer_accept_reminder (trilingue) =====
INSERT INTO public.campaign_templates (slug, name, subject, body_html, body_text, variables, category, target_audience, created_at, updated_at)
VALUES (
  'vep_offer_accept_reminder',
  'VEP offer accept reminder (D7 single-fire)',
  jsonb_build_object(
    'pt', 'Falta 1 passo para você entrar no Núcleo IA, {{first_name}}',
    'en', 'One step left to join Núcleo IA, {{first_name}}',
    'es', 'Falta 1 paso para unirte a Núcleo IA, {{first_name}}'
  ),
  jsonb_build_object(
    'pt', '<p>Olá {{first_name}},</p>' ||
          '<p>Você está recebendo este e-mail porque sua candidatura ao Núcleo IA foi aprovada e há uma ação pendente no portal do PMI para concluir sua entrada como voluntário(a).</p>' ||
          '<p>Para finalizar, aceite a posição no portal do PMI:</p>' ||
          '<ol><li>Acesse <a href="https://volunteer.pmi.org">volunteer.pmi.org</a></li>' ||
          '<li>Abra o menu <strong>My Info &amp; Activity</strong></li>' ||
          '<li>Clique em <strong>Accept Position</strong> na oferta do Núcleo IA</li></ol>' ||
          '<p style="color:#666;font-size:13px;">O PMI envia esse aviso de <code>donotreply@pmi.org</code> — se não encontrar, confira sua caixa de spam.</p>' ||
          '<p style="color:#666;font-size:13px;">Se preferir não prosseguir, responda este e-mail com &quot;desisto&quot; — sem problema nenhum. Sua candidatura será encerrada e não enviaremos mais comunicações sobre o processo seletivo.</p>' ||
          '<p>Obrigado!<br/>Núcleo IA &amp; GP</p>' ||
          '<p style="color:#888;font-size:12px;border-top:1px solid #eee;padding-top:8px;">Este e-mail foi enviado pelo <strong>Núcleo IA — capítulo voluntário do PMI</strong> porque sua candidatura está aprovada e há uma ação pendente no portal do PMI. Dúvidas: responda este e-mail.</p>',
    'en', '<p>Hello {{first_name}},</p>' ||
          '<p>You are receiving this email because your application to Núcleo IA was approved and there is a pending action on the PMI portal to complete your entry as a volunteer.</p>' ||
          '<p>To finish, accept the position on the PMI portal:</p>' ||
          '<ol><li>Go to <a href="https://volunteer.pmi.org">volunteer.pmi.org</a></li>' ||
          '<li>Open the <strong>My Info &amp; Activity</strong> menu</li>' ||
          '<li>Click <strong>Accept Position</strong> on the Núcleo IA offer</li></ol>' ||
          '<p style="color:#666;font-size:13px;">PMI sends this notice from <code>donotreply@pmi.org</code> — if you can''t find it, check your spam folder.</p>' ||
          '<p style="color:#666;font-size:13px;">If you prefer not to proceed, reply to this email with &quot;withdraw&quot; — no problem at all. Your application will be closed and we will not send further communications about the selection process.</p>' ||
          '<p>Thank you!<br/>Núcleo IA &amp; GP</p>' ||
          '<p style="color:#888;font-size:12px;border-top:1px solid #eee;padding-top:8px;">This email was sent by <strong>Núcleo IA — a PMI volunteer chapter</strong> because your application is approved and there is a pending action on the PMI portal. Questions: reply to this email.</p>',
    'es', '<p>Hola {{first_name}},</p>' ||
          '<p>Recibes este correo porque tu candidatura a Núcleo IA fue aprobada y hay una acción pendiente en el portal del PMI para completar tu ingreso como voluntario(a).</p>' ||
          '<p>Para finalizar, acepta la posición en el portal del PMI:</p>' ||
          '<ol><li>Ingresa a <a href="https://volunteer.pmi.org">volunteer.pmi.org</a></li>' ||
          '<li>Abre el menú <strong>My Info &amp; Activity</strong></li>' ||
          '<li>Haz clic en <strong>Accept Position</strong> en la oferta de Núcleo IA</li></ol>' ||
          '<p style="color:#666;font-size:13px;">El PMI envía este aviso desde <code>donotreply@pmi.org</code> — si no lo encuentras, revisa tu carpeta de spam.</p>' ||
          '<p style="color:#666;font-size:13px;">Si prefieres no continuar, responde este correo con &quot;desisto&quot; — sin problema. Tu candidatura será cerrada y no enviaremos más comunicaciones sobre el proceso de selección.</p>' ||
          '<p>¡Gracias!<br/>Núcleo IA &amp; GP</p>' ||
          '<p style="color:#888;font-size:12px;border-top:1px solid #eee;padding-top:8px;">Este correo fue enviado por <strong>Núcleo IA — capítulo voluntario del PMI</strong> porque tu candidatura está aprobada y hay una acción pendiente en el portal del PMI. Dudas: responde este correo.</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}},\n\nSua candidatura ao Núcleo IA foi aprovada e há uma ação pendente no portal do PMI para concluir sua entrada como voluntário(a).\n\nPara finalizar:\n1. Acesse volunteer.pmi.org\n2. Abra o menu My Info & Activity\n3. Clique em Accept Position na oferta do Núcleo IA\n\nO PMI envia esse aviso de donotreply@pmi.org — confira o spam.\n\nSe preferir não prosseguir, responda com "desisto" — sua candidatura será encerrada e não enviaremos mais comunicações.\n\nNúcleo IA & GP\n---\nEnviado pelo Núcleo IA (capítulo voluntário do PMI). Candidatura aprovada, ação pendente no portal do PMI.',
    'en', 'Hello {{first_name}},\n\nYour application to Núcleo IA was approved and there is a pending action on the PMI portal to complete your entry as a volunteer.\n\nTo finish:\n1. Go to volunteer.pmi.org\n2. Open the My Info & Activity menu\n3. Click Accept Position on the Núcleo IA offer\n\nPMI sends this notice from donotreply@pmi.org — check your spam.\n\nIf you prefer not to proceed, reply with "withdraw" — your application will be closed and we will not send further communications.\n\nNúcleo IA & GP\n---\nSent by Núcleo IA (a PMI volunteer chapter). Application approved, pending action on the PMI portal.',
    'es', 'Hola {{first_name}},\n\nTu candidatura a Núcleo IA fue aprobada y hay una acción pendiente en el portal del PMI para completar tu ingreso como voluntario(a).\n\nPara finalizar:\n1. Ingresa a volunteer.pmi.org\n2. Abre el menú My Info & Activity\n3. Haz clic en Accept Position en la oferta de Núcleo IA\n\nEl PMI envía este aviso desde donotreply@pmi.org — revisa tu spam.\n\nSi prefieres no continuar, responde con "desisto" — tu candidatura será cerrada y no enviaremos más comunicaciones.\n\nNúcleo IA & GP\n---\nEnviado por Núcleo IA (capítulo voluntario del PMI). Candidatura aprobada, acción pendiente en el portal del PMI.'
  ),
  jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true)
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

-- ===== 6. RPC: process_pending_vep_offer_reminders (cron-driven, single-fire) =====
CREATE OR REPLACE FUNCTION public.process_pending_vep_offer_reminders()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $func$
DECLARE
  v_app record;
  v_grace interval;
  v_first_name text;
  v_reminders_sent int := 0;
  v_errors jsonb := '[]'::jsonb;
  v_processed jsonb := '[]'::jsonb;
BEGIN
  -- Cron-context auth bypass (sem JWT). Espelha p92 process_pending_reschedule_nudges / ADR-0028.
  -- Esta RPC so e invocada por pg_cron; um usuario real precisa de manage_member.
  IF auth.role() IS NOT NULL AND auth.role() NOT IN ('service_role') AND auth.uid() IS NOT NULL THEN
    IF NOT public.can_by_member(
      (SELECT id FROM public.members WHERE auth_id = auth.uid()),
      'manage_member'
    ) THEN
      RAISE EXCEPTION 'Unauthorized: cron RPC requires manage_member or service_role';
    END IF;
  END IF;

  -- Janela configuravel (J4 sla_policies) com fallback ao literal.
  SELECT value_interval INTO v_grace FROM public.sla_policies WHERE policy_key = 'offer_accept_grace';
  v_grace := COALESCE(v_grace, interval '7 days');

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.first_name, a.email, a.vep_offer_extended_at
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'approved'
      AND a.vep_status_raw = 'OfferExtended'
      AND a.vep_offer_reminder_sent_at IS NULL
      AND a.vep_offer_extended_at IS NOT NULL
      AND a.vep_offer_extended_at < now() - v_grace
      AND c.status = 'open'
      AND a.email IS NOT NULL
  LOOP
    v_first_name := COALESCE(NULLIF(v_app.first_name, ''), split_part(v_app.applicant_name, ' ', 1));

    BEGIN
      PERFORM public.campaign_send_one_off(
        p_template_slug := 'vep_offer_accept_reminder',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object('first_name', v_first_name),
        p_metadata := jsonb_build_object(
          'source', 'process_pending_vep_offer_reminders',
          'application_id', v_app.id,
          'language', 'pt',
          'offer_extended_at', v_app.vep_offer_extended_at,
          'days_since_offer', EXTRACT(EPOCH FROM (now() - v_app.vep_offer_extended_at)) / 86400.0
        )
      );

      UPDATE public.selection_applications
      SET vep_offer_reminder_sent_at = now()
      WHERE id = v_app.id;

      v_reminders_sent := v_reminders_sent + 1;
      -- LGPD: return payload carries IDs + metrics only, never name/email (a manage_member
      -- caller would otherwise see full names; cron discards the return). code-reviewer MEDIUM.
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'days_since_offer', EXTRACT(EPOCH FROM (now() - v_app.vep_offer_extended_at)) / 86400.0
      );

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'reminders_sent', v_reminders_sent,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.process_pending_vep_offer_reminders() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_pending_vep_offer_reminders() TO authenticated, service_role;

COMMENT ON FUNCTION public.process_pending_vep_offer_reminders() IS
'Cron-driven RPC (D7): lembra candidatos approved+OfferExtended (oferta VEP estendida ha > offer_accept_grace, '
'ciclo open) a clicar Accept Position no volunteer.pmi.org. Single-fire por candidatura '
'(vep_offer_reminder_sent_at). Auth: bypass para cron (sem JWT) per ADR-0028; usuario real exige manage_member. '
'Padrao p92. D7 (2026-06-18).';

-- ===== 7. Pg_cron: diario 17:00 UTC (evita cluster 14h/15h/16h dos demais crons de selecao) =====
SELECT cron.unschedule('nudge-vep-offer-accept-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'nudge-vep-offer-accept-daily');

SELECT cron.schedule(
  'nudge-vep-offer-accept-daily',
  '0 17 * * *',
  $cron$ SELECT public.process_pending_vep_offer_reminders() $cron$
);

NOTIFY pgrst, 'reload schema';
