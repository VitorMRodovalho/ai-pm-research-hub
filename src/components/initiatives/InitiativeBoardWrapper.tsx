/**
 * InitiativeBoardWrapper — resolves board_id from initiative_id,
 * then renders the full BoardEngine inline.
 */
import { useState, useEffect } from 'react';
import BoardEngine from '../islands/BoardEngine';

function getSb() { return (window as any).navGetSb?.(); }

export default function InitiativeBoardWrapper({ initiativeId }: { initiativeId: string }) {
  const [boardId, setBoardId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function resolve() {
      const sb = getSb();
      if (!sb) {
        setError('Supabase not available');
        setLoading(false);
        return;
      }
      const { data, error: err } = await sb.rpc('get_initiative_detail', { p_initiative_id: initiativeId });
      if (err || !data || data.error) {
        setError('Could not load board');
        setLoading(false);
        return;
      }
      if (data.board_id) {
        setBoardId(data.board_id);
      } else {
        setError('No board linked to this initiative');
      }
      setLoading(false);
    }
    resolve();
  }, [initiativeId]);

  if (loading) return <div className="text-sm text-[var(--text-muted)] py-4">Carregando quadro...</div>;
  if (error) return <div className="text-sm text-[var(--text-muted)] py-4">{error}</div>;
  if (!boardId) return null;

  return <BoardEngine boardId={boardId} />;
}
