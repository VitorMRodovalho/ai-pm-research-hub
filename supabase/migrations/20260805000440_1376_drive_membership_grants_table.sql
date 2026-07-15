-- #1376 / ADR-0124: auto-GRANT of Drive workspace access for ACTIVE tribe/initiative members.
--
-- Closes the auto-revoke ↔ auto-grant asymmetry. #209/ADR-0107 built auto-REVOKE (offboarded
-- members) and #301/ADR-0108 built a curation FILE-level grant, but NOTHING granted the workspace
-- folder to active tribe/initiative members: access depended on a human sharing each folder by hand,
-- which broke silently on every reorg / folder move / new member (the #1375 incident). This table is
-- the GRANT ledger for the roster×folder reconcile (mirror of drive_offboarding_audit, grant side).
--
-- Scope note: unlike drive_curation_grants (file-level, role=commenter, least-privilege for curators),
-- this grants the WORKSPACE FOLDER as role=writer (Editor) to every active engaged member — the
-- collaboration model tribes always had (folders shared as Editor). Revocation stays the offboarding
-- lane (#209): when a member is offboarded, the offboarding scan detects+revokes; this ledger only
-- records the grant side. permission_email is PII → deny-all RLS, SECURITY DEFINER read only.

CREATE TABLE IF NOT EXISTS public.drive_membership_grants (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       uuid NOT NULL,
  initiative_id         uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  -- The folder the grant targets (a workspace link). Kept denormalized so a terminal row survives
  -- an unlink (history), and so the EF can POST without re-reading the link.
  initiative_drive_link_id uuid REFERENCES public.initiative_drive_links(id) ON DELETE SET NULL,
  drive_folder_id       text NOT NULL,
  drive_folder_url      text,
  -- Grantee: an active engaged member. person_id is the V4 primitive; member_id/email resolved for
  -- the Drive POST + audit. permission_id is produced BY the grant (the future revoke target).
  grantee_person_id     uuid REFERENCES public.persons(id) ON DELETE CASCADE,
  grantee_member_id     uuid REFERENCES public.members(id) ON DELETE CASCADE,
  permission_email      citext NOT NULL,
  permission_id         text,                 -- null until granted
  role                  text NOT NULL DEFAULT 'writer'
                          CHECK (role IN ('reader','commenter','writer')),
  -- Lifecycle: pending_grant → granted | failed ; already_present = roster email already in the folder
  -- ACL (no Drive call, recorded for observability). Terminal rows accrue as immutable history.
  status                text NOT NULL DEFAULT 'pending_grant'
                          CHECK (status IN ('pending_grant','granted','failed','already_present','skipped')),
  api_error             jsonb,
  reconcile_source      text,                 -- 'cron' | 'provision' | 'manual' | 'event'
  requested_at          timestamptz NOT NULL DEFAULT now(),
  granted_at            timestamptz,
  last_dispatched_at    timestamptz,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.drive_membership_grants IS '#1376 / ADR-0124: auto-grant ledger of Drive WORKSPACE access (role=writer) for active tribe/initiative members. GRANT mirror of #209 offboarding revoke. permission_email is PII — deny-all RLS, SECURITY DEFINER read only. Idempotent on (drive_folder_id, permission_email) while a grant is live.';

-- Idempotency: at most ONE row per (folder × member email) across the reconcilable statuses
-- (pending_grant/granted/failed) — so the daily cron UPDATES the row (flip failed→granted on a retry
-- that now succeeds, refresh last_dispatched) instead of accreting a duplicate every run. `skipped`
-- and `already_present` are terminal/non-persisted and excluded. The ON CONFLICT target in
-- upsert_membership_drive_grants MUST mirror this predicate exactly (partial-index inference).
CREATE UNIQUE INDEX IF NOT EXISTS drive_membership_grants_active_uidx
  ON public.drive_membership_grants (drive_folder_id, permission_email)
  WHERE status IN ('pending_grant','granted','failed');

CREATE INDEX IF NOT EXISTS drive_membership_grants_status_idx     ON public.drive_membership_grants (status);
CREATE INDEX IF NOT EXISTS drive_membership_grants_initiative_idx ON public.drive_membership_grants (initiative_id);
CREATE INDEX IF NOT EXISTS drive_membership_grants_member_idx     ON public.drive_membership_grants (grantee_member_id);

-- LGPD fail-closed: RLS on, deny-all to public; all access via SECURITY DEFINER RPCs (read) /
-- service-role EF (grant). Mirror of drive_curation_grants / drive_offboarding_audit.
ALTER TABLE public.drive_membership_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS drive_membership_grants_deny_all ON public.drive_membership_grants;
CREATE POLICY drive_membership_grants_deny_all ON public.drive_membership_grants
  AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);

REVOKE ALL ON public.drive_membership_grants FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
