// #2609 — apresentação pública da tribo com uma fonte só: descrição e entregáveis vêm de
// initiatives.description_i18n / deliverables_i18n, o horário vem da regra recorrente
// (tribe_meeting_slots), tudo pela RPC get_tribe_public_profiles.
import type { Lang } from '../../i18n/utils';

export interface MeetingSlot { day_of_week: number; time_start: string; time_end: string | null }
export interface TribePublicProfile {
  tribe_id: number;
  description_i18n: Record<string, string> | null;
  deliverables_i18n: Record<string, string[]> | null;
  slots: MeetingSlot[] | null;
}

export const langCode = (lang: Lang | string): 'pt' | 'en' | 'es' =>
  lang === 'en-US' ? 'en' : lang === 'es-LATAM' ? 'es' : 'pt';

export const dateLocale = (lang: Lang | string): string =>
  lang === 'en-US' ? 'en-US' : lang === 'es-LATAM' ? 'es-419' : 'pt-BR';

/** Texto na língua pedida; sem tradução, cai no português. */
export function profileDescription(p: TribePublicProfile | null | undefined, lang: Lang | string): string {
  const d = p?.description_i18n;
  const pick = (v: unknown) => (typeof v === 'string' ? v.trim() : '');
  return pick(d?.[langCode(lang)]) || pick(d?.pt);
}

export function profileDeliverables(p: TribePublicProfile | null | undefined, lang: Lang | string): string[] {
  const d = p?.deliverables_i18n;
  const own = d?.[langCode(lang)];
  const list = Array.isArray(own) && own.length ? own : d?.pt;
  return (Array.isArray(list) ? list : []).filter(x => typeof x === 'string' && x.trim() !== '');
}

const hhmm = (t: string | null) => (t ?? '').slice(0, 5);
const weekdayFormats = new Map<string, Intl.DateTimeFormat>();

/** "seg. 21:00–22:00 · qui. 19:00–20:30", com o dia abreviado na língua da página. */
export function formatMeetingSlots(slots: MeetingSlot[] | null | undefined, lang: Lang | string): string {
  if (!slots?.length) return '';
  const locale = dateLocale(lang);
  let fmt = weekdayFormats.get(locale);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat(locale, { weekday: 'short', timeZone: 'UTC' });
    weekdayFormats.set(locale, fmt);
  }
  // 04/01/2026 é domingo: day_of_week 0..6 cai no dia certo da semana.
  return slots.map(s => {
    const day = fmt.format(new Date(Date.UTC(2026, 0, 4 + s.day_of_week)));
    return s.time_end ? `${day} ${hhmm(s.time_start)}–${hhmm(s.time_end)}` : `${day} ${hhmm(s.time_start)}`;
  }).join(' · ');
}
