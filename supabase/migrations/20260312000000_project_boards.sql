-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 7: Project Boards & Board Items
-- Reusable Kanban-style boards for tribes, subprojects, and workflows.
-- Populated via Trello historical import and manual creation.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Project Boards (one per tribe/subproject/workflow) ───

CREATE TABLE IF NOT EXISTS public.project_boards (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  board_name  TEXT NOT NULL,
  tribe_id    INTEGER REFERENCES public.tribes(id) ON DELETE SET NULL,
  source      TEXT NOT NULL DEFAULT 'manual'
              CHECK (source IN ('manual', 'trello', 'notion', 'miro', 'planner')),
  columns     JSONB NOT NULL DEFAULT '["backlog","todo","in_progress","review","done"]'::JSONB,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_by  UUID REFERENCES public.members(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.project_boards IS
  'Kanban-style project boards. Each tribe can have one or more boards.';

CREATE INDEX idx_project_boards_tribe ON public.project_boards (tribe_id)
  WHERE tribe_id IS NOT NULL;

-- ─── Board Items (cards within a board) ───

CREATE TABLE IF NOT EXISTS public.board_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id        UUID NOT NULL REFERENCES public.project_boards(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  description     TEXT,
  status          TEXT NOT NULL DEFAULT 'backlog'
                  CHECK (status IN ('backlog','todo','in_progress','review','done','archived')),
  assignee_id     UUID REFERENCES public.members(id) ON DELETE SET NULL,
  tags            TEXT[] DEFAULT '{}',
  labels          JSONB DEFAULT '[]'::JSONB,
  due_date        DATE,
  position        INTEGER NOT NULL DEFAULT 0,
  source_card_id  TEXT,
  source_board    TEXT,
  cycle           INTEGER,
  attachments     JSONB DEFAULT '[]'::JSONB,
  checklist       JSONB DEFAULT '[]'::JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.board_items IS
  'Cards/items within a project board. Supports Kanban workflow.';

CREATE INDEX idx_board_items_board_status ON public.board_items (board_id, status);
CREATE INDEX idx_board_items_assignee ON public.board_items (assignee_id)
  WHERE assignee_id IS NOT NULL;

-- ─── Auto-update updated_at ───

CREATE OR REPLACE FUNCTION public.project_boards_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_project_boards_updated
  BEFORE UPDATE ON public.project_boards
  FOR EACH ROW EXECUTE FUNCTION public.project_boards_set_updated_at();

CREATE OR REPLACE FUNCTION public.board_items_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_board_items_updated
  BEFORE UPDATE ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION public.board_items_set_updated_at();

-- ─── RLS ───

ALTER TABLE public.project_boards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "project_boards_read" ON public.project_boards
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY "project_boards_write" ON public.project_boards
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (
          m.is_superadmin = TRUE
          OR m.operational_role IN ('manager','deputy_manager','co_gp')
          OR (m.operational_role = 'tribe_leader' AND m.tribe_id = project_boards.tribe_id)
        )
    )
  );

CREATE POLICY "board_items_read" ON public.board_items
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY "board_items_write" ON public.board_items
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.project_boards pb
      JOIN public.members m ON m.auth_id = auth.uid()
      WHERE pb.id = board_items.board_id
        AND (
          m.is_superadmin = TRUE
          OR m.operational_role IN ('manager','deputy_manager','co_gp')
          OR (m.operational_role = 'tribe_leader' AND m.tribe_id = pb.tribe_id)
        )
    )
  );

-- ─── RPCs ───

CREATE OR REPLACE FUNCTION public.list_board_items(
  p_board_id UUID,
  p_status   TEXT DEFAULT NULL
)
RETURNS SETOF JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      bi.id,
      bi.title,
      bi.description,
      bi.status,
      bi.tags,
      bi.labels,
      bi.due_date,
      bi.position,
      bi.cycle,
      bi.attachments,
      bi.checklist,
      bi.created_at,
      bi.updated_at,
      m.name AS assignee_name,
      m.photo_url AS assignee_photo
    FROM board_items bi
    LEFT JOIN members m ON m.id = bi.assignee_id
    WHERE bi.board_id = p_board_id
      AND (p_status IS NULL OR bi.status = p_status)
    ORDER BY bi.position ASC, bi.created_at DESC
  ) r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_board_items(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.move_board_item(
  p_item_id    UUID,
  p_new_status TEXT,
  p_position   INTEGER DEFAULT 0
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_board_id UUID;
  v_tribe_id INTEGER;
  v_caller   RECORD;
BEGIN
  SELECT bi.board_id, pb.tribe_id
    INTO v_board_id, v_tribe_id
    FROM board_items bi
    JOIN project_boards pb ON pb.id = bi.board_id
    WHERE bi.id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board item not found';
  END IF;

  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();

  IF NOT (
    v_caller.is_superadmin = TRUE
    OR v_caller.operational_role IN ('manager','deputy_manager','co_gp')
    OR (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = v_tribe_id)
  ) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  UPDATE board_items
  SET status = p_new_status, position = p_position, updated_at = now()
  WHERE id = p_item_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.move_board_item(UUID, TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_project_boards(
  p_tribe_id INTEGER DEFAULT NULL
)
RETURNS SETOF JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT row_to_json(r) FROM (
    SELECT
      pb.id,
      pb.board_name,
      pb.tribe_id,
      t.name AS tribe_name,
      pb.source,
      pb.columns,
      pb.is_active,
      pb.created_at,
      (SELECT COUNT(*) FROM board_items bi WHERE bi.board_id = pb.id) AS item_count
    FROM project_boards pb
    LEFT JOIN tribes t ON t.id = pb.tribe_id
    WHERE pb.is_active = TRUE
      AND (p_tribe_id IS NULL OR pb.tribe_id = p_tribe_id)
    ORDER BY pb.created_at DESC
  ) r;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_project_boards(INTEGER) TO authenticated;

-- Extend trello_import_log board_source check to include new board types
ALTER TABLE public.trello_import_log
  DROP CONSTRAINT IF EXISTS trello_import_log_board_source_check;

ALTER TABLE public.trello_import_log
  ADD CONSTRAINT trello_import_log_board_source_check
  CHECK (board_source IN (
    'articles_c1','articles_c2','comms_c3','social_media',
    'tribo3_priorizacao','artigos_pmcom','comunicacao_ciclo3','midias_sociais','controle_artigos',
    'other'
  ));

COMMIT;
