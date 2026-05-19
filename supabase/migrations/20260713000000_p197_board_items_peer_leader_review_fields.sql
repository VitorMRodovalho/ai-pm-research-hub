-- =====================================================================
-- p197 Fase B — Structured peer_review + leader_review fields on board_items
-- =====================================================================
-- Context: Manual de Governança §4.2 defines 7-step content production
-- flow. Steps 5 (Peer Review) and 6 (Leader Review) had FSM states
-- (board_items.curation_status = 'peer_review' / 'leader_review') but
-- NO structured metadata fields. Tribe leaders had no UI to record
-- "who reviewed, when, what was the decision, was it waived for a
-- collaborative article" — so they skipped these states entirely.
--
-- Per §4.2:
--   • Peer Review (etapa 5) is COLEGIADO: "rascunho compartilhado com
--     todos os colaboradores da tribo para feedback construtivo"
--     → no single reviewer_id; summary + waiver only at card level;
--       individual feedbacks via existing card_comments (filtered)
--   • Leader Review (etapa 6) is NOMINAL: "Líder da tribo realiza a
--     revisão final de qualidade, aprovando o artigo para próxima etapa"
--     → leader_reviewer_id + decision (approved/returned/waived) + notes
--
-- Fields added (all nullable; existing 503 draft cards untouched):
--   peer_review_completed_at  : when peer phase concluded (or waived)
--   peer_review_summary       : short text aggregating tribe feedback
--   peer_review_waived        : bool — true if dispensed (collaborative)
--   peer_review_waived_reason : context for waiver (manual §4.2 mentions
--                                "adaptações para webinars/podcasts")
--   leader_review_completed_at: when leader decided
--   leader_review_decision    : approved / returned / waived
--   leader_review_notes       : feedback especializado
--   leader_reviewer_id        : nominal reviewer (manual §4.2)
--
-- Rollback: ALTER TABLE board_items DROP COLUMN ... × 8;
--           DROP CONSTRAINT board_items_leader_review_decision_check;
--           DROP CONSTRAINT board_items_leader_reviewer_id_fkey;
-- =====================================================================

ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS peer_review_completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS peer_review_summary text,
  ADD COLUMN IF NOT EXISTS peer_review_waived boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS peer_review_waived_reason text,
  ADD COLUMN IF NOT EXISTS leader_review_completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS leader_review_decision text,
  ADD COLUMN IF NOT EXISTS leader_review_notes text,
  ADD COLUMN IF NOT EXISTS leader_reviewer_id uuid;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.board_items'::regclass
      AND conname = 'board_items_leader_review_decision_check'
  ) THEN
    ALTER TABLE public.board_items
      ADD CONSTRAINT board_items_leader_review_decision_check
      CHECK (leader_review_decision IS NULL
             OR leader_review_decision IN ('approved', 'returned', 'waived'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.board_items'::regclass
      AND conname = 'board_items_leader_reviewer_id_fkey'
  ) THEN
    ALTER TABLE public.board_items
      ADD CONSTRAINT board_items_leader_reviewer_id_fkey
      FOREIGN KEY (leader_reviewer_id)
      REFERENCES public.members(id)
      ON DELETE SET NULL;
  END IF;
END $$;

COMMENT ON COLUMN public.board_items.peer_review_completed_at IS 'p197: timestamp when peer review phase (manual §4.2 etapa 5 — colegiado) concluded; NULL = not started/completed';
COMMENT ON COLUMN public.board_items.peer_review_summary IS 'p197: short text summarizing peer feedback consensus; individual feedbacks live in card_comments';
COMMENT ON COLUMN public.board_items.peer_review_waived IS 'p197: true when peer review was dispensed (e.g. collaborative article where tribe contributed jointly per manual §4.2 adaptações)';
COMMENT ON COLUMN public.board_items.peer_review_waived_reason IS 'p197: explanation for waiver — audit trail per §5.3';
COMMENT ON COLUMN public.board_items.leader_review_completed_at IS 'p197: timestamp when tribe leader concluded gate review (manual §4.2 etapa 6 — nominal)';
COMMENT ON COLUMN public.board_items.leader_review_decision IS 'p197: leader decision — approved | returned | waived (collaborative)';
COMMENT ON COLUMN public.board_items.leader_review_notes IS 'p197: leader feedback especializado per manual §4.2';
COMMENT ON COLUMN public.board_items.leader_reviewer_id IS 'p197: FK to the tribe leader who reviewed (audit per §5.3 rastreabilidade)';
