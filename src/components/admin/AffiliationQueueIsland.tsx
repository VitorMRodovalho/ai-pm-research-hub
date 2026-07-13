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
//
// #996 — enriched journey: (F-A) per-row PMI identity panel (pmi_profile from the queue RPC) and
// (F-C) chapter / VEP-status filters + name-email search + sort (attention default) on top of the
// #1041 expiry column/farol. Migrate from "verify everything by hand" → "review the auto-derived
// and confirm exceptions" without loosening the write boundary (SPEC_996_FILIACAO_JOURNEY.md).
import { useState, useEffect, useCallback, useRef, useMemo, Fragment } from 'react';
import { Loader2, SearchCheck, CalendarClock, ShieldCheck, Info, ArrowUpDown, BadgeCheck, Filter, Search, ChevronDown, ChevronRight, IdCard, ExternalLink } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { unifiedBrChapters, soonestChapterExpiry, type PmiMembershipEntry, type ChapterAffiliation } from '../../lib/affiliation-chapters';
import { validityFarol, toneClasses, VEP_STATUS_TONE, COHORT_TONE } from '../../lib/statusFarol';

interface LatestVerification {
  created_at: string;
  membership_active: boolean | null;
  membership_expires_on: string | null;
  method: string | null;
  chapter_verified: string | null;
}
// #996 F-A — PMI identity from the latest VEP-enriched application (same Phase B source the
// seleção PMI tab uses). Null when the member has no enriched application (fill in manually).
interface PmiProfile {
  pmi_id: string | null;
  member_since: string | null;
  member_until: string | null;
  volunteer_count: number | null;
  last_sync: string | null;
}
// #1129 — cohort derived reliably from engagement/selection → cycle (never members.cycles).
type CohortClass = 'current_selection' | 'carryover' | 'non_selection';
// #1129 — volunteer-term validity vs CURRENT_DATE (server-side, 180d "expiring" window).
type TermStatus = 'valid' | 'expiring' | 'expired' | 'none';

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
  // #1192 — SSOT read-through (member_chapter_affiliations × chapter_registry, resolved server-side)
  chapter_affiliations: ChapterAffiliation[] | null;
  pmi_profile: PmiProfile | null;
  latest_verification: LatestVerification | null;
  // #1129 cohort + term (server-derived)
  cohort_class: CohortClass;
  cohort_cycle_code: string | null;
  cohort_role: string | null;
  term_end_date: string | null;
  term_status: TermStatus;
}

/* "31 Jul 2026" (VEP) -> "2026-07-31" for the <input type=date>; '' if unparseable. */
function toDateInput(raw: string | null | undefined): string {
  if (!raw) return '';
  const ts = Date.parse(raw);
  if (Number.isNaN(ts)) return '';
  return new Date(ts).toISOString().slice(0, 10);
}

/* Human-readable date/datetime for the identity panel; '—' if absent/unparseable. */
function fmtDate(raw: string | null | undefined, withTime = false): string {
  if (!raw) return '—';
  const ts = Date.parse(raw);
  if (Number.isNaN(ts)) return String(raw);
  const d = new Date(ts);
  return withTime ? d.toLocaleString('pt-BR') : d.toLocaleDateString('pt-BR');
}

interface Farol { emoji: string; label: string; cls: string; provisional: boolean; key: 'expired' | 'soon' | 'ok' | 'unverified'; }

/**
 * Verification farol. A GP-recorded verification (append-only latest_verification) is
 * AUTHORITATIVE. #1041 — when none exists yet, derive a PROVISIONAL status from the enriched
 * VEP expiry (soonestChapterExpiry, SSOT-first #1192) so the GP triages at a glance and opens the
 * modal only to confirm.
 */
// #1132 — emoji + colour come from the shared validity farol (src/lib/statusFarol);
// this function keeps only the business logic that picks the farol key + label + provisional.
function farol(r: QueueRow, t: (k: string, f?: string) => string): Farol {
  const mk = (key: Farol['key'], label: string, provisional: boolean): Farol => {
    const f = validityFarol(key);
    return { emoji: f.emoji, label, cls: f.cls, provisional, key };
  };
  const v = r.latest_verification;
  if (v) {
    if (v.membership_active === false) return mk('expired', t('comp.affiliationQueue.affInactive', 'Filiação inativa'), false);
    if (v.membership_expires_on) {
      const days = Math.ceil((new Date(v.membership_expires_on).getTime() - Date.now()) / 86400000);
      if (days < 0) return mk('expired', t('comp.affiliationQueue.affExpired', 'Filiação vencida'), false);
      if (days <= 30) return mk('soon', t('comp.affiliationQueue.affExpiring', 'Vence em breve'), false);
    }
    return mk('ok', t('comp.affiliationQueue.affVerified', 'Verificada'), false);
  }
  const s = soonestChapterExpiry(r.chapter_affiliations, r.pmi_memberships);
  if (s.status === 'expired') return mk('expired', t('comp.affiliationQueue.affExpiredVep', 'Vencida (VEP)'), true);
  if (s.status === 'soon') return mk('soon', t('comp.affiliationQueue.affExpiringVep', 'Vence em breve (VEP)'), true);
  if (s.status === 'ok') return mk('ok', t('comp.affiliationQueue.affActiveVep', 'Ativa (VEP)'), true);
  return mk('unverified', t('comp.affiliationQueue.affUnverified', 'Não verificada'), false);
}

// #1132 — VEP badge colours derived from the shared SSOT (subset used here).
const VEP_CLS: Record<string, string> = Object.fromEntries(
  Object.entries(VEP_STATUS_TONE).map(([status, tone]) => [status, toneClasses(tone)]),
);

/** #1129 — cohort badge presentation (label + tooltip + class). Colour from the shared SSOT (#1132). */
function cohortMeta(cls: CohortClass, t: (k: string, f?: string) => string): { label: string; hint: string; cls: string } {
  return {
    label: t(`comp.affiliationQueue.cohort_${cls}`, cls),
    hint: t(`comp.affiliationQueue.cohortHint_${cls}`, ''),
    cls: toneClasses(COHORT_TONE[cls] ?? 'mutedInk'),
  };
}

/** #1129 — volunteer-term validity badge (emoji + label + class). Farol from the shared SSOT (#1132). */
function termMeta(status: TermStatus, t: (k: string, f?: string) => string): { emoji: string; label: string; cls: string } {
  const labels: Record<TermStatus, string> = {
    expired:  t('comp.affiliationQueue.term_expired', 'Vencido'),
    expiring: t('comp.affiliationQueue.term_expiring', 'Vencendo'),
    valid:    t('comp.affiliationQueue.term_valid', 'Vigente'),
    none:     t('comp.affiliationQueue.term_none', 'Sem termo'),
  };
  // term status keys (expired/expiring/valid/none) are validity-farol keys.
  const f = validityFarol(status);
  return { emoji: f.emoji, label: labels[status], cls: f.cls };
}

// #1192 — chapter-filter option row read straight from chapter_registry (the SSOT).
interface RegistryChapter { chapter_code: string; state: string; }

// #1364 — per-chapter reconciliation row from get_affiliation_chapter_rollup(). `chapter` is
// members.chapter ('PMI-XX', the /admin/members roster axis); in_queue mirrors this queue's cohort.
interface ChapterRollupEntry { chapter: string; total_active: number; in_queue: number; verified_out: number; }

// #1368 — deterministic PMI VEP profile URL by pmi_id (owner-confirmed pattern, 2026-07-13:
// volunteer.pmi.org/profiles/<pmi_id>[/stub]). Lets the office jump straight to the source used
// for affiliation enrichment to verify membership manually. Requires the caller to be logged in.
const vepProfileUrl = (pmiId: string) => `https://volunteer.pmi.org/profiles/${encodeURIComponent(pmiId)}`;

type SortKey = 'attention' | 'name' | 'expiry' | 'sync';

/** #996 "precisa atenção" default ordering: pré-onboarding → vencida → vence em breve → não verificada → resto. */
function attentionRank(r: QueueRow, t: (k: string, f?: string) => string): number {
  if (r.is_pre_onboarding) return 0;
  const k = farol(r, t).key;
  return k === 'expired' ? 1 : k === 'soon' ? 2 : k === 'unverified' ? 3 : 4;
}

/** Best-known last VEP sync timestamp for the "sync" sort (panel value, else the queue's vep_last_seen_at). */
function lastSyncTs(r: QueueRow): number {
  const raw = r.pmi_profile?.last_sync || r.vep_last_seen_at;
  if (!raw) return -Infinity;
  const ts = Date.parse(raw);
  return Number.isNaN(ts) ? -Infinity : ts;
}

export default function AffiliationQueueIsland() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const [rows, setRows] = useState<QueueRow[]>([]);
  const [loading, setLoading] = useState(true);
  // #1129 — default to 'all' so the queue never silently hides the current-selection members who
  // are past pre-onboarding (10/45 were invisible under the old 'pre' default). Attention-sort still
  // floats pre-onboarding rows to the top, so nothing urgent is lost.
  // #1364b — three scopes: 'pre' (pre-onboarding), 'queue' (todos não-verificados = the queue), and
  // 'all' (todos os ativos, verified + unverified — lazy-loaded via p_scope='all'). Default 'queue'
  // preserves the prior landing view.
  const [tab, setTab] = useState<'pre' | 'queue' | 'all'>('queue');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [bulkVerifying, setBulkVerifying] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>('attention');
  const [statusFilter, setStatusFilter] = useState<'all' | 'action' | 'unverified'>('all');
  const [chapterFilter, setChapterFilter] = useState<string>('all');
  const [vepFilter, setVepFilter] = useState<string>('all');
  const [cohortFilter, setCohortFilter] = useState<'all' | CohortClass>('all'); // #1129
  const [termFilter, setTermFilter] = useState<'all' | TermStatus>('all');       // #1129
  const [search, setSearch] = useState('');
  const [registry, setRegistry] = useState<RegistryChapter[]>([]);               // #1192
  const [rollup, setRollup] = useState<ChapterRollupEntry[]>([]);                // #1364
  const [allRows, setAllRows] = useState<QueueRow[]>([]);                        // #1364b full roster
  const [allLoaded, setAllLoaded] = useState(false);                            // #1364b lazy-load latch
  const [allLoading, setAllLoading] = useState(false);                          // #1364b
  const allLoadedRef = useRef(false); allLoadedRef.current = allLoaded;

  // #1192 — chapter filter options come from chapter_registry (RLS: read-all for authenticated),
  // NOT from whatever the loaded rows happen to parse to (the old 5-of-15 bug).
  useEffect(() => {
    let cancelled = false;
    const boot = () => {
      const sb = getSb();
      if (!sb) { if (!cancelled) setTimeout(boot, 400); return; }
      sb.from('chapter_registry')
        .select('chapter_code,state')
        .eq('country', 'BR').eq('is_active', true)
        .order('display_order')
        .then(({ data }: any) => { if (!cancelled && Array.isArray(data)) setRegistry(data); });
    };
    boot();
    return () => { cancelled = true; };
  }, [getSb]);

  // ── load one scope of the queue RPC ('queue' = unverified cohort, 'all' = full active roster #1364b) ──
  const loadScope = useCallback(async (scope: 'queue' | 'all'): Promise<QueueRow[] | null> => {
    const sb = getSb();
    if (!sb) return null;
    const { data, error } = await sb.rpc(
      'get_affiliation_verification_queue',
      scope === 'all' ? { p_scope: 'all' } : undefined,
    );
    if (error) {
      (window as any).toast?.(error.message || t('comp.affiliationQueue.loadError', 'Erro ao carregar a fila'), 'error');
      return null;
    }
    return Array.isArray(data) ? data : [];
  }, [getSb, t]);

  // ── load the queue (retry until Nav publishes the authed client) ──
  const fetchQueue = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(fetchQueue, 300); return; }
    setLoading(true);
    const q = await loadScope('queue');
    if (q) setRows(q);
    // #1364 — per-chapter reconciliation (full roster vs this queue) for the chapter-filter banner.
    sb.rpc('get_affiliation_chapter_rollup')
      .then(({ data: rd }: any) => setRollup(Array.isArray(rd) ? rd : []))
      .catch(() => {});
    setLoading(false);
    // #1364b — keep the full-roster tab in sync after a verify/refresh, if it was already loaded.
    if (allLoadedRef.current) { const a = await loadScope('all'); if (a) setAllRows(a); }
  }, [getSb, t, loadScope]);

  // #1364b — lazy-load the full active roster the first time the "Todos" tab is opened.
  const fetchAll = useCallback(async () => {
    setAllLoading(true);
    const a = await loadScope('all');
    if (a) { setAllRows(a); setAllLoaded(true); }
    setAllLoading(false);
  }, [loadScope]);
  useEffect(() => {
    if (tab === 'all' && !allLoaded && !allLoading) fetchAll();
  }, [tab, allLoaded, allLoading, fetchAll]);

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
    const br = unifiedBrChapters(r.chapter_affiliations, r.pmi_memberships);
    setVMember(r);
    setVActive(r.latest_verification?.membership_active !== false);
    // Prefer the actual PMI membership name (raw) when known — e.g. "Amazônia Chapter" (AM alias).
    setVChapter(br[0] ? (br[0].raw || `${br[0].name}, Brazil Chapter`) : (r.chapter || ''));
    setVExpires(r.latest_verification?.membership_expires_on || toDateInput(br[0]?.expiry) || toDateInput(r.pmi_profile?.member_until));
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
  const toggleExpand = (id: string) =>
    setExpandedIds(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });

  const preCount = rows.filter(r => r.is_pre_onboarding).length;
  // #1129 — current-selection members past pre-onboarding (the subset the old 'pre' default hid).
  const hiddenCurrentSel = rows.filter(r => r.cohort_class === 'current_selection' && !r.is_pre_onboarding).length;

  // #996 F-C — VEP option list derived from the loaded cohort. The CHAPTER options, by contrast,
  // come from chapter_registry (`registry` state above, #1192) — never from the loaded rows.
  const vepOptions = useMemo(() => {
    const set = new Set<string>();
    rows.forEach(r => { if (r.vep_status_raw) set.add(r.vep_status_raw); });
    return [...set].sort((a, b) => a.localeCompare(b));
  }, [rows]);

  const visible = useMemo(() => {
    // #1364b — base set by tab: 'pre' = pre-onboarding subset, 'all' = full active roster, else the queue.
    let list = tab === 'pre' ? rows.filter(r => r.is_pre_onboarding)
             : tab === 'all' ? allRows.slice()
             : rows.slice();
    if (statusFilter === 'action') list = list.filter(r => { const k = farol(r, t).key; return k === 'expired' || k === 'soon'; });
    else if (statusFilter === 'unverified') list = list.filter(r => farol(r, t).key === 'unverified');
    if (cohortFilter !== 'all') list = list.filter(r => r.cohort_class === cohortFilter);   // #1129
    if (termFilter !== 'all') list = list.filter(r => r.term_status === termFilter);         // #1129
    // #1192 — chapter filter matches on the registry chapter_code delivered by the SSOT read-through.
    if (chapterFilter !== 'all') list = list.filter(r => unifiedBrChapters(r.chapter_affiliations, r.pmi_memberships).some(c => c.code === chapterFilter));
    if (vepFilter !== 'all') list = list.filter(r => (r.vep_status_raw || '—') === vepFilter);
    const q = search.trim().toLowerCase();
    if (q) list = list.filter(r => r.name.toLowerCase().includes(q) || (r.email || '').toLowerCase().includes(q));

    list = list.slice().sort((a, b) => {
      if (sortKey === 'name') return a.name.localeCompare(b.name);
      if (sortKey === 'sync') return lastSyncTs(b) - lastSyncTs(a); // most-recent sync first
      if (sortKey === 'expiry') {
        const da = soonestChapterExpiry(a.chapter_affiliations, a.pmi_memberships).days;
        const db = soonestChapterExpiry(b.chapter_affiliations, b.pmi_memberships).days;
        if (da === null && db === null) return a.name.localeCompare(b.name);
        if (da === null) return 1;   // rows without a dated BR chapter sink to the bottom
        if (db === null) return -1;
        return da - db;              // soonest / already-expired first
      }
      // 'attention' (default)
      const ra = attentionRank(a, t), rb = attentionRank(b, t);
      return ra !== rb ? ra - rb : a.name.localeCompare(b.name);
    });
    return list;
  }, [rows, allRows, tab, statusFilter, cohortFilter, termFilter, chapterFilter, vepFilter, search, sortKey, t]);

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
        <button onClick={() => setTab('queue')}
          className={`px-3 py-1.5 text-[13px] rounded-lg border cursor-pointer ${tab === 'queue' ? 'bg-teal-600 text-white border-teal-600' : 'bg-transparent text-[var(--text-secondary)] border-[var(--border-default)] hover:bg-[var(--surface-hover)]'}`}>
          {t('comp.affiliationQueue.tabAll', 'Todos não-verificados')} ({rows.length})
        </button>
        {/* #1364b — full active roster (verified + unverified) so the office can filter a chapter and
            see every member linked to it with each one's status. Lazy-loaded on first open. */}
        <button onClick={() => setTab('all')}
          className={`px-3 py-1.5 text-[13px] rounded-lg border cursor-pointer ${tab === 'all' ? 'bg-teal-600 text-white border-teal-600' : 'bg-transparent text-[var(--text-secondary)] border-[var(--border-default)] hover:bg-[var(--surface-hover)]'}`}>
          {t('comp.affiliationQueue.tabEveryone', 'Todos')}{allLoaded ? ` (${allRows.length})` : ''}
        </button>
      </div>

      {/* #1129 — hidden-subset hint: current-selection members past pre-onboarding (invisible under the old 'pre' default) */}
      {tab === 'pre' && hiddenCurrentSel > 0 && (
        <div className="mb-3 flex items-center gap-1.5 text-[12px] text-amber-700 bg-amber-50 rounded-lg px-3 py-2">
          <Info size={13} className="flex-shrink-0" />
          <span>{t('comp.affiliationQueue.hiddenSubsetHint', '{n} da seleção atual aguardam verificação fora do pré-onboarding').replace('{n}', String(hiddenCurrentSel))}</span>
        </div>
      )}

      {/* filters + controls (#996 F-C) */}
      <div className="flex flex-wrap items-center gap-2 mb-3">
        {/* search */}
        <div className="relative">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder={t('comp.affiliationQueue.searchPh', 'Buscar por nome ou email')}
            className="pl-7 pr-3 py-1.5 text-[13px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)] w-56" />
        </div>
        {/* chapter filter */}
        <select value={chapterFilter} onChange={e => setChapterFilter(e.target.value)}
          className="px-2.5 py-1.5 text-[13px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)] cursor-pointer">
          <option value="all">{t('comp.affiliationQueue.filterChapterAll', 'Todos os capítulos')}</option>
          {registry.map(c => <option key={c.chapter_code} value={c.chapter_code}>{c.state}</option>)}
        </select>
        {/* #1129 cohort filter */}
        <select value={cohortFilter} onChange={e => setCohortFilter(e.target.value as 'all' | CohortClass)}
          className="px-2.5 py-1.5 text-[13px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)] cursor-pointer">
          <option value="all">{t('comp.affiliationQueue.filterCohortAll', 'Todas as coortes')}</option>
          <option value="current_selection">{t('comp.affiliationQueue.cohort_current_selection', 'Seleção atual')}</option>
          <option value="carryover">{t('comp.affiliationQueue.cohort_carryover', 'Carryover')}</option>
          <option value="non_selection">{t('comp.affiliationQueue.cohort_non_selection', 'Não-seleção')}</option>
        </select>
        {/* #1129 term validity filter */}
        <select value={termFilter} onChange={e => setTermFilter(e.target.value as 'all' | TermStatus)}
          className="px-2.5 py-1.5 text-[13px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)] cursor-pointer">
          <option value="all">{t('comp.affiliationQueue.filterTermAll', 'Todos os termos')}</option>
          <option value="expired">{t('comp.affiliationQueue.term_expired', 'Vencido')}</option>
          <option value="expiring">{t('comp.affiliationQueue.term_expiring', 'Vencendo')}</option>
          <option value="valid">{t('comp.affiliationQueue.term_valid', 'Vigente')}</option>
          <option value="none">{t('comp.affiliationQueue.term_none', 'Sem termo')}</option>
        </select>
        {/* VEP status filter */}
        <select value={vepFilter} onChange={e => setVepFilter(e.target.value)}
          className="px-2.5 py-1.5 text-[13px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)] cursor-pointer">
          <option value="all">{t('comp.affiliationQueue.filterVepAll', 'Todos VEP')}</option>
          {vepOptions.map(v => <option key={v} value={v}>{v}</option>)}
        </select>
        {/* sort */}
        <div className="flex items-center gap-1 text-[12px] text-[var(--text-muted)]">
          <ArrowUpDown size={13} />
          <select value={sortKey} onChange={e => setSortKey(e.target.value as SortKey)}
            className="px-2.5 py-1.5 text-[13px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)] cursor-pointer">
            <option value="attention">{t('comp.affiliationQueue.sort_attention', 'Precisa atenção')}</option>
            <option value="name">{t('comp.affiliationQueue.sort_name', 'Nome')}</option>
            <option value="expiry">{t('comp.affiliationQueue.sort_expiry', 'Vencimento')}</option>
            <option value="sync">{t('comp.affiliationQueue.sort_sync', 'Última sync')}</option>
          </select>
        </div>
      </div>

      {/* status filter (farol) */}
      <div className="flex items-center gap-1.5 mb-4 text-[12px]">
        <Filter size={13} className="text-[var(--text-muted)]" />
        {(['all', 'action', 'unverified'] as const).map(fk => (
          <button key={fk} onClick={() => setStatusFilter(fk)}
            className={`px-2.5 py-1 rounded-full border cursor-pointer ${statusFilter === fk ? 'bg-teal-50 text-teal-700 border-teal-300' : 'bg-transparent text-[var(--text-secondary)] border-[var(--border-default)] hover:bg-[var(--surface-hover)]'}`}>
            {t(`comp.affiliationQueue.filter_${fk}`, fk === 'all' ? 'Todos' : fk === 'action' ? 'Vencendo / Vencidas' : 'Não verificadas')}
          </button>
        ))}
      </div>

      {/* #1364 — chapter reconciliation. This screen is a verification QUEUE (a subset of /admin/members),
          so a chapter here shows FEWER people than the same chapter on /membros: the difference is the
          already-verified members, who correctly leave the queue. Surfaced so the two screens reconcile
          at a glance and the old "PMI-RS shows 16 there but 3 here" reads as by-design, not a bug. */}
      {tab !== 'all' && chapterFilter !== 'all' && (() => {
        const r = rollup.find(x => x.chapter === `PMI-${chapterFilter}`);
        if (!r) return null;
        const label = registry.find(c => c.chapter_code === chapterFilter)?.state || `PMI-${chapterFilter}`;
        const msg = t('comp.affiliationQueue.chapterReconcile',
          '{chapter}: {total} membros ativos em Membros · {verified} já verificados (fora desta fila) · {queue} aguardando verificação aqui.')
          .replace('{chapter}', label)
          .replace('{total}', String(r.total_active))
          .replace('{verified}', String(r.verified_out))
          .replace('{queue}', String(r.in_queue));
        return (
          <div className="mb-4 flex items-start gap-1.5 text-[12px] text-[var(--text-secondary)] bg-[var(--surface-section-cool)] rounded-lg px-3 py-2">
            <Info size={13} className="flex-shrink-0 mt-0.5" />
            <span>{msg}</span>
          </div>
        );
      })()}

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

      {tab === 'all' && allLoading && !allLoaded ? (
        <div className="flex items-center justify-center py-16 text-[var(--text-muted)]">
          <Loader2 size={20} className="animate-spin mr-2" /> {t('comp.affiliationQueue.loadingAll', 'Carregando todos os membros…')}
        </div>
      ) : visible.length === 0 ? (
        <div className="text-center py-16 text-[var(--text-muted)]">{t('comp.affiliationQueue.empty', 'Nenhum membro pendente de verificação.')}</div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-[var(--surface-section-cool)] text-[var(--text-muted)] text-[.65rem] uppercase tracking-wider">
                <th className="px-3 py-2 w-10"><input type="checkbox" checked={allVisibleSelected} onChange={toggleAll} className="accent-teal-500" aria-label={t('comp.affiliationQueue.selectAll', 'Selecionar todos')} /></th>
                <th className="px-3 py-2 text-left">{t('comp.affiliationQueue.thMember', 'Membro')}</th>
                <th className="px-3 py-2 text-left">{t('comp.affiliationQueue.thCohort', 'Coorte')}</th>
                <th className="px-3 py-2 text-left">{t('comp.affiliationQueue.thChapter', 'Capítulo / Filiação PMI')}</th>
                <th className="px-3 py-2 text-left">
                  <button onClick={() => setSortKey(s => s === 'expiry' ? 'attention' : 'expiry')} className="inline-flex items-center gap-1 cursor-pointer uppercase tracking-wider hover:text-[var(--text-secondary)]" title={t('comp.affiliationQueue.sortExpiryHint', 'Ordenar por vencimento (vencidas/vencendo primeiro)')}>
                    {t('comp.affiliationQueue.thExpiry', 'Vencimento')}
                    <ArrowUpDown size={11} className={sortKey === 'expiry' ? 'text-teal-600' : 'opacity-40'} />
                  </button>
                </th>
                <th className="px-3 py-2 text-left">{t('comp.affiliationQueue.thTerm', 'Termo de voluntariado')}</th>
                <th className="px-3 py-2 text-center">{t('comp.affiliationQueue.thVep', 'VEP')}</th>
                <th className="px-3 py-2 text-center">{t('comp.affiliationQueue.thStatus', 'Status')}</th>
                <th className="px-3 py-2 text-center w-24">{t('comp.affiliationQueue.thActions', 'Ações')}</th>
              </tr>
            </thead>
            <tbody>
              {visible.map(r => {
                const f = farol(r, t);
                // #1192 — SSOT-first; raw parse is display fallback only. Empty ⇒ neither side has data.
                const br = unifiedBrChapters(r.chapter_affiliations, r.pmi_memberships);
                const expanded = expandedIds.has(r.member_id);
                const p = r.pmi_profile;
                return (
                  <Fragment key={r.member_id}>
                  <tr className="border-t border-[var(--border-default)] hover:bg-[var(--surface-hover)]">
                    <td className="px-3 py-2"><input type="checkbox" checked={selectedIds.has(r.member_id)} onChange={() => toggle(r.member_id)} className="accent-teal-500" /></td>
                    <td className="px-3 py-2">
                      <div className="flex items-start gap-1.5">
                        <button onClick={() => toggleExpand(r.member_id)} title={t('comp.affiliationQueue.expandHint', 'Ver identidade PMI')}
                          className="mt-0.5 text-[var(--text-muted)] hover:text-teal-600 cursor-pointer border-0 bg-transparent p-0" aria-expanded={expanded}>
                          {expanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                        </button>
                        <div>
                          <div className="font-medium text-[var(--text-primary)] flex items-center gap-1.5">
                            {r.name}
                            {r.is_pre_onboarding && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-orange-50 text-orange-600 font-semibold">{t('comp.affiliationQueue.preBadge', 'pré')}</span>}
                            {r.pmi_id_verified && <span title={t('comp.affiliationQueue.pmiIdVerified', 'PMI ID verificado')} className="inline-flex"><BadgeCheck size={13} className="text-teal-600" /></span>}
                          </div>
                          <div className="text-[.7rem] text-[var(--text-muted)]">{r.email}</div>
                        </div>
                      </div>
                    </td>
                    <td className="px-3 py-2">
                      {(() => {
                        const cm = cohortMeta(r.cohort_class, t);
                        const roleLabel = r.cohort_role === 'leader' ? t('comp.affiliationQueue.role_leader', 'Líder')
                          : r.cohort_role === 'researcher' ? t('comp.affiliationQueue.role_researcher', 'Pesquisador(a)')
                          : r.cohort_role;
                        return (
                          <div className="space-y-0.5">
                            <span className={`inline-block text-[10px] px-2 py-0.5 rounded-full font-semibold ${cm.cls}`} title={cm.hint}>{cm.label}</span>
                            {(r.cohort_cycle_code || roleLabel) && (
                              <div className="text-[10px] text-[var(--text-muted)]">
                                {r.cohort_cycle_code || ''}{r.cohort_cycle_code && roleLabel ? ' · ' : ''}{roleLabel || ''}
                              </div>
                            )}
                          </div>
                        );
                      })()}
                    </td>
                    <td className="px-3 py-2">
                      {br.length > 0 ? (
                        <div className="space-y-0.5">
                          {br.map((c, i) => (
                            <div key={i} className="text-[12px] flex items-center gap-1">
                              <span className="font-medium text-[var(--text-primary)]">{c.name}</span>
                              {c.verified && <span title={t('comp.affiliationQueue.ssotVerified', 'Filiação registrada no cadastro de capítulos (verificada)')} className="inline-flex"><BadgeCheck size={11} className="text-teal-600" /></span>}
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
                    <td className="px-3 py-2">
                      {(() => {
                        const s = soonestChapterExpiry(r.chapter_affiliations, r.pmi_memberships);
                        if (!s.expiry) return <span className="text-[12px] text-[var(--text-muted)]">—</span>;
                        const cls = s.expired ? 'text-rose-600' : s.soon ? 'text-amber-600' : 'text-[var(--text-secondary)]';
                        const rel = s.expired
                          ? t('comp.affiliationQueue.expiredAgo', 'vencida há {d}d').replace('{d}', String(Math.abs(s.days ?? 0)))
                          : t('comp.affiliationQueue.expiresIn', 'vence em {d}d').replace('{d}', String(s.days ?? 0));
                        return (
                          <div className={`text-[12px] ${cls}`}>
                            <div className="flex items-center gap-1"><CalendarClock size={11} /> {s.expiry}</div>
                            <div className="text-[10px]">{rel}</div>
                          </div>
                        );
                      })()}
                    </td>
                    <td className="px-3 py-2">
                      {(() => {
                        const tm = termMeta(r.term_status, t);
                        return (
                          <div className="space-y-0.5">
                            <span className={`inline-block text-[10px] px-2 py-0.5 rounded-full font-semibold ${tm.cls}`}>{tm.emoji} {tm.label}</span>
                            {r.term_end_date && (
                              <div className={`text-[10px] flex items-center gap-0.5 ${r.term_status === 'expired' ? 'text-rose-600' : r.term_status === 'expiring' ? 'text-amber-600' : 'text-[var(--text-muted)]'}`}>
                                <CalendarClock size={10} /> {fmtDate(r.term_end_date)}
                              </div>
                            )}
                          </div>
                        );
                      })()}
                    </td>
                    <td className="px-3 py-2 text-center">
                      {r.vep_status_raw
                        ? <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-semibold ${VEP_CLS[r.vep_status_raw] || 'bg-slate-100 text-slate-600'}`}>{r.vep_status_raw}</span>
                        : <span className="text-[var(--text-muted)]">—</span>}
                    </td>
                    <td className="px-3 py-2 text-center">
                      <span className={`text-[10px] px-2 py-0.5 rounded-full font-semibold ${f.cls} ${f.provisional ? 'border border-dashed border-current' : ''}`}
                        title={f.provisional ? t('comp.affiliationQueue.provisionalHint', 'Status derivado do VEP — ainda não confirmado pela Diretoria de Filiação') : f.label}>
                        {f.emoji} {f.label}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-center">
                      <button onClick={() => requireAttest(() => openVerify(r))}
                        className="text-[11px] px-2.5 py-1 rounded-full font-semibold border-0 cursor-pointer bg-emerald-50 text-emerald-700 hover:bg-emerald-100 inline-flex items-center gap-1">
                        <SearchCheck size={12} /> {t('comp.affiliationQueue.verify', 'Verificar')}
                      </button>
                    </td>
                  </tr>
                  {/* #996 F-A — PMI identity panel (expand per row) */}
                  {expanded && (
                    <tr className="border-t border-[var(--border-default)] bg-[var(--surface-section-cool)]">
                      <td></td>
                      <td colSpan={8} className="px-3 py-3">
                        {p ? (
                          <div className="flex flex-wrap gap-x-8 gap-y-2 text-[12px]">
                            <div>
                              <div className="text-[.6rem] uppercase tracking-wider text-[var(--text-muted)] flex items-center gap-1"><IdCard size={11} /> {t('comp.affiliationQueue.panelPmiId', 'PMI ID')}</div>
                              {p.pmi_id ? (
                                <a href={vepProfileUrl(p.pmi_id)} target="_blank" rel="noopener noreferrer"
                                   title={t('comp.affiliationQueue.openVepProfile', 'Abrir perfil no PMI VEP (volunteer.pmi.org) para verificar a filiação')}
                                   className="font-medium text-teal-700 hover:text-teal-800 hover:underline inline-flex items-center gap-1">
                                  {p.pmi_id} <ExternalLink size={11} className="opacity-70" />
                                </a>
                              ) : (
                                <div className="font-medium text-[var(--text-primary)]">—</div>
                              )}
                            </div>
                            <div>
                              <div className="text-[.6rem] uppercase tracking-wider text-[var(--text-muted)]">{t('comp.affiliationQueue.panelSince', 'Membro desde')}</div>
                              <div className="font-medium text-[var(--text-primary)]">{fmtDate(p.member_since)}</div>
                            </div>
                            <div>
                              <div className="text-[.6rem] uppercase tracking-wider text-[var(--text-muted)]">{t('comp.affiliationQueue.panelUntil', 'Membro até')}</div>
                              <div className="font-medium text-[var(--text-primary)]">{fmtDate(p.member_until)}</div>
                            </div>
                            <div>
                              <div className="text-[.6rem] uppercase tracking-wider text-[var(--text-muted)]">{t('comp.affiliationQueue.panelVolunteer', 'Registros de serviço PMI')}</div>
                              <div className="font-medium text-[var(--text-primary)]">{p.volunteer_count ?? '—'}</div>
                            </div>
                            <div>
                              <div className="text-[.6rem] uppercase tracking-wider text-[var(--text-muted)]">{t('comp.affiliationQueue.panelLastSync', 'Última sincronização VEP')}</div>
                              <div className="font-medium text-[var(--text-primary)]">{fmtDate(p.last_sync || r.vep_last_seen_at, true)}</div>
                            </div>
                          </div>
                        ) : (
                          <div className="text-[12px] text-amber-600 flex items-center gap-1"><Info size={12} /> {t('comp.affiliationQueue.panelNoProfile', 'Sem enriquecimento VEP — verifique manualmente.')}</div>
                        )}
                      </td>
                    </tr>
                  )}
                  </Fragment>
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
