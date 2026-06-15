import { useState, useEffect, useCallback, useRef } from 'react';
import { Search, Edit2, Users, UserX, ShieldOff, Loader2, X } from 'lucide-react';
import { trackEvent } from '../../../lib/analytics';
import { usePageI18n } from '../../../i18n/usePageI18n';
import { loadChapters, type Chapter } from '../../../lib/chapters';
import { loadInitiatives, type Initiative } from '../../../lib/initiatives';
import { getEffectiveLocale } from '../../../i18n/utils';

/* ────── Types ────── */
interface MemberRow {
  id: string;
  full_name: string;
  email: string;
  photo_url: string | null;
  operational_role: string;
  designations: string[];
  is_superadmin: boolean;
  is_active: boolean;
  member_status: string;
  /* #625 C0: derived — active member whose ONLY active engagements still await the volunteer term. */
  is_pre_onboarding: boolean;
  tribe_id: number | null;
  tribe_name: string | null;
  chapter: string;
  auth_id: string | null;
  last_seen_at: string | null;
  total_sessions: number;
  credly_username: string | null;
  offboarded_at: string | null;
  status_change_reason: string | null;
  /* p153 GAP-152.3: VEP status from latest selection_applications row linked by email. */
  vep_status_raw: string | null;
  vep_last_seen_at: string | null;
  /* #625 F1: affiliation farol — surfaced by admin_list_members from the append-only trail. */
  pmi_id_verified: boolean;
  affiliation_last_verified_at: string | null;
  affiliation_active: boolean | null;
  affiliation_expires_on: string | null;
  affiliation_method: string | null;
  /* #625 C2: V4-native — active engagements with catalog vocabulary (PT display_name + i18n). */
  engagements: EngagementRow[];
  /* #625 C2: distinct cycles the member participated in (member_cycle_history). */
  cycles: CycleRow[];
  /* #625 C2 (D2=B1): volunteer-term farol — 'green' | 'amber'. 🔴 vencido deferred to #571. */
  term_status: string;
}

interface EngagementRow {
  kind: string;
  role: string | null;
  initiative_id: string | null;
  initiative_title: string | null;
  kind_display_name: string;
  kind_display_i18n: { en?: string; es?: string } | null;
}
interface CycleRow {
  cycle_code: string;
  cycle_label: string;
}

type Locale = 'pt-BR' | 'en-US' | 'es-LATAM';

/* #625 C2 (D1=C) — locale-aware label for an engagement kind. display_name is the
   PT-BR canonical/fallback; display_i18n carries {en,es} from the catalog (config). */
function kindLabel(e: EngagementRow, locale: Locale): string {
  if (locale === 'en-US') return e.kind_display_i18n?.en || e.kind_display_name;
  if (locale === 'es-LATAM') return e.kind_display_i18n?.es || e.kind_display_name;
  return e.kind_display_name;
}

/* #625 C2 — chronological sort key for a cycle_code ('cycle_1'..'cycle_N'); a non-numbered
   code like 'pilot' (the 2024 pilot, oldest) sorts before all numbered cycles. */
function cycleOrder(code: string): number {
  const m = code.match(/(\d+)/);
  return m ? parseInt(m[1], 10) : -1;
}

// NOTE: OPROLE_LABELS and DESIG_LABELS are module-scope constants with Portuguese strings;
// i18n for these labels is deferred (would require refactoring to per-render lookup).
const OPROLE_LABELS: Record<string, string> = {
  manager: 'GP', deputy_manager: 'Vice-GP', tribe_leader: 'Líder de Tribo',
  researcher: 'Pesquisador(a)', facilitator: 'Facilitador(a)',
  communicator: 'Comunicador(a)', none: 'Sem papel', guest: 'Convidado',
};
const OPROLE_COLORS: Record<string, string> = {
  manager: '#FF610F', deputy_manager: '#FF610F', tribe_leader: '#2563EB',
  researcher: '#0D9488', facilitator: '#8B5CF6', communicator: '#06B6D4',
};
const DESIG_LABELS: Record<string, string> = {
  sponsor: 'Patrocinador', chapter_liaison: 'Elo Capítulo', ambassador: 'Embaixador',
  founder: 'Fundador', curator: 'Curador', comms_team: 'Equipe Comms',
  comms_leader: 'Líder Comms', comms_member: 'Membro Comms', co_gp: 'Co-GP',
};
const DESIG_COLORS: Record<string, string> = {
  sponsor: '#BE2027', chapter_liaison: '#BE2027', ambassador: '#10B981',
  founder: '#7C3AED', curator: '#D97706', comms_team: '#06B6D4',
  comms_leader: '#06B6D4', comms_member: '#06B6D4', co_gp: '#FF610F',
};

const ALL_ROLES = ['manager', 'deputy_manager', 'tribe_leader', 'researcher', 'facilitator', 'communicator', 'none', 'guest'];
const ALL_DESIGS = ['sponsor', 'chapter_liaison', 'ambassador', 'founder', 'curator', 'comms_team', 'comms_leader', 'comms_member', 'co_gp'];

function initials(name: string): string {
  return name.split(' ').map(w => w[0]).filter(Boolean).join('').substring(0, 2).toUpperCase() || '?';
}

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  return `${days}d`;
}

/* #625 F1 — affiliation farol from the latest verification surfaced by admin_list_members.
   green = verified & active (not expiring); amber = active but expiring ≤30d; red = inactive
   or expired; neutral = never verified. Clickable chip opens the verify modal. */
function affiliationFarol(m: MemberRow, t: (key: string, fallback?: string) => string): { emoji: string; label: string; cls: string } {
  if (!m.affiliation_last_verified_at) {
    return { emoji: '⚪', label: t('comp.memberList.affUnverified', 'Filiação não verificada'), cls: 'bg-slate-100 text-slate-500' };
  }
  if (m.affiliation_active === false) {
    return { emoji: '🔴', label: t('comp.memberList.affInactive', 'Filiação PMI inativa'), cls: 'bg-rose-50 text-rose-700' };
  }
  if (m.affiliation_expires_on) {
    const days = Math.ceil((new Date(m.affiliation_expires_on).getTime() - Date.now()) / 86400000);
    if (days < 0) return { emoji: '🔴', label: t('comp.memberList.affExpired', 'Filiação vencida'), cls: 'bg-rose-50 text-rose-700' };
    if (days <= 30) return { emoji: '🟡', label: t('comp.memberList.affExpiring', 'Filiação vence em breve'), cls: 'bg-amber-50 text-amber-700' };
  }
  return { emoji: '🟢', label: t('comp.memberList.affVerified', 'Filiação PMI verificada'), cls: 'bg-emerald-50 text-emerald-700' };
}

/* #625 C2 (D2=B1) — volunteer-term farol. amber = member has an active engagement that
   requires the term and still has no agreement certificate; green = none pending.
   🔴 'vencido' is NOT rendered here (no term-validity anchor today → deferred to #571). */
function termFarol(status: string, t: (key: string, fallback?: string) => string): { emoji: string; label: string; cls: string } {
  if (status === 'amber') {
    return { emoji: '🟡', label: t('comp.memberList.termAmber', 'Termo de voluntariado pendente'), cls: 'bg-amber-50 text-amber-700' };
  }
  return { emoji: '🟢', label: t('comp.memberList.termGreen', 'Termo de voluntariado em dia'), cls: 'bg-emerald-50 text-emerald-700' };
}

/* p153 GAP-152.3 — VEP status raw badge inline next to member name/email.
   Color-coded chip with tooltip carrying full status label + last sync date.
   Renders nothing when vep_status_raw is null (pre-Phase-B-import era members). */
function VepStatusBadge({ status, lastSeenAt, t }: { status: string | null; lastSeenAt: string | null; t: (key: string, fallback?: string) => string }) {
  if (!status) return null;
  const entry: { short: string; long: string; cls: string } = (() => {
    switch (status) {
      case 'Submitted': return { short: t('comp.vepBadge.submitted', 'VEP·Subm'), long: t('comp.vepBadge.statusSubmitted', 'Submetido (em análise)'), cls: 'bg-blue-50 text-blue-700' };
      case 'Active': return { short: t('comp.vepBadge.active', 'VEP·Ativ'), long: t('comp.vepBadge.statusActive', 'Ativo (servindo)'), cls: 'bg-emerald-50 text-emerald-700' };
      case 'Withdrawn': return { short: t('comp.vepBadge.withdrawn', 'VEP·Saiu'), long: t('comp.vepBadge.statusWithdrawn', 'Desistiu'), cls: 'bg-gray-100 text-gray-600' };
      case 'Declined': return { short: t('comp.vepBadge.declined', 'VEP·Recus'), long: t('comp.vepBadge.statusDeclined', 'Recusado pelo recrutador'), cls: 'bg-rose-50 text-rose-700' };
      case 'OfferNotExtended': return { short: t('comp.vepBadge.offerNotExtended', 'VEP·SemOf'), long: t('comp.vepBadge.statusOfferNotExtended', 'Sem oferta'), cls: 'bg-amber-50 text-amber-700' };
      default: return { short: t('comp.vepBadge.unknown', 'VEP·?'), long: status, cls: 'bg-slate-100 text-slate-600' };
    }
  })();
  const lastSyncStr = lastSeenAt ? new Date(lastSeenAt).toLocaleDateString('pt-BR') : '—';
  const tooltip = `${t('comp.vepBadge.tooltipPrefix', 'Status no PMI VEP')}: ${entry.long} · ${t('comp.vepBadge.lastSync', 'Última sync VEP')} ${lastSyncStr}`;
  return (
    <span className={`text-[.55rem] font-bold px-1.5 py-0.5 rounded-full ${entry.cls} whitespace-nowrap`} title={tooltip}>
      {entry.short}
    </span>
  );
}

/* ────── Component ────── */
export default function MemberListIsland() {
  const t = usePageI18n();
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [tierFilter, setTierFilter] = useState('');
  const [tribeFilter, setTribeFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('active');
  const [designationFilter, setDesignationFilter] = useState('');
  // #625 C2: V4-native filters (initiative/chapter/cycle) passed straight to the RPC.
  const [initiativeFilter, setInitiativeFilter] = useState('');
  const [chapterFilter, setChapterFilter] = useState('');
  const [cycleFilter, setCycleFilter] = useState('');
  const [initiatives, setInitiatives] = useState<Initiative[]>([]);
  // Resolved once: PT-BR canonical, en/es from the catalog (D1=C). Cheap; reads localStorage/URL.
  const [locale] = useState<Locale>(() => getEffectiveLocale() as Locale);
  const [editMember, setEditMember] = useState<MemberRow | null>(null);
  const [saving, setSaving] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Bulk operation state
  const [showBulkAllocate, setShowBulkAllocate] = useState(false);
  const [showBulkStatus, setShowBulkStatus] = useState(false);
  const [bulkTribeId, setBulkTribeId] = useState('');
  const [bulkActive, setBulkActive] = useState(true);
  const [bulkSaving, setBulkSaving] = useState(false);

  // Edit form state
  const [editRole, setEditRole] = useState('');
  const [editDesigs, setEditDesigs] = useState<string[]>([]);
  const [editChapter, setEditChapter] = useState('');
  const [editActive, setEditActive] = useState(true);
  const [editSuperadmin, setEditSuperadmin] = useState(false);
  const [chapters, setChapters] = useState<Chapter[]>([]);

  // Offboarding state
  const [offboardMember, setOffboardMember] = useState<MemberRow | null>(null);
  const [offboardStatus, setOffboardStatus] = useState('observer');
  const [offboardCategory, setOffboardCategory] = useState('time');
  const [offboardDetail, setOffboardDetail] = useState('');
  const [offboardReassign, setOffboardReassign] = useState('');
  const [offboardSaving, setOffboardSaving] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const fetchMembers = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(fetchMembers, 300); return; }
    setLoading(true);
    const { data, error } = await sb.rpc('admin_list_members', {
      p_search: search || null,
      p_tier: tierFilter || null,
      p_tribe_id: tribeFilter ? parseInt(tribeFilter) : null,
      p_status: statusFilter,
      p_initiative_id: initiativeFilter || null,
      p_chapter: chapterFilter || null,
      p_cycle: cycleFilter || null,
    });
    if (!error && data) setMembers(data);
    setLoading(false);
  }, [search, tierFilter, tribeFilter, statusFilter, initiativeFilter, chapterFilter, cycleFilter, getSb]);

  // p190 BUG-190.B sweep: ref pattern + cleanup to avoid listener accumulation.
  const fetchMembersRef = useRef(fetchMembers);
  fetchMembersRef.current = fetchMembers;
  useEffect(() => {
    let cancelled = false;
    const boot = () => {
      if (cancelled) return;
      if (getSb()) fetchMembersRef.current();
      else setTimeout(boot, 300);
    };
    boot();
    const handler = () => fetchMembersRef.current();
    window.addEventListener('nav:member', handler);
    loadChapters().then(setChapters);
    loadInitiatives().then(setInitiatives);
    return () => {
      cancelled = true;
      window.removeEventListener('nav:member', handler);
    };
  }, []);

  // Re-fetch when filters change (debounce search)
  useEffect(() => {
    const timer = setTimeout(() => {
      fetchMembers();
      if (search || tierFilter || tribeFilter || statusFilter || initiativeFilter || chapterFilter || cycleFilter) {
        trackEvent('member_searched', { search_term_length: search.length, filter_count: [tierFilter, tribeFilter, statusFilter, initiativeFilter, chapterFilter, cycleFilter].filter(Boolean).length });
      }
    }, search ? 400 : 0);
    return () => clearTimeout(timer);
  }, [search, tierFilter, tribeFilter, statusFilter, initiativeFilter, chapterFilter, cycleFilter]);

  // Stats (always fetch 'all' for accurate counts)
  const [allMembers, setAllMembers] = useState<MemberRow[]>([]);
  useEffect(() => {
    (async () => {
      const sb = getSb(); if (!sb) return;
      const { data } = await sb.rpc('admin_list_members', { p_status: 'all' });
      if (data) setAllMembers(data);
    })();
  }, [members, getSb]);
  const total = allMembers.length || members.length;
  // #625 C0: 'Ativos' = operating actives only; the cycle-N pre-onboarding cohort counts apart.
  const active = allMembers.filter(m => m.member_status === 'active' && !m.is_pre_onboarding).length;
  const preOnboarding = allMembers.filter(m => m.is_pre_onboarding).length;
  const observers = allMembers.filter(m => m.member_status === 'observer').length;
  const alumni = allMembers.filter(m => m.member_status === 'alumni').length;
  const noAuth = allMembers.filter(m => !m.auth_id).length;
  const noTribe = allMembers.filter(m => !m.tribe_id && m.member_status === 'active' && !m.is_pre_onboarding).length;

  // History modal state
  const [historyMemberId, setHistoryMemberId] = useState<string | null>(null);
  const [historyMemberName, setHistoryMemberName] = useState('');
  const [transitions, setTransitions] = useState<any[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);

  const openHistory = async (m: MemberRow) => {
    setHistoryMemberId(m.id);
    setHistoryMemberName(m.full_name);
    setHistoryLoading(true);
    setTransitions([]);
    const sb = getSb(); if (!sb) return;
    const { data } = await sb.rpc('get_member_transitions', { p_member_id: m.id });
    if (data?.transitions) setTransitions(data.transitions);
    setHistoryLoading(false);
  };

  // Unique tribes for filter
  const tribes = [...new Map(members.filter(m => m.tribe_id).map(m => [m.tribe_id, m.tribe_name])).entries()]
    .sort((a, b) => (a[0] || 0) - (b[0] || 0));

  // #625 C2: cycle options derived from the full cohort (union of members' cycles[]) —
  // data-driven, no extra RPC. value = cycle_code (what the RPC's p_cycle expects).
  // Chronological numeric sort (not lexicographic — else cycle_10 < cycle_2); non-numbered
  // codes like 'pilot' sort first as the oldest.
  const cycleOptions = [...new Map((allMembers.length ? allMembers : members)
    .flatMap(m => m.cycles || [])
    .map(c => [c.cycle_code, c.cycle_label]))
    .entries()].sort((a, b) => cycleOrder(a[0]) - cycleOrder(b[0]));

  // Open edit modal
  const openEdit = (m: MemberRow) => {
    setEditMember(m);
    setEditRole(m.operational_role);
    setEditDesigs([...m.designations]);
    setEditChapter(m.chapter || 'PMI-GO');
    setEditActive(m.is_active);
    setEditSuperadmin(m.is_superadmin);
  };

  const closeEdit = () => setEditMember(null);

  const saveEdit = async () => {
    if (!editMember) return;
    const sb = getSb();
    if (!sb) return;
    setSaving(true);
    const { error } = await sb.rpc('admin_update_member', {
      p_member_id: editMember.id,
      p_operational_role: editRole,
      p_designations: editDesigs,
      p_chapter: editChapter,
      p_current_cycle_active: editActive,
    });
    if (!error) {
      // Update superadmin if changed
      if (editSuperadmin !== editMember.is_superadmin) {
        await sb.from('members').update({ is_superadmin: editSuperadmin }).eq('id', editMember.id);
      }
      (window as any).toast?.(t('comp.memberList.memberUpdated', 'Membro atualizado'), 'success');
      closeEdit();
      await fetchMembers();
    } else {
      (window as any).toast?.(error.message || t('comp.memberList.saveError', 'Erro ao salvar'), 'error');
    }
    setSaving(false);
  };

  const handleOffboard = async () => {
    if (!offboardMember) return;
    const sb = getSb();
    if (!sb) return;
    setOffboardSaving(true);
    const { data, error } = await sb.rpc('admin_offboard_member', {
      p_member_id: offboardMember.id,
      p_new_status: offboardStatus,
      p_reason_category: offboardCategory,
      p_reason_detail: offboardDetail || null,
      p_reassign_to: offboardReassign || null,
    });
    setOffboardSaving(false);
    if (error || data?.error) {
      (window as any).toast?.(data?.error || error?.message || 'Erro', 'error');
      return;
    }
    (window as any).toast?.(`${offboardMember.full_name} → ${offboardStatus}`, 'success');
    setOffboardMember(null);
    await fetchMembers();
  };

  const handleReactivate = async (member: MemberRow) => {
    const sb = getSb();
    if (!sb) return;
    const tribeId = prompt('Tribe ID para reactivação (1-8):');
    if (!tribeId) return;
    const { data, error } = await sb.rpc('admin_reactivate_member', {
      p_member_id: member.id,
      p_tribe_id: parseInt(tribeId, 10),
      p_role: 'researcher',
    });
    if (error || data?.error) {
      (window as any).toast?.(data?.error || error?.message || 'Erro', 'error');
      return;
    }
    (window as any).toast?.(`${member.full_name} reactivado!`, 'success');
    await fetchMembers();
  };

  const toggleDesig = (d: string) => {
    setEditDesigs(prev => prev.includes(d) ? prev.filter(x => x !== d) : [...prev, d]);
  };

  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  // #625 C0 (council HIGH): selection must operate on the PARTITIONED view — selecting against
  // the raw array would silently enqueue hidden pre-onboarding rows into bulk operations.
  const visibleMembers = statusFilter === 'active' ? members.filter(m => !m.is_pre_onboarding) : members;

  const toggleSelectAll = () => {
    if (selectedIds.size === visibleMembers.length) setSelectedIds(new Set());
    else setSelectedIds(new Set(visibleMembers.map(m => m.id)));
  };

  const handleBulkAllocate = async () => {
    if (!bulkTribeId) return;
    const sb = getSb();
    if (!sb) return;
    setBulkSaving(true);
    const { data, error } = await sb.rpc('admin_bulk_allocate_tribe', {
      p_member_ids: [...selectedIds],
      p_tribe_id: parseInt(bulkTribeId),
    });
    if (!error && data?.success) {
      (window as any).toast?.(`${data.count} ${t('comp.memberList.membersAllocated', 'membro(s) alocado(s)')}`, 'success');
      setSelectedIds(new Set());
      setShowBulkAllocate(false);
      setBulkTribeId('');
      await fetchMembers();
    } else {
      (window as any).toast?.(error?.message || t('comp.memberList.operationError', 'Erro na operação'), 'error');
    }
    setBulkSaving(false);
  };

  const handleBulkStatus = async () => {
    const sb = getSb();
    if (!sb) return;
    setBulkSaving(true);
    const { data, error } = await sb.rpc('admin_bulk_set_status', {
      p_member_ids: [...selectedIds],
      p_is_active: bulkActive,
    });
    if (!error && data?.success) {
      (window as any).toast?.(`${data.count} ${bulkActive ? t('comp.memberList.membersActivated', 'membro(s) ativado(s)') : t('comp.memberList.membersDeactivated', 'membro(s) desativado(s)')}`, 'success');
      setSelectedIds(new Set());
      setShowBulkStatus(false);
      await fetchMembers();
    } else {
      (window as any).toast?.(error?.message || t('comp.memberList.operationError', 'Erro na operação'), 'error');
    }
    setBulkSaving(false);
  };

  // #625 F1: affiliation verification (individual modal + bulk VEP)
  const [verifyMember, setVerifyMember] = useState<MemberRow | null>(null);
  const [verifyActive, setVerifyActive] = useState(true);
  const [verifyExpires, setVerifyExpires] = useState('');
  const [verifyMethod, setVerifyMethod] = useState('sede_manual');
  const [verifyObs, setVerifyObs] = useState('');
  const [verifySaving, setVerifySaving] = useState(false);
  const [bulkVerifying, setBulkVerifying] = useState(false);

  const openVerify = (m: MemberRow) => {
    setVerifyMember(m);
    setVerifyActive(m.affiliation_active !== false);
    setVerifyExpires(m.affiliation_expires_on || '');
    setVerifyMethod('sede_manual');
    setVerifyObs('');
  };

  const handleVerify = async () => {
    if (!verifyMember) return;
    const sb = getSb(); if (!sb) return;
    setVerifySaving(true);
    const { data, error } = await sb.rpc('verify_member_affiliation', {
      p_member_id: verifyMember.id,
      p_chapter: verifyMember.chapter || null,
      p_active: verifyActive,
      p_expires_on: verifyExpires || null,
      p_method: verifyMethod,
      p_obs: verifyObs || null,
    });
    setVerifySaving(false);
    if (error || data?.error) {
      (window as any).toast?.(error?.message || data?.error || t('comp.memberList.saveError', 'Erro ao salvar'), 'error');
      return;
    }
    (window as any).toast?.(t('comp.memberList.verifyDone', 'Filiação verificada'), 'success');
    setVerifyMember(null);
    await fetchMembers();
  };

  // Bulk "marcar verificado via VEP" — the "25 em ≤1h" path on the pre_onboarding queue.
  const handleBulkVerifyVep = async () => {
    const sb = getSb(); if (!sb) return;
    setBulkVerifying(true);
    const { data, error } = await sb.rpc('verify_member_affiliations_bulk', {
      p_member_ids: [...selectedIds],
      p_method: 'vep_sync',
    });
    setBulkVerifying(false);
    if (error || !data?.ok) {
      (window as any).toast?.(error?.message || t('comp.memberList.operationError', 'Erro na operação'), 'error');
      return;
    }
    const noVep = (data.no_vep_ids || []).length;
    const notFound = (data.not_found_ids || []).length;
    const warn = noVep + notFound > 0;
    (window as any).toast?.(
      `${data.count} ${t('comp.memberList.verifyDone', 'Filiação verificada')} (VEP)` +
      (noVep ? ` · ${noVep} sem VEP` : '') + (notFound ? ` · ${notFound} não encontrado(s)` : ''),
      warn ? 'warning' : 'success');
    setSelectedIds(new Set());
    await fetchMembers();
  };

  // #625 F1b: ateste de acesso (confidencialidade/finalidade) — gate just-in-time + re-aceite anual.
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
  }, []);

  // Gate de escrita: se o agente (filiacao_director) ainda não atestou, abre o modal antes da ação.
  // manager/PM tem needs_attestation=false (servidor) → passa direto. Backstop server-side via trigger.
  const requireAttest = (action: () => void) => {
    if (attestation?.needs_attestation) {
      setPendingAttest(() => action);
      setAttestChecked(false);
      setShowAttest(true);
    } else {
      action();
    }
  };

  const handleAttest = async () => {
    const sb = getSb(); if (!sb) return;
    setAttesting(true);
    const { data, error } = await sb.rpc('attest_affiliation_access', { p_signed_user_agent: navigator.userAgent });
    setAttesting(false);
    if (error || !data?.ok) {
      (window as any).toast?.(error?.message || t('comp.memberList.operationError', 'Erro na operação'), 'error');
      return;
    }
    const { data: att } = await sb.rpc('get_my_affiliation_attestation');
    if (att) setAttestation(att);
    setShowAttest(false);
    const act = pendingAttest;
    setPendingAttest(null);
    act?.();
  };

  return (
    <div className="max-w-[1200px] mx-auto">
      {/* Stat cards */}
      <div className="grid grid-cols-3 sm:grid-cols-7 gap-3 mb-6">
        {[
          { label: t('comp.memberList.total', 'Total'), value: total, icon: <Users size={16} /> },
          { label: t('comp.memberList.active', 'Ativos'), value: active, color: 'text-emerald-500' },
          { label: t('comp.memberList.preOnboarding', 'Pré-onboarding'), value: preOnboarding, color: 'text-orange-500' },
          { label: 'Observers', value: observers, color: 'text-blue-500' },
          { label: 'Alumni', value: alumni, color: 'text-slate-500' },
          { label: t('comp.memberList.noTribe', 'Sem tribo'), value: noTribe, color: 'text-amber-500' },
          { label: t('comp.memberList.noLogin', 'Sem login'), value: noAuth, color: 'text-slate-400' },
        ].map(s => (
          <div key={s.label} className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-3 text-center">
            <div className={`text-2xl font-black ${s.color || 'text-[var(--text-primary)]'}`}>{s.value}</div>
            <div className="text-[.7rem] text-[var(--text-muted)] font-semibold uppercase tracking-wider">{s.label}</div>
          </div>
        ))}
      </div>

      {/* Filters row */}
      <div className="flex flex-wrap gap-2 mb-4">
        <div className="relative flex-1 min-w-[200px]">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
          <input
            type="text"
            placeholder={t('comp.memberList.searchPlaceholder', 'Buscar por nome ou email...')}
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-primary)] text-sm focus:outline-none focus:border-teal-500"
          />
        </div>
        <select value={tierFilter} onChange={e => setTierFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="">{t('comp.memberList.allRoles', 'Todos os papéis')}</option>
          {ALL_ROLES.map(r => <option key={r} value={r}>{OPROLE_LABELS[r] || r}</option>)}
        </select>
        <select value={tribeFilter} onChange={e => setTribeFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="">{t('comp.memberList.allTribes', 'Todas as tribos')}</option>
          {tribes.map(([id, name]) => <option key={id} value={String(id)}>T{String(id).padStart(2, '0')} — {name}</option>)}
        </select>
        <select value={designationFilter} onChange={e => setDesignationFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="">Todas designações</option>
          {ALL_DESIGS.map(d => <option key={d} value={d}>{DESIG_LABELS[d] || d}</option>)}
        </select>
        {/* #625 C2: V4-native filters — Iniciativa / Capítulo / Ciclo */}
        <select value={initiativeFilter} onChange={e => setInitiativeFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="">{t('comp.memberList.allInitiatives', 'Todas as iniciativas')}</option>
          {initiatives.map(i => <option key={i.id} value={i.id}>{i.title}</option>)}
        </select>
        <select value={chapterFilter} onChange={e => setChapterFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="">{t('comp.memberList.allChapters', 'Todos os capítulos')}</option>
          {chapters.map(c => <option key={c.display_code} value={c.display_code}>{c.display_code}</option>)}
        </select>
        <select value={cycleFilter} onChange={e => setCycleFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="">{t('comp.memberList.allCycles', 'Todos os ciclos')}</option>
          {cycleOptions.map(([code, label]) => <option key={code} value={code}>{label}</option>)}
        </select>
        <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="active">{t('comp.memberList.active', 'Ativos')}</option>
          <option value="pre_onboarding">{t('comp.memberList.preOnboarding', 'Pré-onboarding')}</option>
          <option value="observer">Observer</option>
          <option value="alumni">Alumni</option>
          <option value="inactive">{t('comp.memberList.inactive', 'Inativos')}</option>
          <option value="all">{t('comp.memberList.all', 'Todos')}</option>
        </select>
      </div>

      {/* Bulk action bar */}
      {selectedIds.size > 0 && (
        <div className="sticky top-0 z-10 mb-3 px-4 py-2.5 bg-teal-600/10 border border-teal-500/30 rounded-lg text-sm font-semibold flex items-center gap-2 flex-wrap">
          <span className="text-teal-500">✓ {selectedIds.size} {t('comp.memberList.selected', 'selecionado(s)')}</span>
          <div className="ml-auto flex gap-2">
            <button onClick={() => setShowBulkAllocate(true)} className="px-3 py-1.5 text-[13px] bg-teal-600 text-white rounded-lg border-0 cursor-pointer hover:bg-teal-700">
              {t('comp.memberList.allocateToTribe', 'Alocar em Tribo')}
            </button>
            <button onClick={() => setShowBulkStatus(true)} className="px-3 py-1.5 text-[13px] bg-amber-500 text-white rounded-lg border-0 cursor-pointer hover:bg-amber-600">
              {t('comp.memberList.changeStatus', 'Mudar Status')}
            </button>
            <button onClick={() => requireAttest(handleBulkVerifyVep)} disabled={bulkVerifying} className="px-3 py-1.5 text-[13px] bg-indigo-600 text-white rounded-lg border-0 cursor-pointer hover:bg-indigo-700 disabled:opacity-50">
              {bulkVerifying ? t('comp.memberList.verifying', 'Verificando...') : t('comp.memberList.bulkVerifyVep', 'Verificar filiação (VEP)')}
            </button>
            <button onClick={() => setSelectedIds(new Set())} className="px-3 py-1.5 text-[13px] text-[var(--text-muted)] hover:text-[var(--text-primary)] bg-transparent border-0 cursor-pointer">
              {t('comp.memberList.cancel', 'Cancelar')}
            </button>
          </div>
        </div>
      )}

      {/* Table */}
      {loading ? (
        <div className="flex items-center justify-center py-16 text-[var(--text-muted)]">
          <Loader2 size={24} className="animate-spin mr-2" /> {t('comp.memberList.loading', 'Carregando membros...')}
        </div>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-[var(--border-default)]">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-[var(--surface-section-cool)] text-[var(--text-muted)] text-[.7rem] uppercase tracking-wider">
                <th className="px-3 py-2 text-left w-10">
                  <input type="checkbox" checked={selectedIds.size === visibleMembers.length && visibleMembers.length > 0} onChange={toggleSelectAll} className="accent-teal-500" />
                </th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thMember', 'Membro')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thRoleDesig', 'Papel / Designações')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thTribe', 'Tribo')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thChapter', 'Capítulo')}</th>
                <th className="px-3 py-2 text-center">{t('comp.memberList.thAffiliation', 'Filiação')}</th>
                <th className="px-3 py-2 text-center">{t('comp.memberList.thTerm', 'Termo')}</th>
                <th className="px-3 py-2 text-center">{t('comp.memberList.thStatus', 'Status')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thLastSeen', 'Último acesso')}</th>
                <th className="px-3 py-2 text-center w-16">{t('comp.memberList.thActions', 'Ações')}</th>
              </tr>
            </thead>
            <tbody>
              {(designationFilter ? visibleMembers.filter(m => (m.designations || []).includes(designationFilter)) : visibleMembers).map(m => (
                <tr key={m.id} className="border-t border-[var(--border-default)] hover:bg-[var(--surface-hover)] transition-colors">
                  <td className="px-3 py-2">
                    <input type="checkbox" checked={selectedIds.has(m.id)} onChange={() => toggleSelect(m.id)} className="accent-teal-500" />
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-2.5">
                      {m.photo_url
                        ? <img src={m.photo_url} className="w-8 h-8 rounded-full object-cover flex-shrink-0" alt="" />
                        : <div className="w-8 h-8 rounded-full bg-teal-600 flex items-center justify-center text-white text-[.6rem] font-bold flex-shrink-0">{initials(m.full_name)}</div>
                      }
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <a href={`/admin/members/${m.id}`} className="font-medium text-[var(--text-primary)] hover:underline truncate no-underline">{m.full_name}</a>
                          <VepStatusBadge status={m.vep_status_raw} lastSeenAt={m.vep_last_seen_at} t={t} />
                        </div>
                        <div className="text-[.7rem] text-[var(--text-muted)] truncate">{m.email}</div>
                        {/* #625 C2: cycle tags (member_cycle_history) */}
                        {(m.cycles?.length ?? 0) > 0 && (
                          <div className="flex flex-wrap gap-1 mt-0.5">
                            {m.cycles.map(c => (
                              <span key={c.cycle_code} title={c.cycle_label}
                                className="text-[.55rem] font-semibold px-1.5 py-0.5 rounded-full bg-slate-100 text-slate-500 whitespace-nowrap">
                                {c.cycle_code.startsWith('cycle_') ? `C${c.cycle_code.slice(6)}` : c.cycle_code}
                              </span>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex flex-wrap gap-1">
                      {m.operational_role && m.operational_role !== 'none' && m.operational_role !== 'guest' && (
                        <span className="text-[.6rem] font-bold px-1.5 py-0.5 rounded" style={{ background: `${OPROLE_COLORS[m.operational_role] || '#94A3B8'}18`, color: OPROLE_COLORS[m.operational_role] || '#94A3B8' }}>
                          {OPROLE_LABELS[m.operational_role] || m.operational_role}
                        </span>
                      )}
                      {m.designations?.map(d => (
                        <span key={d} className="text-[.6rem] font-bold px-1.5 py-0.5 rounded" style={{ background: `${DESIG_COLORS[d] || '#94A3B8'}18`, color: DESIG_COLORS[d] || '#94A3B8' }}>
                          {DESIG_LABELS[d] || d}
                        </span>
                      ))}
                      {m.is_superadmin && <span className="text-[.6rem] font-bold px-1.5 py-0.5 rounded bg-orange-500/10 text-orange-500">🔧 SA</span>}
                      {/* #625 C2: V4-native engagement categories (deduped by kind, locale-aware catalog label). */}
                      {[...new Map((m.engagements || []).map(e => [e.kind, e])).values()].map(e => (
                        <span key={e.kind} title={e.initiative_title || kindLabel(e, locale)}
                          className="text-[.6rem] font-bold px-1.5 py-0.5 rounded bg-indigo-500/10 text-indigo-600">
                          {kindLabel(e, locale)}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="px-3 py-2 text-[var(--text-secondary)]">
                    {m.tribe_name ? <span className="text-[.75rem]">T{String(m.tribe_id).padStart(2, '0')} {m.tribe_name}</span> : <span className="text-[var(--text-muted)]">—</span>}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-secondary)] text-[.8rem]">{m.chapter || '—'}</td>
                  <td className="px-3 py-2 text-center">
                    {(() => { const f = affiliationFarol(m, t); return (
                      <button onClick={() => requireAttest(() => openVerify(m))} title={`${f.label} — ${t('comp.memberList.verifyAffiliation', 'Verificar filiação')}`}
                        className={`text-[11px] px-2 py-0.5 rounded-full font-semibold border-0 cursor-pointer ${f.cls}`}>
                        {f.emoji}
                      </button>
                    ); })()}
                  </td>
                  <td className="px-3 py-2 text-center">
                    {(() => { const f = termFarol(m.term_status, t); return (
                      <span title={f.label} className={`text-[11px] px-2 py-0.5 rounded-full font-semibold ${f.cls}`}>{f.emoji}</span>
                    ); })()}
                  </td>
                  <td className="px-3 py-2 text-center">
                    {m.member_status === 'active' && (m.is_pre_onboarding
                      ? <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-orange-100 text-orange-700 font-semibold" title={t('comp.memberList.preOnboardingHint', 'Aprovado — aguardando termo de voluntariado/onboarding')}>⏳ {t('comp.memberList.preOnboarding', 'Pré-onboarding')}</span>
                      : '🟢')}
                    {m.member_status === 'observer' && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-blue-100 text-blue-700 font-semibold">👁 Observer</span>}
                    {m.member_status === 'alumni' && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-600 font-semibold">🎓 Alumni</span>}
                    {m.member_status === 'inactive' && '🔴'}
                    {!m.member_status && (m.is_active ? '🟢' : '🔴')}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)] text-[.8rem]">{m.last_seen_at ? timeAgo(m.last_seen_at) : '—'}</td>
                  <td className="px-3 py-2 text-center whitespace-nowrap">
                    <button onClick={() => openEdit(m)} className="p-1.5 rounded-lg hover:bg-[var(--surface-hover)] text-[var(--text-muted)] bg-transparent border-0 cursor-pointer" title={t('comp.memberList.edit', 'Editar')}>
                      <Edit2 size={14} />
                    </button>
                    <button onClick={() => openHistory(m)} className="p-1.5 rounded-lg hover:bg-[var(--surface-hover)] text-[var(--text-muted)] bg-transparent border-0 cursor-pointer" title="Histórico">
                      📋
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {members.length === 0 && !loading && (
            <div className="text-center py-12 text-[var(--text-muted)]">{t('comp.memberList.noMembers', 'Nenhum membro encontrado.')}</div>
          )}
        </div>
      )}

      {/* Edit Modal */}
      {editMember && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={closeEdit}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[480px] overflow-hidden flex flex-col" style={{ maxHeight: '90vh' }} onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)] flex justify-between items-center flex-shrink-0">
              <h3 className="text-base font-bold text-[var(--text-primary)]">{t('comp.memberList.editMember', 'Editar Membro')}</h3>
              <button onClick={closeEdit} className="bg-transparent border-0 text-xl cursor-pointer text-[var(--text-muted)]"><X size={18} /></button>
            </div>
            <div className="p-5 overflow-y-auto flex-1 space-y-4">
              {/* Header */}
              <div className="flex items-center gap-3">
                {editMember.photo_url
                  ? <img src={editMember.photo_url} className="w-12 h-12 rounded-full object-cover" alt="" />
                  : <div className="w-12 h-12 rounded-full bg-teal-600 flex items-center justify-center text-white font-bold">{initials(editMember.full_name)}</div>
                }
                <div>
                  <div className="font-semibold text-[var(--text-primary)]">{editMember.full_name}</div>
                  <div className="text-xs text-[var(--text-muted)]">{editMember.email}</div>
                </div>
              </div>

              {/* Operational Role */}
              <div className="p-3 rounded-xl bg-[var(--surface-base)] border border-[var(--border-default)]">
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase tracking-wider block mb-2">{t('comp.memberList.axis1Role', 'Eixo 1 — Papel Operacional')}</label>
                <select value={editRole} onChange={e => setEditRole(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                  {ALL_ROLES.map(r => <option key={r} value={r}>{OPROLE_LABELS[r] || r}</option>)}
                </select>
              </div>

              {/* Designations */}
              <div className="p-3 rounded-xl bg-[var(--surface-base)] border border-[var(--border-default)]">
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase tracking-wider block mb-2">{t('comp.memberList.axis2Desig', 'Eixo 2 — Designações')}</label>
                <div className="grid grid-cols-2 gap-1.5">
                  {ALL_DESIGS.map(d => (
                    <label key={d} className="flex items-center gap-2 px-2.5 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] hover:bg-[var(--surface-hover)] cursor-pointer text-[.75rem]">
                      <input type="checkbox" checked={editDesigs.includes(d)} onChange={() => toggleDesig(d)} className="accent-teal-500" />
                      <span style={{ color: DESIG_COLORS[d] }}>●</span> {DESIG_LABELS[d] || d}
                    </label>
                  ))}
                </div>
              </div>

              {/* Superadmin + Chapter + Status */}
              <div className="grid grid-cols-3 gap-3">
                <div className="flex flex-col gap-1.5">
                  <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase">{t('comp.memberList.chapter', 'Capítulo')}</label>
                  <select value={editChapter} onChange={e => setEditChapter(e.target.value)}
                    className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                    {chapters.map(c => <option key={c.display_code} value={c.display_code}>{c.display_code}</option>)}
                  </select>
                </div>
                <div className="flex flex-col gap-1.5">
                  <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase">{t('comp.memberList.status', 'Status')}</label>
                  <select value={String(editActive)} onChange={e => setEditActive(e.target.value === 'true')}
                    className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                    <option value="true">{t('comp.memberList.activeStatus', 'Ativo')}</option>
                    <option value="false">{t('comp.memberList.inactiveStatus', 'Inativo')}</option>
                  </select>
                </div>
                <div className="flex flex-col gap-1.5">
                  <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase">{t('comp.memberList.superadmin', 'Superadmin')}</label>
                  <label className="flex items-center gap-2 cursor-pointer pt-1">
                    <input type="checkbox" checked={editSuperadmin} onChange={e => setEditSuperadmin(e.target.checked)} className="accent-orange-500" />
                    <span className="text-sm text-[var(--text-secondary)]">🔧 SA</span>
                  </label>
                </div>
              </div>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex justify-between gap-2 flex-shrink-0">
              <div className="flex gap-2">
                {editMember.is_active ? (
                  <button onClick={() => { setOffboardMember(editMember); setOffboardStatus('observer'); setOffboardCategory('time'); setOffboardDetail(''); setOffboardReassign(''); closeEdit(); }}
                    className="px-3 py-2 rounded-lg text-[12px] font-semibold border border-amber-300 text-amber-700 bg-transparent hover:bg-amber-50 cursor-pointer">
                    Gerenciar Status
                  </button>
                ) : (
                  <button onClick={() => { handleReactivate(editMember); closeEdit(); }}
                    className="px-3 py-2 rounded-lg text-[12px] font-semibold border border-emerald-300 text-emerald-700 bg-transparent hover:bg-emerald-50 cursor-pointer">
                    Reactivar
                  </button>
                )}
              </div>
              <div className="flex gap-2">
                <button onClick={closeEdit} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.memberList.cancel', 'Cancelar')}</button>
                <button onClick={saveEdit} disabled={saving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                  {saving ? t('comp.memberList.saving', 'Salvando...') : t('comp.memberList.save', 'Salvar')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Bulk Allocate Modal */}
      {showBulkAllocate && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={() => setShowBulkAllocate(false)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[400px] overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)]">
              <h3 className="text-base font-bold text-[var(--text-primary)]">{t('comp.memberList.allocateTitle', 'Alocar')} {selectedIds.size} {t('comp.memberList.membersInTribe', 'membro(s) em tribo')}</h3>
            </div>
            <div className="p-5 space-y-4">
              <select value={bulkTribeId} onChange={e => setBulkTribeId(e.target.value)}
                className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
                <option value="">{t('comp.memberList.selectTribe', 'Selecione uma tribo...')}</option>
                {tribes.map(([id, name]) => <option key={id} value={String(id)}>T{String(id).padStart(2, '0')} — {name}</option>)}
              </select>
              <p className="text-sm text-[var(--text-muted)]">
                {t('comp.memberList.allocateConfirmPre', 'Esta ação alocará')} {selectedIds.size} {t('comp.memberList.allocateConfirmPost', 'membro(s) na tribo selecionada.')}
              </p>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex justify-end gap-2">
              <button onClick={() => setShowBulkAllocate(false)} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.memberList.cancel', 'Cancelar')}</button>
              <button onClick={handleBulkAllocate} disabled={!bulkTribeId || bulkSaving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                {bulkSaving ? t('comp.memberList.allocating', 'Alocando...') : t('comp.memberList.confirm', 'Confirmar')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Bulk Status Modal */}
      {showBulkStatus && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={() => setShowBulkStatus(false)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[400px] overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)]">
              <h3 className="text-base font-bold text-[var(--text-primary)]">{t('comp.memberList.changeStatusOf', 'Mudar status de')} {selectedIds.size} {t('comp.memberList.membersParens', 'membro(s)')}</h3>
            </div>
            <div className="p-5 space-y-4">
              <div className="flex gap-4">
                <label className="flex items-center gap-2 cursor-pointer text-sm text-[var(--text-primary)]">
                  <input type="radio" name="bulk-status" checked={bulkActive} onChange={() => setBulkActive(true)} className="accent-teal-500" />
                  🟢 {t('comp.memberList.activate', 'Ativar')}
                </label>
                <label className="flex items-center gap-2 cursor-pointer text-sm text-[var(--text-primary)]">
                  <input type="radio" name="bulk-status" checked={!bulkActive} onChange={() => setBulkActive(false)} className="accent-red-500" />
                  🔴 {t('comp.memberList.deactivate', 'Desativar')}
                </label>
              </div>
              <p className="text-sm text-[var(--text-muted)]">
                {bulkActive ? t('comp.memberList.willActivate', 'Esta ação ativará') : t('comp.memberList.willDeactivate', 'Esta ação desativará')} {selectedIds.size} {t('comp.memberList.membersParens', 'membro(s)')}.
              </p>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex justify-end gap-2">
              <button onClick={() => setShowBulkStatus(false)} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.memberList.cancel', 'Cancelar')}</button>
              <button onClick={handleBulkStatus} disabled={bulkSaving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                {bulkSaving ? t('comp.memberList.processing', 'Processando...') : t('comp.memberList.confirm', 'Confirmar')}
              </button>
            </div>
          </div>
        </div>
      )}
      {/* History Modal */}
      {historyMemberId && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={() => setHistoryMemberId(null)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[480px] overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)] flex justify-between items-center">
              <h3 className="text-base font-bold text-[var(--text-primary)]">Histórico — {historyMemberName}</h3>
              <button onClick={() => setHistoryMemberId(null)} className="bg-transparent border-0 text-xl cursor-pointer text-[var(--text-muted)]"><X size={18} /></button>
            </div>
            <div className="p-5 max-h-[400px] overflow-y-auto">
              {historyLoading ? (
                <p className="text-sm text-[var(--text-muted)]">{t('comp.memberList.loading', 'Loading...')}</p>
              ) : transitions.length === 0 ? (
                <p className="text-sm text-[var(--text-muted)]">{t('comp.memberList.noMovements', 'No movements registered.')}</p>
              ) : (
                <div className="space-y-3">
                  {transitions.map((tr: any) => {
                    const icon = tr.new_status === 'observer' ? '👁' : tr.new_status === 'alumni' ? '🎓' : tr.new_status === 'inactive' ? '⏸' : tr.new_status === 'active' && tr.previous_status !== 'active' ? '🔄' : tr.new_tribe_id ? '🔀' : '📝';
                    const d = new Date(tr.created_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
                    return (
                      <div key={tr.id} className="flex gap-2 text-[12px]">
                        <span className="text-base">{icon}</span>
                        <div className="flex-1">
                          <div className="text-[10px] text-[var(--text-muted)]">{d} — {tr.actor_name || 'Sistema'}</div>
                          <div className="font-semibold text-[var(--text-primary)]">
                            {tr.previous_status} → {tr.new_status}
                            {tr.reason_category && <span className="text-[var(--text-muted)] font-normal ml-1">({tr.reason_category})</span>}
                          </div>
                          {tr.previous_tribe_id && tr.new_tribe_id && (
                            <div className="text-[var(--text-secondary)]">T{tr.previous_tribe_id} → T{tr.new_tribe_id}</div>
                          )}
                          {tr.reason_detail && (
                            <div className="text-[var(--text-muted)] mt-0.5">"{tr.reason_detail}"</div>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Offboarding Modal */}
      {offboardMember && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={() => setOffboardMember(null)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[480px] overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)]">
              <h3 className="text-base font-bold text-[var(--text-primary)]">Gerenciar Status</h3>
            </div>
            <div className="p-5 space-y-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-amber-100 flex items-center justify-center text-amber-700 font-bold text-sm">{initials(offboardMember.full_name)}</div>
                <div>
                  <div className="font-semibold text-[var(--text-primary)]">{offboardMember.full_name}</div>
                  <div className="text-xs text-[var(--text-muted)]">{OPROLE_LABELS[offboardMember.operational_role] || offboardMember.operational_role} — T{offboardMember.tribe_id || '?'}</div>
                </div>
              </div>

              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">Novo Status</label>
                <div className="flex gap-2">
                  {(['observer', 'alumni', 'inactive'] as const).map(s => (
                    <button key={s} onClick={() => setOffboardStatus(s)}
                      className={`flex-1 px-3 py-2 rounded-lg text-xs font-semibold border cursor-pointer ${offboardStatus === s ? 'bg-amber-100 border-amber-400 text-amber-800' : 'border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)]'}`}>
                      {s === 'observer' ? '👁 Observer' : s === 'alumni' ? '🎓 Alumni' : '⛔ Inativo'}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">Categoria</label>
                <select value={offboardCategory} onChange={e => setOffboardCategory(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                  <option value="professional">Profissional</option>
                  <option value="personal">Pessoal</option>
                  <option value="time">Falta de tempo</option>
                  <option value="interest_shift">Mudanca de interesses</option>
                  <option value="inactivity">Inatividade</option>
                  <option value="administrative">Administrativo</option>
                </select>
              </div>

              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">Detalhes (opcional)</label>
                <textarea value={offboardDetail} onChange={e => setOffboardDetail(e.target.value)}
                  rows={2} className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)] resize-none" />
              </div>

              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">Reatribuir cards a (opcional)</label>
                <select value={offboardReassign} onChange={e => setOffboardReassign(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                  <option value="">{t('comp.memberList.noReassign', '— None —')}</option>
                  {members.filter(m => m.is_active && m.id !== offboardMember.id).map(m => (
                    <option key={m.id} value={m.id}>{m.full_name} (T{m.tribe_id})</option>
                  ))}
                </select>
              </div>

              <div className="text-[10px] text-[var(--text-muted)] space-y-0.5 bg-[var(--surface-section-cool)] rounded-lg p-3">
                <div>Marcara is_active = false</div>
                <div>{t('comp.memberList.removeWarning', 'Will be removed from homepage/tribes')}</div>
                <div>Preservara contribuicoes</div>
                <div>Registara no log de transicoes</div>
              </div>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex justify-end gap-2">
              <button onClick={() => setOffboardMember(null)} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.memberList.cancel', 'Cancel')}</button>
              <button onClick={handleOffboard} disabled={offboardSaving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-amber-600 text-white border-0 hover:bg-amber-700 cursor-pointer disabled:opacity-50">
                {offboardSaving ? 'Processando...' : 'Confirmar'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* #625 F1 — Affiliation verify modal */}
      {verifyMember && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={() => setVerifyMember(null)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[440px] overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)]">
              <h3 className="text-base font-bold text-[var(--text-primary)]">{t('comp.memberList.verifyTitle', 'Verificar filiação de')} {verifyMember.full_name}</h3>
              <p className="text-xs text-[var(--text-muted)] mt-0.5">{verifyMember.chapter || '—'}{verifyMember.vep_status_raw ? ` · VEP: ${verifyMember.vep_status_raw}` : ''}</p>
            </div>
            <div className="p-5 space-y-4">
              <label className="flex items-center gap-2 cursor-pointer text-sm text-[var(--text-primary)]">
                <input type="checkbox" checked={verifyActive} onChange={e => setVerifyActive(e.target.checked)} className="accent-teal-500" />
                {t('comp.memberList.verifyActiveLabel', 'Filiação PMI ativa')}
              </label>
              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">{t('comp.memberList.verifyExpiresLabel', 'Vencimento (opcional)')}</label>
                <input type="date" value={verifyExpires} onChange={e => setVerifyExpires(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]" />
              </div>
              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">{t('comp.memberList.verifyMethodLabel', 'Método')}</label>
                <select value={verifyMethod} onChange={e => setVerifyMethod(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                  <option value="sede_manual">{t('comp.memberList.verifyMethodManual', 'Verificação manual (sede)')}</option>
                  <option value="vep_sync">{t('comp.memberList.verifyMethodVep', 'VEP (sincronizado)')}</option>
                  <option value="self_attested">{t('comp.memberList.verifyMethodSelf', 'Autodeclarado')}</option>
                </select>
              </div>
              <div>
                <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase block mb-1">{t('comp.memberList.verifyObsLabel', 'Observação (sobre o resultado)')}</label>
                <textarea value={verifyObs} maxLength={500} onChange={e => setVerifyObs(e.target.value)} rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)] resize-none" />
                <p className="text-[10px] text-amber-600 mt-1">⚠ {t('comp.memberList.verifyObsHint', 'Não inclua dados pessoais além do necessário.')}</p>
              </div>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex justify-end gap-2">
              <button onClick={() => setVerifyMember(null)} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.memberList.cancel', 'Cancelar')}</button>
              <button onClick={handleVerify} disabled={verifySaving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                {verifySaving ? t('comp.memberList.verifying', 'Verificando...') : t('comp.memberList.verifySubmit', 'Registrar verificação')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* #625 F1b — Affiliation access attestation (confidentiality/purpose) gate */}
      {showAttest && (
        <div className="fixed inset-0 bg-black/50 z-[110] flex items-center justify-center p-4" onClick={() => setShowAttest(false)}>
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[560px] overflow-hidden flex flex-col" style={{ maxHeight: '90vh' }} onClick={e => e.stopPropagation()}>
            <div className="px-5 py-4 border-b border-[var(--border-default)] flex-shrink-0">
              <h3 className="text-base font-bold text-[var(--text-primary)]">🔒 {t('comp.memberList.attestTitle', 'Acesso à verificação de filiação — dados pessoais de terceiros')}</h3>
            </div>
            <div className="p-5 overflow-y-auto flex-1">
              <p className="text-[13px] text-[var(--text-secondary)] whitespace-pre-line leading-relaxed">{t('comp.memberList.attestBody', '')}</p>
            </div>
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex-shrink-0 space-y-3">
              <label className="flex items-start gap-2 cursor-pointer text-sm text-[var(--text-primary)]">
                <input type="checkbox" checked={attestChecked} onChange={e => setAttestChecked(e.target.checked)} className="accent-teal-500 mt-0.5" />
                <span>{t('comp.memberList.attestCheckbox', 'Declaro estar ciente e de acordo.')}</span>
              </label>
              <div className="flex justify-end gap-2">
                <button onClick={() => setShowAttest(false)} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.memberList.cancel', 'Cancelar')}</button>
                <button onClick={handleAttest} disabled={!attestChecked || attesting} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                  {attesting ? t('comp.memberList.attesting', 'Registrando...') : t('comp.memberList.attestConfirm', 'Confirmar e acessar')}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
