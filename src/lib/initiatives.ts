import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * #625 C2 (D3=C1) — shared initiatives loader, mirror of `lib/chapters.ts`.
 *
 * Reads the V4 initiative registry via the `list_initiatives` RPC (which already
 * exists and is org-scoped + SECURITY DEFINER). Used by /admin/members to drive
 * the "Iniciativa" filter select (and reusable by any other admin surface that
 * needs the canonical initiative list instead of the legacy tribe-only view).
 */
export interface Initiative {
  id: string;                    // uuid — primitive of V4 domain (ADR-0005)
  kind: string;                  // slug: research_tribe | workgroup | congress | committee | study_group | ...
  title: string;
  status: string;                // active | archived | ...
  kind_display_name: string;     // PT-BR catalog label for the kind
}

let _cache: Initiative[] | null = null;

/**
 * Load initiatives from `list_initiatives()` RPC. Cached at module level (the
 * registry changes rarely within a session; a redeploy/reload refreshes it).
 *
 * Pass `sb` for SSR contexts; browser context falls back to `window.navGetSb()`
 * (matches loadChapters pattern). Unlike chapters there is NO hardcoded fallback
 * list — initiatives are dynamic config, so on RPC failure we return an empty
 * list (the filter simply shows no options rather than fabricating entries).
 *
 * @param status optional filter (e.g. 'active') passed straight to the RPC.
 */
export async function loadInitiatives(sb?: SupabaseClient, status: string | null = 'active'): Promise<Initiative[]> {
  if (_cache) return _cache;
  const client = sb || (typeof window !== 'undefined' ? (window as any).navGetSb?.() : null);
  if (!client) return [];
  const { data, error } = await client.rpc('list_initiatives', { p_kind: null, p_status: status });
  if (error || !Array.isArray(data)) return [];
  // list_initiatives RETURNS SETOF jsonb → each row is already the object we want.
  _cache = (data as any[]).map(row => ({
    id: row.id,
    kind: row.kind,
    title: row.title,
    status: row.status,
    kind_display_name: row.kind_display_name || row.kind,
  })) as Initiative[];
  return _cache;
}

/**
 * Reset module-level cache. Use only in tests or when the initiative registry
 * changed mid-session (e.g., an admin just created/archived an initiative).
 */
export function resetInitiativesCache(): void {
  _cache = null;
}
