/**
 * board.ts — Types for the BoardEngine
 * Maps 1:1 to Supabase schema (project_boards, board_items, board_lifecycle_events)
 */

// ─── Board ───────────────────────────────────────────────────────────────────

export interface Board {
  id: string;
  board_name: string;
  tribe_id: number | null;
  initiative_id: string | null;
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
  initiative_id?: string | null;
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
  baseline_date: string | null;
  forecast_date: string | null;
  actual_completion_date: string | null;
  mirror_source_id: string | null;
  mirror_target_id: string | null;
  is_mirror: boolean;
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
  assignments?: ItemAssignment[];
  is_portfolio_item?: boolean;
  baseline_locked_at?: string | null;
}

export type AssignmentRole = 'author' | 'reviewer' | 'contributor' | 'curation_reviewer';

export interface ItemAssignment {
  id?: string | null;
  member_id: string;
  name: string;
  avatar_url: string | null;
  role: AssignmentRole;
  assigned_at?: string;
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
  // W141: Extended fields from board_item_checklists table
  id?: string;
  assigned_to?: string | null;
  assigned_name?: string | null;
  target_date?: string | null;
  completed_at?: string | null;
  completed_by?: string | null;
  completed_by_name?: string | null;
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
  review_score: RubricScore | null;
  review_round: number | null;
  sla_deadline: string | null;
}

export interface RubricScore {
  clarity: number;
  originality: number;
  adherence: number;
  relevance: number;
  ethics: number;
  overall?: string;
}

export interface CurationReview {
  id: string;
  curator_name: string;
  curator_id: string;
  decision: 'approved' | 'returned_for_revision' | 'rejected';
  criteria_scores: RubricScore;
  feedback_notes: string | null;
  completed_at: string;
}

export interface CurationHistory {
  reviews: CurationReview[];
  assignments: { reviewer_name: string; reviewer_id: string; round: number; assigned_at: string; sla_deadline: string | null }[];
  sla_config: { sla_days: number; reviewers_required: number; max_review_rounds: number; rubric_criteria: string[] } | Record<string, never>;
}

// ─── Board Member (for pickers) ─────────────────────────────────────────────

export interface BoardMember {
  id: string;
  name: string;
  avatar_url: string | null;
  operational_role: string;
  board_role?: string;
  designations?: string[];
}

// ─── Board Summary (for selectors) ──────────────────────────────────────────

export interface BoardSummary {
  id: string;
  board_name: string;
  tribe_id: number | null;
  initiative_id: string | null;
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

// i18n-aware column label lookup
const COLUMN_LABELS_I18N: Record<string, Record<string, string>> = {
  backlog:     { 'pt-BR': 'Backlog', 'en-US': 'Backlog', 'es-LATAM': 'Backlog' },
  todo:        { 'pt-BR': 'A Fazer', 'en-US': 'To Do', 'es-LATAM': 'Por Hacer' },
  in_progress: { 'pt-BR': 'Em Andamento', 'en-US': 'In Progress', 'es-LATAM': 'En Progreso' },
  review:      { 'pt-BR': 'Revisão', 'en-US': 'Review', 'es-LATAM': 'Revisión' },
  done:        { 'pt-BR': 'Concluído', 'en-US': 'Done', 'es-LATAM': 'Completado' },
  archived:    { 'pt-BR': 'Arquivado', 'en-US': 'Archived', 'es-LATAM': 'Archivado' },
};

export function getColumnLabel(key: string, lang?: string): string {
  const locale = lang || (typeof window !== 'undefined' && (window as any).__CURRENT_LANG) || 'pt-BR';
  return COLUMN_LABELS_I18N[key]?.[locale] || COLUMN_PRESETS[key]?.label || key;
}

/** Safely coerce checklist to array — handles string, null, undefined */
/** Safely coerce any value to an array — handles string JSON, null, undefined, non-array */
export function safeArray<T = any>(v: unknown): T[] {
  if (!v) return [];
  if (Array.isArray(v)) return v;
  if (typeof v === 'string') { try { const p = JSON.parse(v); return Array.isArray(p) ? p : []; } catch { return []; } }
  return [];
}

export function safeChecklist(cl: unknown): ChecklistItem[] {
  return safeArray<ChecklistItem>(cl);
}

export function getColumnMeta(colId: string, lang?: string): ColumnMeta {
  const preset = COLUMN_PRESETS[colId];
  if (preset) return { id: colId, ...preset, label: getColumnLabel(colId, lang) };
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
  /** @deprecated Use initiativeId instead */
  tribeId?: number;
  initiativeId?: string;
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
  // Multi-assignee
  assignees?: string;
  addMember?: string;
  roleAuthor?: string;
  roleReviewer?: string;
  roleContributor?: string;
  roleCurationReviewer?: string;
  // Curation
  curationStatus?: string;
  curationDue?: string;
  curationTab?: string;
  curationReviews?: string;
  curationAwaitingReviewers?: string;
  curationApproved?: string;
  curationSubmitReview?: string;
  curationRound?: string;
  rubricClarity?: string;
  rubricOriginality?: string;
  rubricAdherence?: string;
  rubricRelevance?: string;
  rubricEthics?: string;
  // Source badges
  fromTrello?: string;
  fromNotion?: string;
  fromManual?: string;
  // Board rules popover
  boardRulesTitle?: string;
  boardRulesCardTitle?: string;
  boardRulesCardDesc?: string;
  boardRulesChecklistTitle?: string;
  boardRulesChecklistDesc?: string;
  boardRulesDatesTitle?: string;
  boardRulesDatesDesc?: string;
  changeReason?: string;
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
  checklist: 'Atividades',
  attachments: 'Anexos',
  timeline: 'Histórico',
  addItem: 'Adicionar atividade',
  noAssignee: 'Sem responsável',
  noReviewer: 'Sem revisor',
  overdue: 'Vencido',
  assignees: 'Participantes',
  addMember: 'Adicionar membro',
  roleAuthor: 'Autor',
  roleReviewer: 'Revisor',
  roleContributor: 'Contribuidor',
  roleCurationReviewer: 'Curador',
  curationStatus: 'Status de curadoria',
  curationDue: 'SLA de curadoria',
  curationTab: 'Curadoria',
  curationReviews: 'Pareceres',
  curationAwaitingReviewers: 'Aguardando revisores',
  curationApproved: 'Aprovado pelo Comitê',
  curationSubmitReview: 'Submeter Parecer',
  curationRound: 'Rodada',
  rubricClarity: 'Clareza e estrutura',
  rubricOriginality: 'Originalidade',
  rubricAdherence: 'Aderência ao tema',
  rubricRelevance: 'Relevância prática',
  rubricEthics: 'Conformidade ética',
  fromTrello: 'Trello',
  fromNotion: 'Notion',
  fromManual: 'Manual',
};
