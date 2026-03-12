/**
 * CuratorshipBoardIsland — Super-Kanban de Curadoria
 * Exibe board_items com curation_status='curation_pending' de todas as tribos.
 * Curador clica no card → Dialog com rubric 5 critérios → Aprovar/Devolver/Rejeitar.
 * Acesso: admin+, curator, co_gp.
 */
import React, { useEffect, useState, useCallback } from 'react';
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
import {
  CheckCircle2,
  RotateCcw,
  XCircle,
  Clock,
  AlertTriangle,
  FileText,
  User,
  Star,
  ChevronDown,
  ChevronUp,
  Loader2,
} from 'lucide-react';
import * as Dialog from '@radix-ui/react-dialog';
import { VisuallyHidden } from '@radix-ui/react-visually-hidden';

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

const CRITERIA = [
  { key: 'clarity', label: 'Clareza', tip: 'O artefato é compreensível sem contexto adicional?' },
  { key: 'originality', label: 'Originalidade', tip: 'Traz perspectiva ou abordagem nova?' },
  { key: 'adherence', label: 'Aderência', tip: 'Está alinhado com o tema/quadrante da tribo?' },
  { key: 'relevance', label: 'Relevância', tip: 'Contribui para o corpo de conhecimento do Núcleo?' },
  { key: 'ethics', label: 'Ética', tip: 'Respeita princípios de IA responsável e governança?' },
] as const;

function daysUntilDue(dueAt: string | null | undefined): number | null {
  if (!dueAt) return null;
  const diff = new Date(dueAt).getTime() - Date.now();
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
}

function SlaBadge({ dueAt }: { dueAt?: string | null }) {
  const days = daysUntilDue(dueAt);
  if (days === null) return null;
  if (days < 0) {
    return (
      <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300 font-bold animate-pulse">
        <AlertTriangle size={10} /> {Math.abs(days)}d atrasado
      </span>
    );
  }
  if (days <= 2) {
    return (
      <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700 dark:bg-amber-900/50 dark:text-amber-300 font-bold">
        <Clock size={10} /> {days}d restante{days !== 1 ? 's' : ''}
      </span>
    );
  }
  return (
    <span className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-400">
      <Clock size={10} /> {days}d
    </span>
  );
}

function SortableCard({ item, onOpen }: { item: BoardItem; onOpen: (item: BoardItem) => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id,
  });
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.6 : 1,
    touchAction: 'none',
  };
  const overdue = daysUntilDue(item.curation_due_at);
  const isOverdue = overdue !== null && overdue < 0;

  return (
    <article
      ref={setNodeRef}
      style={style}
      {...attributes}
      {...listeners}
      className={`rounded-xl border bg-white dark:bg-slate-900 p-3 shadow-sm cursor-grab active:cursor-grabbing hover:shadow-md transition-shadow ${
        isOverdue
          ? 'border-red-300 dark:border-red-700 ring-1 ring-red-200 dark:ring-red-800'
          : 'border-slate-200 dark:border-slate-700'
      }`}
    >
      <div className="flex items-start justify-between gap-2 mb-1">
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onOpen(item); }}
          className="text-[13px] font-bold text-navy dark:text-slate-100 line-clamp-2 flex-1 text-left hover:underline cursor-pointer bg-transparent border-0 p-0"
        >
          {item.title || 'Sem título'}
        </button>
        <SlaBadge dueAt={item.curation_due_at} />
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        {item.tribe_name ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300">
            {item.tribe_name}
          </span>
        ) : null}
        {item.review_count && item.review_count > 0 ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-violet-100 text-violet-600 dark:bg-violet-900/50 dark:text-violet-300">
            {item.review_count}x avaliado
          </span>
        ) : null}
      </div>
      {item.assignee_name ? (
        <p className="text-[11px] text-slate-500 mt-1 truncate">{item.assignee_name}</p>
      ) : null}
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onOpen(item); }}
        className="mt-2 w-full py-1.5 rounded-lg text-[11px] font-semibold bg-navy/10 text-navy hover:bg-navy/20 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600 cursor-pointer border-0 transition-colors"
      >
        Avaliar
      </button>
    </article>
  );
}

function ScoreInput({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  return (
    <div className="flex gap-1">
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          type="button"
          onClick={() => onChange(n)}
          className={`w-7 h-7 rounded-lg text-xs font-bold transition-all ${
            n <= value
              ? 'bg-navy text-white shadow-sm'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-400 hover:bg-slate-200 dark:hover:bg-slate-700'
          }`}
        >
          {n}
        </button>
      ))}
    </div>
  );
}

function ReviewRubricDialog({
  item,
  open,
  onClose,
  onSubmit,
}: {
  item: BoardItem;
  open: boolean;
  onClose: () => void;
  onSubmit: (decision: string, scores: Record<string, number>, feedback: string) => Promise<void>;
}) {
  const [scores, setScores] = useState<Record<string, number>>({});
  const [feedback, setFeedback] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [showHistory, setShowHistory] = useState(false);

  const allScored = CRITERIA.every((c) => (scores[c.key] || 0) > 0);
  const avgScore = allScored
    ? (CRITERIA.reduce((sum, c) => sum + (scores[c.key] || 0), 0) / CRITERIA.length).toFixed(1)
    : null;

  async function handleAction(decision: string) {
    if (decision !== 'approved' && !feedback.trim()) return;
    setSubmitting(true);
    try {
      await onSubmit(decision, scores, feedback);
    } finally {
      setSubmitting(false);
    }
  }

  useEffect(() => {
    if (open) {
      setScores({});
      setFeedback('');
      setShowHistory(false);
    }
  }, [open, item?.id]);

  const attachments = (() => {
    if (!item.attachments) return [];
    if (typeof item.attachments === 'string') {
      try { return JSON.parse(item.attachments); } catch { return []; }
    }
    return item.attachments;
  })();

  return (
    <Dialog.Root open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed right-0 top-0 h-full w-full max-w-lg bg-white dark:bg-slate-900 shadow-2xl z-50 overflow-y-auto data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:slide-out-to-right data-[state=open]:slide-in-from-right"
          aria-describedby={undefined}
        >
          <VisuallyHidden asChild>
            <Dialog.Title>Avaliação de curadoria</Dialog.Title>
          </VisuallyHidden>

          <div className="sticky top-0 bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-700 px-6 py-4 z-10">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <FileText size={18} className="text-navy dark:text-slate-300" />
                <h2 className="text-base font-bold text-navy dark:text-slate-100">Avaliação de Curadoria</h2>
              </div>
              <Dialog.Close asChild>
                <button className="p-1.5 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-400">
                  <span className="sr-only">Fechar</span>
                  <XCircle size={18} />
                </button>
              </Dialog.Close>
            </div>
          </div>

          <div className="px-6 py-5 space-y-6">
            {/* Card info */}
            <section className="space-y-2">
              <h3 className="text-sm font-bold text-navy dark:text-slate-100">{item.title}</h3>
              <div className="flex flex-wrap gap-2">
                {item.tribe_name ? (
                  <span className="text-[11px] px-2 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300">
                    {item.tribe_name}
                  </span>
                ) : null}
                <SlaBadge dueAt={item.curation_due_at} />
              </div>
              {item.assignee_name ? (
                <p className="text-xs text-slate-500 flex items-center gap-1">
                  <User size={12} /> {item.assignee_name}
                </p>
              ) : null}
              {item.description ? (
                <p className="text-xs text-slate-600 dark:text-slate-400 whitespace-pre-wrap max-h-32 overflow-y-auto bg-slate-50 dark:bg-slate-800/50 rounded-lg p-3">
                  {item.description}
                </p>
              ) : null}
              {attachments.length > 0 ? (
                <div className="space-y-1">
                  <p className="text-[11px] font-semibold text-slate-500">Anexos:</p>
                  {attachments.map((a: { url: string }, i: number) => (
                    <a
                      key={i}
                      href={a.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="block text-xs text-navy dark:text-blue-400 underline truncate"
                    >
                      {a.url}
                    </a>
                  ))}
                </div>
              ) : null}
            </section>

            {/* Review history */}
            {item.review_history && item.review_history.length > 0 ? (
              <section>
                <button
                  type="button"
                  onClick={() => setShowHistory(!showHistory)}
                  className="flex items-center gap-1 text-xs font-semibold text-violet-600 dark:text-violet-400 hover:underline"
                >
                  {showHistory ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                  Histórico ({item.review_history.length} avaliação{item.review_history.length > 1 ? 'ões' : ''})
                </button>
                {showHistory ? (
                  <div className="mt-2 space-y-2">
                    {item.review_history.map((r) => (
                      <div key={r.id} className="text-xs bg-slate-50 dark:bg-slate-800/50 rounded-lg p-3 space-y-1">
                        <div className="flex items-center justify-between">
                          <span className="font-semibold text-slate-700 dark:text-slate-300">{r.curator_name || '—'}</span>
                          <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${
                            r.decision === 'approved' ? 'bg-emerald-100 text-emerald-700' :
                            r.decision === 'rejected' ? 'bg-red-100 text-red-700' :
                            'bg-amber-100 text-amber-700'
                          }`}>
                            {r.decision === 'approved' ? 'Aprovado' : r.decision === 'rejected' ? 'Rejeitado' : 'Devolvido'}
                          </span>
                        </div>
                        {r.feedback ? <p className="text-slate-500">{r.feedback}</p> : null}
                        <p className="text-slate-400">{new Date(r.completed_at).toLocaleDateString('pt-BR')}</p>
                      </div>
                    ))}
                  </div>
                ) : null}
              </section>
            ) : null}

            {/* Rubric */}
            <section className="space-y-3">
              <div className="flex items-center justify-between">
                <h4 className="text-sm font-bold text-navy dark:text-slate-100 flex items-center gap-1.5">
                  <Star size={14} /> Rubrica de Avaliação
                </h4>
                {avgScore ? (
                  <span className={`text-sm font-bold px-2 py-0.5 rounded-full ${
                    parseFloat(avgScore) >= 4 ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/50 dark:text-emerald-300' :
                    parseFloat(avgScore) >= 3 ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/50 dark:text-amber-300' :
                    'bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300'
                  }`}>
                    Média: {avgScore}
                  </span>
                ) : null}
              </div>
              {CRITERIA.map((c) => (
                <div key={c.key} className="flex items-center justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-semibold text-slate-700 dark:text-slate-300">{c.label}</p>
                    <p className="text-[10px] text-slate-400 truncate">{c.tip}</p>
                  </div>
                  <ScoreInput
                    value={scores[c.key] || 0}
                    onChange={(v) => setScores((prev) => ({ ...prev, [c.key]: v }))}
                  />
                </div>
              ))}
            </section>

            {/* Feedback */}
            <section className="space-y-2">
              <label className="text-xs font-bold text-navy dark:text-slate-100">
                Feedback para a Tribo
              </label>
              <textarea
                value={feedback}
                onChange={(e) => setFeedback(e.target.value)}
                rows={3}
                placeholder="Observações que serão enviadas ao Líder da Tribo (obrigatório para devoluções e rejeições)..."
                className="w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800 px-3 py-2 text-xs text-slate-700 dark:text-slate-300 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-navy/30 resize-none"
              />
            </section>

            {/* Actions */}
            <section className="flex flex-col gap-2 pt-2 border-t border-slate-200 dark:border-slate-700">
              <button
                type="button"
                disabled={!allScored || submitting}
                onClick={() => handleAction('approved')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
              >
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />}
                Aprovar e Publicar
              </button>
              <button
                type="button"
                disabled={!feedback.trim() || submitting}
                onClick={() => handleAction('returned_for_revision')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-amber-700 bg-amber-100 hover:bg-amber-200 dark:text-amber-300 dark:bg-amber-900/40 dark:hover:bg-amber-900/60 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
              >
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <RotateCcw size={16} />}
                Devolver à Tribo
              </button>
              <button
                type="button"
                disabled={!feedback.trim() || submitting}
                onClick={() => handleAction('rejected')}
                className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl text-sm font-bold text-red-600 bg-red-50 hover:bg-red-100 dark:text-red-400 dark:bg-red-900/20 dark:hover:bg-red-900/40 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
              >
                {submitting ? <Loader2 size={16} className="animate-spin" /> : <XCircle size={16} />}
                Rejeitar
              </button>
            </section>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

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

  const loadItems = useCallback(async () => {
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
  }, []);

  useEffect(() => {
    loadItems().catch(() => setLoading(false));
  }, [loadItems]);

  async function handleReviewSubmit(decision: string, scores: Record<string, number>, feedback: string) {
    if (!modalItem) return;
    const sb = windowRef?.navGetSb?.();
    if (!sb) return;

    const { error } = await sb.rpc('submit_curation_review', {
      p_item_id: modalItem.id,
      p_decision: decision,
      p_criteria_scores: scores,
      p_feedback_notes: feedback || null,
    });

    if (error) {
      windowRef?.toast?.(error.message || ui.error, 'error');
      return;
    }

    const labels: Record<string, string> = {
      approved: 'Aprovado e publicado!',
      returned_for_revision: 'Devolvido à tribo com feedback.',
      rejected: 'Rejeitado pelo comitê.',
    };
    windowRef?.toast?.(labels[decision] || 'Ação concluída.', decision === 'approved' ? 'success' : 'info');

    setModalItem(null);
    setItems((prev) => prev.filter((i) => i.id !== modalItem.id));
  }

  async function onDragEnd(event: DragEndEvent) {
    setActiveId('');
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const itemId = String(active.id);
    const overId = String(over.id);
    if (overId !== 'published') return;

    const item = items.find((i) => i.id === itemId);
    if (!item) return;

    setModalItem(item);
  }

  if (loading) {
    return <div className="text-center py-10 text-slate-400">{ui.loading}</div>;
  }
  if (denied) {
    return <div className="text-center py-10 text-slate-500">{ui.denied}</div>;
  }

  const overdueCount = pending.filter((i) => {
    const d = daysUntilDue(i.curation_due_at);
    return d !== null && d < 0;
  }).length;

  return (
    <div className="space-y-4">
      {overdueCount > 0 ? (
        <div className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
          <AlertTriangle size={16} className="text-red-600 dark:text-red-400" />
          <p className="text-xs font-semibold text-red-700 dark:text-red-300">
            {overdueCount} {overdueCount === 1 ? 'item' : 'itens'} com SLA vencido — ação urgente necessária.
          </p>
        </div>
      ) : null}

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
                Arraste ou clique para avaliar
              </span>
            </div>
            <PublishedDropZone />
          </section>
        </DndContext>
      </div>

      <p className="text-[12px] text-slate-500">
        Itens publicados aparecem em <a href="/publications" className="text-navy font-semibold underline hover:no-underline">/publications</a>.
      </p>

      {modalItem ? (
        <ReviewRubricDialog
          item={modalItem}
          open={!!modalItem}
          onClose={() => setModalItem(null)}
          onSubmit={handleReviewSubmit}
        />
      ) : null}
    </div>
  );
}
