-- #3110 (parte 2): o cron diario do aviso de filiacao pendente.
--
-- Separado da migration da funcao por decisao do GP (20/11/2026): ele ve a lista do ensaio
-- (nudge_entry_chapter_cohort(true)) antes do primeiro disparo. Aplicar SO depois desse OK. A partir daqui o aviso sai
-- por e-mail imediato (entry_chapter_action_needed => transactional_immediate), com dedupe de 30 dias.
--
-- 12:30 UTC = 09:30 em Brasilia; minuto livre (12:40 tem onboarding-auto-complete-daily).
--
-- Rollback: SELECT cron.unschedule('affiliation-action-needed-nudge-daily');

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'affiliation-action-needed-nudge-daily') THEN
    PERFORM cron.unschedule('affiliation-action-needed-nudge-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'affiliation-action-needed-nudge-daily',
  '30 12 * * *',
  $cron$ SELECT public.nudge_entry_chapter_cohort(p_dry_run := false) $cron$
);

-- pos-condicao: um job so, ativo, chamando o aviso de verdade
DO $postcondition$
BEGIN
  IF (SELECT count(*) FROM cron.job WHERE command ~ 'nudge_entry_chapter_cohort') <> 1
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'affiliation-action-needed-nudge-daily' AND active
                    AND command ~ 'p_dry_run := false') THEN
    RAISE EXCEPTION '#3110: cron do aviso nao ficou como esperado';
  END IF;
END
$postcondition$;
