-- Issue #91 G4 (p49) — resync `is_returning_member` for legacy rows that the
-- prior broad-match logic flagged TRUE without an offboarding record on file.
--
-- 20260514020000 tightened the import predicate and backfilled rows that were
-- FALSE-but-should-be-TRUE. This migration handles the opposite drift: rows
-- that were TRUE-but-should-be-FALSE because the matched member had no
-- offboarding record (e.g., active members promoted from the same cycle who
-- got flagged under the broader prior semantic).
--
-- The UPDATE is idempotent — it converges every row to the predicate the new
-- import logic uses, so re-running is a no-op.

UPDATE selection_applications sa
SET is_returning_member = EXISTS (
  SELECT 1
  FROM member_offboarding_records mor
  JOIN members m ON m.id = mor.member_id
  WHERE lower(trim(m.email)) = lower(trim(sa.email))
)
WHERE sa.is_returning_member <> EXISTS (
  SELECT 1
  FROM member_offboarding_records mor
  JOIN members m ON m.id = mor.member_id
  WHERE lower(trim(m.email)) = lower(trim(sa.email))
);
