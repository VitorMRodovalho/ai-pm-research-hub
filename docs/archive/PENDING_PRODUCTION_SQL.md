# Pending Production SQL

> **Run these in order. Each section is idempotent (safe to re-run).**

This file compiles all SQL from recent migrations that the frontend depends on but may not yet have been applied to the production Supabase instance. Copy each section into the **Supabase SQL Editor** and execute sequentially.

Use the checkboxes to track which sections have been applied.

---

## Frontend RPC Cross-Reference

The following RPCs defined in these migrations are actively called by the frontend:

| RPC | Called From |
|-----|------------|
| `get_board` | `src/hooks/useBoard.ts` |
| `get_board_by_domain` | `src/hooks/useBoard.ts` |
| `get_board_members` | `src/components/board/CardDetail.tsx`, `src/components/board/CardCreate.tsx` |
| `create_board_item` | `src/hooks/useBoardMutations.ts` |
| `move_board_item` | `src/hooks/useBoardMutations.ts`, `src/components/boards/PublicationsBoardIsland.tsx`, `src/components/boards/TribeKanbanIsland.tsx` |
| `update_board_item` | `src/hooks/useBoardMutations.ts` |
| `delete_board_item` | `src/hooks/useBoardMutations.ts` |
| `duplicate_board_item` | `src/hooks/useBoardMutations.ts` |
| `move_item_to_board` | `src/hooks/useBoardMutations.ts` |
| `get_card_timeline` | `src/components/board/CardDetail.tsx` |
| `get_curation_cross_board` | Board engine internals |
| `list_active_boards` | `src/components/board/CardDetail.tsx`, `src/pages/workspace.astro` |

---

## 1. Board Engine RPCs (Core)

- [x] **Applied to production** (2026-03-12 via `supabase db push`)

Source: `supabase/migrations/20260317100000_board_engine_rpcs.sql`

Defines 12 RPCs for the generic board engine: `get_board`, `get_board_by_domain`, `get_board_members`, `create_board_item`, `move_board_item`, `update_board_item`, `delete_board_item`, `duplicate_board_item`, `move_item_to_board`, `get_card_timeline`, `get_curation_cross_board`, `list_active_boards`.

```sql
-- ============================================================================
-- BoardEngine RPCs — Sprint 1 Foundation
-- 12 RPCs for the generic board engine component.
-- Uses CREATE OR REPLACE; safe to re-run.
-- Depends on: project_boards, board_items, board_lifecycle_events, members
-- ============================================================================

-- ─── 1. get_board: Fetch board config + all items in one call ───────────────

CREATE OR REPLACE FUNCTION public.get_board(p_board_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'board', (
      SELECT jsonb_build_object(
        'id', b.id,
        'board_name', b.board_name,
        'tribe_id', b.tribe_id,
        'source', b.source,
        'columns', b.columns,
        'is_active', b.is_active,
        'domain_key', b.domain_key,
        'board_scope', b.board_scope,
        'cycle_scope', b.cycle_scope
      )
      FROM project_boards b WHERE b.id = p_board_id
    ),
    'items', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'title', i.title,
          'description', i.description,
          'status', i.status,
          'assignee_id', i.assignee_id,
          'assignee_name', am.name,
          'reviewer_id', i.reviewer_id,
          'reviewer_name', rm.name,
          'tags', i.tags,
          'labels', i.labels,
          'due_date', i.due_date,
          'position', i.position,
          'attachments', i.attachments,
          'checklist', i.checklist,
          'curation_status', i.curation_status,
          'curation_due_at', i.curation_due_at,
          'cycle', i.cycle,
          'source_card_id', i.source_card_id,
          'source_board', i.source_board,
          'created_at', i.created_at,
          'updated_at', i.updated_at
        ) ORDER BY i.position
      ), '[]'::jsonb)
      FROM board_items i
      LEFT JOIN members am ON am.id = i.assignee_id
      LEFT JOIN members rm ON rm.id = i.reviewer_id
      WHERE i.board_id = p_board_id
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- ─── 2. get_board_by_domain: Resolve board by domain_key + optional tribe ───

CREATE OR REPLACE FUNCTION public.get_board_by_domain(
  p_domain_key text,
  p_tribe_id int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
BEGIN
  SELECT id INTO v_board_id
  FROM project_boards
  WHERE domain_key = p_domain_key
    AND is_active = true
    AND (p_tribe_id IS NULL OR tribe_id = p_tribe_id)
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('board', null, 'items', '[]'::jsonb);
  END IF;

  RETURN public.get_board(v_board_id);
END;
$$;

-- ─── 3. get_board_members: Members for MemberPicker ─────────────────────────

CREATE OR REPLACE FUNCTION public.get_board_members(p_board_id uuid)
RETURNS TABLE(id uuid, name text, avatar_url text, operational_role text)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_scope text;
  v_tribe_id int;
BEGIN
  SELECT board_scope, pb.tribe_id INTO v_scope, v_tribe_id
  FROM project_boards pb WHERE pb.id = p_board_id;

  RETURN QUERY
  SELECT m.id, m.name, m.photo_url AS avatar_url, m.operational_role
  FROM members m
  WHERE m.is_active = true
    AND (
      v_scope = 'global'
      OR (v_scope = 'tribe' AND m.tribe_id = v_tribe_id)
    )
  ORDER BY m.name;
END;
$$;

-- ─── 4. create_board_item: Create a new card ────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_board_item(
  p_board_id uuid,
  p_title text,
  p_description text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_tags text[] DEFAULT '{}',
  p_due_date date DEFAULT NULL,
  p_status text DEFAULT 'backlog'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
  v_max_pos int;
  v_actor uuid;
BEGIN
  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = p_board_id AND status = p_status;

  INSERT INTO board_items (
    board_id, title, description, assignee_id, tags, due_date, position, status, cycle
  ) VALUES (
    p_board_id, p_title, p_description, p_assignee_id, p_tags, p_due_date, v_max_pos, p_status, 3
  ) RETURNING id INTO v_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, new_status, actor_member_id)
  VALUES (p_board_id, v_id, 'created', p_status, v_actor);

  RETURN v_id;
END;
$$;

-- ─── 5. Evolve move_board_item: add p_reason param ──────────────────────────
-- The existing function has signature (uuid, text, integer).
-- We drop and recreate with (uuid, text, integer, text) to add audit reason.

DROP FUNCTION IF EXISTS public.move_board_item(uuid, text, integer);

CREATE OR REPLACE FUNCTION public.move_board_item(
  p_item_id uuid,
  p_new_status text,
  p_new_position int DEFAULT 0,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_old_status text;
  v_board_id uuid;
  v_actor uuid;
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id
  FROM board_items WHERE id = p_item_id;

  IF v_old_status IS NULL THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  UPDATE board_items
  SET position = position + 1
  WHERE board_id = v_board_id AND status = p_new_status
    AND position >= p_new_position AND id != p_item_id;

  UPDATE board_items
  SET status = p_new_status, position = p_new_position, updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_old_status != p_new_status THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
    VALUES
      (v_board_id, p_item_id, 'status_change', v_old_status, p_new_status, p_reason, v_actor);
  END IF;
END;
$$;

-- ─── 6. update_board_item: Generic field updater ────────────────────────────

CREATE OR REPLACE FUNCTION public.update_board_item(
  p_item_id uuid,
  p_fields jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
  v_old_assignee uuid;
  v_new_assignee uuid;
  v_actor uuid;
BEGIN
  SELECT board_id, assignee_id INTO v_board_id, v_old_assignee
  FROM board_items WHERE id = p_item_id;

  IF v_board_id IS NULL THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  UPDATE board_items SET
    title = coalesce(p_fields->>'title', title),
    description = CASE WHEN p_fields ? 'description' THEN p_fields->>'description' ELSE description END,
    assignee_id = CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                       THEN (p_fields->>'assignee_id')::uuid
                       WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NULL
                       THEN NULL
                       ELSE assignee_id END,
    reviewer_id = CASE WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NOT NULL
                       THEN (p_fields->>'reviewer_id')::uuid
                       WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NULL
                       THEN NULL
                       ELSE reviewer_id END,
    tags = CASE WHEN p_fields ? 'tags'
                THEN ARRAY(SELECT jsonb_array_elements_text(p_fields->'tags'))
                ELSE tags END,
    labels = CASE WHEN p_fields ? 'labels' THEN p_fields->'labels' ELSE labels END,
    due_date = CASE WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NOT NULL
                    THEN (p_fields->>'due_date')::date
                    WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NULL
                    THEN NULL
                    ELSE due_date END,
    checklist = CASE WHEN p_fields ? 'checklist' THEN p_fields->'checklist' ELSE checklist END,
    attachments = CASE WHEN p_fields ? 'attachments' THEN p_fields->'attachments' ELSE attachments END,
    curation_status = coalesce(p_fields->>'curation_status', curation_status),
    curation_due_at = CASE WHEN p_fields ? 'curation_due_at' AND p_fields->>'curation_due_at' IS NOT NULL
                           THEN (p_fields->>'curation_due_at')::timestamptz
                           ELSE curation_due_at END,
    updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  v_new_assignee := CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                         THEN (p_fields->>'assignee_id')::uuid
                         ELSE v_old_assignee END;

  IF v_new_assignee IS DISTINCT FROM v_old_assignee THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES
      (v_board_id, p_item_id, 'assigned',
       'Atribuído a ' || coalesce((SELECT name FROM members WHERE id = v_new_assignee), 'ninguém'),
       v_actor);
  END IF;
END;
$$;

-- ─── 7. delete_board_item: Soft delete (archive) ───────────────────────────

CREATE OR REPLACE FUNCTION public.delete_board_item(
  p_item_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
  v_old_status text;
  v_actor uuid;
BEGIN
  SELECT board_id, status INTO v_board_id, v_old_status
  FROM board_items WHERE id = p_item_id;

  UPDATE board_items
  SET status = 'archived', updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events
    (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
  VALUES
    (v_board_id, p_item_id, 'archived', v_old_status, 'archived', p_reason, v_actor);
END;
$$;

-- ─── 8. duplicate_board_item: Clone card ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.duplicate_board_item(
  p_item_id uuid,
  p_target_board_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_new_id uuid;
  v_board_id uuid;
  v_max_pos int;
  v_actor uuid;
BEGIN
  SELECT coalesce(p_target_board_id, board_id) INTO v_board_id
  FROM board_items WHERE id = p_item_id;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = v_board_id AND status = 'backlog';

  INSERT INTO board_items (
    board_id, title, description, tags, labels, checklist, attachments, cycle, position, status
  )
  SELECT v_board_id, title || ' (cópia)', description, tags, labels, checklist, attachments, cycle, v_max_pos, 'backlog'
  FROM board_items WHERE id = p_item_id
  RETURNING id INTO v_new_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_board_id, v_new_id, 'created', 'Duplicado de ' || p_item_id::text, v_actor);

  RETURN v_new_id;
END;
$$;

-- ─── 9. move_item_to_board: Transfer card between boards ────────────────────

CREATE OR REPLACE FUNCTION public.move_item_to_board(
  p_item_id uuid,
  p_target_board_id uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_old_board_id uuid;
  v_max_pos int;
  v_actor uuid;
BEGIN
  SELECT board_id INTO v_old_board_id FROM board_items WHERE id = p_item_id;

  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = p_target_board_id AND status = 'backlog';

  UPDATE board_items
  SET board_id = p_target_board_id, status = 'backlog', position = v_max_pos, updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES
    (v_old_board_id, p_item_id, 'moved_out', 'Movido para outro board', v_actor),
    (p_target_board_id, p_item_id, 'moved_in', 'Recebido de outro board', v_actor);
END;
$$;

-- ─── 10. get_card_timeline: Audit trail for a card ──────────────────────────

CREATE OR REPLACE FUNCTION public.get_card_timeline(p_item_id uuid)
RETURNS TABLE(
  id bigint,
  action text,
  previous_status text,
  new_status text,
  reason text,
  actor_name text,
  created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.action,
    e.previous_status,
    e.new_status,
    e.reason,
    m.name AS actor_name,
    e.created_at
  FROM board_lifecycle_events e
  LEFT JOIN members m ON m.id = e.actor_member_id
  WHERE e.item_id = p_item_id
  ORDER BY e.created_at DESC;
END;
$$;

-- ─── 11. get_curation_cross_board: Items across ALL boards ──────────────────

CREATE OR REPLACE FUNCTION public.get_curation_cross_board()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN coalesce((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'board_id', i.board_id,
        'board_name', b.board_name,
        'tribe_id', b.tribe_id,
        'domain_key', b.domain_key,
        'title', i.title,
        'description', i.description,
        'status', i.status,
        'assignee_id', i.assignee_id,
        'assignee_name', am.name,
        'reviewer_id', i.reviewer_id,
        'reviewer_name', rm.name,
        'tags', i.tags,
        'labels', i.labels,
        'due_date', i.due_date,
        'attachments', i.attachments,
        'checklist', i.checklist,
        'curation_status', i.curation_status,
        'curation_due_at', i.curation_due_at,
        'cycle', i.cycle,
        'created_at', i.created_at,
        'updated_at', i.updated_at
      ) ORDER BY
        CASE i.curation_status
          WHEN 'draft' THEN 0
          WHEN 'review' THEN 1
          WHEN 'approved' THEN 2
          WHEN 'rejected' THEN 3
        END,
        i.updated_at DESC
    )
    FROM board_items i
    JOIN project_boards b ON b.id = i.board_id
    LEFT JOIN members am ON am.id = i.assignee_id
    LEFT JOIN members rm ON rm.id = i.reviewer_id
    WHERE b.is_active = true
  ), '[]'::jsonb);
END;
$$;

-- ─── 12. list_active_boards: For board selector / navigation ────────────────

CREATE OR REPLACE FUNCTION public.list_active_boards()
RETURNS TABLE(
  id uuid,
  board_name text,
  tribe_id int,
  domain_key text,
  board_scope text,
  source text,
  item_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.id,
    b.board_name,
    b.tribe_id,
    b.domain_key,
    b.board_scope,
    b.source,
    (SELECT count(*) FROM board_items bi WHERE bi.board_id = b.id) AS item_count
  FROM project_boards b
  WHERE b.is_active = true
  ORDER BY b.board_scope, b.tribe_id NULLS FIRST, b.board_name;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANT EXECUTE to authenticated users
-- ═══════════════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.get_board(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_board_by_domain(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_board_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_board_item(uuid, text, text, uuid, text[], date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_board_item(uuid, text, int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_board_item(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_board_item(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.duplicate_board_item(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_item_to_board(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_card_timeline(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_curation_cross_board() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_active_boards() TO authenticated;
```

---

## 2. Fix full_name to name References

- [x] **Applied to production** (2026-03-12 via `supabase db push` + hotfix for `avatar_url` → `photo_url`)

Source: `supabase/migrations/20260318100000_fix_full_name_to_name.sql`

Hotfix: re-creates RPCs that referenced `members.full_name` (which does not exist) to use `members.name` instead. Affects: `get_board`, `get_board_by_domain`, `get_board_members`, `update_board_item`, `get_card_timeline`, `get_curation_cross_board`.

> **Note:** This migration supersedes the corresponding functions from Section 1. If running both in order, Section 1 creates the functions and Section 2 immediately patches them. Safe to run both.

```sql
-- ============================================================================
-- HOTFIX: Fix "column am.full_name does not exist" in BoardEngine RPCs
-- The members table uses column "name", not "full_name".
-- This migration re-creates all affected RPCs with the correct column name.
-- Safe to re-run (CREATE OR REPLACE).
-- ============================================================================

-- ─── 1. get_board ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_board(p_board_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'board', (
      SELECT jsonb_build_object(
        'id', b.id,
        'board_name', b.board_name,
        'tribe_id', b.tribe_id,
        'source', b.source,
        'columns', b.columns,
        'is_active', b.is_active,
        'domain_key', b.domain_key,
        'board_scope', b.board_scope,
        'cycle_scope', b.cycle_scope
      )
      FROM project_boards b WHERE b.id = p_board_id
    ),
    'items', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'title', i.title,
          'description', i.description,
          'status', i.status,
          'assignee_id', i.assignee_id,
          'assignee_name', am.name,
          'reviewer_id', i.reviewer_id,
          'reviewer_name', rm.name,
          'tags', i.tags,
          'labels', i.labels,
          'due_date', i.due_date,
          'position', i.position,
          'attachments', i.attachments,
          'checklist', i.checklist,
          'curation_status', i.curation_status,
          'curation_due_at', i.curation_due_at,
          'cycle', i.cycle,
          'source_card_id', i.source_card_id,
          'source_board', i.source_board,
          'created_at', i.created_at,
          'updated_at', i.updated_at
        ) ORDER BY i.position
      ), '[]'::jsonb)
      FROM board_items i
      LEFT JOIN members am ON am.id = i.assignee_id
      LEFT JOIN members rm ON rm.id = i.reviewer_id
      WHERE i.board_id = p_board_id
    )
  ) INTO v_result;
  RETURN v_result;
END;
$$;

-- ─── 2. get_board_by_domain (calls get_board internally, no direct fix needed)
-- Included for completeness — no changes to SQL, just re-create to ensure consistency.

CREATE OR REPLACE FUNCTION public.get_board_by_domain(
  p_domain_key text,
  p_tribe_id int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
BEGIN
  SELECT id INTO v_board_id
  FROM project_boards
  WHERE domain_key = p_domain_key
    AND is_active = true
    AND (p_tribe_id IS NULL OR tribe_id = p_tribe_id)
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_board_id IS NULL THEN
    RETURN jsonb_build_object('board', null, 'items', '[]'::jsonb);
  END IF;

  RETURN public.get_board(v_board_id);
END;
$$;

-- ─── 3. get_board_members ────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_board_members(uuid);

CREATE OR REPLACE FUNCTION public.get_board_members(p_board_id uuid)
RETURNS TABLE(id uuid, name text, avatar_url text, operational_role text)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_scope text;
  v_tribe_id int;
BEGIN
  SELECT board_scope, pb.tribe_id INTO v_scope, v_tribe_id
  FROM project_boards pb WHERE pb.id = p_board_id;

  RETURN QUERY
  SELECT m.id, m.name, m.photo_url AS avatar_url, m.operational_role
  FROM members m
  WHERE m.is_active = true
    AND (
      v_scope = 'global'
      OR (v_scope = 'tribe' AND m.tribe_id = v_tribe_id)
    )
  ORDER BY m.name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_board_members(uuid) TO authenticated;

-- ─── 4. update_board_item (assignment log references members.name) ───────────

CREATE OR REPLACE FUNCTION public.update_board_item(
  p_item_id uuid,
  p_fields jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_board_id uuid;
  v_old_assignee uuid;
  v_new_assignee uuid;
  v_actor uuid;
BEGIN
  SELECT board_id, assignee_id INTO v_board_id, v_old_assignee
  FROM board_items WHERE id = p_item_id;

  IF v_board_id IS NULL THEN
    RAISE EXCEPTION 'Item not found: %', p_item_id;
  END IF;

  UPDATE board_items SET
    title = coalesce(p_fields->>'title', title),
    description = CASE WHEN p_fields ? 'description' THEN p_fields->>'description' ELSE description END,
    assignee_id = CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                       THEN (p_fields->>'assignee_id')::uuid
                       WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NULL
                       THEN NULL
                       ELSE assignee_id END,
    reviewer_id = CASE WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NOT NULL
                       THEN (p_fields->>'reviewer_id')::uuid
                       WHEN p_fields ? 'reviewer_id' AND p_fields->>'reviewer_id' IS NULL
                       THEN NULL
                       ELSE reviewer_id END,
    tags = CASE WHEN p_fields ? 'tags'
                THEN ARRAY(SELECT jsonb_array_elements_text(p_fields->'tags'))
                ELSE tags END,
    labels = CASE WHEN p_fields ? 'labels' THEN p_fields->'labels' ELSE labels END,
    due_date = CASE WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NOT NULL
                    THEN (p_fields->>'due_date')::date
                    WHEN p_fields ? 'due_date' AND p_fields->>'due_date' IS NULL
                    THEN NULL
                    ELSE due_date END,
    checklist = CASE WHEN p_fields ? 'checklist' THEN p_fields->'checklist' ELSE checklist END,
    attachments = CASE WHEN p_fields ? 'attachments' THEN p_fields->'attachments' ELSE attachments END,
    curation_status = coalesce(p_fields->>'curation_status', curation_status),
    curation_due_at = CASE WHEN p_fields ? 'curation_due_at' AND p_fields->>'curation_due_at' IS NOT NULL
                           THEN (p_fields->>'curation_due_at')::timestamptz
                           ELSE curation_due_at END,
    updated_at = now()
  WHERE id = p_item_id;

  SELECT m.id INTO v_actor FROM members m WHERE m.auth_id = auth.uid() LIMIT 1;

  v_new_assignee := CASE WHEN p_fields ? 'assignee_id' AND p_fields->>'assignee_id' IS NOT NULL
                         THEN (p_fields->>'assignee_id')::uuid
                         ELSE v_old_assignee END;

  IF v_new_assignee IS DISTINCT FROM v_old_assignee THEN
    INSERT INTO board_lifecycle_events
      (board_id, item_id, action, reason, actor_member_id)
    VALUES
      (v_board_id, p_item_id, 'assigned',
       'Atribuído a ' || coalesce((SELECT name FROM members WHERE id = v_new_assignee), 'ninguém'),
       v_actor);
  END IF;
END;
$$;

-- ─── 5. get_card_timeline ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_card_timeline(p_item_id uuid)
RETURNS TABLE(
  id bigint,
  action text,
  previous_status text,
  new_status text,
  reason text,
  actor_name text,
  created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.action,
    e.previous_status,
    e.new_status,
    e.reason,
    m.name AS actor_name,
    e.created_at
  FROM board_lifecycle_events e
  LEFT JOIN members m ON m.id = e.actor_member_id
  WHERE e.item_id = p_item_id
  ORDER BY e.created_at DESC;
END;
$$;

-- ─── 6. get_curation_cross_board ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_curation_cross_board()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN coalesce((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'board_id', i.board_id,
        'board_name', b.board_name,
        'tribe_id', b.tribe_id,
        'domain_key', b.domain_key,
        'title', i.title,
        'description', i.description,
        'status', i.status,
        'assignee_id', i.assignee_id,
        'assignee_name', am.name,
        'reviewer_id', i.reviewer_id,
        'reviewer_name', rm.name,
        'tags', i.tags,
        'labels', i.labels,
        'due_date', i.due_date,
        'attachments', i.attachments,
        'checklist', i.checklist,
        'curation_status', i.curation_status,
        'curation_due_at', i.curation_due_at,
        'cycle', i.cycle,
        'created_at', i.created_at,
        'updated_at', i.updated_at
      ) ORDER BY
        CASE i.curation_status
          WHEN 'draft' THEN 0
          WHEN 'review' THEN 1
          WHEN 'approved' THEN 2
          WHEN 'rejected' THEN 3
        END,
        i.updated_at DESC
    )
    FROM board_items i
    JOIN project_boards b ON b.id = i.board_id
    LEFT JOIN members am ON am.id = i.assignee_id
    LEFT JOIN members rm ON rm.id = i.reviewer_id
    WHERE b.is_active = true
  ), '[]'::jsonb);
END;
$$;
```

---

## 3. Ensure Tribe Board Domain Keys

- [x] **Applied to production** (2026-03-12 via `supabase db push`)

Source: `supabase/migrations/20260318000001_ensure_tribe_board_domain_keys.sql`

Data fix: ensures all tribe boards have `domain_key = 'research_delivery'` and creates missing boards for tribes 1-8. Required for `get_board_by_domain` to resolve tribe boards correctly.

```sql
-- ============================================================================
-- Ensure all tribe boards have domain_key = 'research_delivery'
-- Safety net for BoardEngine integration (Sprint 6)
-- ============================================================================

UPDATE public.project_boards
SET domain_key = 'research_delivery',
    updated_at = now()
WHERE tribe_id IS NOT NULL
  AND board_scope = 'tribe'
  AND is_active = true
  AND (domain_key IS NULL OR domain_key = '');

-- Ensure tribes 1-8 all have at least one active board
DO $$
DECLARE
  v_tribe RECORD;
BEGIN
  FOR v_tribe IN
    SELECT t.id, t.name
    FROM public.tribes t
    WHERE t.is_active IS TRUE
      AND COALESCE(t.workstream_type, 'research') = 'research'
    ORDER BY t.id
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.project_boards
      WHERE tribe_id = v_tribe.id
        AND is_active = true
        AND domain_key = 'research_delivery'
    ) THEN
      INSERT INTO public.project_boards (
        board_name, tribe_id, source, board_scope, domain_key, columns, is_active
      ) VALUES (
        format('T%s: %s - Quadro Geral', v_tribe.id, v_tribe.name),
        v_tribe.id,
        'manual',
        'tribe',
        'research_delivery',
        '["backlog","todo","in_progress","review","done"]'::jsonb,
        true
      );
    END IF;
  END LOOP;
END;
$$;
```

---

## 4. Tribes Video Columns

- [x] **Applied to production** (2026-03-12 via `supabase db push`)

Source: `supabase/migrations/20260318110000_tribes_video_columns.sql`

Schema change: adds `video_url` and `video_duration` columns to the `tribes` table, then backfills video data for tribes 1-8. The frontend reads these columns from the tribes table.

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P3 Fix: Add video_url and video_duration columns to tribes table
-- Backfill from hardcoded src/data/tribes.ts
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Add columns (idempotent)
ALTER TABLE public.tribes ADD COLUMN IF NOT EXISTS video_url TEXT;
ALTER TABLE public.tribes ADD COLUMN IF NOT EXISTS video_duration TEXT;

-- Backfill video data per tribe
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=XJLAvcHFKT8', video_duration = '7min'  WHERE id = 1;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=HwgjMalJXQE', video_duration = '8min'  WHERE id = 2;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=vxQ4WLTyKpY', video_duration = '4min'  WHERE id = 3;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=LZSk96EsepA', video_duration = '3min'  WHERE id = 4;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=KbhnAJdSeDw', video_duration = '5min'  WHERE id = 5;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=R2fA7hVE1dc', video_duration = '11min' WHERE id = 6;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=3su8GgtFzVY', video_duration = '3min'  WHERE id = 7;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=ghrgJ3_nk4k', video_duration = '14min' WHERE id = 8;

COMMIT;
```

---

## 5. KPI Targets Config

- [x] **Applied to production** (2026-03-12 via `supabase db push`)

Source: `supabase/migrations/20260318110001_kpi_targets_config.sql`

Data: inserts `kpi_targets_cycle_3` into `site_config`. The frontend reads this via `get_site_config` / `get_executive_kpis` RPCs.

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P3 Fix: Store KPI targets in site_config as kpi_targets_cycle_3
-- Sourced from hardcoded src/data/kpis.ts
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO public.site_config (key, value, updated_at)
VALUES (
  'kpi_targets_cycle_3',
  '{"chapters": "8", "articles": "+10", "webinars": "+6", "pilots": "3", "impact": "1.800h", "cert": "70%"}'::JSONB,
  now()
)
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  updated_at = now();

COMMIT;
```

---

## Verification

After applying all sections, verify by running:

```sql
-- Check all board engine RPCs exist
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'get_board', 'get_board_by_domain', 'get_board_members',
    'create_board_item', 'move_board_item', 'update_board_item',
    'delete_board_item', 'duplicate_board_item', 'move_item_to_board',
    'get_card_timeline', 'get_curation_cross_board', 'list_active_boards'
  )
ORDER BY routine_name;
-- Expected: 12 rows

-- Check tribes video columns
SELECT column_name FROM information_schema.columns
WHERE table_name = 'tribes' AND column_name IN ('video_url', 'video_duration');
-- Expected: 2 rows

-- Check KPI config
SELECT key FROM public.site_config WHERE key = 'kpi_targets_cycle_3';
-- Expected: 1 row

-- Check tribe boards have domain keys
SELECT id, board_name, tribe_id, domain_key FROM public.project_boards
WHERE tribe_id IS NOT NULL AND is_active = true
ORDER BY tribe_id;
-- Expected: all rows have domain_key = 'research_delivery'
```
