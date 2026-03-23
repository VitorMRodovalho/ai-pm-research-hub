export type BoardViewMode = 'kanban' | 'table' | 'list' | 'calendar' | 'timeline' | 'activities';

interface Props {
  current: BoardViewMode;
  onChange: (mode: BoardViewMode) => void;
}

const VIEWS: { mode: BoardViewMode; icon: string; label: string }[] = [
  { mode: 'kanban', icon: '📋', label: 'Kanban' },
  { mode: 'table', icon: '📊', label: 'Tabela' },
  { mode: 'list', icon: '📑', label: 'Lista' },
  { mode: 'calendar', icon: '📅', label: 'Calendário' },
  { mode: 'timeline', icon: '📈', label: 'Timeline' },
  { mode: 'activities', icon: '☑️', label: 'Atividades' },
];

export default function ViewToggle({ current, onChange }: Props) {
  return (
    <div className="flex gap-0.5 bg-[var(--surface-section-cool)] rounded-lg p-0.5">
      {VIEWS.map((v) => (
        <button key={v.mode} onClick={() => onChange(v.mode)}
          className={`px-2.5 py-1 rounded-md text-[11px] font-semibold cursor-pointer border-0 transition-all
            ${current === v.mode
              ? 'bg-[var(--surface-card)] text-[var(--text-primary)] shadow-sm'
              : 'bg-transparent text-[var(--text-muted)] hover:text-[var(--text-secondary)]'
            }`}>
          {v.icon} {v.label}
        </button>
      ))}
    </div>
  );
}
