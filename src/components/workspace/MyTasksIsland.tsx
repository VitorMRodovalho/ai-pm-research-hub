import { useState, useEffect, useCallback } from 'react';

interface Task {
  id: string;
  board_id: string;
  board_name: string;
  card_id: string;
  card_title: string;
  card_status: string;
  text: string;
  done: boolean;
  target_date: string | null;
  completed_at: string | null;
}

interface Props {
  lang?: string;
}

const LABELS: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Minhas atividades', pending: 'pendentes', completed: 'concluídas', overdue: 'atrasadas', all: 'Todas', pendingF: 'Pendentes', completedF: 'Concluídas', allDates: 'Todas as datas', week: 'Próximos 7 dias', month: 'Próximos 30 dias', overdueF: 'Atrasadas', loading: 'Carregando...', empty: 'Nenhuma atividade atribuída.' },
  'en-US': { title: 'My tasks', pending: 'pending', completed: 'completed', overdue: 'overdue', all: 'All', pendingF: 'Pending', completedF: 'Completed', allDates: 'All dates', week: 'Next 7 days', month: 'Next 30 days', overdueF: 'Overdue', loading: 'Loading...', empty: 'No assigned tasks.' },
  'es-LATAM': { title: 'Mis actividades', pending: 'pendientes', completed: 'completadas', overdue: 'vencidas', all: 'Todas', pendingF: 'Pendientes', completedF: 'Completadas', allDates: 'Todas las fechas', week: 'Próximos 7 días', month: 'Próximos 30 días', overdueF: 'Vencidas', loading: 'Cargando...', empty: 'Sin actividades asignadas.' },
};

export default function MyTasksIsland({ lang = 'pt-BR' }: Props) {
  const L = LABELS[lang] || LABELS['pt-BR'];
  const [tasks, setTasks] = useState<Task[]>([]);
  const [totalPending, setTotalPending] = useState(0);
  const [totalCompleted, setTotalCompleted] = useState(0);
  const [totalOverdue, setTotalOverdue] = useState(0);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [periodFilter, setPeriodFilter] = useState('all');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    setLoading(true);
    const { data, error } = await sb.rpc('get_my_tasks', {
      p_status_filter: statusFilter,
      p_period_filter: periodFilter,
    });
    if (!error && data) {
      setTasks(data.tasks || []);
      setTotalPending(data.total_pending || 0);
      setTotalCompleted(data.total_completed || 0);
      setTotalOverdue(data.total_overdue || 0);
    }
    setLoading(false);
  }, [statusFilter, periodFilter]);

  useEffect(() => { load(); }, [load]);

  const toggleTask = useCallback(async (taskId: string, currentDone: boolean) => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    const { error } = await sb.rpc('complete_checklist_item', {
      p_checklist_item_id: taskId,
      p_completed: !currentDone,
    });
    if (error) {
      (window as any).toast?.(error.message || 'Error', 'error');
      return;
    }
    load();
  }, [load]);

  // Group by board
  const grouped = tasks.reduce<Record<string, { board_name: string; board_id: string; items: Task[] }>>((acc, t) => {
    if (!acc[t.board_id]) {
      acc[t.board_id] = { board_name: t.board_name, board_id: t.board_id, items: [] };
    }
    acc[t.board_id].items.push(t);
    return acc;
  }, {});

  return (
    <div className="space-y-3">
      {/* Summary */}
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-amber-50 border border-amber-200">
          <span className="text-[14px] font-bold text-amber-700">{totalPending}</span>
          <span className="text-[11px] text-amber-600">{L.pending}</span>
        </div>
        <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-emerald-50 border border-emerald-200">
          <span className="text-[14px] font-bold text-emerald-700">{totalCompleted}</span>
          <span className="text-[11px] text-emerald-600">{L.completed}</span>
        </div>
        {totalOverdue > 0 && (
          <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-50 border border-red-200">
            <span className="text-[14px] font-bold text-red-700">{totalOverdue}</span>
            <span className="text-[11px] text-red-600">{L.overdue}</span>
          </div>
        )}
      </div>

      {/* Filters */}
      <div className="flex gap-2 flex-wrap">
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}
          className="text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5 outline-none">
          <option value="all">{L.all}</option>
          <option value="pending">{L.pendingF}</option>
          <option value="completed">{L.completedF}</option>
        </select>
        <select value={periodFilter} onChange={(e) => setPeriodFilter(e.target.value)}
          className="text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5 outline-none">
          <option value="all">{L.allDates}</option>
          <option value="week">{L.week}</option>
          <option value="month">{L.month}</option>
          <option value="overdue">{L.overdueF}</option>
        </select>
      </div>

      {/* Tasks */}
      {loading ? (
        <p className="text-[12px] text-[var(--text-muted)]">{L.loading}</p>
      ) : Object.keys(grouped).length === 0 ? (
        <p className="text-[12px] text-[var(--text-muted)]">{L.empty}</p>
      ) : (
        <div className="space-y-3">
          {Object.values(grouped).map((group) => (
            <div key={group.board_id} className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden">
              <div className="flex items-center gap-2 px-3 py-2 bg-[var(--surface-section-cool)] border-b border-[var(--border-subtle)]">
                <span className="text-[11px] font-bold text-[var(--text-primary)] flex-1">{group.board_name}</span>
                <span className="text-[10px] text-[var(--text-muted)]">{group.items.filter(i => !i.done).length} {L.pending}</span>
              </div>
              <div className="divide-y divide-[var(--border-subtle)]">
                {group.items.map((task) => {
                  const isOverdue = task.target_date && !task.done && new Date(task.target_date) < new Date();
                  return (
                    <div key={task.id} className="flex items-center gap-2 px-3 py-1.5">
                      <input type="checkbox" checked={task.done}
                        onChange={() => toggleTask(task.id, task.done)}
                        className="w-3.5 h-3.5 rounded accent-emerald-500 cursor-pointer" />
                      <span className={`flex-1 text-[11px] ${task.done ? 'line-through text-[var(--text-muted)]' : 'text-[var(--text-primary)]'}`}>
                        {task.text}
                      </span>
                      <a href={`/admin/board/${task.board_id}?card=${task.card_id}`}
                        className="text-[10px] text-blue-500 hover:underline no-underline font-medium">
                        {task.card_title.length > 25 ? task.card_title.slice(0, 25) + '...' : task.card_title}
                      </a>
                      {task.target_date && (
                        <span className={`text-[10px] font-semibold ${isOverdue ? 'text-red-600' : 'text-[var(--text-muted)]'}`}>
                          📅 {new Date(task.target_date).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })}
                        </span>
                      )}
                      {task.done && task.completed_at && (
                        <span className="text-[9px] text-emerald-600">✅</span>
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
