-- ============================================================================
-- ADR-0015 Phase 2 — Drop dual-write triggers on C3 + tribe_deliverables
--
-- Commit 6 do writer refactor. Remove os 24 triggers de sync tribe_id ↔
-- initiative_id em 12 tabelas agora que writers e frontend fazem dual-write
-- explícito (Commits 1-4) e o contract test anti-regress (Commit 5) impede
-- regressões futuras.
--
-- Tables com triggers removidos (2 cada, trg_a + trg_b = 24 total):
--   1. webinars              7. pilots
--   2. broadcast_log         8. ia_pilots
--   3. meeting_artifacts     9. hub_resources
--   4. publication_submissions   10. announcements
--   5. public_publications   11. project_boards
--   6. events                12. tribe_deliverables
--
-- NOT dropped (by design):
--   - trg_a/b on `members` — Phase 5 (members.tribe_id cutover, pós-CBGPL)
--   - sync_initiative_from_tribe() + sync_tribe_from_initiative() — funções
--     seguem vivas porque ainda são usadas pelos triggers de members
--
-- Pre-drop state (verified live):
--   - Todas as 12 tabelas: 0 rows tribe_only (tribe_id NOT NULL + initiative_id NULL)
--   - trigger job cumprido: dual-write triggers mantiveram sincronia
--   - F_initiative_legacy_tribe_orphan invariant: 0 violations
--   - Writers RPC/frontend: 100% dual-write (Commits 1-4)
--   - Contract test: ADR-0015 anti-regress gate ativo (Commit 5)
--
-- Pós-drop:
--   - Writers escrevem ambas colunas explicitamente; triggers eram no-op
--   - Rows `init_only` existentes (2 em events, 3 em project_boards): ficam
--     como estão. São rows de iniciativas não-tribo (AIPM Ambassadors etc.)
--     cuja tribe_id correta é NULL.
--   - Readers que filtram por tribe_id continuam funcionando enquanto a coluna
--     existir (Phase 3 dropa a coluna por tabela).
--
-- Rollback: reverter esta migration re-cria os triggers (idempotent via
-- CREATE TRIGGER IF NOT EXISTS no arquivo original `20260413230000_v4_phase2_dual_write_triggers.sql`).
--
-- ADR: ADR-0015 Phase 2
-- ============================================================================

BEGIN;

-- webinars
DROP TRIGGER IF EXISTS trg_a_sync_initiative_webinars ON public.webinars;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_webinars ON public.webinars;

-- broadcast_log
DROP TRIGGER IF EXISTS trg_a_sync_initiative_broadcast_log ON public.broadcast_log;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_broadcast_log ON public.broadcast_log;

-- meeting_artifacts
DROP TRIGGER IF EXISTS trg_a_sync_initiative_meeting_artifacts ON public.meeting_artifacts;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_meeting_artifacts ON public.meeting_artifacts;

-- publication_submissions
DROP TRIGGER IF EXISTS trg_a_sync_initiative_publication_submissions ON public.publication_submissions;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_publication_submissions ON public.publication_submissions;

-- public_publications
DROP TRIGGER IF EXISTS trg_a_sync_initiative_public_publications ON public.public_publications;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_public_publications ON public.public_publications;

-- events
DROP TRIGGER IF EXISTS trg_a_sync_initiative_events ON public.events;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_events ON public.events;

-- pilots
DROP TRIGGER IF EXISTS trg_a_sync_initiative_pilots ON public.pilots;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_pilots ON public.pilots;

-- ia_pilots
DROP TRIGGER IF EXISTS trg_a_sync_initiative_ia_pilots ON public.ia_pilots;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_ia_pilots ON public.ia_pilots;

-- hub_resources
DROP TRIGGER IF EXISTS trg_a_sync_initiative_hub_resources ON public.hub_resources;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_hub_resources ON public.hub_resources;

-- announcements
DROP TRIGGER IF EXISTS trg_a_sync_initiative_announcements ON public.announcements;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_announcements ON public.announcements;

-- project_boards
DROP TRIGGER IF EXISTS trg_a_sync_initiative_project_boards ON public.project_boards;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_project_boards ON public.project_boards;

-- tribe_deliverables
DROP TRIGGER IF EXISTS trg_a_sync_initiative_tribe_deliverables ON public.tribe_deliverables;
DROP TRIGGER IF EXISTS trg_b_sync_tribe_tribe_deliverables ON public.tribe_deliverables;

COMMIT;
