import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Lang } from '../i18n/utils';

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

async function rpc<T>(name: string): Promise<T | null> {
  try {
    const { data, error } = await anonClient().rpc(name).abortSignal(AbortSignal.timeout(TIMEOUT_MS));
    return error || data === null || data === undefined ? null : (data as T);
  } catch {
    return null;
  }
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
