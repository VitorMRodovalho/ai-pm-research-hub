import React, { useCallback, useEffect, useState } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

// #1094 — LinkedIn-first enqueue surface for comms_scheduled_posts.
// The RPC trio (schedule_comms_post / list_scheduled_comms_posts /
// cancel_scheduled_comms_post — mig 334) already exists and is gate-checked by
// can_manage_comms_metrics(); this island is the missing UI on-ramp. Scoped to
// LinkedIn TEXT/IMAGE/DOCUMENT (owner decision) — the RPC also accepts VIDEO/ARTICLE
// and the instagram channel, but IG already has a healthy pending queue and does not
// need a composer here. Payload keys mirror publish-linkedin (text=commentary).

type MediaType = 'TEXT' | 'IMAGE' | 'DOCUMENT';

type QueueItem = {
  id: string;
  channel: string;
  media_type: string;
  label: string | null;
  status: string;
  scheduled_at: string;
  published_at: string | null;
  attempts: number;
  error: string | null;
  permalink: string | null;
};

const CAPTION_LIMIT = 3000; // LinkedIn commentary limit (mirrors the RPC guard)

const STATUS_TONE: Record<string, string> = {
  pending: 'bg-blue-50 text-blue-700 border-blue-200',
  publishing: 'bg-amber-50 text-amber-700 border-amber-200',
  published: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  failed: 'bg-red-50 text-red-700 border-red-200',
  canceled: 'bg-gray-100 text-gray-500 border-gray-200',
};

function getSb(): any {
  return (globalThis as any)?.navGetSb?.() ?? null;
}

export default function CommsSchedulerPanel() {
  const t = usePageI18n();

  const [mediaType, setMediaType] = useState<MediaType>('TEXT');
  const [text, setText] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [altText, setAltText] = useState('');
  const [documentUrl, setDocumentUrl] = useState('');
  const [title, setTitle] = useState('');
  const [scheduledAt, setScheduledAt] = useState('');
  const [label, setLabel] = useState('');

  const [submitting, setSubmitting] = useState(false);
  const [feedback, setFeedback] = useState<{ kind: 'ok' | 'err'; msg: string } | null>(null);

  const [items, setItems] = useState<QueueItem[]>([]);
  const [queueLoading, setQueueLoading] = useState(true);
  const [queueError, setQueueError] = useState<string | null>(null);
  const [cancelingId, setCancelingId] = useState<string | null>(null);

  const loadQueue = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setQueueError(t('comp.comms.sched.noSb', 'Supabase não disponível.')); setQueueLoading(false); return; }
    setQueueLoading(true);
    try {
      const { data, error } = await sb.rpc('list_scheduled_comms_posts', {
        p_channel: 'linkedin', p_status: null, p_limit: 50, p_include_payload: false,
      });
      if (error) throw error;
      setItems(Array.isArray(data?.items) ? data.items : []);
      setQueueError(null);
    } catch (e: any) {
      setQueueError(String(e?.message || e));
    } finally {
      setQueueLoading(false);
    }
  }, [t]);

  useEffect(() => { loadQueue(); }, [loadQueue]);

  function buildPayload(): Record<string, unknown> | { error: string } {
    const commentary = text.trim();
    if (mediaType === 'TEXT') {
      if (!commentary) return { error: t('comp.comms.sched.errTextRequired', 'O texto do post é obrigatório.') };
      return { text: commentary };
    }
    if (mediaType === 'IMAGE') {
      if (!imageUrl.trim()) return { error: t('comp.comms.sched.errImageRequired', 'A URL da imagem é obrigatória.') };
      const p: Record<string, unknown> = { image_url: imageUrl.trim() };
      if (commentary) p.text = commentary;
      if (altText.trim()) p.alt_text = altText.trim();
      return p;
    }
    // DOCUMENT
    if (!documentUrl.trim()) return { error: t('comp.comms.sched.errDocRequired', 'A URL do documento (PDF público) é obrigatória.') };
    if (!title.trim()) return { error: t('comp.comms.sched.errTitleRequired', 'O título do documento é obrigatório.') };
    const p: Record<string, unknown> = { document_url: documentUrl.trim(), title: title.trim() };
    if (commentary) p.text = commentary;
    return p;
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setFeedback(null);

    const payload = buildPayload();
    if ('error' in payload && typeof payload.error === 'string') {
      setFeedback({ kind: 'err', msg: payload.error });
      return;
    }
    if (!scheduledAt) {
      setFeedback({ kind: 'err', msg: t('comp.comms.sched.errWhenRequired', 'A data/hora de publicação é obrigatória.') });
      return;
    }
    if (text.length > CAPTION_LIMIT) {
      setFeedback({ kind: 'err', msg: t('comp.comms.sched.errTooLong', 'O texto excede o limite do LinkedIn (3000 caracteres).') });
      return;
    }
    const whenIso = new Date(scheduledAt).toISOString();
    if (Number.isNaN(Date.parse(whenIso))) {
      setFeedback({ kind: 'err', msg: t('comp.comms.sched.errWhenInvalid', 'Data/hora inválida.') });
      return;
    }

    const sb = getSb();
    if (!sb) { setFeedback({ kind: 'err', msg: t('comp.comms.sched.noSb', 'Supabase não disponível.') }); return; }

    setSubmitting(true);
    try {
      const { data, error } = await sb.rpc('schedule_comms_post', {
        p_channel: 'linkedin',
        p_media_type: mediaType,
        p_payload: payload,
        p_scheduled_at: whenIso,
        p_label: label.trim() || null,
        p_idea_id: null,
      });
      if (error) throw error;
      setFeedback({ kind: 'ok', msg: t('comp.comms.sched.ok', 'Post agendado na fila do LinkedIn.') + (data?.id ? ` (${String(data.id).slice(0, 8)})` : '') });
      // reset content fields, keep media type + schedule for rapid multi-post entry
      setText(''); setImageUrl(''); setAltText(''); setDocumentUrl(''); setTitle(''); setLabel('');
      loadQueue();
    } catch (e: any) {
      setFeedback({ kind: 'err', msg: String(e?.message || e) });
    } finally {
      setSubmitting(false);
    }
  }

  async function handleCancel(id: string) {
    setCancelingId(id);
    const sb = getSb();
    if (!sb) { setCancelingId(null); return; }
    try {
      const { error } = await sb.rpc('cancel_scheduled_comms_post', { p_id: id });
      if (error) throw error;
      setFeedback({ kind: 'ok', msg: t('comp.comms.sched.canceled', 'Agendamento cancelado.') });
      loadQueue();
    } catch (e: any) {
      setFeedback({ kind: 'err', msg: String(e?.message || e) });
    } finally {
      setCancelingId(null);
    }
  }

  const mediaTabs: { key: MediaType; label: string }[] = [
    { key: 'TEXT', label: t('comp.comms.sched.typeText', 'Texto') },
    { key: 'IMAGE', label: t('comp.comms.sched.typeImage', 'Imagem') },
    { key: 'DOCUMENT', label: t('comp.comms.sched.typeDocument', 'Documento (PDF)') },
  ];

  const inputCls = 'w-full px-3 py-2 rounded-lg border-[1.5px] border-[var(--border-default)] text-sm bg-[var(--surface-base)] text-[var(--text-primary)] focus:outline-none focus:border-navy transition-colors';
  const labelCls = 'block text-[.68rem] font-semibold uppercase tracking-wide text-[var(--text-secondary)] mb-1';

  return (
    <div className="space-y-5">
      {/* Compose form */}
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <span className={labelCls}>{t('comp.comms.sched.mediaType', 'Tipo de post')}</span>
          <div className="inline-flex rounded-xl border border-[var(--border-default)] overflow-hidden">
            {mediaTabs.map(tab => (
              <button
                key={tab.key}
                type="button"
                onClick={() => setMediaType(tab.key)}
                className={`px-4 py-2 text-[.78rem] font-semibold transition-colors ${mediaType === tab.key ? 'bg-navy text-white' : 'bg-[var(--surface-card)] text-[var(--text-primary)] hover:bg-[var(--surface-hover)]'}`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>

        {mediaType === 'IMAGE' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className={labelCls} htmlFor="sched-image-url">{t('comp.comms.sched.imageUrl', 'URL da imagem (pública)')}</label>
              <input id="sched-image-url" type="url" className={inputCls} value={imageUrl} onChange={e => setImageUrl(e.target.value)} placeholder="https://…/foto.jpg" />
            </div>
            <div>
              <label className={labelCls} htmlFor="sched-alt">{t('comp.comms.sched.altText', 'Texto alternativo (acessibilidade)')}</label>
              <input id="sched-alt" type="text" className={inputCls} value={altText} onChange={e => setAltText(e.target.value)} />
            </div>
          </div>
        )}

        {mediaType === 'DOCUMENT' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className={labelCls} htmlFor="sched-doc-url">{t('comp.comms.sched.documentUrl', 'URL do documento (PDF público)')}</label>
              <input id="sched-doc-url" type="url" className={inputCls} value={documentUrl} onChange={e => setDocumentUrl(e.target.value)} placeholder="https://…/deck.pdf" />
            </div>
            <div>
              <label className={labelCls} htmlFor="sched-doc-title">{t('comp.comms.sched.documentTitle', 'Título do documento')}</label>
              <input id="sched-doc-title" type="text" className={inputCls} value={title} onChange={e => setTitle(e.target.value)} />
            </div>
          </div>
        )}

        <div>
          <label className={labelCls} htmlFor="sched-text">
            {mediaType === 'TEXT'
              ? t('comp.comms.sched.textLabel', 'Texto do post')
              : t('comp.comms.sched.commentaryLabel', 'Comentário (texto que acompanha a mídia)')}
          </label>
          <textarea
            id="sched-text"
            className={`${inputCls} min-h-[120px] resize-y`}
            value={text}
            onChange={e => setText(e.target.value)}
            maxLength={CAPTION_LIMIT + 200}
            placeholder={t('comp.comms.sched.textPlaceholder', 'Escreva o post. URLs viram links clicáveis no LinkedIn.')}
          />
          <div className={`mt-1 text-[.66rem] ${text.length > CAPTION_LIMIT ? 'text-red-600 font-semibold' : 'text-[var(--text-muted)]'}`}>
            {text.length} / {CAPTION_LIMIT}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <label className={labelCls} htmlFor="sched-when">{t('comp.comms.sched.scheduledAt', 'Data e hora da publicação')}</label>
            <input id="sched-when" type="datetime-local" className={inputCls} value={scheduledAt} onChange={e => setScheduledAt(e.target.value)} />
          </div>
          <div>
            <label className={labelCls} htmlFor="sched-label">{t('comp.comms.sched.labelField', 'Rótulo interno (opcional)')}</label>
            <input id="sched-label" type="text" className={inputCls} value={label} onChange={e => setLabel(e.target.value)} placeholder={t('comp.comms.sched.labelPlaceholder', 'ex.: Divulgação AI Community Day')} />
          </div>
        </div>

        {feedback && (
          <div className={`rounded-lg px-3 py-2 text-sm border ${feedback.kind === 'ok' ? 'bg-emerald-50 text-emerald-800 border-emerald-200' : 'bg-red-50 text-red-800 border-red-200'}`}>
            {feedback.msg}
          </div>
        )}

        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={submitting}
            className="px-5 py-2.5 rounded-xl bg-navy text-white text-[.82rem] font-bold border-0 cursor-pointer hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed transition-opacity"
          >
            {submitting ? t('comp.comms.sched.submitting', 'Agendando…') : t('comp.comms.sched.submit', 'Agendar no LinkedIn')}
          </button>
          <button
            type="button"
            onClick={loadQueue}
            className="px-4 py-2.5 rounded-xl bg-[var(--surface-card)] border border-[var(--border-default)] text-[var(--text-primary)] text-[.78rem] font-semibold cursor-pointer hover:bg-[var(--surface-hover)] transition-colors"
          >
            {t('comp.comms.sched.refresh', 'Atualizar fila')}
          </button>
        </div>
      </form>

      {/* Queue */}
      <div className="rounded-xl border border-[var(--border-default)] overflow-hidden">
        <div className="px-4 py-2.5 border-b border-[var(--border-default)] bg-[var(--surface-base)]">
          <h3 className="text-[.78rem] font-bold text-[var(--text-primary)]">{t('comp.comms.sched.queueTitle', 'Fila do LinkedIn')}</h3>
        </div>
        <div className="p-4 overflow-x-auto">
          {queueLoading ? (
            <p className="text-[var(--text-muted)] text-sm py-4">{t('comp.comms.sched.queueLoading', 'Carregando fila…')}</p>
          ) : queueError ? (
            <p className="text-red-700 text-sm py-4">{queueError}</p>
          ) : items.length === 0 ? (
            <p className="text-[var(--text-secondary)] text-sm py-4">{t('comp.comms.sched.queueEmpty', 'Nenhum post LinkedIn na fila.')}</p>
          ) : (
            <table className="w-full text-[.72rem] border-collapse">
              <thead>
                <tr className="border-b border-[var(--border-default)] text-left">
                  <th className="px-2 py-2 font-semibold text-[var(--text-secondary)]">{t('comp.comms.sched.colWhen', 'Quando')}</th>
                  <th className="px-2 py-2 font-semibold text-[var(--text-secondary)]">{t('comp.comms.sched.colType', 'Tipo')}</th>
                  <th className="px-2 py-2 font-semibold text-[var(--text-secondary)]">{t('comp.comms.sched.colLabel', 'Rótulo')}</th>
                  <th className="px-2 py-2 font-semibold text-[var(--text-secondary)]">{t('comp.comms.sched.colStatus', 'Status')}</th>
                  <th className="px-2 py-2 font-semibold text-[var(--text-secondary)] text-right">{t('comp.comms.sched.colActions', 'Ações')}</th>
                </tr>
              </thead>
              <tbody>
                {items.map(it => {
                  const when = it.scheduled_at
                    ? new Date(it.scheduled_at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
                    : '';
                  const tone = STATUS_TONE[it.status] || STATUS_TONE.canceled;
                  return (
                    <tr key={it.id} className="border-b border-[var(--border-subtle)] hover:bg-[var(--surface-hover)] align-top">
                      <td className="px-2 py-2 whitespace-nowrap">{when}</td>
                      <td className="px-2 py-2">{it.media_type}</td>
                      <td className="px-2 py-2">{it.label || <span className="text-[var(--text-muted)]">—</span>}</td>
                      <td className="px-2 py-2">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded-full border text-[.62rem] font-bold ${tone}`}>{it.status}</span>
                        {it.error && <div className="mt-1 text-[.6rem] text-red-600 max-w-[220px] truncate" title={it.error}>{it.error}</div>}
                      </td>
                      <td className="px-2 py-2 text-right whitespace-nowrap">
                        {it.permalink && (
                          <a href={it.permalink} target="_blank" rel="noopener noreferrer" className="text-teal font-semibold no-underline hover:underline mr-2">{t('comp.comms.sched.view', 'Ver')}</a>
                        )}
                        {it.status === 'pending' && (
                          <button
                            type="button"
                            onClick={() => handleCancel(it.id)}
                            disabled={cancelingId === it.id}
                            className="text-red-600 font-semibold cursor-pointer hover:underline disabled:opacity-50"
                          >
                            {cancelingId === it.id ? t('comp.comms.sched.canceling', 'Cancelando…') : t('comp.comms.sched.cancel', 'Cancelar')}
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}
