import { useState } from 'react';

interface Props {
  cr: any;
  sections: any[];
  canReview: boolean;
  member: any;
  t: (key: string, fallback?: string) => string;
  getSb: () => any;
  onClose: () => void;
  onReload: () => void;
}

const TYPE_COLORS: Record<string, string> = { editorial: 'bg-gray-100 text-gray-700', operational: 'bg-blue-100 text-blue-700', structural: 'bg-amber-100 text-amber-700', emergency: 'bg-red-100 text-red-700' };
const IMPACT_COLORS: Record<string, string> = { low: 'bg-gray-100 text-gray-600', medium: 'bg-blue-100 text-blue-700', high: 'bg-amber-100 text-amber-700', critical: 'bg-red-100 text-red-700' };
const STATUS_COLORS: Record<string, string> = { draft: 'bg-gray-100 text-gray-600', submitted: 'bg-blue-100 text-blue-700', under_review: 'bg-yellow-100 text-yellow-700', approved: 'bg-green-100 text-green-700', rejected: 'bg-red-100 text-red-700', implemented: 'bg-emerald-100 text-emerald-700', withdrawn: 'bg-gray-200 text-gray-500' };

export default function CRDetail({ cr, sections, canReview, member, t, getSb, onClose, onReload }: Props) {
  const [notes, setNotes] = useState('');
  const [loading, setLoading] = useState(false);

  const isGP = member?.is_superadmin || member?.operational_role === 'manager' || (member?.designations || []).includes('deputy_manager');
  const canApprove = canReview && ['draft', 'submitted', 'under_review'].includes(cr.status);
  const canImplement = isGP && cr.status === 'approved';
  const canWithdraw = isGP && ['draft', 'submitted', 'under_review'].includes(cr.status);
  const canResubmit = cr.status === 'under_review';

  const handleAction = async (action: string) => {
    if ((action === 'reject' || action === 'request_changes') && !notes.trim()) {
      (window as any).toast?.(t('governance.cr_review_notes_required', 'Notas obrigatórias'), 'error');
      return;
    }
    setLoading(true);
    try {
      const sb = getSb();
      const { data, error } = await sb.rpc('review_change_request', {
        p_cr_id: cr.id, p_action: action, p_notes: notes.trim() || null,
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      (window as any).toast?.(t('governance.cr_reviewed_success', 'CR atualizada.'), 'success');
      onReload();
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro', 'error');
    } finally {
      setLoading(false);
    }
  };

  const linkedSections = (cr.manual_section_ids || [])
    .map((id: string) => sections.find((s: any) => s.id === id))
    .filter(Boolean);

  const badge = (val: string, colors: Record<string, string>, prefix: string) => (
    <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${colors[val] || 'bg-gray-100 text-gray-600'}`}>
      {t(`governance.${prefix}_${val}`, val)}
    </span>
  );

  const infoRow = (label: string, content: string | null | undefined) => {
    if (!content) return null;
    return (
      <div className="mb-3">
        <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-1">{label}</div>
        <div className="text-sm text-[var(--text-primary)] whitespace-pre-wrap">{content}</div>
      </div>
    );
  };

  return (
    <div className="fixed inset-0 z-[9998] flex items-center justify-center bg-black/50 backdrop-blur-sm p-4" onClick={onClose}>
      <div className="bg-[var(--surface-elevated)] rounded-2xl border border-[var(--border-default)] shadow-2xl w-full max-w-xl max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}>
        <div className="px-5 py-4 border-b border-[var(--border-default)] flex items-center justify-between">
          <div>
            <div className="flex items-center gap-2">
              <span className="text-base font-bold text-navy">{cr.cr_number}</span>
              {cr.cr_type && badge(cr.cr_type, TYPE_COLORS, 'type')}
              {cr.impact_level && badge(cr.impact_level, IMPACT_COLORS, 'impact')}
              {cr.status && badge(cr.status, STATUS_COLORS, 'status')}
            </div>
            <h3 className="text-sm font-bold text-[var(--text-primary)] mt-1">{cr.title}</h3>
          </div>
          <button onClick={onClose} className="text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer border-0 bg-transparent text-xl">✕</button>
        </div>

        <div className="px-5 py-4 space-y-1">
          {cr.requested_by_name && (
            <p className="text-xs text-[var(--text-muted)]">Solicitado por: {cr.requested_by_name}</p>
          )}
          {cr.created_at && (
            <p className="text-xs text-[var(--text-muted)]">{new Date(cr.created_at).toLocaleDateString('pt-BR')}</p>
          )}
          <div className="pt-2">
            {infoRow(t('governance.cr_description', 'Descrição'), cr.description)}
            {infoRow(t('governance.cr_proposed_changes', 'Mudanças Propostas'), cr.proposed_changes)}
            {infoRow(t('governance.cr_justification', 'Justificativa PMBOK'), cr.justification)}
            {infoRow(t('governance.cr_impact_description', 'Impacto'), cr.impact_description)}

            {linkedSections.length > 0 && (
              <div className="mb-3">
                <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-1">{t('governance.cr_sections', 'Secções Afetadas')}</div>
                <div className="flex flex-wrap gap-1">
                  {linkedSections.map((s: any) => (
                    <span key={s.id} className="px-2 py-0.5 rounded bg-[var(--surface-section-cool)] text-xs font-medium text-[var(--text-secondary)]">
                      §{s.section_number} {s.title_pt}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {cr.gc_references?.length > 0 && infoRow(t('governance.cr_gc_refs', 'Referências GC'), cr.gc_references.join(', '))}
            {cr.review_notes && infoRow(t('governance.cr_review_notes', 'Notas de Revisão'), cr.review_notes)}
          </div>
        </div>

        {/* Review actions */}
        {(canReview || canWithdraw || canResubmit) && (canApprove || canImplement || canWithdraw || canResubmit) && (
          <div className="px-5 py-4 border-t border-[var(--border-default)] space-y-3">
            <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
              placeholder={t('governance.cr_review_notes', 'Notas de revisão...')}
              className="w-full px-3 py-2 text-sm rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] resize-y" />
            <div className="flex gap-2 flex-wrap">
              {canApprove && (
                <>
                  <button onClick={() => handleAction('approve')} disabled={loading}
                    className="px-3 py-1.5 rounded-lg bg-green-600 text-white text-xs font-semibold cursor-pointer border-0 disabled:opacity-50">
                    {t('governance.cr_approve', 'Aprovar')}
                  </button>
                  <button onClick={() => handleAction('reject')} disabled={loading}
                    className="px-3 py-1.5 rounded-lg bg-red-600 text-white text-xs font-semibold cursor-pointer border-0 disabled:opacity-50">
                    {t('governance.cr_reject', 'Rejeitar')}
                  </button>
                  <button onClick={() => handleAction('request_changes')} disabled={loading}
                    className="px-3 py-1.5 rounded-lg bg-amber-500 text-white text-xs font-semibold cursor-pointer border-0 disabled:opacity-50">
                    {t('governance.cr_request_changes', 'Pedir Ajustes')}
                  </button>
                </>
              )}
              {canImplement && (
                <button onClick={() => handleAction('implement')} disabled={loading}
                  className="px-3 py-1.5 rounded-lg bg-emerald-600 text-white text-xs font-semibold cursor-pointer border-0 disabled:opacity-50">
                  {t('governance.cr_implement', 'Implementar')}
                </button>
              )}
              {canWithdraw && (
                <button onClick={() => { if (confirm(t('governance.withdraw_confirm', 'Retirar esta CR?'))) handleAction('withdraw'); }} disabled={loading}
                  className="px-3 py-1.5 rounded-lg bg-gray-500 text-white text-xs font-semibold cursor-pointer border-0 disabled:opacity-50">
                  {t('governance.withdraw', 'Retirar')}
                </button>
              )}
              {canResubmit && (
                <button onClick={() => handleAction('resubmit')} disabled={loading}
                  className="px-3 py-1.5 rounded-lg bg-blue-500 text-white text-xs font-semibold cursor-pointer border-0 disabled:opacity-50">
                  {t('governance.resubmit', 'Re-submeter')}
                </button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
