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
import { CalendarClock, Paperclip, Trash2, UserCircle2, X, Send, CheckCircle2, Award } from 'lucide-react';
import * as Dialog from '@radix-ui/react-dialog';
import { VisuallyHidden } from '@radix-ui/react-visually-hidden';
import * as Popover from '@radix-ui/react-popover';

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
  curation_status?: string | null;
  reviewer_id?: string | null;
  reviewer_name?: string | null;
  due_date?: string | null;
  assignee_id?: string | null;
  assignee_name?: string | null;
  checklist?: ChecklistItem[] | string | null;
  attachments?: AttachmentItem[] | string | null;
  updated_at?: string | null;
  origin_tribe_id?: number | null;
  origin_tribe_name?: string | null;
  is_legacy?: boolean;
};

type Lane = { key: string; label: string };

const CURATION_LANES: Lane[] = [
  { key: 'draft', label: 'Rascunho' },
  { key: 'peer_review', label: 'Revisao por par' },
  { key: 'leader_review', label: 'Revisao do lider' },
  { key: 'curation_pending', label: 'Aguard. curadoria' },
  { key: 'published', label: 'Publicado' },
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
  if (member.is_superadmin === true) return true;
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
  onLaneKeyboardMove,
  members,
  currentMember,
  tribeData,
  onRequestReview,
  onApprovePeer,
  onApproveLeader,
  i18n,
}: {
  item: BoardItem;
  canEdit: boolean;
  assigneePhoto?: string;
  onOpen: (item: BoardItem) => void;
  onLaneKeyboardMove: (item: BoardItem, direction: -1 | 1) => void;
  members: Member[];
  currentMember: any;
  tribeData: any;
  onRequestReview: (item: BoardItem, reviewerId: string) => void;
  onApprovePeer: (item: BoardItem) => void;
  onApproveLeader: (item: BoardItem) => void;
  i18n: Record<string, string>;
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
  const curation = item.curation_status || 'draft';
  const isAuthor = currentMember?.id === item.assignee_id;
  const isReviewer = currentMember?.id === item.reviewer_id;
  const isLeader = currentMember?.operational_role === 'tribe_leader' && Number(currentMember?.tribe_id) === Number(tribeData?.id);
  const isSuperAdmin = currentMember?.is_superadmin === true;
  const isLeaderOrAdmin = isLeader || isSuperAdmin || ['manager', 'deputy_manager'].includes(String(currentMember?.operational_role || ''));

  const showRequestReview = curation === 'draft' && isAuthor && members.length > 0;
  const showApprovePeer = curation === 'peer_review' && isReviewer;
  const showApproveLeader = curation === 'leader_review' && isLeaderOrAdmin;

  const peers = members.filter((m) => m.id !== currentMember?.id && m.id !== item.assignee_id);

  return (
    <article
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      tabIndex={0}
      className={`rounded-xl border p-3 shadow-sm transition-all ${canEdit ? 'cursor-grab active:cursor-grabbing' : 'cursor-default'} border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900`}
      onClick={(e) => { if (!(e.target as HTMLElement).closest('button, [data-radix-collection-item]')) onOpen(item); }}
      onKeyDown={(e) => {
        if (e.shiftKey && e.key === 'ArrowLeft') {
          e.preventDefault();
          onLaneKeyboardMove(item, -1);
          return;
        }
        if (e.shiftKey && e.key === 'ArrowRight') {
          e.preventDefault();
          onLaneKeyboardMove(item, 1);
          return;
        }
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onOpen(item);
        }
      }}
    >
      <h4 className="text-[13px] font-semibold text-slate-900 dark:text-slate-100 mb-1 line-clamp-2">{item.title || 'Sem titulo'}</h4>
      {item.is_legacy && item.origin_tribe_name ? (
        <span className="inline-block text-[9px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300 font-bold mb-1">
          Legado: {item.origin_tribe_name}
        </span>
      ) : null}
      <div className="flex items-center gap-2 text-[11px] text-slate-500 dark:text-slate-300">
        {assigneePhoto ? (
          <img src={assigneePhoto} className="w-5 h-5 rounded-full object-cover" alt="assignee" />
        ) : (
          <UserCircle2 size={16} />
        )}
        <span className="truncate">{item.assignee_name || 'Sem responsavel'}</span>
      </div>
      {item.reviewer_name && curation === 'peer_review' ? (
        <div className="text-[10px] text-amber-600 mt-0.5">Revisor: {item.reviewer_name}</div>
      ) : null}
      <div className="mt-2 flex flex-wrap items-center gap-2 text-[11px]">
        {attachments.length > 0 ? (
          <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700">
            <Paperclip size={12} /> {attachments.length}
          </span>
        ) : null}
        {due ? (
          <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded ${due.getTime() < Date.now() && curation !== 'published' ? 'bg-red-50 text-red-700' : 'bg-slate-100 text-slate-600'}`}>
            <CalendarClock size={12} /> {due.toLocaleDateString('pt-BR')}
          </span>
        ) : null}
      </div>
      <div className="mt-2 flex flex-wrap gap-1">
        {showRequestReview ? (
          <Popover.Root>
            <Popover.Trigger asChild>
              <button
                type="button"
                onClick={(e) => e.stopPropagation()}
                className="inline-flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-semibold bg-navy text-white hover:opacity-90"
              >
                <Send size={12} /> {i18n.requestReview || 'Solicitar Revisao'}
              </button>
            </Popover.Trigger>
            <Popover.Portal>
              <Popover.Content
                className="rounded-lg border border-slate-200 bg-white dark:bg-slate-900 dark:border-slate-700 p-2 shadow-lg z-50 max-h-48 overflow-y-auto"
                sideOffset={4}
                onOpenAutoFocus={(e) => e.preventDefault()}
              >
                <div className="text-[11px] font-semibold text-slate-600 mb-1.5">{i18n.selectReviewer || 'Selecionar revisor'}</div>
                {peers.map((m) => (
                  <button
                    key={m.id}
                    type="button"
                    onClick={() => { onRequestReview(item, m.id); }}
                    className="block w-full text-left px-2 py-1.5 rounded hover:bg-slate-100 dark:hover:bg-slate-800 text-sm"
                  >
                    {m.name || 'Membro'}
                  </button>
                ))}
                {peers.length === 0 ? (
                  <div className="px-2 py-1.5 text-slate-400 text-[11px]">Nenhum colega disponivel</div>
                ) : null}
              </Popover.Content>
            </Popover.Portal>
          </Popover.Root>
        ) : null}
        {showApprovePeer ? (
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); onApprovePeer(item); }}
            className="inline-flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-semibold bg-emerald-600 text-white hover:opacity-90"
          >
            <CheckCircle2 size={12} /> {i18n.approvePeer || 'Aprovar (Peer)'}
          </button>
        ) : null}
        {showApproveLeader ? (
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); onApproveLeader(item); }}
            className="inline-flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-semibold bg-purple-600 text-white hover:opacity-90"
          >
            <Award size={12} /> {i18n.approveForCuration || 'Aprovar para Curadoria'}
          </button>
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
  const [tribeData, setTribeData] = useState<any>(null);
  const [currentMember, setCurrentMember] = useState<any>(null);
  const ui = {
    deniedBoard: i18n?.deniedBoard || 'Acesso restrito para este quadro.',
    checklist: i18n?.checklist || 'Checklist',
    status: i18n?.status || 'Status',
    assignee: i18n?.assignee || 'Responsavel',
    noAssignee: i18n?.noAssignee || 'Sem responsavel',
    dueDate: i18n?.dueDate || 'Prazo',
    archiveCard: i18n?.archiveCard || 'Arquivar card',
    cancel: i18n?.cancel || 'Cancelar',
    save: i18n?.save || 'Salvar',
    requestReview: i18n?.requestReview || 'Solicitar Revisao',
    approvePeer: i18n?.approvePeer || 'Aprovar (Peer)',
    approveForCuration: i18n?.approveForCuration || 'Aprovar para Curadoria',
    selectReviewer: i18n?.selectReviewer || 'Selecionar revisor',
  };

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const itemsByLane = useMemo(() => {
    return CURATION_LANES.reduce<Record<string, BoardItem[]>>((acc, lane) => {
      acc[lane.key] = items.filter((item) => (item.curation_status || 'draft') === lane.key);
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

    const [{ data: boardItems, error: boardErr }, { data: tribeMembers }] = await Promise.all([
      sb.rpc('list_board_items', { p_board_id: activeBoard.id, p_status: null }),
      sb.from('public_members').select('id,name,photo_url').eq('tribe_id', tribeId).eq('current_cycle_active', true).eq('is_active', true),
    ]);
    console.log('[Kanban] Board items:', Array.isArray(boardItems) ? boardItems.length : 'NOT_ARRAY', 'Error:', boardErr);

    let legacyRaw: BoardItem[] = [];
    try {
      const { data: legacyData, error: legacyErr } = await sb.rpc('list_legacy_board_items_for_tribe', { p_current_tribe_id: tribeId });
      console.log('[Kanban] Legacy items:', Array.isArray(legacyData) ? legacyData.length : 'NOT_ARRAY', 'Error:', legacyErr);
      if (!legacyErr && Array.isArray(legacyData)) {
        legacyRaw = legacyData
          .filter((item: any) => item.status !== 'archived')
          .map((row: any) => ({ ...row, is_legacy: true, curation_status: row.curation_status || 'draft' }));
      }
    } catch (e) { console.warn('[Kanban] Legacy fetch failed:', e); }

    setMembers(Array.isArray(tribeMembers) ? tribeMembers : []);
    setTribeData(tribeData);
    setCurrentMember(member);
    const raw = (Array.isArray(boardItems) ? boardItems : []).filter((item: any) => item.status !== 'archived');
    const combined = [
      ...raw.map((row: any) => ({ ...row, curation_status: row.curation_status || 'draft' })),
      ...legacyRaw,
    ];
    console.log('[Kanban] Combined items:', combined.length, '(board:', raw.length, '+ legacy:', legacyRaw.length, ')');
    setItems(combined);
    setLoading(false);
  }

  useEffect(() => {
    loadBoard().catch((error) => {
      console.warn('tribe kanban island load error', error);
      setDenied(true);
      setLoading(false);
    });
  }, []);

  function rollbackCuration(itemId: string, from: string) {
    setItems((prev) => prev.map((row) => (row.id === itemId ? { ...row, curation_status: from } : row)));
  }

  async function persistMove(itemId: string, newCurationStatus: string, previousCurationStatus: string) {
    const sb = windowRef?.navGetSb?.();
    if (!sb || !boardId) return;
    const item = items.find((i) => i.id === itemId);
    if (!item) return;
    if (previousCurationStatus === newCurationStatus) {
      // Same-lane reorder: use move_board_item to update position only
      const { error } = await sb.rpc('move_board_item', {
        p_item_id: itemId,
        p_new_status: item.status || 'backlog',
        p_position: 0,
      });
      if (error) {
        rollbackCuration(itemId, previousCurationStatus);
        windowRef?.toast?.(error.message || 'Falha ao reordenar', 'error');
      }
      return;
    }
    if (previousCurationStatus === 'peer_review' && newCurationStatus === 'leader_review' && item.reviewer_id === currentMember?.id) {
      const { error } = await sb.rpc('advance_board_item_curation', { p_item_id: itemId, p_action: 'approve_peer', p_reviewer_id: null });
      if (error) {
        rollbackCuration(itemId, previousCurationStatus);
        windowRef?.toast?.(error.message || 'Falha', 'error');
        return;
      }
      windowRef?.toast?.('Aprovado (Peer)', 'success');
      return;
    }
    if (previousCurationStatus === 'leader_review' && newCurationStatus === 'curation_pending') {
      const isLeader = currentMember?.operational_role === 'tribe_leader' && Number(currentMember?.tribe_id) === Number(tribeData?.id);
      const isAdmin = currentMember?.is_superadmin || ['manager', 'deputy_manager'].includes(String(currentMember?.operational_role || ''));
      if (isLeader || isAdmin) {
        const { error } = await sb.rpc('advance_board_item_curation', { p_item_id: itemId, p_action: 'approve_leader', p_reviewer_id: null });
        if (error) {
          rollbackCuration(itemId, previousCurationStatus);
          windowRef?.toast?.(error.message || 'Falha', 'error');
          return;
        }
        windowRef?.toast?.('Enviado para curadoria', 'success');
        return;
      }
    }
    rollbackCuration(itemId, previousCurationStatus);
    windowRef?.toast?.('Transicao nao permitida', 'error');
  }

  async function moveViaKeyboard(item: BoardItem, direction: -1 | 1) {
    if (!canEdit) return;
    const cur = item.curation_status || 'draft';
    if (direction > 0 && cur === 'peer_review' && item.reviewer_id === currentMember?.id) {
      await handleApprovePeer(item);
      return;
    }
    if (direction > 0 && cur === 'leader_review') {
      const isLeader = currentMember?.operational_role === 'tribe_leader' && Number(currentMember?.tribe_id) === Number(tribeData?.id);
      const isAdmin = currentMember?.is_superadmin || ['manager', 'deputy_manager'].includes(String(currentMember?.operational_role || ''));
      if (isLeader || isAdmin) {
        await handleApproveLeader(item);
      }
    }
  }

  async function handleRequestReview(item: BoardItem, reviewerId: string) {
    const sb = windowRef?.navGetSb?.();
    if (!sb) return;
    const { error } = await sb.rpc('advance_board_item_curation', {
      p_item_id: item.id,
      p_action: 'request_review',
      p_reviewer_id: reviewerId,
    });
    if (error) {
      windowRef?.toast?.(error.message || 'Falha ao solicitar revisao', 'error');
      return;
    }
    const reviewer = members.find((m) => m.id === reviewerId);
    setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, curation_status: 'peer_review', reviewer_id: reviewerId, reviewer_name: reviewer?.name } : row)));
    windowRef?.toast?.('Revisao solicitada', 'success');
  }

  async function handleApprovePeer(item: BoardItem) {
    const sb = windowRef?.navGetSb?.();
    if (!sb) return;
    const { error } = await sb.rpc('advance_board_item_curation', {
      p_item_id: item.id,
      p_action: 'approve_peer',
      p_reviewer_id: null,
    });
    if (error) {
      windowRef?.toast?.(error.message || 'Falha ao aprovar', 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, curation_status: 'leader_review' } : row)));
    windowRef?.toast?.('Aprovado (Peer)', 'success');
  }

  async function handleApproveLeader(item: BoardItem) {
    const sb = windowRef?.navGetSb?.();
    if (!sb) return;
    const { error } = await sb.rpc('advance_board_item_curation', {
      p_item_id: item.id,
      p_action: 'approve_leader',
      p_reviewer_id: null,
    });
    if (error) {
      windowRef?.toast?.(error.message || 'Falha ao aprovar para curadoria', 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, curation_status: 'curation_pending' } : row)));
    windowRef?.toast?.('Enviado para curadoria', 'success');
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
    const cur = current.curation_status || 'draft';
    const directLane = CURATION_LANES.find((lane) => lane.key === overId)?.key;
    const overItem = items.find((row) => row.id === overId);
    const targetLane = directLane || (overItem ? (overItem.curation_status || 'draft') : null);
    if (!targetLane) return;

    const isSameLane = targetLane === cur;
    const isCrossLaneCuration = (cur === 'peer_review' && targetLane === 'leader_review') || (cur === 'leader_review' && targetLane === 'curation_pending');
    const canCurationTransition = (cur === 'peer_review' && targetLane === 'leader_review' && current.reviewer_id === currentMember?.id)
      || (cur === 'leader_review' && targetLane === 'curation_pending' && (currentMember?.operational_role === 'tribe_leader' || currentMember?.is_superadmin || ['manager', 'deputy_manager'].includes(String(currentMember?.operational_role || ''))));

    if (!isSameLane && !(isCrossLaneCuration && canCurationTransition)) {
      return;
    }

    setItems((prev) => {
      const next = isSameLane ? prev : prev.map((row) => (row.id === itemId ? { ...row, curation_status: targetLane } : row));
      if (overItem && targetLane === (overItem.curation_status || 'draft')) {
        const laneItems = (isSameLane ? prev : next).filter((row) => (row.curation_status || 'draft') === targetLane);
        const oldIndex = laneItems.findIndex((row) => row.id === itemId);
        const overIndex = laneItems.findIndex((row) => row.id === overId);
        if (oldIndex >= 0 && overIndex >= 0) {
          const moved = arrayMove(laneItems, oldIndex, overIndex);
          const others = (isSameLane ? prev : next).filter((row) => (row.curation_status || 'draft') !== targetLane);
          return [...others, ...moved];
        }
      }
      return isSameLane ? prev : next;
    });
    await persistMove(itemId, targetLane, cur);
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
      p_status: modalItem.status || (modalItem.curation_status || 'draft'),
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
    return <div className="text-center py-10 text-slate-500 dark:text-slate-300">{ui.deniedBoard}</div>;
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
          {CURATION_LANES.map((lane) => (
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
                      onLaneKeyboardMove={moveViaKeyboard}
                      members={members}
                      currentMember={currentMember}
                      tribeData={tribeData}
                      onRequestReview={handleRequestReview}
                      onApprovePeer={handleApprovePeer}
                      onApproveLeader={handleApproveLeader}
                      i18n={ui}
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

      <Dialog.Root open={!!modalItem} onOpenChange={(open) => { if (!open) setModalItem(null); }}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-50 bg-black/40" />
          <Dialog.Content className="fixed z-50 top-1/2 left-1/2 w-full max-w-5xl -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-5 shadow-xl max-h-[90vh] overflow-y-auto" aria-describedby={undefined}>
            <VisuallyHidden asChild><Dialog.Title>Editar card</Dialog.Title></VisuallyHidden>
            {!modalItem ? null : (
              <>
            <div className="flex items-center justify-between gap-3 mb-3">
              <input
                value={modalItem.title || ''}
                onChange={(e) => setModalItem((prev) => (prev ? { ...prev, title: e.target.value } : prev))}
                className="flex-1 text-lg font-bold text-slate-900 dark:text-slate-100 bg-transparent border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2"
              />
              <Dialog.Close asChild>
                <button type="button" className="p-2 rounded-lg border border-slate-200 dark:border-slate-700">
                <X size={16} />
              </button>
              </Dialog.Close>
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
                  <p className="text-[12px] font-semibold text-slate-600 dark:text-slate-300">{ui.checklist}</p>
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
                  <label className="text-[12px] font-semibold text-slate-600 dark:text-slate-300 block mb-1">{ui.status}</label>
                  <select
                    value={modalItem.curation_status || 'draft'}
                    onChange={(e) => setModalItem((prev) => (prev ? { ...prev, curation_status: e.target.value } : prev))}
                    className="w-full border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
                  >
                    {CURATION_LANES.map((lane) => (
                      <option key={lane.key} value={lane.key}>{lane.label}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-slate-600 dark:text-slate-300 block mb-1">{ui.assignee}</label>
                  <select
                    value={modalItem.assignee_id || ''}
                    onChange={(e) => {
                      const selected = members.find((m) => m.id === e.target.value);
                      setModalItem((prev) => (prev ? { ...prev, assignee_id: e.target.value || null, assignee_name: selected?.name || null } : prev));
                    }}
                    className="w-full border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100"
                  >
                    <option value="">{ui.noAssignee}</option>
                    {members.map((member) => (
                      <option key={member.id} value={member.id}>{member.name || 'Membro'}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-slate-600 dark:text-slate-300 block mb-1">{ui.dueDate}</label>
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
                    <Trash2 size={14} /> {ui.archiveCard}
                  </button>
                ) : null}
              </aside>
            </div>
            <div className="mt-4 flex justify-end gap-2">
              <button type="button" onClick={() => setModalItem(null)} className="px-3 py-2 rounded-lg border border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300">
                {ui.cancel}
              </button>
              {canEdit ? (
                <button type="button" onClick={saveModal} className="px-3 py-2 rounded-lg bg-navy text-white">
                  {ui.save}
                </button>
              ) : null}
            </div>
              </>
            )}
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </div>
  );
}
