// src/components/admin/AffiliationQueueIsland.tsx
// #659 — Pasta Diretoria de Filiação (epic #660 step 2).
// Focused, least-privilege panel for the OFFICE of the Diretoria de Filiação (designation
// `filiacao_director`) — NOT the full member-management surface. Reads the verification queue
// (get_affiliation_verification_queue), surfaces the federated-gate data (PMI BR chapter + expiry
// from pmi_memberships), and records verifications via the already-shipped #647 F1 write loop
// (verify_member_affiliation / _bulk) behind the F1b confidentiality attestation gate.
//
// Authority is function-anchored (PM 2026-06-12): access follows the office, never a name. The
// server RPCs are the real boundary; this UI is convenience + the just-in-time attestation gate.
import { useState, useEffect, useCallback, useRef } from 'react';
import { Loader2, SearchCheck, CalendarClock, ShieldCheck, Info } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { brChapters, type PmiMembershipEntry } from '../../lib/affiliation-chapters';

interface LatestVerification {
  created_at: string;
  membership_active: boolean | null;
  membership_expires_on: string | null;
  method: string | null;
  chapter_verified: string | null;
}
interface QueueRow {
  member_id: string;
  name: string;
  email: string;
  chapter: string | null;
  operational_role: string | null;
  is_pre_onboarding: boolean;
  pmi_id_verified: boolean;
  vep_status_raw: string | null;
  vep_last_seen_at: string | null;
  pmi_memberships: PmiMembershipEntry[] | null;
  latest_verification: LatestVerification | null;
}

/* "31 Jul 2026" (VEP) -> "2026-07-31" for the <input type=date>; '' if unparseable. */
function toDateInput(raw: string | null | undefined): string {
  if (!raw) return '';
  const ts = Date.parse(raw);
  if (Number.isNaN(ts)) return '';
  return new Date(ts).toISOString().slice(0, 10);
}

/* Verification farol from the latest append-only verification. */
function farol(r: QueueRow, t: (k: string, f?: string) => string): { emoji: string; label: string; cls: string } {
  const v = r.latest_verification;
  if (!v) return { emoji: '⚪', label: t('comp.affiliationQueue.affUnverified', 'Não verificada'), cls: 'bg-slate-100 text-slate-500' };
  if (v.membership_active === false) return { emoji: '🔴', label: t('comp.affiliationQueue.affInactive', 'Filiação inativa'), cls: 'bg-rose-50 text-rose-700' };
  if (v.membership_expires_on) {
    const days = Math.ceil((new Date(v.membership_expires_on).getTime() - Date.now()) / 86400000);
    if (days < 0) return { emoji: '🔴', label: t('comp.affiliationQueue.affExpired', 'Filiação vencida'), cls: 'bg-rose-50 text-rose-700' };
    if (days <= 30) return { emoji: '🟡', label: t('comp.affiliationQueue.affExpiring', 'Vence em breve'), cls: 'bg-amber-50 text-amber-700' };
  }
  return { emoji: '🟢', label: t('comp.affiliationQueue.affVerified', 'Verificada'), cls: 'bg-emerald-50 text-emerald-700' };
}

const VEP_CLS: Record<string, string> = {
  Active: 'bg-emerald-50 text-emerald-700',
  Submitted: 'bg-blue-50 text-blue-700',
  OfferExtended: 'bg-amber-50 text-amber-700',
};

export default function AffiliationQueueIsland() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const [rows, setRows] = useState<QueueRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'pre' | 'all'>('pre');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [bulkVerifying, setBulkVerifying] = useState(false);

  // ── load the queue (retry until Nav publishes the authed client) ──
  const fetchQueue = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(fetchQueue, 300); return; }
    setLoading(true);
    const { data, error } = await sb.rpc('get_affiliation_verification_queue');
    if (error) {
      (window as any).toast?.(error.message || t('comp.affiliationQueue.loadError', 'Erro ao carregar a fila'), 'error');
      setRows([]);
    } else {
      setRows(Array.isArray(data) ? data : []);
    }
    setLoading(false);
  }, [getSb, t]);

  const fetchRef = useRef(fetchQueue); fetchRef.current = fetchQueue;
  useEffect(() => {
    let cancelled = false;
    const boot = () => { if (cancelled) return; getSb() ? fetchRef.current() : setTimeout(boot, 300); };
    boot();
    const h = () => fetchRef.current();
    window.addEventListener('nav:member', h);
    return () => { cancelled = true; window.removeEventListener('nav:member', h); };
  }, [getSb]);

  // ── F1b attestation gate (lifted from MemberListIsland) ──
  const [attestation, setAttestation] = useState<any>(null);
  const [showAttest, setShowAttest] = useState(false);
  const [attestChecked, setAttestChecked] = useState(false);
  const [attesting, setAttesting] = useState(false);
  const [pendingAttest, setPendingAttest] = useState<(() => void) | null>(null);

  useEffect(() => {
    let cancelled = false;
    const boot = () => {
      const sb = getSb();
      if (!sb) { if (!cancelled) setTimeout(boot, 400); return; }
      sb.rpc('get_my_affiliation_attestation').then(({ data }: any) => { if (!cancelled && data) setAttestation(data); }).catch(() => {});
    };
    boot();
    return () => { cancelled = true; };
  }, [getSb]);

  const requireAttest = (action: () => void) => {
    if (attestation?.needs_attestation) {
      setPendingAttest(() => action);
      setAttestChecked(false);
      setShowAttest(true);
    } else { action(); }
  };

  const handleAttest = async () => {
    const sb = getSb(); if (!sb) return;
    setAttesting(true);
    const { data, error } = await sb.rpc('attest_affiliation_access', { p_signed_user_agent: navigator.userAgent });
    setAttesting(false);
    if (error || !data?.ok) {
      (window as any).toast?.(error?.message || t('comp.affiliationQueue.operationError', 'Erro na operação'), 'error');
      return;
    }
    const { data: att } = await sb.rpc('get_my_affiliation_attestation');
    if (att) setAttestation(att);
    setShowAttest(false);
    const act = pendingAttest; setPendingAttest(null); act?.();
  };

  // ── individual verify modal (sede_manual: active + chapter + expiry + obs) ──
  const [vMember, setVMember] = useState<QueueRow | null>(null);
  const [vActive, setVActive] = useState(true);
  const [vChapter, setVChapter] = useState('');
  const [vExpires, setVExpires] = useState('');
  const [vObs, setVObs] = useState('');
  const [vSaving, setVSaving] = useState(false);

  const openVerify = (r: QueueRow) => {
    const br = brChapters(r.pmi_memberships);
    setVMember(r);
    setVActive(r.latest_verification?.membership_active !== false);
    setVChapter(br[0]?.name ? `${br[0].name}, Brazil Chapter` : (r.chapter || ''));
    setVExpires(r.latest_verification?.membership_expires_on || toDateInput(br[0]?.expiry));
    setVObs('');
  };

  const handleVerify = async () => {
    if (!vMember) return;
    const sb = getSb(); if (!sb) return;
    setVSaving(true);
    const { data, error } = await sb.rpc('verify_member_affiliation', {
      p_member_id: vMember.member_id,
      p_chapter: vChapter || null,
      p_active: vActive,
      p_expires_on: vExpires || null,
      p_method: 'sede_manual',
      p_obs: vObs || null,
    });
    setVSaving(false);
    if (error || data?.error) {
      (window as any).toast?.(error?.message || data?.error || t('comp.affiliationQueue.saveError', 'Erro ao salvar'), 'error');
      return;
    }
    (window as any).toast?.(t('comp.affiliationQueue.verifyDone', 'Filiação verificada'), 'success');
    setVMember(null);
    await fetchQueue();
  };

  // ── bulk "verificar via VEP" (vep_sync) ──
  const handleBulkVerifyVep = async () => {
    const sb = getSb(); if (!sb) return;
    setBulkVerifying(true);
    const { data, error } = await sb.rpc('verify_member_affiliations_bulk', {
      p_member_ids: [...selectedIds],
      p_method: 'vep_sync',
    });
    setBulkVerifying(false);
    if (error || !data?.ok) {
      (window as any).toast?.(error?.message || t('comp.affiliationQueue.operationError', 'Erro na operação'), 'error');
      return;
    }
    const noVep = (data.no_vep_ids || []).length;
    const notFound = (data.not_found_ids || []).length;
    const warn = noVep + notFound > 0;
    (window as any).toast?.(
      `${data.count} ${t('comp.affiliationQueue.verifyDone', 'Filiação verificada')} (VEP)` +
      (noVep ? ` · ${noVep} ${t('comp.affiliationQueue.noVep', 'sem VEP')}` : '') +
      (notFound ? ` · ${notFound} ${t('comp.affiliationQueue.notFound', 'não encontrado(s)')}` : ''),
      warn ? 'warning' : 'success');
    setSelectedIds(new Set());
    await fetchQueue();
  };

  const toggle = (id: string) =>
    setSelectedIds(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });

  const preCount = rows.filter(r => r.is_pre_onboarding).length;
  const visible = tab === 'pre' ? rows.filter(r => r.is_pre_onboarding) : rows;
  const allVisibleSelected = visible.length > 0 && visible.every(r => selectedIds.has(r.member_id));
  const toggleAll = () =>
    setSelectedIds(s => {
      const n = new Set(s);
      if (allVisibleSelected) visible.forEach(r => n.delete(r.member_id));
      else visible.forEach(r => n.add(r.member_id));
      return n;
    });

  if (loading) return (
    <div className="flex items-center justify-center py-20 text-[var(--text-muted)]">
      <Loader2 size={24} className="animate-spin mr-2" /> {t('comp.affiliationQueue.loading', 'Carregando fila…')}
    </div>
  );

  return (
    <div>
      {/* intro */}
      <div className="mb-5 flex items-start gap-2 text-[13px] text-[var(--text-secondary)] bg-[var(--surface-section-cool)] rounded-xl px-4 py-3">
        <ShieldCheck size={18} className="text-teal-600 mt-0.5 flex-shrink-0" />
        <p>{t('comp.affiliationQueue.intro', 'Verifique a filiação PMI dos membros: (1) membresia ativa e (2) filiação a um capítulo brasileiro em dia. O dado de filiação do VEP é exibido quando disponível; quando o candidato mantém a comunidade PMI privada ou ainda não é filiado, preencha manualmente.')}</p>
      </div>

      {/* tabs */}
      <div className="flex items-center gap-2 mb-4">
        <button onClick={() => setTab('pre')}
          className={`px-3 py-1.5 text-[13px] rounded-lg border cursor-pointer ${tab === 'pre' ? 'bg-teal-600 text-white border-teal-600' : 'bg-transparent text-[var(--text-secondary)] border-[var(--border-default)] hover:bg-[var(--surface-hover)]'}`}>
          {t('comp.affiliationQueue.tabPre', 'Pré-onboarding')} ({preCount})
        </button>
        <button onClick={() => setTab('all')}
          className={`px-3 py-1.5 text-[13px] rounded-lg border cursor-pointer ${tab === 'all' ? 'bg-teal-600 text-white border-teal-600' : 'bg-transparent text-[var(--text-secondary)] border-[var(--border-default)] hover:bg-[var(--surface-hover)]'}`}>
          {t('comp.affiliationQueue.tabAll', 'Todos não-verificados')} ({rows.length})
        </button>
      </div>

      {/* bulk bar */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 mb-4 px-3 py-2 rounded-lg bg-[var(--surface-section-cool)]">
          <span className="text-sm text-[var(--text-secondary)]">{selectedIds.size} {t('comp.affiliationQueue.selected', 'selecionado(s)')}</span>
          <button onClick={() => requireAttest(handleBulkVerifyVep)} disabled={bulkVerifying}
            className="px-3 py-1.5 text-[13px] bg-indigo-600 text-white rounded-lg border-0 cursor-pointer hover:bg-indigo-700 disabled:opacity-50">
            {bulkVerifying ? t('comp.affiliationQueue.verifying', 'Verificando…') : t('comp.affiliationQueue.bulkVerifyVep', 'Verificar via VEP (membresia ativa)')}
          </button>
        </div>
      )}

      {visible.length === 0 ? (
        <div className="text-center py-16 text-[var(--text-muted)]">{t('comp.affiliationQueue.empty', 'Nenhum membro pendente de verificação.')}</div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-[var(--surface-section-cool)] text-[var(--text-muted)] text-[.65rem] uppercase tracking-wider">
                <th className="px-3 py-2 w-10"><input type="checkbox" checked={allVisibleSelected} onChange={toggleAll} className="accent-teal-500" aria-label={t('comp.affiliationQueue.selectAll', 'Selecionar todos')} /></th>
                <th className="px-3 py-2 text-left">{t('comp.affiliationQueue.thMember', 'Membro')}</th>
                <th className="px-3 py-2 text-left">{t('comp.affiliationQueue.thChapter', 'Capítulo / Filiação PMI')}</th>
                <th className="px-3 py-2 text-center">{t('comp.affiliationQueue.thVep', 'VEP')}</th>
                <th className="px-3 py-2 text-center">{t('comp.affiliationQueue.thStatus', 'Status')}</th>
                <th className="px-3 py-2 text-center w-24">{t('comp.affiliationQueue.thActions', 'Ações')}</th>
              </tr>
            </thead>
            <tbody>
              {visible.map(r => {
                const f = farol(r, t);
                const br = brChapters(r.pmi_memberships);
                return (
                  <tr key={r.member_id} className="border-t border-[var(--border-default)] hover:bg-[var(--surface-hover)]">
                    <td className="px-3 py-2"><input type="checkbox" checked={selectedIds.has(r.member_id)} onChange={() => toggle(r.member_id)} className="accent-teal-500" /></td>
                    <td className="px-3 py-2">
                      <div className="font-medium text-[var(--text-primary)] flex items-center gap-1.5">
                        {r.name}
                        {r.is_pre_onboarding && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-orange-50 text-orange-600 font-semibold">{t('comp.affiliationQueue.preBadge', 'pré')}</span>}
                      </div>
                      <div className="text-[.7rem] text-[var(--text-muted)]">{r.email}</div>
                    </td>
                    <td className="px-3 py-2">
                      {br.length > 0 ? (
                        <div className="space-y-0.5">
                          {br.map((c, i) => (
                            <div key={i} className="text-[12px] flex items-center gap-1">
                              <span className="font-medium text-[var(--text-primary)]">{c.name}</span>
                              {c.expiry && (
                                <span className={`inline-flex items-center gap-0.5 text-[10px] ${c.expired ? 'text-rose-600' : c.soon ? 'text-amber-600' : 'text-[var(--text-muted)]'}`}>
                                  <CalendarClock size={10} /> {c.expiry}
                                </span>
                              )}
                            </div>
                          ))}
                        </div>
                      ) : (
                        <div className="text-[12px] text-[var(--text-muted)]">
                          {r.chapter || '—'}
                          <span className="text-[10px] text-amber-600 flex items-center gap-0.5"><Info size={10} /> {t('comp.affiliationQueue.noDetail', 'Filiação não pública/não enriquecida — verificar manualmente')}</span>
                        </div>
                      )}
                    </td>
                    <td className="px-3 py-2 text-center">
                      {r.vep_status_raw
                        ? <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-semibold ${VEP_CLS[r.vep_status_raw] || 'bg-slate-100 text-slate-600'}`}>{r.vep_status_raw}</span>
                        : <span className="text-[var(--text-muted)]">—</span>}
                    </td>
                    <td className="px-3 py-2 text-center">
                      <span className={`text-[10px] px-2 py-0.5 rounded-full font-semibold ${f.cls}`} title={f.label}>{f.emoji} {f.label}</span>
                    </td>
                    <td className="px-3 py-2 text-center">
                      <button onClick={() => requireAttest(() => openVerify(r))}
                        className="text-[11px] px-2.5 py-1 rounded-full font-semibold border-0 cursor-pointer bg-emerald-50 text-emerald-700 hover:bg-emerald-100 inline-flex items-center gap-1">
                        <SearchCheck size={12} /> {t('comp.affiliationQueue.verify', 'Verificar')}
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* individual verify modal */}
      {vMember && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={() => setVMember(null)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[460px] overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)]">
              <h3 className="text-base font-bold text-[var(--text-primary)]">{t('comp.affiliationQueue.verifyTitle', 'Verificar filiação de')} {vMember.name}</h3>
              <p className="text-xs text-[var(--text-muted)] mt-0.5">{vMember.chapter || '—'}{vMember.vep_status_raw ? ` · VEP: ${vMember.vep_status_raw}` : ''}</p>
            </div>
            <div className="p-5 space-y-4">
              <label className="flex items-center gap-2 cursor-pointer text-sm text-[var(--text-primary)]">
                <input type="checkbox" checked={vActive} onChange={e => setVActive(e.target.checked)} className="accent-teal-500" />
                {t('comp.affiliationQueue.verifyActiveLabel', 'Filiação PMI ativa')}
              </label>
              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">{t('comp.affiliationQueue.verifyChapterLabel', 'Capítulo (BR) confirmado')}</label>
                <input type="text" value={vChapter} onChange={e => setVChapter(e.target.value)} placeholder={t('comp.affiliationQueue.verifyChapterPh', 'ex.: Goiás, Brazil Chapter')}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]" />
              </div>
              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">{t('comp.affiliationQueue.verifyExpiresLabel', 'Vencimento da filiação')}</label>
                <input type="date" value={vExpires} onChange={e => setVExpires(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]" />
              </div>
              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">{t('comp.affiliationQueue.verifyObsLabel', 'Observação (sobre o resultado)')}</label>
                <textarea value={vObs} maxLength={500} onChange={e => setVObs(e.target.value)} rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)] resize-none" />
                <p className="text-[10px] text-amber-600 mt-1">⚠ {t('comp.affiliationQueue.verifyObsHint', 'Não inclua dados pessoais além do necessário.')}</p>
              </div>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex justify-end gap-2">
              <button onClick={() => setVMember(null)} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.affiliationQueue.cancel', 'Cancelar')}</button>
              <button onClick={handleVerify} disabled={vSaving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                {vSaving ? t('comp.affiliationQueue.verifying', 'Verificando…') : t('comp.affiliationQueue.verifySubmit', 'Registrar verificação')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* F1b confidentiality attestation gate */}
      {showAttest && (
        <div className="fixed inset-0 bg-black/50 z-[110] flex items-center justify-center p-4" onClick={() => setShowAttest(false)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[560px] overflow-hidden flex flex-col" style={{ maxHeight: '90vh' }} onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)] flex-shrink-0">
              <h3 className="text-base font-bold text-[var(--text-primary)]">🔒 {t('comp.affiliationQueue.attestTitle', 'Acesso à verificação de filiação — dados pessoais de terceiros')}</h3>
            </div>
            <div className="p-5 overflow-y-auto flex-1">
              <p className="text-[13px] text-[var(--text-secondary)] whitespace-pre-line leading-relaxed">{t('comp.affiliationQueue.attestBody', 'Você está acessando dados de filiação PMI de terceiros na condição de agente da Diretoria de Filiação. Use exclusivamente para o loop de verificação de filiação; não use para fins próprios; não inclua dados pessoais além do necessário nas observações. Todo acesso é registrado. O ateste é renovado anualmente.')}</p>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex-shrink-0 space-y-3">
              <label className="flex items-start gap-2 cursor-pointer text-sm text-[var(--text-primary)]">
                <input type="checkbox" checked={attestChecked} onChange={e => setAttestChecked(e.target.checked)} className="accent-teal-500 mt-0.5" />
                <span>{t('comp.affiliationQueue.attestCheckbox', 'Declaro estar ciente e de acordo.')}</span>
              </label>
              <div className="flex justify-end gap-2">
                <button onClick={() => setShowAttest(false)} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.affiliationQueue.cancel', 'Cancelar')}</button>
                <button onClick={handleAttest} disabled={!attestChecked || attesting} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                  {attesting ? t('comp.affiliationQueue.attesting', 'Registrando…') : t('comp.affiliationQueue.attestConfirm', 'Confirmar e acessar')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
