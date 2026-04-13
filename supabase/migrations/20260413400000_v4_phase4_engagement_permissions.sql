-- ============================================================================
-- V4 Phase 4 — Migration 1/5: engagement_kind_permissions table + seed
-- ADR: ADR-0007 (Authority as Derived Grant from Active Engagements)
-- Rollback: DROP TABLE public.engagement_kind_permissions CASCADE;
-- ============================================================================

-- Maps (kind, role) → allowed actions. This replaces the hardcoded
-- WRITE_ROLES and BOARD_ROLES arrays in nucleo-mcp.
-- Actions are text slugs checked by can().

CREATE TABLE public.engagement_kind_permissions (
  id                serial PRIMARY KEY,
  kind              text NOT NULL REFERENCES public.engagement_kinds(slug) ON DELETE CASCADE,
  role              text NOT NULL,
  action            text NOT NULL,
  scope             text NOT NULL DEFAULT 'initiative'
                    CHECK (scope IN ('global', 'organization', 'initiative')),
  description       text,
  organization_id   uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                    REFERENCES public.organizations(id) ON DELETE RESTRICT,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kind, role, action)
);

COMMENT ON TABLE public.engagement_kind_permissions IS 'V4: Maps (engagement kind, role) → permitted actions. Source of truth for can() function (ADR-0007).';

CREATE INDEX idx_ekp_kind_role ON public.engagement_kind_permissions(kind, role);
CREATE INDEX idx_ekp_action ON public.engagement_kind_permissions(action);

ALTER TABLE public.engagement_kind_permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ekp_select_authenticated"
  ON public.engagement_kind_permissions FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "ekp_org_scope"
  ON public.engagement_kind_permissions AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = public.auth_org());

-- Seed: map current canWrite/canWriteBoard logic to permission rows
-- Actions:
--   write           = general write (canWrite equivalent)
--   write_board     = write to own initiative's board (canWriteBoard equivalent)
--   manage_partner  = partner pipeline access
--   manage_member   = admin member management
--   manage_event    = create/edit events
--   view_pii        = access PII data
--   promote         = promote members to leader track

-- ── volunteer kind permissions ─────────────────────────────────────────────
-- manager → global write + all admin actions
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'manager', 'write', 'organization', 'General write access (canWrite equivalent)'),
  ('volunteer', 'manager', 'write_board', 'organization', 'Write to any board'),
  ('volunteer', 'manager', 'manage_partner', 'organization', 'Partner pipeline management'),
  ('volunteer', 'manager', 'manage_member', 'organization', 'Admin member management'),
  ('volunteer', 'manager', 'manage_event', 'organization', 'Create/edit events'),
  ('volunteer', 'manager', 'view_pii', 'organization', 'Access PII data'),
  ('volunteer', 'manager', 'promote', 'organization', 'Promote members');

-- deputy_manager → same as manager (via designations, org-wide)
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description)
SELECT 'volunteer', 'deputy_manager', action, scope, description
FROM public.engagement_kind_permissions
WHERE kind = 'volunteer' AND role = 'manager';

-- leader → write + manage_event + write_board (initiative-scoped)
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'leader', 'write', 'organization', 'General write access (canWrite equivalent)'),
  ('volunteer', 'leader', 'write_board', 'organization', 'Write to any board'),
  ('volunteer', 'leader', 'manage_event', 'initiative', 'Create/edit events for own initiative'),
  ('volunteer', 'leader', 'view_pii', 'initiative', 'View PII of own initiative members');

-- researcher → write_board on own initiative only
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'researcher', 'write_board', 'initiative', 'Write to own initiative board');

-- facilitator → write_board on own initiative
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'facilitator', 'write_board', 'initiative', 'Write to own initiative board');

-- communicator → write_board on own initiative
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'communicator', 'write_board', 'initiative', 'Write to own initiative board');

-- curator → write_board (cross-initiative per GC rules)
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'curator', 'write_board', 'organization', 'Curators need cross-board access');

-- co_gp → same as manager
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description)
SELECT 'volunteer', 'co_gp', action, scope, description
FROM public.engagement_kind_permissions
WHERE kind = 'volunteer' AND role = 'manager';

-- comms_leader → write + manage_event
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('volunteer', 'comms_leader', 'write', 'organization', 'Comms leader general write'),
  ('volunteer', 'comms_leader', 'write_board', 'organization', 'Comms leader board access'),
  ('volunteer', 'comms_leader', 'manage_event', 'organization', 'Comms leader event management');

-- ── sponsor kind ───────────────────────────────────────────────────────────
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('sponsor', 'sponsor', 'manage_partner', 'organization', 'Sponsors can manage partner pipeline');

-- ── chapter_board kind ─────────────────────────────────────────────────────
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('chapter_board', 'liaison', 'manage_partner', 'organization', 'Chapter liaisons manage partnerships'),
  ('chapter_board', 'board_member', 'view_pii', 'organization', 'Board members can view PII for governance');

-- ── study_group_owner kind ─────────────────────────────────────────────────
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('study_group_owner', 'owner', 'write', 'initiative', 'Study group owner can write in own initiative'),
  ('study_group_owner', 'owner', 'write_board', 'initiative', 'Study group owner board access'),
  ('study_group_owner', 'owner', 'manage_event', 'initiative', 'Study group owner event management');

NOTIFY pgrst, 'reload schema';
