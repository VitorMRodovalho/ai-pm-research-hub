-- ============================================================
-- ADR-0045: Meeting↔Board traceability schema hardening (#84 Onda 1)
-- Pure aditivo. Sets up FKs and link tables for future #84 Onda 2 (MCP tools)
-- and Onda 3 (UX + extractor). No behavior change in this migration.
-- Cross-references: #84 (issue), ADR-0012 (organization_id invariant)
-- Rollback: DROP added columns + DROP new tables (no data loss since 0 prod rows)
-- ============================================================

-- ── Section A: meeting_action_items FK linkages ────────────
ALTER TABLE public.meeting_action_items
  ADD COLUMN IF NOT EXISTS board_item_id uuid REFERENCES public.board_items(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS checklist_item_id uuid REFERENCES public.board_item_checklists(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS kind text DEFAULT 'action'
    CHECK (kind IN ('action','decision','followup','general')),
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS resolved_by uuid REFERENCES public.members(id),
  ADD COLUMN IF NOT EXISTS resolution_note text;

CREATE INDEX IF NOT EXISTS idx_meeting_action_items_board_item
  ON public.meeting_action_items(board_item_id) WHERE board_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_meeting_action_items_unresolved
  ON public.meeting_action_items(event_id, resolved_at) WHERE resolved_at IS NULL;

-- ── Section B: event_showcases artifact linkages ───────────
ALTER TABLE public.event_showcases
  ADD COLUMN IF NOT EXISTS board_item_id uuid REFERENCES public.board_items(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS artifact_id uuid REFERENCES public.tribe_deliverables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS xp_awarded integer;

CREATE INDEX IF NOT EXISTS idx_event_showcases_board_item
  ON public.event_showcases(board_item_id) WHERE board_item_id IS NOT NULL;

-- ── Section C: tribe_kpi_contributions table ───────────────
-- Maps annual_kpi_targets to specific initiatives (initiative_id replaces
-- legacy tribe_id per ADR-0015 native-first stance). Enables queries like:
-- "Quais KPIs anuais a Tribo 6 contribui? O que está em risco?"
CREATE TABLE IF NOT EXISTS public.tribe_kpi_contributions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  kpi_target_id uuid NOT NULL REFERENCES public.annual_kpi_targets(id) ON DELETE CASCADE,
  initiative_id uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  contribution_query text,
  weight numeric NOT NULL DEFAULT 1.0 CHECK (weight > 0),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(kpi_target_id, initiative_id)
);

CREATE INDEX IF NOT EXISTS idx_tribe_kpi_contributions_kpi
  ON public.tribe_kpi_contributions(kpi_target_id);
CREATE INDEX IF NOT EXISTS idx_tribe_kpi_contributions_initiative
  ON public.tribe_kpi_contributions(initiative_id);

ALTER TABLE public.tribe_kpi_contributions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tribe_kpi_contrib_select_authenticated ON public.tribe_kpi_contributions;
CREATE POLICY tribe_kpi_contrib_select_authenticated ON public.tribe_kpi_contributions
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS tribe_kpi_contrib_write_manage_platform ON public.tribe_kpi_contributions;
CREATE POLICY tribe_kpi_contrib_write_manage_platform ON public.tribe_kpi_contributions
  FOR ALL TO authenticated USING (
    public.can_by_member((SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), 'manage_platform')
  ) WITH CHECK (
    public.can_by_member((SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), 'manage_platform')
  );

REVOKE ALL ON public.tribe_kpi_contributions FROM anon;
GRANT SELECT ON public.tribe_kpi_contributions TO authenticated;

-- ── Section D: board_item_event_links table ────────────────
-- Cross-reference between cards and events where they were discussed.
-- Enables card timeline 360° (#84 GAP 4) — "this card was discussed in
-- meetings X/Y/Z" + "this meeting changed status of cards A/B".
CREATE TABLE IF NOT EXISTS public.board_item_event_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  link_type text NOT NULL
    CHECK (link_type IN ('discussed','action_emerged','decision','status_changed','showcased')),
  author_id uuid REFERENCES public.members(id),
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(board_item_id, event_id, link_type)
);

CREATE INDEX IF NOT EXISTS idx_board_item_event_links_card
  ON public.board_item_event_links(board_item_id);
CREATE INDEX IF NOT EXISTS idx_board_item_event_links_event
  ON public.board_item_event_links(event_id);

ALTER TABLE public.board_item_event_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS board_item_event_links_select_authenticated ON public.board_item_event_links;
CREATE POLICY board_item_event_links_select_authenticated ON public.board_item_event_links
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS board_item_event_links_write_manage_event ON public.board_item_event_links;
CREATE POLICY board_item_event_links_write_manage_event ON public.board_item_event_links
  FOR ALL TO authenticated USING (
    public.can_by_member((SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), 'manage_event')
  ) WITH CHECK (
    public.can_by_member((SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()), 'manage_event')
  );

REVOKE ALL ON public.board_item_event_links FROM anon;
GRANT SELECT ON public.board_item_event_links TO authenticated;

-- ── Section E: COMMENT ON TABLE for documentation ──────────
COMMENT ON COLUMN public.meeting_action_items.board_item_id IS
  'ADR-0045 (#84 Onda 1): optional FK to board_items — when an action item is converted to a card or links to existing card. NULL when action item is meeting-only (e.g. follow-up email).';
COMMENT ON COLUMN public.meeting_action_items.kind IS
  'ADR-0045 (#84 Onda 1): action vs decision vs followup vs general. Decisions have legal/permanent weight; actions are tasks; followups are reminders; general is catch-all.';
COMMENT ON COLUMN public.event_showcases.board_item_id IS
  'ADR-0045 (#84 Onda 1): optional FK linking the showcase to the specific card/deliverable being presented.';
COMMENT ON TABLE public.tribe_kpi_contributions IS
  'ADR-0045 (#84 Onda 1, GAP 7): maps annual_kpi_targets to initiatives (tribes/workgroups) for "which tribe contributes to which annual goal" queries.';
COMMENT ON TABLE public.board_item_event_links IS
  'ADR-0045 (#84 Onda 1, GAP 4): bidirectional cross-reference between board cards and events. Enables card timeline 360° + meeting impact retrospectives.';

-- ── Cache reload ───────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
