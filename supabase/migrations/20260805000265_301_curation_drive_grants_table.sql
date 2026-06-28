-- #301 / ADR-0108: temporary governed Drive access for curation.
-- GRANT mirror of #209/ADR-0107 (revoke). When a board_item enters curation_pending, the
-- Curation Committee (can_by_member 'curate_content') + any formally assigned reviewer get a
-- time-boxed, auditable `commenter` permission on the submitted artifact (board_item_files);
-- revoked when the item leaves active curation. LGPD least-privilege: file-level, not the
-- whole tribe folder. permission_email is PII — deny-all RLS, SECURITY DEFINER read only.

CREATE TABLE IF NOT EXISTS public.drive_curation_grants (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    uuid NOT NULL,
  board_item_id      uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  -- Drive coordinates (the POST target). drive_file_id from board_item_files.
  drive_file_id      text NOT NULL,
  drive_file_url     text,
  revision_id        text,                 -- #301 acceptance: evidence-bundle field (best-effort)
  -- Grantee (a curator). permission_id is produced BY the grant (≠ #209 where it pre-exists).
  grantee_member_id  uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  permission_email   citext NOT NULL,
  permission_id      text,                 -- null until granted; the future revoke target
  role               text NOT NULL DEFAULT 'commenter'
                       CHECK (role IN ('reader','commenter','writer')),
  grant_reason       text NOT NULL DEFAULT 'committee_handoff'
                       CHECK (grant_reason IN ('committee_handoff','reviewer_assignment','manual')),
  -- Lifecycle: pending_grant → granted | failed ; granted → pending_revoke → revoked | revoke_failed ;
  -- pending_grant that never executed and the item leaves curation → cancelled (no Drive call).
  status             text NOT NULL DEFAULT 'pending_grant'
                       CHECK (status IN ('pending_grant','granted','failed','pending_revoke','revoked','revoke_failed','cancelled')),
  api_error          jsonb,
  -- Audit trail
  requested_at       timestamptz NOT NULL DEFAULT now(),
  granted_at         timestamptz,
  revoked_at         timestamptz,
  last_dispatched_at timestamptz,
  notes              text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.drive_curation_grants IS '#301 / ADR-0108: temporary governed Drive grants for curation (GRANT mirror of #209/ADR-0107). permission_email is PII — deny-all RLS, SECURITY DEFINER read only. Idempotent on (drive_file_id, permission_email) while a grant is active.';

-- Idempotency: at most ONE active grant per (file × curator). Terminal rows
-- (granted-then-revoked / failed / cancelled / revoke_failed) accrue as immutable history, and a
-- re-grant after revoke/cancel opens a fresh row.
CREATE UNIQUE INDEX IF NOT EXISTS drive_curation_grants_active_uidx
  ON public.drive_curation_grants (drive_file_id, permission_email)
  WHERE status IN ('pending_grant','granted','pending_revoke');

CREATE INDEX IF NOT EXISTS drive_curation_grants_status_idx     ON public.drive_curation_grants (status);
CREATE INDEX IF NOT EXISTS drive_curation_grants_item_idx       ON public.drive_curation_grants (board_item_id);
CREATE INDEX IF NOT EXISTS drive_curation_grants_grantee_idx    ON public.drive_curation_grants (grantee_member_id);

-- LGPD fail-closed: RLS on, deny-all to public, no anon/authenticated grants.
-- All access via SECURITY DEFINER RPCs (read) / service-role EF (grant+revoke).
ALTER TABLE public.drive_curation_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS drive_curation_grants_deny_all ON public.drive_curation_grants;
CREATE POLICY drive_curation_grants_deny_all ON public.drive_curation_grants
  AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);

REVOKE ALL ON public.drive_curation_grants FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';
