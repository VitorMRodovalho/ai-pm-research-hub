import { useState, useEffect, useCallback } from 'react';
import { getSb } from '../../hooks/useBoard';

interface Comment {
  id: string;
  board_item_id: string;
  parent_comment_id?: string | null;
  body: string;
  author_id: string;
  author_name?: string;
  author_photo_url?: string | null;
  mentioned_member_ids?: string[];
  created_at: string;
  updated_at?: string;
  deleted_at?: string | null;
}

interface MemberOption {
  id: string;
  name: string;
}

interface Props {
  boardItemId: string;
  currentMemberId?: string | null;
  currentMemberIsAdmin?: boolean;
  members: MemberOption[];
}

function formatRelative(iso: string): string {
  const ts = new Date(iso).getTime();
  const diffSec = Math.floor((Date.now() - ts) / 1000);
  if (diffSec < 60) return 'agora';
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}min`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h`;
  if (diffSec < 86400 * 7) return `${Math.floor(diffSec / 86400)}d`;
  return new Date(iso).toLocaleDateString('pt-BR');
}

function parseMentions(body: string, members: MemberOption[]): string[] {
  const ids = new Set<string>();
  const re = /@([a-zA-ZÀ-ſ][\wÀ-ſ\s]*)/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(body)) !== null) {
    const fragment = match[1].trim().toLowerCase();
    const m = members.find((x) =>
      x.name.toLowerCase().startsWith(fragment) ||
      fragment.startsWith(x.name.toLowerCase().split(' ')[0]),
    );
    if (m) ids.add(m.id);
  }
  return Array.from(ids);
}

export default function CardComments({ boardItemId, currentMemberId, currentMemberIsAdmin, members }: Props) {
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [body, setBody] = useState('');
  const [posting, setPosting] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingBody, setEditingBody] = useState('');
  const [replyToId, setReplyToId] = useState<string | null>(null);
  const [replyBody, setReplyBody] = useState('');

  const refresh = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setLoading(false); return; }
    const { data } = await sb.rpc('list_card_comments', { p_board_item_id: boardItemId });
    const arr = data?.comments ?? [];
    setComments(Array.isArray(arr) ? arr : []);
    setLoading(false);
  }, [boardItemId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const post = useCallback(async (text: string, parent: string | null) => {
    if (!text.trim()) return;
    setPosting(true);
    const sb = getSb();
    if (!sb) return;
    try {
      const mentioned = parseMentions(text, members);
      await sb.rpc('create_card_comment', {
        p_board_item_id: boardItemId,
        p_body: text.trim(),
        p_parent_comment_id: parent,
        p_mentioned_member_ids: mentioned,
      });
      await refresh();
      if (parent) {
        setReplyToId(null);
        setReplyBody('');
      } else {
        setBody('');
      }
    } finally {
      setPosting(false);
    }
  }, [boardItemId, members, refresh]);

  const saveEdit = useCallback(async (id: string) => {
    if (!editingBody.trim()) return;
    const sb = getSb();
    if (!sb) return;
    await sb.rpc('update_card_comment', { p_comment_id: id, p_new_body: editingBody.trim() });
    setEditingId(null);
    setEditingBody('');
    await refresh();
  }, [editingBody, refresh]);

  const remove = useCallback(async (id: string) => {
    if (!confirm('Excluir este comentário?')) return;
    const sb = getSb();
    if (!sb) return;
    await sb.rpc('delete_card_comment', { p_comment_id: id });
    await refresh();
  }, [refresh]);

  const topLevel = comments.filter((c) => !c.parent_comment_id);
  const repliesByParent = comments.reduce<Record<string, Comment[]>>((acc, c) => {
    if (c.parent_comment_id) {
      acc[c.parent_comment_id] = acc[c.parent_comment_id] || [];
      acc[c.parent_comment_id].push(c);
    }
    return acc;
  }, {});

  const canEdit = (c: Comment) => currentMemberId && (c.author_id === currentMemberId || currentMemberIsAdmin);

  const renderComment = (c: Comment, isReply = false) => (
    <div key={c.id} className={`group ${isReply ? 'ml-6' : ''}`}>
      <div className="flex items-start gap-2 py-1.5">
        {c.author_photo_url ? (
          <img src={c.author_photo_url} alt="" className="w-6 h-6 rounded-full object-cover flex-shrink-0" />
        ) : (
          <span className="w-6 h-6 rounded-full bg-navy/10 flex items-center justify-center text-[10px] font-bold text-navy flex-shrink-0">
            {(c.author_name ?? '?').charAt(0).toUpperCase()}
          </span>
        )}
        <div className="flex-1 min-w-0">
          <div className="flex items-baseline gap-2 mb-0.5">
            <span className="text-[11px] font-semibold text-[var(--text-primary)]">{c.author_name || 'Membro'}</span>
            <span className="text-[10px] text-[var(--text-muted)]">{formatRelative(c.created_at)}</span>
            {c.updated_at && c.updated_at !== c.created_at && (
              <span className="text-[10px] text-[var(--text-muted)] italic">(editado)</span>
            )}
          </div>
          {editingId === c.id ? (
            <div className="space-y-1">
              <textarea
                value={editingBody}
                onChange={(e) => setEditingBody(e.target.value)}
                className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[12px] outline-none focus:border-blue-400"
                rows={3}
              />
              <div className="flex gap-2">
                <button
                  onClick={() => saveEdit(c.id)}
                  className="px-2 py-0.5 text-[10px] bg-emerald-500 text-white rounded font-semibold cursor-pointer border-0"
                >Salvar</button>
                <button
                  onClick={() => { setEditingId(null); setEditingBody(''); }}
                  className="px-2 py-0.5 text-[10px] bg-transparent text-[var(--text-muted)] cursor-pointer border-0"
                >Cancelar</button>
              </div>
            </div>
          ) : (
            <div className="text-[12px] text-[var(--text-primary)] whitespace-pre-wrap break-words">{c.body}</div>
          )}
          {editingId !== c.id && (
            <div className="flex items-center gap-2 mt-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
              {!isReply && currentMemberId && (
                <button
                  onClick={() => { setReplyToId(replyToId === c.id ? null : c.id); setReplyBody(''); }}
                  className="text-[10px] text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer bg-transparent border-0"
                >Responder</button>
              )}
              {canEdit(c) && (
                <>
                  <button
                    onClick={() => { setEditingId(c.id); setEditingBody(c.body); }}
                    className="text-[10px] text-[var(--text-muted)] hover:text-blue-500 cursor-pointer bg-transparent border-0"
                  >Editar</button>
                  <button
                    onClick={() => remove(c.id)}
                    className="text-[10px] text-[var(--text-muted)] hover:text-red-500 cursor-pointer bg-transparent border-0"
                  >Excluir</button>
                </>
              )}
            </div>
          )}
        </div>
      </div>
      {!isReply && repliesByParent[c.id]?.map((r) => renderComment(r, true))}
      {!isReply && replyToId === c.id && (
        <div className="ml-6 mt-1 mb-2 space-y-1">
          <textarea
            value={replyBody}
            onChange={(e) => setReplyBody(e.target.value)}
            placeholder="Responder... (use @nome para mencionar)"
            className="w-full rounded-lg border border-[var(--border-default)] px-2 py-1 text-[11px] outline-none focus:border-blue-400"
            rows={2}
            autoFocus
          />
          <div className="flex gap-2">
            <button
              disabled={posting || !replyBody.trim()}
              onClick={() => post(replyBody, c.id)}
              className="px-2 py-0.5 text-[10px] bg-emerald-500 text-white rounded font-semibold cursor-pointer disabled:opacity-50 border-0"
            >Postar</button>
            <button
              onClick={() => { setReplyToId(null); setReplyBody(''); }}
              className="px-2 py-0.5 text-[10px] bg-transparent text-[var(--text-muted)] cursor-pointer border-0"
            >Cancelar</button>
          </div>
        </div>
      )}
    </div>
  );

  return (
    <div>
      <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-2 block">
        💬 Comentários {comments.length > 0 && `(${comments.length})`}
      </label>
      {loading ? (
        <div className="text-[11px] text-[var(--text-muted)]">Carregando...</div>
      ) : (
        <>
          <div className="space-y-1 mb-3">
            {topLevel.length === 0 ? (
              <div className="text-[11px] text-[var(--text-muted)] italic py-2">Nenhum comentário ainda. Seja o primeiro a comentar.</div>
            ) : (
              topLevel.map((c) => renderComment(c))
            )}
          </div>
          {currentMemberId && (
            <div className="space-y-1 pt-2 border-t border-[var(--border-subtle)]">
              <textarea
                value={body}
                onChange={(e) => setBody(e.target.value)}
                placeholder="Adicionar comentário... (use @nome para mencionar membros)"
                className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-[12px] outline-none focus:border-blue-400"
                rows={3}
              />
              <button
                disabled={posting || !body.trim()}
                onClick={() => post(body, null)}
                className="px-3 py-1 bg-emerald-500 text-white rounded-lg text-[11px] font-semibold cursor-pointer disabled:opacity-50 border-0"
              >Comentar</button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
