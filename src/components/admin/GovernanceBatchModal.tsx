import { useState } from 'react';

interface Props {
  selectedCRs: any[];
  t: (key: string, fallback?: string) => string;
  getSb: () => any;
  onClose: () => void;
  onDone: () => void;
}

type Phase = 'confirm' | 'processing' | 'result';
interface CRResult { cr: any; success: boolean; error?: string }

export default function GovernanceBatchModal({ selectedCRs, t, getSb, onClose, onDone }: Props) {
  const [phase, setPhase] = useState<Phase>('confirm');
  const [notes, setNotes] = useState('');
  const [results, setResults] = useState<CRResult[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);

  const hasCritical = selectedCRs.some(cr =>
    ['high', 'critical'].includes(cr.impact_level) || ['structural', 'emergency'].includes(cr.cr_type)
  );
  const criticalCount = selectedCRs.filter(cr =>
    ['high', 'critical'].includes(cr.impact_level) || ['structural', 'emergency'].includes(cr.cr_type)
  ).length;

  const handleConfirm = async () => {
    setPhase('processing');
    const sb = getSb();
    const batch: CRResult[] = [];

    for (let i = 0; i < selectedCRs.length; i++) {
      const cr = selectedCRs[i];
      setCurrentIndex(i);
      try {
        const { data, error } = await sb.rpc('review_change_request', {
          p_cr_id: cr.id, p_action: 'approve', p_notes: notes.trim() || null,
        });
        if (error) throw error;
        if (data?.error) throw new Error(data.error);
        batch.push({ cr, success: true });
      } catch (e: any) {
        batch.push({ cr, success: false, error: e.message || 'Erro' });
      }
      setResults([...batch]);
    }
    setPhase('result');
  };

  const handleRetry = async () => {
    const failed = results.filter(r => !r.success).map(r => r.cr);
    if (failed.length === 0) return;
    setPhase('processing');
    setCurrentIndex(0);
    const sb = getSb();
    const newResults = results.filter(r => r.success);

    for (let i = 0; i < failed.length; i++) {
      const cr = failed[i];
      setCurrentIndex(i);
      try {
        const { data, error } = await sb.rpc('review_change_request', {
          p_cr_id: cr.id, p_action: 'approve', p_notes: notes.trim() || null,
        });
        if (error) throw error;
        if (data?.error) throw new Error(data.error);
        newResults.push({ cr, success: true });
      } catch (e: any) {
        newResults.push({ cr, success: false, error: e.message || 'Erro' });
      }
      setResults([...newResults]);
    }
    setPhase('result');
  };

  const successCount = results.filter(r => r.success).length;
  const failCount = results.filter(r => !r.success).length;
  const pct = phase === 'processing'
    ? Math.round(((currentIndex + 1) / selectedCRs.length) * 100)
    : 100;

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 backdrop-blur-sm p-4" onClick={onClose}>
      <div className="bg-[var(--surface-elevated)] rounded-2xl border border-[var(--border-default)] shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}>

        {/* Header */}
        <div className="px-5 py-4 border-b border-[var(--border-default)] flex items-center justify-between">
          <h3 className="text-base font-bold text-navy">
            {t('governance.batch_title', `Aprovar ${selectedCRs.length} Solicitações de Mudança`).replace('{count}', String(selectedCRs.length))}
          </h3>
          {phase !== 'processing' && (
            <button onClick={onClose} className="text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer border-0 bg-transparent text-xl">✕</button>
          )}
        </div>

        <div className="px-5 py-4 space-y-4">
          {/* ── Confirm phase ── */}
          {phase === 'confirm' && (
            <>
              {hasCritical && (
                <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-amber-800 text-sm">
                  {t('governance.warning_critical', `⚠️ ${criticalCount} CRs de impacto alto/crítico ou tipo estrutural seleccionadas.`).replace('{count}', String(criticalCount))}
                </div>
              )}

              <div>
                <div className="text-xs font-bold text-[var(--text-secondary)] mb-2">CRs selecionadas:</div>
                <div className="space-y-1 max-h-40 overflow-y-auto">
                  {selectedCRs.map(cr => (
                    <div key={cr.id} className="text-sm text-[var(--text-primary)]">
                      • {cr.cr_number}: {cr.title}
                      <span className="text-xs text-[var(--text-muted)] ml-1">
                        ({cr.cr_type}/{cr.impact_level})
                      </span>
                    </div>
                  ))}
                </div>
              </div>

              <div>
                <label className="text-xs font-bold text-[var(--text-secondary)] block mb-1">
                  {t('governance.batch_notes_label', 'Notas de aprovação (aplicadas a todas)')}
                </label>
                <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3}
                  placeholder={t('governance.batch_notes_placeholder', 'Registre justificativa objetiva. Ex: Aprovado em reunião CCB com [participantes], [data].')}
                  className="w-full px-3 py-2 text-sm rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] resize-y" />
              </div>

              <div className="rounded-lg bg-blue-50 border border-blue-200 px-3 py-2 text-xs text-blue-700">
                {t('governance.ccb_note', 'As aprovações implementam tecnicamente decisões do Comitê de Controle de Mudanças (CCB) do Núcleo IA & GP.')}
              </div>

              <div className="rounded-lg bg-gray-50 border border-gray-200 px-3 py-2 text-xs text-gray-600">
                {t('governance.partial_failure_help', 'Em caso de falha parcial, use o filtro de status para identificar CRs pendentes e execute novo batch.')}
              </div>

              <div className="flex justify-end gap-2 pt-2">
                <button onClick={onClose}
                  className="px-4 py-2 rounded-lg border border-[var(--border-default)] text-sm font-semibold text-[var(--text-secondary)] cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]">
                  {t('governance.cancel', 'Cancelar')}
                </button>
                <button onClick={handleConfirm}
                  className="px-4 py-2 rounded-lg bg-green-600 text-white text-sm font-semibold cursor-pointer border-0 hover:bg-green-700">
                  {t('governance.batch_confirm', `Confirmar Aprovação de ${selectedCRs.length}`).replace('{count}', String(selectedCRs.length))}
                </button>
              </div>
            </>
          )}

          {/* ── Processing phase ── */}
          {phase === 'processing' && (
            <>
              <div className="text-sm font-bold text-[var(--text-primary)] mb-2">
                {t('governance.batch_processing', 'Processando...')}
              </div>
              <div className="w-full bg-gray-200 rounded-full h-3 overflow-hidden">
                <div className="bg-green-500 h-3 rounded-full transition-all duration-300" style={{ width: `${pct}%` }} />
              </div>
              <div className="text-xs text-[var(--text-muted)] mb-2">
                {currentIndex + 1}/{selectedCRs.length} ({pct}%)
              </div>
              <div className="space-y-1 max-h-48 overflow-y-auto">
                {results.map((r, i) => (
                  <div key={i} className="text-sm">
                    {r.success ? '✅' : '❌'} {r.cr.cr_number} — {r.success ? t('governance.status_approved', 'aprovada') : r.error}
                  </div>
                ))}
                {currentIndex < selectedCRs.length && results.length <= currentIndex && (
                  <div className="text-sm text-[var(--text-muted)]">
                    ⏳ {selectedCRs[currentIndex]?.cr_number} — {t('governance.batch_processing', 'processando...')}
                  </div>
                )}
              </div>
            </>
          )}

          {/* ── Result phase ── */}
          {phase === 'result' && (
            <>
              {successCount > 0 && (
                <div className="rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-green-800 text-sm font-semibold">
                  ✅ {t('governance.batch_result_success', `${successCount} CRs aprovadas com sucesso`).replace('{count}', String(successCount))}
                </div>
              )}
              {failCount > 0 && (
                <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-red-800 text-sm font-semibold">
                  ❌ {t('governance.batch_result_error', `${failCount} CR(s) com erro`).replace('{count}', String(failCount))}
                </div>
              )}

              {notes && (
                <div className="text-xs text-[var(--text-muted)]">
                  <span className="font-bold">Contexto:</span> "{notes}"
                </div>
              )}

              <div className="text-sm text-[var(--text-secondary)]">
                {t('governance.batch_next_step', 'Próximo passo: implementar no Manual R3')}
              </div>

              <div className="space-y-1 max-h-48 overflow-y-auto">
                {results.map((r, i) => (
                  <div key={i} className="text-sm">
                    {r.success ? '✅' : '❌'} {r.cr.cr_number}: {r.cr.title}
                    {r.error && <span className="text-red-600 text-xs ml-1">({r.error})</span>}
                  </div>
                ))}
              </div>

              <div className="flex justify-end gap-2 pt-2">
                {failCount > 0 && (
                  <button onClick={handleRetry}
                    className="px-4 py-2 rounded-lg border border-amber-300 bg-amber-50 text-amber-700 text-sm font-semibold cursor-pointer hover:bg-amber-100">
                    {t('governance.batch_retry', 'Retry falhadas')} ({failCount})
                  </button>
                )}
                <button onClick={() => { onDone(); onClose(); }}
                  className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold cursor-pointer border-0 hover:opacity-90">
                  {t('governance.cancel', 'Fechar')}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
