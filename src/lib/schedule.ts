/**
 * Schedule config from home_schedule — single source of truth for tribe selection deadline, etc.
 * Used by index pages to pass to HeroSection and TribesSection.
 */
import { getSupabase } from './supabase';

export interface HomeScheduleConfig {
  kickoffAt: string | null;
  platformLabel: string | null;
  recurringEndBrt: string | null;
  recurringStartBrt: string | null;
  recurringWeekday: number | null;
  selectionDeadlineAt: string | null;
}

function normalizeScheduleIso(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : value;
}

function normalizeString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function normalizeNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

export async function getHomeSchedule(): Promise<HomeScheduleConfig | null> {
  try {
    const sb = getSupabase();
    const { data, error } = await sb
      .from('home_schedule')
      .select('kickoff_at, platform_label, recurring_end_brt, recurring_start_brt, recurring_weekday, selection_deadline_at')
      .limit(1)
      .maybeSingle();
    if (error || !data) return null;
    return {
      kickoffAt: normalizeScheduleIso(data.kickoff_at),
      platformLabel: normalizeString(data.platform_label),
      recurringEndBrt: normalizeString(data.recurring_end_brt),
      recurringStartBrt: normalizeString(data.recurring_start_brt),
      recurringWeekday: normalizeNumber(data.recurring_weekday),
      selectionDeadlineAt: normalizeScheduleIso(data.selection_deadline_at),
    };
  } catch {
    return null;
  }
}

export async function getSelectionDeadlineIso(): Promise<string | null> {
  const schedule = await getHomeSchedule();
  return schedule?.selectionDeadlineAt ?? null;
}
