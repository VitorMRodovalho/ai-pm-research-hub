// src/components/admin/AdminAgendaVivaPanel.tsx
// #701 Slice 2 — coordination panel for the Agenda Viva de Protagonismo.
// Lists the reserved/confirmed blocks of the next General Meetings (admin tier of
// get_geral_agenda_viva → full names + guest PII) and lets a coordinator with
// manage_event reorder (drag), confirm attendance (per-block or bulk), mark
// no-show (revokes XP) and cancel blocks. The RPCs are the real authority gate;
// the page-level UX gate mirrors manage_event.
import { useState, useEffect, useCallback } from 'react';
import { Loader2, CalendarClock, GripVertical, Check, CheckCheck, UserX, Trash2, RefreshCw, ExternalLink } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';

type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';

interface Block {
  id: string;
  format_slug: string;
  title: string;
  duration_min: number;
  status: 'reserved' | 'confirmed';
  sort_order: number;
  external_guest: boolean;
  owner_first_name: string;
  owner_full_name?: string;
  guest_name?: string | null;
  material_url?: string | null;
}
interface EventRow {
  id: string;
  date: string;
  time_start: string | null;
  capacity_used_min: number;
  capacity_remaining_min: number;
  blocks: Block[];
}
interface FormatRow { slug: string; label_i18n: Record<string, string> }

const LOCALE_MAP: Record<Lang, string> = { 'pt-BR': 'pt-BR', 'en-US': 'en-US', 'es-LATAM': 'es' };

export default function AdminAgendaVivaPanel({ lang = 'pt-BR' }: { lang?: Lang }) {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [formats, setFormats] = useState<Record<string, Record<string, string>>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [dragKey, setDragKey] = useState<{ eventId: string; index: number } | null>(null);

  const toast = (msg: string, kind: 'success' | 'error' = 'success') => (window as any).toast?.(msg, kind);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 300); return; }
    setError(false);
    const [{ data: agenda, error: err }, { data: fmtRows }] = await Promise.all([
      sb.rpc('get_geral_agenda_viva', { p_limit_events: 2 }),
      sb.from('agenda_block_formats').select('slug, label_i18n').eq('active', true),
    ]);
    if (err) { setError(true); setLoading(false); return; }
    if (Array.isArray(fmtRows)) {
      const map: Record<string, Record<string, string>> = {};
      for (const r of fmtRows) map[r.slug] = r.label_i18n || {};
      setFormats(map);
    }
    setEvents((agenda?.events ?? []) as EventRow[]);
    setLoading(false);
  }, [getSb]);

  useEffect(() => { load(); }, [load]);

  const fmtLabel = (slug: string): string => formats[slug]?.[lang] || formats[slug]?.['pt-BR'] || slug;
  const fmtDate = (iso: string): string => {
    const d = new Date(`${iso}T12:00:00Z`);
    if (Number.isNaN(d.getTime())) return iso;
    return new Intl.DateTimeFormat(LOCALE_MAP[lang], { weekday: 'long', day: '2-digit', month: 'long', timeZone: 'UTC' }).format(d);
  };

  const after = async () => { await load(); window.dispatchEvent(new CustomEvent('agenda:changed')); };
  const run = async (key: string, fn: () => Promise<any>, okMsg: string) => {
    const sb = getSb(); if (!sb) return;
    setBusy(key);
    try {
      const { data, error: e } = await fn();
      if (e) throw e;
      if (data?.error) { toast(String(data.error), 'error'); return; }
      toast(okMsg);
      await after();
    } catch (err: any) { toast(err?.message || t('comp.agendaViva.errGeneric', 'Erro'), 'error'); }
    finally { setBusy(null); }
  };

  const confirmBlock = (b: Block) =>
    run(b.id, () => getSb().rpc('confirm_agenda_block', { p_block_id: b.id }), t('comp.agendaViva.confirmSuccess', 'Bloco confirmado.'));
  const confirmAll = (ev: EventRow) =>
    run(`all-${ev.id}`, () => getSb().rpc('confirm_event_blocks', { p_event_id: ev.id }), t('comp.agendaViva.confirmAllSuccess', 'Blocos confirmados.'));
  const noShow = (b: Block) => {
    if (!window.confirm(t('comp.agendaViva.confirmNoShow', 'Marcar como no-show? O XP será revogado.'))) return;
    run(b.id, () => getSb().rpc('revoke_agenda_block_xp', { p_block_id: b.id }), t('comp.agendaViva.noShowSuccess', 'Marcado como no-show.'));
  };
  const cancelBlock = (b: Block) => {
    if (!window.confirm(t('comp.agendaViva.confirmCancelBlock', 'Cancelar este bloco?'))) return;
    run(b.id, () => getSb().rpc('cancel_agenda_block', { p_block_id: b.id }), t('comp.agendaViva.cancelBlockSuccess', 'Bloco cancelado.'));
  };

  // Native HTML5 drag reorder: rearrange the local block array, then persist the
  // full ordered id list via reorder_event_blocks.
  const onDrop = async (ev: EventRow, targetIndex: number) => {
    if (!dragKey || dragKey.eventId !== ev.id || dragKey.index === targetIndex) { setDragKey(null); return; }
    const reordered = [...ev.blocks];
    const [moved] = reordered.splice(dragKey.index, 1);
    reordered.splice(targetIndex, 0, moved);
    setDragKey(null);
    setEvents((prev) => prev.map((e) => (e.id === ev.id ? { ...e, blocks: reordered } : e)));
    const sb = getSb(); if (!sb) return;
    setBusy(`reorder-${ev.id}`);
    try {
      const { data, error: e } = await sb.rpc('reorder_event_blocks', { p_event_id: ev.id, p_ordered_ids: reordered.map((b) => b.id) });
      if (e) throw e;
      if (data?.error) { toast(String(data.error), 'error'); await load(); return; }
      toast(t('comp.agendaViva.reorderSuccess', 'Ordem atualizada.'));
      window.dispatchEvent(new CustomEvent('agenda:changed'));
    } catch (err: any) { toast(err?.message || t('comp.agendaViva.errGeneric', 'Erro'), 'error'); await load(); }
    finally { setBusy(null); }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 py-20 justify-center text-[var(--text-muted)]">
        <Loader2 size={16} className="animate-spin" /> <span>{t('comp.agendaViva.loading', 'Carregando…')}</span>
      </div>
    );
  }
  if (error) {
    return (
      <div className="text-center py-16 text-rose-600">
        <p>{t('comp.agendaViva.loadError', 'Erro ao carregar.')}</p>
        <button onClick={load} className="mt-3 inline-flex items-center gap-1 text-sm text-[var(--accent)] hover:underline">
          <RefreshCw size={14} /> {t('comp.agendaViva.retry', 'Tentar novamente')}
        </button>
      </div>
    );
  }

  const hasAnyBlock = events.some((e) => e.blocks.length > 0);

  return (
    <div>
      <header className="mb-4">
        <h1 className="text-xl font-semibold flex items-center gap-2">
          <CalendarClock size={20} className="text-[var(--accent)]" /> {t('comp.agendaViva.adminHeading', 'Agenda Viva — Coordenação')}
        </h1>
        <p className="text-sm text-[var(--text-muted)] mt-1">{t('comp.agendaViva.adminSubtitle', '')}</p>
        <p className="text-xs text-[var(--text-muted)] mt-1">{t('comp.agendaViva.xpHint', '')}</p>
      </header>

      {!hasAnyBlock ? (
        <div className="text-center py-16 text-[var(--text-muted)]">{t('comp.agendaViva.adminEmpty', 'Nenhum bloco reservado.')}</div>
      ) : (
        <div className="space-y-6">
          {events.map((ev) => (
            <section key={ev.id} className="rounded-xl border border-[var(--border)] overflow-hidden">
              <div className="flex items-center justify-between gap-3 px-4 py-3 bg-[var(--bg-subtle)]">
                <div>
                  <div className="font-semibold capitalize">{fmtDate(ev.date)}</div>
                  <div className="text-xs text-[var(--text-muted)]">{ev.capacity_used_min}/90 {t('comp.agendaViva.min', 'min')}</div>
                </div>
                {ev.blocks.some((b) => b.status === 'reserved') && (
                  <button onClick={() => confirmAll(ev)} disabled={busy === `all-${ev.id}`}
                    className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-sm bg-emerald-600 text-white hover:opacity-90 disabled:opacity-60">
                    {busy === `all-${ev.id}` ? <Loader2 size={14} className="animate-spin" /> : <CheckCheck size={14} />}
                    {t('comp.agendaViva.confirmAllCta', 'Confirmar todos')}
                  </button>
                )}
              </div>

              {ev.blocks.length === 0 ? (
                <p className="px-4 py-4 text-sm text-[var(--text-muted)] italic">{t('comp.agendaViva.adminEmpty', 'Nenhum bloco.')}</p>
              ) : (
                <ul className="divide-y divide-[var(--border)]">
                  {ev.blocks.map((b, idx) => (
                    <li key={b.id} draggable
                      onDragStart={() => setDragKey({ eventId: ev.id, index: idx })}
                      onDragOver={(e) => e.preventDefault()}
                      onDrop={() => onDrop(ev, idx)}
                      className={`flex items-center gap-2 px-3 py-2.5 bg-[var(--surface)] ${dragKey?.eventId === ev.id ? 'cursor-grabbing' : ''}`}>
                      <GripVertical size={15} className="text-[var(--text-muted)] cursor-grab shrink-0" />
                      <span className="shrink-0 w-12 text-sm font-bold text-teal tabular-nums">{b.duration_min}<span className="text-[var(--text-muted)] font-normal ml-0.5">{t('comp.agendaViva.min', 'min')}</span></span>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="font-medium truncate">{b.title}</span>
                          {b.status === 'confirmed' && <span className="text-[.6rem] font-bold px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-700">{t('comp.agendaViva.statusConfirmed', 'Confirmado')}</span>}
                          {b.external_guest && <span className="text-[.6rem] font-bold px-1.5 py-0.5 rounded-full bg-orange/15 text-orange">{t('comp.agendaViva.guestBadge', 'Convidado externo')}</span>}
                        </div>
                        <div className="text-xs text-[var(--text-muted)]">
                          {fmtLabel(b.format_slug)} · {b.owner_full_name || b.owner_first_name}
                          {b.guest_name ? ` · ${b.guest_name}` : ''}
                          {b.material_url && (
                            <a href={b.material_url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-0.5 ml-1.5 text-[var(--accent)] hover:underline">
                              <ExternalLink size={11} /> {t('comp.agendaViva.materialLink', 'Material')}
                            </a>
                          )}
                        </div>
                      </div>
                      <div className="flex items-center gap-1 shrink-0">
                        {b.status === 'reserved' ? (
                          <button onClick={() => confirmBlock(b)} disabled={busy === b.id} title={t('comp.agendaViva.confirmCta', 'Confirmar')}
                            className="p-1.5 rounded hover:bg-emerald-50 text-emerald-600 disabled:opacity-50">
                            {busy === b.id ? <Loader2 size={15} className="animate-spin" /> : <Check size={15} />}
                          </button>
                        ) : (
                          <button onClick={() => noShow(b)} disabled={busy === b.id} title={t('comp.agendaViva.noShowCta', 'No-show')}
                            className="p-1.5 rounded hover:bg-amber-50 text-amber-600 disabled:opacity-50">
                            {busy === b.id ? <Loader2 size={15} className="animate-spin" /> : <UserX size={15} />}
                          </button>
                        )}
                        <button onClick={() => cancelBlock(b)} disabled={busy === b.id} title={t('comp.agendaViva.adminCancelCta', 'Cancelar bloco')}
                          className="p-1.5 rounded hover:bg-rose-50 text-rose-500 disabled:opacity-50">
                          <Trash2 size={15} />
                        </button>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          ))}
          <p className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.reorderHint', 'Arraste para reordenar.')}</p>
        </div>
      )}
    </div>
  );
}
