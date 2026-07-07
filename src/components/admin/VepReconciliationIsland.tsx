import { useState, useEffect, useCallback } from 'react';
import { canForAdminEntry } from '../../lib/permissions';

interface Props { lang?: string; }

type TabKey = 'matrix' | 'selection' | 'onboarding' | 'active_members';

const L: Record<string, Record<string, string>> = {
  'pt-BR': {
    title: 'Reconciliação VEP ↔ Núcleo',
    subtitle: 'Divergências entre estado no PMI VEP e no Núcleo. Sem API write-back, reconciliação é manual.',
    tabSelection: 'Seleção',
    tabOnboarding: 'Onboarding',
    tabActiveMembers: 'Membros',
    tabSelectionHint: 'VEP: terminal (Withdrawn/Declined/OfferNotExtended) · Núcleo: ainda no funil',
    tabOnboardingHint: 'Núcleo: aprovado/convertido · VEP pré-aceite (Submitted = sem oferta / OfferExtended = oferta emitida aguardando aceite). Active = já aceitou, na jornada — não é divergência (#1130).',
    tabActiveMembersHint: 'Membro inativo no Núcleo · VEP: ainda Submitted/Active',
    loading: 'Carregando…',
    noDivergence: 'Sem divergências nesta categoria.',
    emptyState: 'Reconciliado. Sem ações pendentes.',
    refresh: 'Atualizar',
    markReconciled: 'Marcar reconciliado',
    markReconciledHint: 'Acknowledge — some na próxima sync se persistir',
    notePlaceholder: 'Nota opcional (ex: emailei recruiter X)…',
    notePrompt: 'Nota opcional sobre a reconciliação:',
    confirmMark: 'Marcar este item como reconciliado?',
    colName: 'Nome',
    colEmail: 'Email',
    colCycle: 'Ciclo',
    colNucleo: 'Núcleo',
    colVep: 'VEP',
    colLastSeen: 'Última obs',
    colAction: 'Ação sugerida',
    colReconciled: 'Reconciliado',
    summary: 'Total divergente',
    refreshing: 'Atualizando…',
    markErrPrefix: 'Erro ao marcar',
    markOk: 'Marcado como reconciliado.',
    pmiIdLabel: 'PMI ID',
    deniedAccess: 'Acesso restrito.',
    generatedAt: 'Gerado',
    baselineTitle: '📊 Baseline / drift de reconciliação',
    baselineSubtitle: 'Capture um snapshot após cada round de Apply UI C. Compare divergências contra a baseline mais recente pra detectar deriva.',
    captureBaselineBtn: '+ Capturar baseline',
    captureLabelPrompt: 'Label da baseline (ex: "Pós-Apply 12/05"):',
    captureNotesPrompt: 'Notas (opcional):',
    capturedOk: 'Baseline capturada.',
    capturedErr: 'Erro ao capturar baseline',
    baselineEmpty: 'Sem baselines capturadas ainda. Capture uma após confirmar que o estado atual está consistente.',
    deltaLabel: 'Δ vs atual',
    cur: 'Atual',
    colCaptured: 'Capturada',
    colLabel: 'Label',
    colSel: 'Selection',
    colOnb: 'Onboarding',
    colActMem: 'Active mem',
    colMissing: 'Missing VEP',
    // #1130 — matriz papel×coorte + F3/F4
    tabMatrix: 'Matriz papel×coorte',
    tabMatrixHint: 'Plataforma (contrato voluntário ativo) × VEP (mirror Active) por papel e coorte. Join estável por PMI id.',
    mLeader: 'Líder', mResearcher: 'Pesquisador', mOther: 'Outro (GP)',
    colRole: 'Papel', colCohort: 'Coorte', colPlatform: 'Plataforma', colVepActive: 'VEP ativo', colDelta: 'Δ',
    totalRow: 'Total', colVepStatus: 'Status VEP', colMemberActive: 'Member?',
    platformOnlyTitle: 'Ativos na plataforma sem VEP-ativo (mirror)',
    platformOnlyHint: 'Contrato ativo no Núcleo mas mirror VEP não está Active (sync defasado ou oferta não estendida).',
    vepOnlyTitle: 'Ativos no VEP sem contrato de voluntário ativo',
    vepOnlyHint: 'VEP Active mas sem contrato ativo na plataforma (ex.: offboarded).',
    mirrorNote: 'ⓘ "VEP ativo" é o espelho do worker pmi-vep-sync — pode defasar do dashboard PMI ao vivo. Piso reconciliável, não verdade externa.',
    matrixEmpty: 'Sem dados de matriz.',
    errTitle: 'Falha ao carregar', errRetry: 'Tentar novamente',
    linkFiliacao: '→ Fila de filiação', linkSelectionCycle: 'ver ciclo',
    yes: 'sim', no: 'não',
  },
  'en-US': {
    title: 'VEP ↔ Núcleo Reconciliation',
    subtitle: 'Divergences between PMI VEP and Núcleo state. Without API write-back, reconciliation is manual.',
    tabSelection: 'Selection',
    tabOnboarding: 'Onboarding',
    tabActiveMembers: 'Members',
    tabSelectionHint: 'VEP: terminal (Withdrawn/Declined/OfferNotExtended) · Núcleo: still in funnel',
    tabOnboardingHint: 'Núcleo: approved/converted · VEP pre-acceptance (Submitted = no offer / OfferExtended = offer emitted awaiting acceptance). Active = accepted, in journey — not a divergence (#1130).',
    tabActiveMembersHint: 'Inactive member in Núcleo · VEP: still Submitted/Active',
    loading: 'Loading…',
    noDivergence: 'No divergence in this category.',
    emptyState: 'Reconciled. No pending actions.',
    refresh: 'Refresh',
    markReconciled: 'Mark reconciled',
    markReconciledHint: 'Acknowledge — re-surfaces on next sync if persists',
    notePlaceholder: 'Optional note (e.g. emailed recruiter X)…',
    notePrompt: 'Optional reconciliation note:',
    confirmMark: 'Mark this item as reconciled?',
    colName: 'Name',
    colEmail: 'Email',
    colCycle: 'Cycle',
    colNucleo: 'Núcleo',
    colVep: 'VEP',
    colLastSeen: 'Last seen',
    colAction: 'Suggested action',
    colReconciled: 'Reconciled',
    summary: 'Total divergent',
    refreshing: 'Refreshing…',
    markErrPrefix: 'Error marking',
    markOk: 'Marked as reconciled.',
    pmiIdLabel: 'PMI ID',
    deniedAccess: 'Restricted access.',
    generatedAt: 'Generated',
    baselineTitle: '📊 Reconciliation baseline / drift',
    baselineSubtitle: 'Capture a snapshot after each Apply UI C round. Compare divergence against the latest baseline to detect drift.',
    captureBaselineBtn: '+ Capture baseline',
    captureLabelPrompt: 'Baseline label (e.g. "Post-Apply 5/12"):',
    captureNotesPrompt: 'Notes (optional):',
    capturedOk: 'Baseline captured.',
    capturedErr: 'Error capturing baseline',
    baselineEmpty: 'No baselines captured yet. Capture one after confirming the current state is consistent.',
    deltaLabel: 'Δ vs current',
    cur: 'Current',
    colCaptured: 'Captured',
    colLabel: 'Label',
    colSel: 'Selection',
    colOnb: 'Onboarding',
    colActMem: 'Active mem',
    colMissing: 'Missing VEP',
    // #1130 — role×cohort matrix + F3/F4
    tabMatrix: 'Role×cohort matrix',
    tabMatrixHint: 'Platform (active volunteer contract) × VEP (Active mirror) by role and cohort. Stable join by PMI id.',
    mLeader: 'Leader', mResearcher: 'Researcher', mOther: 'Other (GP)',
    colRole: 'Role', colCohort: 'Cohort', colPlatform: 'Platform', colVepActive: 'VEP active', colDelta: 'Δ',
    totalRow: 'Total', colVepStatus: 'VEP status', colMemberActive: 'Member?',
    platformOnlyTitle: 'Active on platform without VEP-active (mirror)',
    platformOnlyHint: 'Active contract in Núcleo but VEP mirror is not Active (stale sync or offer not extended).',
    vepOnlyTitle: 'Active in VEP without active volunteer contract',
    vepOnlyHint: 'VEP Active but no active platform contract (e.g. offboarded).',
    mirrorNote: 'ⓘ "VEP active" is the pmi-vep-sync worker mirror — it may lag the live PMI dashboard. Reconcilable floor, not external truth.',
    matrixEmpty: 'No matrix data.',
    errTitle: 'Failed to load', errRetry: 'Retry',
    linkFiliacao: '→ Affiliation queue', linkSelectionCycle: 'view cycle',
    yes: 'yes', no: 'no',
  },
  'es-LATAM': {
    title: 'Reconciliación VEP ↔ Núcleo',
    subtitle: 'Divergencias entre el estado en PMI VEP y en Núcleo. Sin API write-back, la reconciliación es manual.',
    tabSelection: 'Selección',
    tabOnboarding: 'Onboarding',
    tabActiveMembers: 'Miembros',
    tabSelectionHint: 'VEP: terminal (Withdrawn/Declined/OfferNotExtended) · Núcleo: aún en embudo',
    tabOnboardingHint: 'Núcleo: aprobado/convertido · VEP pre-aceptación (Submitted = sin oferta / OfferExtended = oferta emitida esperando aceptación). Active = ya aceptó, en la jornada — no es divergencia (#1130).',
    tabActiveMembersHint: 'Miembro inactivo en Núcleo · VEP: aún Submitted/Active',
    loading: 'Cargando…',
    noDivergence: 'Sin divergencias en esta categoría.',
    emptyState: 'Reconciliado. Sin acciones pendientes.',
    refresh: 'Actualizar',
    markReconciled: 'Marcar reconciliado',
    markReconciledHint: 'Acknowledge — re-aparece en próxima sync si persiste',
    notePlaceholder: 'Nota opcional (ej: envié email a recruiter X)…',
    notePrompt: 'Nota opcional sobre la reconciliación:',
    confirmMark: '¿Marcar este ítem como reconciliado?',
    colName: 'Nombre',
    colEmail: 'Email',
    colCycle: 'Ciclo',
    colNucleo: 'Núcleo',
    colVep: 'VEP',
    colLastSeen: 'Última obs',
    colAction: 'Acción sugerida',
    colReconciled: 'Reconciliado',
    summary: 'Total divergente',
    refreshing: 'Actualizando…',
    markErrPrefix: 'Error al marcar',
    markOk: 'Marcado como reconciliado.',
    pmiIdLabel: 'PMI ID',
    deniedAccess: 'Acceso restringido.',
    generatedAt: 'Generado',
    baselineTitle: '📊 Baseline / drift de reconciliación',
    baselineSubtitle: 'Captura un snapshot tras cada round de Apply UI C. Compara divergencias contra la baseline más reciente para detectar deriva.',
    captureBaselineBtn: '+ Capturar baseline',
    captureLabelPrompt: 'Etiqueta de la baseline (ej: "Post-Apply 12/05"):',
    captureNotesPrompt: 'Notas (opcional):',
    capturedOk: 'Baseline capturada.',
    capturedErr: 'Error al capturar baseline',
    baselineEmpty: 'Sin baselines capturadas. Captura una luego de confirmar que el estado actual está consistente.',
    deltaLabel: 'Δ vs actual',
    cur: 'Actual',
    colCaptured: 'Capturada',
    colLabel: 'Label',
    colSel: 'Selection',
    colOnb: 'Onboarding',
    colActMem: 'Active mem',
    colMissing: 'Missing VEP',
    // #1130 — matriz papel×coorte + F3/F4
    tabMatrix: 'Matriz rol×cohorte',
    tabMatrixHint: 'Plataforma (contrato de voluntario activo) × VEP (mirror Active) por rol y cohorte. Join estable por PMI id.',
    mLeader: 'Líder', mResearcher: 'Investigador', mOther: 'Otro (GP)',
    colRole: 'Rol', colCohort: 'Cohorte', colPlatform: 'Plataforma', colVepActive: 'VEP activo', colDelta: 'Δ',
    totalRow: 'Total', colVepStatus: 'Estado VEP', colMemberActive: 'Member?',
    platformOnlyTitle: 'Activos en plataforma sin VEP-activo (mirror)',
    platformOnlyHint: 'Contrato activo en Núcleo pero el mirror VEP no está Active (sync desfasado u oferta no extendida).',
    vepOnlyTitle: 'Activos en VEP sin contrato de voluntario activo',
    vepOnlyHint: 'VEP Active pero sin contrato activo en la plataforma (ej.: offboarded).',
    mirrorNote: 'ⓘ "VEP activo" es el espejo del worker pmi-vep-sync — puede desfasarse del dashboard PMI en vivo. Piso reconciliable, no verdad externa.',
    matrixEmpty: 'Sin datos de matriz.',
    errTitle: 'Error al cargar', errRetry: 'Reintentar',
    linkFiliacao: '→ Cola de afiliación', linkSelectionCycle: 'ver ciclo',
    yes: 'sí', no: 'no',
  },
};

function useLang(p?: string): string {
  if (p) return p;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
  }
  return 'pt-BR';
}

function timeAgo(dateStr: string | null | undefined, label: string): string {
  if (!dateStr) return '—';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ${label}`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ${label}`;
  const days = Math.floor(hours / 24);
  return `${days}d ${label}`;
}

const NUCLEO_STATUS_COLOR: Record<string, string> = {
  submitted: 'bg-gray-100 text-gray-700',
  screening: 'bg-blue-50 text-blue-700',
  objective_eval: 'bg-blue-50 text-blue-700',
  interview_pending: 'bg-yellow-50 text-yellow-700',
  interview_scheduled: 'bg-yellow-50 text-yellow-700',
  interview_done: 'bg-yellow-50 text-yellow-700',
  final_eval: 'bg-purple-50 text-purple-700',
  approved: 'bg-emerald-50 text-emerald-700',
  converted: 'bg-emerald-100 text-emerald-800',
  rejected: 'bg-red-50 text-red-700',
  withdrawn: 'bg-red-50 text-red-700',
  cancelled: 'bg-gray-50 text-gray-700',
  waitlist: 'bg-amber-50 text-amber-700',
};

const VEP_STATUS_COLOR: Record<string, string> = {
  Submitted: 'bg-blue-100 text-blue-700',
  OfferExtended: 'bg-amber-100 text-amber-700',
  Active: 'bg-emerald-100 text-emerald-700',
  Withdrawn: 'bg-red-100 text-red-700',
  Declined: 'bg-red-100 text-red-700',
  OfferNotExtended: 'bg-red-100 text-red-700',
  OfferExpired: 'bg-red-100 text-red-700',
  Complete: 'bg-gray-100 text-gray-700',
};

// #1130 — role×cohort reconciliation matrix panel
function MatrixPanel({ t, data, loading, error, onRetry, roleLabel, cycleHref, renderBadge }: {
  t: Record<string, string>;
  data: any;
  loading: boolean;
  error: string | null;
  onRetry: () => void;
  roleLabel: (r: string) => string;
  cycleHref: (code: string | null | undefined) => string | null;
  renderBadge: (status: string | null | undefined, palette: Record<string, string>) => any;
}) {
  if (loading && !data) {
    return <div className="text-center py-10 text-[var(--text-muted)] text-sm">{t.loading}</div>;
  }
  if (error && !data) {
    return (
      <div className="text-center py-10">
        <div className="text-sm font-semibold text-red-700 mb-1">{t.errTitle}</div>
        <div className="text-xs text-[var(--text-muted)] mb-4 font-mono max-w-xl mx-auto break-words">{error}</div>
        <button onClick={onRetry} className="px-4 py-1.5 rounded-lg text-[12px] font-semibold bg-navy text-white hover:opacity-90 cursor-pointer border-0">
          ↻ {t.errRetry}
        </button>
      </div>
    );
  }
  if (!data) {
    return <div className="text-center py-10 text-[var(--text-muted)] text-sm">{t.matrixEmpty}</div>;
  }

  const totals = data.totals || {};
  const matrix: any[] = data.matrix || [];
  const platformOnly: any[] = data.platform_only || [];
  const vepOnly: any[] = data.vep_only || [];

  const deltaCell = (d: number) => {
    if (d === 0) return <span className="text-[var(--text-muted)]">0</span>;
    const cls = d > 0 ? 'text-amber-700' : 'text-blue-700';
    return <span className={`font-bold ${cls}`}>{d > 0 ? '+' : ''}{d}</span>;
  };
  const cohortCell = (code: string) => {
    const href = cycleHref(code);
    return href ? <a href={href} className="text-navy hover:underline">{code}</a> : <span>{code}</span>;
  };

  return (
    <div className="space-y-4">
      {/* Totals headline */}
      <div className="flex flex-wrap gap-4 items-center rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] px-4 py-3">
        <div className="text-[13px]"><span className="text-[var(--text-muted)]">{t.colPlatform}: </span><strong className="text-navy text-lg">{totals.platform_active ?? 0}</strong></div>
        <div className="text-[13px]"><span className="text-[var(--text-muted)]">{t.colVepActive}: </span><strong className="text-navy text-lg">{totals.vep_active_mirror ?? 0}</strong></div>
        <div className="text-[13px]"><span className="text-[var(--text-muted)]">{t.colDelta}: </span>{deltaCell(totals.delta ?? 0)}</div>
      </div>
      {data.mirror_note && <div className="text-[11px] text-[var(--text-muted)] italic">{t.mirrorNote}</div>}

      {/* Matrix table */}
      <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden overflow-x-auto">
        <table className="w-full text-[12px]">
          <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
            <tr>
              <th className="px-3 py-2 text-left font-semibold">{t.colRole}</th>
              <th className="px-3 py-2 text-left font-semibold">{t.colCohort}</th>
              <th className="px-3 py-2 text-right font-semibold">{t.colPlatform}</th>
              <th className="px-3 py-2 text-right font-semibold">{t.colVepActive}</th>
              <th className="px-3 py-2 text-right font-semibold">{t.colDelta}</th>
            </tr>
          </thead>
          <tbody>
            {matrix.map((c, i) => (
              <tr key={`${c.role}-${c.cohort}-${i}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{roleLabel(c.role)}</td>
                <td className="px-3 py-2 text-[var(--text-secondary)]">{cohortCell(c.cohort)}</td>
                <td className="px-3 py-2 text-right">{c.platform_active}</td>
                <td className="px-3 py-2 text-right">{c.vep_active}</td>
                <td className="px-3 py-2 text-right">{deltaCell(c.delta)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-[var(--border-default)] bg-[var(--surface-section-cool)]">
              <td className="px-3 py-2 font-bold text-navy" colSpan={2}>{t.totalRow}</td>
              <td className="px-3 py-2 text-right font-bold text-navy">{totals.platform_active ?? 0}</td>
              <td className="px-3 py-2 text-right font-bold text-navy">{totals.vep_active_mirror ?? 0}</td>
              <td className="px-3 py-2 text-right font-bold">{deltaCell(totals.delta ?? 0)}</td>
            </tr>
          </tfoot>
        </table>
      </div>

      {/* platform_only nominal list */}
      <div>
        <div className="text-[13px] font-bold text-navy mb-1">{t.platformOnlyTitle} <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">{platformOnly.length}</span></div>
        <div className="text-[11px] text-[var(--text-muted)] italic mb-2">{t.platformOnlyHint}</div>
        <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden overflow-x-auto">
          {platformOnly.length === 0 ? (
            <div className="text-center py-6 text-[var(--text-muted)] text-[12px]">{t.emptyState}</div>
          ) : (
            <table className="w-full text-[12px]">
              <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
                <tr>
                  <th className="px-3 py-2 text-left font-semibold">{t.colName}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colEmail}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colRole}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colCohort}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colVepStatus}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colAction}</th>
                </tr>
              </thead>
              <tbody>
                {platformOnly.map((r, i) => (
                  <tr key={`${r.pmi_id || r.email}-${i}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                    <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{r.member_name || '—'}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] font-mono text-[11px]">{r.email}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{roleLabel(r.role)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{cohortCell(r.cohort)}</td>
                    <td className="px-3 py-2">{renderBadge(r.vep_status_raw, VEP_STATUS_COLOR)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{r.suggested_action}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* vep_only nominal list */}
      <div>
        <div className="text-[13px] font-bold text-navy mb-1">{t.vepOnlyTitle} <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">{vepOnly.length}</span></div>
        <div className="text-[11px] text-[var(--text-muted)] italic mb-2">{t.vepOnlyHint}</div>
        <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden overflow-x-auto">
          {vepOnly.length === 0 ? (
            <div className="text-center py-6 text-[var(--text-muted)] text-[12px]">{t.emptyState}</div>
          ) : (
            <table className="w-full text-[12px]">
              <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
                <tr>
                  <th className="px-3 py-2 text-left font-semibold">{t.colName}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colEmail}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colRole}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colCohort}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colMemberActive}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colAction}</th>
                </tr>
              </thead>
              <tbody>
                {vepOnly.map((r, i) => (
                  <tr key={`${r.pmi_id || r.email}-${i}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                    <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{r.applicant_name || '—'}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] font-mono text-[11px]">{r.email}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{roleLabel(r.role)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{cohortCell(r.cohort)}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)]">{r.member_is_active === true ? t.yes : r.member_is_active === false ? t.no : '—'}</td>
                    <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{r.suggested_action}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}

export default function VepReconciliationIsland({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = L[lang] || L['pt-BR'];
  const [authorized, setAuthorized] = useState<boolean | null>(null);
  const [data, setData] = useState<any>(null);
  const [tab, setTab] = useState<TabKey>('matrix');
  const [loading, setLoading] = useState(false);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [toast, setToast] = useState<{ type: 'ok' | 'err'; msg: string } | null>(null);
  // #1130 F3 — load error separate from data==null (avoid infinite spinner on RPC failure)
  const [loadError, setLoadError] = useState<string | null>(null);
  // #1130 — role×cohort matrix (lazy-loaded on tab select)
  const [matrixData, setMatrixData] = useState<any>(null);
  const [matrixLoading, setMatrixLoading] = useState(false);
  const [matrixError, setMatrixError] = useState<string | null>(null);
  // p153 OPP-152.5 — baseline drift panel
  const [baselineData, setBaselineData] = useState<any>(null);
  const [capturingBaseline, setCapturingBaseline] = useState(false);

  const loadBaselines = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    try {
      const { data: b, error } = await sb.rpc('get_vep_baseline_history', { p_limit: 10 });
      if (error) throw error;
      setBaselineData(b);
    } catch (e: any) {
      console.warn('[VepReconciliation] baseline load failed:', e?.message);
    }
  }, []);

  const captureBaseline = useCallback(async () => {
    const label = window.prompt(t.captureLabelPrompt, '');
    if (label === null || label.trim() === '') return;
    const notes = window.prompt(t.captureNotesPrompt, '');
    setCapturingBaseline(true);
    setToast(null);
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('no supabase');
      const { data: r, error } = await sb.rpc('capture_vep_baseline', {
        p_label: label.trim(),
        p_notes: notes ? notes.trim() : null,
      });
      if (error) throw error;
      if (r && typeof r === 'object' && (r as any).error) throw new Error((r as any).error);
      setToast({ type: 'ok', msg: t.capturedOk });
      await loadBaselines();
    } catch (e: any) {
      setToast({ type: 'err', msg: `${t.capturedErr}: ${e?.message || String(e)}` });
    } finally {
      setCapturingBaseline(false);
    }
  }, [t, loadBaselines]);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    // p152 W4 hotfix: retry while member is still loading (was: setAuthorized(false)
    // immediately, causing "Acesso restrito" flash for legit admins including superadmin).
    if (!m) { setTimeout(load, 400); return; }
    // ADR-0007 V4 (p163 Opção C): see docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md
    const isAdmin = m.is_superadmin
      || canForAdminEntry()
      || ['manager', 'deputy_manager'].includes(m.operational_role)
      || (m.designations || []).some((d: string) => d === 'deputy_manager' || d === 'curator' || d === 'chapter_board');
    if (!isAdmin) {
      setAuthorized(false);
      return;
    }
    setAuthorized(true);
    setLoading(true);
    setLoadError(null);
    try {
      const { data: d, error } = await sb.rpc('get_vep_divergence_report');
      if (error) throw error;
      if (d && typeof d === 'object' && (d as any).error) throw new Error((d as any).error);
      setData(d);
      setLoadError(null);
    } catch (e: any) {
      console.error('[VepReconciliation] load error:', e?.message);
      // #1130 F3 — surface a persistent error state (not just a 4s toast) so the GP
      // never mistakes a failed RPC for "still loading".
      setLoadError(e?.message || String(e));
      setToast({ type: 'err', msg: e?.message || String(e) });
    } finally {
      setLoading(false);
    }
  }, []);

  const loadMatrix = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    setMatrixLoading(true);
    setMatrixError(null);
    try {
      const { data: d, error } = await sb.rpc('get_vep_role_cohort_reconciliation');
      if (error) throw error;
      if (d && typeof d === 'object' && (d as any).error) throw new Error((d as any).error);
      setMatrixData(d);
      setMatrixError(null);
    } catch (e: any) {
      console.error('[VepReconciliation] matrix load error:', e?.message);
      setMatrixError(e?.message || String(e));
    } finally {
      setMatrixLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);
  // #1130 — lazy-load the matrix the first time its tab is opened (and on authorize if default)
  useEffect(() => {
    if (authorized === true && tab === 'matrix' && matrixData === null && !matrixLoading && !matrixError) {
      loadMatrix();
    }
  }, [authorized, tab, matrixData, matrixLoading, matrixError, loadMatrix]);
  // p153 OPP-152.5 — load baseline history when authorized
  useEffect(() => { if (authorized === true) loadBaselines(); }, [authorized, loadBaselines]);

  const markReconciled = async (applicationId: string) => {
    const note = window.prompt(t.notePrompt, '');
    if (note === null) return;
    if (!window.confirm(t.confirmMark)) return;
    setPendingId(applicationId);
    setToast(null);
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('no supabase');
      const { data: r, error } = await sb.rpc('mark_vep_reconciled', {
        p_application_id: applicationId,
        p_note: note ? note.trim() : null,
      });
      if (error) throw error;
      if (r && typeof r === 'object' && (r as any).error) throw new Error((r as any).error);
      setToast({ type: 'ok', msg: t.markOk });
      await load();
    } catch (e: any) {
      setToast({ type: 'err', msg: `${t.markErrPrefix}: ${e?.message || String(e)}` });
    } finally {
      setPendingId(null);
    }
  };

  if (authorized === false) {
    return <div className="text-center py-12 text-[var(--text-muted)]">{t.deniedAccess}</div>;
  }
  // #1130 F3 — a failed RPC must not read as "still loading". Show a real error + retry.
  if (loadError && !data) {
    return (
      <div className="text-center py-12">
        <div className="text-sm font-semibold text-red-700 mb-1">{t.errTitle}</div>
        <div className="text-xs text-[var(--text-muted)] mb-4 font-mono max-w-xl mx-auto break-words">{loadError}</div>
        <button
          onClick={load}
          disabled={loading}
          className="px-4 py-1.5 rounded-lg text-[12px] font-semibold bg-navy text-white hover:opacity-90 cursor-pointer border-0 disabled:opacity-50"
        >
          {loading ? t.refreshing : `↻ ${t.errRetry}`}
        </button>
      </div>
    );
  }
  if (authorized === null || !data) {
    return <div className="text-center py-12 text-[var(--text-muted)]">{t.loading}</div>;
  }

  const summary = data.summary || {};
  const lists: Record<Exclude<TabKey, 'matrix'>, any[]> = {
    selection: data.selection_divergent || [],
    onboarding: data.onboarding_divergent || [],
    active_members: data.active_members_divergent || [],
  };
  const matrixDivCount = (matrixData?.totals?.platform_only_count ?? 0) + (matrixData?.totals?.vep_only_count ?? 0);
  const tabCounts: Record<TabKey, number> = {
    matrix: matrixDivCount,
    selection: summary.selection_count ?? lists.selection.length,
    onboarding: summary.onboarding_count ?? lists.onboarding.length,
    active_members: summary.active_members_count ?? lists.active_members.length,
  };
  const tabHints: Record<TabKey, string> = {
    matrix: t.tabMatrixHint,
    selection: t.tabSelectionHint,
    onboarding: t.tabOnboardingHint,
    active_members: t.tabActiveMembersHint,
  };
  const tabLabels: Record<TabKey, string> = {
    matrix: t.tabMatrix,
    selection: t.tabSelection,
    onboarding: t.tabOnboarding,
    active_members: t.tabActiveMembers,
  };
  const currentList = tab === 'matrix' ? [] : lists[tab];

  // #1130 F4 — cross-nav helpers to the sibling admin screens.
  const langPrefix = lang === 'en-US' ? '/en' : lang === 'es-LATAM' ? '/es' : '';
  const filiacaoHref = `${langPrefix}/admin/filiacao`;
  const cycleHref = (code: string | null | undefined) =>
    code && code !== 'no_cycle' ? `${langPrefix}/admin/selection?cycle=${encodeURIComponent(code)}` : null;
  const roleLabel = (r: string) => (r === 'leader' ? t.mLeader : r === 'researcher' ? t.mResearcher : t.mOther);

  const renderBadge = (status: string | null | undefined, palette: Record<string, string>) => {
    if (!status) return <span className="text-[var(--text-muted)]">—</span>;
    const cls = palette[status] || 'bg-gray-100 text-gray-700';
    return <span className={`inline-block text-[10px] font-semibold px-2 py-0.5 rounded-full ${cls}`}>{status}</span>;
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex flex-wrap items-end justify-between gap-3 mb-2">
        <div>
          <h2 className="text-xl font-extrabold text-navy">{t.title}</h2>
          <p className="text-xs text-[var(--text-secondary)] mt-1 max-w-2xl">{t.subtitle}</p>
        </div>
        <div className="flex items-center gap-3">
          {/* #1130 F4 — cross-nav to affiliation queue */}
          <a
            href={filiacaoHref}
            className="text-[11px] font-semibold text-navy hover:underline"
          >
            {t.linkFiliacao}
          </a>
          <div className="text-[11px] text-[var(--text-muted)]">
            {t.summary}: <strong className="text-navy text-base ml-1">{summary.total_divergent ?? 0}</strong>
          </div>
          <button
            onClick={load}
            disabled={loading}
            className="px-3 py-1.5 rounded-lg text-[11px] font-semibold bg-navy text-white hover:opacity-90 cursor-pointer border-0 disabled:opacity-50"
          >
            {loading ? t.refreshing : `↻ ${t.refresh}`}
          </button>
        </div>
      </div>

      {/* Toast */}
      {toast && (
        <div
          role="status"
          className={`text-xs px-3 py-2 rounded-lg ${toast.type === 'ok' ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-700'}`}
        >
          {toast.msg}
        </div>
      )}

      {/* p153 OPP-152.5 — Baseline / drift panel (collapsible) */}
      <details className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden" open={(baselineData?.baselines?.length ?? 0) > 0}>
        <summary className="cursor-pointer px-4 py-3 text-[13px] font-bold text-navy hover:bg-[var(--surface-hover)] flex items-center justify-between">
          <span>{t.baselineTitle}</span>
          <span className="text-[10px] text-[var(--text-muted)] font-normal">
            {baselineData?.baselines?.length ?? 0} {(baselineData?.baselines?.length ?? 0) === 1 ? 'baseline' : 'baselines'}
          </span>
        </summary>
        <div className="px-4 pb-4">
          <p className="text-[11px] text-[var(--text-secondary)] mb-3">{t.baselineSubtitle}</p>
          <div className="flex justify-end mb-2">
            <button
              onClick={captureBaseline}
              disabled={capturingBaseline}
              className="px-3 py-1.5 rounded-lg text-[11px] font-semibold bg-purple-600 text-white hover:opacity-90 cursor-pointer border-0 disabled:opacity-50"
            >
              {capturingBaseline ? '…' : t.captureBaselineBtn}
            </button>
          </div>
          {(!baselineData?.baselines || baselineData.baselines.length === 0) ? (
            <div className="text-center py-6 text-[11px] text-[var(--text-muted)] italic">{t.baselineEmpty}</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-[11px]">
                <thead className="text-[var(--text-muted)]">
                  <tr className="border-b border-[var(--border-subtle)]">
                    <th className="px-2 py-1.5 text-left font-semibold">{t.colCaptured}</th>
                    <th className="px-2 py-1.5 text-left font-semibold">{t.colLabel}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t.colSel}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t.colOnb}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t.colActMem}</th>
                    <th className="px-2 py-1.5 text-right font-semibold">{t.colMissing}</th>
                  </tr>
                </thead>
                <tbody>
                  {/* "Current" pinned row at top */}
                  {baselineData?.current && (
                    <tr className="bg-purple-50/40 border-b border-purple-100">
                      <td className="px-2 py-1.5 font-mono text-[10px] text-purple-700">— {t.cur} —</td>
                      <td className="px-2 py-1.5 italic text-purple-700">{t.deltaLabel}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.selection_divergent ?? 0}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.onboarding_divergent ?? 0}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.active_members_divergent ?? 0}</td>
                      <td className="px-2 py-1.5 text-right font-bold text-purple-700">{baselineData.current.missing_from_latest_vep ?? 0}</td>
                    </tr>
                  )}
                  {baselineData.baselines.map((b: any) => {
                    const cur = baselineData.current || {};
                    const renderDelta = (current: number, baseline: number) => {
                      const d = current - baseline;
                      if (d === 0) return <span className="text-[var(--text-muted)]">={baseline}</span>;
                      const sign = d > 0 ? '+' : '';
                      const cls = d > 0 ? 'text-amber-700' : 'text-emerald-700';
                      return <span><span className="text-[var(--text-secondary)]">{baseline}</span> <span className={`font-bold ${cls}`}>({sign}{d})</span></span>;
                    };
                    return (
                      <tr key={b.id} className="border-b border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]" title={b.notes || ''}>
                        <td className="px-2 py-1.5 text-[var(--text-secondary)] whitespace-nowrap">{new Date(b.captured_at).toLocaleString()}</td>
                        <td className="px-2 py-1.5 font-semibold text-[var(--text-primary)]">{b.label}{b.captured_by_name ? <span className="text-[10px] text-[var(--text-muted)] font-normal"> · {b.captured_by_name}</span> : null}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.selection_divergent ?? 0, b.selection_divergent ?? 0)}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.onboarding_divergent ?? 0, b.onboarding_divergent ?? 0)}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.active_members_divergent ?? 0, b.active_members_divergent ?? 0)}</td>
                        <td className="px-2 py-1.5 text-right">{renderDelta(cur.missing_from_latest_vep ?? 0, b.missing_from_latest_vep ?? 0)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </details>

      {/* Tabs */}
      <div className="flex border-b border-[var(--border-default)]">
        {(['matrix', 'selection', 'onboarding', 'active_members'] as TabKey[]).map((key) => {
          const active = tab === key;
          const count = tabCounts[key];
          return (
            <button
              key={key}
              onClick={() => setTab(key)}
              className={`px-4 py-2 text-[12px] font-semibold cursor-pointer border-0 border-b-2 ${
                active ? 'border-navy text-navy bg-transparent' : 'border-transparent text-[var(--text-secondary)] bg-transparent hover:text-navy'
              }`}
            >
              {tabLabels[key]}
              <span className={`ml-2 inline-block text-[10px] font-bold px-1.5 py-0.5 rounded-full ${count > 0 ? 'bg-amber-100 text-amber-700' : 'bg-gray-100 text-gray-500'}`}>
                {count}
              </span>
            </button>
          );
        })}
      </div>

      {/* Hint */}
      <div className="text-[11px] text-[var(--text-muted)] italic">{tabHints[tab]}</div>

      {/* #1130 — Matrix tab */}
      {tab === 'matrix' && (
        <MatrixPanel
          t={t}
          data={matrixData}
          loading={matrixLoading}
          error={matrixError}
          onRetry={loadMatrix}
          roleLabel={roleLabel}
          cycleHref={cycleHref}
          renderBadge={renderBadge}
        />
      )}

      {/* Table (divergence tabs) */}
      {tab !== 'matrix' && (
      <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden">
        {currentList.length === 0 ? (
          <div className="text-center py-10 text-[var(--text-muted)] text-sm">{summary.total_divergent === 0 ? t.emptyState : t.noDivergence}</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-[12px]">
              <thead className="bg-[var(--surface-section-cool)] text-[var(--text-muted)]">
                <tr>
                  <th className="px-3 py-2 text-left font-semibold">{t.colName}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colEmail}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colCycle}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colNucleo}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colVep}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colLastSeen}</th>
                  <th className="px-3 py-2 text-left font-semibold">{t.colAction}</th>
                  <th className="px-3 py-2 text-right font-semibold">{t.colReconciled}</th>
                </tr>
              </thead>
              <tbody>
                {currentList.map((row: any) => {
                  const appId = row.application_id || row.latest_application_id;
                  const name = row.applicant_name || row.member_name || '—';
                  const isReconciled = row.vep_reconciled_at && row.vep_last_seen_at && new Date(row.vep_reconciled_at).getTime() >= new Date(row.vep_last_seen_at).getTime();
                  return (
                    <tr key={appId || `${row.email}-${row.cycle_code}`} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                      <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">{name}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)] font-mono text-[11px]">{row.email}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)]">
                        {/* #1130 F4 — deep-link to the selection screen filtered by cycle */}
                        {cycleHref(row.cycle_code) ? (
                          <a href={cycleHref(row.cycle_code)!} className="text-navy hover:underline font-medium" title={t.linkSelectionCycle}>{row.cycle_code}</a>
                        ) : (row.cycle_code || '—')}
                      </td>
                      <td className="px-3 py-2">{renderBadge(row.nucleo_status || (row.is_active === false ? 'inactive' : null), NUCLEO_STATUS_COLOR)}</td>
                      <td className="px-3 py-2">{renderBadge(row.vep_status_raw, VEP_STATUS_COLOR)}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{timeAgo(row.vep_last_seen_at, 'ago')}</td>
                      <td className="px-3 py-2 text-[var(--text-secondary)] text-[11px]">{row.suggested_action}</td>
                      <td className="px-3 py-2 text-right">
                        {appId ? (
                          <button
                            onClick={() => markReconciled(appId)}
                            disabled={pendingId === appId}
                            title={t.markReconciledHint}
                            className="px-2 py-1 rounded-lg text-[10px] font-semibold bg-emerald-50 text-emerald-700 hover:bg-emerald-100 cursor-pointer border-0 disabled:opacity-50"
                          >
                            {pendingId === appId ? '…' : `✓ ${t.markReconciled}`}
                          </button>
                        ) : (
                          <span className="text-[var(--text-muted)] text-[10px]">—</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
      )}

      {/* Footer */}
      <div className="text-[10px] text-[var(--text-muted)] text-right">
        {summary.generated_at && `${t.generatedAt}: ${new Date(summary.generated_at).toLocaleString()}`}
      </div>
    </div>
  );
}
