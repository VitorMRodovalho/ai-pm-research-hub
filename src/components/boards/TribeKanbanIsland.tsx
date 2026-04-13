import React, { useEffect, useMemo, useState } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { trackEvent } from '../../lib/analytics';
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
import { hasPermission } from '../../lib/permissions';
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

const BOARD_LANE_KEYS = ['backlog', 'todo', 'doing', 'done'] as const;
const CURATION_LANE_KEYS = ['peer_review', 'leader_review', 'curation_pending', 'published'] as const;

function buildLanes(keys: readonly string[], t: (k: string, fb?: string) => string): Lane[] {
  const labels: Record<string, string> = {
    backlog: t('comp.kanban.lane.backlog', 'Backlog'),
    todo: t('comp.kanban.lane.todo', 'A Fazer'),
    doing: t('comp.kanban.lane.doing', 'Em Progresso'),
    done: t('comp.kanban.lane.done', 'Concluido'),
    peer_review: t('comp.kanban.lane.peerReview', 'Revisao por par'),
    leader_review: t('comp.kanban.lane.leaderReview', 'Revisao do lider'),
    curation_pending: t('comp.kanban.lane.curationPending', 'Aguard. curadoria'),
    published: t('comp.kanban.lane.published', 'Publicado'),
  };
  return keys.map(key => ({ key, label: labels[key] || key }));
}

function resolveItemLane(item: BoardItem): string {
  const cs = item.curation_status;
  if (cs && cs !== 'draft' && ['peer_review', 'leader_review', 'curation_pending', 'published'].includes(cs)) {
    return cs;
  }
  const st = (item.status || 'backlog').toLowerCase();
  if (['todo', 'to_do', 'a fazer'].includes(st)) return 'todo';
  if (['doing', 'in_progress', 'em progresso', 'review'].includes(st)) return 'doing';
  if (['done', 'concluido', 'complete'].includes(st)) return 'done';
  return 'backlog';
}

const ALL_LANE_KEYS = [...BOARD_LANE_KEYS, ...CURATION_LANE_KEYS];

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
  if (hasPermission(member, 'admin.access')) return true;
  if (hasPermission(member, 'board.edit_tribe_items') && Number(member.tribe_id || 0) === Number(tribe?.id || 0)) return true;
  const isCommsOperational = String(tribe?.workstream_type || '').toLowerCase() === 'operational'
    && (String(tribe?.name || '').toLowerCase().includes('comunica')
      || String(tribe?.name_i18n?.en || '').toLowerCase().includes('communication'));
  if (isCommsOperational && hasPermission(member, 'board.view_global')) return true;
  return false;
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
  const t = usePageI18n();
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id,
    disabled: !canEdit,
  });
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
    touchAction: 'none',
  };
  const attachments = parseAttachments(item.attachments);
  const due = item.due_date ? new Date(item.due_date) : null;
  const curation = item.curation_status || 'draft';
  const isAuthor = currentMember?.id === item.assignee_id;
  const isReviewer = currentMember?.id === item.reviewer_id;
  const isLeaderOrAdmin = hasPermission(currentMember, 'admin.access') || (hasPermission(currentMember, 'board.edit_tribe_items') && Number(currentMember?.tribe_id) === Number(tribeData?.id));

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
      className={`rounded-xl border p-3 shadow-sm transition-all ${canEdit ? 'cursor-grab active:cursor-grabbing' : 'cursor-default'} border-[var(--border-default)] bg-[var(--surface-card)]`}
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
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onOpen(item); }}
        className="text-[13px] font-semibold text-[var(--text-primary)] mb-1 line-clamp-2 text-left w-full bg-transparent border-0 p-0 cursor-pointer hover:underline"
      >{item.title || t('comp.kanban.untitled', 'Sem titulo')}</button>
      {item.is_legacy && item.origin_tribe_name ? (
        <span className="inline-block text-[9px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300 font-bold mb-1">
          {i18n.legacyLabel || 'Legado:'} {item.origin_tribe_name}
        </span>
      ) : null}
      <div className="flex items-center gap-2 text-[11px] text-[var(--text-secondary)]">
        {assigneePhoto ? (
          <img src={assigneePhoto} className="w-5 h-5 rounded-full object-cover" alt="assignee" />
        ) : (
          <UserCircle2 size={16} />
        )}
        <span className="truncate">{item.assignee_name || t('comp.kanban.noAssignee', 'Sem responsavel')}</span>
      </div>
      {item.reviewer_name && curation === 'peer_review' ? (
        <div className="text-[10px] text-amber-600 mt-0.5">{i18n.reviewerLabel || 'Revisor:'} {item.reviewer_name}</div>
      ) : null}
      <div className="mt-2 flex flex-wrap items-center gap-2 text-[11px]">
        {attachments.length > 0 ? (
          <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700 dark:bg-indigo-950/30 dark:text-indigo-300">
            <Paperclip size={12} /> {attachments.length}
          </span>
        ) : null}
        {due ? (
          <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded ${due.getTime() < Date.now() && curation !== 'published' ? 'bg-red-50 text-red-700 dark:bg-red-950/30 dark:text-red-300' : 'bg-[var(--surface-section-cool)] text-[var(--text-secondary)]'}`}>
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
                className="rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] p-2 shadow-lg z-50 max-h-48 overflow-y-auto"
                sideOffset={4}
                onOpenAutoFocus={(e) => e.preventDefault()}
              >
                <div className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1.5">{i18n.selectReviewer || 'Selecionar revisor'}</div>
                {peers.map((m) => (
                  <button
                    key={m.id}
                    type="button"
                    onClick={() => { onRequestReview(item, m.id); }}
                    className="block w-full text-left px-2 py-1.5 rounded hover:bg-[var(--surface-hover)] text-sm"
                  >
                    {m.name || t('comp.kanban.member', 'Membro')}
                  </button>
                ))}
                {peers.length === 0 ? (
                  <div className="px-2 py-1.5 text-[var(--text-muted)] text-[11px]">{i18n.noPeersAvailable || 'Nenhum colega disponivel'}</div>
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

export default function TribeKanbanIsland({ tribeId, initiativeId, i18n }: { tribeId?: number; initiativeId?: string; i18n: TribeKanbanI18n }) {
  const t = usePageI18n();
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
  const BOARD_LANES = useMemo(() => buildLanes(BOARD_LANE_KEYS, t), [t]);
  const CURATION_LANES = useMemo(() => buildLanes(CURATION_LANE_KEYS, t), [t]);
  const ALL_LANES = useMemo(() => [...BOARD_LANES, ...CURATION_LANES], [BOARD_LANES, CURATION_LANES]);

  const ui = {
    deniedBoard: i18n?.deniedBoard || t('comp.kanban.deniedBoard', 'Acesso restrito para este quadro.'),
    checklist: i18n?.checklist || t('comp.kanban.checklist', 'Checklist'),
    status: i18n?.status || t('comp.kanban.status', 'Status'),
    assignee: i18n?.assignee || t('comp.kanban.assignee', 'Responsavel'),
    noAssignee: i18n?.noAssignee || t('comp.kanban.noAssignee', 'Sem responsavel'),
    dueDate: i18n?.dueDate || t('comp.kanban.dueDate', 'Prazo'),
    archiveCard: i18n?.archiveCard || t('comp.kanban.archiveCard', 'Arquivar card'),
    cancel: i18n?.cancel || t('comp.kanban.cancel', 'Cancelar'),
    save: i18n?.save || t('comp.kanban.save', 'Salvar'),
    requestReview: i18n?.requestReview || t('comp.kanban.requestReview', 'Solicitar Revisao'),
    approvePeer: i18n?.approvePeer || t('comp.kanban.approvePeer', 'Aprovar (Peer)'),
    approveForCuration: i18n?.approveForCuration || t('comp.kanban.approveForCuration', 'Aprovar para Curadoria'),
    selectReviewer: i18n?.selectReviewer || t('comp.kanban.selectReviewer', 'Selecionar revisor'),
    legacyLabel: i18n?.legacyLabel || t('comp.kanban.legacyLabel', 'Legado:'),
    reviewerLabel: i18n?.reviewerLabel || t('comp.kanban.reviewerLabel', 'Revisor:'),
    noPeersAvailable: i18n?.noPeersAvailable || t('comp.kanban.noPeersAvailable', 'Nenhum colega disponivel'),
    tribeBoardTitle: i18n?.tribeBoardTitle || t('comp.kanban.tribeBoardTitle', 'Quadro da Tribo'),
    curationPipelineTitle: i18n?.curationPipelineTitle || t('comp.kanban.curationPipelineTitle', 'Esteira de Curadoria'),
    cardsCount: i18n?.cardsCount || t('comp.kanban.cardsCount', 'cards'),
    editCardTitle: i18n?.editCardTitle || t('comp.kanban.editCardTitle', 'Editar card'),
  };

  const laneLabels: Record<string, string> = {
    backlog: t('comp.kanban.lane.backlog', 'Backlog'),
    todo: t('comp.kanban.lane.todo', 'A Fazer'),
    doing: t('comp.kanban.lane.doing', 'Em Progresso'),
    done: t('comp.kanban.lane.done', 'Concluido'),
    peer_review: t('comp.kanban.lane.peerReview', 'Revisao por par'),
    leader_review: t('comp.kanban.lane.leaderReview', 'Revisao do lider'),
    curation_pending: t('comp.kanban.lane.curationPending', 'Aguard. curadoria'),
    published: t('comp.kanban.lane.published', 'Publicado'),
  };

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const itemsByLane = useMemo(() => {
    const acc: Record<string, BoardItem[]> = {};
    for (const lane of ALL_LANES) acc[lane.key] = [];
    for (const item of items) {
      const lane = resolveItemLane(item);
      if (acc[lane]) acc[lane].push(item);
      else acc['backlog'].push(item);
    }
    return acc;
  }, [items]);

  async function loadBoard() {
    const sb = windowRef?.navGetSb?.();
    const member = windowRef?.navGetMember?.();
    if (!sb || !member) {
      window.addEventListener('nav:member', () => loadBoard(), { once: true });
      return;
    }

    const { data: tribeData } = initiativeId
      ? await sb.from('tribes').select('id,name,name_i18n,workstream_type').eq('initiative_id', initiativeId).maybeSingle()
      : await sb.from('tribes').select('id,name,name_i18n,workstream_type').eq('id', tribeId).maybeSingle();

    const { data: boards } = initiativeId
      ? await sb.rpc('list_initiative_boards', { p_initiative_id: initiativeId })
      : await sb.rpc('list_project_boards', { p_tribe_id: tribeId });
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
      initiativeId
        ? sb.from('public_members').select('id,name,photo_url').eq('initiative_id', initiativeId).eq('current_cycle_active', true).eq('is_active', true)
        : sb.from('public_members').select('id,name,photo_url').eq('tribe_id', tribeId).eq('current_cycle_active', true).eq('is_active', true),
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
    const laneDistrib: Record<string, number> = {};
    for (const it of combined) { const l = resolveItemLane(it); laneDistrib[l] = (laneDistrib[l] || 0) + 1; }
    console.log('[Kanban] Combined items:', combined.length, '(board:', raw.length, '+ legacy:', legacyRaw.length, ') Lanes:', JSON.stringify(laneDistrib));
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

  const boardLaneKeySet = new Set(BOARD_LANES.map((l) => l.key));

  function rollbackMove(itemId: string, previousLane: string) {
    setItems((prev) => prev.map((row) => {
      if (row.id !== itemId) return row;
      if (boardLaneKeySet.has(previousLane)) return { ...row, status: previousLane };
      return { ...row, curation_status: previousLane };
    }));
  }

  async function persistMove(itemId: string, targetLane: string, previousLane: string) {
    const sb = windowRef?.navGetSb?.();
    if (!sb || !boardId) return;
    const item = items.find((i) => i.id === itemId);
    if (!item) return;

    if (previousLane === targetLane) {
      const { error } = await sb.rpc('move_board_item', {
        p_item_id: itemId,
        p_new_status: item.status || 'backlog',
        p_position: 0,
      });
      if (error) {
        rollbackMove(itemId, previousLane);
        windowRef?.toast?.(error.message || t('comp.kanban.errorReorder', 'Falha ao reordenar'), 'error');
      }
      return;
    }

    if (boardLaneKeySet.has(previousLane) && boardLaneKeySet.has(targetLane)) {
      const { error } = await sb.rpc('move_board_item', {
        p_item_id: itemId,
        p_new_status: targetLane,
        p_position: 0,
      });
      if (error) {
        rollbackMove(itemId, previousLane);
        windowRef?.toast?.(error.message || t('comp.kanban.errorMove', 'Falha ao mover'), 'error');
      } else {
        trackEvent('board_card_moved', { card_id: itemId, from_status: previousLane, to_status: targetLane, tribe_id: tribeId });
      }
      return;
    }

    if (previousLane === 'peer_review' && targetLane === 'leader_review' && item.reviewer_id === currentMember?.id) {
      const { error } = await sb.rpc('advance_board_item_curation', { p_item_id: itemId, p_action: 'approve_peer', p_reviewer_id: null });
      if (error) {
        rollbackMove(itemId, previousLane);
        windowRef?.toast?.(error.message || t('comp.kanban.errorGeneric', 'Falha'), 'error');
        return;
      }
      windowRef?.toast?.(t('comp.kanban.approvedPeer', 'Aprovado (Peer)'), 'success');
      return;
    }
    if (previousLane === 'leader_review' && targetLane === 'curation_pending') {
      const isLeaderOrAdminForCuration = hasPermission(currentMember, 'admin.access') || (hasPermission(currentMember, 'board.edit_tribe_items') && Number(currentMember?.tribe_id) === Number(tribeData?.id));
      if (isLeaderOrAdminForCuration) {
        const { error } = await sb.rpc('advance_board_item_curation', { p_item_id: itemId, p_action: 'approve_leader', p_reviewer_id: null });
        if (error) {
          rollbackMove(itemId, previousLane);
          windowRef?.toast?.(error.message || t('comp.kanban.errorGeneric', 'Falha'), 'error');
          return;
        }
        windowRef?.toast?.(t('comp.kanban.sentToCuration', 'Enviado para curadoria'), 'success');
        return;
      }
    }
    rollbackMove(itemId, previousLane);
    windowRef?.toast?.(t('comp.kanban.transitionNotAllowed', 'Transicao nao permitida'), 'error');
  }

  async function moveViaKeyboard(item: BoardItem, direction: -1 | 1) {
    if (!canEdit) return;
    const curLane = resolveItemLane(item);

    if (boardLaneKeySet.has(curLane)) {
      const idx = BOARD_LANES.findIndex((l) => l.key === curLane);
      const nextIdx = idx + direction;
      if (nextIdx >= 0 && nextIdx < BOARD_LANES.length) {
        const targetLane = BOARD_LANES[nextIdx].key;
        setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, status: targetLane } : row)));
        await persistMove(item.id, targetLane, curLane);
      }
      return;
    }

    if (direction > 0 && curLane === 'peer_review' && item.reviewer_id === currentMember?.id) {
      await handleApprovePeer(item);
      return;
    }
    if (direction > 0 && curLane === 'leader_review') {
      const isLeaderOrAdminForCuration = hasPermission(currentMember, 'admin.access') || (hasPermission(currentMember, 'board.edit_tribe_items') && Number(currentMember?.tribe_id) === Number(tribeData?.id));
      if (isLeaderOrAdminForCuration) {
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
      windowRef?.toast?.(error.message || t('comp.kanban.errorRequestReview', 'Falha ao solicitar revisao'), 'error');
      return;
    }
    const reviewer = members.find((m) => m.id === reviewerId);
    setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, curation_status: 'peer_review', reviewer_id: reviewerId, reviewer_name: reviewer?.name } : row)));
    windowRef?.toast?.(t('comp.kanban.reviewRequested', 'Revisao solicitada'), 'success');
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
      windowRef?.toast?.(error.message || t('comp.kanban.errorApprove', 'Falha ao aprovar'), 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, curation_status: 'leader_review' } : row)));
    windowRef?.toast?.(t('comp.kanban.approvedPeer', 'Aprovado (Peer)'), 'success');
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
      windowRef?.toast?.(error.message || t('comp.kanban.errorApproveCuration', 'Falha ao aprovar para curadoria'), 'error');
      return;
    }
    setItems((prev) => prev.map((row) => (row.id === item.id ? { ...row, curation_status: 'curation_pending' } : row)));
    windowRef?.toast?.(t('comp.kanban.sentToCuration', 'Enviado para curadoria'), 'success');
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
    const curLane = resolveItemLane(current);
    const directLane = ALL_LANES.find((lane) => lane.key === overId)?.key;
    const overItem = items.find((row) => row.id === overId);
    const targetLane = directLane || (overItem ? resolveItemLane(overItem) : null);
    if (!targetLane) return;

    const isSameLane = targetLane === curLane;
    const bothBoard = boardLaneKeySet.has(curLane) && boardLaneKeySet.has(targetLane);
    const isCrossLaneCuration = (curLane === 'peer_review' && targetLane === 'leader_review') || (curLane === 'leader_review' && targetLane === 'curation_pending');
    const canCurationTransition = (curLane === 'peer_review' && targetLane === 'leader_review' && current.reviewer_id === currentMember?.id)
      || (curLane === 'leader_review' && targetLane === 'curation_pending' && (hasPermission(currentMember, 'admin.access') || (hasPermission(currentMember, 'board.edit_tribe_items') && Number(currentMember?.tribe_id) === Number(tribeData?.id))));

    if (!isSameLane && !bothBoard && !(isCrossLaneCuration && canCurationTransition)) {
      return;
    }

    setItems((prev) => {
      const applyLane = (row: BoardItem): BoardItem => {
        if (boardLaneKeySet.has(targetLane)) return { ...row, status: targetLane };
        return { ...row, curation_status: targetLane };
      };
      const next = isSameLane ? prev : prev.map((row) => (row.id === itemId ? applyLane(row) : row));
      if (overItem && targetLane === resolveItemLane(overItem)) {
        const laneItems = (isSameLane ? prev : next).filter((row) => resolveItemLane(row) === targetLane);
        const oldIndex = laneItems.findIndex((row) => row.id === itemId);
        const overIndex = laneItems.findIndex((row) => row.id === overId);
        if (oldIndex >= 0 && overIndex >= 0) {
          const moved = arrayMove(laneItems, oldIndex, overIndex);
          const others = (isSameLane ? prev : next).filter((row) => resolveItemLane(row) !== targetLane);
          return [...others, ...moved];
        }
      }
      return isSameLane ? prev : next;
    });
    await persistMove(itemId, targetLane, curLane);
    if (curLane !== targetLane) trackEvent('board_card_moved', { tribe_id: tribeId, from_column: curLane, to_column: targetLane });
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
      windowRef?.toast?.(error.message || t('comp.kanban.errorSave', 'Nao foi possivel salvar'), 'error');
      return;
    }
    const isNew = !modalItem.id || !items.some((row) => row.id === modalItem.id);
    setItems((prev) => prev.map((row) => (row.id === modalItem.id ? { ...modalItem } : row)));
    setModalItem(null);
    windowRef?.toast?.(t('comp.kanban.cardSaved', 'Card salvo com sucesso'), 'success');
    if (isNew) trackEvent('board_card_created', { tribe_id: tribeId, card_type: modalItem.status || 'backlog' });
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
      windowRef?.toast?.(error.message || t('comp.kanban.errorArchive', 'Nao foi possivel arquivar'), 'error');
      return;
    }
    setItems((prev) => prev.filter((row) => row.id !== modalItem.id));
    setModalItem(null);
    windowRef?.toast?.(t('comp.kanban.cardArchived', 'Card arquivado'), 'success');
  }

  if (loading) {
    return <div className="text-center py-10 text-[var(--text-muted)]">{i18n.loading || t('comp.kanban.loading', 'Carregando...')}</div>;
  }
  if (denied) {
    return <div className="text-center py-10 text-[var(--text-secondary)]">{ui.deniedBoard}</div>;
  }

  const boardLaneItems = BOARD_LANES.reduce((n, l) => n + (itemsByLane[l.key]?.length || 0), 0);
  const curationLaneItems = CURATION_LANES.reduce((n, l) => n + (itemsByLane[l.key]?.length || 0), 0);
  const boardCountLabel = `(${boardLaneItems} ${ui.cardsCount || 'cards'})`;
  const curationCountLabel = `(${curationLaneItems} ${ui.cardsCount || 'cards'})`;

  return (
    <div className="space-y-6">
      <DndContext
        collisionDetection={closestCorners}
        sensors={sensors}
        onDragStart={(event: DragStartEvent) => setActiveId(String(event.active.id))}
        onDragEnd={onDragEnd}
      >
        {/* Board workflow lanes */}
        <section className="space-y-2">
          <h2 className="text-sm font-bold text-[var(--text-primary)]">
            {ui.tribeBoardTitle}
            <span className="ml-2 text-[11px] font-normal text-[var(--text-muted)]">{boardCountLabel}</span>
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
            {BOARD_LANES.map((lane) => (
              <section key={lane.key} className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3">
                <div className="flex items-center justify-between mb-2">
                  <h3 className="text-[12px] font-bold text-[var(--text-primary)]">{laneLabels[lane.key] || lane.label}</h3>
                  <span className="text-[10px] px-2 py-0.5 rounded-full bg-[var(--surface-section-cool)] text-[var(--text-secondary)]">
                    {itemsByLane[lane.key]?.length || 0}
                  </span>
                </div>
                <SortableContext
                  id={lane.key}
                  items={(itemsByLane[lane.key] || []).map((item) => item.id)}
                  strategy={verticalListSortingStrategy}
                >
                  <div id={lane.key} className="min-h-[120px] max-h-[60vh] overflow-y-auto space-y-2">
                    {(itemsByLane[lane.key] || []).map((item) => (
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
                    {(itemsByLane[lane.key]?.length || 0) === 0 ? (
                      <div className="text-[11px] text-[var(--text-muted)] py-6 text-center">
                        {activeId ? t('comp.kanban.dropCardHere', 'Solte o card aqui') : t('comp.kanban.noCards', 'Sem cards')}
                      </div>
                    ) : null}
                  </div>
                </SortableContext>
              </section>
            ))}
          </div>
        </section>

        {/* Curation workflow lanes — only shown if items exist */}
        {curationLaneItems > 0 ? (
          <section className="space-y-2">
            <h2 className="text-sm font-bold text-purple-700 dark:text-purple-300">
              {ui.curationPipelineTitle}
              <span className="ml-2 text-[11px] font-normal text-[var(--text-muted)]">{curationCountLabel}</span>
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
              {CURATION_LANES.map((lane) => (
                <section key={lane.key} className="rounded-2xl border border-purple-200 dark:border-purple-800 bg-purple-50/30 dark:bg-purple-900/10 p-3">
                  <div className="flex items-center justify-between mb-2">
                    <h3 className="text-[12px] font-bold text-purple-700 dark:text-purple-300">{laneLabels[lane.key] || lane.label}</h3>
                    <span className="text-[10px] px-2 py-0.5 rounded-full bg-purple-100 dark:bg-purple-900/50 text-purple-600 dark:text-purple-300">
                      {itemsByLane[lane.key]?.length || 0}
                    </span>
                  </div>
                  <SortableContext
                    id={lane.key}
                    items={(itemsByLane[lane.key] || []).map((item) => item.id)}
                    strategy={verticalListSortingStrategy}
                  >
                    <div id={lane.key} className="min-h-[120px] max-h-[60vh] overflow-y-auto space-y-2">
                      {(itemsByLane[lane.key] || []).map((item) => (
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
                      {(itemsByLane[lane.key]?.length || 0) === 0 ? (
                        <div className="text-[11px] text-[var(--text-muted)] py-6 text-center">
                          {activeId ? t('comp.kanban.dropCardHere', 'Solte o card aqui') : t('comp.kanban.noCards', 'Sem cards')}
                        </div>
                      ) : null}
                    </div>
                  </SortableContext>
                </section>
              ))}
            </div>
          </section>
        ) : null}
      </DndContext>

      <Dialog.Root open={!!modalItem} onOpenChange={(open) => { if (!open) setModalItem(null); }}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-50 bg-black/40" />
          <Dialog.Content className="fixed z-50 top-1/2 left-1/2 w-full max-w-5xl -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-[var(--border-default)] bg-[var(--surface-elevated)] p-5 shadow-xl max-h-[90vh] overflow-y-auto" aria-describedby={undefined}>
            <VisuallyHidden asChild><Dialog.Title>{ui.editCardTitle}</Dialog.Title></VisuallyHidden>
            {!modalItem ? null : (
              <>
            <div className="flex items-center justify-between gap-3 mb-3">
              <input
                value={modalItem.title || ''}
                onChange={(e) => setModalItem((prev) => (prev ? { ...prev, title: e.target.value } : prev))}
                className="flex-1 text-lg font-bold text-[var(--text-primary)] bg-transparent border border-[var(--border-default)] rounded-lg px-3 py-2"
              />
              <Dialog.Close asChild>
                <button type="button" className="p-2 rounded-lg border border-[var(--border-default)]">
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
                  className="w-full text-sm border border-[var(--border-default)] rounded-lg px-3 py-2 bg-[var(--surface-card)] text-[var(--text-primary)]"
                  placeholder={t('comp.kanban.descriptionPlaceholder', 'Descricao do card...')}
                />
                <div className="space-y-2">
                  <p className="text-[12px] font-semibold text-[var(--text-secondary)]">{ui.checklist}</p>
                  {parseChecklist(modalItem.checklist).map((item, idx) => (
                    <label key={`${item.text}-${idx}`} className="flex items-center gap-2 text-sm text-[var(--text-primary)]">
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
                  <label className="text-[12px] font-semibold text-[var(--text-secondary)] block mb-1">{ui.status}</label>
                  <select
                    value={resolveItemLane(modalItem)}
                    onChange={(e) => {
                      const lane = e.target.value;
                      if (boardLaneKeySet.has(lane)) {
                        setModalItem((prev) => (prev ? { ...prev, status: lane, curation_status: 'draft' } : prev));
                      } else {
                        setModalItem((prev) => (prev ? { ...prev, curation_status: lane } : prev));
                      }
                    }}
                    className="w-full border border-[var(--border-default)] rounded-lg px-3 py-2 bg-[var(--surface-card)] text-[var(--text-primary)]"
                  >
                    {ALL_LANES.map((lane) => (
                      <option key={lane.key} value={lane.key}>{laneLabels[lane.key] || lane.label}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-[var(--text-secondary)] block mb-1">{ui.assignee}</label>
                  <select
                    value={modalItem.assignee_id || ''}
                    onChange={(e) => {
                      const selected = members.find((m) => m.id === e.target.value);
                      setModalItem((prev) => (prev ? { ...prev, assignee_id: e.target.value || null, assignee_name: selected?.name || null } : prev));
                    }}
                    className="w-full border border-[var(--border-default)] rounded-lg px-3 py-2 bg-[var(--surface-card)] text-[var(--text-primary)]"
                  >
                    <option value="">{ui.noAssignee}</option>
                    {members.map((member) => (
                      <option key={member.id} value={member.id}>{member.name || t('comp.kanban.member', 'Membro')}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[12px] font-semibold text-[var(--text-secondary)] block mb-1">{ui.dueDate}</label>
                  <input
                    type="date"
                    value={modalItem.due_date ? String(modalItem.due_date).slice(0, 10) : ''}
                    onChange={(e) => setModalItem((prev) => (prev ? { ...prev, due_date: e.target.value || null } : prev))}
                    className="w-full border border-[var(--border-default)] rounded-lg px-3 py-2 bg-[var(--surface-card)] text-[var(--text-primary)]"
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
              <button type="button" onClick={() => setModalItem(null)} className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-[var(--text-secondary)]">
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
