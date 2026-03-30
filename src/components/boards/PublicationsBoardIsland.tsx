import React, { useEffect, useMemo, useState } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
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
import { ExternalLink } from 'lucide-react';
import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import { hasPermission } from '../../lib/permissions';

type BoardItem = {
  id: string;
  title: string;
  description?: string | null;
  status: string;
  due_date?: string | null;
  assignee_name?: string | null;
  tags?: string[] | null;
  external_link?: string | null;
  published_at?: string | null;
};

type Lane = { key: string; label: string };

const LANES: Lane[] = [
  { key: 'backlog', label: 'Backlog' },
  { key: 'todo', label: 'A fazer' },
  { key: 'in_progress', label: 'Em progresso' },
  { key: 'review', label: 'Em revisão' },
  { key: 'done', label: 'Concluído' },
];

const OUTCOME_OPTIONS = ['pending', 'submitted', 'approved', 'rejected', 'withdrawn'] as const;

function canAccessPublicationsWorkspace(member: any): boolean {
  if (!member) return false;
  return hasPermission(member, 'content.view_publications');
}

function SortableCard({
  item,
  onLaneKeyboardMove,
  onOpen,
}: {
  item: BoardItem;
  onLaneKeyboardMove: (item: BoardItem, direction: -1 | 1) => void;
  onOpen: (item: BoardItem) => void;
}) {
  const t = usePageI18n();
  const isOverdue = item.due_date && new Date(item.due_date) < new Date() && item.status !== 'published';
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
      tabIndex={0}
      onKeyDown={(event) => {
        if (!event.shiftKey) return;
        if (event.key === 'ArrowLeft') {
          event.preventDefault();
          onLaneKeyboardMove(item, -1);
        }
        if (event.key === 'ArrowRight') {
          event.preventDefault();
          onLaneKeyboardMove(item, 1);
        }
      }}
      onDoubleClick={() => onOpen(item)}
      className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3 shadow-sm cursor-grab active:cursor-grabbing"
    >
      <h3 className="text-[12px] font-bold text-navy mb-1">{item.title || t('comp.pubBoard.untitled', 'Sem título')}</h3>
      {item.description ? (
        <p className="text-[11px] text-[var(--text-secondary)] line-clamp-3 mb-2">{item.description}</p>
      ) : null}
      <div className="flex flex-wrap gap-1 items-center">
        {item.due_date ? (
          <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${isOverdue ? 'bg-red-100 dark:bg-red-950/30 text-red-700 dark:text-red-300 animate-pulse' : 'bg-amber-100 dark:bg-amber-950/30 text-amber-700 dark:text-amber-300'}`}>{[t('comp.pubBoard.duePrefix', 'Prazo:'), item.due_date].join(' ')}</span>
        ) : null}
        {Array.isArray(item.tags)
          ? item.tags.map((tag) => (
              <span key={`${item.id}-${tag}`} className="text-[10px] px-1.5 py-0.5 rounded-full bg-[var(--surface-base)] text-[var(--text-secondary)]">
                {tag}
              </span>
            ))
          : null}
        {item.status === 'done' && item.external_link ? (
          <a
            href={item.external_link}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-700 hover:opacity-90"
            onClick={(event) => event.stopPropagation()}
            aria-label={t('comp.pubBoard.openExternalPub', 'Abrir publicação externa')}
          >
            <ExternalLink size={12} />
            {t('comp.pubBoard.publishedBadge', 'Publicado')}
          </a>
        ) : null}
      </div>
    </article>
  );
}

export default function PublicationsBoardIsland() {
  const t = usePageI18n();
  const [loading, setLoading] = useState(true);
  const [denied, setDenied] = useState(false);
  const [boardId, setBoardId] = useState<string>('');
  const [items, setItems] = useState<BoardItem[]>([]);
  const [draggingId, setDraggingId] = useState<string>('');
  const [modalItem, setModalItem] = useState<BoardItem | null>(null);
  const [metaChannel, setMetaChannel] = useState('projectmanagement_com');
  const [metaSubmittedAt, setMetaSubmittedAt] = useState('');
  const [metaOutcome, setMetaOutcome] = useState('pending');
  const [metaNotes, setMetaNotes] = useState('');
  const [metaExternalLink, setMetaExternalLink] = useState('');
  const [metaPublishedAt, setMetaPublishedAt] = useState('');

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }));
  const windowRef = globalThis as any;

  const laneLabels: Record<string, string> = {
    backlog: t('comp.pubBoard.lane.backlog', 'Backlog'),
    todo: t('comp.pubBoard.lane.todo', 'A fazer'),
    in_progress: t('comp.pubBoard.lane.inProgress', 'Em progresso'),
    review: t('comp.pubBoard.lane.review', 'Em revisão'),
    done: t('comp.pubBoard.lane.done', 'Concluído'),
  };

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
    const baseItems = normalized.map((row: any) => ({
      ...row,
      external_link: null,
      published_at: null,
    }));
    const itemIds = baseItems.map((row: any) => row.id).filter(Boolean);
    if (itemIds.length) {
      const { data: eventsData } = await sb
        .from('publication_submission_events')
        .select('board_item_id,external_link,published_at,updated_at')
        .in('board_item_id', itemIds)
        .order('updated_at', { ascending: false });
      const latestByItem: Record<string, { external_link: string | null; published_at: string | null }> = {};
      (Array.isArray(eventsData) ? eventsData : []).forEach((row: any) => {
        const itemId = String(row?.board_item_id || '');
        if (!itemId || latestByItem[itemId]) return;
        latestByItem[itemId] = {
          external_link: row?.external_link ? String(row.external_link) : null,
          published_at: row?.published_at ? String(row.published_at) : null,
        };
      });
      setItems(baseItems.map((row: any) => ({
        ...row,
        external_link: latestByItem[row.id]?.external_link ?? null,
        published_at: latestByItem[row.id]?.published_at ?? null,
      })));
    } else {
      setItems(baseItems);
    }
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
      windowRef?.toast?.(error.message || t('comp.pubBoard.errorMoveCard', 'Falha ao mover card'), 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === itemId ? { ...row, status: nextLane } : row)));
    try { if ((window as any).posthog) (window as any).posthog.capture('board_card_moved', { card_id: itemId, from_status: current.status, to_status: nextLane }); } catch {}
    windowRef?.toast?.(t('comp.pubBoard.statusUpdated', 'Status atualizado'), 'success');
  }

  async function moveViaKeyboard(item: BoardItem, direction: -1 | 1) {
    const laneIdx = LANES.findIndex((lane) => lane.key === item.status);
    if (laneIdx < 0) return;
    const targetLane = LANES[laneIdx + direction];
    if (!targetLane || targetLane.key === item.status) return;
    const sb = windowRef?.navGetSb?.();
    if (!sb || !boardId) return;
    const { error } = await sb.rpc('move_board_item', {
      p_item_id: item.id,
      p_new_status: targetLane.key,
      p_position: 0,
    });
    if (error) {
      windowRef?.toast?.(error.message || t('comp.pubBoard.errorMoveCard', 'Falha ao mover card'), 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, status: targetLane.key } : row)));
    windowRef?.toast?.(`${t('comp.pubBoard.cardMovedTo', 'Card movido para')} ${laneLabels[targetLane.key] || targetLane.label}`, 'success');
  }

  async function saveSubmissionMetadata() {
    if (!modalItem) return;
    const sb = windowRef?.navGetSb?.();
    if (!sb) return;
    const { error } = await sb.rpc('upsert_publication_submission_event', {
      p_board_item_id: modalItem.id,
      p_channel: metaChannel,
      p_submitted_at: metaSubmittedAt ? new Date(metaSubmittedAt).toISOString() : null,
      p_outcome: metaOutcome,
      p_notes: metaNotes || null,
      p_external_link: metaExternalLink || null,
      p_published_at: metaPublishedAt ? new Date(metaPublishedAt).toISOString() : null,
    });
    if (error) {
      windowRef?.toast?.(error.message || t('comp.pubBoard.errorSaveMetadata', 'Falha ao salvar metadados de submissão'), 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === modalItem.id
      ? { ...row, external_link: metaExternalLink || null, published_at: metaPublishedAt || null }
      : row)));
    setModalItem(null);
    windowRef?.toast?.(t('comp.pubBoard.metadataUpdated', 'Metadados de submissão atualizados'), 'success');
  }

  function openSubmissionModal(item: BoardItem) {
    setModalItem(item);
    setMetaChannel('projectmanagement_com');
    setMetaSubmittedAt('');
    setMetaOutcome('pending');
    setMetaNotes('');
    setMetaExternalLink(item.external_link || '');
    setMetaPublishedAt(item.published_at ? String(item.published_at).slice(0, 16) : '');
  }

  if (loading) {
    return <div className="text-center py-10 text-[var(--text-muted)]">{t('comp.pubBoard.loadingBoard', 'Carregando quadro global...')}</div>;
  }
  if (denied) {
    return (
      <div className="text-center py-10 text-[var(--text-secondary)]">
        {t('comp.pubBoard.deniedBoard', 'Acesso restrito para esta área.')}
      </div>
    );
  }

  return (
    <>
    <DndContext
      sensors={sensors}
      onDragStart={(event: DragStartEvent) => setDraggingId(String(event.active.id))}
      onDragEnd={onDragEnd}
    >
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-5 gap-4">
        {LANES.map((lane) => (
          <section key={lane.key} className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3">
            <div className="flex items-center justify-between mb-2">
              <h2 className="text-[12px] font-bold text-[var(--text-primary)]">{laneLabels[lane.key] || lane.label}</h2>
              <span className="text-[10px] px-2 py-0.5 rounded-full bg-[var(--surface-base)] text-[var(--text-secondary)]">
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
                  <SortableCard key={item.id} item={item} onLaneKeyboardMove={moveViaKeyboard} onOpen={openSubmissionModal} />
                ))}
                {itemsByLane[lane.key].length === 0 ? (
                  <div className="text-[11px] text-[var(--text-muted)] py-6 text-center">
                    {draggingId ? t('comp.pubBoard.dropCardHere', 'Solte o card aqui') : t('comp.pubBoard.noCards', 'Sem cards')}
                  </div>
                ) : null}
              </div>
            </SortableContext>
          </section>
        ))}
      </div>
    </DndContext>
    {modalItem ? (
      <div className="fixed inset-0 z-50">
        <button type="button" className="absolute inset-0 bg-black/40 border-0 p-0 m-0" aria-label="close-modal-overlay" onClick={() => setModalItem(null)} />
        <div className="absolute top-1/2 left-1/2 w-full max-w-lg -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-xl">
          <h3 className="text-base font-bold text-[var(--text-primary)] mb-3">{t('comp.pubBoard.modalTitle', 'Metadados de submissão PMI')}</h3>
          <div className="space-y-3">
            <div>
              <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.pubBoard.fieldChannel', 'Canal')}</label>
              <input value={metaChannel} onChange={(e) => setMetaChannel(e.target.value)} className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm bg-[var(--surface-card)]" />
            </div>
            <div>
              <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.pubBoard.fieldSubmittedAt', 'Data da submissão')}</label>
              <input type="datetime-local" value={metaSubmittedAt} onChange={(e) => setMetaSubmittedAt(e.target.value)} className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm bg-[var(--surface-card)]" />
            </div>
            <div>
              <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.pubBoard.fieldOutcome', 'Resultado')}</label>
              <DropdownMenu.Root>
                <DropdownMenu.Trigger asChild>
                  <button type="button" className="w-full text-left rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm bg-[var(--surface-card)]">
                    {metaOutcome}
                  </button>
                </DropdownMenu.Trigger>
                <DropdownMenu.Portal>
                  <DropdownMenu.Content sideOffset={6} className="z-50 min-w-[220px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] p-1 shadow-xl">
                    {OUTCOME_OPTIONS.map((option) => (
                      <DropdownMenu.Item
                        key={option}
                        onSelect={() => setMetaOutcome(option)}
                        className="px-2 py-1.5 text-sm rounded-md text-[var(--text-primary)] outline-none hover:bg-[var(--surface-hover)]"
                      >
                        {option}
                      </DropdownMenu.Item>
                    ))}
                  </DropdownMenu.Content>
                </DropdownMenu.Portal>
              </DropdownMenu.Root>
            </div>
            <div>
              <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.pubBoard.fieldNotes', 'Notas')}</label>
              <textarea value={metaNotes} onChange={(e) => setMetaNotes(e.target.value)} rows={4} className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm bg-[var(--surface-card)]" />
            </div>
            <div>
              <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.pubBoard.fieldExternalLink', 'URL de publicação externa')}</label>
              <input
                type="url"
                value={metaExternalLink}
                onChange={(e) => setMetaExternalLink(e.target.value)}
                placeholder="https://..."
                className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm bg-[var(--surface-card)]"
              />
            </div>
            <div>
              <label className="text-xs font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.pubBoard.fieldPublishedAt', 'Data de publicação efetiva')}</label>
              <input
                type="datetime-local"
                value={metaPublishedAt}
                onChange={(e) => setMetaPublishedAt(e.target.value)}
                className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm bg-[var(--surface-card)]"
              />
            </div>
          </div>
          <div className="mt-4 flex justify-end gap-2">
            <button type="button" onClick={() => setModalItem(null)} className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm">{t('comp.pubBoard.cancel', 'Cancelar')}</button>
            <button type="button" onClick={saveSubmissionMetadata} className="px-3 py-2 rounded-lg bg-navy text-white text-sm">{t('comp.pubBoard.save', 'Salvar')}</button>
          </div>
        </div>
      </div>
    ) : null}
    </>
  );
}
