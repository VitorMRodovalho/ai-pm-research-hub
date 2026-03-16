import { useState } from 'react';
import { usePilots } from '../../hooks/usePilots';

interface Props {
  i18n: Record<string, string>;
}

const STATUS_COLORS: Record<string, { bg: string; text: string; icon: string }> = {
  active:    { bg: 'bg-emerald-50', text: 'text-emerald-700', icon: '🟢' },
  completed: { bg: 'bg-blue-50',    text: 'text-blue-700',    icon: '✅' },
  draft:     { bg: 'bg-gray-50',    text: 'text-gray-500',    icon: '⬜' },
  cancelled: { bg: 'bg-red-50',     text: 'text-red-500',     icon: '🔴' },
};

export default function PilotsIsland({ i18n }: Props) {
  const { summary, selectedPilot, loading, loadPilotDetail, closePilotDetail } = usePilots();
  const [expandedId, setExpandedId] = useState<string | null>(null);

  if (loading) return <div className="text-[var(--text-muted)] text-sm py-8 text-center">{i18n.loading || 'Loading...'}</div>;
  if (!summary) return <div className="text-center py-12 text-4xl">🚀</div>;

  const { pilots, target, progress_pct, active } = summary;

  return (
    <div>
      {/* Progress header */}
      <div className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] p-6 mb-6">
        <div className="flex items-center justify-between flex-wrap gap-3 mb-3">
          <div>
            <span className="text-sm font-bold text-[var(--text-primary)]">{i18n.subtitle}</span>
            <span className="ml-2 text-sm text-[var(--text-muted)]">
              {i18n.progress}: {active}/{target} ({progress_pct}%)
            </span>
          </div>
        </div>
        <div className="w-full h-2.5 bg-[var(--surface-base)] rounded-full overflow-hidden">
          <div
            className="h-full rounded-full bg-teal transition-all duration-500"
            style={{ width: `${Math.min(progress_pct, 100)}%` }}
          />
        </div>
      </div>

      {/* Pilot cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {/* Render existing pilots */}
        {(pilots || []).map((p: any) => {
          const st = STATUS_COLORS[p.status] || STATUS_COLORS.draft;
          return (
            <div key={p.id} className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] p-5 shadow-sm hover:-translate-y-px hover:shadow-md transition-all">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-extrabold text-navy">
                  {st.icon} PILOT #{p.pilot_number}
                </h3>
                <span className={`px-2 py-0.5 rounded-full text-[.6rem] font-bold ${st.bg} ${st.text}`}>
                  {i18n[p.status] || p.status}
                </span>
              </div>
              <div className="text-[.82rem] font-semibold text-[var(--text-primary)] mb-2">{p.title}</div>
              {p.hypothesis && (
                <p className="text-[.75rem] text-[var(--text-secondary)] mb-3 line-clamp-3">{p.hypothesis}</p>
              )}
              <div className="flex items-center gap-3 text-[.7rem] text-[var(--text-muted)] mb-3">
                {p.started_at && <span>{p.days_active}d</span>}
                {p.team_count && <span>{i18n.team}: {p.team_count}</span>}
                {p.metrics_count > 0 && <span>{i18n.metrics}: {p.metrics_count}</span>}
              </div>
              <button
                onClick={() => {
                  if (expandedId === p.id) { setExpandedId(null); closePilotDetail(); }
                  else { setExpandedId(p.id); loadPilotDetail(p.id); }
                }}
                className="text-teal text-[.75rem] font-semibold cursor-pointer bg-transparent border-0 p-0 hover:underline"
              >
                {expandedId === p.id ? '▲ ' : ''}{i18n.viewDetails} →
              </button>

              {/* Expanded detail */}
              {expandedId === p.id && selectedPilot && (
                <PilotDetail pilot={selectedPilot} i18n={i18n} />
              )}
            </div>
          );
        })}

        {/* Placeholder cards to fill up to 3 */}
        {Array.from({ length: Math.max(0, 3 - (pilots?.length || 0)) }).map((_, i) => (
          <div key={`placeholder-${i}`} className="bg-[var(--surface-card)] rounded-2xl border border-dashed border-[var(--border-default)] p-5 flex flex-col items-center justify-center min-h-[200px] opacity-60">
            <div className="text-3xl mb-2">🔮</div>
            <div className="text-sm font-bold text-[var(--text-muted)]">PILOT #{(pilots?.length || 0) + i + 1}</div>
            <div className="text-xs text-[var(--text-muted)] mt-1">{i18n.tbd}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function PilotDetail({ pilot, i18n }: { pilot: any; i18n: Record<string, string> }) {
  const p = pilot.pilot;
  const metrics = pilot.metrics || [];

  return (
    <div className="mt-4 pt-4 border-t border-[var(--border-subtle)] text-[.75rem]">
      {p.problem_statement && (
        <div className="mb-3">
          <div className="font-bold text-[var(--text-primary)] mb-1">📋 {i18n.problem}</div>
          <p className="text-[var(--text-secondary)]">{p.problem_statement}</p>
        </div>
      )}
      {p.scope && (
        <div className="mb-3">
          <div className="font-bold text-[var(--text-primary)] mb-1">🎯 {i18n.scope}</div>
          <p className="text-[var(--text-secondary)]">{p.scope}</p>
        </div>
      )}

      {/* Metrics table */}
      {metrics.length > 0 && (
        <div className="mb-3">
          <div className="font-bold text-[var(--text-primary)] mb-2">📊 {i18n.metrics}</div>
          <div className="overflow-x-auto">
            <table className="w-full text-[.7rem]">
              <thead>
                <tr className="text-left text-[var(--text-muted)]">
                  <th className="pb-1 pr-2">{i18n.metricName || 'Métrica'}</th>
                  <th className="pb-1 pr-2">Baseline</th>
                  <th className="pb-1 pr-2">Target</th>
                  <th className="pb-1 pr-2">{i18n.metricCurrent || 'Atual'}</th>
                </tr>
              </thead>
              <tbody>
                {metrics.map((m: any, idx: number) => {
                  const current = m.current;
                  const hasValue = current !== null && current !== undefined;
                  const target = parseFloat(m.target);
                  const baseline = parseFloat(m.baseline);
                  const currentVal = hasValue ? parseFloat(String(current)) : null;
                  const hitTarget = currentVal !== null && (
                    target >= baseline ? currentVal >= target : currentVal <= target
                  );
                  return (
                    <tr key={idx} className="border-t border-[var(--border-subtle)]">
                      <td className="py-1.5 pr-2 text-[var(--text-primary)]">{m.name}</td>
                      <td className="py-1.5 pr-2 text-[var(--text-muted)]">{m.baseline} {m.unit}</td>
                      <td className="py-1.5 pr-2 text-[var(--text-muted)]">{m.target} {m.unit}</td>
                      <td className="py-1.5 pr-2 font-semibold">
                        {hasValue ? (
                          <span className={hitTarget ? 'text-emerald-600' : 'text-amber-600'}>
                            {String(current)} {hitTarget ? '✅' : '⬜'}
                          </span>
                        ) : (
                          <span className="text-[var(--text-muted)]">— ⬜</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <div className="text-[.68rem] text-[var(--text-muted)]">
        {pilot.days_active}d {i18n.active?.toLowerCase() || 'active'}
      </div>
    </div>
  );
}
