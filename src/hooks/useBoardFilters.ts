/**
 * useBoardFilters.ts — Client-side filtering of board items
 */
import { useState, useMemo, useCallback } from 'react';
import type { BoardItem } from '../types/board';

export interface FilterState {
  search: string;
  assigneeId: string | null;   // null = all
  tags: string[];               // empty = all
  dueDateFilter: 'all' | 'overdue' | 'week' | 'none';
  curationStatus: string | null;
}

export function useBoardFilters(items: BoardItem[]) {
  const [filters, setFilters] = useState<FilterState>({
    search: '',
    assigneeId: null,
    tags: [],
    dueDateFilter: 'all',
    curationStatus: null,
  });

  const setSearch = useCallback((v: string) => setFilters((f) => ({ ...f, search: v })), []);
  const setAssignee = useCallback((v: string | null) => setFilters((f) => ({ ...f, assigneeId: v })), []);
  const setTags = useCallback((v: string[]) => setFilters((f) => ({ ...f, tags: v })), []);
  const setDueDateFilter = useCallback((v: FilterState['dueDateFilter']) => setFilters((f) => ({ ...f, dueDateFilter: v })), []);
  const setCurationStatus = useCallback((v: string | null) => setFilters((f) => ({ ...f, curationStatus: v })), []);
  const clearAll = useCallback(() => setFilters({ search: '', assigneeId: null, tags: [], dueDateFilter: 'all', curationStatus: null }), []);

  const hasActiveFilters = filters.search !== '' || filters.assigneeId !== null
    || filters.tags.length > 0 || filters.dueDateFilter !== 'all' || filters.curationStatus !== null;

  const filtered = useMemo(() => {
    let result = items;

    // Search
    if (filters.search) {
      const q = filters.search.toLowerCase();
      result = result.filter((i) =>
        i.title.toLowerCase().includes(q)
        || i.description?.toLowerCase().includes(q)
        || i.assignee_name?.toLowerCase().includes(q)
        || i.tags.some((t) => t.toLowerCase().includes(q))
      );
    }

    // Assignee
    if (filters.assigneeId) {
      result = result.filter((i) => i.assignee_id === filters.assigneeId);
    }

    // Tags
    if (filters.tags.length > 0) {
      result = result.filter((i) => filters.tags.some((t) => i.tags.includes(t)));
    }

    // Due date
    if (filters.dueDateFilter !== 'all') {
      const now = new Date();
      const weekFromNow = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

      if (filters.dueDateFilter === 'overdue') {
        result = result.filter((i) => i.due_date && new Date(i.due_date) < now);
      } else if (filters.dueDateFilter === 'week') {
        result = result.filter((i) => i.due_date && new Date(i.due_date) <= weekFromNow);
      } else if (filters.dueDateFilter === 'none') {
        result = result.filter((i) => !i.due_date);
      }
    }

    // Curation status
    if (filters.curationStatus) {
      result = result.filter((i) => i.curation_status === filters.curationStatus);
    }

    return result;
  }, [items, filters]);

  // Extract unique tags and assignees for filter dropdowns
  const allTags = useMemo(() => [...new Set(items.flatMap((i) => i.tags))].sort(), [items]);
  const allAssignees = useMemo(() => {
    const map = new Map<string, string>();
    items.forEach((i) => { if (i.assignee_id && i.assignee_name) map.set(i.assignee_id, i.assignee_name); });
    return Array.from(map.entries()).map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
  }, [items]);

  return {
    filters, filtered, hasActiveFilters,
    setSearch, setAssignee, setTags, setDueDateFilter, setCurationStatus, clearAll,
    allTags, allAssignees,
  };
}
