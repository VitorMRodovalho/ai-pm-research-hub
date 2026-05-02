import { useEffect, useState, useCallback } from 'react';
import GovernancePipelineBar from './GovernancePipelineBar';
import ClauseCommentDrawer from './ClauseCommentDrawer';
import VersionDiffViewer from './VersionDiffViewer';

type Gate = {
  kind: string;
  order: number;
  threshold: number | 'all';
  signed_count: number;
  signers: Array<{ name: string; chapter: string; signed_at: string; signoff_type: string; hash_short: string }>;
  eligible_pending: Array<{ id: string; name: string; chapter: string }>;
};

type WorkflowDetail = {
  chain_id: string;
  chain_status: 'draft' | 'review' | 'approved' | 'active' | 'withdrawn' | 'superseded';
  document_id: string;
  document_title: string;
  doc_type: string;
  version_id: string;
  version_label: string;
  locked_at: string | null;
  opened_at: string | null;
  submitter: { id: string; name: string; chapter: string; role: string } | null;
  gates: Gate[];
  days_open: number | null;
};

const GATE_LABELS: Record<string, string> = {
  curator: 'Curador',
  leader: 'Liderança',
  leader_awareness: 'Ciência das lideranças',
  submitter_acceptance: 'Aceite do GP',
  president_go: 'Presid. PMI-GO',
  president_others: 'Presid. capítulos',
  chapter_witness: 'Testemunhas',
  member_ratification: 'Ratificação de membros',
  external_signer: 'Signatário externo',
};

const SIGN_LABELS: Record<string, string> = {
  curator: 'Aprovar como curador',
  leader: 'Aprovar como liderança',
  leader_awareness: 'Confirmar ciência',
  submitter_acceptance: 'Aceitar pós-curadoria (liberar presidências)',
  president_go: 'Assinar como presidência PMI-GO',
  president_others: 'Assinar como presidência de capítulo',
  chapter_witness: 'Assinar como testemunha',
  member_ratification: 'Ratificar como membro',
  external_signer: 'Assinar como signatário externo',
};

const STATUS_LABELS: Record<string, { label: string; cls: string }> = {
  draft:      { label: 'Rascunho',    cls: 'bg-gray-100 text-gray-700 border-gray-300' },
  review:     { label: 'Em revisão',  cls: 'bg-amber-100 text-amber-900 border-amber-300' },
  approved:   { label: 'Aprovado',    cls: 'bg-blue-100 text-blue-800 border-blue-300' },
  active:     { label: 'Vigente',     cls: 'bg-emerald-100 text-emerald-800 border-emerald-300' },
  withdrawn:  { label: 'Retirado',    cls: 'bg-red-100 text-red-700 border-red-300' },
  superseded: { label: 'Substituído', cls: 'bg-gray-200 text-gray-600 border-gray-400' },
};

function fmtDT(d: string | null | undefined): string {
  if (!d) return '—';
  return new Date(d).toLocaleString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function activeEligibleGates(detail: WorkflowDetail, memberId: string): string[] {
  const gates = [...detail.gates].sort((a, b) => a.order - b.order);
  const eligible: string[] = [];
  let prevOK = true;
  for (const g of gates) {
    // threshold comes from RPC as text ("0", "1", "all"). Normalize defensively.
    const tStr = String(g.threshold);
    const isAll = tStr === 'all';
    const isInformational = tStr === '0';
    const tNum = isAll || isInformational ? 0 : Number(tStr);
    const satisfied = !isAll && !isInformational && g.signed_count >= tNum;
    if (isInformational) {
      // Informational gate (threshold=0) só fica elegível depois que gate anterior
      // obrigatório foi satisfeito (respeita prevOK). Não muda prevOK — não bloqueia próximo.
      if (prevOK && (g.eligible_pending || []).some(p => p.id === memberId)) {
        eligible.push(g.kind);
      }
      continue;
    }
    if (prevOK && !satisfied && (g.eligible_pending || []).some(p => p.id === memberId)) {
      eligible.push(g.kind);
    }
    prevOK = satisfied;
  }
  return eligible;
}

export default function ReviewChainIsland({ chainId }: { chainId: string }) {
  const [member, setMember] = useState<any>(null);
  const [detail, setDetail] = useState<WorkflowDetail | null>(null);
  const [contentHtml, setContentHtml] = useState<string>('');
  const [prevVersion, setPrevVersion] = useState<{ version_id: string; version_label: string; content_html: string; locked_at: string | null } | null>(null);
  const [nextDraft, setNextDraft] = useState<{ version_id: string; version_label: string; content_html: string; authored_at: string; notes: string | null } | null>(null);
  const [viewMode, setViewMode] = useState<'document' | 'diff' | 'draft' | 'draft_diff'>('document');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>('');
  const [signing, setSigning] = useState<string>('');
  const [showRecirculate, setShowRecirculate] = useState(false);
  const [recirculateLoading, setRecirculateLoading] = useState(false);
  const [recirculatePreview, setRecirculatePreview] = useState<any>(null);
  const [recirculateError, setRecirculateError] = useState<string>('');
  const [recirculateExecuting, setRecirculateExecuting] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    // Retry navGetSb() up to 4s — client script may not have mounted yet on fresh navigate
    let sb = getSb();
    if (!sb) {
      const deadline = Date.now() + 4000;
      while (!sb && Date.now() < deadline) {
        await new Promise(r => setTimeout(r, 250));
        sb = getSb();
      }
    }
    if (!sb) { setError('Cliente Supabase indisponível. Recarregue a página (Ctrl+Shift+R).'); setLoading(false); return; }

    let m: any = (window as any).navGetMember?.();
    if (!m) {
      const deadline = Date.now() + 4000;
      while (!m && Date.now() < deadline) {
        await new Promise(r => setTimeout(r, 250));
        m = (window as any).navGetMember?.();
      }
      if (!m) {
        try { const res = await sb.rpc('get_member_by_auth'); if (res.data) m = res.data; } catch {}
      }
    }
    if (!m) { setError('Faça login para acessar.'); setLoading(false); return; }
    setMember(m);

    const dRes = await sb.rpc('get_chain_workflow_detail', { p_chain_id: chainId });
    if (dRes.error || dRes.data?.error) { setError(dRes.error?.message || dRes.data?.error || 'Erro'); setLoading(false); return; }
    setDetail(dRes.data);

    const vRes = await sb.from('document_versions').select('content_html').eq('id', dRes.data.version_id).single();
    setContentHtml(vRes.data?.content_html || '<p class="text-[var(--text-muted)] italic">(conteúdo indisponível)</p>');

    // Load previous locked version (if any) for diff viewer (IP-3d)
    const pRes = await sb.rpc('get_previous_locked_version', { p_version_id: dRes.data.version_id });
    if (pRes.data && pRes.data.exists) {
      setPrevVersion({
        version_id: pRes.data.version_id,
        version_label: pRes.data.version_label,
        content_html: pRes.data.content_html,
        locked_at: pRes.data.locked_at,
      });
    }

    // Load next draft (if any) for review of pending iteration (p88, ADR-0068)
    const nRes = await sb.rpc('get_next_draft_version', { p_version_id: dRes.data.version_id });
    if (nRes.data && nRes.data.exists) {
      setNextDraft({
        version_id: nRes.data.version_id,
        version_label: nRes.data.version_label,
        content_html: nRes.data.content_html,
        authored_at: nRes.data.authored_at,
        notes: nRes.data.notes,
      });
      // PM feedback p88: quando há draft pendente, abrir review direto na versão
      // do draft. Curador entra na URL e lê o texto novo imediatamente — sem
      // pensar que não houve revisão (fricção observada). Tab pode ser trocada
      // para 'document' (versão lacrada) ou 'draft_diff' (comparação) a qualquer
      // momento via tab buttons.
      setViewMode('draft');
    }

    setLoading(false);
  }, [chainId, getSb]);

  useEffect(() => { load(); }, [load]);

  async function signGate(gateKind: string, signoffType: 'approval' | 'acknowledge') {
    if (!detail) return;
    if (gateKind === 'member_ratification') {
      window.location.href = '/governance/ip-agreement?chain_id=' + encodeURIComponent(detail.chain_id) + '&gate_kind=member_ratification';
      return;
    }
    const sb = getSb();
    if (!sb) return;
    setSigning(gateKind);
    const res = await sb.rpc('sign_ip_ratification', {
      p_chain_id: detail.chain_id,
      p_gate_kind: gateKind,
      p_signoff_type: signoffType,
      p_sections_verified: [],
      p_comment_body: null,
      p_ue_consent_49_1_a: null,
    });
    if (res.error || res.data?.error) {
      (window as any).toast?.(res.error?.message || res.data?.error || 'Erro ao assinar', 'error');
      setSigning('');
      return;
    }
    (window as any).toast?.('Assinatura registrada (' + String(res.data?.signature_hash || '').slice(0, 12) + '…)', 'success');
    setTimeout(() => load(), 600);
    setSigning('');
  }

  async function openRecirculate() {
    const sb = getSb();
    if (!sb || !detail) return;
    setShowRecirculate(true);
    setRecirculateLoading(true);
    setRecirculateError('');
    setRecirculatePreview(null);
    const res = await sb.rpc('recirculate_governance_doc', {
      p_chain_id: detail.chain_id,
      p_dry_run: true,
      p_recipient_emails: null,
    });
    if (res.error || res.data?.error) {
      setRecirculateError(res.error?.message || res.data?.error || 'Erro ao carregar preview');
      setRecirculateLoading(false);
      return;
    }
    setRecirculatePreview(res.data);
    setRecirculateLoading(false);
  }

  async function executeRecirculate() {
    const sb = getSb();
    if (!sb || !detail) return;
    const count = recirculatePreview?.recipient_count || 0;
    if (!confirm(`Confirma re-circulação?\n\nEsta ação:\n• Lacra o draft v${recirculatePreview?.draft_version?.version_label}\n• Marca chain atual como superseded\n• Cria nova chain com gates copiados\n• Envia ${count} email${count === 1 ? '' : 's'} aos recipients listados\n\nNão é reversível.`)) return;
    setRecirculateExecuting(true);
    setRecirculateError('');
    const res = await sb.rpc('recirculate_governance_doc', {
      p_chain_id: detail.chain_id,
      p_dry_run: false,
      p_recipient_emails: null,
    });
    if (res.error || res.data?.error) {
      setRecirculateError(res.error?.message || res.data?.error || 'Erro ao executar');
      setRecirculateExecuting(false);
      return;
    }
    if (res.data?.new_chain_id) {
      (window as any).toast?.(`Re-circulação executada — ${res.data.recipients_count} email(s) enfileirados`, 'success');
      setTimeout(() => { window.location.href = `/admin/governance/documents/${res.data.new_chain_id}`; }, 800);
    } else {
      setRecirculateExecuting(false);
      setShowRecirculate(false);
    }
  }

  if (loading) {
    return <div className="text-center py-16 text-sm text-[var(--text-muted)]">Carregando cadeia…</div>;
  }
  if (error) {
    return <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>;
  }
  if (!detail || !member) return null;

  const isSubmitter = detail.submitter?.id === member.id;
  const designations: string[] = member.designations || [];
  const isCurator = designations.includes('curator');
  const isAdmin = ['manager','deputy_manager'].includes(member.operational_role) || member.is_superadmin;
  const canComment = isCurator || isSubmitter || isAdmin;

  const eligibleGates = activeEligibleGates(detail, member.id);
  const statusMeta = STATUS_LABELS[detail.chain_status] || { label: detail.chain_status, cls: 'bg-gray-100' };

  return (
    <div className="space-y-4">
      <header className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4 space-y-3">
        <div className="flex items-start justify-between gap-3 flex-wrap">
          <div>
            <h2 className="text-lg font-bold text-[var(--text-primary)]">{detail.document_title}</h2>
            <p className="text-[11px] text-[var(--text-muted)] mt-0.5">
              Versão <strong>{detail.version_label}</strong> · Lacrada {fmtDT(detail.locked_at)}
              {' · '}
              Submetida por <strong>{detail.submitter?.name || '—'}</strong>
              {' em '}{fmtDT(detail.opened_at)}
              {detail.days_open != null && ' · aberta há ' + Math.floor(detail.days_open) + ' dia(s)'}
            </p>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <a
              href={`/admin/governance/documents/${detail.chain_id}/export-pdf`}
              className="rounded-lg bg-white text-[var(--text-secondary)] text-[11px] font-semibold px-2.5 py-1 border border-[var(--border-default)] hover:bg-[var(--surface-hover)]"
              title="Gerar PDF oficial da cadeia com evidências"
            >
              ⬇ PDF oficial
            </a>
            <a
              href={`/admin/governance/documents/${detail.chain_id}/audit-report`}
              className="rounded-lg bg-white text-amber-800 text-[11px] font-semibold px-2.5 py-1 border border-amber-300 hover:bg-amber-50"
              title="Relatório de auditoria para Conselho Fiscal (evidence trail completo)"
            >
              ⬇ Auditoria
            </a>
            <span className={`inline-block rounded-full border px-2 py-0.5 text-[11px] font-semibold ${statusMeta.cls}`}>{statusMeta.label}</span>
          </div>
        </div>
        <div className="pt-2 border-t border-[var(--border-default)]">
          <GovernancePipelineBar gates={detail.gates as any} gateLabels={GATE_LABELS} />
        </div>
      </header>

      {eligibleGates.length > 0 && (
        <div className="rounded-xl border-2 border-navy bg-blue-50/30 p-4">
          <h3 className="text-sm font-bold text-navy mb-2">Você pode agir agora</h3>
          <div className="flex flex-wrap gap-2">
            {eligibleGates.map(g => {
              const isInfo = detail.gates.find(x => x.kind === g)?.threshold === 0;
              return (
                <button key={g} type="button"
                  onClick={() => signGate(g, isInfo ? 'acknowledge' : 'approval')}
                  disabled={signing === g}
                  className="rounded-lg bg-navy text-white text-[12px] font-bold px-3 py-1.5 border-0 cursor-pointer hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  {signing === g ? '…' : (SIGN_LABELS[g] || ('Assinar ' + g))}
                </button>
              );
            })}
          </div>
          <p className="text-[10px] text-[var(--text-muted)] mt-2 italic">
            Assinaturas registradas com hash SHA-256 + timestamp + snapshot (Lei 14.063/2020 Art. 4§I). Gates informativos usam signoff_type=acknowledge (não bloqueiam avanço).
          </p>
        </div>
      )}

      {nextDraft && (
        <div className="rounded-xl border border-amber-300 bg-amber-50 p-3">
          <div className="flex items-start gap-2">
            <span className="text-amber-700 text-base">📝</span>
            <div className="flex-1">
              <h3 className="text-[13px] font-bold text-amber-900">
                Próxima versão (draft pendente): <strong>{nextDraft.version_label}</strong>
              </h3>
              <p className="text-[11px] text-amber-800 mt-0.5">
                Criado em {fmtDT(nextDraft.authored_at)} · {nextDraft.content_html.length.toLocaleString()} caracteres ·
                {' '}<button type="button" onClick={() => setViewMode('draft')}
                  className="underline font-semibold cursor-pointer hover:text-amber-900 bg-transparent border-0 p-0">
                  visualizar conteúdo
                </button>
                {' · '}
                <button type="button" onClick={() => setViewMode('draft_diff')}
                  className="underline font-semibold cursor-pointer hover:text-amber-900 bg-transparent border-0 p-0">
                  comparar com {detail.version_label}
                </button>
              </p>
              {nextDraft.notes && (
                <details className="mt-2">
                  <summary className="text-[11px] font-semibold text-amber-900 cursor-pointer hover:text-amber-700">
                    Changelog (notes da v{nextDraft.version_label})
                  </summary>
                  <div className="mt-1 p-2 rounded bg-white/60 border border-amber-200 text-[10px] text-amber-900 whitespace-pre-line max-h-40 overflow-y-auto">
                    {nextDraft.notes}
                  </div>
                </details>
              )}
            </div>
            {isAdmin && detail.chain_status === 'review' && (
              <button type="button" onClick={openRecirculate}
                className="shrink-0 rounded-lg bg-orange-600 text-white text-[11px] font-bold px-3 py-2 border-0 cursor-pointer hover:bg-orange-700"
                title="Lacrar este draft, marcar a chain atual como superseded, criar nova chain de revisão e notificar curadores via email"
              >
                🔄 Re-circular<br/>aos curadores
              </button>
            )}
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-4">
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden">
          {(prevVersion || nextDraft) && (
            <div className="flex items-center gap-2 px-4 py-2 border-b border-[var(--border-default)] bg-[var(--surface-hover)] flex-wrap">
              <div role="tablist" className="inline-flex rounded-lg border border-[var(--border-default)] bg-white p-0.5 flex-wrap">
                <button type="button" role="tab" aria-selected={viewMode === 'document'}
                  onClick={() => setViewMode('document')}
                  className={`text-[11px] font-bold px-3 py-1 rounded-md border-0 cursor-pointer ${viewMode === 'document' ? 'bg-navy text-white' : 'bg-transparent text-[var(--text-secondary)]'}`}
                >
                  Documento ({detail.version_label})
                </button>
                {prevVersion && (
                  <button type="button" role="tab" aria-selected={viewMode === 'diff'}
                    onClick={() => setViewMode('diff')}
                    className={`text-[11px] font-bold px-3 py-1 rounded-md border-0 cursor-pointer ${viewMode === 'diff' ? 'bg-navy text-white' : 'bg-transparent text-[var(--text-secondary)]'}`}
                  >
                    Diff {prevVersion.version_label} ↔ {detail.version_label}
                  </button>
                )}
                {nextDraft && (
                  <>
                    <button type="button" role="tab" aria-selected={viewMode === 'draft'}
                      onClick={() => setViewMode('draft')}
                      className={`text-[11px] font-bold px-3 py-1 rounded-md border-0 cursor-pointer ${viewMode === 'draft' ? 'bg-amber-600 text-white' : 'bg-transparent text-amber-800'}`}
                    >
                      Draft {nextDraft.version_label}
                    </button>
                    <button type="button" role="tab" aria-selected={viewMode === 'draft_diff'}
                      onClick={() => setViewMode('draft_diff')}
                      className={`text-[11px] font-bold px-3 py-1 rounded-md border-0 cursor-pointer ${viewMode === 'draft_diff' ? 'bg-amber-600 text-white' : 'bg-transparent text-amber-800'}`}
                    >
                      Diff {detail.version_label} ↔ Draft
                    </button>
                  </>
                )}
              </div>
            </div>
          )}
          {viewMode === 'diff' && prevVersion ? (
            <div className="px-4 py-3">
              <VersionDiffViewer
                previous={prevVersion}
                current={{ version_id: detail.version_id, version_label: detail.version_label, content_html: contentHtml, locked_at: detail.locked_at }}
              />
            </div>
          ) : viewMode === 'draft_diff' && nextDraft ? (
            <div className="px-4 py-3">
              <VersionDiffViewer
                previous={{ version_id: detail.version_id, version_label: detail.version_label, content_html: contentHtml, locked_at: detail.locked_at }}
                current={{ version_id: nextDraft.version_id, version_label: nextDraft.version_label, content_html: nextDraft.content_html, locked_at: null }}
              />
            </div>
          ) : viewMode === 'draft' && nextDraft ? (
            <div className="prose prose-sm max-w-none px-6 py-5 max-h-[72vh] overflow-y-auto text-[var(--text-primary)] border-l-4 border-amber-400"
                 dangerouslySetInnerHTML={{ __html: nextDraft.content_html }} />
          ) : (
            <div className="prose prose-sm max-w-none px-6 py-5 max-h-[72vh] overflow-y-auto text-[var(--text-primary)]"
                 dangerouslySetInnerHTML={{ __html: contentHtml }} />
          )}
        </div>
        <div className="h-[72vh]">
          <ClauseCommentDrawer
            versionId={detail.version_id}
            chainId={detail.chain_id}
            canComment={canComment}
            isSubmitter={isSubmitter}
            isCurator={isCurator}
            chainStatus={detail.chain_status}
            documentHtml={contentHtml}
          />
        </div>
      </div>

      <details className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)]">
        <summary className="px-4 py-3 cursor-pointer text-[13px] font-semibold text-[var(--text-primary)]">
          Auditoria por gate — assinantes + pendentes
        </summary>
        <div className="px-4 pb-4 overflow-x-auto">
          <table className="w-full text-[12px]">
            <thead className="bg-[var(--surface-hover)]">
              <tr>
                <th className="text-left px-2 py-1.5">Gate</th>
                <th className="text-left px-2 py-1.5">Assinantes</th>
                <th className="text-left px-2 py-1.5">Pendentes</th>
              </tr>
            </thead>
            <tbody>
              {[...detail.gates].sort((a, b) => a.order - b.order).map(g => (
                <tr key={g.kind} className="border-t border-[var(--border-default)]">
                  <td className="px-2 py-1.5 align-top">
                    <strong>{GATE_LABELS[g.kind] || g.kind}</strong>
                    <div className="text-[9px] text-[var(--text-muted)]">threshold: {String(g.threshold)}</div>
                  </td>
                  <td className="px-2 py-1.5 align-top">
                    {(g.signers || []).length === 0 ? (
                      <span className="text-[var(--text-muted)] italic text-[11px]">—</span>
                    ) : (g.signers || []).map((s, i) => (
                      <div key={i} className="text-[11px]">
                        ✓ <strong>{s.name}</strong>{' '}
                        <span className="text-[var(--text-muted)]">
                          ({s.chapter}) · {fmtDT(s.signed_at)} · <code className="text-[9px]">{s.hash_short}…</code>
                        </span>
                      </div>
                    ))}
                  </td>
                  <td className="px-2 py-1.5 align-top text-[11px]">
                    {(g.eligible_pending || []).length === 0 ? (
                      <span className="text-[var(--text-muted)] italic">—</span>
                    ) : (
                      <>
                        {(g.eligible_pending || []).slice(0, 5).map((p, i) => (
                          <span key={i}>{p.name} <span className="text-[var(--text-muted)]">({p.chapter})</span>{i < Math.min(4, g.eligible_pending.length - 1) ? ', ' : ''}</span>
                        ))}
                        {g.eligible_pending.length > 5 && (
                          <span className="text-[var(--text-muted)]">{' '}+{g.eligible_pending.length - 5}</span>
                        )}
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>

      {showRecirculate && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
          onClick={() => !recirculateExecuting && setShowRecirculate(false)}>
          <div className="bg-white rounded-xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-gray-200 flex items-center justify-between">
              <h3 className="text-base font-bold text-gray-900">🔄 Re-circular aos curadores</h3>
              <button type="button" onClick={() => !recirculateExecuting && setShowRecirculate(false)}
                disabled={recirculateExecuting}
                aria-label="Fechar"
                className="text-gray-500 hover:text-gray-900 text-xl leading-none bg-transparent border-0 cursor-pointer disabled:cursor-not-allowed px-1">
                ×
              </button>
            </div>
            <div className="px-5 py-4 space-y-3">
              {recirculateLoading && (
                <p className="text-sm text-gray-600">Carregando preview…</p>
              )}
              {recirculateError && (
                <div className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">
                  {recirculateError}
                </div>
              )}
              {recirculatePreview && !recirculateError && (
                <>
                  <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-[12px] text-amber-900">
                    <strong>Atenção:</strong> esta ação não é reversível. Lacra o draft, marca a chain atual como superseded, cria nova chain de revisão e envia emails aos recipients.
                  </div>
                  <div>
                    <h4 className="text-[11px] font-bold text-gray-600 uppercase mb-0.5">Documento</h4>
                    <p className="text-[14px] text-gray-900">{recirculatePreview.document?.title}</p>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <h4 className="text-[11px] font-bold text-gray-600 uppercase mb-0.5">Versão atual</h4>
                      <p className="text-[13px] text-gray-900">{recirculatePreview.current_chain?.version_label}</p>
                      <p className="text-[10px] text-gray-500">#{recirculatePreview.current_chain?.version_number} · status: {recirculatePreview.current_chain?.status}</p>
                    </div>
                    <div>
                      <h4 className="text-[11px] font-bold text-gray-600 uppercase mb-0.5">Draft pendente</h4>
                      <p className="text-[13px] text-amber-800 font-semibold">{recirculatePreview.draft_version?.version_label}</p>
                      <p className="text-[10px] text-gray-500">#{recirculatePreview.draft_version?.version_number} · changelog: {recirculatePreview.draft_version?.notes_present ? `${recirculatePreview.draft_version.notes_length} chars` : 'sem notes'}</p>
                    </div>
                  </div>
                  <div>
                    <h4 className="text-[11px] font-bold text-gray-600 uppercase mb-1">
                      Recipients ({recirculatePreview.recipient_count}) — gate: {recirculatePreview.first_gate_kind}
                    </h4>
                    {recirculatePreview.recipient_count === 0 ? (
                      <p className="text-[12px] text-gray-500 italic">Nenhum recipient identificado</p>
                    ) : (
                      <ul className="text-[12px] space-y-1 max-h-40 overflow-y-auto bg-gray-50 rounded p-2 border border-gray-200">
                        {(recirculatePreview.recipients || []).map((r: any, i: number) => (
                          <li key={i} className="flex justify-between items-center">
                            <span><strong>{r.first_name}</strong> &lt;{r.email}&gt;</span>
                            <span className="text-gray-500 text-[10px]">{r.source}</span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                  <div>
                    <h4 className="text-[11px] font-bold text-gray-600 uppercase mb-0.5">Gates copiadas para nova chain</h4>
                    <p className="text-[12px] text-gray-700">
                      {(recirculatePreview.gates_to_copy || []).map((g: any) => `${GATE_LABELS[g.kind] || g.kind}`).join(' → ')}
                    </p>
                  </div>
                  {(recirculatePreview.warnings || []).length > 0 && (
                    <div>
                      <h4 className="text-[11px] font-bold text-amber-800 uppercase mb-1">Avisos</h4>
                      <ul className="text-[11px] text-amber-900 space-y-1">
                        {recirculatePreview.warnings.map((w: any, i: number) => (
                          <li key={i}>• <strong>{w.code}:</strong> {w.message}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                </>
              )}
            </div>
            <div className="px-5 py-3 border-t border-gray-200 flex items-center justify-end gap-2">
              <button type="button" onClick={() => setShowRecirculate(false)} disabled={recirculateExecuting}
                className="rounded-lg bg-white text-gray-700 text-[12px] font-semibold px-3 py-1.5 border border-gray-300 cursor-pointer hover:bg-gray-50 disabled:opacity-50">
                Cancelar
              </button>
              <button type="button" onClick={executeRecirculate}
                disabled={!recirculatePreview || recirculateExecuting || !!recirculateError}
                className="rounded-lg bg-orange-600 text-white text-[12px] font-bold px-3 py-1.5 border-0 cursor-pointer hover:bg-orange-700 disabled:opacity-40 disabled:cursor-not-allowed">
                {recirculateExecuting
                  ? 'Executando…'
                  : `Confirmar e re-circular (${recirculatePreview?.recipient_count || 0} email${recirculatePreview?.recipient_count === 1 ? '' : 's'})`}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
