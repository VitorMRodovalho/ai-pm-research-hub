import { useState } from 'react';
import CRDetail from './CRDetail';
import CRSubmitModal from './CRSubmitModal';

const TYPE_COLORS: Record<string, string> = {
  editorial: 'bg-gray-100 text-gray-700',
  operational: 'bg-blue-100 text-blue-700',
  structural: 'bg-amber-100 text-amber-700',
  emergency: 'bg-red-100 text-red-700',
};

const STATUS_COLORS: Record<string, string> = {
  draft: 'bg-gray-100 text-gray-600',
  submitted: 'bg-blue-100 text-blue-700',
  under_review: 'bg-yellow-100 text-yellow-700',
  approved: 'bg-green-100 text-green-700',
  rejected: 'bg-red-100 text-red-700',
  implemented: 'bg-emerald-100 text-emerald-700',
};

const IMPACT_COLORS: Record<string, string> = {
  low: 'bg-gray-100 text-gray-600',
  medium: 'bg-blue-100 text-blue-700',
  high: 'bg-amber-100 text-amber-700',
  critical: 'bg-red-100 text-red-700',
};

interface Props {
  crs: any[];
  sections: any[];
  member: any;
  canSubmit: boolean;
  canReview: boolean;
  t: (key: string, fallback?: string) => string;
  getSb: () => any;
  onReload: () => void;
}

export default function CRList({ crs, sections, member, canSubmit, canReview, t, getSb, onReload }: Props) {
  const [statusFilter, setStatusFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [impactFilter, setImpactFilter] = useState('');
  const [selectedCr, setSelectedCr] = useState<any>(null);
  const [showSubmit, setShowSubmit] = useState(false);

  const filtered = crs.filter(cr => {
    if (statusFilter && cr.status !== statusFilter) return false;
    if (typeFilter && cr.cr_type !== typeFilter) return false;
    if (impactFilter && cr.impact_level !== impactFilter) return false;
    return true;
  });

  const badge = (value: string, colors: Record<string, string>, prefix: string) => {
    const label = t(`governance.${prefix}_${value}`, value);
    const cls = colors[value] || 'bg-gray-100 text-gray-600';
    return <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${cls}`}>{label}</span>;
  };

  return (
    <div className="space-y-4">
      {/* New CR button */}
      {canSubmit && (
        <div className="flex justify-end">
          <button onClick={() => setShowSubmit(true)}
            className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold cursor-pointer border-0 hover:opacity-90">
            + {t('governance.cr_new', 'Nova Solicitação')}
          </button>
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap gap-3 items-center">
        <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)]">
          <option value="">{t('governance.cr_status', 'Status')}: Todos</option>
          {['draft','submitted','under_review','approved','rejected','implemented'].map(s => (
            <option key={s} value={s}>{t(`governance.status_${s}`, s)}</option>
          ))}
        </select>
        <select value={typeFilter} onChange={e => setTypeFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)]">
          <option value="">{t('governance.cr_type', 'Tipo')}: Todos</option>
          {['editorial','operational','structural','emergency'].map(s => (
            <option key={s} value={s}>{t(`governance.type_${s}`, s)}</option>
          ))}
        </select>
        <select value={impactFilter} onChange={e => setImpactFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)]">
          <option value="">{t('governance.cr_impact', 'Impacto')}: Todos</option>
          {['low','medium','high','critical'].map(s => (
            <option key={s} value={s}>{t(`governance.impact_${s}`, s)}</option>
          ))}
        </select>
      </div>

      {/* CR table */}
      {filtered.length === 0 ? (
        <div className="text-center py-12 text-[var(--text-muted)] text-sm">{t('governance.no_crs', 'Nenhuma CR.')}</div>
      ) : (
        <div className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-[var(--surface-section-cool)] text-[10px] font-bold text-[var(--text-secondary)] uppercase">
                  <th className="px-4 py-2.5 text-left">{t('governance.cr_number', 'Nº')}</th>
                  <th className="px-4 py-2.5 text-left">{t('governance.cr_title', 'Título')}</th>
                  <th className="px-4 py-2.5 text-center">{t('governance.cr_type', 'Tipo')}</th>
                  <th className="px-4 py-2.5 text-center">{t('governance.cr_status', 'Status')}</th>
                  <th className="px-4 py-2.5 text-center">{t('governance.cr_impact', 'Impacto')}</th>
                  <th className="px-4 py-2.5 text-center">{t('governance.cr_sections', 'Secções')}</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((cr: any) => (
                  <tr key={cr.id} onClick={() => setSelectedCr(cr)}
                    className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)] cursor-pointer transition-colors">
                    <td className="px-4 py-2.5 font-bold text-navy whitespace-nowrap">{cr.cr_number}</td>
                    <td className="px-4 py-2.5 text-[var(--text-primary)]">{cr.title}</td>
                    <td className="px-4 py-2.5 text-center">{cr.cr_type && badge(cr.cr_type, TYPE_COLORS, 'type')}</td>
                    <td className="px-4 py-2.5 text-center">{cr.status && badge(cr.status, STATUS_COLORS, 'status')}</td>
                    <td className="px-4 py-2.5 text-center">{cr.impact_level && badge(cr.impact_level, IMPACT_COLORS, 'impact')}</td>
                    <td className="px-4 py-2.5 text-center text-xs text-[var(--text-muted)]">{cr.manual_section_ids?.length || 0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* CR Detail drawer */}
      {selectedCr && (
        <CRDetail cr={selectedCr} sections={sections} canReview={canReview} member={member} t={t} getSb={getSb}
          onClose={() => setSelectedCr(null)} onReload={() => { onReload(); setSelectedCr(null); }} />
      )}

      {/* Submit modal */}
      {showSubmit && (
        <CRSubmitModal sections={sections} t={t} getSb={getSb}
          onClose={() => setShowSubmit(false)} onReload={() => { onReload(); setShowSubmit(false); }} />
      )}
    </div>
  );
}
