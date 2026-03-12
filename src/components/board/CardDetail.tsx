import { useState, useEffect, useCallback } from 'react';
import type { Board, BoardItem, BoardI18n, LifecycleEvent, BoardMember, BoardSummary } from '../../types/board';
import { COLUMN_PRESETS } from '../../types/board';
import { getSb } from '../../hooks/useBoard';

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

  const canEdit = permissions.canEditAny || (permissions.canEditOwn && permissions.member?.id === item.assignee_id);

  // Fetch timeline + members on mount
  useEffect(() => {
    (async () => {
      const sb = getSb();
      if (!sb) return;

      const [tl, mb, bl] = await Promise.all([
        sb.rpc('get_card_timeline', { p_item_id: item.id }),
        sb.rpc('get_board_members', { p_board_id: board.id }),
        sb.rpc('list_active_boards'),
      ]);

      if (tl.data) setTimeline(tl.data);
      if (mb.data) setMembers(mb.data);
      if (bl.data) setBoards(bl.data.filter((b: any) => b.id !== board.id));
    })();
  }, [item.id, board.id]);

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
    <div className="fixed inset-0 z-[600] flex items-start justify-center bg-black/40 backdrop-blur-sm p-4 pt-16 overflow-y-auto"
      onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-3xl" onClick={(e) => e.stopPropagation()}>
        {/* Top bar */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100">
          <div className="flex items-center gap-2">
            <span className={`px-2 py-0.5 rounded-md text-[10px] font-bold
              ${COLUMN_PRESETS[item.status]?.badgeBg ?? 'bg-slate-100'} 
              ${COLUMN_PRESETS[item.status]?.badgeText ?? 'text-slate-600'}`}>
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
              className="text-slate-400 hover:text-slate-700 cursor-pointer bg-transparent border-0 text-lg">✕</button>
          </div>
        </div>

        <div className="flex flex-col md:flex-row">
          {/* ── Main content (left) ── */}
          <div className="flex-1 p-6 space-y-5 min-w-0">
            {/* Title */}
            {canEdit ? (
              <input type="text" value={title}
                onChange={(e) => { setTitle(e.target.value); setDirty(true); }}
                className="w-full text-lg font-extrabold text-slate-800 border-0 outline-none bg-transparent
                  focus:bg-slate-50 rounded-lg px-1 -ml-1 transition-colors" />
            ) : (
              <h2 className="text-lg font-extrabold text-slate-800">{title}</h2>
            )}

            {/* Description */}
            <div>
              <label className="text-[11px] font-semibold text-slate-500 mb-1 block">{i18n.description}</label>
              {canEdit ? (
                <textarea value={description}
                  onChange={(e) => { setDescription(e.target.value); setDirty(true); }}
                  rows={4}
                  className="w-full rounded-xl border border-slate-200 px-3 py-2 text-[12px] text-slate-700
                    outline-none focus:border-blue-400 transition-all resize-y"
                  placeholder="Adicionar descrição..." />
              ) : (
                <p className="text-[13px] text-slate-600 whitespace-pre-wrap">{description || 'Sem descrição'}</p>
              )}
            </div>

            {/* Checklist */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-[11px] font-semibold text-slate-500">{i18n.checklist}</label>
                {checkTotal > 0 && (
                  <span className="text-[10px] font-bold text-slate-400">{checkDone}/{checkTotal} ({checkPct}%)</span>
                )}
              </div>
              {checkTotal > 0 && (
                <div className="w-full bg-slate-100 rounded-full h-1.5 mb-3">
                  <div className="bg-emerald-500 h-1.5 rounded-full transition-all" style={{ width: `${checkPct}%` }} />
                </div>
              )}
              <div className="space-y-1.5">
                {checklist.map((ci, idx) => (
                  <div key={idx} className="flex items-center gap-2 group">
                    <input type="checkbox" checked={ci.done}
                      onChange={() => toggleCheck(idx)}
                      disabled={!canEdit}
                      className="w-4 h-4 rounded border-slate-300 cursor-pointer accent-emerald-500" />
                    <span className={`flex-1 text-[12px] ${ci.done ? 'line-through text-slate-400' : 'text-slate-700'}`}>
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
                    className="flex-1 rounded-lg border border-slate-200 px-3 py-1.5 text-[11px]
                      outline-none focus:border-blue-400" />
                  <button onClick={addCheckItem}
                    className="px-3 py-1.5 bg-slate-100 text-slate-600 rounded-lg text-[11px] font-semibold
                      cursor-pointer hover:bg-slate-200 border-0">+ Adicionar</button>
                </div>
              )}
            </div>

            {/* Attachments */}
            {item.attachments && item.attachments.length > 0 && (
              <div>
                <label className="text-[11px] font-semibold text-slate-500 mb-2 block">{i18n.attachments}</label>
                <div className="space-y-1.5">
                  {item.attachments.map((att, idx) => (
                    <a key={idx} href={att.url} target="_blank" rel="noopener noreferrer"
                      className="flex items-center gap-2 px-3 py-2 bg-slate-50 rounded-lg hover:bg-slate-100
                        no-underline transition-colors">
                      <span className="text-[12px]">{att.name?.match(/\.(png|jpg|jpeg|gif|webp)$/i) ? '🖼️' : '📄'}</span>
                      <span className="text-[11px] text-blue-600 truncate">{att.name || att.url}</span>
                    </a>
                  ))}
                </div>
              </div>
            )}

            {/* Timeline */}
            {timeline.length > 0 && (
              <div>
                <label className="text-[11px] font-semibold text-slate-500 mb-2 block">{i18n.timeline}</label>
                <div className="space-y-2 max-h-[200px] overflow-y-auto">
                  {timeline.map((ev) => (
                    <div key={ev.id} className="flex gap-2 text-[11px]">
                      <span className="text-slate-400 whitespace-nowrap">
                        {new Date(ev.created_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                      </span>
                      <span className="text-slate-600">
                        {ev.actor_name && <strong>{ev.actor_name}</strong>}
                        {' '}
                        {ev.action === 'status_change' && `moveu de "${COLUMN_PRESETS[ev.previous_status || '']?.label ?? ev.previous_status}" para "${COLUMN_PRESETS[ev.new_status || '']?.label ?? ev.new_status}"`}
                        {ev.action === 'created' && 'criou este card'}
                        {ev.action === 'assigned' && (ev.reason || 'atribuiu responsável')}
                        {ev.action === 'archived' && 'arquivou este card'}
                        {ev.action === 'moved_out' && 'moveu para outro board'}
                        {ev.action === 'moved_in' && 'recebido de outro board'}
                        {!['status_change', 'created', 'assigned', 'archived', 'moved_out', 'moved_in'].includes(ev.action) && ev.action}
                        {ev.reason && ev.action !== 'assigned' && <span className="text-slate-400 ml-1">— {ev.reason}</span>}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* ── Sidebar (right) ── */}
          <div className="w-full md:w-[240px] p-6 md:border-l border-slate-100 space-y-4">
            {/* Status */}
            <div>
              <label className="text-[10px] font-semibold text-slate-500 mb-1 block uppercase tracking-wide">Status</label>
              <select value={item.status}
                onChange={(e) => onMove(e.target.value)}
                disabled={!permissions.canEditAny}
                className="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-[12px] bg-white
                  outline-none focus:border-blue-400 cursor-pointer">
                {board.columns.map((col: string) => (
                  <option key={col} value={col}>{COLUMN_PRESETS[col]?.label ?? col}</option>
                ))}
              </select>
            </div>

            {/* Assignee */}
            <div>
              <label className="text-[10px] font-semibold text-slate-500 mb-1 block uppercase tracking-wide">{i18n.assignee}</label>
              <select value={assigneeId}
                onChange={(e) => { setAssigneeId(e.target.value); setDirty(true); }}
                disabled={!permissions.canAssign}
                className="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-[12px] bg-white
                  outline-none focus:border-blue-400 cursor-pointer">
                <option value="">{i18n.noAssignee}</option>
                {members.map((m) => <option key={m.id} value={m.id}>{m.full_name}</option>)}
              </select>
            </div>

            {/* Reviewer */}
            <div>
              <label className="text-[10px] font-semibold text-slate-500 mb-1 block uppercase tracking-wide">{i18n.reviewer}</label>
              <select value={reviewerId}
                onChange={(e) => { setReviewerId(e.target.value); setDirty(true); }}
                disabled={!permissions.canAssign}
                className="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-[12px] bg-white
                  outline-none focus:border-blue-400 cursor-pointer">
                <option value="">{i18n.noReviewer}</option>
                {members.map((m) => <option key={m.id} value={m.id}>{m.full_name}</option>)}
              </select>
            </div>

            {/* Tags */}
            <div>
              <label className="text-[10px] font-semibold text-slate-500 mb-1 block uppercase tracking-wide">{i18n.tags}</label>
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
                  className="w-full rounded-lg border border-slate-200 px-2 py-1 text-[11px]
                    outline-none focus:border-blue-400" />
              )}
            </div>

            {/* Due Date */}
            <div>
              <label className="text-[10px] font-semibold text-slate-500 mb-1 block uppercase tracking-wide">{i18n.dueDate}</label>
              <input type="date" value={dueDate}
                onChange={(e) => { setDueDate(e.target.value); setDirty(true); }}
                disabled={!canEdit}
                className="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-[12px] bg-white
                  outline-none focus:border-blue-400" />
            </div>

            {/* Actions */}
            <div className="pt-3 border-t border-slate-100 space-y-2">
              <button onClick={onDuplicate}
                className="w-full px-3 py-1.5 rounded-lg bg-slate-50 text-slate-600 text-[11px] font-semibold
                  border border-slate-200 hover:bg-slate-100 cursor-pointer text-left">
                📋 {i18n.duplicate}
              </button>

              {boards.length > 0 && (
                <div>
                  <button onClick={() => setShowMoveToBoard(!showMoveToBoard)}
                    className="w-full px-3 py-1.5 rounded-lg bg-slate-50 text-slate-600 text-[11px] font-semibold
                      border border-slate-200 hover:bg-slate-100 cursor-pointer text-left">
                    📦 {i18n.moveTo}
                  </button>
                  {showMoveToBoard && (
                    <div className="mt-1 p-2 bg-slate-50 rounded-lg border border-slate-200 max-h-[120px] overflow-y-auto space-y-1">
                      {boards.map((b) => (
                        <button key={b.id} onClick={() => onMoveToBoard(b.id)}
                          className="w-full text-left px-2 py-1 rounded text-[10px] text-slate-600
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
                        className="flex-1 px-2 py-1.5 rounded-lg bg-slate-100 text-slate-600 text-[11px] font-semibold
                          cursor-pointer border border-slate-200">{i18n.cancel}</button>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
