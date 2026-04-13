import { useState, useEffect, useMemo } from 'react';

export interface Artifact {
  id: string;
  title: string;
  description: string | null;
  status: string;
  baseline_date: string | null;
  forecast_date: string | null;
  actual_completion_date: string | null;
  variance_days: number | null;
  health: 'completed' | 'on_track' | 'at_risk' | 'delayed' | 'no_baseline';
  tribe_id: number;
  initiative_id: string | null;
  tribe_name: string;
  leader_name: string;
  legacy_tags: string[];
  unified_tags: { name: string; label: string; color: string }[] | null;
  checklist_total: number;
  checklist_done: number;
  quarter: string;
  baseline_month: string;
}

export interface TribeSummary {
  tribe_id: number;
  initiative_id: string | null;
  tribe_name: string;
  leader: string;
  total: number;
  completed: number;
  on_track: number;
  at_risk: number;
  delayed: number;
  no_baseline: number;
  next_deadline: string | null;
  checklist_pct: number;
}

export interface TypeBreakdown {
  type: string;
  label: string;
  color: string;
  count: number;
}

export interface MonthBreakdown {
  month: string;
  count: number;
  tribes: number[];
}

export interface PortfolioSummary {
  total_artifacts: number;
  completed: number;
  on_track: number;
  at_risk: number;
  delayed: number;
  no_baseline: number;
  avg_variance_days: number | null;
  checklist_total: number;
  checklist_done: number;
  pct_with_baseline: number;
}

export interface PortfolioData {
  cycle: number;
  generated_at: string;
  summary: PortfolioSummary;
  artifacts: Artifact[];
  by_tribe: TribeSummary[];
  by_type: TypeBreakdown[];
  by_month: MonthBreakdown[];
}

export interface PortfolioFilters {
  tribe: number | null;
  initiative: string | null;
  type: string | null;
  status: string | null;
  health: string | null;
  search: string;
  quarter: string | null;
  month: string | null;
}

const EMPTY_FILTERS: PortfolioFilters = {
  tribe: null, initiative: null, type: null, status: null, health: null,
  search: '', quarter: null, month: null,
};

function getSb() {
  return (window as any).navGetSb?.();
}

export function usePortfolio(cycle = 3) {
  const [data, setData] = useState<PortfolioData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filters, setFilters] = useState<PortfolioFilters>(EMPTY_FILTERS);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      // Wait for supabase
      let sb = getSb();
      let retries = 0;
      while (!sb && retries < 20) {
        await new Promise(r => setTimeout(r, 200));
        sb = getSb();
        retries++;
      }
      if (!sb) { setError('Supabase indisponível'); setLoading(false); return; }
      const { data: d, error: e } = await sb.rpc('get_portfolio_dashboard', { p_cycle: cycle });
      if (cancelled) return;
      if (e) { setError(e.message); setLoading(false); return; }
      setData(d);
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [cycle]);

  const filtered = useMemo(() => {
    if (!data?.artifacts) return [];
    return data.artifacts.filter((a: Artifact) => {
      if (filters.initiative && a.initiative_id !== filters.initiative) return false;
      if (filters.tribe && a.tribe_id !== filters.tribe) return false;
      if (filters.type && !a.unified_tags?.some(t => t.name === filters.type)) return false;
      if (filters.status && a.status !== filters.status) return false;
      if (filters.health && a.health !== filters.health) return false;
      if (filters.quarter && a.quarter !== filters.quarter) return false;
      if (filters.month && a.baseline_month !== filters.month) return false;
      if (filters.search) {
        const s = filters.search.toLowerCase();
        if (!a.title.toLowerCase().includes(s) && !a.leader_name?.toLowerCase().includes(s)) return false;
      }
      return true;
    });
  }, [data, filters]);

  const clearFilters = () => setFilters(EMPTY_FILTERS);

  const hasActiveFilters = Object.values(filters).some(v => v !== null && v !== '');

  return { data, filtered, filters, setFilters, clearFilters, hasActiveFilters, loading, error };
}
