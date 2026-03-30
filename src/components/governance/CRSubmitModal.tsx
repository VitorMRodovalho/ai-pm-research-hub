import { useState } from 'react';

interface Props {
  sections: any[];
  t: (key: string, fallback?: string) => string;
  getSb: () => any;
  onClose: () => void;
  onReload: () => void;
}

export default function CRSubmitModal({ sections, t, getSb, onClose, onReload }: Props) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [crType, setCrType] = useState('operational');
  const [impactLevel, setImpactLevel] = useState('medium');
  const [impactDescription, setImpactDescription] = useState('');
  const [justification, setJustification] = useState('');
  const [selectedSections, setSelectedSections] = useState<string[]>([]);
  const [gcRefs, setGcRefs] = useState('');
  const [saving, setSaving] = useState(false);

  const toggleSection = (id: string) => {
    setSelectedSections(prev => prev.includes(id) ? prev.filter(s => s !== id) : [...prev, id]);
  };

  const handleSubmit = async () => {
    if (!title.trim() || !description.trim()) {
      (window as any).toast?.('Título e descrição são obrigatórios.', 'error');
      return;
    }
    setSaving(true);
    try {
      const sb = getSb();
      const { data, error } = await sb.rpc('submit_change_request', {
        p_title: title.trim(),
        p_description: description.trim(),
        p_cr_type: crType,
        p_manual_section_ids: selectedSections.length > 0 ? selectedSections : null,
        p_gc_references: gcRefs.trim() ? gcRefs.split(',').map((s: string) => s.trim()) : null,
        p_impact_level: impactLevel,
        p_impact_description: impactDescription.trim() || null,
        p_justification: justification.trim() || null,
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      try { if ((window as any).posthog) (window as any).posthog.capture('governance_cr_submitted', { cr_type: crType, impact_level: impactLevel }); } catch {}
      (window as any).toast?.(t('governance.cr_submitted_success', 'CR submetida com sucesso!'), 'success');
      onReload();
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro ao submeter', 'error');
    } finally {
      setSaving(false);
    }
  };

  const topSections = sections.filter((s: any) => !s.parent_section_id).sort((a: any, b: any) => a.sort_order - b.sort_order);

  const inputCls = "w-full px-3 py-2 text-sm rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-navy/30";

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 backdrop-blur-sm p-4" onClick={onClose}>
      <div className="bg-[var(--surface-elevated)] rounded-2xl border border-[var(--border-default)] shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}>
        <div className="px-5 py-4 border-b border-[var(--border-default)] flex items-center justify-between">
          <h3 className="text-base font-bold text-navy">📋 {t('governance.cr_new', 'Nova Solicitação')}</h3>
          <button onClick={onClose} className="text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer border-0 bg-transparent text-xl">✕</button>
        </div>

        <div className="px-5 py-4 space-y-4">
          <div>
            <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_title', 'Título')} *</label>
            <input type="text" value={title} onChange={e => setTitle(e.target.value)} required className={inputCls} />
          </div>

          <div>
            <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_description', 'Descrição')} *</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={3} className={inputCls + ' resize-y'} />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_type', 'Tipo')}</label>
              <select value={crType} onChange={e => setCrType(e.target.value)} className={inputCls}>
                <option value="editorial">{t('governance.type_editorial', 'Editorial')}</option>
                <option value="operational">{t('governance.type_operational', 'Operacional')}</option>
                <option value="structural">{t('governance.type_structural', 'Estrutural')}</option>
                <option value="emergency">{t('governance.type_emergency', 'Emergência')}</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_impact', 'Impacto')}</label>
              <select value={impactLevel} onChange={e => setImpactLevel(e.target.value)} className={inputCls}>
                <option value="low">{t('governance.impact_low', 'Baixo')}</option>
                <option value="medium">{t('governance.impact_medium', 'Médio')}</option>
                <option value="high">{t('governance.impact_high', 'Alto')}</option>
                <option value="critical">{t('governance.impact_critical', 'Crítico')}</option>
              </select>
            </div>
          </div>

          <div>
            <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_impact_description', 'Descrição do Impacto')}</label>
            <textarea value={impactDescription} onChange={e => setImpactDescription(e.target.value)} rows={2} className={inputCls + ' resize-y'} />
          </div>

          <div>
            <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_justification', 'Justificativa PMBOK')}</label>
            <textarea value={justification} onChange={e => setJustification(e.target.value)} rows={2} className={inputCls + ' resize-y'} />
          </div>

          <div>
            <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_manual_sections', 'Secções do Manual')}</label>
            <div className="max-h-[150px] overflow-y-auto border border-[var(--border-default)] rounded-lg p-2 space-y-1">
              {topSections.map((s: any) => (
                <label key={s.id} className="flex items-center gap-2 text-xs cursor-pointer hover:bg-[var(--surface-hover)] px-1 py-0.5 rounded">
                  <input type="checkbox" checked={selectedSections.includes(s.id)} onChange={() => toggleSection(s.id)} className="accent-navy" />
                  <span className="font-bold text-navy">§{s.section_number}</span>
                  <span className="text-[var(--text-secondary)] truncate">{s.title_pt}</span>
                </label>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-bold text-navy mb-1">{t('governance.cr_gc_refs', 'Referências GC')} (separadas por vírgula)</label>
            <input type="text" value={gcRefs} onChange={e => setGcRefs(e.target.value)} placeholder="GC-103, GC-116" className={inputCls} />
          </div>
        </div>

        <div className="flex items-center justify-end gap-2 px-5 py-3 border-t border-[var(--border-default)]">
          <button onClick={onClose} className="px-4 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-secondary)] text-sm font-semibold cursor-pointer">
            {t('governance.cancel', 'Cancelar')}
          </button>
          <button onClick={handleSubmit} disabled={saving}
            className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold cursor-pointer border-0 hover:opacity-90 disabled:opacity-50">
            {saving ? '...' : t('governance.save', 'Submeter')}
          </button>
        </div>
      </div>
    </div>
  );
}
