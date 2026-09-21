/**
 * InitiativeBoardWrapper — resolves board_id from initiative_id,
 * then renders the full BoardEngine inline.
 */
import { useState, useEffect } from 'react';
import BoardEngine from '../islands/BoardEngine';
import { waitForSb } from '../../hooks/useBoard';

export default function InitiativeBoardWrapper({ initiativeId }: { initiativeId: string }) {
  const [boardId, setBoardId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function resolve() {
      // #2395b: `navGetSb` e definido pela nav (Nav.astro), e as ilhas hidratam por conta
      // propria. Ler uma vez e desistir transforma "ainda nao carregou" em "nao existe", e a
      // aba imprimia `Supabase not available` sobre um board com 14 cards. `waitForSb` e o
      // esperador canonico do projeto (15 tentativas de 250ms) e vive no mesmo hook que o
      // BoardEngine ja usa uma camada abaixo: a espera existia e este componente morria antes
      // de chegar nela.
      const sb = await waitForSb();
      if (!sb) {
        setError('Nao foi possivel conectar apos 15 tentativas. Recarregue a pagina.');
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
