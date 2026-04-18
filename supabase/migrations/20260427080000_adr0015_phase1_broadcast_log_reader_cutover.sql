-- ============================================================================
-- ADR-0015 Phase 1 — broadcast_log reader cutover (4th C3 table)
--
-- Scope: 2 reader RPCs refactored. broadcast_log.tribe_id is NOT NULL
-- (every row scoped to a tribe), so INNER JOIN initiatives is safe.
-- Dual-write integrity: 25/25 both. Lossless.
--
-- Changed RPCs:
--   1. broadcast_history       — LEFT JOIN tribes → initiatives; filter via legacy_tribe_id
--   2. broadcast_count_today   — INNER JOIN initiatives for filter
--
-- NOT changed (writes still valid; dual-write triggers sync):
--   - send_tribe_broadcast / send_comms_broadcast (EFs still write tribe_id)
--   - platform_activity_summary — references members.tribe_id (C4, separate), not
--     broadcast_log.tribe_id. No refactor needed.
--
-- ADR: ADR-0015 Phase 1, ADR-0005
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. broadcast_history — LEFT JOIN initiatives for tribe_name + filter
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.broadcast_history(
  p_tribe_id integer DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  tribe_id integer,
  tribe_name text,
  subject text,
  recipient_count integer,
  sent_at timestamp with time zone,
  sent_by_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  SELECT
    bl.id,
    bl.tribe_id,
    i.title AS tribe_name,  -- ADR-0015 Phase 1: derive from initiative
    bl.subject,
    bl.recipient_count,
    bl.sent_at,
    m.name AS sent_by_name
  FROM public.broadcast_log bl
  LEFT JOIN public.initiatives i ON i.id = bl.initiative_id  -- ADR-0015 Phase 1
  LEFT JOIN public.members m ON m.id = bl.sender_id
  WHERE (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)  -- ADR-0015 Phase 1
  ORDER BY bl.sent_at DESC
  LIMIT p_limit;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. broadcast_count_today — INNER JOIN initiatives (tribe_id NOT NULL invariant)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.broadcast_count_today(
  p_tribe_id integer
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  SELECT count(*)::integer
  FROM public.broadcast_log bl
  JOIN public.initiatives i ON i.id = bl.initiative_id  -- ADR-0015 Phase 1: INNER (tribe_id NOT NULL)
  WHERE i.legacy_tribe_id = p_tribe_id
    AND bl.sent_at >= current_date
    AND bl.status = 'sent';
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK:
--   broadcast_history:
--     LEFT JOIN public.tribes t ON t.id = bl.tribe_id
--     t.name as tribe_name
--     WHERE p_tribe_id is null OR bl.tribe_id = p_tribe_id
--   broadcast_count_today:
--     WHERE tribe_id = p_tribe_id AND sent_at >= current_date AND status = 'sent'
-- ═══════════════════════════════════════════════════════════════════════════
