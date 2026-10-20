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
  // #2593: só o dono do bloco (e manage_event) recebe estes dois
  guest_name?: string | null;
  guest_email?: string | null;
  guest_language?: Lang | null;
  // #2593 fatia 6: membros que apresentam junto; o dono e manage_event recebem com o id
  copresenters?: { member_id: string; name: string }[];
}
interface EventRow {
  id: string;
  date: string;
  time_start: string | null;
  is_past?: boolean;
  capacity_remaining_min: number;
  blocks: Block[];
}
interface FormatRow { slug: string; label_i18n: Record<string, string>; default_duration_min: number }
interface MemberOption { id: string; name: string }

const DURATIONS = [5, 10, 15, 20, 25, 30];
// o menu só oferece o que cabe no que sobra da reunião; o servidor recusa o resto com capacity_exceeded
const fitDurations = (cap: number) => DURATIONS.filter((m) => m <= cap);
const fitDuration = (want: number, cap: number) => {
  const opts = fitDurations(cap);
  return opts.includes(want) ? want : opts.length ? opts[opts.length - 1] : want;
};
const LOCALE_MAP: Record<Lang, string> = { 'pt-BR': 'pt-BR', 'en-US': 'en-US', 'es-LATAM': 'es' };

interface DraftState {
  format_slug: string;
  duration_min: number;
  title: string;
  guest_name: string;
  material_url: string;
  external_guest: boolean;
  guest_email: string;
  // #2593: idioma do convite (decisão do GP: seletor, já com o idioma de quem reserva)
  guest_language: Lang;
  // #2593 fatia 6: coapresentadores membros (até 3); o convidado de fora continua em guest_name
  copresenter_ids: string[];
  // #2593: remover é explícito; campo vazio na edição mantém o valor atual (a RPC usa COALESCE)
  clear_guest?: boolean;
  clear_material?: boolean;
  // marca a primeira tentativa de salvar: o erro do convidado aparece no campo daí em diante
  attempted?: boolean;
}
const emptyDraft = (format_slug: string, duration_min: number, lang: Lang): DraftState => ({
  format_slug, duration_min, title: '', guest_name: '', material_url: '', external_guest: false, guest_email: '',
  guest_language: lang, copresenter_ids: [],
});
const MAX_COPRESENTERS = 3;
const GUEST_LANGS: Lang[] = ['pt-BR', 'en-US', 'es-LATAM'];
const EMAIL_RE = /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$/i;

// `range` mirrors AgendaVivaPublic's prop of the same name — deliberately NOT called `window`,
// which would read as shadowing the global this component uses for events and toasts.
export default function AgendaVivaReservationIsland({ lang = 'pt-BR', range = 'upcoming' }:
  { lang?: Lang; range?: 'upcoming' | 'both' }) {
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
  // #2593 fatia 6: membros ativos para escolher quem apresenta junto, e a busca de cada formulário
  const [members, setMembers] = useState<MemberOption[]>([]);
  const [copQuery, setCopQuery] = useState<Record<string, string>>({});

  const toast = (msg: string, kind: 'success' | 'error' = 'success') => (window as any).toast?.(msg, kind);

  const recomputeGate = useCallback(() => setAllowed(canFor('reserve_agenda_block')), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 300); return; }
    const [{ data: agenda }, { data: fmtRows }] = await Promise.all([
      sb.rpc('get_geral_agenda_viva', { p_limit_events: 2, p_window: range }),
      sb.from('agenda_block_formats').select('slug, label_i18n, default_duration_min').eq('active', true).order('sort_order'),
    ]);
    if (Array.isArray(fmtRows)) setFormats(fmtRows);
    const evs: EventRow[] = (agenda?.events ?? []) as EventRow[];
    setEvents(evs);
    setLoading(false);
    if ((window as any).navGetMember?.()) {
      const { data: memberRows } = await sb.from('public_members').select('id, name').eq('is_active', true).order('name');
      if (Array.isArray(memberRows)) setMembers(memberRows as MemberOption[]);
    }
  }, [getSb, range]);

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
      guest_name_required: 'errGuestNameRequired', guest_email_required: 'errGuestEmailRequired',
      invalid_guest_email: 'errInvalidGuestEmail',
      invalid_copresenter: 'errInvalidCopresenter', too_many_copresenters: 'errTooManyCopresenters',
      guest_name_requires_external: 'errGuestNameRequiresExternal',
    };
    const key = code && map[code] ? map[code] : 'errGeneric';
    return t(`comp.agendaViva.${key}`, 'Algo deu errado. Tente novamente.');
  };

  const ensureDraft = (eventId: string): DraftState => {
    if (drafts[eventId]) return drafts[eventId];
    const first = formats[0];
    const d = emptyDraft(first?.slug || 'insight_rapido', first?.default_duration_min || 5, lang);
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

  // quanto cabe: na reserva nova, o que sobra; na edição, o que sobra mais o próprio bloco (a RPC o exclui da soma)
  const capFor = (eventId: string): number => events.find((ev) => ev.id === eventId)?.capacity_remaining_min ?? 0;
  const editCapFor = (blockId: string): number => {
    const ev = events.find((e) => e.blocks.some((b) => b.id === blockId));
    const own = ev?.blocks.find((b) => b.id === blockId)?.duration_min ?? 0;
    return (ev?.capacity_remaining_min ?? 0) + own;
  };

  // o servidor recusa do mesmo jeito; aqui é só para a mensagem sair antes da ida ao banco
  const guestProblem = (d: DraftState): string | null => {
    if (!d.external_guest || d.clear_guest) return null;
    if (!d.guest_name.trim()) return 'guest_name_required';
    if (!d.guest_email.trim()) return 'guest_email_required';
    if (!EMAIL_RE.test(d.guest_email.trim())) return 'invalid_guest_email';
    return null;
  };

  const reserve = async (eventId: string) => {
    const sb = getSb(); if (!sb) return;
    const d = ensureDraft(eventId);
    if (!d.title.trim()) { toast(t('comp.agendaViva.errTitleRequired', 'Informe um título.'), 'error'); return; }
    const gp = guestProblem(d); if (gp) { setDraft(eventId, { attempted: true }); toast(errMsg(gp), 'error'); return; }
    const dur = fitDuration(d.duration_min, capFor(eventId));
    setBusy(eventId);
    try {
      const { data, error } = await sb.rpc('reserve_agenda_block', {
        p_event_id: eventId, p_format_slug: d.format_slug, p_title: d.title.trim(), p_duration_min: dur,
        p_guest_name: d.external_guest ? d.guest_name.trim() || null : null,
        p_material_url: d.material_url.trim() || null, p_external_guest: d.external_guest,
        p_guest_email: d.external_guest ? d.guest_email.trim() || null : null,
        p_guest_language: d.external_guest ? d.guest_language : null,
        p_copresenter_ids: d.copresenter_ids,
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
      guest_name: b.guest_name || '', material_url: b.material_url || '', external_guest: b.external_guest,
      guest_email: b.guest_email || '', guest_language: b.guest_language || lang,
      copresenter_ids: (b.copresenters || []).map((c) => c.member_id),
    },
  }));
  const cancelEdit = (blockId: string) => setEditing((p) => { const n = { ...p }; delete n[blockId]; return n; });

  const saveEdit = async (blockId: string) => {
    const sb = getSb(); if (!sb) return;
    const d = editing[blockId]; if (!d) return;
    if (!d.title.trim()) { toast(t('comp.agendaViva.errTitleRequired', 'Informe um título.'), 'error'); return; }
    const gp = guestProblem(d); if (gp) { setEdit(blockId, { attempted: true }); toast(errMsg(gp), 'error'); return; }
    const dur = fitDuration(d.duration_min, editCapFor(blockId));
    setBusy(blockId);
    try {
      const { data, error } = await sb.rpc('update_agenda_block', {
        p_block_id: blockId, p_title: d.title.trim(), p_format_slug: d.format_slug, p_duration_min: dur,
        p_guest_name: d.clear_guest || !d.external_guest ? null : d.guest_name.trim() || null,
        p_material_url: d.clear_material ? null : d.material_url.trim() || null,
        p_external_guest: d.clear_guest ? false : d.external_guest,
        p_guest_email: !d.clear_guest && d.external_guest ? d.guest_email.trim() || null : null,
        p_guest_language: !d.clear_guest && d.external_guest ? d.guest_language : null,
        p_clear_guest: !!d.clear_guest, p_clear_material: !!d.clear_material,
        p_copresenter_ids: d.copresenter_ids,
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

  // #813: the edit/cancel UI for a block the user already owns must NOT depend on
  // the (async, fail-closed) capability cache. `is_mine` is server-derived from
  // auth.uid() in get_geral_agenda_viva, so an authenticated owner always sees it
  // even when canFor('reserve_agenda_block') is still false (cache not yet loaded
  // or nav:member not re-fired). Render the island whenever the caller owns a block
  // OR holds the reserve capability; the NEW-reservation form stays gated on `allowed`.
  const ownsAnyBlock = events.some((ev) => ev.blocks.some((b) => b.is_mine));
  if (loading) return null;
  if (!allowed && !ownsAnyBlock) return null; // anon/insufficient → public island already shows a login hint

  const inputCls = 'mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2 text-sm';

  // #2593 fatia 6: nome de quem coapresenta, da lista de membros ou do que a agenda já devolveu
  const nameOf = (id: string): string =>
    members.find((m) => m.id === id)?.name
    || events.flatMap((ev) => ev.blocks).flatMap((b) => b.copresenters || []).find((c) => c.member_id === id)?.name
    || id;
  const fold = (v: string) => v.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

  // `key` separa os ids de cada formulário (um por reunião e um por edição)
  const renderFields = (d: DraftState, set: (patch: Partial<DraftState>) => void, onFmt: (slug: string) => void,
    key: string, cap: number, isEdit = false) => {
    const problem = d.attempted ? guestProblem(d) : null;
    const nameErr = problem === 'guest_name_required';
    const emailErr = problem === 'guest_email_required' || problem === 'invalid_guest_email';
    const ids = { name: `agenda-guest-name-${key}`, email: `agenda-guest-email-${key}`, hint: `agenda-guest-hint-${key}`,
      lang: `agenda-guest-lang-${key}`, cop: `agenda-cop-${key}`, copHint: `agenda-cop-hint-${key}`,
      nameErr: `agenda-guest-name-err-${key}`, emailErr: `agenda-guest-email-err-${key}`, status: `agenda-removal-${key}` };
    const external = d.external_guest && !d.clear_guest;
    const selfId: string | undefined = (window as any).navGetMember?.()?.id;
    const q = copQuery[key] || '';
    const matches = q.trim().length >= 2
      ? members.filter((m) => m.id !== selfId && !d.copresenter_ids.includes(m.id) && fold(m.name).includes(fold(q.trim()))).slice(0, 6)
      : [];
    return (
    <div className="space-y-3">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <label className="block">
          <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fFormat', 'Formato')}</span>
          <select value={d.format_slug} onChange={(e) => onFmt(e.target.value)} className={inputCls}>
            {formats.map((f) => <option key={f.slug} value={f.slug}>{fmtLabel(f.slug)}</option>)}
          </select>
        </label>
        <label className="block">
          <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fDuration', 'Duração')}</span>
          <select value={fitDuration(d.duration_min, cap)} onChange={(e) => set({ duration_min: Number(e.target.value) })} className={inputCls}>
            {fitDurations(cap).map((m) => <option key={m} value={m}>{m} {t('comp.agendaViva.min', 'min')}</option>)}
          </select>
        </label>
      </div>
      <label className="block">
        <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fTitle', 'Título')}</span>
        <input value={d.title} onChange={(e) => set({ title: e.target.value })}
          placeholder={t('comp.agendaViva.fTitlePlaceholder', '')} className={inputCls} maxLength={140} />
      </label>
      {/* #2593 fatia 6: quem apresenta junto é membro, escolhido da lista; o convidado de fora fica no quadro seguinte */}
      <fieldset className="rounded-xl border border-[var(--border)] p-3 space-y-2">
        <legend className="px-1 text-xs font-semibold text-[var(--text-muted)]">{t('comp.agendaViva.fCopresenterLegend', 'Quem apresenta com você (membros)')}</legend>
        {d.copresenter_ids.length > 0 && (
          <ul className="flex flex-wrap gap-1.5">
            {d.copresenter_ids.map((id) => (
              <li key={id} className="inline-flex items-center gap-1 rounded-full bg-teal/10 text-teal pl-2 pr-0.5 py-0.5 text-xs">
                {nameOf(id)}
                <button type="button" onClick={() => set({ copresenter_ids: d.copresenter_ids.filter((x) => x !== id) })}
                  aria-label={`${t('comp.agendaViva.removeCopresenter', 'Remover coapresentador')}: ${nameOf(id)}`}
                  className="min-h-[28px] min-w-[28px] inline-flex items-center justify-center rounded-full hover:bg-teal/20">
                  <X size={12} />
                </button>
              </li>
            ))}
          </ul>
        )}
        {d.copresenter_ids.length < MAX_COPRESENTERS && (
          <label className="block" htmlFor={ids.cop}>
            <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fCopresenterSearch', 'Buscar membro pelo nome')}</span>
            <input id={ids.cop} type="search" autoComplete="off" value={q} maxLength={80} className={inputCls}
              onChange={(e) => setCopQuery((p) => ({ ...p, [key]: e.target.value }))} aria-describedby={ids.copHint} />
          </label>
        )}
        {matches.length > 0 && (
          <ul className="space-y-1" aria-label={t('comp.agendaViva.fCopresenterResults', 'Membros encontrados')}>
            {matches.map((m) => (
              <li key={m.id}>
                <button type="button"
                  onClick={() => { set({ copresenter_ids: [...d.copresenter_ids, m.id] }); setCopQuery((p) => ({ ...p, [key]: '' })); }}
                  className="w-full text-left min-h-[44px] sm:min-h-0 px-3 py-1.5 rounded-lg text-sm hover:bg-[var(--bg-subtle)]">
                  {m.name}
                </button>
              </li>
            ))}
          </ul>
        )}
        <span id={ids.copHint} className="block text-[12px] text-[var(--text-muted)]">
          {t('comp.agendaViva.fCopresenterHint', 'Até 3 membros. Cada um recebe o XP de protagonismo quando o bloco for confirmado, se estiver presente na reunião.')}
        </span>
      </fieldset>
      {/* #2593: nome, marca de externo e e-mail são uma coisa só, o convidado de fora do Núcleo */}
      <fieldset className="rounded-xl border border-[var(--border)] p-3 space-y-2">
        <legend className="px-1 text-xs font-semibold text-[var(--text-muted)]">{t('comp.agendaViva.fGuestLegend', 'Convidado')}</legend>
        <label className="flex items-center gap-2 text-sm cursor-pointer min-h-[44px]">
          <input type="checkbox" checked={d.external_guest} onChange={(e) => set({ external_guest: e.target.checked, clear_guest: false })} className="rounded" />
          <span>{t('comp.agendaViva.fExternalGuest', 'Convidado externo ao núcleo')}</span>
        </label>
        {external && (
          <label className="block" htmlFor={ids.name}>
            <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fGuestExternalName', 'Nome do convidado externo')}</span>
            <input id={ids.name} value={d.guest_name} onChange={(e) => set({ guest_name: e.target.value })}
              placeholder={t('comp.agendaViva.fGuestPlaceholder', '')} className={inputCls} maxLength={120}
              required aria-required aria-invalid={nameErr || undefined}
              aria-describedby={nameErr ? ids.nameErr : undefined} />
            {nameErr && <span id={ids.nameErr} role="alert" className="mt-1 block text-[12px] text-rose-600">{errMsg('guest_name_required')}</span>}
          </label>
        )}
        {external && (
          <label className="block" htmlFor={ids.email}>
            <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fGuestEmail', 'E-mail do convidado')}</span>
            <input id={ids.email} type="email" inputMode="email" autoComplete="off" value={d.guest_email}
              onChange={(e) => set({ guest_email: e.target.value })}
              placeholder={t('comp.agendaViva.fGuestEmailPlaceholder', 'convidado@example.org')} className={inputCls} maxLength={254}
              required aria-required aria-invalid={emailErr || undefined}
              aria-describedby={emailErr ? `${ids.emailErr} ${ids.hint}` : ids.hint} />
            {emailErr && <span id={ids.emailErr} role="alert" className="mt-1 block text-[12px] text-rose-600">{errMsg(problem || undefined)}</span>}
            <span id={ids.hint} className="mt-1 block text-[12px] text-[var(--text-muted)]">
              {t('comp.agendaViva.fGuestEmailHint', 'O convidado recebe o convite por e-mail quando o bloco for confirmado. Guardamos o e-mail até 1 ano após a reunião.')}
            </span>
          </label>
        )}
        {external && (
          <label className="block" htmlFor={ids.lang}>
            <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fGuestLanguage', 'Idioma do convite')}</span>
            <select id={ids.lang} value={d.guest_language} onChange={(e) => set({ guest_language: e.target.value as Lang })} className={inputCls}>
              {GUEST_LANGS.map((l) => (
                <option key={l} value={l}>{t(`comp.agendaViva.lang.${l}`, l)}</option>
              ))}
            </select>
          </label>
        )}
        {isEdit && (d.guest_name || d.external_guest) && !d.clear_guest && (
          <button type="button" onClick={() => set({ clear_guest: true })}
            aria-label={`${t('comp.agendaViva.removeGuest', 'Remover convidado')}${d.guest_name ? `: ${d.guest_name}` : ''}`}
            className="min-h-[44px] sm:min-h-0 px-3 py-1.5 rounded-lg text-xs border border-[var(--border)] text-rose-600 hover:bg-rose-50">
            {t('comp.agendaViva.removeGuest', 'Remover convidado')}
          </button>
        )}
      </fieldset>
      <label className="block">
        <span className="text-xs text-[var(--text-muted)]">{t('comp.agendaViva.fMaterial', 'Material (opcional)')}</span>
        <input value={d.clear_material ? '' : d.material_url} onChange={(e) => set({ material_url: e.target.value, clear_material: false })}
          placeholder={t('comp.agendaViva.fMaterialPlaceholder', 'https://…')} className={inputCls} />
      </label>
      {isEdit && d.material_url && !d.clear_material && (
        <button type="button" onClick={() => set({ clear_material: true })}
          aria-label={t('comp.agendaViva.removeMaterial', 'Remover material')}
          className="min-h-[44px] sm:min-h-0 px-3 py-1.5 rounded-lg text-xs border border-[var(--border)] text-rose-600 hover:bg-rose-50">
          {t('comp.agendaViva.removeMaterial', 'Remover material')}
        </button>
      )}
      {/* região viva sempre montada: o leitor de tela anuncia quando o texto aparece */}
      <p id={ids.status} role="status" className="text-[12px] text-[var(--text-muted)] flex flex-wrap items-center gap-2">
        {isEdit && d.clear_guest && <span>{t('comp.agendaViva.removalGuestPending', 'O convidado será removido ao salvar.')}</span>}
        {isEdit && d.clear_material && <span>{t('comp.agendaViva.removalMaterialPending', 'O material será removido ao salvar.')}</span>}
        {isEdit && (d.clear_guest || d.clear_material) && (
          <button type="button" onClick={() => set({ clear_guest: false, clear_material: false })}
            className="underline text-[var(--accent)] min-h-[44px] sm:min-h-0">
            {t('comp.agendaViva.undoRemoval', 'Desfazer')}
          </button>
        )}
      </p>
    </div>
    );
  };

  return (
    <div className="mb-8 space-y-4">
      <h2 className="text-lg font-bold text-[var(--text-primary)] flex items-center gap-2">
        <CalendarPlus size={18} className="text-orange" />{' '}
        {allowed
          ? t('comp.agendaViva.reserveHeading', 'Reservar um bloco')
          : t('comp.agendaViva.manageHeading', 'Seu bloco')}
      </h2>
      {events.map((ev) => {
        const myBlock = ev.blocks.find((b) => b.is_mine);
        // A past meeting is here only so its owner can still correct their own block (the #1545
        // case: a block reserved under the wrong format). Nothing else on a past card is valid —
        // reserving is refused server-side (`reservation_window_closed`), and offering to DELETE a
        // block that already happened would erase the record of it. So: no card without a block of
        // mine, and no reserve/cancel affordance on the ones that remain.
        if (ev.is_past && !myBlock) return null;
        const draft = drafts[ev.id] || (formats[0] ? emptyDraft(formats[0].slug, formats[0].default_duration_min, lang) : null);
        const isEditing = myBlock && editing[myBlock.id];
        return (
          <div key={ev.id} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
            <div className="flex items-center justify-between mb-3">
              <span className="font-semibold text-[var(--text-primary)] capitalize">{fmtDate(ev.date)}</span>
              <span className="text-xs text-[var(--text-muted)]">
                {ev.is_past
                  ? t('comp.agendaViva.pastMeeting', 'Reunião já realizada')
                  : `${ev.capacity_remaining_min} ${t('comp.agendaViva.min', 'min')} ${t('comp.agendaViva.capacityFree', 'livres')}`}
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
                      (slug) => { const f = formats.find((x) => x.slug === slug); setEdit(myBlock.id, { format_slug: slug, duration_min: f?.default_duration_min ?? editing[myBlock.id].duration_min }); },
                      `edit-${myBlock.id}`, editCapFor(myBlock.id), true)}
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
                      {(myBlock.copresenters?.length ?? 0) > 0 && (
                        <div className="text-xs text-[var(--text-muted)] truncate">
                          {t('comp.agendaViva.withGuest', 'com')} {myBlock.copresenters!.map((c) => c.name).join(', ')}
                        </div>
                      )}
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button onClick={() => startEdit(myBlock)} title={t('comp.agendaViva.editCta', 'Editar')}
                        className="p-1.5 rounded hover:bg-[var(--bg-subtle)] text-[var(--text-muted)]"><Pencil size={15} /></button>
                      {!ev.is_past && (
                        <button onClick={() => cancelReservation(myBlock.id)} disabled={busy === myBlock.id}
                          title={t('comp.agendaViva.cancelReserveCta', 'Cancelar reserva')}
                          className="p-1.5 rounded hover:bg-rose-50 text-rose-500 disabled:opacity-50">
                          {busy === myBlock.id ? <Loader2 size={15} className="animate-spin" /> : <Trash2 size={15} />}
                        </button>
                      )}
                    </div>
                  </div>
                )}
              </div>
            ) : !ev.is_past && allowed && draft && fitDurations(ev.capacity_remaining_min).length === 0 ? (
              <p className="text-sm text-[var(--text-muted)]">{t('comp.agendaViva.errCapacity', 'Capacidade esgotada para esta reunião.')}</p>
            ) : !ev.is_past && allowed && draft ? (
              <>
                {renderFields(drafts[ev.id] || draft, (p) => setDraft(ev.id, p), (slug) => onFormatChange(ev.id, slug), `new-${ev.id}`, ev.capacity_remaining_min)}
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
