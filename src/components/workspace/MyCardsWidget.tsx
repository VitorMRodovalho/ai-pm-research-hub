import { useState, useEffect, useCallback } from 'react';

interface CardRow {
  id: string;
  title: string;
  status: string;
  due_date: string | null;
  my_role: string;
  board_name: string;
  tribe_name: string | null;
  tribe_id: number | null;
}

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Meus Cards', empty: 'Nenhum card atribuido a voce.', role_author: 'Autor', role_reviewer: 'Revisor', role_contributor: 'Contribuidor', viewBoard: 'Ver Board' },
  'en-US': { title: 'My Cards', empty: 'No cards assigned to you.', role_author: 'Author', role_reviewer: 'Reviewer', role_contributor: 'Contributor', viewBoard: 'View Board' },
  'es-LATAM': { title: 'Mis Cards', empty: 'Ningun card asignado.', role_author: 'Autor', role_reviewer: 'Revisor', role_contributor: 'Contribuidor', viewBoard: 'Ver Board' },
};

const STATUS_STYLE: Record<string, { bg: string; label: string }> = {
  in_progress: { bg: 'bg-blue-100 text-blue-700', label: 'Em andamento' },
  review: { bg: 'bg-purple-100 text-purple-700', label: 'Revisao' },
  backlog: { bg: 'bg-gray-100 text-gray-600', label: 'Backlog' },
  todo: { bg: 'bg-amber-100 text-amber-700', label: 'A fazer' },
  drafting: { bg: 'bg-cyan-100 text-cyan-700', label: 'Rascunho' },
};

export default function MyCardsWidget({ lang = 'pt-BR' }: Props) {
  const t = L[lang] || L['pt-BR'];
  const [cards, setCards] = useState<CardRow[] | null>(null);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m) { setTimeout(load, 400); return; }
    const { data } = await sb.rpc('get_my_cards');
    if (Array.isArray(data)) setCards(data);
    else setCards([]);
  }, []);

  useEffect(() => { load(); }, [load]);

  if (cards === null) return null;
  if (cards.length === 0) return null;

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5">
      <h3 className="text-sm font-extrabold text-[var(--text-primary)] mb-3 flex items-center gap-2">
        <span>📋</span> {t.title}
        <span className="ml-auto text-[10px] font-semibold bg-navy text-white rounded-full px-2 py-0.5">{cards.length}</span>
      </h3>
      <div className="space-y-2">
        {cards.map((c) => {
          const st = STATUS_STYLE[c.status] || { bg: 'bg-gray-100 text-gray-600', label: c.status };
          const isOverdue = c.due_date && new Date(c.due_date) < new Date();
          return (
            <a
              key={`${c.id}-${c.my_role}`}
              href={c.tribe_id ? `/tribe/${c.tribe_id}?tab=board&card=${c.id}` : `/boards?card=${c.id}`}
              className="block rounded-xl border border-[var(--border-subtle)] p-3 hover:bg-[var(--surface-hover)] transition-colors no-underline"
            >
              <div className="flex items-start gap-2">
                <div className="flex-1 min-w-0">
                  <div className="text-[13px] font-semibold text-[var(--text-primary)] truncate">{c.title}</div>
                  <div className="text-[10px] text-[var(--text-muted)] mt-0.5">
                    {c.tribe_name || c.board_name} · {t[`role_${c.my_role}`] || c.my_role}
                  </div>
                </div>
                <span className={`text-[9px] font-bold px-2 py-0.5 rounded-full whitespace-nowrap ${st.bg}`}>
                  {st.label}
                </span>
              </div>
              {isOverdue && c.due_date && (
                <div className="text-[9px] text-red-500 font-semibold mt-1">
                  ⚠️ Vencido: {new Date(c.due_date).toLocaleDateString('pt-BR')}
                </div>
              )}
            </a>
          );
        })}
      </div>
    </div>
  );
}
