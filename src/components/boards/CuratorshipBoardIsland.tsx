/**
 * CuratorshipBoardIsland — Super-Kanban de Curadoria
 * Exibe board_items com curation_status='curation_pending' de todas as tribos.
 * Drag-and-drop para "Publicado" dispara publish_board_item_from_curation.
 * Acesso: admin+, curator, co_gp.
 */
import React, { useEffect, useState } from 'react';
import {
  DndContext,
  PointerSensor,
  useSensor,
  useSensors,
  useDroppable,
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
  tribe_name?: string | null;
  assignee_name?: string | null;
  reviewer_name?: string | null;
  updated_at?: string | null;
};

const LANES = [
  { key: 'curation_pending', label: 'Aguardando Curadoria' },
  { key: 'published', label: 'Publicado' },
];

function SortableCard({ item, onOpen }: { item: BoardItem; onOpen: (item: BoardItem) => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id,
  });
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
      onClick={() => onOpen(item)}
      className="rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-3 shadow-sm cursor-grab active:cursor-grabbing hover:shadow-md transition-shadow"
    >
      <h3 className="text-[13px] font-bold text-navy dark:text-slate-100 mb-1 line-clamp-2">
        {item.title || 'Sem título'}
      </h3>
      {item.tribe_name ? (
        <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300">
          {item.tribe_name}
        </span>
      ) : null}
      {item.assignee_name ? (
        <p className="text-[11px] text-slate-500 mt-1 truncate">{item.assignee_name}</p>
      ) : null}
    </article>
  );
}

export default function CuratorshipBoardIsland({ i18n }: { i18n?: Record<string, string> }) {
  const windowRef = globalThis as any;
  const [loading, setLoading] = useState(true);
  const [denied, setDenied] = useState(false);
  const [items, setItems] = useState<BoardItem[]>([]);
  const [activeId, setActiveId] = useState<string>('');
  const [modalItem, setModalItem] = useState<BoardItem | null>(null);

  const ui = {
    loading: i18n?.loading || 'Carregando...',
    denied: i18n?.denied || 'Acesso restrito.',
    empty: i18n?.empty || 'Nenhum item aguardando curadoria.',
    colPending: i18n?.colPending || 'Aguardando Curadoria',
    colPublished: i18n?.colPublished || 'Publicado',
    published: i18n?.published || 'Publicado na vitrine!',
    error: i18n?.error || 'Erro ao publicar.',
  };

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }));

  const pending = items.filter((i) => (i as any).curation_status !== 'published');
  function PublishedDropZone() {
    const { setNodeRef, isOver } = useDroppable({ id: 'published' });
    return (
      <div
        ref={setNodeRef}
        className={`py-8 text-center text-sm rounded-xl border-2 border-dashed transition-colors ${
          isOver
            ? 'border-emerald-500 bg-emerald-100 dark:bg-emerald-900/40 text-emerald-700'
            : 'border-emerald-200 dark:border-emerald-800 text-slate-400'
        }`}
      >
        ↓ Solte o card aqui para publicar na vitrine
      </div>
    );
  }

  async function loadItems() {
    const sb = windowRef?.navGetSb?.();
    const member = windowRef?.navGetMember?.();
    if (!sb || !member) {
      window.addEventListener('nav:member', () => loadItems(), { once: true });
      return;
    }

    const { data, error } = await sb.rpc('list_curation_pending_board_items');
    if (error) {
      if (error.message?.toLowerCase().includes('access') || error.message?.toLowerCase().includes('curatorship')) {
        setDenied(true);
      }
      setLoading(false);
      return;
    }

    const list = Array.isArray(data) ? data : [];
    setItems(list.map((row: any) => ({
      ...row,
      curation_status: row.curation_status || 'curation_pending',
    })));
    setLoading(false);
  }

  useEffect(() => {
    loadItems().catch(() => setLoading(false));
  }, []);

  async function onDragEnd(event: DragEndEvent) {
    setActiveId('');
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const itemId = String(active.id);
    const overId = String(over.id);
    if (overId !== 'published') return;

    const item = items.find((i) => i.id === itemId);
    if (!item) return;

    const sb = windowRef?.navGetSb?.();
    if (!sb) return;

    const { data: newId, error } = await sb.rpc('publish_board_item_from_curation', {
      p_item_id: itemId,
    });

    if (error) {
      windowRef?.toast?.(error.message || ui.error, 'error');
      return;
    }

    publishedIds.add(itemId);
    setItems((prev) => prev.filter((i) => i.id !== itemId));
    windowRef?.toast?.(ui.published, 'success');
  }

  if (loading) {
    return <div className="text-center py-10 text-slate-400">{ui.loading}</div>;
  }
  if (denied) {
    return <div className="text-center py-10 text-slate-500">{ui.denied}</div>;
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <DndContext
          sensors={sensors}
          onDragStart={(e: DragStartEvent) => setActiveId(String(e.active.id))}
          onDragEnd={onDragEnd}
        >
          <section
            id="curation_pending"
            className="rounded-2xl border-2 border-dashed border-amber-200 dark:border-amber-800 bg-amber-50/30 dark:bg-amber-900/10 p-4 min-h-[280px]"
          >
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-[13px] font-bold text-amber-700 dark:text-amber-400">
                {ui.colPending}
              </h3>
              <span className="text-[11px] px-2 py-0.5 rounded-full bg-amber-100 dark:bg-amber-900/50 text-amber-700 dark:text-amber-300 font-bold">
                {pending.length}
              </span>
            </div>
            <SortableContext
              id="curation_pending"
              items={pending.map((i) => i.id)}
              strategy={verticalListSortingStrategy}
            >
              <div className="space-y-2">
                {pending.map((item) => (
                  <SortableCard
                    key={item.id}
                    item={item}
                    onOpen={setModalItem}
                  />
                ))}
                {pending.length === 0 ? (
                  <div className="py-8 text-center text-slate-400 text-sm">{ui.empty}</div>
                ) : null}
              </div>
            </SortableContext>
          </section>

          <section
            id="published"
            className="rounded-2xl border-2 border-dashed border-emerald-200 dark:border-emerald-800 bg-emerald-50/30 dark:bg-emerald-900/10 p-4 min-h-[280px]"
          >
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-[13px] font-bold text-emerald-700 dark:text-emerald-400">
                {ui.colPublished}
              </h3>
              <span className="text-[11px] text-slate-500">
                Arraste para publicar
              </span>
            </div>
            <PublishedDropZone />
          </section>
        </DndContext>
      </div>

      <p className="text-[12px] text-slate-500">
        Itens publicados aparecem em <a href="/publications" className="text-navy font-semibold underline hover:no-underline">/publications</a>.
      </p>
    </div>
  );
}
