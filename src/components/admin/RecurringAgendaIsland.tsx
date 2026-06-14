// src/components/admin/RecurringAgendaIsland.tsx
// #676 Slice 2 — read-only "Agenda recorrente" admin surface.
// Lists the canonical recurring-meeting rules (one source of truth for tribe/initiative
// recurring meetings) with their next occurrence, link, status, and drift indicators.
// Read-only: reads get_recurring_meeting_admin_list (SECDEF, manage_platform). Editing,
// reconcile-on-demand and cron scheduling are later #676 slices.
import { useState, useEffect, useCallback } from 'react';
import { Loader2, CalendarClock, AlertTriangle, ExternalLink, RefreshCw } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface RuleRow {
  rule_id: string;
  scope_type: string;
  scope_name: string;
  title: string;
  event_type: string;
  day_of_week: number; // ISO 1=Mon..7=Sun
  time_start: string;
  duration_minutes: number;
  frequency: string;
  timezone: string;
  status: string;
  meeting_link: string | null;
  anchor_date: string;
  next_occurrence: string | null;
  future_events: number;
  expected_future: number;
  missing_future: number;
  time_mismatch: number;
  link_mismatch: number;
  last_reconciled_at: string | null;
}

function fmtDate(d: string | null): string {
  if (!d) return '—';
  const ts = Date.parse(`${d}T12:00:00Z`);
  if (Number.isNaN(ts)) return d;
  return new Date(ts).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', timeZone: 'UTC' });
}
function fmtTime(t: string | null): string {
  return t ? t.slice(0, 5) : '—';
}

export default function RecurringAgendaIsland() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const [rows, setRows] = useState<RuleRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 300); return; }
    setLoading(true);
    setError(null);
    const { data, error } = await sb.rpc('get_recurring_meeting_admin_list');
    if (error) {
      setError(t('comp.recurringAgenda.loadError', 'Erro ao carregar a agenda recorrente'));
      setLoading(false);
      return;
    }
    setRows(Array.isArray(data) ? data : []);
    setLoading(false);
  }, [getSb, t]);

  useEffect(() => { load(); }, [load]);

  const dowLabel = (iso: number) =>
    t(`comp.recurringAgenda.dow${iso}`, ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][iso] || '?');
  const freqLabel = (f: string) =>
    f === 'biweekly'
      ? t('comp.recurringAgenda.biweekly', 'Quinzenal')
      : t('comp.recurringAgenda.weekly', 'Semanal');
  const statusMeta = (s: string): { label: string; cls: string } => {
    if (s === 'active') return { label: t('comp.recurringAgenda.statusActive', 'Ativa'), cls: 'bg-emerald-50 text-emerald-700' };
    if (s === 'paused') return { label: t('comp.recurringAgenda.statusPaused', 'Pausada'), cls: 'bg-amber-50 text-amber-700' };
    return { label: t('comp.recurringAgenda.statusArchived', 'Arquivada'), cls: 'bg-slate-100 text-slate-500' };
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 py-20 justify-center text-[var(--text-muted)]">
        <Loader2 size={16} className="animate-spin" />
        <span>{t('comp.recurringAgenda.loading', 'Carregando agenda recorrente…')}</span>
      </div>
    );
  }
  if (error) {
    return (
      <div className="text-center py-16 text-rose-600">
        <p>{error}</p>
        <button onClick={load} className="mt-3 inline-flex items-center gap-1 text-sm text-[var(--accent)] hover:underline">
          <RefreshCw size={14} /> {t('comp.recurringAgenda.retry', 'Tentar novamente')}
        </button>
      </div>
    );
  }

  const driftCount = rows.filter((r) => r.missing_future > 0 || r.time_mismatch > 0 || r.link_mismatch > 0).length;

  return (
    <div>
      <header className="mb-4">
        <h1 className="text-xl font-semibold flex items-center gap-2">
          <CalendarClock size={20} className="text-[var(--accent)]" />
          {t('comp.recurringAgenda.heading', 'Agenda recorrente')}
        </h1>
        <p className="text-sm text-[var(--text-muted)] mt-1">
          {t('comp.recurringAgenda.subtitle', 'Regras canônicas de reuniões recorrentes de tribos e iniciativas. Somente leitura.')}
        </p>
        <div className="mt-2 text-xs text-[var(--text-muted)] flex flex-wrap gap-x-4 gap-y-1">
          <span>{rows.length} {t('comp.recurringAgenda.rulesCount', 'regras')}</span>
          {driftCount > 0 && (
            <span className="inline-flex items-center gap-1 text-amber-700">
              <AlertTriangle size={14} />
              {driftCount} {t('comp.recurringAgenda.withDrift', 'com divergência')}
            </span>
          )}
        </div>
      </header>

      <div className="overflow-x-auto rounded-lg border border-[var(--border)]">
        <table className="w-full text-sm">
          <thead className="bg-[var(--bg-subtle)] text-left text-xs uppercase tracking-wide text-[var(--text-muted)]">
            <tr>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colScope', 'Escopo')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colCadence', 'Cadência')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colNext', 'Próxima')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colStatus', 'Status')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colDrift', 'Divergência')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colLink', 'Link')}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const sm = statusMeta(r.status);
              const hasDrift = r.missing_future > 0 || r.time_mismatch > 0 || r.link_mismatch > 0;
              return (
                <tr key={r.rule_id} className="border-t border-[var(--border)] align-top">
                  <td className="px-3 py-2">
                    <div className="font-medium">{r.scope_name}</div>
                    <div className="text-xs text-[var(--text-muted)]">{r.title}</div>
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">
                    {dowLabel(r.day_of_week)} {fmtTime(r.time_start)}
                    <span className="text-xs text-[var(--text-muted)]"> · {freqLabel(r.frequency)}</span>
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">
                    {fmtDate(r.next_occurrence)}
                    <span className="text-xs text-[var(--text-muted)]"> · {r.future_events}/{r.expected_future}</span>
                  </td>
                  <td className="px-3 py-2">
                    <span className={`inline-block px-2 py-0.5 rounded-full text-xs ${sm.cls}`}>{sm.label}</span>
                  </td>
                  <td className="px-3 py-2">
                    {hasDrift ? (
                      <span className="inline-flex items-center gap-1 text-xs text-amber-700">
                        <AlertTriangle size={14} />
                        {r.missing_future > 0 && <span>{r.missing_future} {t('comp.recurringAgenda.missing', 'faltando')}</span>}
                        {r.time_mismatch > 0 && <span>· {r.time_mismatch} {t('comp.recurringAgenda.timeOff', 'horário')}</span>}
                        {r.link_mismatch > 0 && <span>· {r.link_mismatch} {t('comp.recurringAgenda.linkOff', 'link')}</span>}
                      </span>
                    ) : (
                      <span className="text-xs text-emerald-600">{t('comp.recurringAgenda.inSync', 'Em dia')}</span>
                    )}
                  </td>
                  <td className="px-3 py-2">
                    {r.meeting_link ? (
                      <a href={r.meeting_link} target="_blank" rel="noopener noreferrer"
                         className="inline-flex items-center gap-1 text-[var(--accent)] hover:underline text-xs">
                        <ExternalLink size={14} /> Meet
                      </a>
                    ) : <span className="text-xs text-[var(--text-muted)]">—</span>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <p className="mt-3 text-xs text-[var(--text-muted)]">
        {t('comp.recurringAgenda.readonlyNote', 'Esta tela é somente leitura. A geração de eventos e a edição de recorrências chegam nas próximas fatias.')}
      </p>
    </div>
  );
}
