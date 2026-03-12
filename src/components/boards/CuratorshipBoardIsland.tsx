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

function getSb() { return (globalThis as any).navGetSb?.(); }
function getMember() { return (globalThis as any).navGetMember?.(); }

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

function SlaBadge({ dueAt }: { dueAt?: string | null }) {
  const days = daysUntilDue(dueAt);
  if (days === null) return null;
  if (days < 0) return (
    <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-red-100 text-red-700 font-bold animate-pulse">
      <AlertTriangle size={10} /> {Math.abs(days)}d atrasado
    </span>
  );
  if (days <= 2) return (
    <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700 font-bold">
      <Clock size={10} /> {days}d
    </span>
  );
  return (
    <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-slate-100 text-slate-500">
      <Clock size={10} /> {days}d
    </span>
  );
}

// ─── Tribe Board Item Card (Sortable) ───────────────────────────────────────

function TribeSortableCard({ item, onOpen }: { item: BoardItem; onOpen: (item: BoardItem) => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: item.id });
  const isOverdue = (daysUntilDue(item.curation_due_at) ?? 1) < 0;

  return (
    <article
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.4 : 1, touchAction: 'none' }}
      {...attributes}
      {...listeners}
      className={`rounded-xl border bg-white p-3 shadow-sm cursor-grab active:cursor-grabbing hover:shadow-md transition-all ${
        isOverdue ? 'border-red-300 ring-1 ring-red-200' : 'border-slate-200'
      }`}
    >
      <div className="flex items-start justify-between gap-2 mb-1">
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onOpen(item); }}
          onPointerDown={(e) => e.stopPropagation()}
          className="text-[12px] font-bold text-slate-800 line-clamp-2 flex-1 text-left hover:underline cursor-pointer bg-transparent border-0 p-0"
        >
          {item.title || 'Sem título'}
        </button>
        <SlaBadge dueAt={item.curation_due_at} />
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        {item.tribe_name ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-blue-50 text-blue-700 font-semibold">{item.tribe_name}</span>
        ) : null}
        {(item.review_count || 0) > 0 ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-violet-100 text-violet-600">{item.review_count}x avaliado</span>
        ) : null}
      </div>
      {item.assignee_name ? <p className="text-[11px] text-slate-500 mt-1 truncate">{item.assignee_name}</p> : null}
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onOpen(item); }}
        onPointerDown={(e) => e.stopPropagation()}
        className="mt-2 w-full py-1.5 rounded-lg text-[11px] font-semibold bg-blue-900/10 text-blue-900 hover:bg-blue-900/20 cursor-pointer border-0 transition-colors"
      >
        Avaliar
      </button>
    </article>
  );
}

// ─── Legacy Item Card (Sortable) ────────────────────────────────────────────

function LegacySortableCard({ item, onApprove, onReject }: {
  item: LegacyItem;
  onApprove: (id: string, table: string) => void;
  onReject: (id: string, table: string) => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: item.id, data: { item } });
  const icon = item._table === 'artifacts' ? '📄' : '📚';

  return (
    <article
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.4 : 1, touchAction: 'none' }}
      {...attributes}
      {...listeners}
      className="rounded-xl border border-slate-200 bg-white p-3 shadow-sm cursor-grab active:cursor-grabbing hover:shadow-md transition-all"
    >
      <h4 className="text-[12px] font-bold text-slate-800 line-clamp-2 mb-1">{icon} {item.title}</h4>
      {item.tribe_name ? (
        <span className="inline-block text-[10px] px-1.5 py-0.5 rounded bg-blue-50 text-blue-700 font-semibold mb-1">{item.tribe_name}</span>
      ) : null}
      {item.author_name ? <p className="text-[10px] text-slate-400 mb-1">{item.author_name}</p> : null}
      {(item.tags?.length || 0) > 0 ? (
        <div className="flex flex-wrap gap-1 mb-1">
          {item.tags!.slice(0, 3).map((tag) => (
            <span key={tag} className="px-1.5 py-0.5 bg-slate-100 text-slate-600 rounded text-[9px] font-medium">{tag}</span>
          ))}
        </div>
      ) : null}
      <div className="flex gap-1.5 mt-2 pt-2 border-t border-slate-50" onPointerDown={(e) => e.stopPropagation()}>
        {item.status !== 'approved' ? (
          <button
            onClick={() => onApprove(item.id, item._table)}
            className="flex-1 px-2 py-1 rounded-lg bg-emerald-50 text-emerald-700 text-[10px] font-semibold border border-emerald-200 hover:bg-emerald-100 cursor-pointer transition-colors"
          >
            ✅ Aprovar
          </button>
        ) : null}
        {item.status !== 'rejected' ? (
          <button
            onClick={() => onReject(item.id, item._table)}
            className="flex-1 px-2 py-1 rounded-lg bg-red-50 text-red-600 text-[10px] font-semibold border border-red-200 hover:bg-red-100 cursor-pointer transition-colors"
          >
            ❌ Descartar
          </button>
        ) : null}
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
        isOver ? 'ring-2 ring-blue-300 border-blue-300 bg-blue-50/40 scale-[1.01]' : 'border-slate-200 bg-slate-50/50'
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
            n <= value ? 'bg-blue-900 text-white shadow-sm' : 'bg-slate-100 text-slate-400 hover:bg-slate-200'
          }`}
        >{n}</button>
      ))}
    </div>
  );
}

// ─── Review Rubric Dialog ───────────────────────────────────────────────────

function ReviewRubricDialog({ item, open, onClose, onSubmit }: {
  item: BoardItem; open: boolean; onClose: () => void;
  onSubmit: (decision: string, scores: Record<string, number>, feedback: string) => Promise<void>;
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

  return (
    <Dialog.Root open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50" />
        <Dialog.Content
          className="fixed right-0 top-0 h-full w-full max-w-lg bg-white shadow-2xl z-50 overflow-y-auto"
          aria-describedby={undefined}
        >
          <VisuallyHidden asChild><Dialog.Title>Avaliação de curadoria</Dialog.Title></VisuallyHidden>

          <div className="sticky top-0 bg-white border-b border-slate-200 px-6 py-4 z-10">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <FileText size={18} className="text-blue-900" />
                <h2 className="text-base font-bold text-blue-900">Avaliação de Curadoria</h2>
              </div>
              <Dialog.Close asChild>
                <button className="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 border-0 bg-transparent cursor-pointer">
                  <XCircle size={18} />
                </button>
              </Dialog.Close>
            </div>
          </div>

          <div className="px-6 py-5 space-y-6">
            <section className="space-y-2">
              <h3 className="text-sm font-bold text-blue-900">{item.title}</h3>
              <div className="flex flex-wrap gap-2">
                {item.tribe_name ? <span className="text-[11px] px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">{item.tribe_name}</span> : null}
                <SlaBadge dueAt={item.curation_due_at} />
              </div>
              {item.assignee_name ? <p className="text-xs text-slate-500 flex items-center gap-1"><User size={12} /> {item.assignee_name}</p> : null}
              {item.description ? <p className="text-xs text-slate-600 whitespace-pre-wrap max-h-32 overflow-y-auto bg-slate-50 rounded-lg p-3">{item.description}</p> : null}
            </section>

            {item.review_history && item.review_history.length > 0 ? (
              <section>
                <button type="button" onClick={() => setShowHistory(!showHistory)} className="flex items-center gap-1 text-xs font-semibold text-violet-600 hover:underline bg-transparent border-0 cursor-pointer p-0">
                  {showHistory ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                  Histórico ({item.review_history.length})
                </button>
                {showHistory ? (
                  <div className="mt-2 space-y-2">
                    {item.review_history.map((r) => (
                      <div key={r.id} className="text-xs bg-slate-50 rounded-lg p-3 space-y-1">
                        <div className="flex items-center justify-between">
                          <span className="font-semibold text-slate-700">{r.curator_name || '—'}</span>
                          <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${r.decision === 'approved' ? 'bg-emerald-100 text-emerald-700' : r.decision === 'rejected' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>
                            {r.decision === 'approved' ? 'Aprovado' : r.decision === 'rejected' ? 'Rejeitado' : 'Devolvido'}
                          </span>
                        </div>
                        {r.feedback ? <p className="text-slate-500">{r.feedback}</p> : null}
                      </div>
                    ))}
                  </div>
                ) : null}
              </section>
            ) : null}

            <section className="space-y-3">
              <div className="flex items-center justify-between">
                <h4 className="text-sm font-bold text-blue-900 flex items-center gap-1.5"><Star size={14} /> Rubrica</h4>
                {avgScore ? (
                  <span className={`text-sm font-bold px-2 py-0.5 rounded-full ${parseFloat(avgScore) >= 4 ? 'bg-emerald-100 text-emerald-700' : parseFloat(avgScore) >= 3 ? 'bg-amber-100 text-amber-700' : 'bg-red-100 text-red-700'}`}>
                    {avgScore}
                  </span>
                ) : null}
              </div>
              {CRITERIA.map((c) => (
                <div key={c.key} className="flex items-center justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-semibold text-slate-700">{c.label}</p>
                    <p className="text-[10px] text-slate-400 truncate">{c.tip}</p>
                  </div>
                  <ScoreInput value={scores[c.key] || 0} onChange={(v) => setScores((p) => ({ ...p, [c.key]: v }))} />
                </div>
              ))}
            </section>

            <section className="space-y-2">
              <label className="text-xs font-bold text-blue-900">Feedback para a Tribo</label>
              <textarea
                value={feedback} onChange={(e) => setFeedback(e.target.value)} rows={3}
                placeholder="Obrigatório para devoluções e rejeições..."
                className="w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-xs text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-900/30 resize-none"
              />
            </section>

            <section className="flex flex-col gap-2 pt-2 border-t border-slate-200">
              <button type="button" disabled={!allScored || submitting} onClick={() => handleAction('approved')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors border-0 cursor-pointer">
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />} Aprovar e Publicar
              </button>
              <button type="button" disabled={!feedback.trim() || submitting} onClick={() => handleAction('returned_for_revision')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-amber-700 bg-amber-100 hover:bg-amber-200 disabled:opacity-40 disabled:cursor-not-allowed transition-colors border-0 cursor-pointer">
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <RotateCcw size={16} />} Devolver à Tribo
              </button>
              <button type="button" disabled={!feedback.trim() || submitting} onClick={() => handleAction('rejected')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-red-600 bg-red-50 hover:bg-red-100 disabled:opacity-40 disabled:cursor-not-allowed transition-colors border-0 cursor-pointer">
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <XCircle size={16} />} Rejeitar
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
    <div className="bg-white rounded-xl border-2 border-blue-300 p-3 shadow-xl rotate-[3deg] w-[260px] opacity-95">
      <h4 className="text-[12px] font-bold text-slate-800 line-clamp-2">{title}</h4>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────────────

export default function CuratorshipBoardIsland({ i18n }: { i18n?: I18n }) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [denied, setDenied] = useState(false);

  const [tribeItems, setTribeItems] = useState<BoardItem[]>([]);
  const [legacyItems, setLegacyItems] = useState<LegacyItem[]>([]);
  const [modalItem, setModalItem] = useState<BoardItem | null>(null);
  const [dragTitle, setDragTitle] = useState<string | null>(null);

  const [filter, setFilter] = useState<'all' | 'artifacts' | 'hub_resources'>('all');
  const [search, setSearch] = useState('');

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

    let sb = getSb();
    let retries = 0;
    while (!sb && retries < 15) {
      await new Promise((r) => setTimeout(r, 300));
      sb = getSb();
      retries++;
    }
    if (!sb) { setError('Supabase não disponível. Recarregue a página.'); setLoading(false); return; }

    const member = getMember();
    if (!member) {
      const handler = () => { fetchAll(); };
      window.addEventListener('nav:member', handler, { once: true });
      return;
    }

    try {
      // Supabase JS v2 .rpc() returns a PostgrestFilterBuilder (thenable but no .catch).
      // Must await each call individually — never chain .catch() on rpc().
      let tribeRes: { data: any; error: any } = { data: null, error: null };
      try {
        tribeRes = await sb.rpc('list_curation_pending_board_items');
      } catch (e: any) {
        tribeRes = { data: null, error: { message: e?.message || 'RPC unavailable' } };
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
    } catch (err: any) {
      setError(`Erro: ${err?.message || 'desconhecido'}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchAll(); }, [fetchAll]);

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

  if (loading) return (
    <div className="text-center py-12">
      <div className="inline-flex items-center gap-3 text-slate-400">
        <Loader2 size={20} className="animate-spin" />
        <span className="text-sm font-medium">{ui.loading || 'Carregando...'}</span>
      </div>
    </div>
  );

  if (denied) return (
    <div className="bg-amber-50 border border-amber-200 rounded-2xl p-8 text-center">
      <div className="text-3xl mb-3">🔒</div>
      <p className="font-bold text-amber-800 mb-3">{ui.denied || 'Acesso restrito'}</p>
      <a href="/admin" className="inline-block px-5 py-2.5 bg-blue-900 text-white rounded-xl text-sm font-bold no-underline hover:opacity-90">{ui.backAdmin || 'Voltar'}</a>
    </div>
  );

  if (error) return (
    <div className="bg-red-50 border border-red-200 rounded-2xl p-8 text-center">
      <div className="text-3xl mb-3">⚠️</div>
      <p className="font-bold text-red-700 mb-2">Erro ao carregar</p>
      <p className="text-sm text-red-600 mb-4">{error}</p>
      <button onClick={fetchAll} className="px-5 py-2.5 bg-red-600 text-white rounded-xl text-sm font-bold cursor-pointer hover:bg-red-700 border-0">
        <RefreshCw size={14} className="inline mr-1" /> Tentar novamente
      </button>
    </div>
  );

  const overdueCount = tribeItems.filter((i) => (daysUntilDue(i.curation_due_at) ?? 1) < 0).length;

  return (
    <div className="space-y-8">
      {/* ── Section 1: Tribe Board Items (curation_pending → published) ── */}
      <section>
        <div className="flex items-center justify-between mb-3">
          <div>
            <h2 className="text-lg font-extrabold text-blue-900">Itens das Tribos</h2>
            <p className="text-xs text-slate-500">Artefatos aprovados pelos líderes. Arraste para publicar ou clique para avaliar.</p>
          </div>
          <span className="px-3 py-1 bg-amber-100 text-amber-800 rounded-full text-[11px] font-bold">{tribeItems.length} pendente{tribeItems.length !== 1 ? 's' : ''}</span>
        </div>

        {overdueCount > 0 ? (
          <div className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-red-50 border border-red-200 mb-3">
            <AlertTriangle size={16} className="text-red-600" />
            <p className="text-xs font-semibold text-red-700">{overdueCount} item{overdueCount !== 1 ? 'ns' : ''} com SLA vencido</p>
          </div>
        ) : null}

        {tribeItems.length === 0 ? (
          <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-6 text-center">
            <p className="font-bold text-emerald-800">🎉 {ui.empty || 'Nenhum item pendente. Tudo em dia!'}</p>
          </div>
        ) : (
          <DndContext sensors={sensors} collisionDetection={closestCorners} onDragStart={onDragStart} onDragEnd={onTribeDragEnd}>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <div className="flex items-center justify-between mb-2">
                  <h3 className="text-[13px] font-bold text-amber-700">Aguardando Curadoria</h3>
                  <span className="text-[11px] px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 font-bold">{tribeItems.length}</span>
                </div>
                <SortableContext id="tribe-pending" items={tribeItems.map((i) => i.id)} strategy={verticalListSortingStrategy}>
                  <div className="min-h-[200px] max-h-[60vh] overflow-y-auto space-y-2.5 p-2.5 rounded-xl border-2 border-dashed border-amber-200 bg-amber-50/30">
                    {tribeItems.map((item) => <TribeSortableCard key={item.id} item={item} onOpen={setModalItem} />)}
                  </div>
                </SortableContext>
              </div>
              <div>
                <div className="flex items-center justify-between mb-2">
                  <h3 className="text-[13px] font-bold text-emerald-700">Publicado</h3>
                  <span className="text-[11px] text-slate-500">Arraste ou clique "Avaliar"</span>
                </div>
                <DroppableColumn id="tribe-published">
                  <div className="py-8 text-center text-sm text-slate-400">↓ Solte o card aqui para avaliar e publicar</div>
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
              <h2 className="text-lg font-extrabold text-blue-900">Artefatos & Recursos</h2>
              <p className="text-xs text-slate-500">Itens legados de artifacts e hub_resources.</p>
            </div>
          </div>

          <div className="flex items-center gap-3 mb-4 flex-wrap">
            <input
              type="text" value={search} onChange={(e) => setSearch(e.target.value)}
              placeholder={ui.searchPlaceholder || 'Buscar...'}
              className="flex-1 min-w-[200px] max-w-xs rounded-xl border border-slate-200 bg-white px-3 py-2 text-[12px] text-slate-700 outline-none focus:border-blue-400"
            />
            <div className="flex gap-1">
              {(['all', 'artifacts', 'hub_resources'] as const).map((f) => {
                const labels = { all: ui.filterAll || 'Todos', artifacts: ui.filterArtifacts || 'Artefatos', hub_resources: ui.filterResources || 'Recursos' };
                return (
                  <button key={f} onClick={() => setFilter(f)}
                    className={`px-3 py-1.5 rounded-full text-[12px] font-semibold cursor-pointer border-2 transition-all ${filter === f ? 'border-blue-900 bg-blue-900 text-white' : 'border-slate-200 bg-white text-slate-500 hover:border-slate-300'}`}>
                    {labels[f]}
                  </button>
                );
              })}
            </div>
            <span className="px-3 py-1 bg-blue-50 text-blue-700 rounded-full text-[11px] font-bold">{filteredLegacy.length} itens</span>
          </div>

          <DndContext sensors={sensors} collisionDetection={closestCorners} onDragStart={onDragStart} onDragEnd={onLegacyDragEnd}>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
              {([
                { id: 'leg-draft', label: 'Pendente', dot: 'bg-slate-400', border: 'border-slate-200', bg: 'bg-slate-50/50' },
                { id: 'leg-review', label: 'Em Revisão', dot: 'bg-amber-400', border: 'border-amber-200', bg: 'bg-amber-50/30' },
                { id: 'leg-approved', label: 'Aprovado', dot: 'bg-emerald-500', border: 'border-emerald-200', bg: 'bg-emerald-50/30' },
                { id: 'leg-rejected', label: 'Descartado', dot: 'bg-red-400', border: 'border-red-200', bg: 'bg-red-50/30' },
              ] as const).map((col) => {
                const statusKey = col.id.replace('leg-', '');
                const colItems = legacyByStatus[statusKey] || [];
                return (
                  <div key={col.id}>
                    <div className="flex items-center gap-2 mb-2">
                      <div className={`w-3 h-3 rounded-full ${col.dot}`} />
                      <h3 className="text-[13px] font-bold text-slate-700">{col.label}</h3>
                      <span className="text-[11px] bg-slate-100 text-slate-500 px-2 py-0.5 rounded-full font-bold">{colItems.length}</span>
                    </div>
                    <SortableContext id={col.id} items={colItems.map((i) => i.id)} strategy={verticalListSortingStrategy}>
                      <DroppableColumn id={col.id}>
                        {colItems.length === 0 ? <div className="py-8 text-center text-slate-300 text-[11px]">Vazio</div> : null}
                        {colItems.map((item) => (
                          <LegacySortableCard key={item.id} item={item} onApprove={(id, t) => legacyCurate(id, t, 'approve')} onReject={(id, t) => legacyCurate(id, t, 'reject')} />
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

      <p className="text-[12px] text-slate-500">
        Itens publicados aparecem em <a href="/publications" className="text-blue-900 font-semibold underline hover:no-underline">/publications</a>.
      </p>

      {modalItem ? <ReviewRubricDialog item={modalItem} open={!!modalItem} onClose={() => setModalItem(null)} onSubmit={handleReviewSubmit} /> : null}
    </div>
  );
}
