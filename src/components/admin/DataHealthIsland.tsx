import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface AnomalyItem {
  id: string;
  anomaly_type: string;
  severity: string;
  description: string;
  auto_fixable: boolean;
  detected_at: string;
}

interface HistoryItem {
  anomaly_type: string;
  description: string;
  fixed_by: string | null;
  fixed_at: string | null;
}

interface AnomalyReport {
  summary: {
    total_pending: number;
    total_fixed: number;
    by_type: Record<string, number>;
    by_severity: Record<string, number>;
  };
  pending: AnomalyItem[];
  history: HistoryItem[];
}

const SEVERITY_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  critical: { bg: 'bg-red-50', text: 'text-red-700', border: 'border-red-200' },
  warning: { bg: 'bg-amber-50', text: 'text-amber-700', border: 'border-amber-200' },
  info: { bg: 'bg-blue-50', text: 'text-blue-700', border: 'border-blue-200' },
};

const ANOMALY_LABELS: Record<string, string> = {
  tribe_selection_drift: 'Tribe Selection Drift',
  active_flag_inconsistency: 'Active Flag Inconsistency',
  role_designation_mismatch: 'Role/Designation Mismatch',
  orphan_active_no_tribe: 'Orphan Active (No Tribe)',
  cycle_array_stale: 'Cycle Array Stale',
  duplicate_email: 'Duplicate Email',
  never_logged_in: 'Never Logged In',
  assignment_orphan: 'Assignment Orphan',
  sla_config_missing: 'SLA Config Missing',
};

export default function DataHealthIsland() {
  const t = usePageI18n();
  const [report, setReport] = useState<AnomalyReport | null>(null);
  const [loading, setLoading] = useState(true);
  const [detecting, setDetecting] = useState(false);
  const [fixing, setFixing] = useState(false);
  const [resolveId, setResolveId] = useState<string | null>(null);
  const [resolveDesc, setResolveDesc] = useState('');
  const [resolveNotes, setResolveNotes] = useState('');

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const toast = useCallback((msg: string, type = '') => (window as any).toast?.(msg, type), []);

  const fetchReport = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const { data, error } = await sb.rpc('admin_get_anomaly_report');
    if (!error && data) setReport(data);
    else if (error) toast(t('comp.dataHealth.errorLoad', 'Erro ao carregar relatório: ') + error.message, 'error');
    setLoading(false);
  }, [getSb, toast]);

  useEffect(() => {
    const boot = () => { if (getSb()) fetchReport(); else setTimeout(boot, 300); };
    boot();
    window.addEventListener('nav:member', () => fetchReport());
  }, [getSb, fetchReport]);

  const handleDetect = async (autoFix: boolean) => {
    const sb = getSb();
    if (!sb) return;
    autoFix ? setFixing(true) : setDetecting(true);
    const { data, error } = await sb.rpc('admin_detect_data_anomalies', { p_auto_fix: autoFix });
    if (error) {
      toast(t('comp.dataHealth.errorProcess', 'Erro ao processar anomalias.'), 'error');
    } else {
      const s = data?.summary || {};
      toast(
        autoFix
          ? `${t('comp.dataHealth.fixesApplied', 'Correções aplicadas:')} ${s.fixed || 0} ${t('comp.dataHealth.fixed', 'corrigidas')}, ${s.pending || 0} ${t('comp.dataHealth.pendingCount', 'pendentes')}.`
          : `${t('comp.dataHealth.detectionDone', 'Detecção concluída:')} ${(s.fixed || 0) + (s.pending || 0)} ${t('comp.dataHealth.anomaliesFound', 'anomalias encontradas')}.`,
        'success'
      );
    }
    setDetecting(false);
    setFixing(false);
    fetchReport();
  };

  const handleResolve = async () => {
    if (!resolveId) return;
    const sb = getSb();
    if (!sb) return;
    const { error } = await sb.rpc('admin_resolve_anomaly', { p_anomaly_id: resolveId, p_notes: resolveNotes });
    if (error) toast(t('comp.dataHealth.errorResolve', 'Erro ao resolver anomalia.'), 'error');
    else toast(t('comp.dataHealth.resolvedSuccess', 'Anomalia resolvida com sucesso.'), 'success');
    setResolveId(null);
    setResolveNotes('');
    fetchReport();
  };

  if (loading && !report) {
    return <div className="text-center py-8 text-[var(--text-muted)] text-sm animate-pulse">{t('comp.dataHealth.loading', 'Carregando data health...')}</div>;
  }

  const summary = report?.summary || { total_pending: 0, total_fixed: 0, by_severity: {} };
  const pending = report?.pending || [];
  const history = report?.history || [];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-extrabold text-navy">Data Health</h2>
          <p className="text-xs text-[var(--text-secondary)]">{t('comp.dataHealth.subtitle', 'Detecção e correção automática de anomalias nos dados')}</p>
        </div>
        <div className="flex gap-2">
          <button onClick={() => handleDetect(false)} disabled={detecting}
            className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-[var(--text-primary)] text-xs font-semibold hover:bg-[var(--surface-hover)] cursor-pointer bg-transparent disabled:opacity-50">
            {detecting ? '...' : t('comp.dataHealth.runDetection', 'Executar Detecção')}
          </button>
          <button onClick={() => handleDetect(true)} disabled={fixing}
            className="px-3 py-2 rounded-lg bg-emerald-600 text-white text-xs font-semibold hover:opacity-90 cursor-pointer border-0 disabled:opacity-50">
            {fixing ? '...' : t('comp.dataHealth.autoFix', 'Corrigir Automáticas')}
          </button>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { title: 'Total Pending', value: summary.total_pending, accent: summary.total_pending > 0 ? 'text-amber-600' : 'text-emerald-600' },
          { title: 'Total Fixed', value: summary.total_fixed, accent: 'text-emerald-600' },
          { title: 'Critical', value: summary.by_severity?.critical || 0, accent: (summary.by_severity?.critical || 0) > 0 ? 'text-red-600' : 'text-[var(--text-primary)]' },
          { title: 'Warnings', value: summary.by_severity?.warning || 0, accent: (summary.by_severity?.warning || 0) > 0 ? 'text-amber-600' : 'text-[var(--text-primary)]' },
        ].map(card => (
          <div key={card.title} className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-3">
            <div className="text-[10px] uppercase tracking-wide font-semibold text-[var(--text-secondary)]">{card.title}</div>
            <div className={`text-2xl font-extrabold ${card.accent}`}>{card.value}</div>
          </div>
        ))}
      </div>

      {/* Pending */}
      <div>
        <h3 className="text-sm font-bold text-navy mb-2">{t('comp.dataHealth.pending', 'Pendentes')}</h3>
        <div className="space-y-2">
          {pending.length === 0 && <p className="text-xs text-[var(--text-muted)]">{t('comp.dataHealth.noPending', 'Nenhuma anomalia pendente.')}</p>}
          {pending.map(a => {
            const sc = SEVERITY_COLORS[a.severity] || SEVERITY_COLORS.info;
            const label = ANOMALY_LABELS[a.anomaly_type] || a.anomaly_type;
            return (
              <div key={a.id} className={`flex items-start gap-3 p-3 rounded-xl border ${sc.border} ${sc.bg}`}>
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1 flex-wrap">
                    <span className={`text-[10px] font-bold uppercase tracking-wide ${sc.text}`}>{label}</span>
                    <span className={`text-[9px] px-1.5 py-0.5 rounded-full font-semibold ${sc.text} ${sc.bg} border ${sc.border}`}>{a.severity}</span>
                    {a.auto_fixable && <span className="text-[9px] px-1.5 py-0.5 rounded-full font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200">auto-fixable</span>}
                  </div>
                  <p className="text-xs text-[var(--text-primary)]">{a.description}</p>
                  <p className="text-[10px] text-[var(--text-muted)] mt-1">{new Date(a.detected_at).toLocaleString('pt-BR')}</p>
                </div>
                {!a.auto_fixable && (
                  <button onClick={() => { setResolveId(a.id); setResolveDesc(a.description); setResolveNotes(''); }}
                    className="px-2 py-1 rounded-lg border border-[var(--border-default)] text-[10px] font-semibold cursor-pointer hover:bg-[var(--surface-hover)] bg-transparent text-[var(--text-primary)]">
                    {t('comp.dataHealth.resolve', 'Resolver')}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* History */}
      <div>
        <h3 className="text-sm font-bold text-navy mb-2">{t('comp.dataHealth.history', 'Histórico')}</h3>
        <div className="space-y-2">
          {history.length === 0 && <p className="text-xs text-[var(--text-muted)]">{t('comp.dataHealth.noHistory', 'Nenhuma correção registrada.')}</p>}
          {history.slice(0, 20).map((h, i) => {
            const label = ANOMALY_LABELS[h.anomaly_type] || h.anomaly_type;
            return (
              <div key={i} className="flex items-center gap-3 p-2 rounded-lg bg-emerald-50/50 border border-emerald-100 text-xs">
                <span className="text-emerald-600 font-semibold">{label}</span>
                <span className="text-[var(--text-muted)] flex-1">{h.description?.substring(0, 80) || ''}</span>
                <span className="text-[10px] text-[var(--text-muted)]">
                  {h.fixed_by || 'auto'} · {h.fixed_at ? new Date(h.fixed_at).toLocaleString('pt-BR') : ''}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Resolve Modal */}
      {resolveId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setResolveId(null)}>
          <div className="bg-[var(--surface-card)] rounded-2xl shadow-xl w-full max-w-md mx-4 p-5" onClick={e => e.stopPropagation()}>
            <h3 className="text-sm font-bold text-navy mb-2">{t('comp.dataHealth.resolveTitle', 'Resolver Anomalia')}</h3>
            <p className="text-xs text-[var(--text-secondary)] mb-3">{resolveDesc}</p>
            <textarea value={resolveNotes} onChange={e => setResolveNotes(e.target.value)}
              placeholder={t('comp.dataHealth.resolveNotesPlaceholder', 'Notas de resolução (opcional)')}
              className="w-full border border-[var(--border-default)] rounded-lg px-3 py-2 text-xs bg-[var(--surface-card)] text-[var(--text-primary)] mb-3" rows={3} />
            <div className="flex gap-2 justify-end">
              <button onClick={() => setResolveId(null)}
                className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-xs font-semibold cursor-pointer bg-transparent text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]">
                {t('comp.dataHealth.cancel', 'Cancelar')}
              </button>
              <button onClick={handleResolve}
                className="px-3 py-2 rounded-lg bg-emerald-600 text-white text-xs font-semibold hover:opacity-90 cursor-pointer border-0">
                {t('comp.dataHealth.confirmResolve', 'Confirmar Resolução')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
