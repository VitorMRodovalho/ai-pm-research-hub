/**
 * CuratorshipBoardIsland — Unified Curatorship Super-Kanban
 *
 * Two boards in one:
 * 1. Tribe board_items (curation_pending → published) via submit_curation_review RPC
 * 2. Legacy artifacts/hub_resources via curate_item RPC
 *
 * Uses @dnd-kit for drag-and-drop (desktop + mobile/touch + keyboard).
 * Access: admin+, curator, co_gp.
 */
import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react';
import {
  DndContext,
  DragOverlay,
  closestCorners,
  PointerSensor,
  TouchSensor,
  KeyboardSensor,
  useSensor,
  useSensors,
  useDroppable,
} from '@dnd-kit/core';
import type { DragEndEvent, DragStartEvent, DragOverEvent } from '@dnd-kit/core';
import {
  SortableContext,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import {
  CheckCircle2, RotateCcw, XCircle, Clock, AlertTriangle,
  FileText, User, Star, ChevronDown, ChevronUp, Loader2, RefreshCw,
} from 'lucide-react';
import * as Dialog from '@radix-ui/react-dialog';
import { VisuallyHidden } from '@radix-ui/react-visually-hidden';

// ─── Types ──────────────────────────────────────────────────────────────────

type ReviewHistoryEntry = {
  id: string;
  curator_name?: string | null;
  decision: string;
  feedback?: string | null;
  scores?: Record<string, number> | null;
  completed_at: string;
};

type BoardItem = {
  id: string;
  title: string;
  description?: string | null;
  tribe_name?: string | null;
  assignee_name?: string | null;
  reviewer_name?: string | null;
  updated_at?: string | null;
  curation_status?: string | null;
  curation_due_at?: string | null;
  attachments?: { url: string }[] | string | null;
  review_count?: number;
  review_history?: ReviewHistoryEntry[] | null;
};

type LegacyItem = {
  id: string;
  title: string;
  description?: string | null;
  _table: string;
  status: string;
  tags?: string[];
  suggested_tags?: string[];
  author_name?: string | null;
  tribe_name?: string | null;
  source?: string | null;
};

type I18n = Record<string, string>;

// ─── Helpers ────────────────────────────────────────────────────────────────

import { getSb, waitForSb } from '../../hooks/useBoard';
import { useMemberContext } from '../../hooks/useBoardPermissions';
import { hasPermission } from '../../lib/permissions';
import { usePageI18n } from '../../i18n/usePageI18n';

function daysUntilDue(dueAt: string | null | undefined): number | null {
  if (!dueAt) return null;
  return Math.ceil((new Date(dueAt).getTime() - Date.now()) / 86400000);
}

const CRITERIA = [
  { key: 'clarity', label: 'Clareza', tip: 'Compreensível sem contexto adicional?' },
  { key: 'originality', label: 'Originalidade', tip: 'Perspectiva ou abordagem nova?' },
  { key: 'adherence', label: 'Aderência', tip: 'Alinhado com o quadrante da tribo?' },
  { key: 'relevance', label: 'Relevância', tip: 'Contribui para o corpo de conhecimento?' },
  { key: 'ethics', label: 'Ética', tip: 'Respeita IA responsável e governança?' },
] as const;

// ─── SLA Badge ──────────────────────────────────────────────────────────────

function SlaBadge({ dueAt, ui = {} }: { dueAt?: string | null; ui?: Record<string, string> }) {
  const days = daysUntilDue(dueAt);
  if (days === null) return null;
  if (days < 0) return (
    <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-red-100 dark:bg-red-950/30 text-red-700 dark:text-red-300 font-bold animate-pulse">
      <AlertTriangle size={10} /> {Math.abs(days)}{ui.slaOverdue || 'd atrasado'}
    </span>
  );
  if (days <= 2) return (
    <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700 font-bold">
      <Clock size={10} /> {days}{ui.slaDays || 'd'}
    </span>
  );
  return (
    <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-[var(--surface-section-cool)] text-[var(--text-secondary)]">
      <Clock size={10} /> {days}{ui.slaDays || 'd'}
    </span>
  );
}

// ─── Tribe Board Item Card (Sortable) ───────────────────────────────────────

function TribeSortableCard({ item, onOpen, ui = {} }: { item: BoardItem; onOpen: (item: BoardItem) => void; ui?: Record<string, string> }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: item.id });
  const isOverdue = (daysUntilDue(item.curation_due_at) ?? 1) < 0;

  return (
    <article
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.4 : 1, touchAction: 'none' }}
      {...attributes}
      {...listeners}
      className={`rounded-xl border bg-[var(--surface-card)] p-3 shadow-sm cursor-grab active:cursor-grabbing hover:shadow-md transition-all ${
        isOverdue ? 'border-red-300 ring-1 ring-red-200' : 'border-[var(--border-default)]'
      }`}
    >
      <div className="flex items-start justify-between gap-2 mb-1">
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onOpen(item); }}
          onPointerDown={(e) => e.stopPropagation()}
          className="text-[12px] font-bold text-[var(--text-primary)] line-clamp-2 flex-1 text-left hover:underline cursor-pointer bg-transparent border-0 p-0"
        >
          {item.title || 'Sem título'}
        </button>
        <SlaBadge dueAt={item.curation_due_at} ui={ui} />
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        {item.tribe_name ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300 font-semibold">{item.tribe_name}</span>
        ) : null}
        {((item as any).reviews_approved != null && (item as any).reviewers_required) ? (
          <span className={`text-[10px] px-1.5 py-0.5 rounded font-semibold ${
            (item as any).reviews_approved >= (item as any).reviewers_required
              ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300' : 'bg-violet-100 text-violet-600'
          }`}>{(item as any).reviews_approved}{String('/')}{(item as any).reviewers_required}{' '}{ui.reviewersLabel || 'revisores'}</span>
        ) : (item.review_count || 0) > 0 ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-violet-100 text-violet-600">{item.review_count}{ui.timesReviewed || 'x avaliado'}</span>
        ) : null}
      </div>
      {item.assignee_name ? <p className="text-[11px] text-[var(--text-secondary)] mt-1 truncate">{item.assignee_name}</p> : null}
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onOpen(item); }}
        onPointerDown={(e) => e.stopPropagation()}
        className="mt-2 w-full py-1.5 rounded-lg text-[11px] font-semibold bg-blue-900/10 text-blue-900 hover:bg-blue-900/20 cursor-pointer border-0 transition-colors"
      >
        {ui.evaluate || 'Avaliar'}
      </button>
    </article>
  );
}

// ─── Legacy Item Card (Sortable) ────────────────────────────────────────────

function LegacySortableCard({ item, onApprove, onReject, tribes = [], ui = {} }: {
  item: LegacyItem;
  onApprove: (id: string, table: string, tribeId?: number | null) => void;
  onReject: (id: string, table: string) => void;
  tribes?: { id: number; name: string }[];
  ui?: Record<string, string>;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: item.id, data: { item } });
  const icon = item._table === 'artifacts' ? '📄' : '📚';
  const [confirming, setConfirming] = useState(false);
  const [selectedTribe, setSelectedTribe] = useState<number | null>(null);

  return (
    <article
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.4 : 1, touchAction: 'none' }}
      {...attributes}
      {...listeners}
      className="kanban-card rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3 shadow-sm cursor-grab active:cursor-grabbing hover:shadow-md transition-all"
    >
      <h4 className="text-[12px] font-bold text-[var(--text-primary)] line-clamp-2 mb-1">{icon}{' '}{item.title}</h4>
      {item.tribe_name ? (
        <span className="inline-block text-[10px] px-1.5 py-0.5 rounded bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300 font-semibold mb-1">{item.tribe_name}</span>
      ) : null}
      {item.author_name ? <p className="text-[10px] text-[var(--text-muted)] mb-1">{item.author_name}</p> : null}
      {(item.tags?.length || 0) > 0 ? (
        <div className="flex flex-wrap gap-1 mb-1">
          {item.tags!.slice(0, 3).map((tag) => (
            <span key={tag} className="px-1.5 py-0.5 bg-[var(--surface-section-cool)] text-[var(--text-secondary)] rounded text-[9px] font-medium">{tag}</span>
          ))}
        </div>
      ) : null}
      <div className="flex flex-col gap-1.5 mt-2 pt-2 border-t border-[var(--border-subtle)]" onPointerDown={(e) => e.stopPropagation()}>
        {confirming ? (
          <div className="cur-confirm-approve flex flex-col gap-1.5">
            <select
              value={selectedTribe ?? ''}
              onChange={(e) => setSelectedTribe(e.target.value ? Number(e.target.value) : null)}
              className="cur-approve-tribe w-full rounded-lg border border-emerald-200 dark:border-emerald-800 bg-emerald-50 dark:bg-emerald-950/30 text-[10px] px-2 py-1"
            >
              <option value="">{ui.noTribe || '— Sem tribo —'}</option>
              {tribes.map((t) => {
                const _sl = typeof window !== 'undefined' ? (window.location.pathname.startsWith('/en') ? 'en' : window.location.pathname.startsWith('/es') ? 'es' : 'pt') : 'pt';
                return <option key={t.id} value={t.id}>{(t as any).name_i18n?.[_sl] || t.name}</option>;
              })}
            </select>
            <div className="flex gap-1.5">
              <button
                onClick={() => { onApprove(item.id, item._table, selectedTribe); setConfirming(false); }}
                className="flex-1 px-2 py-1 rounded-lg bg-emerald-100 text-emerald-800 text-[10px] font-semibold border border-emerald-300 hover:bg-emerald-200 cursor-pointer transition-colors"
              >
                {ui.confirmApprove || '✅ Confirmar'}
              </button>
              <button
                onClick={() => setConfirming(false)}
                className="px-2 py-1 rounded-lg bg-gray-100 text-gray-600 text-[10px] font-semibold border border-gray-200 hover:bg-gray-200 cursor-pointer transition-colors"
              >
                {ui.cancel || '✕'}
              </button>
            </div>
          </div>
        ) : (
          <div className="flex gap-1.5">
            {item.status !== 'approved' ? (
              <button
                onClick={() => setConfirming(true)}
                className="cur-btn-approve flex-1 px-2 py-1 rounded-lg bg-emerald-50 dark:bg-emerald-950/30 text-emerald-700 dark:text-emerald-300 text-[10px] font-semibold border border-emerald-200 dark:border-emerald-800 hover:bg-emerald-100 dark:hover:bg-emerald-900 cursor-pointer transition-colors"
              >
                {ui.approveBtn || '✅ Aprovar'}
              </button>
            ) : null}
            {item.status !== 'rejected' ? (
              <button
                onClick={() => onReject(item.id, item._table)}
                className="flex-1 px-2 py-1 rounded-lg bg-red-50 dark:bg-red-950/30 text-red-600 dark:text-red-300 text-[10px] font-semibold border border-red-200 dark:border-red-800 hover:bg-red-100 dark:hover:bg-red-900 cursor-pointer transition-colors"
              >
                {ui.discardBtn || '❌ Descartar'}
              </button>
            ) : null}
          </div>
        )}
      </div>
    </article>
  );
}

// ─── Droppable Column ───────────────────────────────────────────────────────

function DroppableColumn({ id, children }: { id: string; children: React.ReactNode }) {
  const { setNodeRef, isOver } = useDroppable({ id });
  return (
    <div
      ref={setNodeRef}
      className={`min-h-[200px] max-h-[60vh] overflow-y-auto space-y-2.5 p-2.5 rounded-xl border-2 border-dashed transition-all ${
        isOver ? 'ring-2 ring-blue-300 dark:ring-blue-700 border-blue-300 dark:border-blue-700 bg-blue-50/40 dark:bg-blue-950/20 scale-[1.01]' : 'border-[var(--border-default)] bg-[var(--surface-base)]/50'
      }`}
    >
      {children}
    </div>
  );
}

// ─── Score Input ────────────────────────────────────────────────────────────

function ScoreInput({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  return (
    <div className="flex gap-1">
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          type="button"
          onClick={() => onChange(n)}
          className={`w-7 h-7 rounded-lg text-xs font-bold transition-all ${
            n <= value ? 'bg-blue-900 text-white shadow-sm' : 'bg-[var(--surface-section-cool)] text-[var(--text-muted)] hover:bg-[var(--surface-hover)]'
          }`}
        >{n}</button>
      ))}
    </div>
  );
}

// ─── Review Rubric Dialog ───────────────────────────────────────────────────

function ReviewRubricDialog({ item, open, onClose, onSubmit, ui = {} }: {
  item: BoardItem; open: boolean; onClose: () => void;
  onSubmit: (decision: string, scores: Record<string, number>, feedback: string) => Promise<void>;
  ui?: Record<string, string>;
}) {
  const [scores, setScores] = useState<Record<string, number>>({});
  const [feedback, setFeedback] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [showHistory, setShowHistory] = useState(false);

  const allScored = CRITERIA.every((c) => (scores[c.key] || 0) > 0);
  const avgScore = allScored
    ? (CRITERIA.reduce((s, c) => s + (scores[c.key] || 0), 0) / CRITERIA.length).toFixed(1)
    : null;

  async function handleAction(decision: string) {
    if (decision !== 'approved' && !feedback.trim()) return;
    setSubmitting(true);
    try { await onSubmit(decision, scores, feedback); } finally { setSubmitting(false); }
  }

  useEffect(() => { if (open) { setScores({}); setFeedback(''); setShowHistory(false); } }, [open, item?.id]);

  const historyBtnLabel = `${ui.historyLabel || 'Histórico'} (${item.review_history?.length || 0})`;

  return (
    <Dialog.Root open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50" />
        <Dialog.Content
          className="fixed right-0 top-0 h-full w-full max-w-lg bg-[var(--surface-elevated)] shadow-2xl z-50 overflow-y-auto"
          aria-describedby={undefined}
        >
          <VisuallyHidden asChild><Dialog.Title>{ui.reviewDialogTitle || 'Avaliação de curadoria'}</Dialog.Title></VisuallyHidden>

          <div className="sticky top-0 bg-[var(--surface-elevated)] border-b border-[var(--border-default)] px-6 py-4 z-10">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <FileText size={18} className="text-blue-900" />
                <h2 className="text-base font-bold text-blue-900">{ui.reviewHeading || 'Avaliação de Curadoria'}</h2>
              </div>
              <Dialog.Close asChild>
                <button className="p-1.5 rounded-lg hover:bg-[var(--surface-hover)] text-[var(--text-muted)] border-0 bg-transparent cursor-pointer">
                  <XCircle size={18} />
                </button>
              </Dialog.Close>
            </div>
          </div>

          <div className="px-6 py-5 space-y-6">
            <section className="space-y-2">
              <h3 className="text-sm font-bold text-blue-900">{item.title}</h3>
              <div className="flex flex-wrap gap-2">
                {item.tribe_name ? <span className="text-[11px] px-2 py-0.5 rounded-full bg-[var(--surface-section-cool)] text-[var(--text-secondary)]">{item.tribe_name}</span> : null}
                <SlaBadge dueAt={item.curation_due_at} ui={ui} />
              </div>
              {item.assignee_name ? <p className="text-xs text-[var(--text-secondary)] flex items-center gap-1"><User size={12} /> {item.assignee_name}</p> : null}
              {item.description ? <p className="text-xs text-[var(--text-secondary)] whitespace-pre-wrap max-h-32 overflow-y-auto bg-[var(--surface-base)] rounded-lg p-3">{item.description}</p> : null}
            </section>

            {item.review_history && item.review_history.length > 0 ? (
              <section>
                <button type="button" onClick={() => setShowHistory(!showHistory)} className="flex items-center gap-1 text-xs font-semibold text-violet-600 hover:underline bg-transparent border-0 cursor-pointer p-0">
                  {showHistory ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                  {historyBtnLabel}
                </button>
                {showHistory ? (
                  <div className="mt-2 space-y-2">
                    {item.review_history.map((r) => (
                      <div key={r.id} className="text-xs bg-[var(--surface-base)] rounded-lg p-3 space-y-1">
                        <div className="flex items-center justify-between">
                          <span className="font-semibold text-[var(--text-primary)]">{r.curator_name || '—'}</span>
                          <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${r.decision === 'approved' ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300' : r.decision === 'rejected' ? 'bg-red-100 text-red-700 dark:bg-red-950/30 dark:text-red-300' : 'bg-amber-100 text-amber-700'}`}>
                            {r.decision === 'approved' ? (ui.histApproved || 'Aprovado') : r.decision === 'rejected' ? (ui.histRejected || 'Rejeitado') : (ui.histReturned || 'Devolvido')}
                          </span>
                        </div>
                        {r.feedback ? <p className="text-[var(--text-secondary)]">{r.feedback}</p> : null}
                      </div>
                    ))}
                  </div>
                ) : null}
              </section>
            ) : null}

            <section className="space-y-3">
              <div className="flex items-center justify-between">
                <h4 className="text-sm font-bold text-blue-900 flex items-center gap-1.5"><Star size={14} /> {ui.rubric || 'Rubrica'}</h4>
                {avgScore ? (
                  <span className={`text-sm font-bold px-2 py-0.5 rounded-full ${parseFloat(avgScore) >= 4 ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300' : parseFloat(avgScore) >= 3 ? 'bg-amber-100 text-amber-700' : 'bg-red-100 text-red-700 dark:bg-red-950/30 dark:text-red-300'}`}>
                    {avgScore}
                  </span>
                ) : null}
              </div>
              {CRITERIA.map((c) => (
                <div key={c.key} className="flex items-center justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-semibold text-[var(--text-primary)]">{c.label}</p>
                    <p className="text-[10px] text-[var(--text-muted)] truncate">{c.tip}</p>
                  </div>
                  <ScoreInput value={scores[c.key] || 0} onChange={(v) => setScores((p) => ({ ...p, [c.key]: v }))} />
                </div>
              ))}
            </section>

            <section className="space-y-2">
              <label className="text-xs font-bold text-blue-900">{ui.feedbackLabel || pt('comp.curation.feedbackForTribe', 'Feedback para a Tribo')}</label>
              <textarea
                value={feedback} onChange={(e) => setFeedback(e.target.value)} rows={3}
                placeholder="Obrigatório para devoluções e rejeições..."
                className="w-full rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] px-3 py-2 text-xs text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none focus:ring-2 focus:ring-blue-900/30 resize-none"
              />
            </section>

            <section className="flex flex-col gap-2 pt-2 border-t border-[var(--border-default)]">
              <button type="button" disabled={!allScored || submitting} onClick={() => handleAction('approved')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors border-0 cursor-pointer">
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />} {ui.approvePublish || 'Aprovar e Publicar'}
              </button>
              <button type="button" disabled={!feedback.trim() || submitting} onClick={() => handleAction('returned_for_revision')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-amber-700 bg-amber-100 hover:bg-amber-200 disabled:opacity-40 disabled:cursor-not-allowed transition-colors border-0 cursor-pointer">
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <RotateCcw size={16} />} {ui.returnToTribe || pt('comp.curation.returnToTribe', 'Devolver à Tribo')}
              </button>
              <button type="button" disabled={!feedback.trim() || submitting} onClick={() => handleAction('rejected')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-red-600 dark:text-red-300 bg-red-50 dark:bg-red-950/30 hover:bg-red-100 dark:hover:bg-red-900 disabled:opacity-40 disabled:cursor-not-allowed transition-colors border-0 cursor-pointer">
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <XCircle size={16} />} {ui.reject || 'Rejeitar'}
              </button>
            </section>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

// ─── Drag Overlay ───────────────────────────────────────────────────────────

function DragOverlayCard({ title }: { title: string }) {
  return (
    <div className="bg-[var(--surface-card)] rounded-xl border-2 border-blue-300 dark:border-blue-700 p-3 shadow-xl rotate-[3deg] w-[260px] opacity-95">
      <h4 className="text-[12px] font-bold text-[var(--text-primary)] line-clamp-2">{title}</h4>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────────────

export default function CuratorshipBoardIsland({ i18n }: { i18n?: I18n }) {
  const pt = usePageI18n();
  const { member: authMember, isLoading: memberLoading } = useMemberContext();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [denied, setDenied] = useState(false);

  const [tribeItems, setTribeItems] = useState<BoardItem[]>([]);
  const [legacyItems, setLegacyItems] = useState<LegacyItem[]>([]);
  const [tribesList, setTribesList] = useState<{ id: number; name: string }[]>([]);
  const [modalItem, setModalItem] = useState<BoardItem | null>(null);
  const [dragTitle, setDragTitle] = useState<string | null>(null);

  const [filter, setFilter] = useState<'all' | 'artifacts' | 'hub_resources'>('all');
  const [search, setSearch] = useState('');

  // Derive curation access from shared member context
  const canCurate = useMemo(() => {
    if (!authMember) return false;
    return hasPermission(authMember, 'admin.curation');
  }, [authMember]);

  const ui = i18n || {};

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 6 } }),
    useSensor(KeyboardSensor),
  );

  const toast = useCallback((msg: string, type: string) => {
    (globalThis as any).toast?.(msg, type);
  }, []);

  // ── Fetch ──

  const fetchAll = useCallback(async () => {
    setLoading(true);
    setError(null);

    const sb = await waitForSb();
    if (!sb) { setError('Supabase não disponível. Recarregue a página.'); setLoading(false); return; }

    try {
      // Supabase JS v2 .rpc() returns a PostgrestFilterBuilder (thenable but no .catch).
      // Must await each call individually — never chain .catch() on rpc().
      // Try get_curation_dashboard first (W90), fallback to list_curation_pending_board_items
      let tribeRes: { data: any; error: any } = { data: null, error: null };
      let dashboardData: any = null;
      try {
        const dashRes = await sb.rpc('get_curation_dashboard');
        if (dashRes.data && !dashRes.error) {
          dashboardData = dashRes.data;
          tribeRes = { data: dashRes.data.items || [], error: null };
        } else {
          tribeRes = await sb.rpc('list_curation_pending_board_items');
        }
      } catch (e: any) {
        try {
          tribeRes = await sb.rpc('list_curation_pending_board_items');
        } catch (e2: any) {
          tribeRes = { data: null, error: { message: e2?.message || 'RPC unavailable' } };
        }
      }

      let legacyRes: { data: any; error: any } = { data: null, error: null };
      try {
        legacyRes = await sb.rpc('list_curation_board');
      } catch {
        try {
          legacyRes = await sb.rpc('list_pending_curation', { p_table: 'all' });
        } catch {
          legacyRes = { data: null, error: null };
        }
      }

      if (tribeRes.error?.message?.includes('access') || tribeRes.error?.message?.includes('curatorship') || tribeRes.error?.message?.includes('Curatorship')) {
        setDenied(true);
        setLoading(false);
        return;
      }

      const tList = Array.isArray(tribeRes.data) ? tribeRes.data : [];
      setTribeItems(tList.map((row: any) => ({ ...row, curation_status: row.curation_status || 'curation_pending' })));

      const lList = Array.isArray(legacyRes?.data) ? legacyRes.data : [];
      setLegacyItems(lList.map((row: any) => ({
        id: String(row.id),
        title: row.title || 'Sem título',
        description: row.description,
        _table: row._table || row.source_type || 'artifacts',
        status: row.status || 'draft',
        tags: row.tags || [],
        suggested_tags: row.suggested_tags || [],
        author_name: row.author_name,
        tribe_name: row.tribe_name,
        source: row.source,
      })));

      // Fetch tribes list for approve confirmation
      try {
        const { data: tribesData } = await sb.from('tribes').select('id,name,name_i18n').eq('is_active', true).order('name');
        if (Array.isArray(tribesData)) setTribesList(tribesData);
      } catch { /* non-critical */ }
    } catch (err: any) {
      setError(`Erro: ${err?.message || 'desconhecido'}`);
    } finally {
      setLoading(false);
    }
  }, []);

  // Gate data fetch on member context resolution
  useEffect(() => {
    if (memberLoading) return;
    if (!authMember || !canCurate) {
      setDenied(true);
      setLoading(false);
      return;
    }
    // Member arrived (possibly late via nav:member) — reset denied and fetch
    setDenied(false);
    fetchAll();
  }, [memberLoading, authMember, canCurate, fetchAll]);

  // Signal island readiness and manage SSR fallback visibility
  useEffect(() => {
    if (!loading) {
      window.dispatchEvent(new Event('cur:island-ready'));
      // If board loaded successfully, ensure SSR denied fallback is hidden
      if (!denied) {
        const ssrDenied = document.getElementById('cur-denied');
        if (ssrDenied) ssrDenied.classList.add('hidden');
      }
    }
  }, [loading, denied]);

  // ── Tribe board: review submit ──

  async function handleReviewSubmit(decision: string, scores: Record<string, number>, feedback: string) {
    if (!modalItem) return;
    const sb = getSb();
    if (!sb) return;

    const { error: err } = await sb.rpc('submit_curation_review', {
      p_item_id: modalItem.id,
      p_decision: decision,
      p_criteria_scores: scores,
      p_feedback_notes: feedback || null,
    });

    if (err) { toast(err.message || 'Erro ao submeter', 'error'); return; }

    const labels: Record<string, string> = {
      approved: ui.approved || 'Aprovado e publicado!',
      returned_for_revision: 'Devolvido à tribo com feedback.',
      rejected: ui.rejected || 'Rejeitado pelo comitê.',
    };
    toast(labels[decision] || 'Concluído.', decision === 'approved' ? 'success' : 'info');
    setModalItem(null);
    setTribeItems((prev) => prev.filter((i) => i.id !== modalItem.id));
  }

  // ── Legacy board: quick actions ──

  const legacyCurate = useCallback(async (id: string, table: string, action: string) => {
    const sb = getSb();
    if (!sb) return;
    const item = legacyItems.find((i) => i.id === id);

    setLegacyItems((prev) => prev.map((i) => i.id === id ? { ...i, status: action === 'approve' ? 'approved' : action === 'reject' ? 'rejected' : i.status } : i));

    const { error: err } = await sb.rpc('curate_item', {
      p_table: table, p_id: id, p_action: action,
      p_tags: item?.suggested_tags || item?.tags || null,
      p_tribe_id: null, p_audience_level: null,
    });

    if (err) {
      toast(err.message || 'Erro', 'error');
      fetchAll();
      return;
    }
    toast(action === 'approve' ? (ui.approved || 'Aprovado!') : (ui.rejected || 'Descartado.'), 'success');
  }, [legacyItems, fetchAll, toast, ui]);

  // ── DnD handlers ──

  function onDragStart(e: DragStartEvent) {
    const item = tribeItems.find((i) => i.id === e.active.id) || legacyItems.find((i) => i.id === e.active.id);
    setDragTitle(item?.title || null);
  }

  function onTribeDragEnd(e: DragEndEvent) {
    setDragTitle(null);
    const { active, over } = e;
    if (!over) return;
    if (String(over.id) === 'tribe-published') {
      const item = tribeItems.find((i) => i.id === active.id);
      if (item) setModalItem(item);
    }
  }

  function onLegacyDragEnd(e: DragEndEvent) {
    setDragTitle(null);
    const { active, over } = e;
    if (!over) return;
    const targetCol = String(over.id);
    const item = legacyItems.find((i) => i.id === String(active.id));
    if (!item) return;

    const STATUS_MAP: Record<string, string> = { 'leg-approved': 'approve', 'leg-rejected': 'reject', 'leg-review': 'review', 'leg-draft': 'draft' };
    const action = STATUS_MAP[targetCol];
    if (action && action !== item.status) {
      legacyCurate(item.id, item._table, action);
    }
  }

  // ── Filtered legacy items ──

  const filteredLegacy = useMemo(() => {
    let result = legacyItems;
    if (filter !== 'all') result = result.filter((i) => i._table === filter);
    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter((i) => i.title.toLowerCase().includes(q) || (i.author_name || '').toLowerCase().includes(q));
    }
    return result;
  }, [legacyItems, filter, search]);

  const legacyByStatus = useMemo(() => {
    const g: Record<string, LegacyItem[]> = { draft: [], review: [], approved: [], rejected: [] };
    filteredLegacy.forEach((i) => { (g[i.status] || g.draft).push(i); });
    return g;
  }, [filteredLegacy]);

  // ── Render states ──

  if (loading || memberLoading) return (
    <div className="text-center py-12">
      <div className="inline-flex items-center gap-3 text-[var(--text-muted)]">
        <Loader2 size={20} className="animate-spin" />
        <span className="text-sm font-medium">{ui.loading || 'Carregando...'}</span>
      </div>
    </div>
  );

  if (denied) {
    // Show the SSR #cur-denied fallback instead of rendering a duplicate
    if (typeof document !== 'undefined') {
      const ssrDenied = document.getElementById('cur-denied');
      if (ssrDenied) ssrDenied.classList.remove('hidden');
    }
    return null;
  }

  if (error) return (
    <div className="bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-800 rounded-2xl p-8 text-center">
      <div className="text-3xl mb-3">{ui.warnIcon || '⚠️'}</div>
      <p className="font-bold text-red-700 dark:text-red-300 mb-2">{ui.loadError || 'Erro ao carregar'}</p>
      <p className="text-sm text-red-600 dark:text-red-300 mb-4">{error}</p>
      <button onClick={fetchAll} className="px-5 py-2.5 bg-red-600 text-white rounded-xl text-sm font-bold cursor-pointer hover:bg-red-700 border-0">
        <RefreshCw size={14} className="inline mr-1" /> {ui.retry || 'Tentar novamente'}
      </button>
    </div>
  );

  const overdueCount = tribeItems.filter((i) => (daysUntilDue(i.curation_due_at) ?? 1) < 0).length;
  const pubLinkLabel = ui.publicationsPath || '/publications';
  const pubFooter = (ui.publishedNote || 'Itens publicados aparecem em ') + pubLinkLabel + '.';

  const totalCount = tribeItems.length + legacyItems.length;

  return (
    <div id="cur-board" className="space-y-8">
      <span id="cur-count" className="text-xs text-[var(--text-muted)]">
        {totalCount}{' '}{totalCount === 1 ? 'item' : 'itens'}{' '}{ui.totalLabel || 'no painel'}
      </span>
      {/* ── Section 1: Tribe Board Items (curation_pending → published) ── */}
      <section>
        <div className="flex items-center justify-between mb-3">
          <div>
            <h2 className="text-lg font-extrabold text-blue-900">{ui.tribeItemsTitle || pt('comp.curation.tribeItems', 'Itens das Tribos')}</h2>
            <p className="text-xs text-[var(--text-secondary)]">{ui.tribeItemsDesc || 'Artefatos aprovados pelos líderes. Arraste para publicar ou clique para avaliar.'}</p>
          </div>
          <span className="px-3 py-1 bg-amber-100 text-amber-800 rounded-full text-[11px] font-bold">{tribeItems.length}{' '}{ui.pending || 'pendente'}{tribeItems.length !== 1 ? 's' : ''}</span>
        </div>

        {overdueCount > 0 ? (
          <div className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-800 mb-3">
            <AlertTriangle size={16} className="text-red-600 dark:text-red-300" />
            <p className="text-xs font-semibold text-red-700 dark:text-red-300">{overdueCount}{' '}{ui.slaExpiredItems || 'item'}{overdueCount !== 1 ? 'ns' : ''}{' '}{ui.slaExpiredSuffix || 'com SLA vencido'}</p>
          </div>
        ) : null}

        {tribeItems.length === 0 ? (
          <div className="bg-emerald-50 dark:bg-emerald-950/30 border border-emerald-200 dark:border-emerald-800 rounded-2xl p-6 text-center">
            <p className="font-bold text-emerald-800">{ui.celebrateIcon || '🎉'}{' '}{ui.empty || 'Nenhum item pendente. Tudo em dia!'}</p>
          </div>
        ) : (
          <DndContext sensors={sensors} collisionDetection={closestCorners} onDragStart={onDragStart} onDragEnd={onTribeDragEnd}>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <div className="flex items-center justify-between mb-2">
                  <h3 className="text-[13px] font-bold text-amber-700">{ui.awaitingCuration || 'Aguardando Curadoria'}</h3>
                  <span className="text-[11px] px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 font-bold">{tribeItems.length}</span>
                </div>
                <SortableContext id="tribe-pending" items={tribeItems.map((i) => i.id)} strategy={verticalListSortingStrategy}>
                  <div className="min-h-[200px] max-h-[60vh] overflow-y-auto space-y-2.5 p-2.5 rounded-xl border-2 border-dashed border-amber-200 dark:border-amber-800 bg-amber-50/30 dark:bg-amber-950/10">
                    {tribeItems.map((item) => <TribeSortableCard key={item.id} item={item} onOpen={setModalItem} ui={ui} />)}
                  </div>
                </SortableContext>
              </div>
              <div>
                <div className="flex items-center justify-between mb-2">
                  <h3 className="text-[13px] font-bold text-emerald-700 dark:text-emerald-300">{ui.published || 'Publicado'}</h3>
                  <span className="text-[11px] text-[var(--text-secondary)]">{ui.dragOrClickHint || 'Arraste ou clique "Avaliar"'}</span>
                </div>
                <DroppableColumn id="tribe-published">
                  <div className="py-8 text-center text-sm text-[var(--text-muted)]">{ui.dropToPublish || '↓ Solte o card aqui para avaliar e publicar'}</div>
                </DroppableColumn>
              </div>
            </div>
            <DragOverlay dropAnimation={{ duration: 200, easing: 'ease-out' }}>
              {dragTitle ? <DragOverlayCard title={dragTitle} /> : null}
            </DragOverlay>
          </DndContext>
        )}
      </section>

      {/* ── Section 2: Legacy Artifacts/Resources ── */}
      {legacyItems.length > 0 ? (
        <section>
          <div className="flex items-center justify-between mb-3">
            <div>
              <h2 className="text-lg font-extrabold text-blue-900">{ui.legacyTitle || 'Artefatos & Recursos'}</h2>
              <p className="text-xs text-[var(--text-secondary)]">{ui.legacyDesc || 'Itens legados de artifacts e hub_resources.'}</p>
            </div>
          </div>

          <div className="flex items-center gap-3 mb-4 flex-wrap">
            <input
              id="cur-search"
              type="text" value={search} onChange={(e) => setSearch(e.target.value)}
              placeholder={ui.searchPlaceholder || 'Buscar...'}
              className="flex-1 min-w-[200px] max-w-xs rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] px-3 py-2 text-[12px] text-[var(--text-primary)] outline-none focus:border-blue-400"
            />
            <div className="flex gap-1">
              {(['all', 'artifacts', 'hub_resources'] as const).map((f) => {
                const labels = { all: ui.filterAll || 'Todos', artifacts: ui.filterArtifacts || 'Artefatos', hub_resources: ui.filterResources || 'Recursos' };
                return (
                  <button key={f} onClick={() => setFilter(f)}
                    className={`px-3 py-1.5 rounded-full text-[12px] font-semibold cursor-pointer border-2 transition-all ${filter === f ? 'border-blue-900 bg-blue-900 text-white' : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)] hover:border-[var(--border-default)]'}`}>
                    {labels[f]}
                  </button>
                );
              })}
            </div>
            <span className="px-3 py-1 bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300 rounded-full text-[11px] font-bold">{filteredLegacy.length}{' '}{ui.items || 'itens'}</span>
          </div>

          <DndContext sensors={sensors} collisionDetection={closestCorners} onDragStart={onDragStart} onDragEnd={onLegacyDragEnd}>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
              {([
                { id: 'leg-draft', label: 'Pendente', dot: 'bg-[var(--text-muted)]', border: 'border-[var(--border-default)]', bg: 'bg-[var(--surface-base)]/50' },
                { id: 'leg-review', label: 'Em Revisão', dot: 'bg-amber-400', border: 'border-amber-200 dark:border-amber-800', bg: 'bg-amber-50/30 dark:bg-amber-950/10' },
                { id: 'leg-approved', label: 'Aprovado', dot: 'bg-emerald-500', border: 'border-emerald-200 dark:border-emerald-800', bg: 'bg-emerald-50/30 dark:bg-emerald-950/30' },
                { id: 'leg-rejected', label: 'Descartado', dot: 'bg-red-400', border: 'border-red-200 dark:border-red-800', bg: 'bg-red-50/30 dark:bg-red-950/30' },
              ] as const).map((col) => {
                const statusKey = col.id.replace('leg-', '');
                const colItems = legacyByStatus[statusKey] || [];
                return (
                  <div key={col.id}>
                    <div className="flex items-center gap-2 mb-2">
                      <div className={`w-3 h-3 rounded-full ${col.dot}`} />
                      <h3 className="text-[13px] font-bold text-[var(--text-primary)]">{col.label}</h3>
                      <span className="text-[11px] bg-[var(--surface-section-cool)] text-[var(--text-secondary)] px-2 py-0.5 rounded-full font-bold">{colItems.length}</span>
                    </div>
                    <SortableContext id={col.id} items={colItems.map((i) => i.id)} strategy={verticalListSortingStrategy}>
                      <DroppableColumn id={col.id}>
                        {colItems.length === 0 ? <div className="py-8 text-center text-[var(--text-muted)] text-[11px]">{ui.emptyCol || 'Vazio'}</div> : null}
                        {colItems.map((item) => (
                          <LegacySortableCard key={item.id} item={item} tribes={tribesList} onApprove={(id, t) => legacyCurate(id, t, 'approve')} onReject={(id, t) => legacyCurate(id, t, 'reject')} ui={ui} />
                        ))}
                      </DroppableColumn>
                    </SortableContext>
                  </div>
                );
              })}
            </div>
            <DragOverlay dropAnimation={{ duration: 200, easing: 'ease-out' }}>
              {dragTitle ? <DragOverlayCard title={dragTitle} /> : null}
            </DragOverlay>
          </DndContext>
        </section>
      ) : null}

      <p className="text-[12px] text-[var(--text-secondary)]">
        {ui.publishedNote || 'Itens publicados aparecem em '}<a href="/publications" className="text-blue-900 font-semibold underline hover:no-underline">{pubLinkLabel}</a>
      </p>

      {modalItem ? <ReviewRubricDialog item={modalItem} open={!!modalItem} onClose={() => setModalItem(null)} onSubmit={handleReviewSubmit} ui={ui} /> : null}
    </div>
  );
}
