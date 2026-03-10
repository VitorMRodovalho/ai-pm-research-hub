/**
 * Schedule config from home_schedule — single source of truth for tribe selection deadline, etc.
 * Used by index pages to pass to HeroSection and TribesSection.
 */
import { getSupabase } from './supabase';

function normalizeScheduleIso(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : value;
}

export async function getSelectionDeadlineIso(): Promise<string | null> {
  try {
    const sb = getSupabase();
    const { data, error } = await sb
      .from('home_schedule')
      .select('selection_deadline_at')
      .limit(1)
      .maybeSingle();
    if (error) return null;
    return normalizeScheduleIso(data?.selection_deadline_at);
  } catch {
    return null;
  }
}
