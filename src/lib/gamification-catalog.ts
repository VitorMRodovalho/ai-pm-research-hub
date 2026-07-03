// #1087 wave 2 — shared client helpers over get_gamification_rules_catalog().
// ADR-0081 Pattern 47 extended to the frontend: no screen repeats a rule value;
// every displayed number derives from this catalog (rules + champion criteria +
// level thresholds). One fetch per page, cached on window so Astro inline
// scripts and React islands share the same promise.

export interface CatalogRule {
  slug: string;
  pillar: string;
  display_name_i18n: Record<string, string> | null;
  description_i18n: Record<string, string> | null;
  base_points: number;
  bonus_per_criterion: number | null;
  cap_points: number | null;
  on_time_bonus_points: number | null;
  trigger_source: string;
  effective_from: string;
}

export interface CatalogCriterion {
  surface: string;
  slug: string;
  display_name_i18n: Record<string, string> | null;
  description_i18n: Record<string, string> | null;
  sort_order: number;
}

export interface LevelThreshold {
  slug: string;
  emoji: string;
  min_points: number;
  max_points: number | null;
}

export interface GamificationCatalog {
  rules: CatalogRule[];
  champion_criteria: CatalogCriterion[];
  level_thresholds: LevelThreshold[];
}

export interface LevelInfo {
  slug: string;
  emoji: string;
  nextSlug: string | null;
  ptsToNext: number;
  pctInLevel: number;
  min: number;
  max: number | null;
}

/** Pillar emoji chrome — single copy (consumed by ScoringInfoPopover + gamification.astro). */
export const PILLAR_EMOJI: Record<string, string> = {
  presenca: '📅', trilha: '🧭', certificacoes: '🏅', producao: '🏗️',
  curadoria: '📚', champions: '🏆', protagonismo: '🎤',
};

/**
 * Fetch the rules catalog once per page (member-only RPC — callers must only
 * invoke after the member session is confirmed). Cached promise on window so
 * concurrent islands don't duplicate the call.
 */
export function getCatalog(sb: any): Promise<GamificationCatalog> {
  const w = window as any;
  if (!w.__GAM_CATALOG_PROMISE) {
    w.__GAM_CATALOG_PROMISE = sb
      .rpc('get_gamification_rules_catalog')
      .then(({ data, error }: any) => {
        if (error) throw error;
        const cat = (typeof data === 'string' ? JSON.parse(data) : data) as GamificationCatalog;
        w.__GAM_CATALOG = cat;
        window.dispatchEvent(new CustomEvent('gam:catalog', { detail: cat }));
        return cat;
      })
      .catch((e: any) => {
        // Reset so a later (post-login) caller can retry.
        delete w.__GAM_CATALOG_PROMISE;
        throw e;
      });
  }
  return w.__GAM_CATALOG_PROMISE;
}

/** Localize a *_i18n jsonb from the DB (same fallback chain as profile.astro). */
export function localizeI18n(obj: Record<string, string> | null | undefined, lang: string, fallback = ''): string {
  if (!obj) return fallback;
  return obj[lang] || obj['pt-BR'] || fallback;
}

/**
 * Human XP label for a rule, derived only from catalog fields.
 * base — flat value; base–cap — variable (per-criterion bonus or capped);
 * on-time bonus is annotated by the caller (it needs an i18n label).
 */
export function ruleXpRange(rule: CatalogRule): string {
  const base = rule.base_points ?? 0;
  const cap = rule.cap_points;
  const bonus = rule.bonus_per_criterion ?? 0;
  if (cap != null && cap > base) return `${base}–${cap}`;
  if (bonus > 0) return `${base}+`;
  return `${base}`;
}

/** Min–max base_points range across a pillar's rules (points-legend chips). */
export function pillarXpRange(rules: CatalogRule[]): string {
  const pts = rules.map((r) => Number(r.base_points) || 0);
  if (!pts.length) return '0';
  const min = Math.min(...pts);
  const max = Math.max(...pts);
  return min === max ? `+${max}` : `${min}–${max}`;
}

/** Group active rules by pillar preserving catalog order (pillar, base desc). */
export function rulesByPillar(catalog: GamificationCatalog): Array<{ pillar: string; rules: CatalogRule[] }> {
  const order: string[] = [];
  const grouped: Record<string, CatalogRule[]> = {};
  for (const r of catalog.rules || []) {
    if (!grouped[r.pillar]) {
      grouped[r.pillar] = [];
      order.push(r.pillar);
    }
    grouped[r.pillar].push(r);
  }
  return order.map((pillar) => ({ pillar, rules: grouped[pillar] }));
}

/** Compute the member level from the catalog's level_thresholds (SSOT). */
export function getLevelInfo(thresholds: LevelThreshold[], pts: number): LevelInfo | null {
  const tiers = (thresholds || []).slice().sort((a, b) => a.min_points - b.min_points);
  if (!tiers.length) return null;
  let idx = tiers.findIndex((t) => pts >= t.min_points && (t.max_points == null || pts <= t.max_points));
  // No exact match: above every closed range → highest tier; below the first → lowest.
  if (idx === -1) idx = pts >= tiers[tiers.length - 1].min_points ? tiers.length - 1 : 0;
  const tier = tiers[idx];
  const next = tiers[idx + 1] || null;
  const range = tier.max_points != null ? tier.max_points - tier.min_points : 0;
  const progress = pts - tier.min_points;
  return {
    slug: tier.slug,
    emoji: tier.emoji,
    nextSlug: next ? next.slug : null,
    ptsToNext: next ? Math.max(next.min_points - pts, 0) : 0,
    pctInLevel: range > 0 ? Math.min(Math.round((progress / range) * 100), 100) : 100,
    min: tier.min_points,
    max: tier.max_points,
  };
}

/** Localized display name of a champion criterion slug for a surface. */
export function criterionLabel(catalog: GamificationCatalog | null, surface: string, slug: string, lang: string): string {
  const hit = (catalog?.champion_criteria || []).find((c) => c.surface === surface && c.slug === slug);
  return hit ? localizeI18n(hit.display_name_i18n, lang, slug) : slug;
}

export interface ChampionAward {
  id: string;
  surface: string;
  context_kind: string;
  context_id: string;
  criteria_met: string[];
  justification: string;
  points_awarded: number;
  awarded_by: string | null;
  awarded_by_name: string | null;
  created_at: string;
}

/**
 * #1087 wave 2 (G4) — champion attribution for any member visible to the caller.
 * champions_awarded is org-readable by authenticated (ADR-0081: the champion
 * ledger is auditable by design); awarder names resolve via public_members.
 */
export async function fetchChampionAttribution(sb: any, memberId: string): Promise<ChampionAward[]> {
  const { data: rows, error } = await sb
    .from('champions_awarded')
    .select('id, surface, context_kind, context_id, criteria_met, justification, points_awarded, awarded_by, created_at')
    .eq('recipient_id', memberId)
    .eq('status', 'active')
    .order('created_at', { ascending: false });
  if (error) throw error;
  const list = rows || [];
  const awarderIds = [...new Set(list.map((r: any) => r.awarded_by).filter(Boolean))];
  const names: Record<string, string> = {};
  if (awarderIds.length) {
    const { data: ppl } = await sb.from('public_members').select('id, name').in('id', awarderIds);
    (ppl || []).forEach((p: any) => { names[p.id] = p.name; });
  }
  return list.map((r: any) => ({ ...r, awarded_by_name: r.awarded_by ? names[r.awarded_by] || null : null }));
}
