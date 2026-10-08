-- #2580 frente 2, regra 3 (decisoes do GP de 08/10/2026, D1 a D3 da PR D): o mesmo tipo de aviso para a mesma pessoa
-- em ate 7 dias vira item do resumo semanal, nao e-mail novo.
--
-- D1: "mesmo tema" e o tipo da notificacao. Quando a taxonomia da #2586 existir, o tipo vira tema sem mexer no gatilho.
-- D2 (opcao B): a repeticao vai para o resumo semanal, exceto os tipos com prazo (ratificacao de PI, curadoria, wiki),
--     que seguem so com o limite de 1 e-mail por dia. Por isso a regra e uma LISTA de tipos informativos, e nao "todos
--     menos os com prazo": tipo novo nasce fora da regra, porque atrasar um aviso com prazo custa mais que um e-mail a
--     mais. Urgentes (public._is_urgent_email_type) nunca entram na lista.
-- D3: lembrete do mesmo item fica fora da regra. A repeticao so conta quando o item (source_id) e outro.
--
-- So rebaixa para quem recebe o resumo semanal (o mesmo filtro de generate_weekly_member_digest_cron). Para os outros,
-- rebaixar seria sumir com o e-mail.

CREATE OR REPLACE FUNCTION public._notification_repeat_to_digest()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.delivery_mode IS DISTINCT FROM 'transactional_immediate' THEN RETURN NEW; END IF;
  IF NEW.type NOT IN (
    'engagement_welcome',
    'engagement_added',
    'member_offboarded',
    'card_comment_mention',
    'certificate_issued',
    'webinar_status_completed',
    'governance_cr_approved',
    'project_charter_approved'
  ) THEN RETURN NEW; END IF;
  IF public._is_urgent_email_type(NEW.type) THEN RETURN NEW; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = NEW.recipient_id
      AND m.is_active = true
      AND m.notify_weekly_digest = true
      AND m.notify_delivery_mode_pref IN ('weekly_digest', 'custom_per_type')
  ) THEN RETURN NEW; END IF;

  IF EXISTS (
    SELECT 1 FROM public.notifications p
    WHERE p.recipient_id = NEW.recipient_id
      AND p.type = NEW.type
      AND p.delivery_mode = 'transactional_immediate'
      AND p.created_at >= now() - interval '7 days'
      AND p.source_id IS DISTINCT FROM NEW.source_id
  ) THEN
    NEW.delivery_mode := 'digest_weekly';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._notification_repeat_to_digest() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notification_repeat_to_digest ON public.notifications;
CREATE TRIGGER trg_notification_repeat_to_digest
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public._notification_repeat_to_digest();
