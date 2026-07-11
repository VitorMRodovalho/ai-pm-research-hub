import { useState, useEffect, useCallback, useRef } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

/* ────────────────────────── Shapes (grounded on live RPC output) ──────────────────────────
 * get_gp_cohort_health() and get_cycle_attendance_overview(p_cycle_code) both return jsonb.
 * Field names below mirror the RPC bodies exactly (migrations 409/411). Both self-gate by
 * manage_member OR view_internal_analytics and return { error } when the caller lacks it —
 * we surface that as the "restricted" state instead of an empty page.
 */
interface CohortSummary {
  total: number;
  with_tribe: number;
  committee_members: number;
  without_tribe: number;
  at_kickoff: number;
  no_kickoff: number;
  no_activity: number;
}

interface AtRiskMember {
  member_id: string;
  name: string;
  chapter: string | null;
  is_committee: boolean;
  no_tribe: boolean;
  no_kickoff: boolean;
  no_activity: boolean;
  risk_count: number;
}

interface PendingApproval {
  invitation_id: string;
  requester_member_id: string;
  requester_name: string;
  tribe: string | null;
  legacy_tribe_id: number | null;
  requested_at: string;
  expires_at: string;
  days_waiting: number;
}

interface CohortHealth {
  cycle: { code: string; label: string };
  kickoff_event_id: string | null;
  cohort_summary: CohortSummary;
  at_risk_members: AtRiskMember[];
  pending_leader_approvals: PendingApproval[];
  generated_at: string;
  error?: string;
}

interface AttendanceMember {
  member_id: string;
  name: string;
  chapter: string | null;
  tribe_id: number | null;
  present: number;
  absent: number;
  excused: number;
  eligible: number;
  attendance_rate: number | null;
}

interface AttendanceOverview {
  cycle: { code: string; label: string; start: string; end: string; is_current: boolean };
  total_members: number;
  members: AttendanceMember[];
  generated_at: string;
  error?: string;
}

interface CycleRow {
  cycle_code: string;
  cycle_label: string;
  is_current: boolean;
  sort_order: number;
}

export default function CohortHealthIsland() {
  const t = usePageI18n();
  const [health, setHealth] = useState<CohortHealth | null>(null);
  const [attendance, setAttendance] = useState<AttendanceOverview | null>(null);
  const [cycles, setCycles] = useState<CycleRow[]>([]);
  const [selectedCycle, setSelectedCycle] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [attLoading, setAttLoading] = useState(false);
  const [restricted, setRestricted] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const toast = useCallback((msg: string, type = '') => (window as any).toast?.(msg, type), []);

  const fetchAttendance = useCallback(async (cycleCode: string) => {
    const sb = getSb();
    if (!sb) return;
    setAttLoading(true);
    const { data, error } = await sb.rpc('get_cycle_attendance_overview', { p_cycle_code: cycleCode || null });
    if (error) {
      toast(t('comp.cohortHealth.error.load', 'Erro ao carregar dados.') + ' ' + error.message, 'error');
    } else if (data?.error) {
      setRestricted(true);
    } else if (data) {
      setAttendance(data);
    }
    setAttLoading(false);
  }, [getSb, t, toast]);

  const fetchAll = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const [healthRes, cyclesRes] = await Promise.all([
      sb.rpc('get_gp_cohort_health'),
      sb.rpc('list_cycles'),
    ]);
    if (healthRes.error) {
      toast(t('comp.cohortHealth.error.load', 'Erro ao carregar dados.') + ' ' + healthRes.error.message, 'error');
    } else if (healthRes.data?.error) {
      setRestricted(true);
      setLoading(false);
      return;
    } else if (healthRes.data) {
      setHealth(healthRes.data);
    }
    if (!cyclesRes.error && Array.isArray(cyclesRes.data)) {
      const sorted = [...cyclesRes.data].sort((a: CycleRow, b: CycleRow) => b.sort_order - a.sort_order);
      setCycles(sorted);
      const current = sorted.find((c: CycleRow) => c.is_current);
      const initial = current?.cycle_code || sorted[0]?.cycle_code || '';
      setSelectedCycle(initial);
      await fetchAttendance(initial);
    } else {
      await fetchAttendance('');
    }
    setLoading(false);
  }, [getSb, t, toast, fetchAttendance]);

  // Stable mount effect (usePageI18n returns a new `t` each render — mirror the
  // DataHealthIsland ref pattern to avoid listener accumulation / retry storms).
  const fetchAllRef = useRef(fetchAll);
  fetchAllRef.current = fetchAll;
  useEffect(() => {
    let cancelled = false;
    const boot = () => {
      if (cancelled) return;
      if (getSb()) fetchAllRef.current();
      else setTimeout(boot, 300);
    };
    boot();
    const handler = () => fetchAllRef.current();
    window.addEventListener('nav:member', handler);
    return () => {
      cancelled = true;
      window.removeEventListener('nav:member', handler);
    };
  }, [getSb]);

  const onCycleChange = (code: string) => {
    setSelectedCycle(code);
    fetchAttendance(code);
  };

  const fmtDate = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString('pt-BR') : '—');

  if (loading && !health) {
    return <div className="text-center py-8 text-[var(--text-muted)] text-sm animate-pulse">{t('comp.cohortHealth.loading', 'Carregando visão da coorte...')}</div>;
  }

  if (restricted) {
    return (
      <div className="text-center py-16 text-[var(--text-muted)] text-sm">
        {t('comp.cohortHealth.restricted', 'Acesso restrito: requer permissão de gestão de membros ou analytics interno.')}
      </div>
    );
  }

  const summary = health?.cohort_summary || { total: 0, with_tribe: 0, committee_members: 0, without_tribe: 0, at_kickoff: 0, no_kickoff: 0, no_activity: 0 };
  const atRisk = health?.at_risk_members || [];
  const pending = health?.pending_leader_approvals || [];
  const attMembers = attendance?.members || [];

  const summaryCards = [
    { key: 'total', label: t('comp.cohortHealth.summary.total', 'Total na coorte'), value: summary.total, accent: 'text-[var(--text-primary)]' },
    { key: 'withTribe', label: t('comp.cohortHealth.summary.withTribe', 'Com tribo'), value: summary.with_tribe, accent: 'text-emerald-600' },
    { key: 'withoutTribe', label: t('comp.cohortHealth.summary.withoutTribe', 'Sem tribo (em risco)'), value: summary.without_tribe, accent: summary.without_tribe > 0 ? 'text-amber-600' : 'text-emerald-600' },
    { key: 'committee', label: t('comp.cohortHealth.summary.committee', 'Membros de comitê'), value: summary.committee_members, accent: 'text-[var(--text-primary)]' },
    { key: 'noKickoff', label: t('comp.cohortHealth.summary.noKickoff', 'Sem kickoff'), value: summary.no_kickoff, accent: summary.no_kickoff > 0 ? 'text-amber-600' : 'text-emerald-600' },
    { key: 'noActivity', label: t('comp.cohortHealth.summary.noActivity', 'Sem atividade'), value: summary.no_activity, accent: summary.no_activity > 0 ? 'text-amber-600' : 'text-emerald-600' },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-extrabold text-navy">{t('comp.cohortHealth.title', 'Saúde da Coorte (GP)')}</h2>
          <p className="text-xs text-[var(--text-secondary)]">
            {t('comp.cohortHealth.subtitle', 'Visibilidade GP/co-GP: pendências de líder e coorte em risco.')}
            {health?.cycle?.label ? ` · ${health.cycle.label}` : ''}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {health?.generated_at && (
            <span className="text-[10px] text-[var(--text-muted)]">
              {t('comp.cohortHealth.generatedAt', 'Atualizado:')} {new Date(health.generated_at).toLocaleString('pt-BR')}
            </span>
          )}
          <button onClick={() => fetchAll()} disabled={loading}
            className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-[var(--text-primary)] text-xs font-semibold hover:bg-[var(--surface-hover)] cursor-pointer bg-transparent disabled:opacity-50">
            {loading ? '...' : t('comp.cohortHealth.refresh', 'Atualizar')}
          </button>
        </div>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        {summaryCards.map(card => (
          <div key={card.key} className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3">
            <div className="text-[10px] uppercase tracking-wide font-semibold text-[var(--text-secondary)]">{card.label}</div>
            <div className={`text-2xl font-extrabold ${card.accent}`}>{card.value}</div>
          </div>
        ))}
      </div>

      {/* Pending leader approvals */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
        <div className="mb-2">
          <h3 className="text-sm font-bold text-navy">
            {t('comp.cohortHealth.pending.title', 'Pendências de aprovação de líder')}
            <span className="ml-2 text-[10px] font-semibold text-amber-600">{pending.length}</span>
          </h3>
          <p className="text-[11px] text-[var(--text-secondary)] mt-0.5">
            {t('comp.cohortHealth.pending.subtitle', 'Auto-solicitações de entrada em tribo aguardando o líder responder.')}
          </p>
        </div>
        {pending.length === 0 ? (
          <p className="text-xs text-[var(--text-muted)]">{t('comp.cohortHealth.pending.empty', 'Nenhuma pendência.')}</p>
        ) : (
          <div className="space-y-2">
            {pending.map(p => (
              <div key={p.invitation_id} className="flex items-start justify-between gap-3 rounded-lg bg-amber-50 border border-amber-200 p-2.5">
                <div>
                  <div className="text-xs font-bold text-[var(--text-primary)]">{p.requester_name}</div>
                  <div className="text-[11px] text-[var(--text-secondary)] mt-0.5">
                    {t('comp.cohortHealth.pending.tribe', 'Tribo:')} {p.tribe || '—'}
                  </div>
                </div>
                <div className="text-right shrink-0">
                  <div className="text-[11px] font-semibold text-amber-700">
                    {p.days_waiting} {t('comp.cohortHealth.pending.daysWaiting', 'dia(s) aguardando')}
                  </div>
                  <div className="text-[10px] text-[var(--text-muted)]">
                    {t('comp.cohortHealth.pending.expires', 'Expira:')} {fmtDate(p.expires_at)}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* At-risk members */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
        <div className="mb-2">
          <h3 className="text-sm font-bold text-navy">
            {t('comp.cohortHealth.risk.title', 'Coorte em risco')}
            <span className="ml-2 text-[10px] font-semibold text-amber-600">{atRisk.length}</span>
          </h3>
          <p className="text-[11px] text-[var(--text-secondary)] mt-0.5">
            {t('comp.cohortHealth.risk.subtitle', 'Membros sem tribo, sem presença no kickoff, ou sem atividade no ciclo.')}
          </p>
        </div>
        {atRisk.length === 0 ? (
          <p className="text-xs text-[var(--text-muted)]">{t('comp.cohortHealth.risk.empty', 'Ninguém em risco.')}</p>
        ) : (
          <div className="space-y-1.5">
            {atRisk.map(m => (
              <div key={m.member_id} className="flex items-center gap-2 flex-wrap rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] p-2.5">
                <span className="text-xs font-bold text-[var(--text-primary)]">{m.name}</span>
                <span className="text-[10px] text-[var(--text-muted)]">{m.chapter || '—'}</span>
                {m.is_committee && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full font-semibold text-blue-700 bg-blue-50 border border-blue-200">
                    {t('comp.cohortHealth.risk.committee', 'comitê')}
                  </span>
                )}
                <span className="flex-1" />
                {m.no_tribe && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full font-semibold text-amber-700 bg-amber-50 border border-amber-200">
                    {t('comp.cohortHealth.risk.noTribe', 'sem tribo')}
                  </span>
                )}
                {m.no_kickoff && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full font-semibold text-amber-700 bg-amber-50 border border-amber-200">
                    {t('comp.cohortHealth.risk.noKickoff', 'sem kickoff')}
                  </span>
                )}
                {m.no_activity && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full font-semibold text-amber-700 bg-amber-50 border border-amber-200">
                    {t('comp.cohortHealth.risk.noActivity', 'sem atividade')}
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Attendance overview */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
        <div className="flex items-center justify-between flex-wrap gap-2 mb-2">
          <div>
            <h3 className="text-sm font-bold text-navy">{t('comp.cohortHealth.att.title', 'Presença por ciclo')}</h3>
            <p className="text-[11px] text-[var(--text-secondary)] mt-0.5">
              {t('comp.cohortHealth.att.subtitle', 'Presenças, faltas e justificativas por membro.')}
            </p>
          </div>
          {cycles.length > 0 && (
            <select value={selectedCycle} onChange={e => onCycleChange(e.target.value)}
              className="px-2 py-1.5 rounded-md border border-[var(--border-default)] text-xs bg-[var(--surface-base)] text-[var(--text-primary)]">
              {cycles.map(c => (
                <option key={c.cycle_code} value={c.cycle_code}>{c.cycle_label}</option>
              ))}
            </select>
          )}
        </div>
        {attLoading ? (
          <div className="text-center py-6 text-[var(--text-muted)] text-xs animate-pulse">{t('comp.cohortHealth.loading', 'Carregando...')}</div>
        ) : attMembers.length === 0 ? (
          <p className="text-xs text-[var(--text-muted)]">{t('comp.cohortHealth.att.empty', 'Sem dados de presença para este ciclo.')}</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="text-[10px] uppercase tracking-wide text-[var(--text-secondary)] border-b border-[var(--border-default)]">
                  <th className="text-left font-semibold py-1.5 px-2">{t('comp.cohortHealth.att.member', 'Membro')}</th>
                  <th className="text-left font-semibold py-1.5 px-2">{t('comp.cohortHealth.att.chapter', 'Capítulo')}</th>
                  <th className="text-right font-semibold py-1.5 px-2">{t('comp.cohortHealth.att.present', 'Presenças')}</th>
                  <th className="text-right font-semibold py-1.5 px-2">{t('comp.cohortHealth.att.absent', 'Faltas')}</th>
                  <th className="text-right font-semibold py-1.5 px-2">{t('comp.cohortHealth.att.excused', 'Justificadas')}</th>
                  <th className="text-right font-semibold py-1.5 px-2">{t('comp.cohortHealth.att.rate', 'Taxa')}</th>
                </tr>
              </thead>
              <tbody>
                {attMembers.map(m => {
                  const rate = m.attendance_rate == null ? null : Math.round(m.attendance_rate * 100);
                  const rateColor = rate == null ? 'text-[var(--text-muted)]' : rate >= 75 ? 'text-emerald-600' : rate >= 50 ? 'text-amber-600' : 'text-red-600';
                  return (
                    <tr key={m.member_id} className="border-b border-[var(--border-default)]/50">
                      <td className="py-1.5 px-2 font-semibold text-[var(--text-primary)]">{m.name}</td>
                      <td className="py-1.5 px-2 text-[var(--text-muted)]">{m.chapter || '—'}</td>
                      <td className="py-1.5 px-2 text-right text-[var(--text-primary)]">{m.present}</td>
                      <td className="py-1.5 px-2 text-right text-[var(--text-primary)]">{m.absent}</td>
                      <td className="py-1.5 px-2 text-right text-[var(--text-muted)]">{m.excused}</td>
                      <td className={`py-1.5 px-2 text-right font-bold ${rateColor}`}>{rate == null ? '—' : `${rate}%`}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
