import { useState, useEffect, useCallback, useRef } from 'react';
import type { Board, BoardItem, BoardI18n, LifecycleEvent, BoardMember, BoardSummary, CurationHistory, RubricScore, ItemAssignment, AssignmentRole } from '../../types/board';
import { COLUMN_PRESETS } from '../../types/board';
import { getSb } from '../../hooks/useBoard';
import MemberPicker from './MemberPicker';
import MemberPickerMulti from './MemberPickerMulti';

interface Props {
  item: BoardItem;
  board: Board;
  permissions: { canEditOwn: boolean; canEditAny: boolean; canAssign: boolean; canDelete: boolean; canCurate: boolean; member: any };
  mode: string;
  i18n: BoardI18n;
  onClose: () => void;
  onUpdate: (fields: Record<string, any>) => Promise<void>;
  onMove: (newStatus: string) => void;
  onDelete: () => void;
  onDuplicate: () => void;
  onMoveToBoard: (boardId: string) => void;
}

export default function CardDetail({ item, board, permissions, mode, i18n, onClose, onUpdate, onMove, onDelete, onDuplicate, onMoveToBoard }: Props) {
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKey);
    panelRef.current?.focus();
    return () => window.removeEventListener('keydown', handleKey);
  }, [onClose]);
  const [title, setTitle] = useState(item.title);
  const [description, setDescription] = useState(item.description || '');
  const [checklist, setChecklist] = useState(item.checklist || []);
  const [newCheckItem, setNewCheckItem] = useState('');
  const [tags, setTags] = useState(item.tags || []);
  const [tagInput, setTagInput] = useState('');
  const [dueDate, setDueDate] = useState(item.due_date || '');
  const [timeline, setTimeline] = useState<LifecycleEvent[]>([]);
  const [members, setMembers] = useState<BoardMember[]>([]);
  const [boards, setBoards] = useState<BoardSummary[]>([]);
  const [assigneeId, setAssigneeId] = useState(item.assignee_id || '');
  const [reviewerId, setReviewerId] = useState(item.reviewer_id || '');
  const [dirty, setDirty] = useState(false);
  const [showMoveToBoard, setShowMoveToBoard] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [attachments, setAttachments] = useState(item.attachments || []);
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [curationHistory, setCurationHistory] = useState<CurationHistory | null>(null);
  const [showReviewForm, setShowReviewForm] = useState(false);
  const [reviewScores, setReviewScores] = useState<Record<string, number>>({ clarity: 3, originality: 3, adherence: 3, relevance: 3, ethics: 3 });
  const [reviewVerdict, setReviewVerdict] = useState<string>('approved');
  const [reviewNotes, setReviewNotes] = useState('');
  const [submittingReview, setSubmittingReview] = useState(false);
  const [itemAssignments, setItemAssignments] = useState<ItemAssignment[]>(item.assignments || []);

  const canEdit = mode !== 'readonly' && (permissions.canEditAny || (permissions.canEditOwn && permissions.member?.id === item.assignee_id));
  const isCurator = permissions.canCurate;
  const isCurationItem = item.curation_status === 'curation_pending';

  // ── Attachment upload ──
  const ALLOWED_TYPES = ['application/pdf', 'image/png', 'image/jpeg', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'];
  const ALLOWED_EXTENSIONS = /\.(pdf|png|jpg|jpeg|docx|xlsx|pptx)$/i;
  const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB

  const handleFileUpload = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    // Reset input so same file can be re-selected
    e.target.value = '';

    if (!ALLOWED_EXTENSIONS.test(file.name)) {
      (window as any).toast?.('Tipo de arquivo não permitido. Use: pdf, png, jpg, docx, xlsx, pptx', 'error');
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      (window as any).toast?.('Arquivo muito grande. Limite: 5MB', 'error');
      return;
    }

    setUploading(true);
    try {
      const sb = getSb();
      if (!sb) throw new Error('Supabase indisponível');

      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
      const storagePath = `${board.id}/${item.id}/${Date.now()}_${safeName}`;

      const { error: uploadError } = await sb.storage
        .from('board-attachments')
        .upload(storagePath, file, { contentType: file.type, upsert: false });

      if (uploadError) throw uploadError;

      const { data: urlData } = sb.storage
        .from('board-attachments')
        .getPublicUrl(storagePath);

      const newAttachment = { name: file.name, url: urlData?.publicUrl || storagePath };
      const updated = [...attachments, newAttachment];
      setAttachments(updated);
      await onUpdate({ attachments: updated });
      (window as any).toast?.('Arquivo anexado', 'success');
    } catch (err: any) {
      console.error('Upload error:', err);
      (window as any).toast?.(`Erro no upload: ${err.message || 'desconhecido'}`, 'error');
    } finally {
      setUploading(false);
    }
  }, [attachments, board.id, item.id, onUpdate]);

  const handleRemoveAttachment = useCallback(async (idx: number) => {
    const updated = attachments.filter((_, i) => i !== idx);
    setAttachments(updated);
    await onUpdate({ attachments: updated });
    (window as any).toast?.('Anexo removido');
  }, [attachments, onUpdate]);

  // Fetch timeline + members on mount
  useEffect(() => {
    (async () => {
      const sb = getSb();
      if (!sb) return;

      const safe = (p: Promise<any>) => p.then((r: any) => r).catch(() => ({ data: null }));
      const [tl, mb, bl] = await Promise.all([
        safe(sb.rpc('get_card_timeline', { p_item_id: item.id })),
        safe(sb.rpc('get_board_members', { p_board_id: board.id })),
        safe(sb.rpc('list_active_boards')),
      ]);

      if (Array.isArray(tl.data)) setTimeline(tl.data);
      if (Array.isArray(mb.data)) setMembers(mb.data);
      if (Array.isArray(bl.data)) setBoards(bl.data.filter((b: any) => b.id !== board.id));

      // Fetch assignments from junction table
      const asn = await safe(sb.rpc('get_item_assignments', { p_item_id: item.id }));
      if (Array.isArray(asn.data) && asn.data.length > 0) {
        setItemAssignments(asn.data as ItemAssignment[]);
      } else if (item.assignments && item.assignments.length > 0) {
        setItemAssignments(item.assignments);
      }

      // Fetch curation history if item has curation_status
      if (item.curation_status && item.curation_status !== 'draft') {
        const ch = await safe(sb.rpc('get_item_curation_history', { p_item_id: item.id }));
        if (ch.data && typeof ch.data === 'object') setCurationHistory(ch.data as CurationHistory);
      }
    })();
  }, [item.id, board.id, item.curation_status]);

  // ── Save ──
  const handleSave = useCallback(async () => {
    const fields: Record<string, any> = {};
    if (title !== item.title) fields.title = title;
    if (description !== (item.description || '')) fields.description = description;
    if (JSON.stringify(checklist) !== JSON.stringify(item.checklist || [])) fields.checklist = checklist;
    if (JSON.stringify(tags) !== JSON.stringify(item.tags || [])) fields.tags = tags;
    if (dueDate !== (item.due_date || '')) fields.due_date = dueDate || null;
    if (assigneeId !== (item.assignee_id || '')) fields.assignee_id = assigneeId || null;
    if (reviewerId !== (item.reviewer_id || '')) fields.reviewer_id = reviewerId || null;

    if (Object.keys(fields).length > 0) {
      await onUpdate(fields);
      setDirty(false);
    }
  }, [title, description, checklist, tags, dueDate, assigneeId, reviewerId, item, onUpdate]);

  // ── Multi-assignee handlers ──
  const handleAddAssignment = useCallback(async (memberId: string, role: AssignmentRole) => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { error } = await sb.rpc('assign_member_to_item', {
        p_item_id: item.id, p_member_id: memberId, p_role: role,
      });
      if (error) throw error;
      const member = members.find((m) => m.id === memberId);
      setItemAssignments((prev) => [
        ...prev,
        { member_id: memberId, name: member?.name || '', avatar_url: member?.avatar_url || null, role, assigned_at: new Date().toISOString() },
      ]);
      (window as any).toast?.('Membro adicionado', 'success');
    } catch (err: any) {
      (window as any).toast?.(err.message || 'Erro ao adicionar membro', 'error');
    }
  }, [item.id, members]);

  const handleRemoveAssignment = useCallback(async (memberId: string, role: AssignmentRole) => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { error } = await sb.rpc('unassign_member_from_item', {
        p_item_id: item.id, p_member_id: memberId, p_role: role,
      });
      if (error) throw error;
      setItemAssignments((prev) => prev.filter((a) => !(a.member_id === memberId && a.role === role)));
      (window as any).toast?.('Membro removido');
    } catch (err: any) {
      (window as any).toast?.(err.message || 'Erro ao remover membro', 'error');
    }
  }, [item.id]);

  // ── Curation review submit ──
  const handleSubmitReview = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setSubmittingReview(true);
    try {
      const { error } = await sb.rpc('submit_curation_review', {
        p_item_id: item.id,
        p_decision: reviewVerdict,
        p_criteria_scores: reviewScores,
        p_feedback_notes: reviewNotes || null,
      });
      if (error) throw error;
      (window as any).toast?.('Parecer registrado', 'success');
      setShowReviewForm(false);
      // Refresh curation history
      const ch = await sb.rpc('get_item_curation_history', { p_item_id: item.id });
      if (ch.data && typeof ch.data === 'object') setCurationHistory(ch.data as CurationHistory);
    } catch (err: any) {
      (window as any).toast?.(`Erro: ${err.message || 'desconhecido'}`, 'error');
    } finally {
      setSubmittingReview(false);
    }
  }, [item.id, reviewVerdict, reviewScores, reviewNotes]);

  // ── Checklist helpers ──
  const addCheckItem = () => {
    if (!newCheckItem.trim()) return;
    setChecklist([...checklist, { text: newCheckItem.trim(), done: false }]);
    setNewCheckItem('');
    setDirty(true);
  };

  const toggleCheck = (idx: number) => {
    const updated = [...checklist];
    updated[idx] = { ...updated[idx], done: !updated[idx].done };
    setChecklist(updated);
    setDirty(true);
  };

  const removeCheck = (idx: number) => {
    setChecklist(checklist.filter((_, i) => i !== idx));
    setDirty(true);
  };

  // ── Tag helpers ──
  const addTag = (t: string) => {
    const clean = t.trim().toLowerCase();
    if (clean && !tags.includes(clean)) { setTags([...tags, clean]); setDirty(true); }
    setTagInput('');
  };

  const checkDone = checklist.filter((c) => c.done).length;
  const checkTotal = checklist.length;
  const checkPct = checkTotal > 0 ? Math.round((checkDone / checkTotal) * 100) : 0;

  return (
    <div ref={panelRef} tabIndex={-1}
      className="fixed inset-0 z-[600] flex items-start justify-center bg-black/40 backdrop-blur-sm p-4 pt-16 overflow-y-auto outline-none"
      onClick={onClose} role="dialog" aria-modal="true" aria-label={item.title}>
      <div className="bg-[var(--surface-elevated)] rounded-2xl shadow-2xl w-full max-w-3xl" onClick={(e) => e.stopPropagation()}>
        {/* Top bar */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--border-subtle)]">
          <div className="flex items-center gap-2">
            <span className={`px-2 py-0.5 rounded-md text-[10px] font-bold
              ${COLUMN_PRESETS[item.status]?.badgeBg ?? 'bg-[var(--surface-section-cool)]'} 
              ${COLUMN_PRESETS[item.status]?.badgeText ?? 'text-[var(--text-secondary)]'}`}>
              {COLUMN_PRESETS[item.status]?.label ?? item.status}
            </span>
            {item.source_card_id && <span className="text-[9px] text-blue-400">🟦 Trello</span>}
          </div>
          <div className="flex items-center gap-2">
            {dirty && canEdit && (
              <button onClick={handleSave}
                className="px-4 py-1.5 bg-blue-600 text-white rounded-lg text-[11px] font-bold cursor-pointer hover:bg-blue-700 border-0">
                💾 {i18n.save}
              </button>
            )}
            <button onClick={onClose}
              className="text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer bg-transparent border-0 text-lg">✕</button>
          </div>
        </div>

        <div className="flex flex-col md:flex-row">
          {/* ── Main content (left) ── */}
          <div className="flex-1 p-6 space-y-5 min-w-0">
            {/* Title */}
            {canEdit ? (
              <input type="text" value={title}
                onChange={(e) => { setTitle(e.target.value); setDirty(true); }}
                className="w-full text-lg font-extrabold text-[var(--text-primary)] border-0 outline-none bg-transparent
                  focus:bg-[var(--surface-base)] rounded-lg px-1 -ml-1 transition-colors" />
            ) : (
              <h2 className="text-lg font-extrabold text-[var(--text-primary)]">{title}</h2>
            )}

            {/* Description */}
            <div>
              <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1 block">{i18n.description}</label>
              {canEdit ? (
                <textarea value={description}
                  onChange={(e) => { setDescription(e.target.value); setDirty(true); }}
                  rows={4}
                  className="w-full rounded-xl border border-[var(--border-default)] px-3 py-2 text-[12px] text-[var(--text-primary)]
                    outline-none focus:border-blue-400 transition-all resize-y"
                  placeholder="Adicionar descrição..." />
              ) : (
                <p className="text-[13px] text-[var(--text-secondary)] whitespace-pre-wrap">{description || 'Sem descrição'}</p>
              )}
            </div>

            {/* Checklist */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-[11px] font-semibold text-[var(--text-secondary)]">{i18n.checklist}</label>
                {checkTotal > 0 && (
                  <span className="text-[10px] font-bold text-[var(--text-muted)]">{checkDone}/{checkTotal} ({checkPct}%)</span>
                )}
              </div>
              {checkTotal > 0 && (
                <div className="w-full bg-[var(--surface-section-cool)] rounded-full h-1.5 mb-3">
                  <div className="bg-emerald-500 h-1.5 rounded-full transition-all" style={{ width: `${checkPct}%` }} />
                </div>
              )}
              <div className="space-y-1.5">
                {checklist.map((ci, idx) => (
                  <div key={idx} className="flex items-center gap-2 group">
                    <input type="checkbox" checked={ci.done}
                      onChange={() => toggleCheck(idx)}
                      disabled={!canEdit}
                      className="w-4 h-4 rounded border-[var(--border-default)] cursor-pointer accent-emerald-500" />
                    <span className={`flex-1 text-[12px] ${ci.done ? 'line-through text-[var(--text-muted)]' : 'text-[var(--text-primary)]'}`}>
                      {ci.text}
                    </span>
                    {canEdit && (
                      <button onClick={() => removeCheck(idx)}
                        className="opacity-0 group-hover:opacity-100 text-red-400 hover:text-red-600 
                          cursor-pointer bg-transparent border-0 text-[10px]">✕</button>
                    )}
                  </div>
                ))}
              </div>
              {canEdit && (
                <div className="flex gap-2 mt-2">
                  <input type="text" value={newCheckItem}
                    onChange={(e) => setNewCheckItem(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && addCheckItem()}
                    placeholder={i18n.addItem}
                    className="flex-1 rounded-lg border border-[var(--border-default)] px-3 py-1.5 text-[11px]
                      outline-none focus:border-blue-400" />
                  <button onClick={addCheckItem}
                    className="px-3 py-1.5 bg-[var(--surface-section-cool)] text-[var(--text-secondary)] rounded-lg text-[11px] font-semibold
                      cursor-pointer hover:bg-[var(--surface-hover)] border-0">+ Adicionar</button>
                </div>
              )}
            </div>

            {/* Attachments */}
            <div>
              <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-2 block">{i18n.attachments}</label>
              {attachments.length > 0 && (
                <div className="space-y-1.5 mb-2">
                  {attachments.map((att, idx) => {
                    const isImage = att.name?.match(/\.(png|jpg|jpeg|gif|webp)$/i);
                    return (
                      <div key={idx} className="flex items-center gap-2 group">
                        <a href={att.url} target="_blank" rel="noopener noreferrer"
                          className="flex-1 flex items-center gap-2 px-3 py-2 bg-[var(--surface-base)] rounded-lg hover:bg-[var(--surface-hover)]
                            no-underline transition-colors min-w-0">
                          {isImage ? (
                            <img src={att.url} alt={att.name} className="w-8 h-8 rounded object-cover flex-shrink-0" />
                          ) : (
                            <span className="text-[12px] flex-shrink-0">📄</span>
                          )}
                          <span className="text-[11px] text-blue-600 truncate">{att.name || att.url}</span>
                        </a>
                        {canEdit && (
                          <button type="button" onClick={() => handleRemoveAttachment(idx)}
                            className="opacity-0 group-hover:opacity-100 text-[10px] text-red-500 hover:text-red-700
                              border-0 bg-transparent cursor-pointer transition-opacity p-1"
                            title="Remover anexo">✕</button>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
              {canEdit && (
                <>
                  <input ref={fileInputRef} type="file" className="hidden"
                    accept=".pdf,.png,.jpg,.jpeg,.docx,.xlsx,.pptx"
                    onChange={handleFileUpload} />
                  <button type="button" onClick={() => fileInputRef.current?.click()}
                    disabled={uploading}
                    className="text-[11px] font-semibold text-teal hover:text-[var(--color-teal-deep)]
                      border border-dashed border-[var(--border-default)] rounded-lg px-3 py-2 w-full
                      bg-transparent cursor-pointer hover:bg-[var(--surface-hover)] transition-colors
                      disabled:opacity-50 disabled:cursor-wait">
                    {uploading ? 'Enviando...' : '+ Anexar arquivo'}
                  </button>
                  <p className="text-[9px] text-[var(--text-muted)] mt-1">PDF, PNG, JPG, DOCX, XLSX, PPTX — máx 5MB</p>
                </>
              )}
            </div>

            {/* ── Curation Pipeline Visual ── */}
            {item.curation_status && item.curation_status !== 'draft' && (
              <div className="mb-3">
                <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-2 block">
                  {i18n.curationPipeline || 'Pipeline de Curadoria'}
                </label>
                <div className="flex items-center gap-0.5 flex-wrap">
                  {['ideation', 'research', 'drafting', 'author_review', 'peer_review', 'leader_review', 'curation', 'published'].map((step, idx) => {
                    const STEP_LABELS: Record<string, string> = {
                      ideation: 'Ideação', research: 'Pesquisa', drafting: 'Redação',
                      author_review: 'Rev. Autores', peer_review: 'Peer Review',
                      leader_review: 'Rev. Líder', curation: 'Curadoria', published: 'Publicado'
                    };
                    const steps = ['ideation', 'research', 'drafting', 'author_review', 'peer_review', 'leader_review', 'curation', 'published'];
                    const currentIdx = steps.indexOf(item.curation_status || '');
                    const isActive = idx === currentIdx;
                    const isDone = idx < currentIdx;
                    const bg = isActive ? 'bg-teal text-white' : isDone ? 'bg-teal/20 text-teal' : 'bg-[var(--surface-hover)] text-[var(--text-muted)]';
                    return (
                      <span key={step} className={`px-1.5 py-0.5 rounded text-[8px] font-bold ${bg}`} title={STEP_LABELS[step]}>
                        {STEP_LABELS[step]}
                      </span>
                    );
                  })}
                </div>
              </div>
            )}

            {/* ── Curation Section ── */}
            {curationHistory && (curationHistory.reviews.length > 0 || isCurationItem) && (
              <div>
                <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-2 block">
                  {i18n.curationTab || 'Curadoria'}
                </label>

                {/* SLA Badge */}
                {item.curation_due_at && (
                  <div className="mb-3">
                    {(() => {
                      const due = new Date(item.curation_due_at);
                      const now = new Date();
                      const daysLeft = Math.ceil((due.getTime() - now.getTime()) / 86400000);
                      const color = daysLeft < 0 ? 'bg-red-100 text-red-700' : daysLeft <= 2 ? 'bg-amber-100 text-amber-700' : 'bg-emerald-100 text-emerald-700';
                      const label = daysLeft < 0 ? `${Math.abs(daysLeft)}d atrasado` : daysLeft === 0 ? 'Vence hoje' : `${daysLeft}d restantes`;
                      return <span className={`inline-block px-2 py-0.5 rounded text-[10px] font-bold ${color}`}>SLA: {label}</span>;
                    })()}
                  </div>
                )}

                {/* Reviewer progress */}
                {curationHistory.sla_config && 'reviewers_required' in curationHistory.sla_config && (
                  <div className="mb-3 text-[11px] text-[var(--text-secondary)]">
                    {(() => {
                      const approved = curationHistory.reviews.filter(r => r.decision === 'approved').length;
                      const required = curationHistory.sla_config.reviewers_required || 2;
                      return <span>{approved}/{required} revisores aprovaram</span>;
                    })()}
                  </div>
                )}

                {/* Review history */}
                {curationHistory.reviews.length > 0 && (
                  <div className="space-y-3 mb-3">
                    {curationHistory.reviews.map((rev) => (
                      <div key={rev.id} className="bg-[var(--surface-base)] rounded-xl p-3 border border-[var(--border-subtle)]">
                        <div className="flex items-center justify-between mb-2">
                          <span className="text-[11px] font-bold text-[var(--text-primary)]">{rev.curator_name}</span>
                          <span className={`px-1.5 py-0.5 rounded text-[9px] font-bold ${
                            rev.decision === 'approved' ? 'bg-emerald-100 text-emerald-700'
                            : rev.decision === 'rejected' ? 'bg-red-100 text-red-700'
                            : 'bg-amber-100 text-amber-700'
                          }`}>
                            {rev.decision === 'approved' ? 'Aprovado' : rev.decision === 'rejected' ? 'Rejeitado' : 'Revisão solicitada'}
                          </span>
                        </div>
                        {/* Rubric scores as bars */}
                        {rev.criteria_scores && Object.keys(rev.criteria_scores).length > 0 && (
                          <div className="space-y-1 mb-2">
                            {(['clarity', 'originality', 'adherence', 'relevance', 'ethics'] as const).map((key) => {
                              const score = (rev.criteria_scores as RubricScore)?.[key] || 0;
                              const labels: Record<string, string> = {
                                clarity: i18n.rubricClarity || 'Clareza',
                                originality: i18n.rubricOriginality || 'Originalidade',
                                adherence: i18n.rubricAdherence || 'Aderência',
                                relevance: i18n.rubricRelevance || 'Relevância',
                                ethics: i18n.rubricEthics || 'Ética',
                              };
                              return (
                                <div key={key} className="flex items-center gap-2">
                                  <span className="text-[9px] text-[var(--text-muted)] w-16 truncate">{labels[key]}</span>
                                  <div className="flex-1 bg-[var(--surface-section-cool)] rounded-full h-1.5">
                                    <div className="bg-blue-500 h-1.5 rounded-full transition-all" style={{ width: `${(score / 5) * 100}%` }} />
                                  </div>
                                  <span className="text-[9px] font-bold text-[var(--text-secondary)] w-4 text-right">{score}</span>
                                </div>
                              );
                            })}
                          </div>
                        )}
                        {rev.feedback_notes && (
                          <p className="text-[10px] text-[var(--text-muted)] italic mt-1">{rev.feedback_notes}</p>
                        )}
                        <span className="text-[9px] text-[var(--text-muted)]">
                          {new Date(rev.completed_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' })}
                        </span>
                      </div>
                    ))}
                  </div>
                )}

                {/* Review form button + form */}
                {isCurator && isCurationItem && !showReviewForm && (
                  <button onClick={() => setShowReviewForm(true)}
                    className="w-full px-3 py-2 bg-purple-600 text-white rounded-lg text-[11px] font-bold cursor-pointer hover:bg-purple-700 border-0">
                    📝 {i18n.curationSubmitReview || 'Submeter Parecer'}
                  </button>
                )}

                {showReviewForm && (
                  <div className="bg-[var(--surface-base)] rounded-xl p-4 border border-purple-200 space-y-3">
                    <h4 className="text-[12px] font-bold text-[var(--text-primary)]">Parecer de Curadoria</h4>
                    {/* Rubric sliders */}
                    {(['clarity', 'originality', 'adherence', 'relevance', 'ethics'] as const).map((key) => {
                      const labels: Record<string, string> = {
                        clarity: i18n.rubricClarity || 'Clareza e estrutura',
                        originality: i18n.rubricOriginality || 'Originalidade',
                        adherence: i18n.rubricAdherence || 'Aderência ao tema',
                        relevance: i18n.rubricRelevance || 'Relevância prática',
                        ethics: i18n.rubricEthics || 'Conformidade ética',
                      };
                      return (
                        <div key={key}>
                          <div className="flex justify-between text-[10px] mb-0.5">
                            <span className="text-[var(--text-secondary)]">{labels[key]}</span>
                            <span className="font-bold text-[var(--text-primary)]">{reviewScores[key]}/5</span>
                          </div>
                          <input type="range" min="1" max="5" step="1"
                            value={reviewScores[key]}
                            onChange={(e) => setReviewScores({ ...reviewScores, [key]: parseInt(e.target.value) })}
                            className="w-full h-1.5 accent-purple-600" />
                        </div>
                      );
                    })}
                    {/* Verdict */}
                    <div>
                      <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block">Decisão</label>
                      <select value={reviewVerdict} onChange={(e) => setReviewVerdict(e.target.value)}
                        className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1.5 text-[12px] bg-[var(--surface-card)] outline-none">
                        <option value="approved">Aprovado</option>
                        <option value="returned_for_revision">Devolver para revisão</option>
                        <option value="rejected">Rejeitar</option>
                      </select>
                    </div>
                    {/* Notes */}
                    <textarea value={reviewNotes} onChange={(e) => setReviewNotes(e.target.value)}
                      rows={3} placeholder="Observações (opcional)"
                      className="w-full rounded-xl border border-[var(--border-default)] px-3 py-2 text-[11px] outline-none focus:border-purple-400 resize-y" />
                    {/* Actions */}
                    <div className="flex gap-2">
                      <button onClick={handleSubmitReview} disabled={submittingReview}
                        className="flex-1 px-3 py-1.5 bg-purple-600 text-white rounded-lg text-[11px] font-bold cursor-pointer hover:bg-purple-700 border-0 disabled:opacity-50">
                        {submittingReview ? 'Enviando...' : 'Confirmar Parecer'}
                      </button>
                      <button onClick={() => setShowReviewForm(false)}
                        className="px-3 py-1.5 bg-[var(--surface-section-cool)] text-[var(--text-secondary)] rounded-lg text-[11px] font-semibold cursor-pointer border border-[var(--border-default)]">
                        {i18n.cancel || 'Cancelar'}
                      </button>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Timeline */}
            {timeline.length > 0 && (
              <div>
                <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-2 block">{i18n.timeline}</label>
                <div className="space-y-2 max-h-[200px] overflow-y-auto">
                  {timeline.map((ev) => (
                    <div key={ev.id} className="flex gap-2 text-[11px]">
                      <span className="text-[var(--text-muted)] whitespace-nowrap">
                        {new Date(ev.created_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                      </span>
                      <span className="text-[var(--text-secondary)]">
                        {ev.actor_name && <strong>{ev.actor_name}</strong>}
                        {' '}
                        {ev.action === 'status_change' && `moveu de "${COLUMN_PRESETS[ev.previous_status || '']?.label ?? ev.previous_status}" para "${COLUMN_PRESETS[ev.new_status || '']?.label ?? ev.new_status}"`}
                        {ev.action === 'created' && 'criou este card'}
                        {ev.action === 'assigned' && (ev.reason || 'atribuiu responsável')}
                        {ev.action === 'archived' && 'arquivou este card'}
                        {ev.action === 'moved_out' && 'moveu para outro board'}
                        {ev.action === 'moved_in' && 'recebido de outro board'}
                        {ev.action === 'submitted_for_curation' && 'submeteu para curadoria'}
                        {ev.action === 'reviewer_assigned' && (ev.reason || 'designou revisor')}
                        {ev.action === 'curation_review' && `registrou parecer${ev.review_round ? ` (rodada ${ev.review_round})` : ''}`}
                        {ev.action === 'curation_approved' && (ev.reason || 'aprovado pelo comitê de curadoria')}
                        {!['status_change', 'created', 'assigned', 'archived', 'moved_out', 'moved_in', 'submitted_for_curation', 'reviewer_assigned', 'curation_review', 'curation_approved'].includes(ev.action) && ev.action}
                        {ev.reason && ev.action !== 'assigned' && <span className="text-[var(--text-muted)] ml-1">— {ev.reason}</span>}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* ── Sidebar (right) ── */}
          <div className="w-full md:w-[240px] p-6 md:border-l border-[var(--border-subtle)] space-y-4">
            {/* Status */}
            <div>
              <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">Status</label>
              <select value={item.status}
                onChange={(e) => onMove(e.target.value)}
                disabled={mode === 'readonly' || !permissions.canEditAny}
                className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1.5 text-[12px] bg-[var(--surface-card)]
                  outline-none focus:border-blue-400 cursor-pointer disabled:opacity-60 disabled:cursor-not-allowed">
                {board.columns.map((col: string) => (
                  <option key={col} value={col}>{COLUMN_PRESETS[col]?.label ?? col}</option>
                ))}
              </select>
            </div>

            {/* Assignees (multi-role) */}
            <div>
              <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">{i18n.assignees || 'Participantes'}</label>
              <MemberPickerMulti
                members={members}
                assignments={itemAssignments}
                onAdd={handleAddAssignment}
                onRemove={handleRemoveAssignment}
                i18n={i18n}
                disabled={!permissions.canAssign}
              />
            </div>

            {/* Legacy single assignee/reviewer (hidden if junction data exists) */}
            {itemAssignments.length === 0 && (
              <>
                <div>
                  <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">{i18n.assignee}</label>
                  <MemberPicker
                    members={members}
                    value={assigneeId}
                    onChange={(id) => { setAssigneeId(id); setDirty(true); }}
                    placeholder={i18n.noAssignee}
                    disabled={!permissions.canAssign}
                  />
                </div>
                <div>
                  <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">{i18n.reviewer}</label>
                  <MemberPicker
                    members={members}
                    value={reviewerId}
                    onChange={(id) => { setReviewerId(id); setDirty(true); }}
                    placeholder={i18n.noReviewer}
                    disabled={!permissions.canAssign}
                  />
                </div>
              </>
            )}

            {/* Tags */}
            <div>
              <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">{i18n.tags}</label>
              <div className="flex flex-wrap gap-1 mb-1.5 min-h-[24px]">
                {tags.map((t) => (
                  <span key={t} className="inline-flex items-center gap-0.5 px-1.5 py-0.5 bg-blue-50 text-blue-700 rounded text-[10px] font-medium">
                    {t}
                    {canEdit && <button onClick={() => { setTags(tags.filter((x) => x !== t)); setDirty(true); }}
                      className="text-blue-400 hover:text-red-500 cursor-pointer bg-transparent border-0 text-[9px] ml-0.5">✕</button>}
                  </span>
                ))}
              </div>
              {canEdit && (
                <input type="text" value={tagInput}
                  onChange={(e) => setTagInput(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); addTag(tagInput); } }}
                  placeholder="Tag + Enter"
                  className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[11px]
                    outline-none focus:border-blue-400" />
              )}
            </div>

            {/* Due Date */}
            <div>
              <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">{i18n.dueDate}</label>
              <input type="date" value={dueDate}
                onChange={(e) => { setDueDate(e.target.value); setDirty(true); }}
                disabled={!canEdit}
                className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1.5 text-[12px] bg-[var(--surface-card)]
                  outline-none focus:border-blue-400" />
            </div>

            {/* Actions — hidden in readonly mode */}
            {mode !== 'readonly' && (
            <div className="pt-3 border-t border-[var(--border-subtle)] space-y-2">
              <button onClick={onDuplicate}
                className="w-full px-3 py-1.5 rounded-lg bg-[var(--surface-base)] text-[var(--text-secondary)] text-[11px] font-semibold
                  border border-[var(--border-default)] hover:bg-[var(--surface-hover)] cursor-pointer text-left">
                📋 {i18n.duplicate}
              </button>

              {boards.length > 0 && (
                <div>
                  <button onClick={() => setShowMoveToBoard(!showMoveToBoard)}
                    className="w-full px-3 py-1.5 rounded-lg bg-[var(--surface-base)] text-[var(--text-secondary)] text-[11px] font-semibold
                      border border-[var(--border-default)] hover:bg-[var(--surface-hover)] cursor-pointer text-left">
                    📦 {i18n.moveTo}
                  </button>
                  {showMoveToBoard && (
                    <div className="mt-1 p-2 bg-[var(--surface-base)] rounded-lg border border-[var(--border-default)] max-h-[120px] overflow-y-auto space-y-1">
                      {boards.map((b) => (
                        <button key={b.id} onClick={() => onMoveToBoard(b.id)}
                          className="w-full text-left px-2 py-1 rounded text-[10px] text-[var(--text-secondary)]
                            hover:bg-blue-50 hover:text-blue-700 cursor-pointer bg-transparent border-0">
                          {b.board_name} ({b.item_count})
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {permissions.canDelete && (
                <div>
                  {!confirmDelete ? (
                    <button onClick={() => setConfirmDelete(true)}
                      className="w-full px-3 py-1.5 rounded-lg bg-red-50 text-red-600 text-[11px] font-semibold
                        border border-red-200 hover:bg-red-100 cursor-pointer text-left">
                      🗑️ {i18n.archive}
                    </button>
                  ) : (
                    <div className="flex gap-1">
                      <button onClick={onDelete}
                        className="flex-1 px-2 py-1.5 rounded-lg bg-red-600 text-white text-[11px] font-bold
                          cursor-pointer border-0 hover:bg-red-700">Confirmar</button>
                      <button onClick={() => setConfirmDelete(false)}
                        className="flex-1 px-2 py-1.5 rounded-lg bg-[var(--surface-section-cool)] text-[var(--text-secondary)] text-[11px] font-semibold
                          cursor-pointer border border-[var(--border-default)]">{i18n.cancel}</button>
                    </div>
                  )}
                </div>
              )}
            </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
