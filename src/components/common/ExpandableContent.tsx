import { useState } from 'react';

interface ExpandableContentProps {
  title: string;
  content: string | null | undefined;
  maxCollapsedLines?: number;
  expandLabel?: string;
  collapseLabel?: string;
}

export function ExpandableContent({
  title,
  content,
  maxCollapsedLines = 3,
  expandLabel = 'Ver mais',
  collapseLabel = 'Ver menos',
}: ExpandableContentProps) {
  const [expanded, setExpanded] = useState(false);

  if (!content) return null;

  const lineHeight = 1.5; // em
  const maxHeight = maxCollapsedLines * lineHeight;
  const needsTruncation = content.split('\n').length > maxCollapsedLines || content.length > maxCollapsedLines * 80;

  return (
    <div className="mt-2 rounded-lg border border-[var(--border-subtle,#e5e7eb)] bg-[var(--surface-section-cool,#f9fafb)] overflow-hidden">
      <div className="px-3 py-2 text-[.65rem] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        {title}
      </div>
      <div
        className="px-3 pb-2 text-sm text-[var(--text-secondary)] whitespace-pre-wrap transition-[max-height] duration-300 overflow-hidden"
        style={!expanded && needsTruncation ? { maxHeight: `${maxHeight}em`, lineHeight: `${lineHeight}em` } : { lineHeight: `${lineHeight}em` }}
      >
        {content}
      </div>
      {needsTruncation && (
        <button
          onClick={() => setExpanded(v => !v)}
          className="w-full px-3 py-1.5 text-xs font-semibold text-[var(--accent,#6366f1)] hover:bg-[var(--surface-hover)] transition-colors border-0 bg-transparent cursor-pointer border-t border-[var(--border-subtle)]"
        >
          {expanded ? collapseLabel : expandLabel}
        </button>
      )}
    </div>
  );
}
