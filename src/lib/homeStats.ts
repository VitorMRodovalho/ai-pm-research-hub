import { createClient } from '@supabase/supabase-js';

/**
 * #2553 PR 1: a fonte ÚNICA dos números da home.
 *
 * Medido em 03/10/2026, a home mostrava o mesmo conceito vindo de lugares diferentes:
 *   - capítulos: 5 em "A plataforma em números" e nas Metas (get_chapter_metrics().signed),
 *     15 no hero (texto fixo no i18n) e 15 na seção de capítulos (contagem do chapter_registry);
 *   - pesquisadores: 76 no hero (v_operational_members, ADR-0126) e 97 no mapa (outra população).
 *
 * A página agora busca get_homepage_stats UMA vez por requisição e passa o objeto aos blocos que
 * mostram esses números. Nenhum bloco recalcula um número que outro bloco já mostra.
 *
 * Cada campo é null quando não veio do banco, e o bloco então OMITE o número: um número inventado
 * (fallback literal) é exatamente o defeito que esta fonte existe para eliminar.
 */
export interface HomeStats {
  /** "Pesquisadores ativos": a equipe de pesquisa, v_operational_members (ADR-0126). */
  members: number | null;
  tribes: number | null;
  initiatives: number | null;
  impactHours: number | null;
  /** Capítulos PMI: get_chapter_metrics().engaged, assinados + em negociação (decisão do GP, 03/10/2026). */
  chapters: number | null;
}

function count(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
}

export async function loadHomeStats(): Promise<HomeStats | null> {
  try {
    const sb = createClient(import.meta.env.PUBLIC_SUPABASE_URL, import.meta.env.PUBLIC_SUPABASE_ANON_KEY);
    const { data, error } = await sb.rpc('get_homepage_stats');
    if (error || !data || typeof data !== 'object') return null;
    const s = data as Record<string, unknown>;
    return {
      members: count(s.members),
      tribes: count(s.tribes),
      initiatives: count(s.initiatives),
      impactHours: count(s.impact_hours),
      chapters: count(s.chapters),
    };
  } catch {
    return null;
  }
}
