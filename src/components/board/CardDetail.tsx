import { useState, useEffect, useCallback, useRef } from 'react';
import { safeChecklist, safeArray, COLUMN_PRESETS, type Board, type BoardItem, type BoardI18n, type LifecycleEvent, type BoardMember, type BoardSummary, type CurationHistory, type RubricScore, type ItemAssignment, type AssignmentRole } from '../../types/board';
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
  const [checklist, setChecklist] = useState(safeChecklist(item.checklist));
  const [newCheckItem, setNewCheckItem] = useState('');
  const [tags, setTags] = useState(safeArray<string>(item.tags));
  const [tagInput, setTagInput] = useState('');
  const [dueDate, setDueDate] = useState(item.due_date || '');
  const [baselineDate, setBaselineDate] = useState(item.baseline_date || '');
  const [forecastDate, setForecastDate] = useState(item.forecast_date || '');
  const [actualDate] = useState(item.actual_completion_date || '');
  const [timeline, setTimeline] = useState<LifecycleEvent[]>([]);
  const [members, setMembers] = useState<BoardMember[]>([]);
  const [boards, setBoards] = useState<BoardSummary[]>([]);
  const [assigneeId, setAssigneeId] = useState(item.assignee_id || '');
  const [reviewerId, setReviewerId] = useState(item.reviewer_id || '');
  const [dirty, setDirty] = useState(false);
  const [showMoveToBoard, setShowMoveToBoard] = useState(false);
  const [showMirrorDialog, setShowMirrorDialog] = useState(false);
  const [mirrorTargetBoard, setMirrorTargetBoard] = useState('');
  const [mirrorTargetStatus, setMirrorTargetStatus] = useState('backlog');
  const [mirrorNotes, setMirrorNotes] = useState('');
  const [creatingMirror, setCreatingMirror] = useState(false);
  const [mirrorBoards, setMirrorBoards] = useState<BoardSummary[]>([]);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const checklistMigrated = useRef(false);
  const [attachments, setAttachments] = useState(safeArray(item.attachments));
  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [curationHistory, setCurationHistory] = useState<CurationHistory | null>(null);
  const [showReviewForm, setShowReviewForm] = useState(false);
  const [reviewScores, setReviewScores] = useState<Record<string, number>>({ clarity: 3, originality: 3, adherence: 3, relevance: 3, ethics: 3 });
  const [reviewVerdict, setReviewVerdict] = useState<string>('approved');
  const [reviewNotes, setReviewNotes] = useState('');
  const [submittingReview, setSubmittingReview] = useState(false);
  const [itemAssignments, setItemAssignments] = useState<ItemAssignment[]>(safeArray(item.assignments));

  const canEdit = mode !== 'readonly' && (permissions.canEditAny || (permissions.canEditOwn && permissions.member?.id === item.assignee_id));
  const isCurator = permissions.canCurate;
  const isCurationItem = item.curation_status === 'curation_pending';

  // ── Attachment upload ──
  const ALLOWED_TYPES = ['application/pdf', 'image/png', 'image/jpeg', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'];
  const ALLOWED_EXTENSIONS = /\.(pdf|png|jpg|jpeg|docx|xlsx|pptx)$/i;
  const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB

  // EXIF strip: re-draw image via canvas to remove metadata (GPS, camera info)
  const stripExif = useCallback((file: File): Promise<Blob> => {
    return new Promise((resolve) => {
      if (!file.type.startsWith('image/')) { resolve(file); return; }
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement('canvas');
        canvas.width = img.width;
        canvas.height = img.height;
        const ctx = canvas.getContext('2d');
        if (!ctx) { resolve(file); return; }
        ctx.drawImage(img, 0, 0);
        canvas.toBlob(
          (blob) => resolve(blob || file),
          file.type,
          0.9
        );
        URL.revokeObjectURL(img.src);
      };
      img.onerror = () => { resolve(file); };
      img.src = URL.createObjectURL(file);
    });
  }, []);

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

    // MIME type validation
    if (!ALLOWED_TYPES.includes(file.type)) {
      (window as any).toast?.('Tipo MIME não permitido', 'error');
      return;
    }

    setUploading(true);
    try {
      const sb = getSb();
      if (!sb) throw new Error('Supabase indisponível');

      // Strip EXIF from images before upload
      const cleanFile = file.type.startsWith('image/') ? await stripExif(file) : file;

      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
      const storagePath = `${board.id}/${item.id}/${Date.now()}_${safeName}`;

      const { error: uploadError } = await sb.storage
        .from('board-attachments')
        .upload(storagePath, cleanFile, { contentType: file.type, upsert: false });

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

      // Load checklist items from table
      const cl = await safe(sb.from('board_item_checklists')
        .select('id, text, is_completed, position, assigned_to, target_date, completed_at, completed_by, assigned_at')
        .eq('board_item_id', item.id)
        .order('position'));
      if (Array.isArray(cl.data) && cl.data.length > 0) {
        setChecklist(cl.data.map((c: any) => ({
          id: c.id, text: c.text, done: c.is_completed,
          assigned_to: c.assigned_to, target_date: c.target_date,
          completed_at: c.completed_at, completed_by: c.completed_by,
        })));
      } else if (!checklistMigrated.current) {
        // Migrate existing JSON checklist items to the table on first open
        const parsed = safeChecklist(item.checklist);
        if (parsed.length > 0) {
          checklistMigrated.current = true;
          const jsonItems = parsed.filter((c: any) => c.text);
          if (jsonItems.length > 0) {
            const rows = jsonItems.map((c: any, i: number) => ({
              board_item_id: item.id, text: c.text, is_completed: !!c.done, position: i,
            }));
            const { data: inserted } = await sb.from('board_item_checklists')
              .insert(rows).select('id, text, is_completed, position, assigned_to, target_date, completed_at, completed_by');
            if (Array.isArray(inserted)) {
              setChecklist(inserted.map((c: any) => ({
                id: c.id, text: c.text, done: c.is_completed,
                assigned_to: c.assigned_to, target_date: c.target_date,
                completed_at: c.completed_at, completed_by: c.completed_by,
              })));
            }
          }
        }
      }

      // Load mirror target boards
      const mt = await safe(sb.rpc('get_mirror_target_boards', { p_source_board_id: board.id }));
      if (Array.isArray(mt.data)) setMirrorBoards(mt.data);

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
    if (JSON.stringify(tags) !== JSON.stringify(item.tags || [])) fields.tags = tags;
    if (dueDate !== (item.due_date || '')) fields.due_date = dueDate || null;
    if (baselineDate !== (item.baseline_date || '')) fields.baseline_date = baselineDate || null;
    if (forecastDate !== (item.forecast_date || '')) fields.forecast_date = forecastDate || null;
    if (assigneeId !== (item.assignee_id || '')) fields.assignee_id = assigneeId || null;
    if (reviewerId !== (item.reviewer_id || '')) fields.reviewer_id = reviewerId || null;

    if (Object.keys(fields).length > 0) {
      await onUpdate(fields);
      setDirty(false);
    }
  }, [title, description, tags, dueDate, baselineDate, forecastDate, assigneeId, reviewerId, item, onUpdate]);

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

  // ── Checklist helpers (always DB-backed via board_item_checklists table) ──
  const addCheckItem = async () => {
    if (!newCheckItem.trim()) return;
    const sb = getSb();
    if (!sb) return;
    const { data, error } = await sb.from('board_item_checklists')
      .insert({ board_item_id: item.id, text: newCheckItem.trim(), position: checklist.length })
      .select('id, text, is_completed, position, assigned_to, target_date, completed_at, completed_by')
      .single();
    if (!error && data) {
      setChecklist([...checklist, { id: data.id, text: data.text, done: false }]);
    }
    setNewCheckItem('');
  };

  const toggleCheck = async (idx: number) => {
    const ci = checklist[idx];
    if (!ci.id) return;
    const sb = getSb();
    if (!sb) return;
    const newDone = !ci.done;
    await sb.rpc('complete_checklist_item', { p_checklist_item_id: ci.id, p_completed: newDone });
    const updated = [...checklist];
    updated[idx] = { ...updated[idx], done: newDone, completed_at: newDone ? new Date().toISOString() : null };
    setChecklist(updated);
  };

  const removeCheck = async (idx: number) => {
    const ci = checklist[idx];
    if (ci.id) {
      const sb = getSb();
      if (!sb) return;
      await sb.from('board_item_checklists').delete().eq('id', ci.id);
    }
    setChecklist(checklist.filter((_, i) => i !== idx));
  };

  const assignCheckItem = async (checkId: string, memberId: string, targetDate?: string) => {
    const sb = getSb();
    if (!sb) return;
    await sb.rpc('assign_checklist_item', {
      p_checklist_item_id: checkId,
      p_assigned_to: memberId || null,
      p_target_date: targetDate || null,
    });
    setChecklist(checklist.map(c => c.id === checkId ? { ...c, assigned_to: memberId || null, target_date: targetDate || null } : c));
  };

  // ── Mirror card handler ──
  const handleCreateMirror = async () => {
    if (!mirrorTargetBoard) return;
    const sb = getSb();
    if (!sb) return;
    setCreatingMirror(true);
    try {
      const { data, error } = await sb.rpc('create_mirror_card', {
        p_source_item_id: item.id,
        p_target_board_id: mirrorTargetBoard,
        p_target_status: mirrorTargetStatus,
        p_notes: mirrorNotes || null,
      });
      if (error) throw error;
      (window as any).toast?.('Card espelho criado', 'success');
      setShowMirrorDialog(false);
    } catch (err: any) {
      (window as any).toast?.(err.message || 'Erro ao criar espelho', 'error');
    } finally {
      setCreatingMirror(false);
    }
  };

  // ── Tag helpers ──
  const [tagSuggestions, setTagSuggestions] = useState<string[]>([]);
  const [showTagSuggestions, setShowTagSuggestions] = useState(false);

  const boardId = board?.id || item.board_id;
  const loadTagSuggestions = useCallback(async () => {
    if (tagSuggestions.length > 0 || !boardId) return;
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) return;
      const { data } = await sb.rpc('get_board_tags', { p_board_id: boardId });
      if (Array.isArray(data)) setTagSuggestions(data);
    } catch {}
  }, [boardId, tagSuggestions.length]);

  const filteredSuggestions = tagInput.trim()
    ? tagSuggestions.filter(s => s.toLowerCase().includes(tagInput.toLowerCase()) && !tags.includes(s))
    : tagSuggestions.filter(s => !tags.includes(s));

  const addTag = (t: string) => {
    const clean = t.trim();
    if (clean && !tags.includes(clean.toLowerCase())) { setTags([...tags, clean.toLowerCase()]); setDirty(true); }
    setTagInput('');
    setShowTagSuggestions(false);
  };

  const handleClose = useCallback(async () => {
    if (dirty) { try { await handleSave(); } catch {} }
    onClose();
  }, [dirty, handleSave, onClose]);

  const checkDone = checklist.filter((c) => c.done).length;
  const checkTotal = checklist.length;
  const checkPct = checkTotal > 0 ? Math.round((checkDone / checkTotal) * 100) : 0;

  return (
    <div ref={panelRef} tabIndex={-1}
      className="fixed inset-0 z-[600] flex items-start justify-center bg-black/40 backdrop-blur-sm p-4 pt-16 overflow-y-auto outline-none"
      onClick={handleClose} role="dialog" aria-modal="true" aria-label={item.title}>
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
            <button onClick={handleClose}
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
              <div className="space-y-2">
                {checklist.map((ci, idx) => (
                  <div key={ci.id || idx} className="group">
                    <div className="flex items-center gap-2">
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
                    {/* W141: Assignment row for checklist items */}
                    {ci.id && (
                      <div className="ml-6 mt-1 flex items-center gap-2 flex-wrap">
                        {canEdit ? (
                          <select value={ci.assigned_to || ''}
                            onChange={(e) => assignCheckItem(ci.id!, e.target.value, ci.target_date || undefined)}
                            className="rounded border border-[var(--border-default)] px-1.5 py-0.5 text-[10px] bg-[var(--surface-card)] outline-none">
                            <option value="">— Responsável —</option>
                            {members.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                          </select>
                        ) : ci.assigned_to ? (
                          <span className="text-[10px] text-[var(--text-secondary)]">👤 {members.find(m => m.id === ci.assigned_to)?.name || 'Membro'}</span>
                        ) : null}
                        {canEdit ? (
                          <input type="date" value={ci.target_date || ''}
                            onChange={(e) => assignCheckItem(ci.id!, ci.assigned_to || '', e.target.value || undefined)}
                            className="rounded border border-[var(--border-default)] px-1.5 py-0.5 text-[10px] bg-[var(--surface-card)] outline-none" />
                        ) : ci.target_date ? (
                          <span className="text-[10px] text-[var(--text-muted)]">📅 {ci.target_date}</span>
                        ) : null}
                        {ci.done && ci.completed_at && (
                          <span className="text-[10px] text-emerald-600">✅ {new Date(ci.completed_at).toLocaleDateString('pt-BR')}</span>
                        )}
                      </div>
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
                        {ev.action === 'forecast_update' && `alterou forecast: ${ev.previous_status || '—'} → ${ev.new_status || '—'}`}
                        {ev.action === 'actual_completion' && `conclusão real: ${ev.new_status || '—'}`}
                        {ev.action === 'mirror_created' && 'criou card espelho'}
                        {!['status_change', 'created', 'assigned', 'archived', 'moved_out', 'moved_in', 'submitted_for_curation', 'reviewer_assigned', 'curation_review', 'curation_approved', 'forecast_update', 'actual_completion', 'mirror_created'].includes(ev.action) && ev.action}
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
                <div className="relative">
                  <input type="text" value={tagInput}
                    onChange={(e) => { setTagInput(e.target.value); setShowTagSuggestions(true); }}
                    onFocus={() => { loadTagSuggestions(); setShowTagSuggestions(true); }}
                    onBlur={() => setTimeout(() => setShowTagSuggestions(false), 200)}
                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); addTag(tagInput); } if (e.key === 'Escape') setShowTagSuggestions(false); }}
                    placeholder="Tag + Enter"
                    className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[11px] outline-none focus:border-blue-400 bg-[var(--surface-base)] text-[var(--text-primary)]" />
                  {showTagSuggestions && filteredSuggestions.length > 0 && (
                    <div className="absolute z-50 top-full left-0 right-0 mt-0.5 bg-[var(--surface-elevated)] border border-[var(--border-default)] rounded-lg shadow-lg max-h-[120px] overflow-y-auto">
                      {filteredSuggestions.slice(0, 8).map(s => (
                        <button key={s} onMouseDown={() => addTag(s)}
                          className="w-full text-left px-2 py-1 text-[11px] text-[var(--text-primary)] hover:bg-[var(--surface-hover)] cursor-pointer border-0 bg-transparent">
                          {s}
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* PMBOK Dates */}
            <div>
              <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">Datas</label>
              <div className="space-y-2">
                <div>
                  <span className="text-[9px] text-[var(--text-muted)] block mb-0.5">Baseline (pactuada)</span>
                  <input type="date" value={baselineDate}
                    onChange={(e) => { setBaselineDate(e.target.value); if (!forecastDate) setForecastDate(e.target.value); setDirty(true); }}
                    disabled={!canEdit || (!!item.baseline_date && !permissions.canEditAny)}
                    className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[11px] bg-[var(--surface-card)]
                      outline-none focus:border-blue-400 disabled:opacity-60" />
                </div>
                <div>
                  <span className="text-[9px] text-[var(--text-muted)] block mb-0.5">Forecast (previsão)</span>
                  <input type="date" value={forecastDate}
                    onChange={(e) => { setForecastDate(e.target.value); setDirty(true); }}
                    disabled={!canEdit}
                    className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[11px] bg-[var(--surface-card)]
                      outline-none focus:border-blue-400" />
                </div>
                {actualDate && (
                  <div>
                    <span className="text-[9px] text-[var(--text-muted)] block mb-0.5">Actual (conclusão)</span>
                    <span className="text-[11px] text-emerald-600 font-bold">✅ {actualDate}</span>
                  </div>
                )}
                {/* Variance indicator */}
                {baselineDate && forecastDate && (
                  (() => {
                    const diff = Math.round((new Date(forecastDate).getTime() - new Date(baselineDate).getTime()) / 86400000);
                    const color = diff <= 0 ? 'text-emerald-600' : diff <= 7 ? 'text-amber-600' : 'text-red-600';
                    const icon = diff <= 0 ? '✅' : diff <= 7 ? '⚠️' : '🔴';
                    const label = diff === 0 ? 'No prazo' : diff < 0 ? `${Math.abs(diff)}d adiantado` : `${diff}d atraso`;
                    return <span className={`text-[10px] font-bold ${color}`}>{icon} Desvio: {label}</span>;
                  })()
                )}
              </div>
            </div>

            {/* Legacy Due Date (hidden if PMBOK dates exist) */}
            {!baselineDate && !forecastDate && (
            <div>
              <label className="text-[10px] font-semibold text-[var(--text-secondary)] mb-1 block uppercase tracking-wide">{i18n.dueDate}</label>
              <input type="date" value={dueDate}
                onChange={(e) => { setDueDate(e.target.value); setDirty(true); }}
                disabled={!canEdit}
                className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1.5 text-[12px] bg-[var(--surface-card)]
                  outline-none focus:border-blue-400" />
            </div>
            )}

            {/* Mirror Card Info */}
            {item.is_mirror && item.mirror_source_id && (
              <div className="bg-blue-50 rounded-lg p-2.5 border border-blue-200">
                <span className="text-[10px] font-bold text-blue-700 block mb-1">🔗 Card Espelho</span>
                <a href={`/admin/board/${item.board_id}?card=${item.mirror_source_id}`}
                  className="text-[10px] text-blue-600 hover:underline no-underline">Ver card original →</a>
              </div>
            )}
            {item.mirror_target_id && (
              <div className="bg-teal-50 rounded-lg p-2.5 border border-teal-200">
                <span className="text-[10px] font-bold text-teal-700 block mb-1">🔗 Espelhado</span>
                <span className="text-[10px] text-teal-600">Card enviado para outro board</span>
              </div>
            )}

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

              {/* Mirror card button */}
              {mirrorBoards.length > 0 && (
                <div>
                  <button onClick={() => setShowMirrorDialog(!showMirrorDialog)}
                    className="w-full px-3 py-1.5 rounded-lg bg-blue-50 text-blue-700 text-[11px] font-semibold
                      border border-blue-200 hover:bg-blue-100 cursor-pointer text-left">
                    🔗 Criar Espelho
                  </button>
                  {showMirrorDialog && (
                    <div className="mt-1 p-3 bg-[var(--surface-base)] rounded-lg border border-blue-200 space-y-2">
                      <label className="text-[10px] font-semibold text-[var(--text-secondary)] block">Board destino</label>
                      <select value={mirrorTargetBoard}
                        onChange={(e) => setMirrorTargetBoard(e.target.value)}
                        className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[11px] bg-[var(--surface-card)] outline-none">
                        <option value="">Selecionar...</option>
                        {mirrorBoards.map((b: any) => (
                          <option key={b.board_id} value={b.board_id}>{b.board_name} ({b.item_count})</option>
                        ))}
                      </select>
                      <label className="text-[10px] font-semibold text-[var(--text-secondary)] block">Status inicial</label>
                      <select value={mirrorTargetStatus}
                        onChange={(e) => setMirrorTargetStatus(e.target.value)}
                        className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[11px] bg-[var(--surface-card)] outline-none">
                        {board.columns.map((col: string) => (
                          <option key={col} value={col}>{COLUMN_PRESETS[col]?.label ?? col}</option>
                        ))}
                      </select>
                      <textarea value={mirrorNotes}
                        onChange={(e) => setMirrorNotes(e.target.value)}
                        rows={2} placeholder="Notas para o time de destino..."
                        className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[10px] outline-none resize-y" />
                      <div className="flex gap-1">
                        <button onClick={handleCreateMirror} disabled={!mirrorTargetBoard || creatingMirror}
                          className="flex-1 px-2 py-1 bg-blue-600 text-white rounded-lg text-[10px] font-bold
                            cursor-pointer border-0 hover:bg-blue-700 disabled:opacity-50">
                          {creatingMirror ? 'Criando...' : 'Criar Espelho'}
                        </button>
                        <button onClick={() => setShowMirrorDialog(false)}
                          className="px-2 py-1 bg-[var(--surface-section-cool)] text-[var(--text-secondary)] rounded-lg text-[10px]
                            cursor-pointer border border-[var(--border-default)]">{i18n.cancel}</button>
                      </div>
                    </div>
                  )}
                </div>
              )}

              {permissions.canEditAny && item.status !== 'archived' && (
                <button onClick={() => onMove('archived')}
                  className="w-full px-3 py-1.5 rounded-lg bg-amber-50 text-amber-700 text-[11px] font-semibold
                    border border-amber-200 hover:bg-amber-100 cursor-pointer text-left">
                  📦 {i18n.archive || 'Arquivar'}
                </button>
              )}
              {permissions.canDelete && (
                <div>
                  {!confirmDelete ? (
                    <button onClick={() => setConfirmDelete(true)}
                      className="w-full px-3 py-1.5 rounded-lg bg-red-50 text-red-600 text-[11px] font-semibold
                        border border-red-200 hover:bg-red-100 cursor-pointer text-left">
                      🗑️ Excluir
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

      {/* Fixed save bar — always visible when dirty */}
      {dirty && canEdit && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-[650] px-6 py-3 bg-[var(--surface-elevated)] border border-[var(--border-default)] rounded-xl shadow-2xl flex items-center gap-4">
          <span className="text-xs text-amber-600 font-semibold">⚠️ Alterações não salvas</span>
          <button onClick={handleSave}
            className="px-5 py-2 bg-blue-600 text-white rounded-lg text-sm font-bold cursor-pointer hover:bg-blue-700 border-0 transition-colors">
            💾 {i18n.save || 'Salvar'}
          </button>
        </div>
      )}
    </div>
  );
}
