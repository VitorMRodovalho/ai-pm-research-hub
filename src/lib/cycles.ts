import type { SupabaseClient } from '@supabase/supabase-js';

export interface Cycle {
  cycle_code: string;
  cycle_label: string;
  cycle_abbr: string;
  cycle_start: string;
  cycle_end: string | null;
  cycle_color: string;
  sort_order: number;
  is_current: boolean;
}

let _cache: Cycle[] | null = null;

export async function loadCycles(sb?: SupabaseClient): Promise<Cycle[]> {
  if (_cache) return _cache;
  const client = sb || (typeof window !== 'undefined' ? (window as any).navGetSb?.() : null);
  if (!client) return getFallbackCycles();
  const { data } = await client.rpc('list_cycles');
  if (Array.isArray(data) && data.length > 0) {
    _cache = data as Cycle[];
    return _cache;
  }
  return getFallbackCycles();
}

export function getCurrentCycle(cycles: Cycle[]): Cycle | undefined {
  return cycles.find(c => c.is_current) || cycles[cycles.length - 1];
}

export function getCycleMeta(cycles: Cycle[]): Record<string, { label: string; abbr: string; color: string }> {
  const meta: Record<string, { label: string; abbr: string; color: string }> = {};
  for (const c of cycles) {
    meta[c.cycle_code] = { label: c.cycle_label, abbr: c.cycle_abbr, color: c.cycle_color };
  }
  return meta;
}

export function getCycleOrder(cycles: Cycle[]): string[] {
  return cycles.map(c => c.cycle_code);
}

export function getCycleDates(cycles: Cycle[]): Record<string, { start: string; end: string | null }> {
  const dates: Record<string, { start: string; end: string | null }> = {};
  for (const c of cycles) {
    dates[c.cycle_code] = { start: c.cycle_start, end: c.cycle_end };
  }
  return dates;
}

export function getCycleLabels(cycles: Cycle[]): Record<string, string> {
  const labels: Record<string, string> = {};
  for (const c of cycles) {
    labels[c.cycle_code] = c.cycle_label;
  }
  return labels;
}

function getFallbackCycles(): Cycle[] {
  return [
    { cycle_code: 'pilot',   cycle_label: 'Piloto 2024',      cycle_abbr: 'P24', cycle_start: '2024-03-01', cycle_end: '2024-12-31', cycle_color: '#F59E0B', sort_order: 1, is_current: false },
    { cycle_code: 'cycle_1', cycle_label: 'Ciclo 1 (2025/1)', cycle_abbr: 'C1',  cycle_start: '2025-01-01', cycle_end: '2025-06-30', cycle_color: '#3B82F6', sort_order: 2, is_current: false },
    { cycle_code: 'cycle_2', cycle_label: 'Ciclo 2 (2025/2)', cycle_abbr: 'C2',  cycle_start: '2025-07-01', cycle_end: '2025-12-31', cycle_color: '#8B5CF6', sort_order: 3, is_current: false },
    { cycle_code: 'cycle_3', cycle_label: 'Ciclo 3 (2026/1)', cycle_abbr: 'C3',  cycle_start: '2026-01-01', cycle_end: null,          cycle_color: '#10B981', sort_order: 4, is_current: true },
  ];
}
