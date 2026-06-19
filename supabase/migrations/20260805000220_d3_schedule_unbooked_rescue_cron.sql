-- ─────────────────────────────────────────────────────────────────────────────
-- D3 auto-rescue — GO-LIVE: agenda o cron _selection_unbooked_rescue_cron().
--
-- Follow-up de 20260805000219 (D3 auto-rescue unbooked), que CRIOU o cron mas o
-- deixou NÃO AGENDADO atrás de 2 gates. Gates liberados pelo PM (2026-06-18):
--   R1 — copy da linha de "saída por inação" no template selection_cutoff_approved: APROVADA.
--   R5 — DPA do provedor do link de booking: VERIFICADO.
--
-- Horário: 15:30 UTC — ENTRE selection-stuck-scheduled-rescue-daily (15:00) e o
-- detector #781 detect-stuck-selection-funnel-daily (16:00). Roda antes do detector de
-- propósito: o re-convite re-seta cutoff_approved_email_sent_at=now(), então o detector
-- às 16:00 não notifica o GP sobre um caso que o auto-rescue acabou de tratar.
--
-- cron.schedule UPSERTS por jobname (idempotente). Snippet original em COMMENT na §3 da
-- mig 20260805000219. Sem NOTIFY pgrst: não muda a superfície PostgREST.
-- Rollback: SELECT cron.unschedule('selection-unbooked-rescue-daily');
-- ─────────────────────────────────────────────────────────────────────────────
SELECT cron.schedule(
  'selection-unbooked-rescue-daily',
  '30 15 * * *',
  $cron$SELECT public._selection_unbooked_rescue_cron()$cron$
);
