import { useEffect, useState, useCallback, useMemo } from 'react';

type Comment = {
  id: string;
  clause_anchor: string | null;
  body: string;
  visibility: 'curator_only' | 'submitter_only' | 'change_notes' | 'public';
  parent_id: string | null;
  author_id: string;
  author_name: string;
  author_role: string;
  created_at: string;
  resolved_at: string | null;
  resolved_by_name: string | null;
  resolution_note: string | null;
  // p93b: inheritance fields — set when comment was made on a prior version
  from_version_id: string | null;
  from_version_label: string | null;
  is_inherited: boolean;
};

type Props = {
  versionId: string;
  chainId: string;
  canComment: boolean;
  isSubmitter: boolean;
  isCurator: boolean;
  chainStatus: string;
  documentHtml?: string;
  locale?: string;
};

type Anchor = { value: string; label: string };

// Matches: "§ 3", "§ 4.5.1", "1.", "2.3", "2.3.4", "Art. 5", "Cláusula 2"
const CLAUSE_REGEX = /^\s*(§\s*[\d]+(?:\.\d+)*[a-z]?|\d+(?:\.\d+)+|\d+\.(?!\d)|Art\.?\s*\d+|Cláusula\s*[\d.]+)/i;

function extractAnchors(html: string): Anchor[] {
  if (!html || typeof DOMParser === 'undefined') return [];
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const anchors = new Map<string, string>();

  doc.querySelectorAll('h2, h3').forEach(el => {
    const text = (el.textContent || '').trim();
    if (!text) return;
    const m = text.match(CLAUSE_REGEX);
    const value = (m ? m[1].replace(/\s+/g, ' ') : text).replace(/\.$/, '').trim();
    if (value && !anchors.has(value)) anchors.set(value, text);
  });

  // Strong-tag fallback: only include entries that match clause numbering
  doc.querySelectorAll('strong').forEach(el => {
    const text = (el.textContent || '').trim();
    const m = text.match(CLAUSE_REGEX);
    if (!m) return;
    const value = m[1].replace(/\s+/g, ' ').replace(/\.$/, '').trim();
    if (value && !anchors.has(value)) anchors.set(value, text);
  });

  return Array.from(anchors.entries()).map(([value, label]) => ({ value, label }));
}

function fmt(d: string): string {
  return new Date(d).toLocaleString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
}

function visibilityLabel(v: Comment['visibility']): string {
  return v === 'curator_only' ? 'Só curadores/GP' : v === 'submitter_only' ? 'Só GP' : v === 'change_notes' ? 'Notas de alteração' : 'Público';
}

function visibilityCls(v: Comment['visibility']): string {
  return v === 'curator_only' ? 'bg-purple-100 text-purple-800 border-purple-300'
    : v === 'submitter_only' ? 'bg-slate-100 text-slate-800 border-slate-300'
    : v === 'change_notes' ? 'bg-amber-100 text-amber-800 border-amber-300'
    : 'bg-gray-100 text-gray-700 border-gray-300';
}

export default function ClauseCommentDrawer({ versionId, chainId, canComment, isSubmitter, isCurator, chainStatus, documentHtml }: Props) {
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [includeResolved, setIncludeResolved] = useState(false);
  const [draftBody, setDraftBody] = useState('');
  const [draftAnchorSel, setDraftAnchorSel] = useState('');
  const [draftAnchorCustom, setDraftAnchorCustom] = useState('');
  const [draftVisibility, setDraftVisibility] = useState<Comment['visibility']>('curator_only');
  const [submitting, setSubmitting] = useState(false);

  const anchors = useMemo(() => extractAnchors(documentHtml || ''), [documentHtml]);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const { data, error } = await sb.rpc('list_document_comments', {
      p_version_id: versionId,
      p_include_resolved: includeResolved,
      p_include_prior_versions: true,
    });
    if (!error && Array.isArray(data)) setComments(data);
    setLoading(false);
  }, [getSb, versionId, includeResolved]);

  useEffect(() => { load(); }, [load]);

  // If anchors were parsed (select shown), honor the select value; '__custom__' → use custom input.
  // If no anchors (fallback input only), use custom directly.
  const resolvedAnchor = anchors.length === 0
    ? draftAnchorCustom.trim()
    : draftAnchorSel === '__custom__' ? draftAnchorCustom.trim() : draftAnchorSel;

  async function submitComment() {
    if (!draftBody.trim()) return;
    const sb = getSb();
    if (!sb) return;
    setSubmitting(true);
    const rpcName = draftVisibility === 'change_notes' ? 'create_change_note' : 'create_document_comment';
    const payload = draftVisibility === 'change_notes'
      ? { p_chain_id: chainId, p_body: draftBody }
      : {
          p_version_id: versionId,
          p_clause_anchor: resolvedAnchor || null,
          p_body: draftBody,
          p_visibility: draftVisibility,
          p_parent_id: null,
        };
    const { data, error } = await sb.rpc(rpcName, payload);
    setSubmitting(false);
    if (error || data?.error) {
      (window as any).toast?.(error?.message || data?.error || 'Erro ao salvar comentário', 'error');
      return;
    }
    setDraftBody(''); setDraftAnchorSel(''); setDraftAnchorCustom('');
    (window as any).toast?.('Comentário registrado', 'success');
    load();
  }

  async function resolve(commentId: string) {
    const note = window.prompt('Nota de resolução (opcional):');
    if (note === null) return;
    const sb = getSb();
    if (!sb) return;
    const { data, error } = await sb.rpc('resolve_document_comment', {
      p_comment_id: commentId,
      p_resolution_note: note || null,
    });
    if (error || data?.error) {
      (window as any).toast?.(error?.message || data?.error || 'Erro', 'error');
      return;
    }
    (window as any).toast?.('Comentário resolvido', 'success');
    load();
  }

  const openCount = comments.filter(c => !c.resolved_at).length;
  const inheritedOpenCount = comments.filter(c => !c.resolved_at && c.is_inherited).length;
  const changeNotes = comments.filter(c => c.visibility === 'change_notes');
  const reviewComments = comments.filter(c => c.visibility !== 'change_notes');

  // Count open comments per anchor for the select badge hint
  const anchorCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const c of reviewComments) {
      if (c.resolved_at) continue;
      const k = c.clause_anchor || '';
      counts[k] = (counts[k] || 0) + 1;
    }
    return counts;
  }, [reviewComments]);

  // Group review comments by clause_anchor
  const grouped = reviewComments.reduce<Record<string, Comment[]>>((acc, c) => {
    const k = c.clause_anchor || '(geral)';
    if (!acc[k]) acc[k] = [];
    acc[k].push(c);
    return acc;
  }, {});
  const groupKeys = Object.keys(grouped).sort();

  return (
    <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden flex flex-col h-full">
      <header className="px-4 py-3 border-b border-[var(--border-default)] bg-[var(--surface-hover)]">
        <div className="flex items-center justify-between flex-wrap gap-1">
          <h3 className="text-sm font-bold text-[var(--text-primary)]">Comentários</h3>
          <div className="flex items-center gap-1.5 flex-wrap">
            {openCount > 0 && <span className="inline-block rounded-full bg-amber-100 border border-amber-300 px-2 py-0.5 text-[10px] font-bold text-amber-900">{openCount} abertos</span>}
            {inheritedOpenCount > 0 && <span className="inline-block rounded-full bg-orange-50 border border-orange-300 px-2 py-0.5 text-[10px] font-semibold text-orange-800" title="Comentários de versões anteriores (ainda abertos)">↩ {inheritedOpenCount} herdados</span>}
          </div>
        </div>
        <label className="flex items-center gap-2 text-[11px] mt-2 cursor-pointer">
          <input type="checkbox" checked={includeResolved} onChange={e => setIncludeResolved(e.target.checked)} className="w-3.5 h-3.5 accent-navy" />
          Mostrar resolvidos
        </label>
      </header>

      <div className="flex-1 overflow-y-auto px-3 py-3 space-y-3">
        {loading && <p className="text-[12px] text-[var(--text-muted)] italic text-center py-4">Carregando…</p>}
        {!loading && comments.length === 0 && <p className="text-[12px] text-[var(--text-muted)] italic text-center py-4">Nenhum comentário ainda.</p>}

        {changeNotes.length > 0 && (
          <div className="rounded-lg border border-amber-200 bg-amber-50 p-2">
            <h4 className="text-[11px] font-bold uppercase tracking-wide text-amber-900 mb-2">Notas de alteração</h4>
            <ul className="space-y-2">
              {changeNotes.map(c => (
                <li key={c.id} className="text-[12px]">
                  <div className="flex items-center gap-2 text-[10px] text-amber-800">
                    <strong>{c.author_name}</strong> · {fmt(c.created_at)}
                  </div>
                  <p className="text-amber-950 mt-1 whitespace-pre-wrap">{c.body}</p>
                </li>
              ))}
            </ul>
          </div>
        )}

        {groupKeys.map(key => (
          <section key={key} className="rounded-lg border border-[var(--border-default)] bg-white">
            <header className="px-2 py-1.5 border-b border-[var(--border-default)] bg-[var(--surface-hover)] text-[10px] font-semibold uppercase tracking-wide text-[var(--text-secondary)]">
              § {key}
            </header>
            <ul className="divide-y divide-[var(--border-subtle)]">
              {grouped[key].map(c => (
                <li key={c.id} className={`px-2 py-2 ${c.resolved_at ? 'opacity-60' : ''} ${c.is_inherited ? 'border-l-2 border-orange-300 bg-orange-50/40' : ''}`}>
                  <div className="flex items-center gap-2 flex-wrap">
                    <strong className="text-[11px] text-[var(--text-primary)]">{c.author_name}</strong>
                    <span className={`inline-block rounded-full border px-1.5 py-0 text-[9px] font-semibold ${visibilityCls(c.visibility)}`}>{visibilityLabel(c.visibility)}</span>
                    {c.is_inherited && c.from_version_label && (
                      <span className="inline-block rounded-full border border-orange-300 bg-orange-100 px-1.5 py-0 text-[9px] font-semibold text-orange-900" title="Comentário herdado de versão anterior">
                        ↩ {c.from_version_label}
                      </span>
                    )}
                    <span className="text-[10px] text-[var(--text-muted)]">{fmt(c.created_at)}</span>
                  </div>
                  <p className="text-[12px] text-[var(--text-primary)] mt-1 whitespace-pre-wrap">{c.body}</p>
                  {c.resolved_at ? (
                    <div className="mt-1.5 text-[10px] text-emerald-700">
                      ✓ Resolvido por {c.resolved_by_name} em {fmt(c.resolved_at)}
                      {c.resolution_note && <div className="text-emerald-800 italic mt-0.5">"{c.resolution_note}"</div>}
                    </div>
                  ) : (isCurator || isSubmitter) && (
                    <button type="button" onClick={() => resolve(c.id)}
                      className="mt-1.5 text-[10px] rounded border border-emerald-300 bg-white px-2 py-0.5 cursor-pointer text-emerald-700 font-semibold hover:bg-emerald-50">
                      Marcar resolvido
                    </button>
                  )}
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>

      {canComment && (
        <footer className="border-t border-[var(--border-default)] bg-[var(--surface-hover)] p-3 space-y-2">
          {isCurator && draftVisibility !== 'change_notes' && (
            anchors.length > 0 ? (
              <div className="space-y-1.5">
                <select
                  value={draftAnchorSel}
                  onChange={e => setDraftAnchorSel(e.target.value)}
                  className="w-full text-[12px] rounded border border-[var(--border-default)] bg-white px-2 py-1 focus:outline-none focus:border-navy"
                  aria-label="Âncora da cláusula"
                >
                  <option value="">(geral — sem cláusula específica)</option>
                  {anchors.map(a => {
                    const n = anchorCounts[a.value] || 0;
                    const suffix = n > 0 ? ` · ${n} aberto${n > 1 ? 's' : ''}` : '';
                    return (
                      <option key={a.value} value={a.value} title={a.label}>
                        {a.value}{a.label.length > a.value.length + 2 ? ` — ${a.label.slice(0, 60)}${a.label.length > 60 ? '…' : ''}` : ''}{suffix}
                      </option>
                    );
                  })}
                  <option value="__custom__">Outro…</option>
                </select>
                {draftAnchorSel === '__custom__' && (
                  <input
                    type="text"
                    value={draftAnchorCustom}
                    onChange={e => setDraftAnchorCustom(e.target.value)}
                    placeholder="Cláusula custom (ex: 4.5.4)"
                    className="w-full text-[12px] rounded border border-[var(--border-default)] bg-white px-2 py-1 focus:outline-none focus:border-navy"
                    autoFocus
                  />
                )}
              </div>
            ) : (
              <input
                type="text"
                value={draftAnchorCustom}
                onChange={e => setDraftAnchorCustom(e.target.value)}
                placeholder="Cláusula (ex: 4.5.4)"
                className="w-full text-[12px] rounded border border-[var(--border-default)] bg-white px-2 py-1 focus:outline-none focus:border-navy"
              />
            )
          )}
          <textarea
            value={draftBody}
            onChange={e => setDraftBody(e.target.value)}
            placeholder={draftVisibility === 'change_notes' ? 'Resumo das alterações aplicadas pós-curadoria…' : 'Seu comentário…'}
            rows={3}
            className="w-full text-[12px] rounded border border-[var(--border-default)] bg-white px-2 py-1.5 focus:outline-none focus:border-navy resize-y"
          />
          <div className="flex items-center gap-2">
            <select
              value={draftVisibility}
              onChange={e => setDraftVisibility(e.target.value as Comment['visibility'])}
              className="text-[11px] rounded border border-[var(--border-default)] bg-white px-2 py-1 focus:outline-none focus:border-navy"
            >
              {isCurator && <option value="curator_only">Só curadores/GP</option>}
              {isSubmitter && <option value="submitter_only">Só GP</option>}
              {isSubmitter && chainStatus === 'review' && <option value="change_notes">Notas de alteração</option>}
            </select>
            <button
              type="button"
              onClick={submitComment}
              disabled={submitting || !draftBody.trim()}
              className="ml-auto rounded-lg bg-navy text-white text-[11px] font-bold px-3 py-1 border-0 cursor-pointer hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {submitting ? '…' : 'Publicar'}
            </button>
          </div>
        </footer>
      )}
    </div>
  );
}
