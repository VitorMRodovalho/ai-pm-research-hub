import { useState } from 'react';
import CRDetail from '../governance/CRDetail';
import GovernanceBatchModal from './GovernanceBatchModal';

const TYPE_COLORS: Record<string, string> = { editorial: 'bg-gray-100 text-gray-700', operational: 'bg-blue-100 text-blue-700', structural: 'bg-amber-100 text-amber-700', emergency: 'bg-red-100 text-red-700' };
const IMPACT_COLORS: Record<string, string> = { low: 'bg-gray-100 text-gray-600', medium: 'bg-blue-100 text-blue-700', high: 'bg-amber-100 text-amber-700', critical: 'bg-red-100 text-red-700' };
const STATUS_COLORS: Record<string, string> = { draft: 'bg-gray-100 text-gray-600', submitted: 'bg-blue-100 text-blue-700', under_review: 'bg-yellow-100 text-yellow-700', approved: 'bg-green-100 text-green-700', rejected: 'bg-red-100 text-red-700', implemented: 'bg-emerald-100 text-emerald-700', withdrawn: 'bg-gray-200 text-gray-500' };

interface Props {
  crs: any[];
  sections: any[];
  member: any;
  preFilter?: 'pending' | 'all';
  t: (key: string, fallback?: string) => string;
  getSb: () => any;
  onRefresh: () => void;
}

function exportCSV(crs: any[], t: (k: string, f?: string) => string) {
  const header = `Relatório de Change Requests — Núcleo IA & GP — Gerado em ${new Date().toLocaleDateString('pt-BR')} — Documento interno\n\n`;
  const columns = 'CR,Título,Tipo,Impacto,Status,Submetido por,Submetido em,Revisado por,Revisado em,Aprovado em,Implementado em,Secções,Notas\n';
  const esc = (v: any) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const rows = crs.map(cr => [
    cr.cr_number, cr.title, cr.cr_type, cr.impact_level, cr.status,
    cr.requested_by_name || '', cr.submitted_at ? new Date(cr.submitted_at).toLocaleDateString('pt-BR') : '',
    cr.reviewed_by_name || '', cr.reviewed_at ? new Date(cr.reviewed_at).toLocaleDateString('pt-BR') : '',
    cr.approved_at ? new Date(cr.approved_at).toLocaleDateString('pt-BR') : '',
    cr.implemented_at ? new Date(cr.implemented_at).toLocaleDateString('pt-BR') : '',
    (cr.manual_section_ids || []).length,
    cr.review_notes || '',
  ].map(esc).join(',')).join('\n');

  const blob = new Blob([header + columns + rows], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `change_requests_${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

export default function GovernanceCRTable({ crs, sections, member, preFilter = 'all', t, getSb, onRefresh }: Props) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [statusFilter, setStatusFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [impactFilter, setImpactFilter] = useState('');
  const [selectedCr, setSelectedCr] = useState<any>(null);
  const [showBatch, setShowBatch] = useState(false);
  const [quickLoading, setQuickLoading] = useState<string | null>(null);

  const isGP = member?.is_superadmin || member?.operational_role === 'manager' || (member?.designations || []).includes('deputy_manager');
  const canReview = isGP || (member?.designations || []).includes('curator') || ['sponsor', 'chapter_liaison'].includes(member?.operational_role);

  // Apply pre-filter + manual filters
  let filtered = crs;
  if (preFilter === 'pending') {
    filtered = filtered.filter(cr => ['submitted', 'under_review'].includes(cr.status));
  }
  if (statusFilter) filtered = filtered.filter(cr => cr.status === statusFilter);
  if (typeFilter) filtered = filtered.filter(cr => cr.cr_type === typeFilter);
  if (impactFilter) filtered = filtered.filter(cr => cr.impact_level === impactFilter);

  const allIds = filtered.map(cr => cr.id);
  const allSelected = allIds.length > 0 && allIds.every(id => selected.has(id));

  const toggleAll = () => {
    if (allSelected) {
      setSelected(new Set());
    } else {
      setSelected(new Set(allIds));
    }
  };

  const toggleOne = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id); else next.add(id);
    setSelected(next);
  };

  const handleQuickApprove = async (cr: any, e: React.MouseEvent) => {
    e.stopPropagation();
    setQuickLoading(cr.id);
    try {
      const sb = getSb();
      const { data, error } = await sb.rpc('review_change_request', {
        p_cr_id: cr.id, p_action: 'approve', p_notes: null,
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      (window as any).toast?.(`${cr.cr_number} ${t('governance.status_approved', 'aprovada')}`, 'success');
      onRefresh();
    } catch (err: any) {
      (window as any).toast?.(err.message || 'Erro', 'error');
    } finally {
      setQuickLoading(null);
    }
  };

  const badge = (val: string, colors: Record<string, string>, prefix: string) => (
    <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold whitespace-nowrap ${colors[val] || 'bg-gray-100 text-gray-600'}`}>
      {t(`governance.${prefix}_${val}`, val)}
    </span>
  );

  const selectedCRs = filtered.filter(cr => selected.has(cr.id));

  return (
    <div className="space-y-3">
      {/* Action bar */}
      <div className="flex flex-wrap items-center gap-2">
        {selected.size > 0 && (
          <>
            <button onClick={() => setShowBatch(true)}
              className="px-3 py-1.5 rounded-lg bg-green-600 text-white text-xs font-semibold cursor-pointer border-0 hover:bg-green-700">
              {t('governance.approve_selected', 'Aprovar Seleccionadas')} ({selected.size})
            </button>
            <button onClick={() => exportCSV(selectedCRs, t)}
              className="px-3 py-1.5 rounded-lg border border-[var(--border-default)] text-xs font-semibold text-[var(--text-secondary)] cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]">
              {t('governance.export_csv', 'Exportar CSV')}
            </button>
          </>
        )}

        {/* Filters (only for 'all' mode) */}
        {preFilter === 'all' && (
          <div className="flex flex-wrap gap-2 ml-auto">
            <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
              className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-xs text-[var(--text-primary)]">
              <option value="">Status: {t('governance.all_crs_section', 'Todos')}</option>
              {['draft', 'submitted', 'under_review', 'approved', 'rejected', 'implemented', 'withdrawn'].map(s => (
                <option key={s} value={s}>{t(`governance.status_${s}`, s)}</option>
              ))}
            </select>
            <select value={typeFilter} onChange={e => setTypeFilter(e.target.value)}
              className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-xs text-[var(--text-primary)]">
              <option value="">{t('governance.cr_type', 'Tipo')}: Todos</option>
              {['editorial', 'operational', 'structural', 'emergency'].map(s => (
                <option key={s} value={s}>{t(`governance.type_${s}`, s)}</option>
              ))}
            </select>
            <select value={impactFilter} onChange={e => setImpactFilter(e.target.value)}
              className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-xs text-[var(--text-primary)]">
              <option value="">{t('governance.cr_impact', 'Impacto')}: Todos</option>
              {['low', 'medium', 'high', 'critical'].map(s => (
                <option key={s} value={s}>{t(`governance.impact_${s}`, s)}</option>
              ))}
            </select>
          </div>
        )}
      </div>

      {/* Table */}
      {filtered.length === 0 ? (
        <div className="text-center py-10 text-[var(--text-muted)] text-sm">{t('governance.no_crs', 'Nenhuma CR.')}</div>
      ) : (
        <div className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-[var(--surface-section-cool)] text-[10px] font-bold text-[var(--text-secondary)] uppercase">
                  <th className="px-3 py-2.5 text-center w-10">
                    <input type="checkbox" checked={allSelected} onChange={toggleAll}
                      className="w-3.5 h-3.5 cursor-pointer accent-navy" />
                  </th>
                  <th className="px-3 py-2.5 text-left">{t('governance.cr_number', 'CR#')}</th>
                  <th className="px-3 py-2.5 text-left">{t('governance.cr_title', 'Título')}</th>
                  <th className="px-3 py-2.5 text-center">{t('governance.cr_type', 'Tipo')}</th>
                  <th className="px-3 py-2.5 text-center">{t('governance.cr_impact', 'Impacto')}</th>
                  <th className="px-3 py-2.5 text-center">{t('governance.cr_status', 'Status')}</th>
                  <th className="px-3 py-2.5 text-center">{t('governance.cr_submitted', 'Submetida em')}</th>
                  {canReview && <th className="px-3 py-2.5 text-center w-10">⚡</th>}
                </tr>
              </thead>
              <tbody>
                {filtered.map(cr => {
                  const canQuickApprove = canReview && ['draft', 'submitted', 'under_review'].includes(cr.status);
                  return (
                    <tr key={cr.id}
                      onClick={() => setSelectedCr(cr)}
                      className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)] cursor-pointer transition-colors">
                      <td className="px-3 py-2.5 text-center" onClick={e => e.stopPropagation()}>
                        <input type="checkbox" checked={selected.has(cr.id)}
                          onChange={() => toggleOne(cr.id)}
                          className="w-3.5 h-3.5 cursor-pointer accent-navy" />
                      </td>
                      <td className="px-3 py-2.5 font-bold text-navy whitespace-nowrap">{cr.cr_number}</td>
                      <td className="px-3 py-2.5 text-[var(--text-primary)] max-w-[200px] truncate">{cr.title}</td>
                      <td className="px-3 py-2.5 text-center">{cr.cr_type && badge(cr.cr_type, TYPE_COLORS, 'type')}</td>
                      <td className="px-3 py-2.5 text-center">{cr.impact_level && badge(cr.impact_level, IMPACT_COLORS, 'impact')}</td>
                      <td className="px-3 py-2.5 text-center">{cr.status && badge(cr.status, STATUS_COLORS, 'status')}</td>
                      <td className="px-3 py-2.5 text-center text-xs text-[var(--text-muted)] whitespace-nowrap">
                        {cr.submitted_at ? new Date(cr.submitted_at).toLocaleDateString('pt-BR') : cr.created_at ? new Date(cr.created_at).toLocaleDateString('pt-BR') : '—'}
                      </td>
                      {canReview && (
                        <td className="px-3 py-2.5 text-center" onClick={e => e.stopPropagation()}>
                          {canQuickApprove && (
                            <button onClick={e => handleQuickApprove(cr, e)}
                              disabled={quickLoading === cr.id}
                              title={t('governance.quick_approve', 'Aprovar')}
                              className="w-7 h-7 rounded-lg bg-green-100 text-green-700 text-sm font-bold cursor-pointer border-0 hover:bg-green-200 disabled:opacity-50">
                              {quickLoading === cr.id ? '…' : '✓'}
                            </button>
                          )}
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* CR Detail modal */}
      {selectedCr && (
        <CRDetail cr={selectedCr} sections={sections} canReview={canReview} member={member} t={t} getSb={getSb}
          onClose={() => setSelectedCr(null)} onReload={() => { onRefresh(); setSelectedCr(null); }} />
      )}

      {/* Batch modal */}
      {showBatch && selectedCRs.length > 0 && (
        <GovernanceBatchModal selectedCRs={selectedCRs} t={t} getSb={getSb}
          onClose={() => setShowBatch(false)}
          onDone={() => { setSelected(new Set()); onRefresh(); }} />
      )}
    </div>
  );
}
