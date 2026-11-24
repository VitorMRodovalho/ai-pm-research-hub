import { useEffect, useState, useCallback } from 'react';
import { Loader2, Lock, RefreshCw, ShieldQuestion, CheckCircle2, Undo2, Ban } from 'lucide-react';
import { usePageI18n } from '../../../i18n/usePageI18n';
import { useResolvedMember } from '../../../hooks/useResolvedMember';

/**
 * #3179: acesso à pasta de trabalho que não veio do ledger (compartilhamento manual, herdado, ou anterior ao
 * reconcile) de quem não fica com o acesso pelo roster. O reconcile diário lê a ACL e registra; nada sai sozinho.
 * Leitura: admin_list_drive_folder_access_findings (manage_platform, rls_can_see_initiative). Ação:
 * admin_review_drive_folder_access (manter, reabrir, revogar). Revogar entra no dreno de hora em hora
 * (revoke-drive-drain-hourly). A fronteira é o SECDEF; esta tela é só o casco (ADR-0106).
 */

interface FindingRow {
  id: string;
  permission_email: string;
  permission_role: string | null;
  inherited: boolean | null;
  member_id: string | null;
  member_name: string | null;
  member_status: string | null;
  status: 'open' | 'kept' | 'approved' | 'revoked' | 'already_absent' | 'failed' | 'closed';
  first_seen_at: string;
  last_seen_at: string;
  review_note: string | null;
  google_error: { status?: number; message?: string } | null;
  initiatives: Array<{ id: string; title: string; is_confidential: boolean; linked: boolean }>;
  drive_folder_url: string | null;
  is_confidential: boolean;
  folder_linked: boolean;
}

// #3186: o herdado da pasta de cima não vira item; chega agregado por pasta, sem e-mail.
interface InheritedFolder {
  drive_folder_id: string;
  inherited_count: number;
  unknown_person: number;
  last_seen_at: string;
  initiatives: Array<{ id: string; title: string; is_confidential: boolean }>;
  drive_folder_url: string | null;
  is_confidential: boolean;
}

interface Findings {
  rows: FindingRow[];
  inherited_by_folder?: InheritedFolder[];
  summary: { open: number; kept: number; approved: number; failed: number; unknown_person: number; confidential_open: number;
             inherited?: number; inherited_folders?: number };
}

function fmtDate(s: string | null): string {
  if (!s) return '-';
  try { return new Date(s).toLocaleDateString(); } catch { return '-'; }
}

export default function DriveFolderAccessReviewIsland() {
  const t = usePageI18n();
  const { ready, memberId } = useResolvedMember();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<Findings | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ kind: 'ok' | 'err'; msg: string } | null>(null);

  const getSb = () => (window as any).navGetSb?.();

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    setError(null);
    const { data: d, error: rpcErr } = await sb.rpc('admin_list_drive_folder_access_findings', { p_include_closed: false });
    if (rpcErr) setError(rpcErr.message);
    else setData(d as Findings);
    setLoading(false);
  }, []);

  useEffect(() => { if (memberId) load(); }, [load, memberId]);

  const review = async (r: FindingRow, action: 'keep' | 'reopen' | 'revoke', okMsg: string) => {
    const sb = getSb();
    if (!sb) return;
    setBusy(r.id);
    setNotice(null);
    const { error: rpcErr } = await sb.rpc('admin_review_drive_folder_access',
      { p_finding_id: r.id, p_action: action, p_note: notes[r.id] ?? null });
    setBusy(null);
    if (rpcErr) { setNotice({ kind: 'err', msg: rpcErr.message }); return; }
    setNotice({ kind: 'ok', msg: okMsg });
    setNotes((n) => ({ ...n, [r.id]: '' }));
    load();
  };

  if (ready && !memberId) return null;
  if (loading && !data) {
    return (
      <div className="flex items-center gap-2 text-sm text-[var(--text-muted)] py-6">
        <Loader2 className="w-4 h-4 animate-spin" /> {t('common.loading', 'Carregando...')}
      </div>
    );
  }
  if (error) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
        <p className="font-semibold">{t('driveFolderReview.error', 'Erro ao carregar a revisão de acesso às pastas')}</p>
        <p>{error}</p>
      </div>
    );
  }
  if (!data) return null;
  const s = data.summary;
  const inh = data.inherited_by_folder ?? [];

  return (
    <section className="mt-10 space-y-4" aria-labelledby="drive-folder-review-title">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 id="drive-folder-review-title" className="text-lg font-bold text-[var(--text-primary)] flex items-center gap-2">
            <ShieldQuestion className="w-5 h-5" /> {t('driveFolderReview.title', 'Acesso às pastas fora do registro')}
          </h2>
          <p className="text-sm text-[var(--text-secondary)] max-w-3xl">
            {t('driveFolderReview.subtitle', 'Quem tem acesso a uma pasta de trabalho sem ter vindo da concessão automática e não está no roster de nenhuma iniciativa que usa a pasta. A leitura é diária. Nada sai sozinho: mantenha o acesso legítimo ou peça a revogação, que roda de hora em hora, sem aviso à pessoa.')}
          </p>
        </div>
        <button type="button" onClick={load} className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--border-default)] px-3 py-1.5 text-sm">
          <RefreshCw className="w-4 h-4" /> {t('driveRevocation.refresh', 'Atualizar')}
        </button>
      </div>

      {notice && (
        <div className={`rounded-lg p-3 text-sm ${notice.kind === 'ok' ? 'bg-emerald-50 text-emerald-900' : 'bg-red-50 text-red-800'}`}>{notice.msg}</div>
      )}

      <div className="flex flex-wrap gap-2 text-sm">
        <span className="rounded-full bg-amber-100 text-amber-900 px-3 py-1">{t('driveFolderReview.sumOpen', 'Para revisar')}: {s.open}</span>
        <span className="rounded-full bg-slate-100 text-slate-800 px-3 py-1">{t('driveFolderReview.sumKept', 'Mantidos')}: {s.kept}</span>
        <span className="rounded-full bg-blue-100 text-blue-900 px-3 py-1">{t('driveRevocation.sumApproved', 'Aprovados')}: {s.approved}</span>
        <span className="rounded-full bg-red-100 text-red-800 px-3 py-1">{t('driveRevocation.sumFailed', 'Falhas')}: {s.failed}</span>
        <span className="rounded-full bg-slate-100 text-slate-800 px-3 py-1">{t('driveFolderReview.sumUnknown', 'Fora do cadastro')}: {s.unknown_person}</span>
        <span className="rounded-full bg-purple-100 text-purple-900 px-3 py-1">{t('driveRevocation.sumConfidential', 'Confidenciais abertos')}: {s.confidential_open}</span>
        <span className="rounded-full bg-slate-100 text-slate-800 px-3 py-1">{t('driveFolderReview.sumInherited', 'Herdados da pasta de cima')}: {s.inherited ?? 0}</span>
      </div>

      {data.rows.length === 0 ? (
        <p className="text-sm text-[var(--text-muted)]">{t('driveFolderReview.empty', 'Nenhum acesso fora do registro.')}</p>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
          <table className="w-full text-sm">
            <thead className="bg-[var(--surface-section-cool)]">
              <tr>
                <th className="text-left px-3 py-2">{t('driveFolderReview.colFolder', 'Pasta de')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colPerson', 'Pessoa')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colStatus', 'Estado')}</th>
                <th className="text-left px-3 py-2">{t('driveFolderReview.colSeen', 'Visto em')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colActions', 'Ações')}</th>
              </tr>
            </thead>
            <tbody>
              {data.rows.map((r) => {
                const note = notes[r.id] ?? '';
                const canRevoke = ['open', 'kept', 'failed'].includes(r.status) && r.inherited !== true;
                return (
                  <tr key={r.id} className="border-t border-[var(--border-subtle)] align-top">
                    <td className="px-3 py-2">
                      {r.initiatives.map((i) => (
                        <span key={i.id} className="flex items-center gap-1">
                          {i.is_confidential && <Lock className="w-3.5 h-3.5 text-purple-700" aria-label={t('driveRevocation.confidential', 'confidencial')} />}
                          {r.drive_folder_url ? <a href={r.drive_folder_url} target="_blank" rel="noopener noreferrer" className="underline">{i.title}</a> : i.title}
                        </span>
                      ))}
                      {!r.folder_linked && <span className="block text-xs text-[var(--text-muted)]">{t('driveFolderReview.unlinked', 'pasta já desvinculada')}</span>}
                    </td>
                    <td className="px-3 py-2">
                      <span className="block">{r.member_name ?? t('driveFolderReview.unknownPerson', 'fora do cadastro')}</span>
                      <span className="block text-xs text-[var(--text-muted)]">
                        {r.permission_email}{r.permission_role ? ` · ${t(`driveFolderReview.role.${r.permission_role}`, r.permission_role)}` : ''}{r.member_status && r.member_status !== 'active' ? ` · ${r.member_status}` : ''}
                      </span>
                      {r.inherited === true && <span className="block text-xs text-amber-800">{t('driveFolderReview.inherited', 'Herdado da pasta-mãe: só sai lá.')}</span>}
                    </td>
                    <td className="px-3 py-2">
                      <span className="block">{t(`driveFolderReview.st.${r.status}`, r.status)}</span>
                      {r.review_note && <span className="block text-xs text-[var(--text-muted)]">{r.review_note}</span>}
                      {r.status === 'failed' && r.google_error && (
                        <span className="block text-xs text-red-700">{r.google_error.status ?? ''} {(r.google_error.message ?? '').slice(0, 120)}</span>
                      )}
                    </td>
                    <td className="px-3 py-2">{fmtDate(r.first_seen_at)}</td>
                    <td className="px-3 py-2 space-y-1.5 min-w-[16rem]">
                      {r.status !== 'approved' && (
                        <input type="text" value={note} onChange={(e) => setNotes((n) => ({ ...n, [r.id]: e.target.value }))}
                          placeholder={t('driveFolderReview.notePlaceholder', 'Motivo (obrigatório para manter ou revogar)')}
                          className="w-full rounded border border-[var(--border-default)] px-2 py-1 text-xs bg-[var(--surface-card)]" />
                      )}
                      <div className="flex flex-wrap gap-1.5">
                        {(r.status === 'open' || r.status === 'failed') && (
                          <button type="button" disabled={busy === r.id || !note.trim()}
                            onClick={() => review(r, 'keep', t('driveFolderReview.okKept', 'Mantido: o acesso fica e o item sai da revisão.'))}
                            className="inline-flex items-center gap-1 rounded border border-[var(--border-default)] px-2 py-1 text-xs disabled:opacity-50">
                            <CheckCircle2 className="w-3.5 h-3.5" /> {t('driveFolderReview.keep', 'Manter')}
                          </button>
                        )}
                        {r.status === 'kept' && (
                          <button type="button" disabled={busy === r.id}
                            onClick={() => review(r, 'reopen', t('driveFolderReview.okReopened', 'Reaberto para revisão.'))}
                            className="inline-flex items-center gap-1 rounded border border-[var(--border-default)] px-2 py-1 text-xs disabled:opacity-50">
                            <Undo2 className="w-3.5 h-3.5" /> {t('driveFolderReview.reopen', 'Reabrir')}
                          </button>
                        )}
                        {canRevoke && (
                          <button type="button" disabled={busy === r.id || !note.trim()}
                            onClick={() => review(r, 'revoke', t('driveRevocation.okApproved', 'Aprovado: o acesso sai em até 1 hora.'))}
                            className="inline-flex items-center gap-1 rounded bg-red-600 text-white px-2 py-1 text-xs disabled:opacity-50">
                            <Ban className="w-3.5 h-3.5" /> {t('driveRevocation.adhocRevoke', 'Revogar')}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {inh.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-semibold text-[var(--text-primary)]">{t('driveFolderReview.inheritedTitle', 'Herdado da pasta de cima')}</h3>
          <p className="text-xs text-[var(--text-secondary)] max-w-3xl">
            {t('driveFolderReview.inheritedHint', 'Permissões que a pasta de trabalho herda da pasta de cima, de quem não tem concessão nem está no roster. Não viram item, porque aqui não se revogam: a decisão é na pasta de cima, no Drive.')}
          </p>
          <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
            <table className="w-full text-sm">
              <thead className="bg-[var(--surface-section-cool)]">
                <tr>
                  <th className="text-left px-3 py-2">{t('driveFolderReview.colFolder', 'Pasta de')}</th>
                  <th className="text-left px-3 py-2">{t('driveFolderReview.colInherited', 'Herdadas')}</th>
                  <th className="text-left px-3 py-2">{t('driveFolderReview.sumUnknown', 'Fora do cadastro')}</th>
                  <th className="text-left px-3 py-2">{t('driveFolderReview.colSeen', 'Visto em')}</th>
                </tr>
              </thead>
              <tbody>
                {inh.map((f) => (
                  <tr key={f.drive_folder_id} className="border-t border-[var(--border-subtle)] align-top">
                    <td className="px-3 py-2">
                      {f.initiatives.map((i) => (
                        <span key={i.id} className="flex items-center gap-1">
                          {i.is_confidential && <Lock className="w-3.5 h-3.5 text-purple-700" aria-label={t('driveRevocation.confidential', 'confidencial')} />}
                          {f.drive_folder_url ? <a href={f.drive_folder_url} target="_blank" rel="noopener noreferrer" className="underline">{i.title}</a> : i.title}
                        </span>
                      ))}
                    </td>
                    <td className="px-3 py-2">{f.inherited_count}</td>
                    <td className="px-3 py-2">{f.unknown_person}</td>
                    <td className="px-3 py-2">{fmtDate(f.last_seen_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  );
}
