/**
 * board.ts — Types for the BoardEngine
 * Maps 1:1 to Supabase schema (project_boards, board_items, board_lifecycle_events)
 */

// ─── Board ───────────────────────────────────────────────────────────────────

export interface Board {
  id: string;
  board_name: string;
  tribe_id: number | null;
  source: 'trello' | 'notion' | 'manual';
  columns: string[];
  is_active: boolean;
  domain_key: string | null;
  board_scope: 'global' | 'tribe';
  cycle_scope: number | null;
}

// ─── Board Item (Card) ──────────────────────────────────────────────────────

export interface BoardItem {
  id: string;
  board_id?: string;
  board_name?: string;
  tribe_id?: number | null;
  domain_key?: string | null;
  title: string;
  description: string | null;
  status: string;
  assignee_id: string | null;
  assignee_name: string | null;
  reviewer_id: string | null;
  reviewer_name: string | null;
  tags: string[];
  labels: Label[];
  due_date: string | null;
  position: number;
  attachments: Attachment[];
  checklist: ChecklistItem[];
  curation_status: CurationStatus;
  curation_due_at: string | null;
  cycle: number | null;
  source_card_id: string | null;
  source_board: string | null;
  created_at: string;
  updated_at: string;
}

export interface Label {
  color: string;
  text: string;
}

export interface Attachment {
  name: string;
  url: string;
}

export interface ChecklistItem {
  text: string;
  done: boolean;
}

export type CurationStatus = 'draft' | 'review' | 'approved' | 'rejected';

// ─── Lifecycle Event ────────────────────────────────────────────────────────

export interface LifecycleEvent {
  id: number;
  action: string;
  previous_status: string | null;
  new_status: string | null;
  reason: string | null;
  actor_name: string | null;
  created_at: string;
}

// ─── Board Member (for pickers) ─────────────────────────────────────────────

export interface BoardMember {
  id: string;
  full_name: string;
  avatar_url: string | null;
  operational_role: string;
}

// ─── Board Summary (for selectors) ──────────────────────────────────────────

export interface BoardSummary {
  id: string;
  board_name: string;
  tribe_id: number | null;
  domain_key: string | null;
  board_scope: string;
  source: string;
  item_count: number;
}

// ─── Column metadata ────────────────────────────────────────────────────────

export interface ColumnMeta {
  id: string;
  label: string;
  icon: string;
  color: string;
  dotColor: string;
  borderColor: string;
  bgColor: string;
  badgeBg: string;
  badgeText: string;
}

export const COLUMN_PRESETS: Record<string, Omit<ColumnMeta, 'id'>> = {
  backlog: {
    label: 'Backlog', icon: '📋', color: 'slate',
    dotColor: 'bg-slate-400', borderColor: 'border-slate-200',
    bgColor: 'bg-slate-50/50', badgeBg: 'bg-slate-100', badgeText: 'text-slate-600',
  },
  todo: {
    label: 'A Fazer', icon: '📌', color: 'blue',
    dotColor: 'bg-blue-400', borderColor: 'border-blue-200',
    bgColor: 'bg-blue-50/30', badgeBg: 'bg-blue-100', badgeText: 'text-blue-700',
  },
  in_progress: {
    label: 'Em Andamento', icon: '🔨', color: 'amber',
    dotColor: 'bg-amber-400', borderColor: 'border-amber-200',
    bgColor: 'bg-amber-50/30', badgeBg: 'bg-amber-100', badgeText: 'text-amber-700',
  },
  review: {
    label: 'Revisão', icon: '🔍', color: 'purple',
    dotColor: 'bg-purple-400', borderColor: 'border-purple-200',
    bgColor: 'bg-purple-50/30', badgeBg: 'bg-purple-100', badgeText: 'text-purple-700',
  },
  done: {
    label: 'Concluído', icon: '✅', color: 'emerald',
    dotColor: 'bg-emerald-500', borderColor: 'border-emerald-200',
    bgColor: 'bg-emerald-50/30', badgeBg: 'bg-emerald-100', badgeText: 'text-emerald-700',
  },
  archived: {
    label: 'Arquivado', icon: '📦', color: 'gray',
    dotColor: 'bg-gray-400', borderColor: 'border-gray-200',
    bgColor: 'bg-gray-50/30', badgeBg: 'bg-gray-100', badgeText: 'text-gray-500',
  },
};

export function getColumnMeta(colId: string): ColumnMeta {
  const preset = COLUMN_PRESETS[colId];
  if (preset) return { id: colId, ...preset };
  // Fallback for unknown columns
  return {
    id: colId, label: colId, icon: '📄', color: 'slate',
    dotColor: 'bg-slate-400', borderColor: 'border-slate-200',
    bgColor: 'bg-slate-50/50', badgeBg: 'bg-slate-100', badgeText: 'text-slate-600',
  };
}

// ─── Component Props ────────────────────────────────────────────────────────

export interface BoardEngineProps {
  boardId?: string;
  domainKey?: string;
  tribeId?: number;
  scope?: 'global' | 'tribe';
  mode?: 'default' | 'curation' | 'readonly';
  i18n?: BoardI18n;
}

export interface BoardI18n {
  // Board
  newCard?: string;
  search?: string;
  filterAll?: string;
  empty?: string;
  loading?: string;
  error?: string;
  retry?: string;
  // Card
  approve?: string;
  reject?: string;
  editTags?: string;
  saveTags?: string;
  save?: string;
  cancel?: string;
  delete?: string;
  duplicate?: string;
  moveTo?: string;
  archive?: string;
  // Card detail
  description?: string;
  assignee?: string;
  reviewer?: string;
  tags?: string;
  dueDate?: string;
  checklist?: string;
  attachments?: string;
  timeline?: string;
  addItem?: string;
  noAssignee?: string;
  noReviewer?: string;
  overdue?: string;
  // Curation
  curationStatus?: string;
  curationDue?: string;
  // Source badges
  fromTrello?: string;
  fromNotion?: string;
  fromManual?: string;
}

export const DEFAULT_I18N: BoardI18n = {
  newCard: 'Novo Card',
  search: 'Buscar...',
  filterAll: 'Todos',
  empty: 'Nenhum item neste board',
  loading: 'Carregando board...',
  error: 'Erro ao carregar',
  retry: 'Tentar novamente',
  approve: 'Aprovar',
  reject: 'Descartar',
  editTags: 'Editar Tags',
  saveTags: 'Salvar Tags',
  save: 'Salvar',
  cancel: 'Cancelar',
  delete: 'Excluir',
  duplicate: 'Duplicar',
  moveTo: 'Mover para...',
  archive: 'Arquivar',
  description: 'Descrição',
  assignee: 'Responsável',
  reviewer: 'Revisor',
  tags: 'Tags',
  dueDate: 'Data limite',
  checklist: 'Checklist',
  attachments: 'Anexos',
  timeline: 'Histórico',
  addItem: 'Adicionar item',
  noAssignee: 'Sem responsável',
  noReviewer: 'Sem revisor',
  overdue: 'Vencido',
  curationStatus: 'Status de curadoria',
  curationDue: 'SLA de curadoria',
  fromTrello: 'Trello',
  fromNotion: 'Notion',
  fromManual: 'Manual',
};
