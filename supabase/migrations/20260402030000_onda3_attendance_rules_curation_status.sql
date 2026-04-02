-- Sprint 12 — Onda 3: Operational Clarity (CR-032, CR-028, CR-2026-001)
-- Applied live via execute_sql. This migration records the changes for git history.

-- ═══ CR-032: Enrich R3 §5 Presença section with detailed attendance rules ═══
-- Updated inline (attendance types table, dropout alerts, 70% target)

-- ═══ CR-028: Board Members Panel ═══
-- governance_documents.content column added (Onda 2)
-- BoardMembersPanel.tsx created for admin governance page
-- Uses existing RPCs: admin_manage_board_member, get_board_members

-- ═══ CR-2026-001: Curation Digital Pipeline ═══
-- ALREADY FULLY IMPLEMENTED:
-- - CuratorshipBoardIsland.tsx: SLA badge, rubric 5 criteria, overdue counter
-- - submit_curation_review RPC with criteria_scores jsonb
-- - curation_review_log table with full audit trail
-- - 16 curation RPCs operational
-- - CR proposed_changes updated with implementation status

NOTIFY pgrst, 'reload schema';
