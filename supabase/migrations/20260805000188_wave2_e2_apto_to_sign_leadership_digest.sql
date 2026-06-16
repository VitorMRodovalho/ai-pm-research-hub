-- Wave 2 / E2: daily leadership digest — "voluntários aptos a assinar o termo".
--
-- Gap (discovery #740): a liderança (manage_member: GP + Diretoria de Voluntariado)
-- recebe notif quando alguém JÁ assinou (volunteer_agreement_signed) e sobre
-- entrevistas, mas NADA quando um candidato fica APTO a assinar. O lado-candidato
-- já existe (selection_termo_due, p157/p159). Este cron fecha o lado-liderança como
-- DIGEST DIÁRIO (decisão PM 2026-06-16: menor ruído que push por-candidato).
--
-- Coorte "apto a assinar" = engagement de voluntário ativo que exige acordo e ainda
-- não tem certificado (mesma fonte canônica do get_pending_agreement_engagements / E1).
-- Entrega: 1 notificação in-app/dia por destinatário de liderança, delivery_mode
-- 'suppress' (sino, sem e-mail — nudge diário não deve spammar caixa), link p/ a
-- fila priorizada E1 em /admin/certificates. Idempotente: 1×/dia (janela 20h).
--
-- Notas de escopo (code-reviewer #746/E2):
--  * Coorte filtra ae.kind='volunteer' (único kind com template de termo pronto) e
--    m.is_active=TRUE (acionável agora) — narrowing DELIBERADO vs o total irrestrito
--    de get_pending_agreement_engagements; DISTINCT m.id evita fan-out person→member.
--  * v_not_notified é um HINT advisory (mesma heurística LIKE do RPC E1), não
--    autoritativo; janela de 365d é folgada — tighten p/ ae.start_date é follow-up (#740).
--  * delivery_mode hardcoded 'suppress' no INSERT (não via _delivery_mode_for) p/ não
--    clobberar o helper; registrar o tipo no catálogo ADR-0022 + helper = follow-up (#740).
--
-- Rollback:
--   SELECT cron.unschedule('selection-apto-to-sign-digest-daily');
--   DROP FUNCTION IF EXISTS public._selection_apto_to_sign_digest_cron();

CREATE OR REPLACE FUNCTION public._selection_apto_to_sign_digest_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $func$
DECLARE
  v_apto_total int := 0;
  v_not_notified int := 0;
  v_inserted int := 0;
  v_run_at timestamptz := now();
BEGIN
  WITH apto AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.auth_engagements ae
    JOIN public.persons p ON p.id = ae.person_id
    JOIN public.members m ON m.person_id = p.id
    WHERE ae.status = 'active'
      AND ae.requires_agreement IS TRUE
      AND ae.agreement_certificate_id IS NULL
      AND ae.kind = 'volunteer'
      AND m.is_active IS TRUE
  )
  SELECT
    (SELECT count(*) FROM apto),
    (SELECT count(*) FROM apto a WHERE NOT EXISTS (
       SELECT 1 FROM public.notifications n
       WHERE n.recipient_id = a.member_id
         AND n.created_at > now() - interval '365 days'
         AND (lower(coalesce(n.type, ''))  LIKE '%agreement%'
           OR lower(coalesce(n.type, ''))  LIKE '%termo%'
           OR lower(coalesce(n.title, '')) LIKE '%termo%'
           OR lower(coalesce(n.body, ''))  LIKE '%termo%')
    ))
  INTO v_apto_total, v_not_notified;

  IF v_apto_total = 0 THEN
    RETURN jsonb_build_object('success', true, 'apto_total', 0, 'inserted', 0, 'run_at', v_run_at);
  END IF;

  WITH inserted AS (
    INSERT INTO public.notifications (
      recipient_id, type, title, body, link, source_type, source_id, delivery_mode
    )
    SELECT
      m.id,
      'selection_apto_to_sign_digest',
      'Voluntários aptos a assinar o termo',
      format(
        '%s voluntário(s) apto(s) a assinar o Termo de Voluntariado%s. Revise e priorize em /admin/certificates.',
        v_apto_total,
        CASE WHEN v_not_notified > 0 THEN format(' (%s ainda sem notificação)', v_not_notified) ELSE '' END
      ),
      '/admin/certificates',
      'volunteer_agreement_digest',
      NULL,
      'suppress'
    FROM public.members m
    WHERE m.is_active IS TRUE
      AND public.can_by_member(m.id, 'manage_member')
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'selection_apto_to_sign_digest'
          AND n.created_at > now() - interval '20 hours'
      )
    RETURNING 1
  )
  SELECT count(*)::int INTO v_inserted FROM inserted;

  RETURN jsonb_build_object(
    'success', true,
    'apto_total', v_apto_total,
    'not_notified', v_not_notified,
    'inserted', v_inserted,
    'run_at', v_run_at
  );
END;
$func$;

REVOKE ALL ON FUNCTION public._selection_apto_to_sign_digest_cron() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._selection_apto_to_sign_digest_cron() TO service_role;

COMMENT ON FUNCTION public._selection_apto_to_sign_digest_cron() IS
'Wave 2 #740 E2: daily leadership digest for volunteers ready to sign the term. '
'Cohort = active volunteer engagement requiring agreement with no certificate '
'(canonical pending-agreement source, shared with get_pending_agreement_engagements / E1). '
'Emits ONE in-app notification (delivery_mode suppress = bell, no email) per manage_member '
'holder, idempotent on a 20h window (once/day), linking to /admin/certificates. Candidate '
'side already covered by selection_termo_due (p157/p159).';

-- pg_cron — daily 13:45 UTC (10:45 BRT), staggered from the other selection crons.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'selection-apto-to-sign-digest-daily') THEN
    PERFORM cron.unschedule('selection-apto-to-sign-digest-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'selection-apto-to-sign-digest-daily',
  '45 13 * * *',
  $cron$ SELECT public._selection_apto_to_sign_digest_cron() $cron$
);

NOTIFY pgrst, 'reload schema';
