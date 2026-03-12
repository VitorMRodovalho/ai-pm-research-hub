/**
 * useBoardMutations.ts — Create, move, update, delete, duplicate board items
 */
import { useCallback, useRef, useState } from 'react';
import type { BoardItem } from '../types/board';
import { getSb } from './useBoard';

interface Toast { id: number; message: string; type: 'success' | 'error' }

export function useBoardMutations(
  items: BoardItem[],
  setItems: React.Dispatch<React.SetStateAction<BoardItem[]>>,
  refetch: () => Promise<void>
) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  const toast = useCallback((message: string, type: Toast['type'] = 'success') => {
    const id = ++toastId.current;
    setToasts((prev) => [...prev, { id, message, type }]);
    setTimeout(() => setToasts((prev) => prev.filter((t) => t.id !== id)), 3500);
  }, []);

  // ── Move card between columns ──
  const moveItem = useCallback(async (itemId: string, newStatus: string, newPosition = 0, reason?: string) => {
    const item = items.find((i) => i.id === itemId);
    if (!item || item.status === newStatus) return;

    // Optimistic
    setItems((prev) => prev.map((i) => i.id === itemId ? { ...i, status: newStatus, position: newPosition } : i));

    const sb = getSb();
    if (!sb) { toast('Supabase indisponível', 'error'); return; }

    const { error } = await sb.rpc('move_board_item', {
      p_item_id: itemId,
      p_new_status: newStatus,
      p_new_position: newPosition,
      p_reason: reason ?? null,
    });

    if (error) {
      toast(`Erro: ${error.message}`, 'error');
      refetch();
    } else {
      toast(`Movido para ${newStatus}`);
    }
  }, [items, setItems, refetch, toast]);

  // ── Create card ──
  const createItem = useCallback(async (
    boardId: string,
    fields: { title: string; description?: string; assignee_id?: string; tags?: string[]; due_date?: string; status?: string }
  ): Promise<string | null> => {
    const sb = getSb();
    if (!sb) { toast('Supabase indisponível', 'error'); return null; }

    const { data, error } = await sb.rpc('create_board_item', {
      p_board_id: boardId,
      p_title: fields.title,
      p_description: fields.description ?? null,
      p_assignee_id: fields.assignee_id ?? null,
      p_tags: fields.tags ?? [],
      p_due_date: fields.due_date ?? null,
      p_status: fields.status ?? 'backlog',
    });

    if (error) {
      toast(`Erro ao criar: ${error.message}`, 'error');
      return null;
    }

    toast('Card criado');
    await refetch();
    return data;
  }, [refetch, toast]);

  // ── Update card fields ──
  const updateItem = useCallback(async (itemId: string, fields: Record<string, any>) => {
    // Optimistic
    setItems((prev) => prev.map((i) => i.id === itemId ? { ...i, ...fields, updated_at: new Date().toISOString() } : i));

    const sb = getSb();
    if (!sb) { toast('Supabase indisponível', 'error'); return; }

    const { error } = await sb.rpc('update_board_item', {
      p_item_id: itemId,
      p_fields: fields,
    });

    if (error) {
      toast(`Erro: ${error.message}`, 'error');
      refetch();
    } else {
      toast('Atualizado');
    }
  }, [setItems, refetch, toast]);

  // ── Delete (archive) card ──
  const deleteItem = useCallback(async (itemId: string, reason?: string) => {
    setItems((prev) => prev.filter((i) => i.id !== itemId));

    const sb = getSb();
    if (!sb) { toast('Supabase indisponível', 'error'); return; }

    const { error } = await sb.rpc('delete_board_item', {
      p_item_id: itemId,
      p_reason: reason ?? null,
    });

    if (error) {
      toast(`Erro: ${error.message}`, 'error');
      refetch();
    } else {
      toast('Arquivado');
    }
  }, [setItems, refetch, toast]);

  // ── Duplicate card ──
  const duplicateItem = useCallback(async (itemId: string, targetBoardId?: string) => {
    const sb = getSb();
    if (!sb) { toast('Supabase indisponível', 'error'); return; }

    const { data, error } = await sb.rpc('duplicate_board_item', {
      p_item_id: itemId,
      p_target_board_id: targetBoardId ?? null,
    });

    if (error) {
      toast(`Erro: ${error.message}`, 'error');
    } else {
      toast('Duplicado');
      await refetch();
    }
    return data;
  }, [refetch, toast]);

  // ── Move to another board ──
  const moveToBoard = useCallback(async (itemId: string, targetBoardId: string) => {
    setItems((prev) => prev.filter((i) => i.id !== itemId));

    const sb = getSb();
    if (!sb) { toast('Supabase indisponível', 'error'); return; }

    const { error } = await sb.rpc('move_item_to_board', {
      p_item_id: itemId,
      p_target_board_id: targetBoardId,
    });

    if (error) {
      toast(`Erro: ${error.message}`, 'error');
      refetch();
    } else {
      toast('Movido para outro board');
    }
  }, [setItems, refetch, toast]);

  return { moveItem, createItem, updateItem, deleteItem, duplicateItem, moveToBoard, toasts, toast };
}
