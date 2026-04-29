import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../../i18n/usePageI18n';
import { ArrowLeft, Edit2, Save, X, Loader2, Award, Calendar, BookOpen, Shield, Trophy, ChevronDown, ChevronRight } from 'lucide-react';
import { loadChapters, type Chapter } from '../../../lib/chapters';

/* ────── Constants ────── */
const OPROLE_LABELS: Record<string, string> = {
  manager: 'GP', deputy_manager: 'Vice-GP', tribe_leader: 'Lider de Tribo',
  researcher: 'Pesquisador(a)', facilitator: 'Facilitador(a)',
  communicator: 'Comunicador(a)', none: 'Sem papel', guest: 'Convidado',
};
const OPROLE_COLORS: Record<string, string> = {
  manager: '#FF610F', deputy_manager: '#FF610F', tribe_leader: '#2563EB',
  researcher: '#0D9488', facilitator: '#8B5CF6', communicator: '#06B6D4',
};
const DESIG_LABELS: Record<string, string> = {
  sponsor: 'Patrocinador', chapter_liaison: 'Elo Capitulo', ambassador: 'Embaixador',
  founder: 'Fundador', curator: 'Curador', comms_team: 'Equipe Comms',
  comms_leader: 'Lider Comms', comms_member: 'Membro Comms', co_gp: 'Co-GP',
};
const DESIG_COLORS: Record<string, string> = {
  sponsor: '#BE2027', chapter_liaison: '#BE2027', ambassador: '#10B981',
  founder: '#7C3AED', curator: '#D97706', comms_team: '#06B6D4',
  comms_leader: '#06B6D4', comms_member: '#06B6D4', co_gp: '#FF610F',
};
const ALL_ROLES = ['manager', 'deputy_manager', 'tribe_leader', 'researcher', 'facilitator', 'communicator', 'none', 'guest'];
const ALL_DESIGS = ['sponsor', 'chapter_liaison', 'ambassador', 'founder', 'curator', 'comms_team', 'comms_leader', 'comms_member', 'co_gp'];

/* ────── Types ────── */
interface MemberDetail {
  member: {
    id: string; full_name: string; email: string; photo_url: string | null;
    operational_role: string; designations: string[]; is_superadmin: boolean;
    is_active: boolean; tribe_id: number | null; tribe_name: string | null;
    chapter: string; auth_id: string | null; credly_username: string | null;
    last_seen_at: string | null; total_sessions: number; credly_badges: any[];
  };
  cycles: Array<{ cycle: string; tribe_id: number | null; tribe_name: string | null; operational_role: string; designations: string[]; status: string }>;
  gamification: { total_xp: number; rank: number; categories: Array<{ category: string; xp: number; description: string }> } | null;
  attendance: { total_events: number; attended: number; rate: number; recent: Array<{ event_name: string; event_date: string; present: boolean }> };
  publications: Array<{ id: string; title: string; status: string; submitted_at: string; target_type: string }>;
  audit_log: Array<{ action: string; changes: any; actor_name: string; created_at: string }>;
}

/* ────── Helpers ────── */
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
function fmtDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });
}

/* ────── Component ────── */
export default function MemberDetailIsland({ memberId }: { memberId: string }) {
  const t = usePageI18n();
  const [data, setData] = useState<MemberDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState<'cycles' | 'gamification' | 'attendance' | 'publications' | 'audit'>('cycles');

  // Edit form state
  const [editRole, setEditRole] = useState('');
  const [editDesigs, setEditDesigs] = useState<string[]>([]);
  const [editTribe, setEditTribe] = useState('');
  const [editChapter, setEditChapter] = useState('');
  const [editActive, setEditActive] = useState(true);
  const [editSuperadmin, setEditSuperadmin] = useState(false);
  const [chapters, setChapters] = useState<Chapter[]>([]);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const fetchData = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(fetchData, 300); return; }
    setLoading(true);
    const { data: result, error } = await sb.rpc('get_member_detail', { p_member_id: memberId });
    if (!error && result) setData(result);
    setLoading(false);
  }, [memberId, getSb]);

  useEffect(() => {
    const boot = () => {
      if (getSb()) fetchData();
      else setTimeout(boot, 300);
    };
    boot();
    loadChapters().then(setChapters);
  }, []);

  const openEdit = () => {
    if (!data) return;
    const m = data.member;
    setEditRole(m.operational_role);
    setEditDesigs([...m.designations]);
    setEditTribe(m.tribe_id != null ? String(m.tribe_id) : '');
    setEditChapter(m.chapter || 'PMI-GO');
    setEditActive(m.is_active);
    setEditSuperadmin(m.is_superadmin);
    setEditing(true);
  };

  const cancelEdit = () => setEditing(false);

  const toggleDesig = (d: string) => {
    setEditDesigs(prev => prev.includes(d) ? prev.filter(x => x !== d) : [...prev, d]);
  };

  const saveEdit = async () => {
    if (!data) return;
    const sb = getSb();
    if (!sb) return;
    setSaving(true);
    const m = data.member;
    const changes: Record<string, any> = {};
    if (editRole !== m.operational_role) changes.operational_role = editRole;
    if (JSON.stringify(editDesigs.sort()) !== JSON.stringify([...m.designations].sort())) changes.designations = editDesigs;
    if (editTribe !== (m.tribe_id != null ? String(m.tribe_id) : '')) changes.tribe_id = editTribe ? parseInt(editTribe) : null;
    if (editChapter !== m.chapter) changes.chapter = editChapter;
    if (editActive !== m.is_active) changes.is_active = editActive;
    if (editSuperadmin !== m.is_superadmin) changes.is_superadmin = editSuperadmin;

    const { error } = await sb.rpc('admin_update_member_audited', {
      p_member_id: memberId,
      p_changes: changes,
    });
    if (!error) {
      (window as any).toast?.('Membro atualizado', 'success');
      setEditing(false);
      await fetchData();
    } else {
      (window as any).toast?.(error.message || 'Erro ao salvar', 'error');
    }
    setSaving(false);
  };

  const PUB_STATUS_COLORS: Record<string, string> = {
    draft: '#94A3B8',
    review: '#EAB308',
    approved: '#22C55E',
    published: '#8B5CF6',
    rejected: '#EF4444',
  };
  const PUB_STATUS_ICONS: Record<string, string> = {
    draft: '',
    review: '',
    approved: '',
    published: '',
    rejected: '',
  };

  if (loading) {
    return (
      <div className="max-w-[900px] mx-auto flex items-center justify-center py-24 text-[var(--text-muted)]">
        <Loader2 size={24} className="animate-spin mr-2" /> {t('comp.memberDetail.loading', 'Loading member details...')}
      </div>
    );
  }

  if (!data) {
    return (
      <div className="max-w-[900px] mx-auto text-center py-24 text-[var(--text-muted)]">
        {t('comp.memberDetail.notFound', 'Member not found.')}
      </div>
    );
  }

  const m = data.member;

  const tabs = [
    { key: 'cycles' as const, label: 'Ciclos' },
    { key: 'gamification' as const, label: 'Gamificacao' },
    { key: 'attendance' as const, label: 'Presenca' },
    { key: 'publications' as const, label: 'Publicacoes' },
    { key: 'audit' as const, label: 'Auditoria' },
  ];

  return (
    <div className="max-w-[900px] mx-auto">
      {/* Section 1 — Header */}
      <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-5 mb-4 relative">
        <a href="/admin/members" className="inline-flex items-center gap-1.5 text-teal-500 text-sm font-semibold mb-4 no-underline hover:underline">
          <ArrowLeft size={14} /> {t('comp.memberDetail.backToMembers', 'Back to Members')}
        </a>

        <button
          onClick={openEdit}
          className="absolute top-5 right-5 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer"
        >
          <Edit2 size={14} /> {t('comp.memberDetail.edit', 'Edit')}
        </button>

        <div className="flex items-start gap-4">
          {m.photo_url
            ? <img src={m.photo_url} className="w-16 h-16 rounded-full object-cover flex-shrink-0" alt="" />
            : <div className="w-16 h-16 rounded-full bg-teal-600 flex items-center justify-center text-white text-lg font-bold flex-shrink-0">{initials(m.full_name)}</div>
          }
          <div className="min-w-0 flex-1">
            <h1 className="text-2xl font-extrabold text-[var(--text-primary)] m-0 mb-2">{m.full_name}</h1>
            <div className="flex flex-wrap gap-1.5 mb-2">
              {m.operational_role && m.operational_role !== 'none' && m.operational_role !== 'guest' && (
                <span className="text-[.65rem] font-bold px-2 py-0.5 rounded" style={{ background: `${OPROLE_COLORS[m.operational_role] || '#94A3B8'}18`, color: OPROLE_COLORS[m.operational_role] || '#94A3B8' }}>
                  {OPROLE_LABELS[m.operational_role] || m.operational_role}
                </span>
              )}
              {(m.operational_role === 'none' || m.operational_role === 'guest') && (
                <span className="text-[.65rem] font-bold px-2 py-0.5 rounded bg-slate-500/10 text-slate-400">
                  {OPROLE_LABELS[m.operational_role] || m.operational_role}
                </span>
              )}
              {m.designations?.map(d => (
                <span key={d} className="text-[.65rem] font-bold px-2 py-0.5 rounded" style={{ background: `${DESIG_COLORS[d] || '#94A3B8'}18`, color: DESIG_COLORS[d] || '#94A3B8' }}>
                  {DESIG_LABELS[d] || d}
                </span>
              ))}
              {m.is_superadmin && <span className="text-[.65rem] font-bold px-2 py-0.5 rounded bg-orange-500/10 text-orange-500">SA</span>}
            </div>
            <div className="text-sm text-[var(--text-secondary)] mb-1">{m.chapter || '—'}</div>
            <div className="text-sm text-[var(--text-muted)]">{m.email}</div>
            <div className="text-sm text-[var(--text-muted)] mt-1">
              {m.last_seen_at ? `Visto ${timeAgo(m.last_seen_at)}` : 'Nunca acessou'} &middot; {m.total_sessions} sessoes
            </div>
          </div>
        </div>
      </div>

      {/* Section 2 — Edit Form */}
      {editing && (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-5 mb-4 space-y-4">
          <h3 className="text-base font-bold text-[var(--text-primary)] m-0">{t('comp.memberDetail.editTitle', 'Edit Member')}</h3>

          {/* Operational Role */}
          <div className="p-3 rounded-xl bg-[var(--surface-base)] border border-[var(--border-default)]">
            <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase tracking-wider block mb-2">Papel Operacional</label>
            <select value={editRole} onChange={e => setEditRole(e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
              {ALL_ROLES.map(r => <option key={r} value={r}>{OPROLE_LABELS[r] || r}</option>)}
            </select>
          </div>

          {/* Designations */}
          <div className="p-3 rounded-xl bg-[var(--surface-base)] border border-[var(--border-default)]">
            <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase tracking-wider block mb-2">Designacoes</label>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-1.5">
              {ALL_DESIGS.map(d => (
                <label key={d} className="flex items-center gap-2 px-2.5 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] hover:bg-[var(--surface-hover)] cursor-pointer text-[.75rem]">
                  <input type="checkbox" checked={editDesigs.includes(d)} onChange={() => toggleDesig(d)} className="accent-teal-500" />
                  <span style={{ color: DESIG_COLORS[d] }}>&#9679;</span> {DESIG_LABELS[d] || d}
                </label>
              ))}
            </div>
          </div>

          {/* Tribe / Chapter / Status / Superadmin */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div className="flex flex-col gap-1.5">
              <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase">Tribo</label>
              <input
                type="text"
                value={editTribe}
                onChange={e => setEditTribe(e.target.value)}
                placeholder="ID da tribo"
                className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]"
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase">Capitulo</label>
              <select value={editChapter} onChange={e => setEditChapter(e.target.value)}
                className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                {chapters.map(c => <option key={c.display_code} value={c.display_code}>{c.display_code}</option>)}
              </select>
            </div>
            <div className="flex flex-col gap-1.5">
              <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase">Status</label>
              <select value={String(editActive)} onChange={e => setEditActive(e.target.value === 'true')}
                className="px-2 py-1.5 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]">
                <option value="true">Ativo</option>
                <option value="false">Inativo</option>
              </select>
            </div>
            <div className="flex flex-col gap-1.5">
              <label className="text-[.65rem] font-bold text-[var(--text-muted)] uppercase">Superadmin</label>
              <label className="flex items-center gap-2 cursor-pointer pt-1">
                <input type="checkbox" checked={editSuperadmin} onChange={e => setEditSuperadmin(e.target.checked)} className="accent-orange-500" />
                <span className="text-sm text-[var(--text-secondary)]">SA</span>
              </label>
            </div>
          </div>

          {/* Actions */}
          <div className="flex justify-end gap-2 pt-2">
            <button onClick={cancelEdit} className="px-4 py-2 rounded-lg text-[13px] font-semibold border border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer inline-flex items-center gap-1.5">
              <X size={14} /> {t('comp.memberDetail.cancel', 'Cancel')}
            </button>
            <button onClick={saveEdit} disabled={saving} className="px-4 py-2 rounded-lg text-[13px] font-semibold bg-teal-600 text-white border-0 hover:bg-teal-700 cursor-pointer disabled:opacity-50 inline-flex items-center gap-1.5">
              {saving ? <Loader2 size={14} className="animate-spin" /> : <Save size={14} />}
              {saving ? 'Salvando...' : 'Salvar'}
            </button>
          </div>
        </div>
      )}

      {/* Tab Bar */}
      <div className="flex gap-0 border-b border-[var(--border-default)] mb-4">
        {tabs.map(t => (
          <button
            key={t.key}
            onClick={() => setActiveTab(t.key)}
            className={`px-4 py-2.5 text-sm font-semibold border-0 bg-transparent cursor-pointer transition-colors ${
              activeTab === t.key
                ? 'text-teal-500 border-b-2 border-teal-500'
                : 'text-[var(--text-muted)] hover:text-[var(--text-secondary)]'
            }`}
            style={activeTab === t.key ? { borderBottom: '2px solid #14B8A6' } : {}}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* Tab: Ciclos */}
      {activeTab === 'cycles' && (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-[var(--surface-section-cool)] text-[var(--text-muted)] text-[.7rem] uppercase tracking-wider">
                <th className="px-4 py-2.5 text-left">Ciclo</th>
                <th className="px-4 py-2.5 text-left">Tribo</th>
                <th className="px-4 py-2.5 text-left">Papel</th>
                <th className="px-4 py-2.5 text-center">Status</th>
              </tr>
            </thead>
            <tbody>
              {data.cycles.length === 0 && (
                <tr><td colSpan={4} className="px-4 py-8 text-center text-[var(--text-muted)]">{t('comp.memberDetail.noCycles', 'No cycles registered.')}</td></tr>
              )}
              {data.cycles.map((c, i) => (
                <tr key={i} className="border-t border-[var(--border-default)]">
                  <td className="px-4 py-2.5 text-[var(--text-primary)] font-medium">{c.cycle}</td>
                  <td className="px-4 py-2.5 text-[var(--text-secondary)]">{c.tribe_name || '\u2014'}</td>
                  <td className="px-4 py-2.5">
                    <div className="flex flex-wrap gap-1">
                      {c.operational_role && c.operational_role !== 'none' && (
                        <span className="text-[.6rem] font-bold px-1.5 py-0.5 rounded" style={{ background: `${OPROLE_COLORS[c.operational_role] || '#94A3B8'}18`, color: OPROLE_COLORS[c.operational_role] || '#94A3B8' }}>
                          {OPROLE_LABELS[c.operational_role] || c.operational_role}
                        </span>
                      )}
                      {c.designations?.map(d => (
                        <span key={d} className="text-[.6rem] font-bold px-1.5 py-0.5 rounded" style={{ background: `${DESIG_COLORS[d] || '#94A3B8'}18`, color: DESIG_COLORS[d] || '#94A3B8' }}>
                          {DESIG_LABELS[d] || d}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="px-4 py-2.5 text-center">
                    <span className={`text-[.65rem] font-bold px-2 py-0.5 rounded ${c.status === 'ativo' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-400'}`}>
                      {c.status === 'ativo' ? 'Ativo' : 'Inativo'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Tab: Gamificacao */}
      {activeTab === 'gamification' && (
        <div className="space-y-4">
          {data.gamification ? (
            <>
              <div className="grid grid-cols-2 gap-3">
                <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4 text-center">
                  <div className="text-3xl font-black text-teal-500">{data.gamification.total_xp}</div>
                  <div className="text-[.7rem] text-[var(--text-muted)] font-semibold uppercase tracking-wider mt-1">XP Total</div>
                </div>
                <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4 text-center">
                  <div className="text-3xl font-black text-amber-500">#{data.gamification.rank}</div>
                  <div className="text-[.7rem] text-[var(--text-muted)] font-semibold uppercase tracking-wider mt-1">Ranking</div>
                </div>
              </div>

              {data.gamification.categories.length > 0 && (
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  {data.gamification.categories.map((cat, i) => (
                    <div key={i} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-3">
                      <div className="text-xl font-black text-[var(--text-primary)]">{cat.xp}</div>
                      <div className="text-[.7rem] text-[var(--text-muted)] font-semibold uppercase tracking-wider">{cat.category}</div>
                      {cat.description && <div className="text-[.65rem] text-[var(--text-muted)] mt-1">{cat.description}</div>}
                    </div>
                  ))}
                </div>
              )}

              {m.credly_badges && m.credly_badges.length > 0 && (
                <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
                  <h4 className="text-sm font-bold text-[var(--text-primary)] m-0 mb-3 flex items-center gap-2">
                    <Award size={16} className="text-amber-500" /> Credly Badges
                  </h4>
                  <div className="flex flex-wrap gap-3">
                    {m.credly_badges.map((badge: any, i: number) => (
                      <div key={i} className="flex items-center gap-2 px-3 py-2 rounded-lg bg-[var(--surface-base)] border border-[var(--border-default)]">
                        {badge.image_url
                          ? <img src={badge.image_url} className="w-8 h-8 rounded" alt="" />
                          : <Award size={16} className="text-amber-500" />
                        }
                        <span className="text-[.75rem] text-[var(--text-secondary)] font-medium">{badge.name || badge.title || `Badge ${i + 1}`}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-8 text-center text-[var(--text-muted)]">
              {t('comp.memberDetail.noGamification', 'No gamification data available.')}
            </div>
          )}
        </div>
      )}

      {/* Tab: Presenca */}
      {activeTab === 'attendance' && (
        <div className="space-y-4">
          <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
            <div className="text-lg font-bold text-[var(--text-primary)]">
              Taxa: {data.attendance.rate}% <span className="text-sm font-normal text-[var(--text-muted)]">({data.attendance.attended}/{data.attendance.total_events} eventos)</span>
            </div>
          </div>

          <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-[var(--surface-section-cool)] text-[var(--text-muted)] text-[.7rem] uppercase tracking-wider">
                  <th className="px-4 py-2.5 text-left">Data</th>
                  <th className="px-4 py-2.5 text-left">Evento</th>
                  <th className="px-4 py-2.5 text-center">Presente</th>
                </tr>
              </thead>
              <tbody>
                {data.attendance.recent.length === 0 && (
                  <tr><td colSpan={3} className="px-4 py-8 text-center text-[var(--text-muted)]">{t('comp.memberDetail.noEvents', 'No events registered.')}</td></tr>
                )}
                {data.attendance.recent.map((evt, i) => (
                  <tr key={i} className="border-t border-[var(--border-default)]">
                    <td className="px-4 py-2.5 text-[var(--text-secondary)]">{fmtDate(evt.event_date)}</td>
                    <td className="px-4 py-2.5 text-[var(--text-primary)]">{evt.event_name}</td>
                    <td className="px-4 py-2.5 text-center text-base">{evt.present ? '\u2705' : '\u274C'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tab: Publicacoes */}
      {activeTab === 'publications' && (
        <div className="space-y-4">
          <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
            <div className="text-lg font-bold text-[var(--text-primary)]">{data.publications.length} submissoes</div>
          </div>

          <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-[var(--surface-section-cool)] text-[var(--text-muted)] text-[.7rem] uppercase tracking-wider">
                  <th className="px-4 py-2.5 text-left">Titulo</th>
                  <th className="px-4 py-2.5 text-center">Status</th>
                  <th className="px-4 py-2.5 text-left">Data</th>
                </tr>
              </thead>
              <tbody>
                {data.publications.length === 0 && (
                  <tr><td colSpan={3} className="px-4 py-8 text-center text-[var(--text-muted)]">{t('comp.memberDetail.noPublications', 'No publications registered.')}</td></tr>
                )}
                {data.publications.map((pub, i) => (
                  <tr key={pub.id || i} className="border-t border-[var(--border-default)]">
                    <td className="px-4 py-2.5 text-[var(--text-primary)]">{pub.title}</td>
                    <td className="px-4 py-2.5 text-center">
                      <span
                        className="text-[.65rem] font-bold px-2 py-0.5 rounded"
                        style={{
                          background: `${PUB_STATUS_COLORS[pub.status] || '#94A3B8'}18`,
                          color: PUB_STATUS_COLORS[pub.status] || '#94A3B8',
                        }}
                      >
                        {pub.status}
                      </span>
                    </td>
                    <td className="px-4 py-2.5 text-[var(--text-secondary)]">{fmtDate(pub.submitted_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tab: Auditoria */}
      {activeTab === 'audit' && (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
          {data.audit_log.length === 0 ? (
            <div className="px-4 py-8 text-center text-[var(--text-muted)]">{t('comp.memberDetail.noAudit', 'No audit records.')}</div>
          ) : (
            <div className="divide-y divide-[var(--border-default)]">
              {data.audit_log.map((entry, i) => {
                const d = new Date(entry.created_at);
                const dateStr = d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
                const timeStr = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
                return (
                  <div key={i} className="px-4 py-3">
                    <div className="flex items-start gap-3">
                      <div className="text-[.75rem] text-[var(--text-muted)] whitespace-nowrap font-mono">
                        {dateStr} {timeStr}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="text-sm text-[var(--text-primary)]">
                          <span className="font-semibold">{entry.actor_name}</span>
                          <span className="text-[var(--text-muted)]"> &rarr; </span>
                          <span>{entry.action}</span>
                        </div>
                        {entry.changes && Object.keys(entry.changes).length > 0 && (
                          <div className="mt-1 text-[.7rem] text-[var(--text-muted)] bg-[var(--surface-base)] rounded-lg px-2.5 py-1.5 font-mono">
                            {Object.entries(entry.changes).map(([key, val]) => (
                              <div key={key}>{key}: {JSON.stringify(val)}</div>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
