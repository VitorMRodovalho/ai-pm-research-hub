// src/components/agenda/AgendaVivaPublic.tsx
// #701 Slice 1 + #812 — public Agenda Viva de Protagonismo, columns-by-date layout.
// Reads get_geral_agenda_viva (anon-OK, layered PII). Each upcoming/past General Meeting is
// a COLUMN (benchmark: UFF "Agendamento de Defesas"): header with date + block count, a 90-min
// capacity bar, and one card per block (title, owner first name, format, duration, status chip).
// Columns sit side-by-side on desktop and stack vertically on mobile (#812 PD-3).
//
// `range` selects the RPC window:
//   'upcoming' (default) — next General Meetings only (the /reunioes-gerais reservation surface).
//   'both'                — last concluded meeting + next ones, a past→future timeline (home).
//
// PII layering (RPC-enforced): anon sees first name + title + format + duration; authenticated
// adds is_mine + material_url; manage_event adds full detail. #812 PD-5 (LGPD): a no_show block
// never exposes the owner's name to the public/ordinary member (owner_first_name comes back null);
// the FE shows a NEUTRAL chip ("Bloco não realizado"), never "did not show up".
//
// Format labels come from the anon-readable agenda_block_formats catalog (label_i18n).
import { useState, useEffect, useCallback } from 'react';
import { Loader2, CalendarDays, ExternalLink, Star, UserPlus, RefreshCw, CheckCircle2 } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';

type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';
type Range = 'upcoming' | 'both';

interface Block {
  id: string;
  format_slug: string;
  title: string;
  duration_min: number;
  status: 'reserved' | 'confirmed' | 'no_show';
  sort_order: number;
  external_guest: boolean;
  owner_first_name: string | null;
  is_mine: boolean;
  material_url?: string | null;
}
interface EventRow {
  id: string;
  title: string;
  date: string;
  time_start: string | null;
  timezone: string | null;
  start_at: string;
  is_past?: boolean;
  capacity_total_min: number;
  capacity_used_min: number;
  capacity_remaining_min: number;
  blocks: Block[];
}
interface AgendaPayload {
  viewer: { is_authenticated: boolean; is_admin: boolean };
  events: EventRow[];
}

const LOCALE_MAP: Record<Lang, string> = { 'pt-BR': 'pt-BR', 'en-US': 'en-US', 'es-LATAM': 'es' };

export default function AgendaVivaPublic({ lang = 'pt-BR', range = 'upcoming' }: { lang?: Lang; range?: Range }) {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const [data, setData] = useState<AgendaPayload | null>(null);
  const [formats, setFormats] = useState<Record<string, Record<string, string>>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 300); return; }
    setError(false);
    const { data: res, error: err } = await sb.rpc('get_geral_agenda_viva', { p_limit_events: 2, p_window: range });
    if (err) { setError(true); setLoading(false); return; }
    setData(res as AgendaPayload);
    setLoading(false);
  }, [getSb, range]);

  // Format catalog (slug → label_i18n) — anon-readable reference data.
  useEffect(() => {
    const sb = getSb();
    if (!sb) return;
    sb.from('agenda_block_formats').select('slug, label_i18n').eq('active', true)
      .then(({ data: rows }: any) => {
        if (!Array.isArray(rows)) return;
        const map: Record<string, Record<string, string>> = {};
        for (const r of rows) map[r.slug] = r.label_i18n || {};
        setFormats(map);
      }).catch(() => {});
  }, [getSb]);

  useEffect(() => {
    load();
    const onMember = () => load();
    // `agenda:changed` is dispatched by the reservation/admin islands after a
    // successful mutation so this read-only timeline refreshes in lockstep.
    window.addEventListener('nav:member', onMember);
    window.addEventListener('agenda:changed', onMember);
    return () => {
      window.removeEventListener('nav:member', onMember);
      window.removeEventListener('agenda:changed', onMember);
    };
  }, [load]);

  const formatLabel = (slug: string): string =>
    formats[slug]?.[lang] || formats[slug]?.['pt-BR'] || slug;

  const fmtColumnDate = (iso: string): string => {
    const d = new Date(`${iso}T12:00:00Z`);
    if (Number.isNaN(d.getTime())) return iso;
    return new Intl.DateTimeFormat(LOCALE_MAP[lang], {
      weekday: 'short', day: '2-digit', month: 'short', timeZone: 'UTC',
    }).format(d);
  };
  const fmtTime = (time: string | null): string => (time ? time.slice(0, 5) : '—');

  // Status chip: text + colour (never colour-only — a11y). Dark text on a light tint keeps
  // contrast ≥ AA in both themes. no_show renders a NEUTRAL label (LGPD PD-5), never "absent".
  const statusChip = (status: Block['status']) => {
    const map: Record<Block['status'], { cls: string; label: string }> = {
      reserved: { cls: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200', label: t('comp.agendaViva.statusReserved', 'Reservado') },
      confirmed: { cls: 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-200', label: t('comp.agendaViva.statusConfirmed', 'Confirmado') },
      no_show: { cls: 'bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200', label: t('comp.agendaViva.statusNotHeld', 'Bloco não realizado') },
    };
    const s = map[status] || map.reserved;
    return <span className={`inline-flex items-center text-[.62rem] font-bold px-1.5 py-0.5 rounded-full ${s.cls}`}>{s.label}</span>;
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 py-20 justify-center text-[var(--text-muted)]">
        <Loader2 size={16} className="animate-spin" />
        <span>{t('comp.agendaViva.loading', 'Carregando a pauta…')}</span>
      </div>
    );
  }
  if (error) {
    return (
      <div className="text-center py-16 text-rose-600">
        <p>{t('comp.agendaViva.loadError', 'Erro ao carregar a Agenda Viva.')}</p>
        <button onClick={load} className="mt-3 inline-flex items-center gap-1 text-sm text-[var(--accent)] hover:underline">
          <RefreshCw size={14} /> {t('comp.agendaViva.retry', 'Tentar novamente')}
        </button>
      </div>
    );
  }

  const events = data?.events ?? [];
  const isAuth = data?.viewer?.is_authenticated ?? false;

  if (events.length === 0) {
    return (
      <div className="text-center py-16 text-[var(--text-muted)]">
        {t('comp.agendaViva.empty', 'Nenhuma Reunião Geral agendada no momento.')}
      </div>
    );
  }

  return (
    <div>
      {/* Columns side-by-side on desktop; stack vertically on mobile (PD-3). */}
      <div
        className="flex flex-col md:flex-row md:flex-wrap gap-4"
        role="list"
        aria-label={t('comp.agendaViva.gridAria', 'Agenda das Reuniões Gerais por data')}
      >
        {events.map((ev) => {
          const pct = ev.capacity_total_min > 0
            ? Math.min(100, Math.round((ev.capacity_used_min / ev.capacity_total_min) * 100)) : 0;
          const full = ev.capacity_remaining_min <= 0;
          return (
            <section
              key={ev.id}
              role="listitem"
              className={`flex-1 md:min-w-[260px] bg-[var(--surface-card)] border rounded-2xl p-4 ${
                ev.is_past ? 'border-[var(--border-subtle)] opacity-90' : 'border-[var(--border-default)]'}`}
            >
              <header className="mb-3">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-1.5 text-[var(--text-primary)] font-bold capitalize">
                    <CalendarDays size={16} className={ev.is_past ? 'text-[var(--text-muted)] shrink-0' : 'text-teal shrink-0'} />
                    {fmtColumnDate(ev.date)}
                  </div>
                  {ev.is_past ? (
                    <span className="inline-flex items-center gap-1 text-[.62rem] font-bold px-1.5 py-0.5 rounded-full bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200">
                      <CheckCircle2 size={10} /> {t('comp.agendaViva.concludedBadge', 'Concluída')}
                    </span>
                  ) : (
                    <span className="text-[.7rem] text-[var(--text-muted)]">{fmtTime(ev.time_start)}</span>
                  )}
                </div>
                <div className="text-[.7rem] text-[var(--text-muted)] mt-1">
                  {(() => {
                    const parts: string[] = [];
                    if (ev.blocks.length > 0) {
                      const label = ev.blocks.length === 1
                        ? t('comp.agendaViva.blockLabelOne', 'bloco')
                        : t('comp.agendaViva.blocksLabel', 'blocos');
                      parts.push(`${ev.blocks.length} ${label}`);
                    } else if (full && !ev.is_past) {
                      parts.push(t('comp.agendaViva.capacityFull', 'Pauta cheia'));
                    }
                    if (!ev.is_past && ev.capacity_remaining_min > 0) {
                      parts.push(`${ev.capacity_remaining_min} ${t('comp.agendaViva.min', 'min')} ${t('comp.agendaViva.capacityFree', 'livres')}`);
                    }
                    return parts.join(' · ') || null;
                  })()}
                </div>
              </header>

              {!ev.is_past && (
                <div className="h-1.5 w-full rounded-full bg-[var(--bg-subtle)] overflow-hidden mb-3" aria-hidden="true">
                  <div className={`h-full rounded-full ${full ? 'bg-amber-500' : 'bg-teal'}`} style={{ width: `${pct}%` }} />
                </div>
              )}

              {ev.blocks.length === 0 ? (
                <p className="text-xs text-[var(--text-muted)] italic py-3">
                  {ev.is_past
                    ? t('comp.agendaViva.columnNoBlocks', 'Sem blocos')
                    : t('comp.agendaViva.blocksEmpty', 'Nenhum bloco reservado ainda — seja o primeiro.')}
                </p>
              ) : (
                <ol className="space-y-2">
                  {ev.blocks.map((b) => (
                    <li key={b.id}
                      className={`rounded-xl border px-3 py-2 ${
                        b.is_mine ? 'border-teal/40 bg-teal/5' : 'border-[var(--border-subtle)] bg-[var(--surface-section-warm)]'}`}>
                      <div className="flex items-start justify-between gap-2">
                        <span className="font-semibold text-sm text-[var(--text-primary)] leading-snug">{b.title}</span>
                        <span className="shrink-0 text-xs font-bold text-teal tabular-nums">
                          {b.duration_min}<span className="text-[var(--text-muted)] font-normal">{t('comp.agendaViva.min', 'min')}</span>
                        </span>
                      </div>
                      <div className="flex flex-wrap items-center gap-1.5 mt-1.5">
                        {statusChip(b.status)}
                        {b.is_mine && (
                          <span className="inline-flex items-center gap-0.5 text-[.6rem] font-bold px-1.5 py-0.5 rounded-full bg-teal/15 text-teal">
                            <Star size={9} /> {t('comp.agendaViva.mineBadge', 'Seu bloco')}
                          </span>
                        )}
                        {b.external_guest && (
                          <span className="inline-flex items-center gap-0.5 text-[.6rem] font-bold px-1.5 py-0.5 rounded-full bg-orange/15 text-orange">
                            <UserPlus size={9} /> {t('comp.agendaViva.guestBadge', 'Convidado externo')}
                          </span>
                        )}
                      </div>
                      <div className="text-[.7rem] text-[var(--text-muted)] mt-1">
                        {formatLabel(b.format_slug)}
                        {b.owner_first_name ? <> · {b.owner_first_name}</> : null}
                      </div>
                      {isAuth && b.material_url && (
                        <a href={b.material_url} target="_blank" rel="noopener noreferrer"
                          className="mt-1.5 inline-flex items-center gap-1 text-xs text-[var(--accent)] hover:underline">
                          <ExternalLink size={12} /> {t('comp.agendaViva.materialLink', 'Material')}
                        </a>
                      )}
                    </li>
                  ))}
                </ol>
              )}
            </section>
          );
        })}
      </div>

      {!isAuth && (
        <p className="text-center text-sm text-[var(--text-muted)] italic pt-4">
          {t('comp.agendaViva.loginHint', 'Entre na plataforma para reservar seu bloco.')}
        </p>
      )}
    </div>
  );
}
