// src/components/agenda/AgendaVivaReservationIsland.tsx
// #701 Slice 2 — self-service reservation for the Agenda Viva de Protagonismo.
// For each of the next General Meetings, the signed-in volunteer either manages
// their existing block (edit/cancel until the meeting starts) or reserves a new
// one. All authority is enforced server-side (reserve_agenda_block V4 action +
// capacity lock); canFor('reserve_agenda_block') here is a UX gate only.
//
// On any successful mutation it dispatches `agenda:changed` so the read-only
// public timeline (AgendaVivaPublic) refreshes in lockstep.
import { useState, useEffect, useCallback } from 'react';
import { Loader2, CalendarPlus, Pencil, X, Trash2, Star } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { canFor } from '../../lib/permissions';

type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';

interface Block {
  id: string;
  format_slug: string;
  title: string;
  duration_min: number;
  status: 'reserved' | 'confirmed';
  external_guest: boolean;
  is_mine: boolean;
  material_url?: string | null;
}
interface EventRow {
  id: string;
  date: string;
  time_start: string | null;
  capacity_remaining_min: number;
  blocks: Block[];
}
interface FormatRow { slug: string; label_i18n: Record<string, string>; default_duration_min: number }

const DURATIONS = [5, 10, 15, 20, 30];
const LOCALE_MAP: Record<Lang, string> = { 'pt-BR': 'pt-BR', 'en-US': 'en-US', 'es-LATAM': 'es' };

interface DraftState {
  format_slug: string;
  duration_min: number;
  title: string;
  guest_name: string;
  material_url: string;
  external_guest: boolean;
}
const emptyDraft = (format_slug: string, duration_min: number): DraftState => ({
  format_slug, duration_min, title: '', guest_name: '', material_url: '', external_guest: false,
});

export default function AgendaVivaReservationIsland({ lang = 'pt-BR' }: { lang?: Lang }) {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const [allowed, setAllowed] = useState(false);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [formats, setFormats] = useState<FormatRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  // Per-event draft for the new-reservation form; editId tracks an in-place edit.
  const [drafts, setDrafts] = useState<Record<string, DraftState>>({});
  const [editing, setEditing] = useState<Record<string, DraftState>>({});

  const toast = (msg: string, kind: 'success' | 'error' = 'success') => (window as any).toast?.(msg, kind);

  const recomputeGate = useCallback(() => setAllowed(canFor('reserve_agenda_block')), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 300); return; }
    const [{ data: agenda }, { data: fmtRows }] = await Promise.all([
      sb.rpc('get_geral_agenda_viva', { p_limit_events: 2 }),
      sb.from('agenda_block_formats').select('slug, label_i18n, default_duration_min').eq('active', true).order('sort_order'),
    ]);
    if (Array.isArray(fmtRows)) setFormats(fmtRows);
    const evs: EventRow[] = (agenda?.events ?? []) as EventRow[];
    setEvents(evs);
    setLoading(false);
  }, [getSb]);

  useEffect(() => {
    recomputeGate();
    load();
    const onMember = () => { recomputeGate(); load(); };
    window.addEventListener('nav:member', onMember);
    return () => window.removeEventListener('nav:member', onMember);
  }, [load, recomputeGate]);

  const fmtLabel = (slug: string): string => {
    const f = formats.find((x) => x.slug === slug);
    return f?.label_i18n?.[lang] || f?.label_i18n?.['pt-BR'] || slug;
  };
  const fmtDate = (iso: string): string => {
    const d = new Date(`${iso}T12:00:00Z`);
    if (Number.isNaN(d.getTime())) return iso;
    return new Intl.DateTimeFormat(LOCALE_MAP[lang], { weekday: 'short', day: '2-digit', month: 'short', timeZone: 'UTC' }).format(d);
  };

  // Map RPC error codes → localized messages.
  const errMsg = (code?: string): string => {
    const map: Record<string, string> = {
      title_required: 'errTitleRequired', invalid_duration: 'errInvalidDuration', invalid_format: 'errInvalidFormat',
      event_not_reservable: 'errEventNotReservable', reservation_window_closed: 'errWindowClosed',
      capacity_exceeded: 'errCapacity', already_reserved: 'errAlreadyReserved', access_denied: 'errDenied',
      edit_window_closed: 'errWindowEdit', cancel_window_closed: 'errWindowEdit',
    };
    const key = code && map[code] ? map[code] : 'errGeneric';
    return t(`comp.agendaViva.${key}`, 'Algo deu errado. Tente novamente.');
  };

  const ensureDraft = (eventId: string): DraftState => {
    if (drafts[eventId]) return drafts[eventId];
    const first = formats[0];
    const d = emptyDraft(first?.slug || 'insight_rapido', first?.default_duration_min || 5);
    setDrafts((p) => ({ ...p, [eventId]: d }));
    return d;
  };
  const setDraft = (eventId: string, patch: Partial<DraftState>) =>
    setDrafts((p) => ({ ...p, [eventId]: { ...ensureDraft(eventId), ...patch } }));
  const setEdit = (blockId: string, patch: Partial<DraftState>) =>
    setEditing((p) => ({ ...p, [blockId]: { ...p[blockId], ...patch } }));

  const onFormatChange = (eventId: string, slug: string) => {
    const f = formats.find((x) => x.slug === slug);
    setDraft(eventId, { format_slug: slug, duration_min: f?.default_duration_min ?? ensureDraft(eventId).duration_min });
  };

  const afterChange = async () => { await load(); window.dispatchEvent(new CustomEvent('agenda:changed')); };

  const reserve = async (eventId: string) => {
    const sb = getSb(); if (!sb) return;
    const d = ensureDraft(eventId);
    if (!d.title.trim()) { toast(t('comp.agendaViva.errTitleRequired', 'Informe um título.'), 'error'); return; }
    setBusy(eventId);
    try {
      const { data, error } = await sb.rpc('reserve_agenda_block', {
        p_event_id: eventId, p_format_slug: d.format_slug, p_title: d.title.trim(), p_duration_min: d.duration_min,
        p_guest_name: d.guest_name.trim() || null, p_material_url: d.material_url.trim() || null, p_external_guest: d.external_guest,
      });
      if (error) throw error;
      if (data?.error) { toast(errMsg(data.error), 'error'); return; }
      toast(t('comp.agendaViva.reserveSuccess', 'Bloco reservado!'));
      setDrafts((p) => { const n = { ...p }; delete n[eventId]; return n; });
      await afterChange();
    } catch (e: any) { toast(errMsg(e?.code || e?.message), 'error'); }
    finally { setBusy(null); }
  };

  const startEdit = (b: Block) => setEditing((p) => ({
    ...p, [b.id]: {
      format_slug: b.format_slug, duration_min: b.duration_min, title: b.title,
      guest_name: '', material_url: b.material_url || '', external_guest: b.external_guest,
    },
  }));
  const cancelEdit = (blockId: string) => setEditing((p) => { const n = { ...p }; delete n[blockId]; return n; });

  const saveEdit = async (blockId: string) => {
    const sb = getSb(); if (!sb) return;
    const d = editing[blockId]; if (!d) return;
    if (!d.title.trim()) { toast(t('comp.agendaViva.errTitleRequired', 'Informe um título.'), 'error'); return; }
    setBusy(blockId);
    try {
      const { data, error } = await sb.rpc('update_agenda_block', {
        p_block_id: blockId, p_title: d.title.trim(), p_format_slug: d.format_slug, p_duration_min: d.duration_min,
        p_guest_name: d.guest_name.trim() || null, p_material_url: d.material_url.trim() || null, p_external_guest: d.external_guest,
      });
      if (error) throw error;
      if (data?.error) { toast(errMsg(data.error), 'error'); return; }
      toast(t('comp.agendaViva.updateSuccess', 'Bloco atualizado!'));
      cancelEdit(blockId);
      await afterChange();
    } catch (e: any) { toast(errMsg(e?.code || e?.message), 'error'); }
    finally { setBusy(null); }
  };

  const cancelReservation = async (blockId: string) => {
    const sb = getSb(); if (!sb) return;
    if (!window.confirm(t('comp.agendaViva.confirmCancelReserve', 'Cancelar esta reserva?'))) return;
    setBusy(blockId);
    try {
      const { data, error } = await sb.rpc('cancel_agenda_block', { p_block_id: blockId });
      if (error) throw error;
      if (data?.error) { toast(errMsg(data.error), 'error'); return; }
      toast(t('comp.agendaViva.cancelSuccess', 'Reserva cancelada.'));
      await afterChange();
    } catch (e: any) { toast(errMsg(e?.code || e?.message), 'error'); }
    finally { setBusy(null); }
  };

  if (loading || !allowed) return null; // anon/insufficient → public island already shows a login hint

  const inputCls = 'mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2 text-sm';

  const renderFields = (d: DraftState, set: (patch: Partial<DraftState>) => void, onFmt: (slug: string) => void) => (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fFormat', 'Formato')}</span>
          <select value={d.format_slug} onChange={(e) => onFmt(e.target.value)} className={inputCls}>
            {formats.map((f) => <option key={f.slug} value={f.slug}>{fmtLabel(f.slug)}</option>)}
          </select>
        </label>
        <label className="block">
          <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fDuration', 'Duração')}</span>
          <select value={d.duration_min} onChange={(e) => set({ duration_min: Number(e.target.value) })} className={inputCls}>
            {DURATIONS.map((m) => <option key={m} value={m}>{m} {t('comp.agendaViva.min', 'min')}</option>)}
          </select>
        </label>
      </div>
      <label className="block">
        <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fTitle', 'Título')}</span>
        <input value={d.title} onChange={(e) => set({ title: e.target.value })}
          placeholder={t('comp.agendaViva.fTitlePlaceholder', '')} className={inputCls} maxLength={140} />
      </label>
      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fGuest', 'Convidado (opcional)')}</span>
          <input value={d.guest_name} onChange={(e) => set({ guest_name: e.target.value })}
            placeholder={t('comp.agendaViva.fGuestPlaceholder', '')} className={inputCls} maxLength={120} />
        </label>
        <label className="block">
          <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fMaterial', 'Material (opcional)')}</span>
          <input value={d.material_url} onChange={(e) => set({ material_url: e.target.value })}
            placeholder={t('comp.agendaViva.fMaterialPlaceholder', 'https://…')} className={inputCls} />
        </label>
      </div>
      <label className="flex items-center gap-2 text-sm cursor-pointer">
        <input type="checkbox" checked={d.external_guest} onChange={(e) => set({ external_guest: e.target.checked })} className="rounded" />
        <span>{t('comp.agendaViva.fExternalGuest', 'Convidado externo ao núcleo')}</span>
      </label>
    </div>
  );

  return (
    <div className="mb-8 space-y-4">
      <h2 className="text-lg font-bold text-[var(--text-primary)] flex items-center gap-2">
        <CalendarPlus size={18} className="text-orange" /> {t('comp.agendaViva.reserveHeading', 'Reservar um bloco')}
      </h2>
      {events.map((ev) => {
        const myBlock = ev.blocks.find((b) => b.is_mine);
        const draft = drafts[ev.id] || (formats[0] ? emptyDraft(formats[0].slug, formats[0].default_duration_min) : null);
        const isEditing = myBlock && editing[myBlock.id];
        return (
          <div key={ev.id} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
            <div className="flex items-center justify-between mb-3">
              <span className="font-semibold text-[var(--text-primary)] capitalize">{fmtDate(ev.date)}</span>
              <span className="text-xs text-[var(--text-muted)]">
                {ev.capacity_remaining_min} {t('comp.agendaViva.min', 'min')} {t('comp.agendaViva.capacityFree', 'livres')}
              </span>
            </div>

            {myBlock ? (
              <div>
                <div className="flex items-center gap-2 text-sm mb-2">
                  <Star size={13} className="text-teal" />
                  <span className="font-medium text-teal">{t('comp.agendaViva.myBlockHeading', 'Seu bloco nesta reunião')}</span>
                </div>
                {isEditing ? (
                  <>
                    {renderFields(editing[myBlock.id], (p) => setEdit(myBlock.id, p),
                      (slug) => { const f = formats.find((x) => x.slug === slug); setEdit(myBlock.id, { format_slug: slug, duration_min: f?.default_duration_min ?? editing[myBlock.id].duration_min }); })}
                    <div className="mt-3 flex justify-end gap-2">
                      <button onClick={() => cancelEdit(myBlock.id)} className="px-3 py-1.5 rounded-lg text-sm text-[var(--text-muted)] hover:bg-[var(--bg-subtle)]">
                        {t('comp.agendaViva.cancel', 'Cancelar')}
                      </button>
                      <button onClick={() => saveEdit(myBlock.id)} disabled={busy === myBlock.id}
                        className="px-3 py-1.5 rounded-lg text-sm bg-[var(--accent)] text-white hover:opacity-90 inline-flex items-center gap-1 disabled:opacity-60">
                        {busy === myBlock.id && <Loader2 size={13} className="animate-spin" />} {t('comp.agendaViva.save', 'Salvar')}
                      </button>
                    </div>
                  </>
                ) : (
                  <div className="flex items-center justify-between gap-3 rounded-xl border border-teal/30 bg-teal/5 px-3 py-2.5">
                    <div className="min-w-0">
                      <div className="font-semibold text-[var(--text-primary)] truncate">{myBlock.title}</div>
                      <div className="text-xs text-[var(--text-muted)]">{fmtLabel(myBlock.format_slug)} · {myBlock.duration_min} {t('comp.agendaViva.min', 'min')}</div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button onClick={() => startEdit(myBlock)} title={t('comp.agendaViva.editCta', 'Editar')}
                        className="p-1.5 rounded hover:bg-[var(--bg-subtle)] text-[var(--text-muted)]"><Pencil size={15} /></button>
                      <button onClick={() => cancelReservation(myBlock.id)} disabled={busy === myBlock.id}
                        title={t('comp.agendaViva.cancelReserveCta', 'Cancelar reserva')}
                        className="p-1.5 rounded hover:bg-rose-50 text-rose-500 disabled:opacity-50">
                        {busy === myBlock.id ? <Loader2 size={15} className="animate-spin" /> : <Trash2 size={15} />}
                      </button>
                    </div>
                  </div>
                )}
              </div>
            ) : draft ? (
              <>
                {renderFields(drafts[ev.id] || draft, (p) => setDraft(ev.id, p), (slug) => onFormatChange(ev.id, slug))}
                <div className="mt-3 flex justify-end">
                  <button onClick={() => reserve(ev.id)} disabled={busy === ev.id}
                    className="px-4 py-2 rounded-lg text-sm bg-orange text-white hover:opacity-90 inline-flex items-center gap-1.5 disabled:opacity-60">
                    {busy === ev.id ? <Loader2 size={14} className="animate-spin" /> : <CalendarPlus size={14} />}
                    {t('comp.agendaViva.reserveCta', 'Reservar bloco')}
                  </button>
                </div>
              </>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
