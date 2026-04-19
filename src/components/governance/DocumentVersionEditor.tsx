/**
 * DocumentVersionEditor — IP-3d Phase editor WYSIWYG para novas versoes de
 * governance_documents. Reuse de RichTextEditor (Tiptap, toolbar=full).
 *
 * Features:
 *  - Auto-save debounce 30s + save explicito
 *  - beforeunload guard se isDirty
 *  - Status "Salvo as HH:MM" inline
 *  - Modal de lock (UX-leader design — 3 secoes + label descritivo sem checkbox)
 *  - Preview de gates/signers antes de lock (stakeholder-persona GP-leader RC-1)
 *  - Delete draft inline
 *
 * Reference: ADR-0016, handoff_ip3d_prompt.md, auditorias council p33b.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import RichTextEditor from '../shared/RichTextEditor';

type DocMeta = {
  id: string;
  title: string;
  doc_type: string;
  current_version_id: string | null;
};

type SeedVersion = {
  id: string;
  version_label: string;
  content_html: string;
  locked_at: string | null;
};

type Gate = { kind: string; order: number; threshold: number | 'all' };

type SignerCount = { gate_kind: string; label: string; count: number; sample: string[] };

const GATE_LABELS: Record<string, string> = {
  curator: 'Curador',
  leader: 'Lideranca',
  leader_awareness: 'Ciencia das liderancas',
  submitter_acceptance: 'Aceite do GP',
  president_go: 'Presid. PMI-GO',
  president_others: 'Presid. outros capitulos',
  chapter_witness: 'Testemunhas dos capitulos',
  member_ratification: 'Ratificacao dos membros',
  external_signer: 'Signatarios externos',
};

// Default gates template (matches IP-3c v2.2 shape, order 1..7)
const DEFAULT_GATES: Gate[] = [
  { kind: 'curator', order: 1, threshold: 1 },
  { kind: 'leader_awareness', order: 2, threshold: 0 },
  { kind: 'submitter_acceptance', order: 3, threshold: 1 },
  { kind: 'chapter_witness', order: 4, threshold: 5 },
  { kind: 'president_go', order: 5, threshold: 1 },
  { kind: 'president_others', order: 6, threshold: 4 },
  { kind: 'member_ratification', order: 7, threshold: 'all' },
];

interface Props {
  docId: string;
  draftVersionId?: string;
}

function fmtTime(d: Date | null): string {
  if (!d) return '';
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

function thresholdLabel(t: number | 'all'): string {
  if (t === 'all') return 'todos';
  if (t === 0) return 'informativo';
  return `${t} assinatura${t === 1 ? '' : 's'}`;
}

export default function DocumentVersionEditor({ docId, draftVersionId }: Props) {
  const [doc, setDoc] = useState<DocMeta | null>(null);
  const [seed, setSeed] = useState<SeedVersion | null>(null);
  const [content, setContent] = useState<string>('');
  const [versionId, setVersionId] = useState<string | null>(draftVersionId || null);
  const [versionLabel, setVersionLabel] = useState<string>('');
  const [notes, setNotes] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>('');
  const [saving, setSaving] = useState(false);
  const [lastSavedAt, setLastSavedAt] = useState<Date | null>(null);
  const [isDirty, setIsDirty] = useState(false);
  const [gates] = useState<Gate[]>(DEFAULT_GATES);
  const [changeNotes, setChangeNotes] = useState<string>('');
  const [modalOpen, setModalOpen] = useState(false);
  const [locking, setLocking] = useState(false);
  const [signerPreview, setSignerPreview] = useState<SignerCount[]>([]);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false);

  const lastSavedContentRef = useRef<string>('');
  const saveTimerRef = useRef<any>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  // ── Load doc + seed content or existing draft ──
  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setError('Cliente Supabase indisponivel.'); setLoading(false); return; }

    const dRes = await sb
      .from('governance_documents')
      .select('id, title, doc_type, current_version_id')
      .eq('id', docId)
      .single();
    if (dRes.error || !dRes.data) {
      setError('Documento nao encontrado.');
      setLoading(false);
      return;
    }
    setDoc(dRes.data as DocMeta);

    // If draft version id provided, load it as the working copy
    if (draftVersionId) {
      const vRes = await sb
        .from('document_versions')
        .select('id, version_label, content_html, content_markdown, notes, locked_at, version_number')
        .eq('id', draftVersionId)
        .single();
      if (vRes.error || !vRes.data) {
        setError('Rascunho nao encontrado.');
        setLoading(false);
        return;
      }
      if (vRes.data.locked_at) {
        setError('Esta versao esta bloqueada. Crie uma nova versao.');
        setLoading(false);
        return;
      }
      setContent(vRes.data.content_html || '');
      lastSavedContentRef.current = vRes.data.content_html || '';
      setVersionLabel(vRes.data.version_label || '');
      setNotes(vRes.data.notes || '');
    }

    // Always also load the current locked version (for seed + diff context)
    if (dRes.data.current_version_id) {
      const curRes = await sb
        .from('document_versions')
        .select('id, version_label, content_html, locked_at')
        .eq('id', dRes.data.current_version_id)
        .single();
      if (curRes.data) setSeed(curRes.data as SeedVersion);

      // If no draft, pre-populate editor with the locked current version content
      if (!draftVersionId && curRes.data?.content_html) {
        setContent(curRes.data.content_html);
        lastSavedContentRef.current = curRes.data.content_html;
      }
    }

    setLoading(false);
  }, [docId, draftVersionId, getSb]);

  useEffect(() => { load(); }, [load]);

  // ── isDirty tracking ──
  useEffect(() => {
    setIsDirty(content !== lastSavedContentRef.current);
  }, [content]);

  // ── beforeunload guard ──
  useEffect(() => {
    function onBeforeUnload(e: BeforeUnloadEvent) {
      if (isDirty) {
        e.preventDefault();
        e.returnValue = '';
      }
    }
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, [isDirty]);

  // ── Save (explicit or auto) ──
  const save = useCallback(async () => {
    if (!doc) return;
    if (!content || !content.trim()) {
      (window as any).toast?.('Conteudo vazio — adicione texto antes de salvar.', 'error');
      return;
    }
    const sb = getSb();
    if (!sb) return;
    setSaving(true);
    const res = await sb.rpc('upsert_document_version', {
      p_document_id: doc.id,
      p_content_html: content,
      p_content_markdown: null,
      p_version_label: versionLabel || null,
      p_version_id: versionId,
      p_notes: notes || null,
    });
    setSaving(false);
    if (res.error || res.data?.error) {
      (window as any).toast?.(res.error?.message || res.data?.error || 'Erro ao salvar', 'error');
      return;
    }
    if (res.data?.version_id && !versionId) setVersionId(res.data.version_id);
    if (res.data?.version_label && !versionLabel) setVersionLabel(res.data.version_label);
    lastSavedContentRef.current = content;
    setLastSavedAt(new Date());
    setIsDirty(false);
  }, [doc, content, versionId, versionLabel, notes, getSb]);

  // ── Auto-save debounce 30s ──
  useEffect(() => {
    if (!isDirty) return;
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => {
      void save();
    }, 30000);
    return () => {
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    };
  }, [isDirty, save]);

  // ── Open lock modal: preload signer preview for UX-leader spec ──
  const openLockModal = useCallback(async () => {
    if (!versionId || isDirty) {
      (window as any).toast?.('Salve o rascunho antes de colocar em revisao.', 'error');
      return;
    }
    setModalOpen(true);
    setPreviewLoading(true);
    setSignerPreview([]);
    const sb = getSb();
    if (!sb) { setPreviewLoading(false); return; }
    // Count eligibles per gate by hitting members + _can_sign_gate is server-side;
    // client-side shortcut: use static designation/role queries.
    const previews: SignerCount[] = [];
    for (const g of gates) {
      if (g.kind === 'member_ratification') {
        const r = await sb.from('members').select('id, name').eq('member_status', 'active').eq('is_active', true).limit(5);
        const total = await sb.from('members').select('id', { count: 'exact', head: true }).eq('member_status', 'active').eq('is_active', true);
        previews.push({
          gate_kind: g.kind,
          label: GATE_LABELS[g.kind] || g.kind,
          count: total.count || 0,
          sample: (r.data || []).map((m: any) => m.name).slice(0, 3),
        });
        continue;
      }
      let query: any = sb.from('members').select('id, name', { count: 'exact' }).eq('is_active', true);
      if (g.kind === 'curator') query = query.contains('designations', ['curator']);
      else if (g.kind === 'leader_awareness') query = query.in('operational_role', ['tribe_leader','manager','deputy_manager']);
      else if (g.kind === 'submitter_acceptance') query = query.limit(1); // always 1 = submitter
      else if (g.kind === 'president_go') query = query.eq('chapter', 'PMI-GO').contains('designations', ['chapter_board']);
      else if (g.kind === 'president_others') query = query.in('chapter', ['PMI-CE','PMI-DF','PMI-MG','PMI-RS']).contains('designations', ['chapter_board']);
      else if (g.kind === 'chapter_witness') query = query.contains('designations', ['chapter_witness']);
      const r = await query;
      previews.push({
        gate_kind: g.kind,
        label: GATE_LABELS[g.kind] || g.kind,
        count: r.count || (r.data?.length || 0),
        sample: (r.data || []).map((m: any) => m.name).slice(0, 3),
      });
    }
    setSignerPreview(previews);
    setPreviewLoading(false);
  }, [versionId, isDirty, gates, getSb]);

  // ── Lock + create chain + optional change_notes ──
  const lock = useCallback(async () => {
    if (!versionId) return;
    const sb = getSb();
    if (!sb) return;
    setLocking(true);
    const res = await sb.rpc('lock_document_version', {
      p_version_id: versionId,
      p_gates: gates,
    });
    if (res.error || res.data?.error) {
      setLocking(false);
      (window as any).toast?.(res.error?.message || res.data?.error || 'Erro ao lacrar', 'error');
      return;
    }
    // If change notes provided, register them as change_notes comment on the new chain
    if (changeNotes.trim() && res.data?.chain_id) {
      const cnRes = await sb.rpc('create_change_note', {
        p_chain_id: res.data.chain_id,
        p_body: changeNotes.trim(),
      });
      if (cnRes.error || cnRes.data?.error) {
        // Non-fatal — lock succeeded. Toast warning and continue.
        (window as any).toast?.('Versão lacrada, mas notas de alteração não salvas: ' + (cnRes.error?.message || cnRes.data?.error), 'error');
      }
    }
    setLocking(false);
    (window as any).toast?.(`Versão lacrada — ${res.data?.notifications_enqueued || 0} notificações enviadas`, 'success');
    if (res.data?.chain_id) {
      setTimeout(() => { window.location.href = `/admin/governance/documents/${res.data.chain_id}`; }, 800);
    }
  }, [versionId, gates, changeNotes, getSb]);

  // ── Delete draft ──
  const deleteDraft = useCallback(async () => {
    if (!versionId) { window.location.href = '/admin/governance/documents'; return; }
    const sb = getSb();
    if (!sb) return;
    const res = await sb.rpc('delete_document_version_draft', { p_version_id: versionId });
    if (res.error || res.data?.error) {
      (window as any).toast?.(res.error?.message || res.data?.error || 'Erro ao descartar', 'error');
      return;
    }
    (window as any).toast?.('Rascunho descartado', 'success');
    setTimeout(() => { window.location.href = '/admin/governance/documents'; }, 500);
  }, [versionId, getSb]);

  if (loading) return <div className="text-center py-16 text-sm text-[var(--text-muted)]">Carregando editor…</div>;
  if (error) return <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>;
  if (!doc) return null;

  return (
    <div className="space-y-4">
      {/* Header */}
      <header className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4 flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-xl font-bold text-[var(--text-primary)]">
            {draftVersionId || versionId ? 'Editar rascunho' : 'Nova versao'} — {doc.title}
          </h1>
          {seed && (
            <p className="text-[11px] text-[var(--text-muted)] mt-0.5">
              Base: {seed.version_label} {seed.locked_at ? `(lacrada ${new Date(seed.locked_at).toLocaleDateString('pt-BR')})` : ''}
            </p>
          )}
        </div>
        <div className="flex items-center gap-2">
          <span className="text-[11px] text-[var(--text-muted)]" aria-live="polite">
            {saving ? 'Salvando…' : lastSavedAt ? `Salvo as ${fmtTime(lastSavedAt)}` : isDirty ? 'Nao salvo' : 'Pronto'}
          </span>
          <button
            type="button"
            onClick={save}
            disabled={saving || !isDirty}
            className="rounded-lg bg-[var(--surface-hover)] text-[var(--text-primary)] text-[12px] font-semibold px-3 py-1.5 border border-[var(--border-default)] cursor-pointer hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Salvar rascunho
          </button>
          <button
            type="button"
            onClick={openLockModal}
            disabled={!versionId || isDirty}
            className="rounded-lg bg-navy text-white text-[12px] font-bold px-3 py-1.5 border-0 cursor-pointer hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
            title={!versionId ? 'Salve o rascunho primeiro' : isDirty ? 'Ha alteracoes nao salvas' : 'Abre modal de confirmacao'}
          >
            Colocar em revisao
          </button>
          {versionId && (
            <button
              type="button"
              onClick={() => setDeleteConfirmOpen(true)}
              className="rounded-lg bg-white text-red-700 text-[12px] font-semibold px-3 py-1.5 border border-red-300 cursor-pointer hover:bg-red-50"
            >
              Descartar
            </button>
          )}
        </div>
      </header>

      {/* Metadata */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4 grid grid-cols-1 md:grid-cols-[1fr_1fr] gap-3">
        <label className="block">
          <span className="block text-[11px] font-semibold text-[var(--text-secondary)] mb-1">Rotulo da versao</span>
          <input
            type="text"
            value={versionLabel}
            onChange={e => { setVersionLabel(e.target.value); setIsDirty(true); }}
            placeholder="Ex: v3.0 — revisao pos-CBGPL"
            className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-[13px] bg-[var(--surface-base)]"
          />
        </label>
        <label className="block">
          <span className="block text-[11px] font-semibold text-[var(--text-secondary)] mb-1">Notas de autoria (opcional)</span>
          <input
            type="text"
            value={notes}
            onChange={e => { setNotes(e.target.value); setIsDirty(true); }}
            placeholder="Breve nota sobre o que mudou nesta versao"
            className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-[13px] bg-[var(--surface-base)]"
          />
        </label>
      </div>

      {/* Notice of immutability — displayed upfront (gp-leader FP-1 preventive) */}
      <div className="rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 text-[12px] text-amber-900">
        <strong>Aviso:</strong> ao colocar em revisao, o texto desta versao ficara <em>permanentemente bloqueado</em>. Edicoes adicionais exigem criar uma versao seguinte (v+1) e retirar esta.
      </div>

      {/* Editor */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-2">
        <RichTextEditor
          content={content}
          onChange={setContent}
          placeholder="Comece a escrever o conteudo da nova versao..."
          minHeight="500px"
          toolbar="full"
        />
      </div>

      {/* Lock modal (UX-leader spec — 3 sections, no checkbox, descriptive button label) */}
      {modalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="lock-modal-title"
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
        >
          <div className="bg-white rounded-xl max-w-xl w-full shadow-xl overflow-hidden">
            <header className="px-5 py-4 border-b border-[var(--border-default)]">
              <h2 id="lock-modal-title" className="text-base font-bold text-[var(--text-primary)]">
                Lacrar versao e iniciar ratificacao
              </h2>
            </header>
            <div className="px-5 py-4 space-y-4">
              {/* Section 1 — Consequence (amber) */}
              <div className="rounded-lg border-l-4 border-amber-500 bg-amber-50 px-3 py-2">
                <p className="text-[13px] text-amber-900">
                  Ao confirmar, o texto desta versao <strong>ficara permanentemente bloqueado</strong> para edicao.
                  Esta acao nao pode ser desfeita pela plataforma.
                </p>
              </div>

              {/* Section 2 — Impact preview */}
              <div>
                <p className="text-[12px] font-semibold text-[var(--text-secondary)] mb-2">
                  Pessoas que serão notificadas por email para iniciar assinaturas:
                </p>
                {previewLoading ? (
                  <p className="text-[12px] text-[var(--text-muted)] italic">Calculando elegíveis…</p>
                ) : (
                  <ul className="space-y-1">
                    {signerPreview.map(p => (
                      <li key={p.gate_kind} className="flex items-start gap-2 text-[12px]">
                        <span className="inline-block rounded bg-[var(--surface-hover)] px-1.5 py-0.5 text-[10px] font-mono text-[var(--text-secondary)]">
                          {gates.find(g => g.kind === p.gate_kind)?.order}
                        </span>
                        <span className="flex-1">
                          <strong className="text-[var(--text-primary)]">{p.label}</strong>
                          <span className="text-[var(--text-muted)]">
                            {' '}· {p.count} elegível{p.count === 1 ? '' : 'is'}
                            {p.sample.length > 0 && ` (ex: ${p.sample.slice(0, 3).join(', ')}${p.count > 3 ? '…' : ''})`}
                            {' '}· {thresholdLabel(gates.find(g => g.kind === p.gate_kind)?.threshold ?? 1)}
                          </span>
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              {/* Section 3 — Change notes (registra no change_notes do chain) */}
              <div>
                <label className="block">
                  <span className="block text-[12px] font-semibold text-[var(--text-secondary)] mb-1">
                    Notas de alteração <span className="text-[10px] text-[var(--text-muted)] font-normal">(opcional — registradas fora do documento, visíveis a curadores, testemunhas e presidências)</span>
                  </span>
                  <textarea
                    value={changeNotes}
                    onChange={e => setChangeNotes(e.target.value)}
                    placeholder="Resumo do que mudou em relação à versão anterior (ex: Ajustes §4.5.4 IRRF + nova Cláusula 8 AI Training…). Fica registrado como 'Notas de alteração' na chain, separado do corpo do documento."
                    rows={3}
                    className="w-full text-[12px] rounded border border-[var(--border-default)] bg-white px-2 py-1.5 focus:outline-none focus:border-navy resize-y"
                  />
                </label>
              </div>
            </div>
            <footer className="px-5 py-3 border-t border-[var(--border-default)] bg-[var(--surface-hover)] flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                disabled={locking}
                className="rounded-lg bg-white text-[var(--text-secondary)] text-[12px] font-semibold px-3 py-1.5 border border-[var(--border-default)] cursor-pointer hover:bg-[var(--surface-base)]"
              >
                Cancelar — continuar editando
              </button>
              <button
                type="button"
                onClick={lock}
                disabled={locking}
                className="rounded-lg bg-navy text-white text-[12px] font-bold px-3 py-1.5 border-0 cursor-pointer hover:opacity-90 disabled:opacity-40"
              >
                {locking ? 'Lacrando…' : `Lacrar ${versionLabel || 'versao'} e notificar signatarios`}
              </button>
            </footer>
          </div>
        </div>
      )}

      {/* Delete confirmation modal */}
      {deleteConfirmOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
        >
          <div className="bg-white rounded-xl max-w-sm w-full shadow-xl overflow-hidden">
            <header className="px-5 py-4 border-b border-[var(--border-default)]">
              <h2 className="text-base font-bold text-[var(--text-primary)]">Descartar rascunho?</h2>
            </header>
            <div className="px-5 py-4">
              <p className="text-[13px] text-[var(--text-secondary)]">
                Esta acao remove o rascunho atual. Nao afeta versoes ja lacradas. Texto nao recuperavel.
              </p>
            </div>
            <footer className="px-5 py-3 border-t border-[var(--border-default)] bg-[var(--surface-hover)] flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setDeleteConfirmOpen(false)}
                className="rounded-lg bg-white text-[var(--text-secondary)] text-[12px] font-semibold px-3 py-1.5 border border-[var(--border-default)] cursor-pointer"
              >
                Manter
              </button>
              <button
                type="button"
                onClick={deleteDraft}
                className="rounded-lg bg-red-600 text-white text-[12px] font-bold px-3 py-1.5 border-0 cursor-pointer hover:opacity-90"
              >
                Descartar definitivamente
              </button>
            </footer>
          </div>
        </div>
      )}
    </div>
  );
}
