/**
 * BoardEngine.tsx — Main orchestrator component (Astro Island)
 *
 * Usage:
 *   <BoardEngine client:load boardId="..." />
 *   <BoardEngine client:load domainKey="communication" />
 *   <BoardEngine client:load tribeId={6} domainKey="research_delivery" />
 */
import { useState, useEffect, useMemo, useCallback } from 'react';
import { DndContext, DragOverlay, pointerWithin, rectIntersection, PointerSensor, TouchSensor, KeyboardSensor, useSensor, useSensors, type CollisionDetection } from '@dnd-kit/core';
import type { DragStartEvent, DragEndEvent, DragOverEvent } from '@dnd-kit/core';

import type { BoardEngineProps, BoardItem, BoardI18n } from '../../types/board';
import { DEFAULT_I18N, getColumnMeta } from '../../types/board';
import { useBoard, getSb } from '../../hooks/useBoard';
import { useBoardMutations } from '../../hooks/useBoardMutations';
import { useBoardFilters } from '../../hooks/useBoardFilters';
import { useBoardPermissions } from '../../hooks/useBoardPermissions';

import BoardHeader from '../board/BoardHeader';
import BoardFilters from '../board/BoardFilters';
import BoardKanban from '../board/BoardKanban';
import CardDetail from '../board/CardDetail';
import CardCreate from '../board/CardCreate';
import ToastContainer from '../board/ToastContainer';
import ViewToggle from '../board/ViewToggle';
import type { BoardViewMode } from '../board/ViewToggle';
import TableView from '../board/TableView';
import GroupedListView from '../board/GroupedListView';
import CalendarView from '../board/CalendarView';
import TimelineView from '../board/TimelineView';
import BoardActivitiesView from '../board/BoardActivitiesView';

export default function BoardEngine(props: BoardEngineProps) {
  const i18n: BoardI18n = { ...DEFAULT_I18N, ...props.i18n };
  const mode = props.mode ?? 'default';

  // ── Data layer ──
  const { board, items: rawItems, loading, error, refetch } = useBoard(props);
  const [items, setItems] = useState<BoardItem[]>([]);
  const permissions = useBoardPermissions(board);

  useEffect(() => { setItems(rawItems); }, [rawItems]);

  const mutations = useBoardMutations(items, setItems, refetch);

  // Load board/tribe members for filter dropdown
  const [boardMembers, setBoardMembers] = useState<{ id: string; name: string }[]>([]);
  useEffect(() => {
    if (!board) return;
    const sb = getSb();
    if (!sb) return;
    (async () => {
      const { data } = board.tribe_id
        ? await sb.from('members').select('id, name').eq('tribe_id', board.tribe_id).eq('is_active', true)
        : await sb.from('active_members').select('id, name');
      if (Array.isArray(data)) setBoardMembers(data);
    })();
  }, [board?.id, board?.tribe_id]);

  const filterHook = useBoardFilters(items, boardMembers);

  // ── View mode ──
  const [viewMode, setViewMode] = useState<BoardViewMode>('kanban');

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

  // Custom collision detection: prefer column droppables over card sortables
  // Fixes issue where closestCorners fails for cross-column drops
  const collisionDetection: CollisionDetection = useCallback((args) => {
    // First check pointerWithin (most intuitive for cross-column)
    const pointerCollisions = pointerWithin(args);
    if (pointerCollisions.length > 0) return pointerCollisions;
    // Fallback to rect intersection
    return rectIntersection(args);
  }, []);

  // ── Column config (from DB) ──
  const _lang = typeof window !== 'undefined'
    ? (window.location.pathname.startsWith('/en') ? 'en-US' : window.location.pathname.startsWith('/es') ? 'es-LATAM' : new URLSearchParams(window.location.search).get('lang') || localStorage.getItem('preferred_locale') || 'pt-BR')
    : 'pt-BR';
  const columns = useMemo(() => {
    if (!board?.columns) return [];
    return board.columns.map((colId: string) => getColumnMeta(colId, _lang));
  }, [board, _lang]);

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
    if (!over || !permissions.canMove || mode === 'readonly') return;

    const activeId = String(active.id);
    const activeItemData = items.find((i) => i.id === activeId);
    if (!activeItemData) return;

    let targetStatus: string | null = null;
    let targetPosition = 0;
    const overData = over.data?.current;

    if (overData?.item) {
      targetStatus = overData.item.status;
      const colItems = items
        .filter((i) => i.status === overData.item.status)
        .sort((a, b) => a.position - b.position);
      const overIdx = colItems.findIndex((i) => i.id === overData.item.id);
      targetPosition = overIdx >= 0 ? overIdx : colItems.length;
    } else if (overData?.columnId) {
      targetStatus = overData.columnId;
      targetPosition = items.filter((i) => i.status === overData.columnId).length;
    }

    if (!targetStatus) return;

    if (targetStatus === activeItemData.status) {
      const colItems = items
        .filter((i) => i.status === targetStatus)
        .sort((a, b) => a.position - b.position);
      const oldIdx = colItems.findIndex((i) => i.id === activeId);
      if (oldIdx !== targetPosition && oldIdx !== -1) {
        mutations.reorderItem(activeId, targetStatus, targetPosition);
      }
    } else {
      mutations.moveItem(activeId, targetStatus, targetPosition);
    }
  }, [items, mutations, permissions, mode]);

  // ── Keyboard shortcut ──
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'n' && !e.ctrlKey && !e.metaKey && !e.altKey
      && !(e.target instanceof HTMLInputElement) && !(e.target instanceof HTMLTextAreaElement)) {
      if (permissions.canCreate && mode !== 'readonly') setShowCreate(true);
    }
  }, [permissions, mode]);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    window.addEventListener('keydown', handleKeyDown as any);
    return () => window.removeEventListener('keydown', handleKeyDown as any);
  }, [handleKeyDown]);

  // ── Render states ──

  if (loading || permissions.isLoading) {
    return (
      <div className="space-y-4 animate-pulse">
        <div className="flex items-center justify-between">
          <div className="h-6 w-48 bg-[var(--surface-hover)] rounded-lg" />
          <div className="h-9 w-28 bg-[var(--surface-hover)] rounded-xl" />
        </div>
        <div className="flex gap-3">
          <div className="h-9 w-44 bg-[var(--surface-section-cool)] rounded-xl" />
          <div className="h-9 w-32 bg-[var(--surface-section-cool)] rounded-xl" />
          <div className="h-9 w-36 bg-[var(--surface-section-cool)] rounded-xl" />
        </div>
        <div className="grid grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((n) => (
            <div key={n} className="space-y-3">
              <div className="h-4 w-24 bg-[var(--surface-hover)] rounded" />
              <div className="bg-[var(--surface-base)] rounded-xl border-2 border-dashed border-[var(--border-default)] p-3 space-y-2.5 min-h-[200px]">
                {[1, 2].map((c) => (
                  <div key={c} className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-subtle)] p-3 space-y-2">
                    <div className="h-3 w-full bg-[var(--surface-hover)] rounded" />
                    <div className="h-3 w-2/3 bg-[var(--surface-section-cool)] rounded" />
                    <div className="flex gap-2">
                      <div className="h-2.5 w-10 bg-[var(--surface-section-cool)] rounded" />
                      <div className="h-2.5 w-14 bg-[var(--surface-section-cool)] rounded" />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
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
      {/* Readonly banner */}
      {mode === 'readonly' && (
        <div className="flex items-center gap-2 px-4 py-2.5 bg-amber-50 border border-amber-200 rounded-xl text-[12px] text-amber-800 font-medium">
          <span>🔒</span>
          <span>Modo somente leitura — este board é um registro histórico e não pode ser editado.</span>
        </div>
      )}

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

      {/* View Toggle */}
      <ViewToggle current={viewMode} onChange={setViewMode} />

      {/* Kanban Board (default) */}
      {viewMode === 'kanban' && (
        <DndContext
          sensors={sensors}
          collisionDetection={collisionDetection}
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
              <div className="bg-[var(--surface-card)] rounded-xl border-2 border-blue-300 p-3 shadow-xl rotate-[3deg] w-[260px] opacity-95">
                <h4 className="text-[12px] font-bold text-[var(--text-primary)] line-clamp-2">{activeItem.title}</h4>
                {activeItem.assignee_name && <p className="text-[10px] text-[var(--text-muted)] mt-1">👤 {activeItem.assignee_name}</p>}
              </div>
            ) : null}
          </DragOverlay>
        </DndContext>
      )}

      {/* Table View */}
      {viewMode === 'table' && board && (
        <TableView
          items={filterHook.filtered}
          columns={board.columns}
          i18n={i18n}
          onOpenDetail={(item) => setDetailItem(item)}
          onMove={(itemId, newStatus) => mutations.moveItem(itemId, newStatus)}
        />
      )}

      {/* Grouped List View */}
      {viewMode === 'list' && (
        <GroupedListView
          items={filterHook.filtered}
          i18n={i18n}
          onOpenDetail={(item) => setDetailItem(item)}
        />
      )}

      {/* Calendar View */}
      {viewMode === 'calendar' && (
        <CalendarView
          items={filterHook.filtered}
          i18n={i18n}
          onOpenDetail={(item) => setDetailItem(item)}
        />
      )}

      {/* Timeline View */}
      {viewMode === 'timeline' && (
        <TimelineView
          items={filterHook.filtered}
          i18n={i18n}
          onOpenDetail={(item) => setDetailItem(item)}
        />
      )}

      {/* Activities View */}
      {viewMode === 'activities' && board && (
        <BoardActivitiesView
          boardId={board.id}
          members={boardMembers as any}
          onOpenCard={(cardId) => {
            const item = items.find((i) => i.id === cardId);
            if (item) setDetailItem(item);
          }}
        />
      )}

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
