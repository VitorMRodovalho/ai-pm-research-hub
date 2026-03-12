import { useState, useEffect, useRef } from 'react';
import type { BoardI18n, BoardMember } from '../../types/board';
import { COLUMN_PRESETS } from '../../types/board';
import { getSb } from '../../hooks/useBoard';
import MemberPicker from './MemberPicker';

interface Props {
  boardId: string;
  columns: string[];
  i18n: BoardI18n;
  onClose: () => void;
  onCreate: (fields: {
    title: string; description?: string; assignee_id?: string;
    tags?: string[]; due_date?: string; status?: string;
  }) => Promise<void>;
}

export default function CardCreate({ boardId, columns, i18n, onClose, onCreate }: Props) {
  const overlayRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [onClose]);

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [assigneeId, setAssigneeId] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [tagInput, setTagInput] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [status, setStatus] = useState(columns[0] || 'backlog');
  const [members, setMembers] = useState<BoardMember[]>([]);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    (async () => {
      const sb = getSb();
      if (!sb) return;
      try {
        const { data } = await sb.rpc('get_board_members', { p_board_id: boardId });
        if (Array.isArray(data)) setMembers(data);
      } catch { /* RPC may not exist yet — MemberPicker shows empty */ }
    })();
  }, [boardId]);

  const handleSubmit = async () => {
    if (!title.trim()) return;
    setSubmitting(true);
    await onCreate({
      title: title.trim(),
      description: description.trim() || undefined,
      assignee_id: assigneeId || undefined,
      tags: tags.length > 0 ? tags : undefined,
      due_date: dueDate || undefined,
      status,
    });
    setSubmitting(false);
  };

  const addTag = (t: string) => {
    const clean = t.trim().toLowerCase();
    if (clean && !tags.includes(clean)) setTags([...tags, clean]);
    setTagInput('');
  };

  return (
    <div ref={overlayRef} tabIndex={-1}
      className="fixed inset-0 z-[600] flex items-center justify-center bg-black/40 backdrop-blur-sm p-4 outline-none"
      onClick={onClose} role="dialog" aria-modal="true" aria-label={i18n.newCard || 'Novo Card'}>
      <div className="bg-[var(--surface-elevated)] rounded-2xl p-6 max-w-md w-full shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-5">
          <h3 className="text-base font-extrabold text-[var(--text-primary)]">➕ {i18n.newCard}</h3>
          <button onClick={onClose}
            className="text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer bg-transparent border-0 text-lg">✕</button>
        </div>

        <div className="space-y-4">
          {/* Title */}
          <div>
            <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1 block">Título *</label>
            <input type="text" value={title} onChange={(e) => setTitle(e.target.value)}
              autoFocus placeholder="Nome do card..."
              className="w-full rounded-xl border-2 border-[var(--border-default)] px-3 py-2.5 text-sm
                outline-none focus:border-blue-400 transition-all" />
          </div>

          {/* Description */}
          <div>
            <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1 block">{i18n.description}</label>
            <textarea value={description} onChange={(e) => setDescription(e.target.value)}
              rows={3} placeholder="Descrição opcional..."
              className="w-full rounded-xl border border-[var(--border-default)] px-3 py-2 text-[12px]
                outline-none focus:border-blue-400 resize-y" />
          </div>

          {/* Two-column row */}
          <div className="grid grid-cols-2 gap-3">
            {/* Assignee */}
            <div>
              <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1 block">{i18n.assignee}</label>
              <MemberPicker
                members={members}
                value={assigneeId}
                onChange={setAssigneeId}
                placeholder={i18n.noAssignee}
              />
            </div>

            {/* Status (which column) */}
            <div>
              <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1 block">Coluna</label>
              <select value={status} onChange={(e) => setStatus(e.target.value)}
                className="w-full rounded-xl border border-[var(--border-default)] px-2 py-2 text-[12px] bg-[var(--surface-card)]
                  outline-none focus:border-blue-400 cursor-pointer">
                {columns.map((col) => (
                  <option key={col} value={col}>{COLUMN_PRESETS[col]?.label ?? col}</option>
                ))}
              </select>
            </div>
          </div>

          {/* Due date */}
          <div>
            <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1 block">{i18n.dueDate}</label>
            <input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)}
              className="w-full rounded-xl border border-[var(--border-default)] px-3 py-2 text-[12px] bg-[var(--surface-card)]
                outline-none focus:border-blue-400" />
          </div>

          {/* Tags */}
          <div>
            <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-1 block">{i18n.tags}</label>
            <div className="flex flex-wrap gap-1 mb-1.5 min-h-[24px]">
              {tags.map((t) => (
                <span key={t} className="inline-flex items-center gap-0.5 px-2 py-0.5 bg-blue-50 text-blue-700 rounded-lg text-[10px] font-semibold">
                  {t}
                  <button onClick={() => setTags(tags.filter((x) => x !== t))}
                    className="text-blue-400 hover:text-red-500 cursor-pointer bg-transparent border-0 text-[9px]">✕</button>
                </span>
              ))}
            </div>
            <input type="text" value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); addTag(tagInput); } }}
              placeholder="Tag + Enter"
              className="w-full rounded-xl border border-[var(--border-default)] px-3 py-1.5 text-[11px]
                outline-none focus:border-blue-400" />
          </div>
        </div>

        {/* Submit */}
        <button onClick={handleSubmit} disabled={!title.trim() || submitting}
          className={`w-full mt-5 px-4 py-3 rounded-xl text-sm font-bold cursor-pointer border-0 transition-all
            ${title.trim() && !submitting
              ? 'bg-blue-900 text-white hover:bg-blue-800'
              : 'bg-[var(--surface-hover)] text-[var(--text-muted)] cursor-not-allowed'}`}>
          {submitting ? '⏳ Criando...' : `✅ Criar Card`}
        </button>
      </div>
    </div>
  );
}
