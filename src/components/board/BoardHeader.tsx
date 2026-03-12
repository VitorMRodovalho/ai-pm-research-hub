import type { Board, BoardI18n } from '../../types/board';

interface Props {
  board: Board;
  itemCount: number;
  totalCount: number;
  canCreate: boolean;
  onCreateClick: () => void;
  i18n: BoardI18n;
}

const SOURCE_BADGE: Record<string, { label: string; color: string }> = {
  trello: { label: '🟦 Trello', color: 'bg-blue-50 text-blue-700' },
  notion: { label: '🟨 Notion', color: 'bg-amber-50 text-amber-700' },
  manual: { label: '✋ Manual', color: 'bg-[var(--surface-base)] text-[var(--text-secondary)]' },
};

export default function BoardHeader({ board, itemCount, totalCount, canCreate, onCreateClick, i18n }: Props) {
  const src = SOURCE_BADGE[board.source] || SOURCE_BADGE.manual;

  return (
    <div className="flex items-center justify-between flex-wrap gap-3">
      <div className="flex items-center gap-3">
        <div>
          <h2 className="text-lg font-extrabold text-[var(--text-primary)]">{board.board_name}</h2>
          <div className="flex items-center gap-2 mt-0.5">
            <span className={`inline-flex items-center px-2 py-0.5 rounded-md text-[10px] font-semibold ${src.color}`}>
              {src.label}
            </span>
            {board.tribe_id && (
              <span className="inline-flex items-center px-2 py-0.5 rounded-md bg-teal-50 text-teal-700 text-[10px] font-semibold">
                Tribo {board.tribe_id}
              </span>
            )}
            <span className="text-[11px] text-[var(--text-muted)]">
              {itemCount === totalCount ? `${totalCount} itens` : `${itemCount} de ${totalCount} itens`}
            </span>
          </div>
        </div>
      </div>

      {canCreate && (
        <button
          onClick={onCreateClick}
          className="px-4 py-2 bg-blue-900 text-white rounded-xl text-[12px] font-bold 
            cursor-pointer hover:bg-blue-800 transition-colors border-0 flex items-center gap-1.5"
        >
          <span className="text-base leading-none">+</span> {i18n.newCard}
          <kbd className="hidden sm:inline ml-1 px-1 py-0.5 bg-white/20 rounded text-[9px] font-mono">N</kbd>
        </button>
      )}
    </div>
  );
}
