import React, { useEffect, useMemo, useState } from 'react';
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCorners,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import type { DragEndEvent, DragStartEvent } from '@dnd-kit/core';
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { CalendarClock, Paperclip, Trash2, UserCircle2, X } from 'lucide-react';

type Member = {
  id: string;
  name?: string | null;
  photo_url?: string | null;
};

type ChecklistItem = { text: string; done: boolean };
type AttachmentItem = { url: string };

type BoardItem = {
  id: string;
  title: string;
  description?: string | null;
  status: string;
  due_date?: string | null;
  assignee_id?: string | null;
  assignee_name?: string | null;
  checklist?: ChecklistItem[] | string | null;
  attachments?: AttachmentItem[] | string | null;
  updated_at?: string | null;
};

type Lane = { key: string; label: string };

const LANES: Lane[] = [
  { key: 'backlog', label: 'Backlog' },
  { key: 'todo', label: 'To Do' },
  { key: 'in_progress', label: 'Em Progresso' },
  { key: 'review', label: 'Revisao' },
  { key: 'done', label: 'Concluido' },
];

type TribeKanbanI18n = Record<string, any>;

function parseChecklist(input: any): ChecklistItem[] {
  const raw = Array.isArray(input)
    ? input
    : typeof input === 'string'
      ? (() => { try { const parsed = JSON.parse(input); return Array.isArray(parsed) ? parsed : []; } catch { return []; } })()
      : [];
  return raw
    .map((entry: any) => {
      if (entry && typeof entry === 'object') {
        const text = String(entry.text || '').trim();
        if (!text) return null;
        return { text, done: entry.done === true };
      }
      const text = String(entry || '').trim();
      if (!text) return null;
      return { text, done: false };
    })
    .filter(Boolean) as ChecklistItem[];
}

function parseAttachments(input: any): AttachmentItem[] {
  const raw = Array.isArray(input)
    ? input
    : typeof input === 'string'
      ? (() => { try { const parsed = JSON.parse(input); return Array.isArray(parsed) ? parsed : []; } catch { return []; } })()
      : [];
  return raw
    .map((entry: any) => {
      if (typeof entry === 'string') return { url: entry.trim() };
      if (entry && typeof entry === 'object' && typeof entry.url === 'string') return { url: entry.url.trim() };
      return null;
    })
    .filter((entry: any) => !!entry?.url);
}

function canEditBoard(member: any, tribe: any): boolean {
  if (!member) return false;
  const desigs: string[] = Array.isArray(member.designations) ? member.designations : [];
  const isCommsOperational = String(tribe?.workstream_type || '').toLowerCase() === 'operational'
    && String(tribe?.name || '').toLowerCase().includes('comunica');
  const canOperateComms = isCommsOperational
    && (
      member.operational_role === 'communicator'
      || desigs.includes('comms_team')
      || desigs.includes('comms_leader')
      || desigs.includes('comms_member')
    );
  const isMgmt = ['manager', 'deputy_manager'].includes(String(member.operational_role || ''));
  const isLeaderOfThisTribe = String(member.operational_role || '') === 'tribe_leader'
    && Number(member.tribe_id || 0) === Number(tribe?.id || 0);
  return !!member?.is_superadmin || isMgmt || isLeaderOfThisTribe || canOperateComms;
}

function SortableCard({
  item,
  canEdit,
  assigneePhoto,
  onOpen,
}: {
  item: BoardItem;
  canEdit: boolean;
  assigneePhoto?: string;
  onOpen: (item: BoardItem) => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id,
    disabled: !canEdit,
  });
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
  };
  const attachments = parseAttachments(item.attachments);
  const due = item.due_date ? new Date(item.due_date) : null;
  const isOverdue = !!due && due.getTime() < Date.now() && item.status !== 'done';

  return (
    <article
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      tabIndex={0}
      className={`rounded-xl border p-3 shadow-sm transition-all ${canEdit ? 'cursor-grab active:cursor-grabbing' : 'cursor-default'} border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900`}
      onClick={() => onOpen(item)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onOpen(item);
        }
      }}
    >
      <h4 className="text-[13px] font-semibold text-slate-900 dark:text-slate-100 mb-2 line-clamp-2">{item.title || 'Sem titulo'}</h4>
      <div className="flex items-center gap-2 text-[11px] text-slate-500 dark:text-slate-300">
        {assigneePhoto ? (
          <img src={assigneePhoto} className="w-5 h-5 rounded-full object-cover" alt="assignee" />
        ) : (
          <UserCircle2 size={16} />
        )}
        <span className="truncate">{item.assignee_name || 'Sem responsavel'}</span>
      </div>
      <div className="mt-2 flex items-center gap-2 text-[11px]">
        {attachments.length > 0 ? (
          <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700">
            <Paperclip size={12} /> {attachments.length}
          </span>
        ) : null}
        {due ? (
          <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded ${isOverdue ? 'bg-red-50 text-red-700' : 'bg-slate-100 text-slate-600'}`}>
            <CalendarClock size={12} /> {due.toLocaleDateString('pt-BR')}
          </span>
        ) : null}
      </div>
    </article>
  );
}

export default function TribeKanbanIsland({ tribeId, i18n }: { tribeId: number; i18n: TribeKanbanI18n }) {
  const windowRef = globalThis as any;
  const [loading, setLoading] = useState(true);
  const [denied, setDenied] = useState(false);
  const [canEdit, setCanEdit] = useState(false);
  const [boardId, setBoardId] = useState<string>('');
  const [items, setItems] = useState<BoardItem[]>([]);
  const [members, setMembers] = useState<Member[]>([]);
  const [activeId, setActiveId] = useState<string>('');
  const [modalItem, setModalItem] = useState<BoardItem | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const itemsByLane = useMemo(() => {
    return LANES.reduce<Record<string, BoardItem[]>>((acc, lane) => {
      acc[lane.key] = items.filter((item) => item.status === lane.key);
      return acc;
    }, {});
  }, [items]);

  async function loadBoard() {
    const sb = windowRef?.navGetSb?.();
    const member = windowRef?.navGetMember?.();
    if (!sb || !member) {
      window.addEventListener('nav:member', () => loadBoard(), { once: true });
      return;
    }

    const { data: tribeData } = await sb
      .from('tribes')
      .select('id,name,workstream_type')
      .eq('id', tribeId)
      .maybeSingle();

    const { data: boards } = await sb.rpc('list_project_boards', { p_tribe_id: tribeId });
    if (!Array.isArray(boards) || boards.length === 0) {
      setDenied(true);
      setLoading(false);
      return;
    }
    const activeBoard = boards[0];
    setBoardId(String(activeBoard.id));
    setCanEdit(canEditBoard(member, tribeData));

    const [{ data: boardItems }, { data: tribeMembers }] = await Promise.all([
      sb.rpc('list_board_items', { p_board_id: activeBoard.id, p_status: null }),
      sb.from('public_members').select('id,name,photo_url').eq('tribe_id', tribeId).eq('current_cycle_active', true).eq('is_active', true),
    ]);

    setMembers(Array.isArray(tribeMembers) ? tribeMembers : []);
    setItems((Array.isArray(boardItems) ? boardItems : []).filter((item: any) => item.status !== 'archived'));
    setLoading(false);
  }

  useEffect(() => {
    loadBoard().catch((error) => {
      console.warn('tribe kanban island load error', error);
      setDenied(true);
      setLoading(false);
    });
  }, []);

  function rollbackMove(itemId: string, from: string) {
    setItems((prev) => prev.map((row) => (row.id === itemId ? { ...row, status: from } : row)));
  }

  async function persistMove(itemId: string, newLane: string, previousLane: string) {
    const sb = windowRef?.navGetSb?.();
    if (!sb || !boardId) return;
    const { error } = await sb.rpc('move_board_item', {
      p_item_id: itemId,
      p_new_status: newLane,
      p_position: 0,
    });
    if (error) {
      rollbackMove(itemId, previousLane);
      windowRef?.toast?.(error.message || 'Falha ao mover card', 'error');
      return;
    }
    windowRef?.toast?.('Status atualizado', 'success');
  }

  async function onDragEnd(event: DragEndEvent) {
    setActiveId('');
    if (!canEdit) return;
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const itemId = String(active.id);
    const overId = String(over.id);
    const current = items.find((item) => item.id === itemId);
    if (!current) return;
    const directLane = LANES.find((lane) => lane.key === overId)?.key;
    const targetLane = directLane || items.find((row) => row.id === overId)?.status;
    if (!targetLane || targetLane === current.status) return;

    const previousLane = current.status;
    setItems((prev) => {
      const next = prev.map((row) => (row.id === itemId ? { ...row, status: targetLane } : row));
      const laneItems = next.filter((row) => row.status === targetLane);
      const oldIndex = laneItems.findIndex((row) => row.id === itemId);
      const overIndex = laneItems.findIndex((row) => row.id === overId);
      if (oldIndex >= 0 && overIndex >= 0) {
        const moved = arrayMove(laneItems, oldIndex, overIndex);
        const others = next.filter((row) => row.status !== targetLane);
        return [...others, ...moved];
      }
      return next;
    });
    await persistMove(itemId, targetLane, previousLane);
  }

  async function saveModal() {
    if (!modalItem) return;
    const sb = windowRef?.navGetSb?.();
    if (!sb || !boardId) return;
    const { error } = await sb.rpc('upsert_board_item', {
      p_item_id: modalItem.id || null,
      p_board_id: boardId,
      p_title: modalItem.title,
      p_description: modalItem.description || null,
      p_status: modalItem.status || 'backlog',
      p_assignee_id: modalItem.assignee_id || null,
      p_due_date: modalItem.due_date || null,
      p_tags: null,
      p_labels: [],
      p_checklist: parseChecklist(modalItem.checklist),
      p_attachments: parseAttachments(modalItem.attachments),
    });
    if (error) {
      windowRef?.toast?.(error.message || 'Nao foi possivel salvar', 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === modalItem.id ? { ...modalItem } : row)));
    setModalItem(null);
    windowRef?.toast?.('Card salvo com sucesso', 'success');
  }

  async function archiveModal() {
    if (!modalItem?.id) return;
    const sb = windowRef?.navGetSb?.();
    if (!sb) return;
    const { error } = await sb.rpc('admin_archive_board_item', {
      p_item_id: modalItem.id,
      p_reason: 'Archived from TribeKanbanIsland',
    });
    if (error) {
      windowRef?.toast?.(error.message || 'Nao foi possivel arquivar', 'error');
      return;
    }
    setItems((prev) => prev.filter((row) => row.id !== modalItem.id));
    setModalItem(null);
    windowRef?.toast?.('Card arquivado', 'success');
  }

  if (loading) {
    return <div className="text-center py-10 text-slate-400">{i18n.loading || 'Carregando...'}</div>;
  }
  if (denied) {
    return <div className="text-center py-10 text-slate-500 dark:text-slate-300">Acesso restrito para este quadro.</div>;
  }

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-5 gap-3">
        <DndContext
          collisionDetection={closestCorners}
          sensors={sensors}
          onDragStart={(event: DragStartEvent) => setActiveId(String(event.active.id))}
          onDragEnd={onDragEnd}
        >
          {LANES.map((lane) => (
            <section key={lane.key} className="rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-3">
              <div className="flex items-center justify-between mb-2">
                <h3 className="text-[12px] font-bold text-slate-700 dark:text-slate-200">{lane.label}</h3>
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
                    <SortableCard
                      key={item.id}
                      item={item}
                      canEdit={canEdit}
                      assigneePhoto={members.find((m) => m.id === item.assignee_id)?.photo_url || undefined}
                      onOpen={setModalItem}
                    />
                  ))}
                  {itemsByLane[lane.key].length === 0 ? (
                    <div className="text-[11px] text-slate-400 dark:text-slate-500 py-6 text-center">
                      {activeId ? 'Solte o card aqui' : 'Sem cards'}
                    </div>
                  ) : null}
                </div>
              </SortableContext>
            </section>
          ))}
        </DndContext>
      </div>

      {modalItem ? (
        <div className="fixed inset-0 z-50">
          <button
            type="button"
            className="absolute inset-0 bg-black/40 border-0 p-0 m-0 cursor-default"
            aria-label="close-modal-overlay"
            onClick={() => setModalItem(null)}
          />
          <div className="absolute top-1/2 left-1/2 w-full max-w-5xl -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-5 shadow-xl max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between gap-3 mb-3">
              <input
                value={modalItem.title || ''}
                onChange={(e) => setModalItem((prev) => (prev ? { ...prev, title: e.target.value } : prev))}
                className="flex-1 text-lg font-bold text-slate-900 dark:text-slate-100 bg-transparent border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2"
              />
              <button type="button" onClick={() => setModalItem(null)} className="p-2 rounded-lg border border-slate-200 dark:border-slate-700">
                <X size={16} />
              </button>
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
              <div className="lg:col-span-2 space-y-3">
                <textarea
                  value={modalItem.description || ''}
                  onChange={(e) => setModalItem((prev) => (prev ? { ...prev, description: e.target.value } : prev))}
                  rows={8}
                  className="w-full text-sm border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
                  placeholder="Descricao do card..."
                />
                <div className="space-y-2">
                  <p className="text-[12px] font-semibold text-slate-600 dark:text-slate-300">Checklist</p>
                  {parseChecklist(modalItem.checklist).map((item, idx) => (
                    <label key={`${item.text}-${idx}`} className="flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200">
                      <input
                        type="checkbox"
                        checked={item.done}
                        onChange={(e) => {
                          const checklist = parseChecklist(modalItem.checklist).map((row, rowIdx) => rowIdx === idx ? { ...row, done: e.target.checked } : row);
                          setModalItem((prev) => (prev ? { ...prev, checklist } : prev));
                        }}
                      />
                      <span>{item.text}</span>
                    </label>
                  ))}
                </div>
              </div>
              <aside className="space-y-3">
                <div>
                  <label className="text-[12px] font-semibold text-slate-600 dark:text-slate-300 block mb-1">Status</label>
                  <select
                    value={modalItem.status || 'backlog'}
                    onChange={(e) => setModalItem((prev) => (prev ? { ...prev, status: e.target.value } : prev))}
                    className="w-full border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
                  >
                    {LANES.map((lane) => (
                      <option key={lane.key} value={lane.key}>{lane.label}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-slate-600 dark:text-slate-300 block mb-1">Responsavel</label>
                  <select
                    value={modalItem.assignee_id || ''}
                    onChange={(e) => {
                      const selected = members.find((m) => m.id === e.target.value);
                      setModalItem((prev) => (prev ? { ...prev, assignee_id: e.target.value || null, assignee_name: selected?.name || null } : prev));
                    }}
                    className="w-full border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
                  >
                    <option value="">Sem responsavel</option>
                    {members.map((member) => (
                      <option key={member.id} value={member.id}>{member.name || 'Membro'}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-slate-600 dark:text-slate-300 block mb-1">Prazo</label>
                  <input
                    type="date"
                    value={modalItem.due_date ? String(modalItem.due_date).slice(0, 10) : ''}
                    onChange={(e) => setModalItem((prev) => (prev ? { ...prev, due_date: e.target.value || null } : prev))}
                    className="w-full border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
                  />
                </div>
                {canEdit ? (
                  <button
                    type="button"
                    onClick={archiveModal}
                    className="w-full inline-flex items-center justify-center gap-2 border border-red-200 dark:border-red-900 text-red-600 px-3 py-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/30"
                  >
                    <Trash2 size={14} /> Arquivar card
                  </button>
                ) : null}
              </aside>
            </div>
            <div className="mt-4 flex justify-end gap-2">
              <button type="button" onClick={() => setModalItem(null)} className="px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300">
                Cancelar
              </button>
              {canEdit ? (
                <button type="button" onClick={saveModal} className="px-3 py-2 rounded-lg bg-navy text-white">
                  Salvar
                </button>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
