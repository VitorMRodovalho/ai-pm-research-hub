-- #1372: fail-early guard — an engagement window must never end before it starts.
-- Context: pmi-vep-sync fanned a per-vaga VEP serviceEndDateUTC across a person's active
-- engagements, stamping a stale end_date (< start_date) onto workgroup engagements and demoting
-- a promoted leader to guest on the next trigger fire (#1362 recurrence). The worker fix scopes the
-- write per-vaga; this CHECK is the writer-agnostic backstop so ANY future writer that produces
-- end<start fails at write time instead of silently voiding authority.
-- Verified 0 existing violations across all statuses before adding (2026-07-13).
ALTER TABLE public.engagements
  ADD CONSTRAINT engagements_end_after_start_check
  CHECK (end_date IS NULL OR end_date >= start_date);
