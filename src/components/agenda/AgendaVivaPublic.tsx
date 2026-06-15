// src/components/agenda/AgendaVivaPublic.tsx
// #701 Slice 1 — public Agenda Viva de Protagonismo timeline.
// Reads get_geral_agenda_viva (anon-OK, layered PII): renders the next General
// Meetings, each with a 90-min capacity bar and the reserved/confirmed blocks.
// Anon sees first name + format + duration only; authenticated additionally sees
// the material link and which block is theirs. No PII for anon (RPC enforces it).
//
// Format labels come from the anon-readable agenda_block_formats catalog
// (label_i18n), not the i18n dictionary, so admin-tunable formats stay canonical.
import { useState, useEffect, useCallback } from 'react';
import { Loader2, CalendarDays, Clock, ExternalLink, Star, UserPlus, RefreshCw } from 'lucide-react';
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

export default function AgendaVivaPublic({ lang = 'pt-BR' }: { lang?: Lang }) {
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
    const { data: res, error: err } = await sb.rpc('get_geral_agenda_viva', { p_limit_events: 2 });
    if (err) { setError(true); setLoading(false); return; }
    setData(res as AgendaPayload);
    setLoading(false);
  }, [getSb]);

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

  const fmtDate = (iso: string): string => {
    const d = new Date(`${iso}T12:00:00Z`);
    if (Number.isNaN(d.getTime())) return iso;
    return new Intl.DateTimeFormat(LOCALE_MAP[lang], {
      weekday: 'long', day: '2-digit', month: 'long', timeZone: 'UTC',
    }).format(d);
  };
  const fmtTime = (time: string | null): string => (time ? time.slice(0, 5) : '—');

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
    <div className="space-y-6">
      {events.map((ev) => {
        const pct = ev.capacity_total_min > 0
          ? Math.min(100, Math.round((ev.capacity_used_min / ev.capacity_total_min) * 100)) : 0;
        const full = ev.capacity_remaining_min <= 0;
        return (
          <section key={ev.id} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-5">
            <header className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-4">
              <div>
                <div className="flex items-center gap-2 text-[var(--text-primary)] font-bold text-lg capitalize">
                  <CalendarDays size={18} className="text-teal shrink-0" />
                  {fmtDate(ev.date)}
                </div>
                <div className="flex items-center gap-1.5 text-sm text-[var(--text-muted)] mt-0.5">
                  <Clock size={14} /> {fmtTime(ev.time_start)} · {ev.timezone || 'America/Sao_Paulo'}
                </div>
              </div>
              <div className="text-right shrink-0">
                <div className="text-xs uppercase tracking-wider text-[var(--text-muted)] mb-1">
                  {t('comp.agendaViva.capacityLabel', 'Capacidade')}
                </div>
                <div className="text-sm font-semibold text-[var(--text-primary)]">
                  {full ? (
                    <span className="text-amber-600">{t('comp.agendaViva.capacityFull', 'Pauta cheia')}</span>
                  ) : (
                    <>{ev.capacity_remaining_min} {t('comp.agendaViva.min', 'min')} {t('comp.agendaViva.capacityFree', 'livres')}</>
                  )}
                </div>
              </div>
            </header>

            <div className="h-2 w-full rounded-full bg-[var(--bg-subtle)] overflow-hidden mb-4" aria-hidden="true">
              <div className={`h-full rounded-full ${full ? 'bg-amber-500' : 'bg-teal'}`} style={{ width: `${pct}%` }} />
            </div>

            {ev.blocks.length === 0 ? (
              <p className="text-sm text-[var(--text-muted)] italic py-3">
                {t('comp.agendaViva.blocksEmpty', 'Nenhum bloco reservado ainda — seja o primeiro.')}
              </p>
            ) : (
              <ol className="space-y-2">
                {ev.blocks.map((b) => (
                  <li key={b.id}
                    className={`flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3 rounded-xl border px-3 py-2.5 ${
                      b.is_mine ? 'border-teal/40 bg-teal/5' : 'border-[var(--border-subtle)] bg-[var(--surface-section-warm)]'}`}>
                    <span className="shrink-0 inline-flex items-center justify-center w-12 text-sm font-bold text-teal tabular-nums">
                      {b.duration_min}<span className="text-[var(--text-muted)] font-normal ml-0.5">{t('comp.agendaViva.min', 'min')}</span>
                    </span>
                    <div className="flex-1 min-w-0">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <span className="font-semibold text-[var(--text-primary)] truncate">{b.title}</span>
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
                      <div className="text-xs text-[var(--text-muted)] mt-0.5">
                        {formatLabel(b.format_slug)} · {b.owner_first_name}
                        {b.status === 'confirmed' && (
                          <span className="ml-1.5 text-emerald-600 font-medium">· {t('comp.agendaViva.statusConfirmed', 'Confirmado')}</span>
                        )}
                      </div>
                    </div>
                    {isAuth && b.material_url && (
                      <a href={b.material_url} target="_blank" rel="noopener noreferrer"
                        className="shrink-0 inline-flex items-center gap-1 text-xs text-[var(--accent)] hover:underline">
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

      {!isAuth && (
        <p className="text-center text-sm text-[var(--text-muted)] italic pt-2">
          {t('comp.agendaViva.loginHint', 'Entre na plataforma para reservar seu bloco.')}
        </p>
      )}
    </div>
  );
}
