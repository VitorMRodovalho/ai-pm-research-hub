import { useState, useEffect, useCallback } from 'react';

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Saúde dos Syncs', healthy: 'Saudável', warning: 'Atenção', job: 'Job', schedule: 'Agendamento', lastRun: 'Última Execução', status: 'Status', ago: 'atrás', never: 'Nunca executado', failures: 'falhas (7d)', noFailures: 'Sem falhas (24h)', artiaSync: 'Último Sync Artia', expand: 'Expandir', collapse: 'Recolher', succeeded: 'OK', failed: 'Falha' },
  'en-US': { title: 'Sync Health', healthy: 'Healthy', warning: 'Warning', job: 'Job', schedule: 'Schedule', lastRun: 'Last Run', status: 'Status', ago: 'ago', never: 'Never run', failures: 'failures (7d)', noFailures: 'No failures (24h)', artiaSync: 'Last Artia Sync', expand: 'Expand', collapse: 'Collapse', succeeded: 'OK', failed: 'Failed' },
  'es-LATAM': { title: 'Salud de Sincronización', healthy: 'Saludable', warning: 'Atención', job: 'Job', schedule: 'Horario', lastRun: 'Última Ejecución', status: 'Estado', ago: 'atrás', never: 'Nunca ejecutado', failures: 'fallos (7d)', noFailures: 'Sin fallos (24h)', artiaSync: 'Último Sync Artia', expand: 'Expandir', collapse: 'Contraer', succeeded: 'OK', failed: 'Error' },
};

function useLang(p?: string): string {
  if (p) return p;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
  }
  return 'pt-BR';
}

function timeAgo(dateStr: string, agoLabel: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ${agoLabel}`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ${agoLabel}`;
  const days = Math.floor(hours / 24);
  return `${days}d ${agoLabel}`;
}

const SCHEDULE_LABELS: Record<string, string> = {
  '*/5 * * * *': '5 min',
  '0 3 */5 * *': '5d 03:00',
  '15 3 */5 * *': '5d 03:15',
  '0 14 * * 1': 'Seg 14:00',
  '0 14 * * *': 'Diário 14:00',
  '0 4 * * 0': 'Dom 04:00',
  '0 5 * * 0': 'Dom 05:00',
  '30 5 * * 0': 'Dom 05:30',
};

export default function SyncHealthWidget({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = L[lang] || L['pt-BR'];
  const [data, setData] = useState<any>(null);
  const [authorized, setAuthorized] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m || !(m.is_superadmin || ['manager', 'deputy_manager'].includes(m.operational_role))) return;
    setAuthorized(true);
    try {
      const { data: d, error: rpcErr } = await sb.rpc('get_cron_status');
      if (rpcErr) { console.error('[SyncHealth] RPC error:', rpcErr.message); return; }
      if (d && typeof d === 'object' && !d.error) setData(d);
      else console.warn('[SyncHealth] RPC returned:', d);
    } catch (e: any) { console.error('[SyncHealth] Error:', e?.message); }
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!authorized || !data) return null;

  const health = data.health || {};
  const jobs = data.jobs || [];
  const artia = data.last_artia_sync;
  const isWarning = health.overall_status === 'warning' || health.status === 'warning';

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      {/* Header */}
      <div className="flex items-center gap-2 mb-3">
        <span className="text-lg">🔄</span>
        <h3 className="text-sm font-extrabold text-navy">{t.title}</h3>
        <span className={`ml-auto text-[9px] px-2 py-0.5 rounded-full font-semibold ${
          isWarning ? 'bg-amber-100 text-amber-700' : 'bg-emerald-100 text-emerald-700'
        }`}>{isWarning ? t.warning : t.healthy}</span>
      </div>

      {/* Job table */}
      <div className="overflow-x-auto">
        <table className="w-full text-[10px]">
          <thead>
            <tr className="text-[var(--text-muted)] border-b border-[var(--border-subtle)]">
              <th className="text-left py-1 font-semibold">{t.job}</th>
              <th className="text-left py-1 font-semibold">{t.schedule}</th>
              <th className="text-left py-1 font-semibold">{t.lastRun}</th>
              <th className="text-center py-1 font-semibold">{t.status}</th>
            </tr>
          </thead>
          <tbody>
            {jobs.map((j: any) => {
              const lr = j.last_run;
              const isFailed = lr?.status === 'failed';
              const isNever = !lr;
              const hasFailures7d = (j.recent_failures || j.failures_7d || 0) > 0;
              return (
                <tr key={j.jobid || j.jobname} className="border-b border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                  <td className="py-1.5 font-mono text-[var(--text-primary)]">{j.jobname}</td>
                  <td className="py-1.5 text-[var(--text-muted)]">{SCHEDULE_LABELS[j.schedule] || j.schedule}</td>
                  <td className="py-1.5 text-[var(--text-secondary)]">
                    {isNever ? <span className="text-amber-600">{t.never}</span> : timeAgo(lr.start_time, t.ago)}
                  </td>
                  <td className="py-1.5 text-center">
                    {isNever ? (
                      <span className="inline-block w-2 h-2 rounded-full bg-gray-300" title={t.never} />
                    ) : isFailed ? (
                      <span className="inline-flex items-center gap-1">
                        <span className="inline-block w-2 h-2 rounded-full bg-red-500" />
                        {hasFailures7d && <span className="text-red-600 font-semibold">{j.recent_failures || j.failures_7d} {t.failures}</span>}
                      </span>
                    ) : (
                      <span className="inline-block w-2 h-2 rounded-full bg-emerald-500" title={t.succeeded} />
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Artia sync expandable */}
      {artia && (
        <div className="mt-3 pt-2 border-t border-[var(--border-subtle)]">
          <button
            onClick={() => setExpanded(!expanded)}
            className="flex items-center gap-1 text-[10px] font-semibold text-[var(--text-secondary)] cursor-pointer bg-transparent border-0 p-0 hover:text-navy"
          >
            <span>{expanded ? '▾' : '▸'}</span>
            <span>{t.artiaSync}</span>
            {artia.synced_at && <span className="text-[var(--text-muted)] font-normal ml-1">— {timeAgo(artia.synced_at, t.ago)}</span>}
          </button>
          {expanded && artia.kpis && (
            <div className="mt-2 grid grid-cols-2 sm:grid-cols-3 gap-1.5 text-[9px]">
              {(() => {
                try {
                  const kpis = typeof artia.kpis === 'string' ? JSON.parse(artia.kpis) : artia.kpis;
                  const entries = kpis.kpis || kpis;
                  if (typeof entries === 'object' && !Array.isArray(entries)) {
                    return Object.entries(entries).map(([key, val]: [string, any]) => (
                      <div key={key} className="bg-[var(--surface-section-cool)] rounded-lg px-2 py-1.5">
                        <div className="text-[var(--text-muted)] truncate">{key.replace(/_/g, ' ')}</div>
                        <div className="font-bold text-[var(--text-primary)]">{val?.current ?? val} <span className="font-normal text-[var(--text-muted)]">({val?.pct ?? 0}%)</span></div>
                      </div>
                    ));
                  }
                  return null;
                } catch { return null; }
              })()}
            </div>
          )}
        </div>
      )}

      {/* Footer */}
      <div className="mt-3 pt-2 border-t border-[var(--border-subtle)] flex items-center justify-between text-[9px] text-[var(--text-muted)]">
        <span>{health.total_jobs || jobs.length} jobs · {isWarning ? `⚠️ ${health.jobs_with_recent_failure || health.failures_24h || 0} ${t.failures}` : `✅ ${t.noFailures}`}</span>
        <span>{data.generated_at ? new Date(data.generated_at).toLocaleTimeString() : ''}</span>
      </div>
    </div>
  );
}
