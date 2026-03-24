import { useEffect, useState, useCallback } from 'react';

interface Partner {
  id: string;
  name: string;
  entity_type: string;
  status: string;
  contact_name: string | null;
  contact_email: string | null;
  chapter: string | null;
  partnership_date: string | null;
  notes: string | null;
  next_action: string | null;
  follow_up_date: string | null;
  last_interaction_at: string | null;
  days_in_stage: number;
  updated_at: string;
}

interface Interaction {
  id: string;
  interaction_type: string;
  summary: string;
  details: string | null;
  outcome: string | null;
  next_action: string | null;
  follow_up_date: string | null;
  actor_name: string | null;
  created_at: string;
}

interface StalePartner {
  id: string;
  name: string;
  status: string;
  days_stale: number;
}

interface PipelineData {
  pipeline: Partner[];
  by_status: Record<string, number>;
  by_type: Record<string, number>;
  total: number;
  active: number;
  stale: StalePartner[];
}

const COLUMNS = ['prospect', 'contact', 'negotiation', 'active', 'inactive'] as const;

const COL_LABELS: Record<string, Record<string, string>> = {
  'pt-BR': { prospect: 'Prospect', contact: 'Contato', negotiation: 'Negociação', active: 'Ativo', inactive: 'Inativo' },
  'en-US': { prospect: 'Prospect', contact: 'Contact', negotiation: 'Negotiation', active: 'Active', inactive: 'Inactive' },
  'es-LATAM': { prospect: 'Prospecto', contact: 'Contacto', negotiation: 'Negociación', active: 'Activo', inactive: 'Inactivo' },
};

const COL_COLORS: Record<string, string> = {
  prospect: 'border-amber-300 bg-amber-50',
  contact: 'border-blue-300 bg-blue-50',
  negotiation: 'border-purple-300 bg-purple-50',
  active: 'border-emerald-300 bg-emerald-50',
  inactive: 'border-gray-300 bg-gray-50',
};

const COL_HEADER_COLORS: Record<string, string> = {
  prospect: 'bg-amber-100 text-amber-800',
  contact: 'bg-blue-100 text-blue-800',
  negotiation: 'bg-purple-100 text-purple-800',
  active: 'bg-emerald-100 text-emerald-800',
  inactive: 'bg-gray-100 text-gray-600',
};

const TYPE_LABELS: Record<string, string> = {
  pmi_chapter: 'PMI Chapter', academia: 'Academia', academic: 'Academic',
  governo: 'Governo', empresa: 'Empresa', outro: 'Outro',
  community: 'Community', research: 'Research', association: 'Association',
};

const NEXT_STATUS: Record<string, string> = {
  prospect: 'contact', contact: 'negotiation', negotiation: 'active',
};

const IX_ICONS: Record<string, string> = {
  email: '📧', whatsapp: '📱', linkedin: '💬', call: '📞', meeting: '🤝', note: '📝', status_change: '🔄',
};

const LABELS: Record<string, Record<string, string>> = {
  'pt-BR': {
    title: 'Pipeline de Parcerias',
    subtitle: 'Visualização Kanban do funil de parcerias',
    addPartner: '+ Nova Parceria',
    staleAlert: 'parceria(s) sem atualização há 30+ dias',
    advance: 'Avançar Status',
    edit: 'Editar',
    archive: 'Arquivar',
    daysInStage: 'dias neste estágio',
    detailTitle: 'Detalhes da Parceria',
    contact: 'Contato',
    email: 'E-mail',
    chapter: 'Capítulo',
    partnershipDate: 'Data de Parceria',
    notes: 'Observações',
    close: 'Fechar',
    advanceConfirm: 'Confirmar avanço para',
    advanceNote: 'Nota (opcional)',
    confirm: 'Confirmar',
    cancel: 'Cancelar',
    loading: 'Carregando pipeline...',
    total: 'Total',
    activeCount: 'Ativos',
    nextAction: 'Próximo passo',
    followUp: 'Follow-up',
    addInteraction: '+ Registar interação',
    timeline: 'Timeline',
    ixSummary: 'Resumo da interação...',
    ixOutcome: 'Resultado (opcional)',
    ixNext: 'Próximo passo (opcional)',
    register: 'Registar',
    noInteractions: 'Nenhuma interação registada.',
    outcome: 'Resultado',
    daysOverdue: 'd atrasado',
    daysUntil: 'd',
  },
  'en-US': {
    title: 'Partnership Pipeline',
    subtitle: 'Kanban view of partnership funnel',
    addPartner: '+ New Partnership',
    staleAlert: 'partnership(s) with no update in 30+ days',
    advance: 'Advance Status',
    edit: 'Edit',
    archive: 'Archive',
    daysInStage: 'days in this stage',
    detailTitle: 'Partnership Details',
    contact: 'Contact',
    email: 'Email',
    chapter: 'Chapter',
    partnershipDate: 'Partnership Date',
    notes: 'Notes',
    close: 'Close',
    advanceConfirm: 'Confirm advance to',
    advanceNote: 'Note (optional)',
    confirm: 'Confirm',
    cancel: 'Cancel',
    loading: 'Loading pipeline...',
    total: 'Total',
    activeCount: 'Active',
    nextAction: 'Next action',
    followUp: 'Follow-up',
    addInteraction: '+ Log interaction',
    timeline: 'Timeline',
    ixSummary: 'Interaction summary...',
    ixOutcome: 'Outcome (optional)',
    ixNext: 'Next action (optional)',
    register: 'Log',
    noInteractions: 'No interactions logged.',
    outcome: 'Outcome',
    daysOverdue: 'd overdue',
    daysUntil: 'd',
  },
  'es-LATAM': {
    title: 'Pipeline de Alianzas',
    subtitle: 'Vista Kanban del embudo de alianzas',
    addPartner: '+ Nueva Alianza',
    staleAlert: 'alianza(s) sin actualización en 30+ días',
    advance: 'Avanzar Estado',
    edit: 'Editar',
    archive: 'Archivar',
    daysInStage: 'días en esta etapa',
    detailTitle: 'Detalles de la Alianza',
    contact: 'Contacto',
    email: 'Correo',
    chapter: 'Capítulo',
    partnershipDate: 'Fecha de Alianza',
    notes: 'Notas',
    close: 'Cerrar',
    advanceConfirm: 'Confirmar avance a',
    advanceNote: 'Nota (opcional)',
    confirm: 'Confirmar',
    cancel: 'Cancelar',
    loading: 'Cargando pipeline...',
    total: 'Total',
    activeCount: 'Activos',
    nextAction: 'Próximo paso',
    followUp: 'Seguimiento',
    addInteraction: '+ Registrar interacción',
    timeline: 'Línea de tiempo',
    ixSummary: 'Resumen de la interacción...',
    ixOutcome: 'Resultado (opcional)',
    ixNext: 'Próximo paso (opcional)',
    register: 'Registrar',
    noInteractions: 'Sin interacciones registradas.',
    outcome: 'Resultado',
    daysOverdue: 'd vencido',
    daysUntil: 'd',
  },
};

export default function PartnerPipelineIsland({ lang = 'pt-BR' }: { lang?: string }) {
  const [data, setData] = useState<PipelineData | null>(null);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Partner | null>(null);
  const [interactions, setInteractions] = useState<Interaction[]>([]);
  const [ixLoading, setIxLoading] = useState(false);
  const [showIxForm, setShowIxForm] = useState(false);
  const [ixType, setIxType] = useState('email');
  const [ixSummary, setIxSummary] = useState('');
  const [ixOutcome, setIxOutcome] = useState('');
  const [ixNext, setIxNext] = useState('');
  const [ixFollowUp, setIxFollowUp] = useState('');
  const [advancingId, setAdvancingId] = useState<string | null>(null);
  const [advanceNote, setAdvanceNote] = useState('');
  const l = LABELS[lang] || LABELS['pt-BR'];
  const cl = COL_LABELS[lang] || COL_LABELS['pt-BR'];

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const loadPipeline = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(loadPipeline, 300); return; }
    try {
      const { data: d, error } = await sb.rpc('get_partner_pipeline');
      if (!error && d) setData(d);
    } catch {}
    setLoading(false);
  }, [getSb]);

  useEffect(() => { loadPipeline(); }, [loadPipeline]);

  const loadInteractions = useCallback(async (partnerId: string) => {
    const sb = getSb();
    if (!sb) return;
    setIxLoading(true);
    try {
      const { data: d } = await sb.rpc('get_partner_interactions', { p_partner_id: partnerId });
      if (d?.interactions) setInteractions(d.interactions);
      else setInteractions([]);
    } catch { setInteractions([]); }
    setIxLoading(false);
  }, [getSb]);

  const openDetail = useCallback((partner: Partner) => {
    setSelected(partner);
    setInteractions([]);
    setShowIxForm(false);
    setIxSummary(''); setIxOutcome(''); setIxNext(''); setIxFollowUp(''); setIxType('email');
    loadInteractions(partner.id);
  }, [loadInteractions]);

  const handleAddInteraction = useCallback(async () => {
    if (!selected || !ixSummary.trim()) {
      (window as any).toast?.('Resumo obrigatório.', 'error');
      return;
    }
    const sb = getSb();
    if (!sb) return;
    try {
      const { data: result, error } = await sb.rpc('add_partner_interaction', {
        p_partner_id: selected.id,
        p_interaction_type: ixType,
        p_summary: ixSummary.trim(),
        p_details: null,
        p_outcome: ixOutcome.trim() || null,
        p_next_action: ixNext.trim() || null,
        p_follow_up_date: ixFollowUp || null,
      });
      if (error || !result?.success) {
        (window as any).toast?.(result?.error || 'Erro ao registar.', 'error');
        return;
      }
      (window as any).toast?.('Interação registada!', 'success');
      setIxSummary(''); setIxOutcome(''); setIxNext(''); setIxFollowUp('');
      setShowIxForm(false);
      loadInteractions(selected.id);
      loadPipeline(); // refresh cards
    } catch {
      (window as any).toast?.('Erro inesperado.', 'error');
    }
  }, [selected, ixType, ixSummary, ixOutcome, ixNext, ixFollowUp, getSb, loadInteractions, loadPipeline]);

  const handleAdvance = async (partner: Partner) => {
    const nextStatus = NEXT_STATUS[partner.status];
    if (!nextStatus) return;
    setAdvancingId(partner.id);
    setAdvanceNote('');
  };

  const confirmAdvance = async () => {
    if (!advancingId || !data) return;
    const partner = data.pipeline.find(p => p.id === advancingId);
    if (!partner) return;
    const nextStatus = NEXT_STATUS[partner.status];
    if (!nextStatus) return;

    const sb = getSb();
    if (!sb) return;

    try {
      const { data: result, error } = await sb.rpc('admin_update_partner_status', {
        p_partner_id: advancingId,
        p_new_status: nextStatus,
        p_notes: advanceNote || null,
      });
      if (error) {
        (window as any).toast?.('Erro ao avançar status.', 'error');
        return;
      }
      if (result && !result.success) {
        (window as any).toast?.(result.error || 'Erro', 'error');
        return;
      }
      (window as any).toast?.('Status atualizado!', 'success');
      setAdvancingId(null);
      setSelected(null);
      setLoading(true);
      await loadPipeline();
    } catch {
      (window as any).toast?.('Erro inesperado.', 'error');
    }
  };

  const handleArchive = async (partner: Partner) => {
    if (!confirm('Arquivar esta parceria?')) return;
    const sb = getSb();
    if (!sb) return;
    try {
      await sb.rpc('admin_update_partner_status', {
        p_partner_id: partner.id,
        p_new_status: 'inactive',
        p_notes: 'Arquivado via pipeline',
      });
      (window as any).toast?.('Parceria arquivada.', 'success');
      setSelected(null);
      setLoading(true);
      await loadPipeline();
    } catch {}
  };

  if (loading) return <div className="text-center py-12 text-[var(--text-muted)]">{l.loading}</div>;
  if (!data) return null;

  const staleIds = new Set((data.stale || []).map(s => s.id));

  return (
    <div className="space-y-6">
      {/* Header + Stats */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-extrabold text-navy">{l.title}</h1>
          <p className="text-sm text-[var(--text-secondary)]">{l.subtitle}</p>
        </div>
        <div className="flex items-center gap-4">
          <div className="text-xs text-[var(--text-muted)]">
            <span className="font-bold text-[var(--text-primary)]">{data.total}</span> {l.total} &middot;{' '}
            <span className="font-bold text-emerald-600">{data.active}</span> {l.activeCount}
          </div>
        </div>
      </div>

      {/* Stale Alert */}
      {data.stale?.length > 0 && (
        <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 flex items-center gap-2">
          <span className="text-lg">⚠️</span>
          <span className="font-semibold">{data.stale.length}</span> {l.staleAlert}
        </div>
      )}

      {/* Kanban Board */}
      <div className="overflow-x-auto -mx-4 px-4 md:mx-0 md:px-0 md:overflow-visible pipeline-mobile-scroll">
      <div className="grid grid-cols-[repeat(5,minmax(200px,1fr))] md:grid-cols-5 gap-3 min-h-[400px] min-w-[900px] md:min-w-0">
        {COLUMNS.map(status => {
          const partners = (data.pipeline || []).filter(p => p.status === status);
          const count = data.by_status?.[status] || 0;
          return (
            <div key={status} className={`rounded-xl border-2 p-3 ${COL_COLORS[status]} min-h-[200px]`}>
              <div className={`text-xs font-bold uppercase tracking-wide px-2 py-1 rounded-lg mb-3 text-center ${COL_HEADER_COLORS[status]}`}>
                {cl[status]} ({count})
              </div>
              <div className="space-y-2">
                {partners.map(partner => (
                  <div
                    key={partner.id}
                    onClick={() => openDetail(partner)}
                    className="bg-white rounded-lg border border-[var(--border-default)] p-3 cursor-pointer hover:shadow-md transition-shadow"
                  >
                    <div className="font-semibold text-xs text-[var(--text-primary)] truncate">{partner.name}</div>
                    <div className="text-[10px] text-[var(--text-muted)] mt-1">{TYPE_LABELS[partner.entity_type] || partner.entity_type}</div>
                    <div className="flex items-center justify-between mt-2">
                      <span className="text-[10px] text-[var(--text-muted)]">
                        {partner.days_in_stage} {l.daysInStage.split(' ').slice(0, 1).join('')}d
                      </span>
                      {staleIds.has(partner.id) && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700 font-semibold">⚠️ stale</span>
                      )}
                    </div>
                    {partner.contact_name && (
                      <div className="text-[10px] text-[var(--text-muted)] mt-1 truncate">{partner.contact_name}</div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
      </div>

      {/* Detail Modal */}
      {selected && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={(e) => { if (e.target === e.currentTarget) setSelected(null); }}>
          <div className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] shadow-xl w-full max-w-2xl p-5 mx-4 max-h-[85vh] overflow-y-auto">
            <h2 className="text-lg font-extrabold text-navy mb-4">{l.detailTitle}</h2>
            <div className="space-y-3">
              <div>
                <div className="font-bold text-sm text-[var(--text-primary)]">{selected.name}</div>
                <div className="text-xs text-[var(--text-muted)]">{TYPE_LABELS[selected.entity_type] || selected.entity_type}</div>
              </div>
              <div className="flex items-center gap-2">
                <span className={`text-[10px] px-2 py-0.5 rounded-full font-semibold ${COL_HEADER_COLORS[selected.status] || 'bg-gray-100 text-gray-600'}`}>
                  {cl[selected.status] || selected.status}
                </span>
                <span className="text-[10px] text-[var(--text-muted)]">{selected.days_in_stage} {l.daysInStage}</span>
              </div>
              {selected.contact_name && (
                <div><span className="text-xs font-semibold text-[var(--text-secondary)]">{l.contact}:</span> <span className="text-xs text-[var(--text-primary)]">{selected.contact_name}</span></div>
              )}
              {selected.contact_email && (
                <div><span className="text-xs font-semibold text-[var(--text-secondary)]">{l.email}:</span> <a href={`mailto:${selected.contact_email}`} className="text-xs text-teal hover:underline">{selected.contact_email}</a></div>
              )}
              {selected.partnership_date && (
                <div><span className="text-xs font-semibold text-[var(--text-secondary)]">{l.partnershipDate}:</span> <span className="text-xs text-[var(--text-primary)]">{selected.partnership_date}</span></div>
              )}
              {selected.next_action && (
                <div className="flex items-start gap-1.5">
                  <span className="text-xs font-semibold text-blue-600">→ {l.nextAction}:</span>
                  <span className="text-xs text-[var(--text-primary)]">{selected.next_action}</span>
                </div>
              )}
              {selected.follow_up_date && (
                <div className="flex items-center gap-1.5">
                  <span className="text-xs font-semibold text-amber-600">📅 {l.followUp}:</span>
                  <span className="text-xs text-[var(--text-primary)]">{new Date(selected.follow_up_date + 'T00:00:00').toLocaleDateString('pt-BR')}</span>
                  {(() => {
                    const diff = Math.round((new Date(selected.follow_up_date).getTime() - Date.now()) / 86400000);
                    return diff < 0
                      ? <span className="text-[10px] font-bold text-red-600">({Math.abs(diff)}{l.daysOverdue})</span>
                      : <span className="text-[10px] text-[var(--text-muted)]">({diff}{l.daysUntil})</span>;
                  })()}
                </div>
              )}
            </div>

            {/* Interaction Form */}
            <div className="mt-4 pt-3 border-t border-[var(--border-subtle)]">
              <button onClick={() => setShowIxForm(!showIxForm)}
                className="text-xs font-bold text-teal cursor-pointer bg-transparent border-0 hover:underline mb-2">
                {l.addInteraction}
              </button>
              {showIxForm && (
                <div className="space-y-2 p-3 rounded-lg bg-[var(--surface-section-cool)] mb-3">
                  <div className="grid grid-cols-2 gap-2">
                    <select value={ixType} onChange={(e) => setIxType(e.target.value)}
                      className="text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5">
                      <option value="email">📧 Email</option>
                      <option value="whatsapp">📱 WhatsApp</option>
                      <option value="linkedin">💬 LinkedIn</option>
                      <option value="call">📞 Call</option>
                      <option value="meeting">🤝 Meeting</option>
                      <option value="note">📝 Note</option>
                    </select>
                    <input type="date" value={ixFollowUp} onChange={(e) => setIxFollowUp(e.target.value)}
                      className="text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5" />
                  </div>
                  <input type="text" value={ixSummary} onChange={(e) => setIxSummary(e.target.value)}
                    placeholder={l.ixSummary}
                    className="w-full text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5" />
                  <input type="text" value={ixOutcome} onChange={(e) => setIxOutcome(e.target.value)}
                    placeholder={l.ixOutcome}
                    className="w-full text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5" />
                  <input type="text" value={ixNext} onChange={(e) => setIxNext(e.target.value)}
                    placeholder={l.ixNext}
                    className="w-full text-[11px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-2 py-1.5" />
                  <button onClick={handleAddInteraction}
                    className="px-3 py-1.5 rounded-lg bg-teal text-white text-[11px] font-semibold hover:opacity-90 cursor-pointer border-0">
                    {l.register}
                  </button>
                </div>
              )}
            </div>

            {/* Interaction Timeline */}
            <div className="mt-3">
              <h3 className="text-xs font-bold text-[var(--text-secondary)] mb-2">{l.timeline}</h3>
              {ixLoading ? (
                <p className="text-[10px] text-[var(--text-muted)]">...</p>
              ) : interactions.length === 0 ? (
                <p className="text-[10px] text-[var(--text-muted)]">{l.noInteractions}</p>
              ) : (
                <div className="space-y-2 max-h-[250px] overflow-y-auto">
                  {interactions.map((ix) => (
                    <div key={ix.id} className="flex gap-2 text-[11px] pb-2 border-b border-[var(--border-subtle)] last:border-0">
                      <span className="text-base">{IX_ICONS[ix.interaction_type] || '📝'}</span>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-0.5">
                          <span className="text-[var(--text-muted)] text-[10px]">
                            {new Date(ix.created_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                          </span>
                          {ix.actor_name && <span className="text-[var(--text-secondary)] font-semibold text-[10px]">{ix.actor_name}</span>}
                        </div>
                        <p className="text-[var(--text-primary)] font-medium">{ix.summary}</p>
                        {ix.outcome && <p className="text-[var(--text-secondary)] text-[10px] mt-0.5">{l.outcome}: {ix.outcome}</p>}
                        {ix.next_action && <p className="text-blue-600 text-[10px] mt-0.5">→ {ix.next_action}</p>}
                        {ix.follow_up_date && <p className="text-amber-600 text-[10px] mt-0.5">📅 {new Date(ix.follow_up_date + 'T00:00:00').toLocaleDateString('pt-BR')}</p>}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="flex flex-wrap gap-2 mt-5 pt-3 border-t border-[var(--border-subtle)]">
              {NEXT_STATUS[selected.status] && (
                <button onClick={() => handleAdvance(selected)}
                  className="px-3 py-2 rounded-lg bg-teal text-white text-xs font-semibold hover:opacity-90">
                  {l.advance} →
                </button>
              )}
              {selected.status !== 'inactive' && selected.status !== 'churned' && (
                <button onClick={() => handleArchive(selected)}
                  className="px-3 py-2 rounded-lg border border-gray-300 text-gray-600 text-xs font-semibold hover:bg-gray-50">
                  {l.archive}
                </button>
              )}
              <button onClick={() => setSelected(null)}
                className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-[var(--text-primary)] text-xs font-semibold hover:bg-[var(--surface-hover)] ml-auto">
                {l.close}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Advance Confirmation Modal */}
      {advancingId && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/40" onClick={(e) => { if (e.target === e.currentTarget) setAdvancingId(null); }}>
          <div className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] shadow-xl w-full max-w-sm p-5 mx-4">
            {(() => {
              const partner = data.pipeline.find(p => p.id === advancingId);
              const nextStatus = partner ? NEXT_STATUS[partner.status] : '';
              return (
                <>
                  <h3 className="text-sm font-extrabold text-navy mb-3">
                    {l.advanceConfirm} <span className={`px-2 py-0.5 rounded-full text-[10px] font-semibold ${COL_HEADER_COLORS[nextStatus] || ''}`}>{cl[nextStatus] || nextStatus}</span>?
                  </h3>
                  <textarea
                    className="w-full text-sm rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] px-3 py-2 mb-3"
                    rows={2}
                    placeholder={l.advanceNote}
                    value={advanceNote}
                    onChange={(e) => setAdvanceNote(e.target.value)}
                  />
                  <div className="flex gap-2 justify-end">
                    <button onClick={() => setAdvancingId(null)} className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-xs font-semibold">{l.cancel}</button>
                    <button onClick={confirmAdvance} className="px-3 py-2 rounded-lg bg-teal text-white text-xs font-semibold hover:opacity-90">{l.confirm}</button>
                  </div>
                </>
              );
            })()}
          </div>
        </div>
      )}
    </div>
  );
}
