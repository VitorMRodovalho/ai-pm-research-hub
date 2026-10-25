import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Lang } from '../i18n/utils';
import type { ImpactData } from '../components/islands/ImpactPageIsland';

/**
 * #2553 PR 2: as leituras públicas da home, no servidor, com a chave anônima (o que o visitante pode ver).
 *
 * Cada loader devolve null quando a leitura falha, e a seção então diz que o bloco está indisponível ou some.
 * Nenhum número, rótulo ou link de reserva é escrito aqui: a fonte é o banco (decisões D3, D9 e cursos, GP 20/10/2026).
 * Prazo curto em cada chamada, para que um banco lento (#2758) não segure a página.
 */
const TIMEOUT_MS = 2000;

function anonClient(): SupabaseClient {
  return createClient(import.meta.env.PUBLIC_SUPABASE_URL, import.meta.env.PUBLIC_SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
  });
}

async function rpcOnce<T>(name: string): Promise<T | null> {
  try {
    const { data, error } = await anonClient().rpc(name).abortSignal(AbortSignal.timeout(TIMEOUT_MS));
    return error || data === null || data === undefined ? null : (data as T);
  } catch {
    return null;
  }
}

// Duas seções da home leem a mesma RPC (as linhas, na lista e na agenda). Uma leitura boa vale 60 s no módulo, e uma
// leitura em voo é compartilhada; falha não fica guardada, para a próxima requisição tentar de novo.
const CACHE_MS = 60 * 1000;
const cache = new Map<string, { at: number; value: Promise<unknown> }>();

async function rpc<T>(name: string): Promise<T | null> {
  const hit = cache.get(name);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.value as Promise<T | null>;
  const value = rpcOnce<T>(name);
  cache.set(name, { at: Date.now(), value });
  const result = await value;
  if (result === null) cache.delete(name);
  return result;
}

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const shortLang = (lang: Lang) => (lang === 'en-US' ? 'en' : lang === 'es-LATAM' ? 'es' : 'pt');

// ── Metas (exec_portfolio_health) ────────────────────────────────────────────────────────────────────────────────
export type GoalUnit = 'count' | 'percent' | 'hours';
export interface HomeGoal {
  key: string;
  label: string;
  /** null quando o cálculo não devolveu número: a meta continua na tela, como "dado indisponível". */
  current: number | null;
  target: number | null;
  unit: GoalUnit;
}

// D9: nenhuma meta sai da tela. Toda linha que a RPC devolve vira um item, sem filtro por valor: um filtro
// aqui seria exatamente o que esconderia uma meta atrasada no dia em que o cálculo dela quebrasse.
export async function loadHomeGoals(lang: Lang): Promise<HomeGoal[] | null> {
  const rows = await rpc<unknown[]>('exec_portfolio_health');
  if (!Array.isArray(rows)) return null;
  const l = shortLang(lang);
  const goals = rows
    .map((r) => (r ?? {}) as Record<string, any>)
    .sort((a, b) => (Number(a.display_order) || 0) - (Number(b.display_order) || 0))
    .map((r, i) => ({
      key: String(r.metric_key ?? `meta-${i + 1}`),
      label: String(r.label?.[l] ?? r.label?.pt ?? r.metric_key ?? ''),
      current: isNum(r.current) ? r.current : null,
      target: isNum(r.target) && r.target > 0 ? r.target : null,
      unit: (['percent', 'hours'].includes(r.unit) ? r.unit : 'count') as GoalUnit,
    }));
  return goals.length ? goals : null;
}

/** atingida = igual ao alvo; superada = acima; atrás = abaixo (a barra mostra o real); sem número = indisponível. */
export function goalState(g: Pick<HomeGoal, 'current' | 'target'>): 'surpassed' | 'met' | 'behind' | 'unavailable' {
  if (g.current === null || g.target === null) return 'unavailable';
  return g.current > g.target ? 'surpassed' : g.current === g.target ? 'met' : 'behind';
}

// ── Cursos da trilha (get_trail_courses) ─────────────────────────────────────────────────────────────────────────
export type CourseTier = 'core' | 'specialty' | 'complementary' | 'master';
export interface PublicCourse {
  code: string;
  name: string;
  tier: CourseTier;
  url: string;
  isTrail: boolean;
  freeFor: 'everyone' | 'pmi_members' | null;
}

export async function loadTrailCourses(): Promise<PublicCourse[] | null> {
  const rows = await rpc<unknown[]>('get_trail_courses');
  if (!Array.isArray(rows)) return null;
  const courses = rows
    .map((r) => r as Record<string, any>)
    .filter((r) => typeof r.code === 'string' && typeof r.name === 'string' && /^https:\/\//.test(String(r.url ?? ''))
      && ['core', 'specialty', 'complementary', 'master'].includes(r.tier))
    .map((r) => ({
      code: r.code as string,
      name: r.name as string,
      tier: r.tier as CourseTier,
      url: r.url as string,
      isTrail: r.is_trail === true,
      freeFor: r.free_for === 'everyone' || r.free_for === 'pmi_members' ? r.free_for : null,
    }));
  return courses.length ? courses : null;
}

// ── Mural PMI-CPMAI (get_public_cpmai_wall) ──────────────────────────────────────────────────────────────────────
export interface CpmaiWallEntry {
  name: string;
  certifiedYear: number | null;
  credlyUrl: string;
}

export async function loadCpmaiWall(): Promise<CpmaiWallEntry[] | null> {
  const rows = await rpc<unknown[]>('get_public_cpmai_wall');
  if (!Array.isArray(rows)) return null;
  return rows
    .map((r) => r as Record<string, any>)
    .filter((r) => typeof r.name === 'string' && /^https:\/\/(www\.)?credly\.com\//i.test(String(r.credly_url ?? '')))
    .map((r) => ({
      name: r.name as string,
      certifiedYear: isNum(r.certified_year) ? r.certified_year : null,
      credlyUrl: r.credly_url as string,
    }));
}

/** O ano corrente em Brasília, o mesmo que as metas usam como janela. */
export function currentYearBrt(now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-US', { timeZone: 'America/Sao_Paulo', year: 'numeric' }).format(now);
}

// ── Linhas de pesquisa (get_public_research_lines, DB-3) ─────────────────────────────────────────────────────────
export interface ResearchLineSlot { day_of_week: number; time_start: string; time_end: string | null }
export interface ResearchLine {
  id: number;
  name: string;
  quadrant: string;
  quadrantName: string;
  description: string;
  deliverables: string[];
  slots: ResearchLineSlot[];
  members: number;
  capacity: number;
}

const pickText = (v: unknown, l: string): string => {
  const o = v as Record<string, unknown> | null;
  const own = o?.[l];
  const pt = o?.pt;
  return typeof own === 'string' && own.trim() ? own.trim() : typeof pt === 'string' ? pt.trim() : '';
};
const pickList = (v: unknown, l: string): string[] => {
  const o = v as Record<string, unknown> | null;
  const own = o?.[l];
  const list = Array.isArray(own) && own.length ? own : o?.pt;
  return (Array.isArray(list) ? list : []).filter((x): x is string => typeof x === 'string' && x.trim() !== '');
};

export async function loadResearchLines(lang: Lang): Promise<ResearchLine[] | null> {
  const rows = await rpc<unknown[]>('get_public_research_lines');
  if (!Array.isArray(rows)) return null;
  const l = shortLang(lang);
  return rows
    .map((r) => (r ?? {}) as Record<string, any>)
    .filter((r) => Number.isInteger(r.tribe_id))
    .map((r) => ({
      id: r.tribe_id as number,
      name: pickText(r.name_i18n, l),
      quadrant: String(r.quadrant ?? ''),
      quadrantName: pickText(r.quadrant_name_i18n, l),
      description: pickText(r.description_i18n, l),
      deliverables: pickList(r.deliverables_i18n, l),
      slots: Array.isArray(r.slots) ? (r.slots as ResearchLineSlot[]) : [],
      members: isNum(r.members) ? r.members : 0,
      capacity: isNum(r.capacity) ? r.capacity : 0,
    }))
    .sort((a, b) => a.id - b.id);
}

// ── Campo de atuação de cada linha (get_public_line_fields; vazio = sem filtro por campo) ─────────────────────────
export interface LineField { tribeId: number; verticalId: string; verticalTitle: string }

export async function loadLineFields(): Promise<LineField[]> {
  const rows = await rpc<unknown[]>('get_public_line_fields');
  if (!Array.isArray(rows)) return [];
  return rows
    .map((r) => (r ?? {}) as Record<string, any>)
    .filter((r) => Number.isInteger(r.tribe_id) && typeof r.vertical_id === 'string' && typeof r.vertical_title === 'string')
    .map((r) => ({ tribeId: r.tribe_id, verticalId: r.vertical_id, verticalTitle: r.vertical_title }));
}

/** Os campos de atuação (verticais ativas), para o filtro mostrar também campo ainda sem linha. */
export async function loadVerticals(): Promise<{ id: string; title: string }[]> {
  const rows = await rpc<unknown[]>('get_public_verticals');
  if (!Array.isArray(rows)) return [];
  return rows
    .map((r) => (r ?? {}) as Record<string, any>)
    .filter((r) => typeof r.id === 'string' && typeof r.title === 'string')
    .map((r) => ({ id: r.id, title: r.title }));
}

// ── Quem faz, em contagem (get_public_home_team) e trilha (get_public_trail_summary) ─────────────────────────────
export type HomeTeam = Record<'management' | 'line_leaders' | 'initiative_leaders' | 'curators' | 'hub_members' | 'chapter_focal_points' | 'researchers', number>;
const TEAM_KEYS = ['management', 'line_leaders', 'initiative_leaders', 'curators', 'hub_members', 'chapter_focal_points', 'researchers'] as const;

export async function loadHomeTeam(): Promise<HomeTeam | null> {
  const data = await rpc<Record<string, unknown>>('get_public_home_team');
  if (!data || typeof data !== 'object') return null;
  if (!TEAM_KEYS.every((k) => isNum(data[k]))) return null;
  return Object.fromEntries(TEAM_KEYS.map((k) => [k, data[k] as number])) as HomeTeam;
}

export interface TrailSummary { population: number; trailCourses: number; completedAll: number; avgPct: number }

export async function loadTrailSummary(): Promise<TrailSummary | null> {
  const d = await rpc<Record<string, unknown>>('get_public_trail_summary');
  if (!d || ![d.population, d.trail_courses, d.completed_all, d.avg_pct].every(isNum)) return null;
  return { population: d.population as number, trailCourses: d.trail_courses as number, completedAll: d.completed_all as number, avgPct: d.avg_pct as number };
}

// ── Capítulos: ano de entrada e sede (get_public_chapter_entries) ────────────────────────────────────────────────
export interface ChapterEntry { code: string; entryYear: number | null; isHost: boolean }

export async function loadChapterEntries(): Promise<ChapterEntry[]> {
  const rows = await rpc<unknown[]>('get_public_chapter_entries');
  if (!Array.isArray(rows)) return [];
  return rows
    .map((r) => (r ?? {}) as Record<string, any>)
    .filter((r) => typeof r.display_code === 'string')
    .map((r) => ({ code: r.display_code, entryYear: isNum(r.entry_year) ? r.entry_year : null, isHost: r.is_host === true }));
}

// ── Produção: o item mais recente de cada formato ────────────────────────────────────────────────────────────────
export interface LatestOutput { title: string; date: string; context: string; href: string; external: boolean; count: number }

export async function loadLatestWebinar(): Promise<LatestOutput | null> {
  const rows = await rpc<unknown[]>('get_public_webinars');
  if (!Array.isArray(rows)) return null;
  const done = rows
    .map((r) => (r ?? {}) as Record<string, any>)
    .filter((r) => r.status === 'completed' && typeof r.title === 'string' && /^https:\/\//.test(String(r.youtube_url ?? '')))
    .sort((a, b) => String(b.scheduled_at).localeCompare(String(a.scheduled_at)));
  const w = done[0];
  return w ? { title: w.title, date: String(w.scheduled_at), context: String(w.tribe_name ?? ''), href: w.youtube_url, external: true, count: done.length } : null;
}

export async function loadLatestEpisode(): Promise<LatestOutput | null> {
  const d = await rpc<Record<string, any>>('get_public_podcast_episodes');
  const eps = Array.isArray(d?.episodes) ? (d!.episodes as Record<string, any>[]) : [];
  const e = eps.filter((x) => typeof x?.title === 'string').sort((a, b) => String(b.published_at).localeCompare(String(a.published_at)))[0];
  return e ? { title: e.title, date: String(e.published_at), context: String(e.series ?? ''), href: '/podcast', external: false, count: isNum(d?.total) ? d!.total : eps.length } : null;
}

export async function loadLatestPost(lang: Lang): Promise<LatestOutput | null> {
  try {
    const { data, error } = await anonClient().from('blog_posts')
      .select('slug, title, published_at')
      .eq('status', 'published')
      .order('published_at', { ascending: false })
      .limit(1)
      .abortSignal(AbortSignal.timeout(TIMEOUT_MS));
    const p = !error && Array.isArray(data) ? (data[0] as Record<string, any> | undefined) : undefined;
    if (!p || typeof p.slug !== 'string') return null;
    const title = typeof p.title === 'string' ? p.title : String(p.title?.[lang] ?? p.title?.['pt-BR'] ?? '');
    return title ? { title, date: String(p.published_at), context: '', href: `/blog/${p.slug}`, external: false, count: 0 } : null;
  } catch {
    return null;
  }
}

// ── Impacto do /about (get_public_impact_data), no servidor (PR4 A6, GP 25/10/2026) ──────────────────────────────
// O /about chega com os números no HTML, como a home: quem lê sem JavaScript (buscador, prévia de link) vê a página.
// O HTML leva só o que a página mostra: cada campo é copiado pelo nome, e uma chave nova da RPC só chega à página
// passando por aqui. Resposta fora do formato devolve null, e a página busca no navegador, como fazia antes.
const IMPACT_COUNTERS = ['chapters', 'active_members', 'tribes', 'articles_published', 'impact_hours'] as const;

const isText = (v: unknown): v is string => typeof v === 'string';
const optText = (v: unknown): string => (isText(v) ? v : '');
const rowsOf = (v: unknown): Record<string, any>[] | null =>
  Array.isArray(v) && v.every((x) => x !== null && typeof x === 'object') ? (v as Record<string, any>[]) : null;

export async function loadImpactData(): Promise<ImpactData | null> {
  const d = await rpc<Record<string, any>>('get_public_impact_data');
  if (!d || typeof d !== 'object' || !IMPACT_COUNTERS.every((k) => isNum(d[k]))) return null;
  const pubs = rowsOf(d.recent_publications);
  const tribes = rowsOf(d.tribes_summary);
  const chapters = rowsOf(d.chapters_summary);
  const timeline = rowsOf(d.timeline);
  if (!pubs || !tribes || !chapters || !timeline) return null;
  if (!tribes.every((t) => Number.isInteger(t.id) && isText(t.name) && isNum(t.member_count))) return null;
  if (!chapters.every((c) => isText(c.chapter) && (c.member_count === null || isNum(c.member_count)))) return null;
  if (!timeline.every((t) => isText(t.year) && isText(t.title)) || !pubs.every((p) => isText(p.title))) return null;
  return {
    chapters: d.chapters,
    active_members: d.active_members,
    tribes: d.tribes,
    articles_published: d.articles_published,
    impact_hours: d.impact_hours,
    impact_hours_since: isNum(d.impact_hours_since) ? d.impact_hours_since : null,
    recent_publications: pubs.map((p) => ({
      title: p.title, platform: optText(p.platform), publication_date: optText(p.publication_date), external_url: optText(p.external_url),
    })),
    tribes_summary: tribes.map((t) => ({ id: t.id, name: t.name, quadrant_name: optText(t.quadrant_name), member_count: t.member_count })),
    chapters_summary: chapters.map((c) => ({ chapter: c.chapter, member_count: c.member_count })),
    timeline: timeline.map((t) => ({ year: t.year, title: t.title, description: optText(t.description) })),
  };
}
