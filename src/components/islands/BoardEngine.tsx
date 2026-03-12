/**
 * BoardEngine.tsx — Main orchestrator component (Astro Island)
 *
 * Usage:
 *   <BoardEngine client:load boardId="..." />
 *   <BoardEngine client:load domainKey="communication" />
 *   <BoardEngine client:load tribeId={6} domainKey="research_delivery" />
 */
import { useState, useMemo, useCallback } from 'react';
import { DndContext, DragOverlay, closestCorners, PointerSensor, TouchSensor, KeyboardSensor, useSensor, useSensors } from '@dnd-kit/core';
import type { DragStartEvent, DragEndEvent, DragOverEvent } from '@dnd-kit/core';

import type { BoardEngineProps, BoardItem, BoardI18n } from '../../types/board';
import { DEFAULT_I18N, getColumnMeta } from '../../types/board';
import { useBoard } from '../../hooks/useBoard';
import { useBoardMutations } from '../../hooks/useBoardMutations';
import { useBoardFilters } from '../../hooks/useBoardFilters';
import { useBoardPermissions } from '../../hooks/useBoardPermissions';

import BoardHeader from '../board/BoardHeader';
import BoardFilters from '../board/BoardFilters';
import BoardKanban from '../board/BoardKanban';
import CardDetail from '../board/CardDetail';
import CardCreate from '../board/CardCreate';
import ToastContainer from '../board/ToastContainer';

export default function BoardEngine(props: BoardEngineProps) {
  const i18n: BoardI18n = { ...DEFAULT_I18N, ...props.i18n };
  const mode = props.mode ?? 'default';

  // ── Data layer ──
  const { board, items: rawItems, loading, error, refetch } = useBoard(props);
  const [items, setItems] = useState<BoardItem[]>([]);
  const permissions = useBoardPermissions(board);

  // Sync rawItems → local state (for optimistic updates)
  useState(() => { /* initial */ });
  useMemo(() => { setItems(rawItems); }, [rawItems]);

  const mutations = useBoardMutations(items, setItems, refetch);
  const filterHook = useBoardFilters(items);

  // ── DnD state ──
  const [activeItem, setActiveItem] = useState<BoardItem | null>(null);
  const [overColumnId, setOverColumnId] = useState<string | null>(null);
  const [detailItem, setDetailItem] = useState<BoardItem | null>(null);
  const [showCreate, setShowCreate] = useState(false);

  // ── DnD sensors ──
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 6 } }),
    useSensor(KeyboardSensor)
  );

  // ── Column config (from DB) ──
  const columns = useMemo(() => {
    if (!board?.columns) return [];
    return board.columns.map((colId: string) => getColumnMeta(colId));
  }, [board]);

  // ── Group items by column ──
  const columnItems = useMemo(() => {
    const grouped: Record<string, BoardItem[]> = {};
    columns.forEach((col) => { grouped[col.id] = []; });
    filterHook.filtered.forEach((item) => {
      if (grouped[item.status]) {
        grouped[item.status].push(item);
      } else {
        // Item in unknown status — put in first column
        const first = columns[0]?.id;
        if (first && grouped[first]) grouped[first].push(item);
      }
    });
    // Sort by position within each column
    Object.keys(grouped).forEach((k) => grouped[k].sort((a, b) => a.position - b.position));
    return grouped;
  }, [columns, filterHook.filtered]);

  // ── DnD handlers ──
  const handleDragStart = useCallback((e: DragStartEvent) => {
    const item = items.find((i) => i.id === e.active.id);
    setActiveItem(item || null);
  }, [items]);

  const handleDragOver = useCallback((e: DragOverEvent) => {
    if (!e.over) { setOverColumnId(null); return; }
    const overData = e.over.data?.current;
    if (overData?.item) setOverColumnId(overData.item.status);
    else if (overData?.columnId) setOverColumnId(overData.columnId);
    else setOverColumnId(null);
  }, []);

  const handleDragEnd = useCallback((e: DragEndEvent) => {
    const { active, over } = e;
    setActiveItem(null);
    setOverColumnId(null);
    if (!over || !permissions.canMove) return;

    const activeId = String(active.id);
    const activeItemData = items.find((i) => i.id === activeId);
    if (!activeItemData) return;

    let targetStatus: string | null = null;
    const overData = over.data?.current;
    if (overData?.item) targetStatus = overData.item.status;
    else if (overData?.columnId) targetStatus = overData.columnId;

    if (targetStatus && targetStatus !== activeItemData.status) {
      mutations.moveItem(activeId, targetStatus);
    }
  }, [items, mutations, permissions]);

  // ── Keyboard shortcut ──
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'n' && !e.ctrlKey && !e.metaKey && !e.altKey
      && !(e.target instanceof HTMLInputElement) && !(e.target instanceof HTMLTextAreaElement)) {
      if (permissions.canCreate && mode !== 'readonly') setShowCreate(true);
    }
  }, [permissions, mode]);

  // Register keyboard listener
  useState(() => {
    if (typeof window !== 'undefined') {
      window.addEventListener('keydown', handleKeyDown as any);
      return () => window.removeEventListener('keydown', handleKeyDown as any);
    }
  });

  // ── Render states ──

  if (loading || permissions.isLoading) {
    return (
      <div className="text-center py-14">
        <div className="inline-flex items-center gap-3 text-slate-400">
          <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <span className="text-sm font-medium">{i18n.loading}</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-2xl p-8 text-center">
        <div className="text-3xl mb-3">⚠️</div>
        <p className="font-bold text-red-700 mb-2">{i18n.error}</p>
        <p className="text-sm text-red-600 mb-4">{error}</p>
        <button onClick={refetch}
          className="px-5 py-2.5 bg-red-600 text-white rounded-xl text-sm font-bold cursor-pointer hover:bg-red-700 border-0">
          🔄 {i18n.retry}
        </button>
      </div>
    );
  }

  if (!board) return null;

  return (
    <div className="space-y-4">
      {/* Header */}
      <BoardHeader
        board={board}
        itemCount={filterHook.filtered.length}
        totalCount={items.length}
        canCreate={permissions.canCreate && mode !== 'readonly'}
        onCreateClick={() => setShowCreate(true)}
        i18n={i18n}
      />

      {/* Filters */}
      <BoardFilters
        filters={filterHook.filters}
        hasActive={filterHook.hasActiveFilters}
        allTags={filterHook.allTags}
        allAssignees={filterHook.allAssignees}
        onSearch={filterHook.setSearch}
        onAssignee={filterHook.setAssignee}
        onTags={filterHook.setTags}
        onDueDate={filterHook.setDueDateFilter}
        onClear={filterHook.clearAll}
        showCuration={mode === 'curation'}
        onCurationStatus={filterHook.setCurationStatus}
        i18n={i18n}
      />

      {/* Kanban Board */}
      <DndContext
        sensors={sensors}
        collisionDetection={closestCorners}
        onDragStart={handleDragStart}
        onDragOver={handleDragOver}
        onDragEnd={handleDragEnd}
      >
        <BoardKanban
          columns={columns}
          columnItems={columnItems}
          overColumnId={overColumnId}
          mode={mode}
          permissions={permissions}
          i18n={i18n}
          onCardClick={(item) => setDetailItem(item)}
          onQuickMove={mutations.moveItem}
        />

        <DragOverlay dropAnimation={{ duration: 200, easing: 'ease-out' }}>
          {activeItem ? (
            <div className="bg-white rounded-xl border-2 border-blue-300 p-3 shadow-xl rotate-[3deg] w-[260px] opacity-95">
              <h4 className="text-[12px] font-bold text-slate-800 line-clamp-2">{activeItem.title}</h4>
              {activeItem.assignee_name && <p className="text-[10px] text-slate-400 mt-1">👤 {activeItem.assignee_name}</p>}
            </div>
          ) : null}
        </DragOverlay>
      </DndContext>

      {/* Card Detail Modal */}
      {detailItem && (
        <CardDetail
          item={detailItem}
          board={board}
          permissions={permissions}
          mode={mode}
          i18n={i18n}
          onClose={() => setDetailItem(null)}
          onUpdate={async (fields) => {
            await mutations.updateItem(detailItem.id, fields);
            setDetailItem((prev) => prev ? { ...prev, ...fields } : null);
          }}
          onMove={(newStatus) => { mutations.moveItem(detailItem.id, newStatus); setDetailItem(null); }}
          onDelete={() => { mutations.deleteItem(detailItem.id); setDetailItem(null); }}
          onDuplicate={() => mutations.duplicateItem(detailItem.id)}
          onMoveToBoard={(boardId) => { mutations.moveToBoard(detailItem.id, boardId); setDetailItem(null); }}
        />
      )}

      {/* Create Card Modal */}
      {showCreate && board && (
        <CardCreate
          boardId={board.id}
          columns={board.columns}
          i18n={i18n}
          onClose={() => setShowCreate(false)}
          onCreate={async (fields) => {
            await mutations.createItem(board.id, fields);
            setShowCreate(false);
          }}
        />
      )}

      {/* Toasts */}
      <ToastContainer toasts={mutations.toasts} />
    </div>
  );
}
