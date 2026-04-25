-- ADR-0022 W1 — notifications.delivery_mode + digest tracking columns.
--
-- Goal: schema substrate for ADR-0022 Communication Batching. Subsequent waves
-- (W2 digest content, W3 leader digest, W3 smart-skip, W3 broadcast rate-limit)
-- opt into delivery routing without further DDL.
--
-- Spec: docs/specs/SPEC_ADR_0022_W1.md
-- Catalog: docs/adr/ADR-0022-notification-types-catalog.json
--
-- Defaults applied:
--   - Q1 (modes): single 'digest_weekly' default; 4-mode UI deferred to W2.
--   - Q6 (producer audit): 5 mandatory-immediate types backfilled here.
--     The remaining 11 types either keep default 'digest_weekly' or get
--     conditional handling at the producer site (W2/W3).
--   - Q7 (legacy rows): accept default 'digest_weekly' for all 2349 existing
--     rows; producers update specific rows post-deploy if needed.
--
-- Rollback:
--   DROP INDEX IF EXISTS idx_notifications_digest_pending;
--   ALTER TABLE public.notifications
--     DROP COLUMN IF EXISTS digest_batch_id,
--     DROP COLUMN IF EXISTS digest_delivered_at,
--     DROP COLUMN IF EXISTS delivery_mode;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS delivery_mode text NOT NULL
    DEFAULT 'digest_weekly'
    CHECK (delivery_mode IN ('transactional_immediate','digest_weekly','suppress')),
  ADD COLUMN IF NOT EXISTS digest_delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS digest_batch_id uuid;

-- Partial index for the W2 digest aggregation query — only ~10-30 pending
-- rows per recipient at any time. Full index would scan 2349+ rows and grow
-- unbounded. Partial keeps the hot path tight.
CREATE INDEX IF NOT EXISTS idx_notifications_digest_pending
  ON public.notifications (recipient_id, created_at)
  WHERE delivery_mode = 'digest_weekly' AND digest_delivered_at IS NULL;

-- Backfill 5 mandatory-immediate types (Q6 W1 scope). Producers will be
-- updated to set delivery_mode explicitly in companion migrations below.
UPDATE public.notifications SET delivery_mode = 'transactional_immediate'
  WHERE type IN (
    'volunteer_agreement_signed',
    'ip_ratification_gate_pending',
    'system_alert',
    'certificate_ready',
    'member_offboarded'
  )
  AND delivery_mode <> 'transactional_immediate';

-- Backfill 3 suppressed types (in-app only — already not emailed today via
-- producer-side gate or empty body, but explicit suppress avoids future drift).
UPDATE public.notifications SET delivery_mode = 'suppress'
  WHERE type IN ('attendance_detractor','info','system')
  AND delivery_mode <> 'suppress';

COMMENT ON COLUMN public.notifications.delivery_mode IS
  'ADR-0022: transactional_immediate | digest_weekly | suppress. Default digest_weekly. Producers set explicitly when row should bypass digest (urgent/transactional). See docs/adr/ADR-0022-notification-types-catalog.json for the type→mode mapping.';
COMMENT ON COLUMN public.notifications.digest_delivered_at IS
  'ADR-0022: when the row was sent as part of a weekly digest batch. NULL = not yet delivered (or non-digest mode).';
COMMENT ON COLUMN public.notifications.digest_batch_id IS
  'ADR-0022: groups rows that were delivered in the same digest send (one batch per recipient per send).';

NOTIFY pgrst, 'reload schema';
