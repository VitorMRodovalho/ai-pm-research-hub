-- #209 / ADR-0107 / ADR-0094 G2.4+G4.1: Drive permission revocation cascade on member offboarding.
-- LGPD Art.16 — queue ex-members' Drive permissions, GP-approval-gated revocation.

CREATE TABLE IF NOT EXISTS public.drive_offboarding_audit (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL,
  member_id         uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  engagement_id     uuid REFERENCES public.engagements(id),  -- ADR-0094 G2.4 readiness; nullable for #209
  -- Drive coordinates
  drive_file_id     text NOT NULL,
  drive_file_name   text,
  drive_file_url    text,
  is_shared_drive   boolean NOT NULL DEFAULT false,
  shared_drive_id   text,
  -- Permission coordinates (the DELETE target)
  permission_id     text NOT NULL,
  permission_email  citext NOT NULL,
  permission_role   text,
  permission_type   text,
  -- Lifecycle
  status            text NOT NULL DEFAULT 'pending_revoke'
                     CHECK (status IN ('pending_revoke','approved','revoked','failed','already_absent','skipped')),
  google_error      jsonb,
  -- Audit trail
  detected_at       timestamptz NOT NULL DEFAULT now(),
  last_detected_at  timestamptz NOT NULL DEFAULT now(),
  approved_by       uuid REFERENCES public.members(id),
  approved_at       timestamptz,
  revoked_at        timestamptz,
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.drive_offboarding_audit IS '#209 / ADR-0107: Google Drive permissions held by offboarded members, GP-approval-gated revocation cascade (LGPD Art.16). permission_email is PII — deny-all RLS, SECURITY DEFINER read only.';

-- Idempotency (core requirement): at most ONE actionable row per concrete grant.
-- Partial index lets terminal rows (revoked/failed/already_absent/skipped) accrue as immutable history,
-- while preventing duplicate pending/approved rows on weekly re-scan.
CREATE UNIQUE INDEX IF NOT EXISTS drive_offb_audit_open_grant_uidx
  ON public.drive_offboarding_audit (drive_file_id, permission_id)
  WHERE status IN ('pending_revoke','approved');

CREATE INDEX IF NOT EXISTS drive_offb_audit_status_idx ON public.drive_offboarding_audit (status);
CREATE INDEX IF NOT EXISTS drive_offb_audit_member_idx ON public.drive_offboarding_audit (member_id);
CREATE INDEX IF NOT EXISTS drive_offb_audit_org_idx    ON public.drive_offboarding_audit (organization_id);

-- LGPD fail-closed: RLS on, deny-all to public, no anon/authenticated grants.
-- All access via SECURITY DEFINER RPCs (read) / service-role EFs (scan+revoke).
ALTER TABLE public.drive_offboarding_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS drive_offb_audit_deny_all ON public.drive_offboarding_audit;
CREATE POLICY drive_offb_audit_deny_all ON public.drive_offboarding_audit
  AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);

REVOKE ALL ON public.drive_offboarding_audit FROM anon, authenticated;
