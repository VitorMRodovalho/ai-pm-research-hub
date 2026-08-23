import { useState, useEffect, useCallback } from 'react';
import { formatDateOnly, isOverdueDateOnly, daysUntilDateOnly } from '../../lib/date-only';

/**
 * #1942 - as acoes de reuniao atribuidas a mim.
 *
 * Esta e a unica superficie que nao aparecia em lugar nenhum: card ja vem no MyCardsWidget e
 * checklist no MyTasksIsland, mas acao de reuniao que nunca virou card ficava invisivel para quem
 * responde por ela. Medido em 23/08/2026: 138 acoes abertas na plataforma, 45 delas vencidas.
 *
 * Le `get_my_responsibilities()`, que resolve o chamador por auth.uid() e por isso nao pode ser
 * apontada para outra pessoa. Renderiza SO `surfaces.action_items`, para nao duplicar o que os
 * dois vizinhos ja mostram.
 */

interface ActionItem {
  id: string;
  description: string;
  event_id: string | null;
  due_date: string | null;
}

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': {
    title: 'Minhas ações de reunião',
    empty: 'Nenhuma ação de reunião aberta para você.',
    overdue: 'Vencida',
    today: 'Vence hoje',
    tomorrow: 'Vence amanhã',
    inDays: 'Vence em {n} dias',
    noDue: 'Sem prazo',
    viewMeetings: 'Ver reuniões',
  },
  'en-US': {
    title: 'My meeting actions',
    empty: 'No open meeting actions for you.',
    overdue: 'Overdue',
    today: 'Due today',
    tomorrow: 'Due tomorrow',
    inDays: 'Due in {n} days',
    noDue: 'No due date',
    viewMeetings: 'View meetings',
  },
  'es-LATAM': {
    title: 'Mis acciones de reunión',
    empty: 'Ninguna acción de reunión abierta.',
    overdue: 'Vencida',
    today: 'Vence hoy',
    tomorrow: 'Vence mañana',
    inDays: 'Vence en {n} días',
    noDue: 'Sin plazo',
    viewMeetings: 'Ver reuniones',
  },
};

export default function MyActionItemsWidget({ lang = 'pt-BR' }: Props) {
  const t = L[lang] || L['pt-BR'];
  // p123: link interno preserva o idioma do usuario; `/rota` seco derruba o contexto.
  const lp = lang === 'en-US' ? '/en' : lang === 'es-LATAM' ? '/es' : '';
  const [items, setItems] = useState<ActionItem[] | null>(null);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m) { setTimeout(load, 400); return; }
    const { data } = await sb.rpc('get_my_responsibilities');
    const lista = data?.surfaces?.action_items?.items;
    setItems(Array.isArray(lista) ? lista : []);
  }, []);

  useEffect(() => { load(); }, [load]);

  // Mesma convencao do MyCardsWidget: nada de esqueleto e nada de bloco vazio.
  if (items === null) return null;
  if (items.length === 0) return null;

  // #1511 - `due_date` e coluna `date`: o prazo so vence depois do fim do dia LOCAL.
  const prazo = (due: string | null) => {
    if (!due) return { texto: t.noDue, urgente: false, vencida: false };
    if (isOverdueDateOnly(due)) return { texto: `${t.overdue}: ${formatDateOnly(due)}`, urgente: true, vencida: true };
    const d = daysUntilDateOnly(due);
    if (d === 0) return { texto: t.today, urgente: true, vencida: false };
    if (d === 1) return { texto: t.tomorrow, urgente: true, vencida: false };
    return { texto: t.inDays.replace('{n}', String(d)), urgente: d !== null && d <= 3, vencida: false };
  };

  const vencidas = items.filter((i) => isOverdueDateOnly(i.due_date)).length;

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5">
      <h3 className="text-sm font-extrabold text-[var(--text-primary)] mb-3 flex items-center gap-2">
        <span>🗣️</span> {t.title}
        {vencidas > 0 && (
          <span className="text-[9px] font-bold px-2 py-0.5 rounded-full bg-red-100 text-red-700">
            {vencidas} {t.overdue.toLowerCase()}{vencidas > 1 ? 's' : ''}
          </span>
        )}
        <span className="ml-auto text-[10px] font-semibold bg-navy text-white rounded-full px-2 py-0.5">{items.length}</span>
      </h3>
      <div className="space-y-2">
        {items.map((it) => {
          const p = prazo(it.due_date);
          return (
            <div
              key={it.id}
              className="rounded-xl border border-[var(--border-subtle)] p-3"
            >
              <div className="text-[13px] text-[var(--text-primary)] leading-snug">{it.description}</div>
              <div
                className={`text-[10px] mt-1 font-semibold ${
                  p.vencida ? 'text-red-500' : p.urgente ? 'text-amber-600' : 'text-[var(--text-muted)]'
                }`}
              >
                {p.vencida ? '⚠️ ' : ''}{p.texto}
              </div>
            </div>
          );
        })}
      </div>
      <a
        href={`${lp}/meetings`}
        className="mt-3 inline-block text-[11px] font-semibold text-navy hover:underline"
      >
        {t.viewMeetings} →
      </a>
    </div>
  );
}
