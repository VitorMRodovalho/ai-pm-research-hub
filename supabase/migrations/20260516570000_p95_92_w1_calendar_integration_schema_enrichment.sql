-- p95 #92 W1: Calendar integration schema enrichment
-- ====================================================================
-- Aditive only. Backfill events com calendar_event_id existente OR source='calendar_import'
-- → external_calendar_provider='gcal' + sync_status='ok'.
-- Wave 2-N (MCP tools, webhook, sync RPCs) deferred.
--
-- Smoke validated p95 2026-05-05: 5/5 cols shipped, backfill 65 rows ('gcal'/'ok'),
-- invariants 11/11 = 0 violations.

-- 1. external_calendar_provider enum
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS external_calendar_provider text;

ALTER TABLE public.events
  ADD CONSTRAINT events_external_calendar_provider_check
  CHECK (external_calendar_provider IS NULL OR external_calendar_provider IN ('gcal','outlook','ical','other'));

-- 2. timezone (default America/Sao_Paulo)
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'America/Sao_Paulo';

ALTER TABLE public.events
  ADD CONSTRAINT events_timezone_check
  CHECK (timezone IS NULL OR timezone ~ '^[A-Za-z_]+/[A-Za-z_]+');

-- 3. last_synced_at (drift detection prep)
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS last_synced_at timestamptz;

-- 4. sync_status enum
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS sync_status text;

ALTER TABLE public.events
  ADD CONSTRAINT events_sync_status_check
  CHECK (sync_status IS NULL OR sync_status IN ('ok','stale','conflict','manual'));

-- 5. rescheduled_from (audit lineage when event moves)
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS rescheduled_from uuid REFERENCES public.events(id) ON DELETE SET NULL;

-- Index for sync-drift detection queries
CREATE INDEX IF NOT EXISTS ix_events_sync_status_provider
  ON public.events (sync_status, external_calendar_provider, last_synced_at)
  WHERE external_calendar_provider IS NOT NULL;

-- Backfill: events with calendar_event_id OR source='calendar_import' → assume gcal + ok
UPDATE public.events
SET external_calendar_provider = 'gcal',
    sync_status = 'ok'
WHERE (calendar_event_id IS NOT NULL OR source = 'calendar_import')
  AND external_calendar_provider IS NULL;

COMMENT ON COLUMN public.events.external_calendar_provider IS
  'p95 #92 W1: external calendar source if event was imported/synced from external system (gcal/outlook/ical/other). NULL for purely internal events.';
COMMENT ON COLUMN public.events.timezone IS
  'p95 #92 W1: IANA timezone (e.g., America/Sao_Paulo). Default Sao Paulo (matches Núcleo operations). Used to resolve scheduled_at for cross-timezone operations.';
COMMENT ON COLUMN public.events.last_synced_at IS
  'p95 #92 W1: timestamp of last sync operation with external calendar (push or pull). NULL for events never synced.';
COMMENT ON COLUMN public.events.sync_status IS
  'p95 #92 W1: ok | stale | conflict | manual. Computed by sync RPC (Wave 2). manual = explicitly disabled sync.';
COMMENT ON COLUMN public.events.rescheduled_from IS
  'p95 #92 W1: lineage to previous event row if this event resulted from rescheduling. Audit alternative to minutes_edit_history.';

NOTIFY pgrst, 'reload schema';
