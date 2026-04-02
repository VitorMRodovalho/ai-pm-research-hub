import { useState, useMemo } from 'react';
import { safeChecklist, COLUMN_PRESETS, getColumnLabel, type BoardItem, type BoardI18n } from '../../types/board';

interface Props {
  items: BoardItem[];
  i18n: BoardI18n;
  onOpenDetail: (item: BoardItem) => void;
}

type GroupBy = 'tag' | 'assignee' | 'status';

export default function GroupedListView({ items, i18n, onOpenDetail }: Props) {
  const [groupBy, setGroupBy] = useState<GroupBy>('tag');
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());

  const groups = useMemo(() => {
    const map = new Map<string, BoardItem[]>();

    items.forEach((item) => {
      let keys: string[];
      switch (groupBy) {
        case 'tag':
          keys = item.tags?.length ? item.tags : ['(sem tag)'];
          break;
        case 'assignee':
          keys = item.assignments?.length
            ? item.assignments.map(a => a.name)
            : item.assignee_name ? [item.assignee_name] : ['(sem responsável)'];
          break;
        case 'status':
          keys = [getColumnLabel(item.status)];
          break;
        default:
          keys = ['—'];
      }
      keys.forEach((key) => {
        if (!map.has(key)) map.set(key, []);
        map.get(key)!.push(item);
      });
    });

    return Array.from(map.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }, [items, groupBy]);

  const toggleGroup = (key: string) => {
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key); else next.add(key);
      return next;
    });
  };

  return (
    <div>
      {/* Group selector */}
      <div className="flex items-center gap-2 mb-4">
        <span className="text-[11px] text-[var(--text-secondary)]">Agrupar por:</span>
        {(['tag', 'assignee', 'status'] as GroupBy[]).map((g) => (
          <button key={g} onClick={() => setGroupBy(g)}
            className={`px-2 py-1 rounded-md text-[10px] font-semibold cursor-pointer border-0 transition-all
              ${groupBy === g
                ? 'bg-blue-100 text-blue-700'
                : 'bg-[var(--surface-section-cool)] text-[var(--text-muted)] hover:text-[var(--text-secondary)]'
              }`}>
            {g === 'tag' ? 'Tag' : g === 'assignee' ? 'Responsável' : 'Status'}
          </button>
        ))}
      </div>

      {/* Groups */}
      <div className="space-y-3">
        {groups.map(([key, groupItems]) => (
          <div key={key} className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-subtle)] overflow-hidden">
            <button onClick={() => toggleGroup(key)}
              className="w-full flex items-center justify-between px-4 py-2.5 bg-[var(--surface-section-cool)] hover:bg-[var(--surface-hover)]
                cursor-pointer border-0 text-left transition-colors">
              <span className="text-[12px] font-bold text-[var(--text-primary)]">
                {collapsed.has(key) ? '▸' : '▾'} {key}
              </span>
              <span className="text-[10px] text-[var(--text-muted)] font-semibold">{groupItems.length} cards</span>
            </button>
            {!collapsed.has(key) && (
              <div className="divide-y divide-[var(--border-subtle)]">
                {groupItems.map((item) => {
                  const assignees = item.assignments?.length
                    ? item.assignments.map(a => a.name).join(', ')
                    : item.assignee_name || '—';
                  const _cl = safeChecklist(item.checklist);
                  const checkDone = _cl.filter(c => c.done).length;
                  const checkTotal = _cl.length;

                  return (
                    <div key={item.id}
                      onClick={() => onOpenDetail(item)}
                      className="flex items-center gap-3 px-4 py-2 hover:bg-[var(--surface-hover)] cursor-pointer transition-colors">
                      <input type="checkbox" checked={item.status === 'done'}
                        readOnly className="w-3.5 h-3.5 accent-emerald-500 pointer-events-none" />
                      <span className="flex-1 text-[12px] text-[var(--text-primary)] truncate font-medium">
                        {item.is_mirror && '🔗 '}{item.title}
                      </span>
                      <span className="text-[10px] text-[var(--text-muted)] w-24 truncate text-right">{assignees}</span>
                      <span className={`px-1.5 py-0.5 rounded text-[9px] font-bold
                        ${COLUMN_PRESETS[item.status]?.badgeBg ?? 'bg-gray-100'}
                        ${COLUMN_PRESETS[item.status]?.badgeText ?? 'text-gray-600'}`}>
                        {getColumnLabel(item.status)}
                      </span>
                      <span className="text-[10px] text-[var(--text-muted)] w-16 text-right">
                        {item.forecast_date || item.due_date || '—'}
                      </span>
                      {checkTotal > 0 && (
                        <span className="text-[10px] text-[var(--text-muted)] w-10 text-right">{checkDone}/{checkTotal}</span>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        ))}
      </div>

      {groups.length === 0 && (
        <div className="text-center py-8 text-[var(--text-muted)] text-[13px]">{i18n.empty || 'No cards found'}</div>
      )}
    </div>
  );
}
