import { useState, useMemo } from 'react';

interface Section {
  id: string;
  section_number: string;
  title_pt: string;
  title_en: string | null;
  parent_section_id: string | null;
  sort_order: number;
  page_start: number | null;
  page_end: number | null;
}

interface Props {
  sections: Section[];
  crs: any[];
  t: (key: string, fallback?: string) => string;
  onSwitchToCr: (crNumber: string) => void;
}

export default function ManualBrowser({ sections, crs, t, onSwitchToCr }: Props) {
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  const toggle = (id: string) => {
    setExpanded(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  // Build CR count per section
  const crCountMap = useMemo(() => {
    const map = new Map<string, number>();
    for (const cr of crs) {
      const ids: string[] = cr.manual_section_ids || [];
      for (const sid of ids) {
        map.set(sid, (map.get(sid) || 0) + 1);
      }
    }
    return map;
  }, [crs]);

  // Build tree: top-level + children
  const topLevel = useMemo(() =>
    sections.filter(s => !s.parent_section_id).sort((a, b) => a.sort_order - b.sort_order),
  [sections]);

  const childrenOf = useMemo(() => {
    const map = new Map<string, Section[]>();
    for (const s of sections) {
      if (s.parent_section_id) {
        if (!map.has(s.parent_section_id)) map.set(s.parent_section_id, []);
        map.get(s.parent_section_id)!.push(s);
      }
    }
    for (const arr of map.values()) arr.sort((a, b) => a.sort_order - b.sort_order);
    return map;
  }, [sections]);

  const pageLabel = (s: Section) => {
    if (!s.page_start) return '';
    return s.page_start === s.page_end
      ? `${t('governance.page', 'pág.')} ${s.page_start}`
      : `${t('governance.page', 'pág.')} ${s.page_start}-${s.page_end}`;
  };

  const crBadge = (sectionId: string) => {
    const count = crCountMap.get(sectionId);
    if (!count) return null;
    return (
      <span className="ml-2 inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-[9px] font-bold bg-amber-100 text-amber-700">
        {count} CR
      </span>
    );
  };

  const renderSection = (s: Section, depth: number) => {
    const children = childrenOf.get(s.id) || [];
    const hasChildren = children.length > 0;
    const isOpen = expanded.has(s.id);
    const indent = depth * 20;

    return (
      <div key={s.id}>
        <div
          className="flex items-center justify-between py-2 px-3 hover:bg-[var(--surface-hover)] transition-colors rounded-lg cursor-pointer"
          style={{ paddingLeft: `${12 + indent}px` }}
          onClick={() => toggle(s.id)}
        >
          <div className="flex items-center gap-2 min-w-0">
            {hasChildren ? (
              <span className="text-[10px] text-[var(--text-muted)] w-3">{isOpen ? '▼' : '▶'}</span>
            ) : (
              <span className="text-[10px] text-[var(--text-muted)] w-3">{(s as any).content_pt ? (isOpen ? '▼' : '▶') : '·'}</span>
            )}
            <span className="text-xs font-bold text-navy">{s.section_number}</span>
            <span className="text-sm text-[var(--text-primary)] truncate">{s.title_pt}</span>
            {crBadge(s.id)}
          </div>
          <span className="text-[10px] text-[var(--text-muted)] whitespace-nowrap ml-2">{pageLabel(s)}</span>
        </div>
        {isOpen && (s as any).content_pt && !hasChildren && (
          <div className="mx-3 mb-2 px-4 py-2 rounded-lg bg-[var(--surface-section-cool)] text-xs text-[var(--text-secondary)] whitespace-pre-wrap max-h-[200px] overflow-y-auto" style={{ marginLeft: `${12 + indent + 20}px` }}>
            {(s as any).content_pt}
          </div>
        )}
        {isOpen && children.map(child => renderSection(child, depth + 1))}
      </div>
    );
  };

  return (
    <div className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] overflow-hidden">
      <div className="px-5 py-3.5 border-b border-[var(--border-default)] flex items-center justify-between">
        <div>
          <h2 className="text-sm font-bold text-navy">{t('governance.manual_tab', 'Manual')} R2</h2>
          <p className="text-xs text-[var(--text-muted)]">33 {t('governance.section', 'seções').toLowerCase()}s · 22 páginas</p>
        </div>
        <a
          href="https://www.canva.com/design/DAG1Nc3jhC4/gWGhQCJyv7axeCbKozD1gg/view"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-xs font-semibold text-navy hover:bg-[var(--surface-hover)] no-underline transition-colors"
        >
          📄 {t('governance.view_pdf', 'Ver PDF Original')}
        </a>
      </div>
      <div className="py-1">
        {topLevel.map(s => renderSection(s, 0))}
      </div>
    </div>
  );
}
