import { useEffect, useState, useCallback } from 'react';
import {
  Loader2, AlertTriangle, HardDrive, CheckCircle2, Clock, ShieldAlert,
  ChevronDown, ChevronRight, RefreshCw,
} from 'lucide-react';
import { usePageI18n } from '../../../i18n/usePageI18n';

/**
 * /admin/members/drive-teardown — #1026 Fatia C (+ Fatia B provenance, #1039).
 * Makes the (previously UI-less, LL#588) Drive-offboarding queue visible to the GP:
 *   - get_drive_teardown_overview() → per-member rollup (attested-clean / needs-action / not-scanned)
 *   - drill-down per member via admin_list_drive_revocation_audit
 *   - manual approve via bulk_approve_drive_revocations (inactive lane; drains via cron 64 ≤1h)
 *   - #1039: alumni rows are auto-approved (approval_mode='auto') when the kill-switch
 *     site_config drive_auto_revoke_enabled is on — the panel shows in-flight autos and the
 *     skipped exception lane (owner_permission | member_reactivated). GP cannot pause the
 *     switch (superadmin-only site_config write) — see DRIVE_OFFBOARDING_CASCADE.md.
 */

interface MemberRow {
  member_id: string;
  name: string;
  member_status: string;
  offboarded_at: string | null;
  latest_scan_at: string | null;
  latest_grants_found: number | null;
  latest_scan_source: string | null;
  pending_revoke: number;
  approved: number;
  auto_approved: number;
  revoked: number;
  already_absent: number;
  failed: number;
  skipped: number;
  open_count: number;
  scanned: boolean;
  verified_clean: boolean;
  verified_clean_at: string | null;
  bucket: 'needs_action' | 'attested_clean' | 'not_scanned';
}

interface Summary {
  total_offboarded: number;
  attested_clean: number;
  needs_action: number;
  not_scanned: number;
  open_pending: number;
  open_approved: number;
  auto_approved: number;
  open_failed: number;
}

interface Grant {
  id: string;
  permission_email: string | null;
  drive_file_name: string | null;
  drive_file_url: string | null;
  permission_role: string | null;
  status: string;
  approval_mode: string | null;
  skip_reason: string | null;
  detected_at: string | null;
}

function fmtDate(s: string | null): string {
  if (!s) return '—';
  try { return new Date(s).toLocaleDateString(); } catch { return '—'; }
}

export default function DriveTeardownIsland() {
  const t = usePageI18n();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [grants, setGrants] = useState<Record<string, Grant[]>>({});
  const [grantsLoading, setGrantsLoading] = useState<string | null>(null);
  const [approving, setApproving] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ kind: 'ok' | 'err'; msg: string } | null>(null);

  const getSb = () => (window as any).navGetSb?.();

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 300); return; }
    setLoading(true);
    setError(null);
    const { data, error: rpcErr } = await sb.rpc('get_drive_teardown_overview');
    if (rpcErr) { setError(rpcErr.message); setLoading(false); return; }
    setSummary(data?.summary ?? null);
    setMembers(Array.isArray(data?.members) ? data.members : []);
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  const toggleDrill = useCallback(async (memberId: string) => {
    if (expanded === memberId) { setExpanded(null); return; }
    setExpanded(memberId);
    if (grants[memberId]) return; // cached
    const sb = getSb();
    if (!sb) return;
    setGrantsLoading(memberId);
    const { data, error: rpcErr } = await sb.rpc('admin_list_drive_revocation_audit', {
      p_status: null, p_member_id: memberId, p_limit: 200, p_offset: 0,
    });
    setGrantsLoading(null);
    if (rpcErr) { setNotice({ kind: 'err', msg: rpcErr.message }); return; }
    setGrants((g) => ({ ...g, [memberId]: (data?.rows ?? []) as Grant[] }));
  }, [expanded, grants]);

  const approve = useCallback(async (memberId: string, pending: number) => {
    const sb = getSb();
    if (!sb) return;
    setApproving(memberId);
    setNotice(null);
    const { error: rpcErr } = await sb.rpc('bulk_approve_drive_revocations', { p_member_id: memberId });
    setApproving(null);
    if (rpcErr) { setNotice({ kind: 'err', msg: rpcErr.message }); return; }
    setNotice({ kind: 'ok', msg: t('driveTeardown.approveOk', 'Revogação aprovada — será executada em até 1h (cron).').replace('{n}', String(pending)) });
    setGrants((g) => { const c = { ...g }; delete c[memberId]; return c; }); // invalidate drill-down cache
    await load();
  }, [load, t]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-16 text-sm text-[var(--text-muted)]">
        <Loader2 className="w-4 h-4 mr-2 animate-spin" />
        {t('common.loading', 'Carregando...')}
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-2xl p-6 flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-red-600 mt-0.5 shrink-0" />
        <div>
          <p className="font-semibold text-red-800 text-sm">{t('driveTeardown.error', 'Erro ao carregar o painel de teardown')}</p>
          <p className="text-xs text-red-700 mt-1">{error}</p>
        </div>
      </div>
    );
  }

  const s = summary;

  return (
    <div className="space-y-6">
      <header className="space-y-2 flex items-start justify-between gap-4">
        <div className="space-y-2">
          <h1 className="text-2xl font-extrabold text-navy flex items-center gap-2">
            <HardDrive className="w-6 h-6 text-orange" />
            {t('driveTeardown.title', 'Teardown de Acesso ao Drive')}
          </h1>
          <p className="text-sm text-[var(--text-secondary)] max-w-3xl">
            {t('driveTeardown.subtitle', 'Estado de revogação de acesso ao Google Drive por membro desligado. A detecção é disparada no desligamento; alumni são auto-aprovados quando o auto-revoke está ativo (#1039), inactive permanece com aprovação manual. Execução via cron em até 1h.')}
          </p>
        </div>
        <button
          onClick={load}
          className="shrink-0 inline-flex items-center gap-1.5 text-xs font-semibold text-[var(--text-secondary)] border border-[var(--border-default)] rounded-lg px-3 py-1.5 hover:bg-[var(--surface-hover)]"
        >
          <RefreshCw className="w-3.5 h-3.5" />
          {t('driveTeardown.refresh', 'Atualizar')}
        </button>
      </header>

      {notice && (
        <div className={`rounded-2xl p-4 text-sm flex items-start gap-2 ${notice.kind === 'ok' ? 'bg-emerald-50 border border-emerald-200 text-emerald-800' : 'bg-red-50 border border-red-200 text-red-800'}`}>
          {notice.kind === 'ok' ? <CheckCircle2 className="w-4 h-4 mt-0.5 shrink-0" /> : <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />}
          <span>{notice.msg}</span>
        </div>
      )}

      {s && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <StatCard label={t('driveTeardown.statTotal', 'Desligados')} value={s.total_offboarded} tone="neutral" />
          <StatCard label={t('driveTeardown.statNeedsAction', 'Requerem ação')} value={s.needs_action} tone="amber" icon={<Clock className="w-4 h-4" />} />
          <StatCard label={t('driveTeardown.statClean', 'Atestados limpos')} value={s.attested_clean} tone="emerald" icon={<CheckCircle2 className="w-4 h-4" />} />
          <StatCard label={t('driveTeardown.statNotScanned', 'Sem atestação')} value={s.not_scanned} tone="slate" />
        </div>
      )}

      {s && s.auto_approved > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-2xl p-3 text-xs text-blue-800 flex items-center gap-2">
          <Clock className="w-3.5 h-3.5 shrink-0" />
          <span>{t('driveTeardown.autoInFlight', '{n} aprovação(ões) automática(s) de alumni em execução — a revogação roda via cron em até 1h. Não é necessária ação manual.').replace('{n}', String(s.auto_approved))}</span>
        </div>
      )}

      {members.length === 0 ? (
        <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-8 text-center">
          <CheckCircle2 className="w-8 h-8 mx-auto text-emerald-600 mb-2" />
          <p className="font-semibold text-emerald-900">{t('driveTeardown.empty', 'Nenhum membro desligado no momento')}</p>
        </div>
      ) : (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-[var(--surface-base)] border-b border-[var(--border-default)]">
              <tr>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('driveTeardown.colMember', 'Membro')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('driveTeardown.colStatus', 'Status')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('driveTeardown.colQueue', 'Fila')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('driveTeardown.colLastScan', 'Última verificação')}</th>
                <th className="px-4 py-2.5 w-40"></th>
              </tr>
            </thead>
            <tbody>
              {members.map((m) => {
                const isOpen = expanded === m.member_id;
                return (
                  <>
                    <tr key={m.member_id} className="border-b border-[var(--border-subtle)] last:border-0 hover:bg-[var(--surface-hover)]">
                      <td className="px-4 py-3">
                        <button onClick={() => toggleDrill(m.member_id)} className="inline-flex items-center gap-1.5 font-medium text-[var(--text-primary)] hover:text-orange">
                          {isOpen ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                          {m.name}
                        </button>
                        <span className="block text-xs text-[var(--text-muted)] ml-5">{t(`driveTeardown.mstatus.${m.member_status}`, m.member_status)} · {fmtDate(m.offboarded_at)}</span>
                      </td>
                      <td className="px-4 py-3"><BucketBadge bucket={m.bucket} t={t} /></td>
                      <td className="px-4 py-3">
                        <div className="flex flex-wrap gap-1">
                          {m.pending_revoke > 0 && <Pill tone="amber">{t('driveTeardown.stPending', 'pendente')}: {m.pending_revoke}</Pill>}
                          {m.approved > 0 && <Pill tone="blue">{t('driveTeardown.stApproved', 'aprovado')}: {m.approved}{m.auto_approved > 0 ? ` (${t('driveTeardown.autoShort', 'auto')}: ${m.auto_approved})` : ''}</Pill>}
                          {m.failed > 0 && <Pill tone="red">{t('driveTeardown.stFailed', 'falha')}: {m.failed}</Pill>}
                          {m.revoked > 0 && <Pill tone="emerald">{t('driveTeardown.stRevoked', 'revogado')}: {m.revoked}</Pill>}
                          {m.already_absent > 0 && <Pill tone="slate">{t('driveTeardown.stAbsent', 'ausente')}: {m.already_absent}</Pill>}
                          {m.skipped > 0 && <Pill tone="slate">{t('driveTeardown.stSkipped', 'ignorado')}: {m.skipped}</Pill>}
                          {m.open_count === 0 && m.revoked === 0 && m.already_absent === 0 && m.skipped === 0 && <span className="text-xs text-[var(--text-muted)]">—</span>}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-[var(--text-secondary)] text-xs">
                        {m.scanned ? (
                          <span>{fmtDate(m.latest_scan_at)}{m.latest_scan_source ? <span className="text-[var(--text-muted)]"> · {m.latest_scan_source}</span> : null}</span>
                        ) : (
                          <span className="text-[var(--text-muted)]">{t('driveTeardown.neverScanned', 'nunca verificado')}</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {m.pending_revoke > 0 && (
                          <button
                            onClick={() => approve(m.member_id, m.pending_revoke)}
                            disabled={approving === m.member_id}
                            className="inline-flex items-center gap-1 text-xs font-semibold text-white bg-orange rounded-lg px-3 py-1.5 hover:opacity-90 disabled:opacity-50"
                          >
                            {approving === m.member_id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : null}
                            {t('driveTeardown.approve', 'Aprovar revogação')}
                          </button>
                        )}
                      </td>
                    </tr>
                    {isOpen && (
                      <tr key={`${m.member_id}-drill`} className="bg-[var(--surface-base)]">
                        <td colSpan={5} className="px-6 py-3">
                          {grantsLoading === m.member_id ? (
                            <div className="flex items-center gap-2 text-xs text-[var(--text-muted)] py-2">
                              <Loader2 className="w-3.5 h-3.5 animate-spin" /> {t('common.loading', 'Carregando...')}
                            </div>
                          ) : (grants[m.member_id]?.length ?? 0) === 0 ? (
                            <p className="text-xs text-[var(--text-muted)] py-2 flex items-center gap-1.5">
                              <ShieldAlert className="w-3.5 h-3.5" />
                              {t('driveTeardown.noGrants', 'Nenhuma permissão de Drive registrada para este membro.')}
                            </p>
                          ) : (
                            <div className="space-y-1.5 py-1">
                              {grants[m.member_id].map((g) => (
                                <div key={g.id} className="flex items-center justify-between gap-3 text-xs border-b border-[var(--border-subtle)] last:border-0 pb-1.5">
                                  <div className="min-w-0">
                                    <span className="font-medium text-[var(--text-primary)]">{g.drive_file_name || g.drive_file_id || '—'}</span>
                                    <span className="text-[var(--text-muted)] ml-2">{g.permission_email} · {g.permission_role}</span>
                                  </div>
                                  <Pill tone={g.status === 'revoked' ? 'emerald' : g.status === 'pending_revoke' ? 'amber' : g.status === 'approved' ? 'blue' : g.status === 'failed' ? 'red' : 'slate'}>
                                    {g.status}
                                    {g.approval_mode === 'auto' ? ` · ${t('driveTeardown.autoShort', 'auto')}` : ''}
                                    {g.status === 'skipped' && g.skip_reason ? ` · ${g.skip_reason}` : ''}
                                  </Pill>
                                </div>
                              ))}
                            </div>
                          )}
                        </td>
                      </tr>
                    )}
                  </>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <footer className="pt-1">
        <p className="text-xs text-[var(--text-muted)]">
          {t('driveTeardown.footer', 'Detecção disparada no desligamento (event-triggered) + varredura semanal de reconciliação. Alumni: aprovação automática (#1039, badge "auto") quando o auto-revoke está ativo; inactive: "Aprovar revogação" manual. A remoção efetiva roda via cron em até 1h. "Atestado limpo" = verificação positiva sem acesso. "ignorado" = fechado sem revogação (permissão de owner em revisão de exceção, ou cancelado por reativação do membro).')}
        </p>
      </footer>
    </div>
  );
}

function StatCard({ label, value, tone, icon }: { label: string; value: number; tone: 'neutral' | 'amber' | 'emerald' | 'slate'; icon?: React.ReactNode }) {
  const toneMap: Record<string, string> = {
    neutral: 'text-navy', amber: 'text-amber-600', emerald: 'text-emerald-600', slate: 'text-slate-500',
  };
  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
      <p className="text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide flex items-center gap-1">{icon}{label}</p>
      <p className={`text-2xl font-bold mt-1 ${toneMap[tone]}`}>{value}</p>
    </div>
  );
}

function BucketBadge({ bucket, t }: { bucket: string; t: (k: string, f: string) => string }) {
  if (bucket === 'attested_clean') {
    return <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-emerald-100 text-emerald-700"><CheckCircle2 className="w-3 h-3" />{t('driveTeardown.bucketClean', 'Atestado limpo')}</span>;
  }
  if (bucket === 'needs_action') {
    return <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-amber-100 text-amber-700"><Clock className="w-3 h-3" />{t('driveTeardown.bucketAction', 'Requer ação')}</span>;
  }
  return <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-slate-100 text-slate-600">{t('driveTeardown.bucketNotScanned', 'Sem atestação')}</span>;
}

function Pill({ tone, children }: { tone: 'amber' | 'blue' | 'red' | 'emerald' | 'slate'; children: React.ReactNode }) {
  const map: Record<string, string> = {
    amber: 'bg-amber-100 text-amber-700', blue: 'bg-blue-100 text-blue-700', red: 'bg-red-100 text-red-700',
    emerald: 'bg-emerald-100 text-emerald-700', slate: 'bg-slate-100 text-slate-600',
  };
  return <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-semibold ${map[tone]}`}>{children}</span>;
}
