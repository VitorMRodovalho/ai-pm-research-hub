import { useEffect, useState, useCallback } from 'react';
import { Loader2, AlertTriangle, Lock, RefreshCw, PauseCircle, PlayCircle, Undo2, CheckCircle2, Ban } from 'lucide-react';
import { usePageI18n } from '../../../i18n/usePageI18n';
import { useResolvedMember } from '../../../hooks/useResolvedMember';

/**
 * #3147: fila de revogação do acesso ao Drive por fim do vínculo com a iniciativa, na mesma página da fila de
 * desligamento (ADR-0107). Leitura: admin_list_drive_revocation_queue (manage_platform), que devolve as duas filas.
 * Ações: segurar ou soltar, desfazer, aprovar já e a revogação avulsa. O executor é o dreno de hora em hora
 * (revoke-drive-drain-hourly). A fronteira é o SECDEF; esta tela é só o casco (ADR-0106).
 */

interface QueueRow {
  id: string;
  grant_id: string;
  initiative_title: string;
  is_confidential: boolean;
  member_name: string | null;
  member_status: string | null;
  permission_email: string | null;
  drive_folder_url: string | null;
  reason: 'engagement_ended' | 'manual';
  status: 'pending' | 'approved' | 'revoked' | 'already_absent' | 'failed' | 'cancelled';
  detected_at: string;
  notified_at: string | null;
  due_at: string | null;
  held_at: string | null;
  hold_note: string | null;
  approval_mode: string | null;
  google_error: { status?: number; message?: string } | null;
  cancel_reason: string | null;
}

interface OffbRow {
  id: string;
  member_name: string;
  member_status: string;
  drive_file_name: string | null;
  status: string;
  detected_at: string;
}

interface Queue {
  enabled: boolean;
  notice_days: number;
  rows: QueueRow[];
  offboarding_open: OffbRow[];
  summary: { pending: number; held: number; approved: number; failed: number; confidential_open: number; offboarding_open: number };
}

interface GrantRow {
  id: string;
  initiative_title: string;
  grantee_name: string | null;
  permission_email: string | null;
  status: string;
}

function fmtDate(s: string | null): string {
  if (!s) return '-';
  try { return new Date(s).toLocaleDateString(); } catch { return '-'; }
}

export default function DriveMembershipRevocationIsland() {
  const t = usePageI18n();
  // #2974: a primeira chamada espera o membro resolvido, sem laço próprio
  const { ready, memberId } = useResolvedMember();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [queue, setQueue] = useState<Queue | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ kind: 'ok' | 'err'; msg: string } | null>(null);
  const [grants, setGrants] = useState<GrantRow[] | null>(null);
  const [grantFilter, setGrantFilter] = useState('');

  const getSb = () => (window as any).navGetSb?.();

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    setError(null);
    const { data, error: rpcErr } = await sb.rpc('admin_list_drive_revocation_queue', { p_include_closed: false });
    if (rpcErr) setError(rpcErr.message);
    else setQueue(data as Queue);
    setLoading(false);
  }, []);

  useEffect(() => { if (memberId) load(); }, [load, memberId]);

  const act = async (key: string, rpc: string, args: Record<string, unknown>, okMsg: string) => {
    const sb = getSb();
    if (!sb) return;
    setBusy(key);
    setNotice(null);
    const { error: rpcErr } = await sb.rpc(rpc, args);
    setBusy(null);
    if (rpcErr) { setNotice({ kind: 'err', msg: rpcErr.message }); return; }
    setNotice({ kind: 'ok', msg: okMsg });
    setNotes((n) => ({ ...n, [key]: '' }));
    load();
  };

  const loadGrants = async () => {
    const sb = getSb();
    if (!sb) return;
    const { data, error: rpcErr } = await sb.rpc('admin_list_membership_drive_grants',
      { p_status: 'granted', p_initiative_id: null, p_limit: 200, p_offset: 0 });
    if (rpcErr) { setNotice({ kind: 'err', msg: rpcErr.message }); return; }
    setGrants((data ?? []) as GrantRow[]);
  };

  if (ready && !memberId) return null;
  if (loading && !queue) {
    return (
      <div className="flex items-center gap-2 text-sm text-[var(--text-muted)] py-6">
        <Loader2 className="w-4 h-4 animate-spin" /> {t('common.loading', 'Carregando...')}
      </div>
    );
  }
  if (error) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
        <p className="font-semibold">{t('driveRevocation.error', 'Erro ao carregar a fila de revogação')}</p>
        <p>{error}</p>
      </div>
    );
  }
  if (!queue) return null;

  const s = queue.summary;
  const statusLabel = (r: QueueRow) => {
    if (r.status === 'pending' && r.held_at) return t('driveRevocation.stHeld', 'segurado');
    return t(`driveRevocation.st.${r.status}`, r.status);
  };
  const filteredGrants = (grants ?? []).filter((g) => {
    const q = grantFilter.trim().toLowerCase();
    if (!q) return true;
    return [g.initiative_title, g.grantee_name, g.permission_email].some((v) => (v ?? '').toLowerCase().includes(q));
  });

  return (
    <section className="mt-10 space-y-4" aria-labelledby="drive-revocation-title">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 id="drive-revocation-title" className="text-lg font-bold text-[var(--text-primary)]">
            {t('driveRevocation.title', 'Fim do vínculo com a iniciativa')}
          </h2>
          <p className="text-sm text-[var(--text-secondary)] max-w-3xl">
            {t('driveRevocation.subtitle', 'Acesso à pasta da iniciativa de quem saiu do roster dela. A pessoa é avisada e o acesso sai em {n} dias; em iniciativa confidencial, sai no ciclo seguinte. Quem tem gestão da plataforma não entra na fila. A execução roda de hora em hora.').replace('{n}', String(queue.notice_days))}
          </p>
        </div>
        <button type="button" onClick={load} className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--border-default)] px-3 py-1.5 text-sm">
          <RefreshCw className="w-4 h-4" /> {t('driveRevocation.refresh', 'Atualizar')}
        </button>
      </div>

      {!queue.enabled && (
        <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900 flex gap-2">
          <PauseCircle className="w-4 h-4 mt-0.5 shrink-0" />
          <span>{t('driveRevocation.disabled', 'A revogação automática está desligada: a fila se forma, mas ninguém é avisado nem revogado. Aprovar um item à mão executa só aquele item.')}</span>
        </div>
      )}

      {notice && (
        <div className={`rounded-lg p-3 text-sm ${notice.kind === 'ok' ? 'bg-emerald-50 text-emerald-900' : 'bg-red-50 text-red-800'}`}>{notice.msg}</div>
      )}

      <div className="flex flex-wrap gap-2 text-sm">
        <span className="rounded-full bg-amber-100 text-amber-900 px-3 py-1">{t('driveRevocation.sumPending', 'Pendentes')}: {s.pending}</span>
        <span className="rounded-full bg-slate-100 text-slate-800 px-3 py-1">{t('driveRevocation.sumHeld', 'Segurados')}: {s.held}</span>
        <span className="rounded-full bg-blue-100 text-blue-900 px-3 py-1">{t('driveRevocation.sumApproved', 'Aprovados')}: {s.approved}</span>
        <span className="rounded-full bg-red-100 text-red-800 px-3 py-1">{t('driveRevocation.sumFailed', 'Falhas')}: {s.failed}</span>
        <span className="rounded-full bg-purple-100 text-purple-900 px-3 py-1">{t('driveRevocation.sumConfidential', 'Confidenciais abertos')}: {s.confidential_open}</span>
        <span className="rounded-full bg-slate-100 text-slate-800 px-3 py-1">{t('driveRevocation.sumOffboarding', 'Fila de desligamento aberta')}: {s.offboarding_open}</span>
      </div>

      {queue.rows.length === 0 ? (
        <p className="text-sm text-[var(--text-muted)]">{t('driveRevocation.empty', 'Nenhum acesso na fila.')}</p>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
          <table className="w-full text-sm">
            <thead className="bg-[var(--surface-section-cool)]">
              <tr>
                <th className="text-left px-3 py-2">{t('driveRevocation.colInitiative', 'Iniciativa')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colPerson', 'Pessoa')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colReason', 'Motivo')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colStatus', 'Estado')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colDue', 'Prazo')}</th>
                <th className="text-left px-3 py-2">{t('driveRevocation.colActions', 'Ações')}</th>
              </tr>
            </thead>
            <tbody>
              {queue.rows.map((r) => {
                const note = notes[r.id] ?? '';
                const pending = r.status === 'pending';
                return (
                  <tr key={r.id} className="border-t border-[var(--border-subtle)] align-top">
                    <td className="px-3 py-2">
                      <span className="inline-flex items-center gap-1">
                        {r.is_confidential && <Lock className="w-3.5 h-3.5 text-purple-700" aria-label={t('driveRevocation.confidential', 'confidencial')} />}
                        {r.initiative_title}
                      </span>
                    </td>
                    <td className="px-3 py-2">
                      <span className="block">{r.member_name ?? '-'}</span>
                      <span className="block text-xs text-[var(--text-muted)]">{r.permission_email ?? ''}{r.member_status && r.member_status !== 'active' ? ` · ${r.member_status}` : ''}</span>
                    </td>
                    <td className="px-3 py-2">{t(`driveRevocation.reason.${r.reason}`, r.reason)}</td>
                    <td className="px-3 py-2">
                      <span className="block">{statusLabel(r)}{r.approval_mode === 'auto' ? ` (${t('driveRevocation.auto', 'automático')})` : ''}</span>
                      {r.held_at && <span className="block text-xs text-[var(--text-muted)]">{r.hold_note}</span>}
                      {r.status === 'failed' && r.google_error && (
                        <span className="block text-xs text-red-700">{r.google_error.status ?? ''} {(r.google_error.message ?? '').slice(0, 120)}</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      {r.due_at ? fmtDate(r.due_at) : (pending ? t('driveRevocation.notNotified', 'sem aviso ainda') : '-')}
                    </td>
                    <td className="px-3 py-2 space-y-1.5 min-w-[16rem]">
                      {(pending || r.status === 'approved') && (
                        <input
                          type="text"
                          value={note}
                          onChange={(e) => setNotes((n) => ({ ...n, [r.id]: e.target.value }))}
                          placeholder={t('driveRevocation.notePlaceholder', 'Motivo (obrigatório para segurar ou desfazer)')}
                          className="w-full rounded border border-[var(--border-default)] px-2 py-1 text-xs bg-[var(--surface-card)]"
                        />
                      )}
                      <div className="flex flex-wrap gap-1.5">
                        {pending && (
                          <button type="button" disabled={busy === r.id}
                            onClick={() => act(r.id, 'admin_approve_drive_membership_revocation', { p_revocation_id: r.id }, t('driveRevocation.okApproved', 'Aprovado: o acesso sai em até 1 hora.'))}
                            className="inline-flex items-center gap-1 rounded bg-blue-600 text-white px-2 py-1 text-xs disabled:opacity-50">
                            <CheckCircle2 className="w-3.5 h-3.5" /> {t('driveRevocation.approveNow', 'Revogar já')}
                          </button>
                        )}
                        {pending && !r.held_at && (
                          <button type="button" disabled={busy === r.id || !note.trim()}
                            onClick={() => act(r.id, 'admin_hold_drive_revocation', { p_revocation_id: r.id, p_hold: true, p_note: note }, t('driveRevocation.okHeld', 'Item segurado.'))}
                            className="inline-flex items-center gap-1 rounded border border-[var(--border-default)] px-2 py-1 text-xs disabled:opacity-50">
                            <PauseCircle className="w-3.5 h-3.5" /> {t('driveRevocation.hold', 'Segurar')}
                          </button>
                        )}
                        {pending && r.held_at && (
                          <button type="button" disabled={busy === r.id}
                            onClick={() => act(r.id, 'admin_hold_drive_revocation', { p_revocation_id: r.id, p_hold: false, p_note: null }, t('driveRevocation.okReleased', 'Item solto: volta ao prazo.'))}
                            className="inline-flex items-center gap-1 rounded border border-[var(--border-default)] px-2 py-1 text-xs disabled:opacity-50">
                            <PlayCircle className="w-3.5 h-3.5" /> {t('driveRevocation.release', 'Soltar')}
                          </button>
                        )}
                        {(pending || r.status === 'approved') && (
                          <button type="button" disabled={busy === r.id || !note.trim()}
                            onClick={() => act(r.id, 'admin_cancel_drive_revocation', { p_revocation_id: r.id, p_note: note }, t('driveRevocation.okCancelled', 'Desfeito: o acesso fica.'))}
                            className="inline-flex items-center gap-1 rounded border border-red-300 text-red-700 px-2 py-1 text-xs disabled:opacity-50">
                            <Undo2 className="w-3.5 h-3.5" /> {t('driveRevocation.cancel', 'Desfazer')}
                          </button>
                        )}
                        {r.status === 'failed' && (
                          <button type="button" disabled={busy === r.id || !note.trim()}
                            onClick={() => act(r.id, 'admin_request_drive_revocation', { p_grant_id: r.grant_id, p_note: note }, t('driveRevocation.okRetry', 'Nova tentativa aprovada.'))}
                            className="inline-flex items-center gap-1 rounded border border-[var(--border-default)] px-2 py-1 text-xs disabled:opacity-50">
                            <RefreshCw className="w-3.5 h-3.5" /> {t('driveRevocation.retry', 'Tentar de novo')}
                          </button>
                        )}
                      </div>
                      {r.status === 'failed' && (
                        <input type="text" value={note} onChange={(e) => setNotes((n) => ({ ...n, [r.id]: e.target.value }))}
                          placeholder={t('driveRevocation.notePlaceholder', 'Motivo (obrigatório para segurar ou desfazer)')}
                          className="w-full rounded border border-[var(--border-default)] px-2 py-1 text-xs bg-[var(--surface-card)]" />
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {queue.offboarding_open.length > 0 && (
        <div className="rounded-xl border border-[var(--border-default)] p-3 text-sm">
          <p className="font-semibold mb-2 flex items-center gap-1.5"><AlertTriangle className="w-4 h-4 text-amber-600" /> {t('driveRevocation.offbTitle', 'Fila de desligamento ainda aberta')}</p>
          <ul className="space-y-1">
            {queue.offboarding_open.map((o) => (
              <li key={o.id}>{o.member_name} · {o.drive_file_name ?? '-'} · {t(`driveRevocation.offbSt.${o.status}`, o.status)} · {fmtDate(o.detected_at)}</li>
            ))}
          </ul>
          <p className="text-xs text-[var(--text-muted)] mt-2">{t('driveRevocation.offbHint', 'Essa fila é aprovada no painel de desligamento acima.')}</p>
        </div>
      )}

      <div className="rounded-xl border border-[var(--border-default)] p-3 text-sm space-y-2">
        <p className="font-semibold flex items-center gap-1.5"><Ban className="w-4 h-4" /> {t('driveRevocation.adhocTitle', 'Revogação avulsa')}</p>
        <p className="text-xs text-[var(--text-muted)]">{t('driveRevocation.adhocHint', 'Revoga um acesso vivo fora do ciclo, de membro ativo ou não. Entra aprovado e sai em até 1 hora, sem aviso à pessoa.')}</p>
        {grants === null ? (
          <button type="button" onClick={loadGrants} className="rounded border border-[var(--border-default)] px-3 py-1 text-xs">
            {t('driveRevocation.adhocLoad', 'Listar acessos ativos')}
          </button>
        ) : (
          <>
            <input type="search" value={grantFilter} onChange={(e) => setGrantFilter(e.target.value)}
              placeholder={t('driveRevocation.adhocFilter', 'Filtrar por iniciativa, nome ou e-mail')}
              className="w-full rounded border border-[var(--border-default)] px-2 py-1 text-xs bg-[var(--surface-card)]" />
            <ul className="max-h-72 overflow-y-auto divide-y divide-[var(--border-subtle)]">
              {filteredGrants.slice(0, 50).map((g) => {
                const key = `g:${g.id}`;
                const note = notes[key] ?? '';
                return (
                  <li key={g.id} className="py-1.5 flex flex-wrap items-center gap-2">
                    <span className="flex-1 min-w-[12rem]">{g.initiative_title} · {g.grantee_name ?? '-'} <span className="text-xs text-[var(--text-muted)]">{g.permission_email}</span></span>
                    <input type="text" value={note} onChange={(e) => setNotes((n) => ({ ...n, [key]: e.target.value }))}
                      placeholder={t('driveRevocation.adhocNote', 'Motivo')}
                      className="w-40 rounded border border-[var(--border-default)] px-2 py-1 text-xs bg-[var(--surface-card)]" />
                    <button type="button" disabled={busy === key || !note.trim()}
                      onClick={() => act(key, 'admin_request_drive_revocation', { p_grant_id: g.id, p_note: note }, t('driveRevocation.okApproved', 'Aprovado: o acesso sai em até 1 hora.'))}
                      className="rounded bg-red-600 text-white px-2 py-1 text-xs disabled:opacity-50">
                      {t('driveRevocation.adhocRevoke', 'Revogar')}
                    </button>
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </div>
    </section>
  );
}
