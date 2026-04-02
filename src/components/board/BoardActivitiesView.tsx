import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { getSb } from '../../hooks/useBoard';
import type { BoardMember } from '../../types/board';

interface Activity {
  id: string;
  card_id: string;
  card_title: string;
  card_status: string;
  card_baseline: string | null;
  card_forecast: string | null;
  is_portfolio_item: boolean;
  text: string;
  done: boolean;
  assignee_id: string | null;
  assignee_name: string | null;
  target_date: string | null;
  completed_at: string | null;
  completed_by_name: string | null;
  position: number;
}

interface Props {
  boardId: string;
  members: BoardMember[];
  onOpenCard: (cardId: string) => void;
}

export default function BoardActivitiesView({ boardId, members, onOpenCard }: Props) {
  const t = usePageI18n();
  const i18n = {
    pendingFilter: t('comp.board.pendingFilter'),
    loadingActivities: t('comp.board.loadingActivities'),
    noActivities: t('comp.board.noActivities'),
  };
  const [activities, setActivities] = useState<Activity[]>([]);
  const [total, setTotal] = useState(0);
  const [completed, setCompleted] = useState(0);
  const [pending, setPending] = useState(0);
  const [assigneeFilter, setAssigneeFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [periodFilter, setPeriodFilter] = useState('all');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const { data, error } = await sb.rpc('get_board_activities', {
      p_board_id: boardId,
      p_assignee_filter: assigneeFilter || null,
      p_status_filter: statusFilter,
      p_period_filter: periodFilter,
    });
    if (!error && data) {
      setActivities(data.activities || []);
      setTotal(data.total || 0);
      setCompleted(data.completed || 0);
      setPending(data.pending || 0);
    }
    setLoading(false);
  }, [boardId, assigneeFilter, statusFilter, periodFilter]);

  useEffect(() => { load(); }, [load]);

  const toggleActivity = useCallback(async (activityId: string, currentDone: boolean) => {
    const sb = getSb();
    if (!sb) return;
    const { error } = await sb.rpc('complete_checklist_item', {
      p_checklist_item_id: activityId,
      p_completed: !currentDone,
    });
    if (error) {
      (window as any).toast?.(error.message || 'Erro ao atualizar', 'error');
      return;
    }
    load();
  }, [load]);

  // Group activities by card
  const grouped = activities.reduce<Record<string, { card_title: string; card_status: string; card_id: string; is_portfolio: boolean; items: Activity[] }>>((acc, a) => {
    if (!acc[a.card_id]) {
      acc[a.card_id] = { card_title: a.card_title, card_status: a.card_status, card_id: a.card_id, is_portfolio: a.is_portfolio_item, items: [] };
    }
    acc[a.card_id].items.push(a);
    return acc;
  }, {});

  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;

  return (
    <div className="space-y-4">
      {/* Summary */}
      <div className="flex items-center gap-4 text-[12px]">
        <span className="font-bold text-[var(--text-primary)]">{total} atividades</span>
        <span className="text-emerald-600 font-semibold">{completed} concluídas</span>
        <span className="text-amber-600 font-semibold">{pending} pendentes</span>
        {total > 0 && (
          <div className="flex items-center gap-2 flex-1">
            <div className="flex-1 bg-[var(--surface-section-cool)] rounded-full h-1.5 max-w-[200px]">
              <div className="bg-emerald-500 h-1.5 rounded-full transition-all" style={{ width: `${pct}%` }} />
            </div>
            <span className="text-[10px] text-[var(--text-muted)]">{pct}%</span>
          </div>
        )}
      </div>

      {/* Filters */}
      <div className="flex gap-2 flex-wrap">
        <select value={assigneeFilter} onChange={(e) => setAssigneeFilter(e.target.value)}
          className="text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5 outline-none">
          <option value="">Todos</option>
          {members.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
        </select>
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}
          className="text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5 outline-none">
          <option value="all">Todas</option>
          <option value="pending">{i18n.pendingFilter || 'Pending'}</option>
          <option value="completed">Concluídas</option>
        </select>
        <select value={periodFilter} onChange={(e) => setPeriodFilter(e.target.value)}
          className="text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5 outline-none">
          <option value="all">Todas as datas</option>
          <option value="week">Próximos 7 dias</option>
          <option value="month">Próximos 30 dias</option>
          <option value="overdue">Atrasadas</option>
        </select>
      </div>

      {/* Activities grouped by card */}
      {loading ? (
        <p className="text-[12px] text-[var(--text-muted)]">{i18n.loadingActivities || 'Loading activities...'}</p>
      ) : Object.keys(grouped).length === 0 ? (
        <p className="text-[12px] text-[var(--text-muted)]">{i18n.noActivities || 'No activities found.'}</p>
      ) : (
        <div className="space-y-3">
          {Object.values(grouped).map((group) => (
            <div key={group.card_id} className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden">
              {/* Card header */}
              <div className="flex items-center gap-2 px-3 py-2 bg-[var(--surface-section-cool)] border-b border-[var(--border-subtle)] cursor-pointer hover:bg-[var(--surface-hover)]"
                onClick={() => onOpenCard(group.card_id)}>
                <span className="text-[12px] font-bold text-[var(--text-primary)] flex-1">{group.card_title}</span>
                {group.is_portfolio && (
                  <span className="text-[9px] px-1.5 py-0.5 rounded bg-amber-50 text-amber-700 font-semibold">📊</span>
                )}
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-blue-50 text-blue-600 font-semibold">{group.card_status}</span>
                <span className="text-[10px] text-[var(--text-muted)]">
                  {group.items.filter(i => i.done).length}/{group.items.length}
                </span>
              </div>
              {/* Activities */}
              <div className="divide-y divide-[var(--border-subtle)]">
                {group.items.map((a) => {
                  const isOverdue = a.target_date && !a.done && new Date(a.target_date) < new Date();
                  return (
                    <div key={a.id} className="flex items-center gap-2 px-3 py-1.5">
                      <input type="checkbox" checked={a.done}
                        onChange={() => toggleActivity(a.id, a.done)}
                        className="w-3.5 h-3.5 rounded accent-emerald-500 cursor-pointer" />
                      <span className={`flex-1 text-[11px] ${a.done ? 'line-through text-[var(--text-muted)]' : 'text-[var(--text-primary)]'}`}>
                        {a.text}
                      </span>
                      {a.assignee_name && (
                        <span className="text-[10px] text-[var(--text-secondary)]">👤 {a.assignee_name}</span>
                      )}
                      {a.target_date && (
                        <span className={`text-[10px] font-semibold ${isOverdue ? 'text-red-600' : 'text-[var(--text-muted)]'}`}>
                          📅 {new Date(a.target_date).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })}
                        </span>
                      )}
                      {a.done && a.completed_at && (
                        <span className="text-[9px] text-emerald-600">✅ {new Date(a.completed_at).toLocaleDateString('pt-BR')}</span>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
