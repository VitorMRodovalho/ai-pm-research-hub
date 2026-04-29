import type { SupabaseClient } from '@supabase/supabase-js';

export interface Chapter {
  chapter_code: string;          // canonical: GO, CE, DF, MG, RS, ...
  display_code: string;          // PMI-GO, PMI-CE, ... (for matching members.chapter)
  legal_name: string;
  state: string;
  country: string;               // ISO-3166-1 alpha-2 (BR default)
  logo_url: string | null;
  is_contracting: boolean;
  display_order: number | null;
}

let _cache: Chapter[] | null = null;

/**
 * Load active chapters from `get_active_chapters()` RPC. Cached at module level
 * (1h conceptual TTL handled at SSR build cycle — no explicit expiry needed since
 * chapter list changes very rarely and a redeploy refreshes everything).
 *
 * Pass `sb` for SSR contexts (Astro components, edge functions). Browser context
 * falls back to `window.navGetSb()` (matches loadCycles pattern).
 *
 * Always returns at least the fallback list — never throws.
 */
export async function loadChapters(sb?: SupabaseClient): Promise<Chapter[]> {
  if (_cache) return _cache;
  const client = sb || (typeof window !== 'undefined' ? (window as any).navGetSb?.() : null);
  if (!client) return getFallbackChapters();
  const { data, error } = await client.rpc('get_active_chapters');
  if (error || !Array.isArray(data) || data.length === 0) return getFallbackChapters();
  _cache = data as Chapter[];
  return _cache;
}

/**
 * Reset module-level cache. Use only in tests or when you know chapter
 * registry changed mid-session (e.g., admin just added/removed a chapter).
 */
export function resetChaptersCache(): void {
  _cache = null;
}

/**
 * Sync read for inline `<script>` blocks (Astro components) that injected the
 * chapter list via `<script id="chapters-data" type="application/json">`.
 * Returns fallback if DOM element not found or malformed.
 */
export function getChaptersFromDOM(elementId = 'chapters-data'): Chapter[] {
  if (typeof document === 'undefined') return getFallbackChapters();
  try {
    const el = document.getElementById(elementId);
    if (!el) return getFallbackChapters();
    const parsed = JSON.parse(el.textContent || '[]');
    if (Array.isArray(parsed) && parsed.length > 0) return parsed as Chapter[];
  } catch {
    /* fall through */
  }
  return getFallbackChapters();
}

/**
 * Returns ordered list of `display_code` strings (e.g., ['PMI-GO', 'PMI-CE', ...]).
 * Use for `<select>` `<option>` rendering and for sorting groups by chapter.
 */
export function getChapterDisplayCodes(chapters: Chapter[]): string[] {
  return chapters.map(c => c.display_code);
}

/**
 * Returns map of display_code → logo_url for fast lookup in render loops.
 * Chapters without logo_url get a `null` value (caller decides fallback).
 */
export function getChapterLogos(chapters: Chapter[]): Record<string, string | null> {
  const map: Record<string, string | null> = {};
  for (const c of chapters) map[c.display_code] = c.logo_url;
  return map;
}

/**
 * Returns map of display_code → legal_name (e.g., for tooltips, accessibility).
 */
export function getChapterLegalNames(chapters: Chapter[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (const c of chapters) map[c.display_code] = c.legal_name;
  return map;
}

/**
 * Returns count of contracting chapters (those with formal cooperation agreement signed).
 * Used in i18n-rendered phrases like "X chapters PMI Brasil".
 */
export function getContractingCount(chapters: Chapter[]): number {
  return chapters.filter(c => c.is_contracting).length;
}

/**
 * Fallback list — used when RPC is unavailable (e.g., build-time SSG without
 * Supabase reachable, network failure, or first render before script ran).
 *
 * Mirrors the 5 chapters seeded in chapter_registry as of p83 (CE/DF/GO/MG/RS).
 * Will need updating if/when Ivan Lourenço (PMI-GO Pres) confirms expansion to 15
 * and the new chapters are seeded into the registry.
 */
function getFallbackChapters(): Chapter[] {
  return [
    { chapter_code: 'GO', display_code: 'PMI-GO', legal_name: 'Seção Goiânia, Goiás — Brasil do Project Management Institute (PMI Goiás)', state: 'Goiás',             country: 'BR', logo_url: '/assets/logos/pmigo.png', is_contracting: true,  display_order: 1 },
    { chapter_code: 'CE', display_code: 'PMI-CE', legal_name: 'PMI Fortaleza Ceará Brazil Chapter',                                            state: 'Ceará',             country: 'BR', logo_url: '/assets/logos/pmice.jpg', is_contracting: false, display_order: 2 },
    { chapter_code: 'DF', display_code: 'PMI-DF', legal_name: 'Seção Distrito Federal — Brasil do Project Management Institute',              state: 'Distrito Federal',  country: 'BR', logo_url: '/assets/logos/pmidf.png', is_contracting: false, display_order: 3 },
    { chapter_code: 'MG', display_code: 'PMI-MG', legal_name: 'Project Management Institute Brazil Minas Gerais Chapter',                     state: 'Minas Gerais',      country: 'BR', logo_url: '/assets/logos/pmimg.png', is_contracting: false, display_order: 4 },
    { chapter_code: 'RS', display_code: 'PMI-RS', legal_name: 'Seção Rio Grande do Sul — Brasil do Project Management Institute',             state: 'Rio Grande do Sul', country: 'BR', logo_url: '/assets/logos/pmirs.png', is_contracting: false, display_order: 5 },
  ];
}
