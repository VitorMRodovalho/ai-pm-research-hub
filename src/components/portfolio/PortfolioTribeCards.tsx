import type { TribeSummary } from '../../hooks/usePortfolio';

interface Props {
  tribes: TribeSummary[];
}

function fmtDate(d: string | null) {
  if (!d) return '—';
  const dt = new Date(d + 'T00:00:00');
  return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
}

const HEALTH_DOT: Record<string, string> = {
  completed: '✅',
  on_track: '🟢',
  at_risk: '🟡',
  delayed: '🔴',
  no_baseline: '⚪',
};

export default function PortfolioTribeCards({ tribes }: Props) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
      {tribes.map(tribe => {
        const baselinePct = tribe.total > 0
          ? Math.round(((tribe.total - tribe.no_baseline) / tribe.total) * 100)
          : 0;

        return (
          <div
            key={tribe.tribe_id}
            className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4 hover:border-teal transition-all"
          >
            {/* Header */}
            <div className="flex items-start justify-between mb-2">
              <div>
                <div className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider">
                  T{tribe.tribe_id}
                </div>
                <div className="text-sm font-extrabold text-[var(--text-primary)] leading-tight">
                  {tribe.tribe_name}
                </div>
              </div>
              <span className="text-xl font-extrabold text-[var(--text-primary)]">{tribe.total}</span>
            </div>

            {/* Leader */}
            <div className="text-[11px] text-[var(--text-secondary)] mb-3">
              Líder: <strong>{tribe.leader?.split(' ')[0] || '—'}</strong>
            </div>

            {/* Health summary */}
            <div className="flex items-center gap-2 text-[11px] mb-2">
              {tribe.completed > 0 && <span>{HEALTH_DOT.completed} {tribe.completed}</span>}
              {tribe.on_track > 0 && <span>{HEALTH_DOT.on_track} {tribe.on_track}</span>}
              {tribe.at_risk > 0 && <span>{HEALTH_DOT.at_risk} {tribe.at_risk}</span>}
              {tribe.delayed > 0 && <span>{HEALTH_DOT.delayed} {tribe.delayed}</span>}
              {tribe.no_baseline > 0 && <span>{HEALTH_DOT.no_baseline} {tribe.no_baseline}</span>}
            </div>

            {/* Next deadline */}
            {(() => {
              const isDeadlineOverdue = tribe.next_deadline && new Date(tribe.next_deadline) < new Date();
              return (
                <div className={`text-[11px] mb-2 ${isDeadlineOverdue ? 'text-red-600 dark:text-red-400' : 'text-[var(--text-secondary)]'}`}>
                  {isDeadlineOverdue ? '⚠ ' : ''}Próx. entrega: <strong>{fmtDate(tribe.next_deadline)}</strong>
                </div>
              );
            })()}

            {/* Checklist progress */}
            <div className="text-[11px] text-[var(--text-secondary)] mb-2">
              Atividades: <strong>{tribe.checklist_pct}%</strong>
            </div>

            {/* Baseline coverage bar */}
            <div className="mt-2">
              <div className="flex justify-between text-[9px] text-[var(--text-muted)] mb-1">
                <span>Baseline</span>
                <span>{baselinePct}%</span>
              </div>
              <div className="w-full h-1.5 rounded-full bg-gray-100 overflow-hidden">
                <div
                  className="h-full rounded-full transition-all"
                  style={{
                    width: `${baselinePct}%`,
                    backgroundColor: baselinePct === 100 ? '#22c55e' : baselinePct >= 50 ? '#eab308' : '#ef4444',
                  }}
                />
              </div>
            </div>

            {/* Link */}
            <a
              href={`/tribe/${tribe.tribe_id}`}
              className="mt-3 block text-center text-[10px] font-bold text-teal no-underline hover:underline"
            >
              Ver Board →
            </a>
          </div>
        );
      })}

      {tribes.length === 0 && (
        <div className="col-span-full text-center py-8 text-[var(--text-muted)] text-sm">Nenhuma tribo encontrada.</div>
      )}
    </div>
  );
}
