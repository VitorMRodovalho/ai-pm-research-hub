-- p152 W4 followup (2026-05-12) — selection_interviews dedupe + UNIQUE(calendar_event_id).
--
-- Surfaced em Phase A do W4 calendar sync audit: William Junio tem 4 DB rows
-- para 2 cal events distintos (2 duplicatas com mesmo calendar_event_id +
-- scheduled_at, criadas com diff de microsegundos pelo webhook handler — race
-- condition entre o detect+insert sem locking idempotente).
--
-- Webhook notes indicam padrão "Auto-synced from Calendar webhook" — pattern
-- de calendar→DB sync via webhook que duplicou por dois eventos (race no
-- handler quando recebe webhook notification duplicada ou retried).
--
-- Cleanup:
--   1. DELETE younger of each duplicate pair (kept older = original sync).
--   2. CANCEL phantom rows (DB row sem cal event correspondente; cal foi
--      deletado pelo candidato mas DB row stale).
--   3. ADD partial UNIQUE constraint em (calendar_event_id) WHERE NOT NULL
--      para que próximo race INSERT falhe explicitamente em vez de duplicar.

-- ─── 1) Dedupe — DELETE younger of each pair ─────────────────────────────
DELETE FROM public.selection_interviews
WHERE id IN (
  '00afdcd0-4c22-4b87-8be4-998d18d3d48e',  -- duplicate of bd684651 (rpuvo5d5m8o4tgucdr69qdseoo)
  '6085c8e6-be49-486c-860f-7173aae605fb'   -- duplicate of e711f99e (fpb2f334tg4c2j8io6su59m4f8)
);

-- ─── 2) Mark phantoms as cancelled (preserve audit trail) ────────────────
UPDATE public.selection_interviews
SET status = 'cancelled',
    notes = COALESCE(notes, '') || ' [p152 W4 cleanup: cal event no longer exists in Google Calendar — phantom row from prior reschedule]'
WHERE id IN (
  '3ba4223f-bc4a-4f52-be65-ede73be8e59e',  -- b4lj8042 13/05 19:30 SP — cal deleted
  '0e7c0f87-dfed-491b-b092-72762adfcbd5'   -- ai468v3qbn 13/05 21:30 SP — cal deleted
);

-- ─── 3) Partial UNIQUE constraint ────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uniq_selection_interviews_calendar_event_id
  ON public.selection_interviews (calendar_event_id)
  WHERE calendar_event_id IS NOT NULL;

COMMENT ON INDEX public.uniq_selection_interviews_calendar_event_id IS
  'Prevents webhook race-condition duplicates. p152 W4: William Junio had 4 rows for 2 cal events created with microsecond delta. Pattern: webhook retries or notification dup. Partial WHERE clause allows multi-row legacy/manual interviews without calendar_event_id.';
