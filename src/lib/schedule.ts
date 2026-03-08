/**
 * Schedule config from home_schedule — single source of truth for tribe selection deadline, etc.
 * Used by index pages to pass to HeroSection and TribesSection.
 */
import { getSupabase } from './supabase';

const FALLBACK_DEADLINE_ISO = '2030-12-31T23:59:59Z'; // far future — avoid blocking if DB empty

export async function getSelectionDeadlineIso(): Promise<string> {
  try {
    const sb = getSupabase();
    const { data, error } = await sb
      .from('home_schedule')
      .select('selection_deadline_at')
      .limit(1)
      .maybeSingle();
    if (error || !data?.selection_deadline_at) return FALLBACK_DEADLINE_ISO;
    return data.selection_deadline_at;
  } catch {
    return FALLBACK_DEADLINE_ISO;
  }
}
