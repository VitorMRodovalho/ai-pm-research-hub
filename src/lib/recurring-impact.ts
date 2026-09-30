// #2524: what an edit to a recurring rule does to the meetings already generated.
// update_recurring_meeting_rule returns it in `future_events`; with p_dry_run=true the same block runs and
// is undone, so the preview the screen shows is the effect, not an estimate.

export type RuleImpact = {
  time: number;
  duration: number;
  link: number;
  title: number;
  timezone: number;
  removed: number;
  created: number;
  kept: { event_id: string; date: string }[];
};

export function impactOf(res: any): RuleImpact | null {
  const f = res?.future_events;
  if (!f) return null;
  const n = (v: unknown) => (typeof v === 'number' ? v : Number(v) || 0);
  return {
    time: n(f.time), duration: n(f.duration), link: n(f.link), title: n(f.title), timezone: n(f.timezone),
    removed: n(f.removed), created: n(f.created),
    kept: Array.isArray(f.kept_with_records) ? f.kept_with_records : [],
  };
}

export function impactTotal(i: RuleImpact | null): number {
  if (!i) return 0;
  return i.time + i.duration + i.link + i.title + i.timezone + i.removed + i.created + i.kept.length;
}

const br = (d: string) => (d && /^\d{4}-\d{2}-\d{2}$/.test(d) ? d.split('-').reverse().join('/') : d);

/** One line per kind of change, only for the kinds that happen. */
export function impactLines(i: RuleImpact, t: (key: string, fallback: string) => string): string[] {
  const out: string[] = [];
  const add = (count: number, key: string, fallback: string) => { if (count > 0) out.push(`${t(key, fallback)}: ${count}`); };
  add(i.time, 'comp.recurringAgenda.impactTime', 'Reuniões com o horário novo');
  add(i.duration, 'comp.recurringAgenda.impactDuration', 'Reuniões com a duração nova');
  add(i.link, 'comp.recurringAgenda.impactLink', 'Reuniões com o link novo');
  add(i.title, 'comp.recurringAgenda.impactTitle', 'Reuniões com o título novo');
  add(i.timezone, 'comp.recurringAgenda.impactTimezone', 'Reuniões com o fuso novo');
  add(i.removed, 'comp.recurringAgenda.impactRemoved', 'Reuniões do dia antigo removidas (sem registro)');
  add(i.created, 'comp.recurringAgenda.impactCreated', 'Reuniões criadas no dia novo');
  if (i.kept.length > 0) {
    out.push(`${t('comp.recurringAgenda.impactKept', 'Reuniões do dia antigo mantidas por já terem registro (revise)')}: ${i.kept.map((k) => br(k.date)).join(', ')}`);
  }
  return out;
}
