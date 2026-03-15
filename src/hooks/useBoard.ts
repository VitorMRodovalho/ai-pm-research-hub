/**
 * useBoard.ts — Fetch board config + items + realtime subscriptions
 */
import { useState, useEffect, useCallback, useRef } from 'react';
import type { Board, BoardItem, BoardEngineProps } from '../types/board';
import { safeArray, safeChecklist } from '../types/board';

function getSb() {
  return (window as any).navGetSb?.();
}

async function waitForSb(maxRetries = 15): Promise<any> {
  let sb = getSb();
  let retries = 0;
  while (!sb && retries < maxRetries) {
    await new Promise((r) => setTimeout(r, 250));
    sb = getSb();
    retries++;
  }
  return sb;
}

interface UseBoardResult {
  board: Board | null;
  items: BoardItem[];
  loading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useBoard(props: BoardEngineProps): UseBoardResult {
  const [board, setBoard] = useState<Board | null>(null);
  const [items, setItems] = useState<BoardItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    setLoading(true);
    setError(null);

    const sb = await waitForSb();
    if (!sb) {
      setError('Supabase não disponível.');
      setLoading(false);
      return;
    }

    try {
      let result: any;

      if (props.boardId) {
        const { data, error: err } = await sb.rpc('get_board', { p_board_id: props.boardId });
        if (err) throw err;
        result = data;
      } else if (props.domainKey) {
        const { data, error: err } = await sb.rpc('get_board_by_domain', {
          p_domain_key: props.domainKey,
          p_tribe_id: props.tribeId ?? null,
        });
        if (err) throw err;
        result = data;
      } else {
        throw new Error('boardId or domainKey is required');
      }

      if (!result?.board) {
        setError('Board não encontrado.');
        setLoading(false);
        return;
      }

      // Normalize columns: ensure it's always a string[]
      const rawCols = result.board.columns;
      const cols = Array.isArray(rawCols)
        ? rawCols
        : typeof rawCols === 'string'
          ? (() => { try { const p = JSON.parse(rawCols); return Array.isArray(p) ? p : []; } catch { return []; } })()
          : [];
      setBoard({ ...result.board, columns: cols });
      setItems(
        (result.items || []).map((item: any) => ({
          ...item,
          tags: safeArray(item.tags),
          labels: safeArray(item.labels),
          attachments: safeArray(item.attachments),
          checklist: safeChecklist(item.checklist),
          assignments: safeArray(item.assignments),
        }))
      );
    } catch (err: any) {
      setError(err?.message || 'Erro desconhecido');
    } finally {
      setLoading(false);
    }
  }, [props.boardId, props.domainKey, props.tribeId]);

  useEffect(() => {
    fetch();
  }, [fetch]);

  // ── Realtime subscription ──────────────────────────────────────
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!board?.id) return;

    let channel: any = null;

    (async () => {
      const sb = await waitForSb();
      if (!sb) return;

      const debouncedRefetch = () => {
        if (debounceRef.current) clearTimeout(debounceRef.current);
        debounceRef.current = setTimeout(() => fetch(), 500);
      };

      channel = sb
        .channel(`board:${board.id}`)
        .on(
          'postgres_changes',
          { event: '*', schema: 'public', table: 'board_items', filter: `board_id=eq.${board.id}` },
          debouncedRefetch,
        )
        .subscribe();
    })();

    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
      if (channel) {
        const sb = getSb();
        sb?.removeChannel(channel);
      }
    };
  }, [board?.id, fetch]);

  return { board, items, loading, error, refetch: fetch };
}

export { waitForSb, getSb };
