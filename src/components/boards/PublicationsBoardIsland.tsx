import React, { useEffect, useMemo, useState } from 'react';
import {
  DndContext,
  PointerSensor,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import type { DragEndEvent, DragStartEvent } from '@dnd-kit/core';
import {
  SortableContext,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';

type BoardItem = {
  id: string;
  title: string;
  description?: string | null;
  status: string;
  due_date?: string | null;
  assignee_name?: string | null;
  tags?: string[] | null;
};

type Lane = { key: string; label: string };

const LANES: Lane[] = [
  { key: 'backlog', label: 'Backlog' },
  { key: 'todo', label: 'A fazer' },
  { key: 'in_progress', label: 'Em progresso' },
  { key: 'review', label: 'Em revisão' },
  { key: 'done', label: 'Concluído' },
];

function canAccessPublicationsWorkspace(member: any): boolean {
  if (!member) return false;
  if (member.is_superadmin) return true;
  const opRole = String(member.operational_role || 'guest');
  const designations: string[] = Array.isArray(member.designations) ? member.designations : [];
  if (['manager', 'deputy_manager', 'tribe_leader', 'communicator'].includes(opRole)) return true;
  return ['curator', 'co_gp', 'comms_leader', 'comms_member'].some((d) => designations.includes(d));
}

function SortableCard({ item }: { item: BoardItem }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: item.id });
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
  };
  return (
    <article
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      className="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-3 shadow-sm cursor-grab active:cursor-grabbing"
    >
      <h3 className="text-[12px] font-bold text-navy dark:text-slate-100 mb-1">{item.title || 'Sem título'}</h3>
      {item.description ? (
        <p className="text-[11px] text-slate-500 dark:text-slate-300 line-clamp-3 mb-2">{item.description}</p>
      ) : null}
      <div className="flex flex-wrap gap-1 items-center">
        {item.due_date ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">Prazo: {item.due_date}</span>
        ) : null}
        {Array.isArray(item.tags)
          ? item.tags.map((tag) => (
              <span key={`${item.id}-${tag}`} className="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300">
                {tag}
              </span>
            ))
          : null}
      </div>
    </article>
  );
}

export default function PublicationsBoardIsland() {
  const [loading, setLoading] = useState(true);
  const [denied, setDenied] = useState(false);
  const [boardId, setBoardId] = useState<string>('');
  const [items, setItems] = useState<BoardItem[]>([]);
  const [draggingId, setDraggingId] = useState<string>('');

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }));
  const windowRef = globalThis as any;

  const itemsByLane = useMemo(() => {
    return LANES.reduce<Record<string, BoardItem[]>>((acc, lane) => {
      acc[lane.key] = items.filter((item) => item.status === lane.key);
      return acc;
    }, {});
  }, [items]);

  async function loadData() {
    const sb = windowRef?.navGetSb?.();
    const member = windowRef?.navGetMember?.();
    if (!sb || !member) {
      window.addEventListener('nav:member', () => loadData(), { once: true });
      return;
    }

    if (!canAccessPublicationsWorkspace(member)) {
      setDenied(true);
      setLoading(false);
      return;
    }

    const { data: boardsData, error: boardsError } = await sb.rpc('list_project_boards', { p_tribe_id: null });
    if (boardsError) throw new Error(boardsError.message);
    const targetBoard = (Array.isArray(boardsData) ? boardsData : []).find((entry: any) => String(entry?.domain_key || '') === 'publications_submissions');
    if (!targetBoard?.id) throw new Error('Global publications board not found');
    setBoardId(targetBoard.id);

    const { data: boardItems, error: itemsError } = await sb.rpc('list_board_items', {
      p_board_id: targetBoard.id,
      p_status: null,
    });
    if (itemsError) throw new Error(itemsError.message);
    const normalized = (Array.isArray(boardItems) ? boardItems : []).filter((row: any) => row.status !== 'archived');
    setItems(normalized);
    setLoading(false);
  }

  useEffect(() => {
    loadData().catch((error) => {
      console.warn('publications island load error', error);
      setDenied(true);
      setLoading(false);
    });
  }, []);

  async function onDragEnd(event: DragEndEvent) {
    setDraggingId('');
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const itemId = String(active.id);
    const overId = String(over.id);
    const nextLane = LANES.find((lane) => lane.key === overId)
      ? overId
      : (items.find((row) => row.id === overId)?.status || '');
    if (!nextLane) return;
    const current = items.find((row) => row.id === itemId);
    if (!current || current.status === nextLane) return;

    const sb = windowRef?.navGetSb?.();
    if (!sb || !boardId) return;
    const { error } = await sb.rpc('move_board_item', {
      p_item_id: itemId,
      p_new_status: nextLane,
      p_position: 0,
    });
    if (error) {
      windowRef?.toast?.(error.message || 'Falha ao mover card', 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === itemId ? { ...row, status: nextLane } : row)));
    windowRef?.toast?.('Status atualizado', 'success');
  }

  if (loading) {
    return <div className="text-center py-10 text-slate-400">Carregando quadro global...</div>;
  }
  if (denied) {
    return (
      <div className="text-center py-10 text-slate-500 dark:text-slate-300">
        Acesso restrito para esta área.
      </div>
    );
  }

  return (
    <DndContext
      sensors={sensors}
      onDragStart={(event: DragStartEvent) => setDraggingId(String(event.active.id))}
      onDragEnd={onDragEnd}
    >
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-5 gap-4">
        {LANES.map((lane) => (
          <section key={lane.key} className="rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-3">
            <div className="flex items-center justify-between mb-2">
              <h2 className="text-[12px] font-bold text-slate-700 dark:text-slate-200">{lane.label}</h2>
              <span className="text-[10px] px-2 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300">
                {itemsByLane[lane.key]?.length || 0}
              </span>
            </div>
            <SortableContext
              id={lane.key}
              items={itemsByLane[lane.key].map((item) => item.id)}
              strategy={verticalListSortingStrategy}
            >
              <div id={lane.key} className="min-h-[220px] space-y-2">
                {itemsByLane[lane.key].map((item) => (
                  <SortableCard key={item.id} item={item} />
                ))}
                {itemsByLane[lane.key].length === 0 ? (
                  <div className="text-[11px] text-slate-400 dark:text-slate-500 py-6 text-center">
                    {draggingId ? 'Solte o card aqui' : 'Sem cards'}
                  </div>
                ) : null}
              </div>
            </SortableContext>
          </section>
        ))}
      </div>
    </DndContext>
  );
}
