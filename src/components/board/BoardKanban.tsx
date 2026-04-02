import { useMemo } from 'react';
import { SortableContext, verticalListSortingStrategy, useSortable } from '@dnd-kit/sortable';
import { useDroppable } from '@dnd-kit/core';
import { CSS } from '@dnd-kit/utilities';
import { safeChecklist, type BoardItem, type ColumnMeta, type BoardI18n } from '../../types/board';

interface Props {
  columns: ColumnMeta[];
  columnItems: Record<string, BoardItem[]>;
  overColumnId: string | null;
  mode: string;
  permissions: { canMove: boolean; canCurate: boolean; canEditAny: boolean };
  i18n: BoardI18n;
  onCardClick: (item: BoardItem) => void;
  onQuickMove: (itemId: string, newStatus: string) => void;
}

// ── Sortable Card Wrapper ────────────────────────────────────────────────────
function SortableCard({ item, i18n, onClick, onQuickMove, columns, mode, canMove }: {
  item: BoardItem; i18n: BoardI18n;
  onClick: () => void; onQuickMove: (status: string) => void;
  columns: string[]; mode: string; canMove: boolean;
}) {
  const isReadonly = mode === 'readonly';
  const isDraggable = canMove && !isReadonly;

  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id, data: { item }, disabled: !isDraggable,
  });

  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.3 : 1 };

  const cl = safeChecklist(item.checklist);
  const checkDone = cl.filter((c) => c.done).length;
  const checkTotal = cl.length;
  const attachCount = item.attachments?.length ?? 0;
  const isOverdue = item.due_date && new Date(item.due_date) < new Date();
  const isCurationOverdue = item.curation_due_at && new Date(item.curation_due_at) < new Date();
  const nextCol = columns[columns.indexOf(item.status) + 1];
  const showCuration = mode === 'curation' && item.curation_status;

  return (
    <div ref={setNodeRef} style={style}
      className={`group bg-[var(--surface-card)] rounded-xl border border-[var(--border-subtle)] p-3 shadow-sm
        hover:shadow-md hover:border-[var(--border-default)] transition-all duration-150
        ${isDraggable ? 'cursor-grab active:cursor-grabbing' : 'cursor-default'}
        ${isDragging ? 'ring-2 ring-blue-300' : ''}
        ${isCurationOverdue ? 'border-l-4 border-l-red-400' : ''}`}
      {...attributes} {...(isDraggable ? listeners : {})}>

      {/* Submission workflow badge — visible on all modes when curation_status is set */}
      {item.curation_status && item.curation_status !== 'draft' && (
        <div className="flex items-center gap-1.5 mb-1.5">
          <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded-md
            ${item.curation_status === 'approved' || item.curation_status === 'published' ? 'bg-emerald-100 text-emerald-700' :
              item.curation_status === 'review' || item.curation_status === 'peer_review' || item.curation_status === 'leader_review' || item.curation_status === 'curation' ? 'bg-purple-100 text-purple-700' :
              item.curation_status === 'rejected' ? 'bg-red-100 text-red-700' :
              item.curation_status === 'drafting' || item.curation_status === 'author_review' ? 'bg-blue-100 text-blue-700' :
              item.curation_status === 'research' || item.curation_status === 'ideation' ? 'bg-amber-100 text-amber-700' :
              'bg-[var(--surface-section-cool)] text-[var(--text-secondary)]'}`}>
            {item.curation_status === 'approved' ? i18n.approve || 'Approved' :
             item.curation_status === 'published' ? '\u{1F4E2} Publicado' :
             item.curation_status === 'review' ? '\u{1F50D} Em Revisão' :
             item.curation_status === 'peer_review' ? '\u{1F50D} Peer Review' :
             item.curation_status === 'leader_review' ? '\u{1F50D} Rev. Líder' :
             item.curation_status === 'curation' ? '\u{1F50D} Curadoria' :
             item.curation_status === 'rejected' ? '\u274C Descartado' :
             item.curation_status === 'drafting' ? '\u270D\uFE0F Redação' :
             item.curation_status === 'author_review' ? '\u270D\uFE0F Rev. Autores' :
             item.curation_status === 'research' ? '\u{1F4DA} Pesquisa' :
             item.curation_status === 'ideation' ? '\u{1F4A1} Ideação' :
             `\u{1F4DD} ${item.curation_status}`}
          </span>
          {isCurationOverdue && (
            <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-md bg-red-100 text-red-700 animate-pulse">
              {'\u23F0'} SLA Vencido
            </span>
          )}
          {item.curation_due_at && !isCurationOverdue && (
            <span className="text-[9px] text-[var(--text-muted)]">
              SLA: {new Date(item.curation_due_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })}
            </span>
          )}
        </div>
      )}

      {/* Title */}
      <h4 className="text-[12px] font-bold text-[var(--text-primary)] leading-snug line-clamp-2 mb-1.5 pr-4"
        onClick={(e) => { e.stopPropagation(); onClick(); }}
        onPointerDown={(e) => e.stopPropagation()}
        style={{ cursor: 'pointer' }}>
        {item.title}
      </h4>

      {/* Badges row */}
      <div className="flex items-center gap-2 flex-wrap mb-1.5">
        {attachCount > 0 && (
          <span className="text-[10px] text-[var(--text-muted)]">📎 {attachCount}</span>
        )}
        {checkTotal > 0 && (
          <span className={`text-[10px] ${checkDone === checkTotal ? 'text-emerald-600' : 'text-[var(--text-muted)]'}`}>
            ☑️ {checkDone}/{checkTotal}
          </span>
        )}
        {item.due_date && (
          <span className={`text-[10px] font-semibold ${isOverdue ? 'text-red-600' : 'text-[var(--text-muted)]'}`}>
            📅 {new Date(item.due_date).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })}
          </span>
        )}
        {item.source_card_id && (
          <span className="text-[9px] px-1 py-0.5 rounded bg-blue-50 text-blue-500 font-medium">🟦</span>
        )}
        {item.is_portfolio_item && (
          <span className="text-[9px] px-1.5 py-0.5 rounded bg-amber-50 text-amber-700 font-semibold" title="Entregável — aparece no Portfólio Executivo">📊 Portfólio</span>
        )}
      </div>

      {/* Tags */}
      {item.tags?.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-1.5">
          {item.tags.slice(0, 3).map((t) => (
            <span key={t} className="px-1.5 py-0.5 bg-[var(--surface-section-cool)] text-[var(--text-secondary)] rounded text-[9px] font-medium">{t}</span>
          ))}
          {item.tags.length > 3 && <span className="text-[9px] text-[var(--text-muted)]">+{item.tags.length - 3}</span>}
        </div>
      )}

      {/* Assignee + Reviewer */}
      <div className="flex items-center gap-2 mb-1">
        {item.assignee_name && (
          <span className="text-[10px] text-[var(--text-secondary)]">👤 {item.assignee_name}</span>
        )}
        {item.reviewer_name && (
          <span className="text-[10px] text-purple-500">🔍 {item.reviewer_name}</span>
        )}
      </div>

      {/* Quick actions — hidden in readonly mode */}
      {!isReadonly && (
        <div className="flex gap-1.5 pt-1.5 border-t border-[var(--border-subtle)]" onPointerDown={(e) => e.stopPropagation()}>
          <button onClick={onClick}
            className="flex-1 px-2 py-1 rounded-lg bg-[var(--surface-base)] text-[var(--text-secondary)] text-[10px] font-semibold
              border border-[var(--border-default)] hover:bg-[var(--surface-hover)] transition-colors cursor-pointer">
            📝 Abrir
          </button>
          {nextCol && canMove && (
            <button onClick={() => onQuickMove(nextCol)}
              className="flex-1 px-2 py-1 rounded-lg bg-blue-50 text-blue-700 text-[10px] font-semibold
                border border-blue-200 hover:bg-blue-100 transition-colors cursor-pointer">
              → Avançar
            </button>
          )}
        </div>
      )}
    </div>
  );
}

// ── Droppable Column ─────────────────────────────────────────────────────────
function KanbanColumn({ col, items, isOver, i18n, onCardClick, onQuickMove, allColumns, mode, canMove }: {
  col: ColumnMeta; items: BoardItem[]; isOver: boolean;
  i18n: BoardI18n; onCardClick: (item: BoardItem) => void;
  onQuickMove: (itemId: string, status: string) => void;
  allColumns: string[]; mode: string; canMove: boolean;
}) {
  const itemIds = useMemo(() => items.map((i) => i.id), [items]);
  const { setNodeRef } = useDroppable({ id: `col-${col.id}`, data: { columnId: col.id } });

  return (
    <div className="flex flex-col min-w-[250px]">
      <div className="flex items-center gap-2 mb-3">
        <div className={`w-3 h-3 rounded-full ${col.dotColor}`} />
        <h3 className="text-[13px] font-bold text-[var(--text-primary)]">{col.label}</h3>
        <span className={`text-[11px] ${col.badgeBg} ${col.badgeText} px-2 py-0.5 rounded-full font-bold`}>
          {items.length}
        </span>
      </div>

      <SortableContext items={itemIds} strategy={verticalListSortingStrategy}>
        <div ref={setNodeRef} data-column-id={col.id}
          className={`flex-1 space-y-2.5 min-h-[180px] p-2.5 rounded-xl border-2 border-dashed
            transition-all duration-200 ${col.borderColor} ${col.bgColor}
            ${isOver ? 'ring-2 ring-blue-300 border-blue-300 bg-blue-50/40 scale-[1.01]' : ''}`}>
          {items.length === 0 && (
            <div className="flex items-center justify-center h-[100px] text-[var(--text-muted)] text-[11px] font-medium">
              {isOver ? '↓ Soltar aqui' : 'Vazio'}
            </div>
          )}
          {items.map((item) => (
            <SortableCard key={item.id} item={item} i18n={i18n}
              onClick={() => onCardClick(item)}
              onQuickMove={(status) => onQuickMove(item.id, status)}
              columns={allColumns} mode={mode} canMove={canMove} />
          ))}
        </div>
      </SortableContext>
    </div>
  );
}

// ── Main ─────────────────────────────────────────────────────────────────────
export default function BoardKanban({ columns, columnItems, overColumnId, mode, permissions, i18n, onCardClick, onQuickMove }: Props) {
  const allColumnIds = columns.map((c) => c.id);

  return (
    <div className="overflow-x-auto -mx-2 px-2 pb-2 scrollbar-thin">
    <style>{`@media(min-width:1280px){.bk-grid{grid-template-columns:repeat(${columns.length},minmax(0,1fr))!important}}`}</style>
    <div className="bk-grid grid gap-4 grid-cols-1 md:grid-cols-2" style={{ minHeight: 400 }}>
      {columns.map((col) => (
        <KanbanColumn key={col.id} col={col}
          items={columnItems[col.id] || []}
          isOver={overColumnId === col.id}
          i18n={i18n}
          onCardClick={onCardClick}
          onQuickMove={onQuickMove}
          allColumns={allColumnIds}
          mode={mode}
          canMove={permissions.canMove} />
      ))}
    </div>
    </div>
  );
}
