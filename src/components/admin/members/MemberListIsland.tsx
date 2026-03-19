import { useState, useEffect, useCallback } from 'react';
import { Search, Edit2, Users, UserX, ShieldOff, Loader2, X } from 'lucide-react';
import { trackEvent } from '../../../lib/analytics';
import { usePageI18n } from '../../../i18n/usePageI18n';

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
  tribe_id: number | null;
  tribe_name: string | null;
  chapter: string;
  auth_id: string | null;
  last_seen_at: string | null;
  total_sessions: number;
  credly_username: string | null;
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

/* ────── Component ────── */
export default function MemberListIsland() {
  const t = usePageI18n();
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [tierFilter, setTierFilter] = useState('');
  const [tribeFilter, setTribeFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('active');
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
    });
    if (!error && data) setMembers(data);
    setLoading(false);
  }, [search, tierFilter, tribeFilter, statusFilter, getSb]);

  useEffect(() => {
    const boot = () => {
      if (getSb()) fetchMembers();
      else setTimeout(boot, 300);
    };
    boot();
    window.addEventListener('nav:member', () => fetchMembers());
  }, []);

  // Re-fetch when filters change (debounce search)
  useEffect(() => {
    const timer = setTimeout(() => {
      fetchMembers();
      if (search || tierFilter || tribeFilter || statusFilter) {
        trackEvent('member_searched', { search_term_length: search.length, filter_count: [tierFilter, tribeFilter, statusFilter].filter(Boolean).length });
      }
    }, search ? 400 : 0);
    return () => clearTimeout(timer);
  }, [search, tierFilter, tribeFilter, statusFilter]);

  // Stats
  const total = members.length;
  const active = members.filter(m => m.is_active).length;
  const inactive = total - active;
  const noAuth = members.filter(m => !m.auth_id).length;
  const noTribe = members.filter(m => !m.tribe_id && m.is_active).length;

  // Unique tribes for filter
  const tribes = [...new Map(members.filter(m => m.tribe_id).map(m => [m.tribe_id, m.tribe_name])).entries()]
    .sort((a, b) => (a[0] || 0) - (b[0] || 0));

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

  const toggleSelectAll = () => {
    if (selectedIds.size === members.length) setSelectedIds(new Set());
    else setSelectedIds(new Set(members.map(m => m.id)));
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

  return (
    <div className="max-w-[1200px] mx-auto">
      {/* Stat cards */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-6">
        {[
          { label: t('comp.memberList.total', 'Total'), value: total, icon: <Users size={16} /> },
          { label: t('comp.memberList.active', 'Ativos'), value: active, color: 'text-emerald-500' },
          { label: t('comp.memberList.inactive', 'Inativos'), value: inactive, color: 'text-red-400' },
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
        <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
          className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]">
          <option value="active">{t('comp.memberList.active', 'Ativos')}</option>
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
                  <input type="checkbox" checked={selectedIds.size === members.length && members.length > 0} onChange={toggleSelectAll} className="accent-teal-500" />
                </th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thMember', 'Membro')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thRoleDesig', 'Papel / Designações')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thTribe', 'Tribo')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thChapter', 'Capítulo')}</th>
                <th className="px-3 py-2 text-center">{t('comp.memberList.thStatus', 'Status')}</th>
                <th className="px-3 py-2 text-left">{t('comp.memberList.thLastSeen', 'Último acesso')}</th>
                <th className="px-3 py-2 text-center w-16">{t('comp.memberList.thActions', 'Ações')}</th>
              </tr>
            </thead>
            <tbody>
              {members.map(m => (
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
                        <a href={`/admin/members/${m.id}`} className="font-medium text-[var(--text-primary)] hover:underline truncate block no-underline">{m.full_name}</a>
                        <div className="text-[.7rem] text-[var(--text-muted)] truncate">{m.email}</div>
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
                    </div>
                  </td>
                  <td className="px-3 py-2 text-[var(--text-secondary)]">
                    {m.tribe_name ? <span className="text-[.75rem]">T{String(m.tribe_id).padStart(2, '0')} {m.tribe_name}</span> : <span className="text-[var(--text-muted)]">—</span>}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-secondary)] text-[.8rem]">{m.chapter || '—'}</td>
                  <td className="px-3 py-2 text-center">{m.is_active ? '🟢' : '🔴'}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)] text-[.8rem]">{m.last_seen_at ? timeAgo(m.last_seen_at) : '—'}</td>
                  <td className="px-3 py-2 text-center">
                    <button onClick={() => openEdit(m)} className="p-1.5 rounded-lg hover:bg-[var(--surface-hover)] text-[var(--text-muted)] bg-transparent border-0 cursor-pointer" title={t('comp.memberList.edit', 'Editar')}>
                      <Edit2 size={14} />
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
                    {['PMI-GO', 'PMI-CE', 'PMI-DF', 'PMI-MG', 'PMI-RS'].map(c => <option key={c} value={c}>{c}</option>)}
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
            <div className="px-5 py-3.5 border-t border-[var(--border-default)] flex justify-end gap-2 flex-shrink-0">
              <button onClick={closeEdit} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer">{t('comp.memberList.cancel', 'Cancelar')}</button>
              <button onClick={saveEdit} disabled={saving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50">
                {saving ? t('comp.memberList.saving', 'Salvando...') : t('comp.memberList.save', 'Salvar')}
              </button>
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
    </div>
  );
}
