import { useEffect, useState } from 'react';
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from 'recharts';
import { usePageI18n } from '../../i18n/usePageI18n';

interface TribeDashboardProps {
  tribeId: string;
}

type TabKey = 'members' | 'production' | 'engagement' | 'gamification';

const DAY_NAMES: Record<number, string> = {
  0: 'Domingo', 1: 'Segunda', 2: 'Terça', 3: 'Quarta',
  4: 'Quinta', 5: 'Sexta', 6: 'Sábado',
};

const STATUS_COLORS: Record<string, string> = {
  backlog: '#94A3B8', todo: '#CBD5E1', in_progress: '#3B82F6',
  review: '#F59E0B', submitted: '#8B5CF6', approved: '#10B981',
  done: '#059669', published: '#047857',
};

const CHART_COLORS = ['#00799E', '#FF610F', '#4F17A8', '#10B981', '#F59E0B', '#EF4444', '#6366F1', '#EC4899'];

const ROLE_LABELS: Record<string, string> = {
  researcher: 'Pesquisador', tribe_leader: 'Líder de Tribo',
  communicator: 'Comunicador', facilitator: 'Facilitador',
  guest: 'Convidado', manager: 'Gerente', deputy_manager: 'Vice-Gerente',
};

export default function TribeDashboardIsland({ tribeId }: TribeDashboardProps) {
  const t = usePageI18n();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<TabKey>('members');
  const [sortBy, setSortBy] = useState<'xp' | 'attendance' | 'name'>('xp');

  useEffect(() => {
    const load = async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) { setTimeout(load, 300); return; }

      try {
        const { data: result, error: err } = await sb.rpc('exec_tribe_dashboard', {
          p_tribe_id: parseInt(tribeId),
        });
        if (err) throw err;
        setData(result);
      } catch (e: any) {
        setError(e?.message || 'Failed to load tribe dashboard');
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [tribeId]);

  if (loading) return <div className="text-center py-12 text-[var(--text-muted)]">Carregando dashboard da tribo...</div>;
  if (error) return <div className="text-center py-12 text-red-500">{error}</div>;
  if (!data) return null;

  const tribe = data.tribe || {};
  const members = data.members || {};
  const production = data.production || {};
  const engagement = data.engagement || {};
  const gamification = data.gamification || {};
  const trends = data.trends || {};

  const _sl = typeof window !== 'undefined' ? (window.location.pathname.startsWith('/en') ? 'en' : window.location.pathname.startsWith('/es') ? 'es' : 'pt') : 'pt';
  const tribeName = tribe.name_i18n?.[_sl] || tribe.name;
  const quadrantName = tribe.quadrant_name_i18n?.[_sl] || tribe.quadrant_name;

  const meetingLabel = tribe.meeting_slots?.[0]
    ? `${DAY_NAMES[tribe.meeting_slots[0].day_of_week] || ''} · ${(tribe.meeting_slots[0].time_start || '').substring(0,5).replace(/:00$/, 'h').replace(/:(\d\d)$/, 'h$1')}–${(tribe.meeting_slots[0].time_end || '').substring(0,5).replace(/:00$/, 'h').replace(/:(\d\d)$/, 'h$1')}`
    : '';

  const tabs: { key: TabKey; label: string; icon: string }[] = [
    { key: 'members', label: t('comp.tribe.members', 'Membros'), icon: '👥' },
    { key: 'production', label: t('comp.tribe.production', 'Produção'), icon: '📄' },
    { key: 'engagement', label: t('comp.tribe.engagement', 'Engajamento'), icon: '📊' },
    { key: 'gamification', label: t('comp.tribe.gamification', 'Gamificação'), icon: '🏆' },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-2xl font-extrabold text-navy">
              Tribo {tribe.id}: {tribeName}
            </h1>
            <p className="text-sm text-[var(--text-secondary)] mt-1">
              {tribe.leader?.name ? `Líder: ${tribe.leader.name}` : ''}
              {quadrantName ? ` · ${quadrantName}` : ''}
            </p>
            <div className="flex flex-wrap gap-3 mt-2 text-xs text-[var(--text-secondary)]">
              {meetingLabel && <span>📅 {meetingLabel}</span>}
              {tribe.whatsapp_url && (
                <a href={tribe.whatsapp_url} target="_blank" rel="noopener"
                   className="text-teal hover:underline">WhatsApp ↗</a>
              )}
              {tribe.drive_url && (
                <a href={tribe.drive_url} target="_blank" rel="noopener"
                   className="text-teal hover:underline">Drive ↗</a>
              )}
            </div>
          </div>
          <a href="/admin" className="text-xs text-[var(--text-secondary)] hover:text-navy no-underline">
            ← Voltar
          </a>
        </div>
      </div>

      {/* Alerts */}
      {engagement.members_inactive_30d > 0 && (
        <div className="bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-xl px-4 py-3 text-sm text-amber-800 dark:text-amber-200">
          ⚠️ {engagement.members_inactive_30d} membro(s) sem presença nos últimos 30 dias
        </div>
      )}
      {!tribe.meeting_slots?.length && (
        <div className="bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-800 rounded-xl px-4 py-3 text-sm text-red-700 dark:text-red-300">
          🔴 Sem reunião agendada — configure os horários da tribo
        </div>
      )}

      {/* KPI Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KpiCard label={t('comp.tribe.members', 'Membros')} value={members.total || 0} sub={`${members.active || 0} ativos`} color="bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300" />
        <KpiCard label={t('comp.tribe.attendance', 'Presença')} value={(engagement.total_meetings || 0) > 0 ? `${Math.round((engagement.attendance_rate || 0) * 100)}%` : '—'} sub={`${engagement.total_meetings || 0} reuniões`} color="bg-emerald-50 dark:bg-emerald-950/30 text-emerald-700 dark:text-emerald-300" />
        <KpiCard label="Cards" value={production.total_cards || 0} sub={`${production.articles_approved || 0} aprovados`} color="bg-indigo-50 dark:bg-indigo-950/30 text-indigo-700 dark:text-indigo-300" />
        <KpiCard label="XP Total" value={gamification.tribe_total_xp || 0} sub={`média ${gamification.tribe_avg_xp || 0}`} color="bg-amber-50 dark:bg-amber-950/30 text-amber-700 dark:text-amber-300" />
      </div>

      {/* Tabs */}
      <div className="flex gap-2 flex-wrap">
        {tabs.map(tab => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={`px-4 py-2 rounded-xl text-[13px] font-semibold border-0 cursor-pointer transition-all ${
              activeTab === tab.key
                ? 'bg-navy text-white'
                : 'bg-[var(--surface-section-cool)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
            }`}
          >
            {tab.icon} {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl overflow-hidden">
        {activeTab === 'members' && <MembersTab members={members} sortBy={sortBy} setSortBy={setSortBy} />}
        {activeTab === 'production' && <ProductionTab production={production} trends={trends} />}
        {activeTab === 'engagement' && <EngagementTab engagement={engagement} trends={trends} />}
        {activeTab === 'gamification' && <GamificationTab gamification={gamification} members={members} />}
      </div>
    </div>
  );
}

// ─── KPI Card ───
function KpiCard({ label, value, sub, color }: { label: string; value: string | number; sub: string; color: string }) {
  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4 text-center">
      <div className="text-2xl font-extrabold text-navy">{value}</div>
      <div className="text-[.72rem] font-bold text-[var(--text-secondary)] mt-1">{label}</div>
      <div className={`text-[.6rem] ${color} mt-1 font-medium`}>{sub}</div>
    </div>
  );
}

// ─── Members Tab ───
function MembersTab({ members, sortBy, setSortBy }: { members: any; sortBy: string; setSortBy: (s: any) => void }) {
  const t = usePageI18n();
  const roleLabels: Record<string, string> = {
    ...ROLE_LABELS,
    researcher: t('comp.tribe.researcher', 'Pesquisador(a)'),
    tribe_leader: t('comp.tribe.tribeLeader', 'Líder de Tribo'),
  };
  const list = [...(members.list || [])].sort((a: any, b: any) => {
    if (sortBy === 'xp') return (b.xp_total || 0) - (a.xp_total || 0);
    if (sortBy === 'attendance') return (b.attendance_rate || 0) - (a.attendance_rate || 0);
    return (a.name || '').localeCompare(b.name || '');
  });

  return (
    <div className="p-5">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-bold text-navy">Membros da Tribo</h3>
        <div className="flex gap-1">
          {(['xp', 'attendance', 'name'] as const).map(s => (
            <button key={s} onClick={() => setSortBy(s)}
              className={`px-2 py-1 text-[.65rem] rounded-md border-0 cursor-pointer ${
                sortBy === s ? 'bg-navy text-white' : 'bg-[var(--surface-section-cool)] text-[var(--text-secondary)]'
              }`}>
              {s === 'xp' ? 'XP' : s === 'attendance' ? 'Presença' : 'Nome'}
            </button>
          ))}
        </div>
      </div>

      {/* By role + chapter summary */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-5">
        <div>
          <div className="text-[.68rem] font-semibold text-[var(--text-secondary)] mb-2">{t('comp.tribe.byRole', 'Por Papel')}</div>
          <div className="flex flex-wrap gap-1.5">
            {Object.entries(members.by_role || {}).map(([role, count]: any) => (
              <span key={role} className="px-2 py-1 bg-indigo-50 dark:bg-indigo-950/30 text-indigo-700 dark:text-indigo-300 rounded-md text-[.65rem] font-semibold">
                {roleLabels[role] || role}: {count}
              </span>
            ))}
          </div>
        </div>
        <div>
          <div className="text-[.68rem] font-semibold text-[var(--text-secondary)] mb-2">{t('comp.tribe.byChapter', 'Por Capítulo')}</div>
          <div className="flex flex-wrap gap-1.5">
            {Object.entries(members.by_chapter || {}).map(([ch, count]: any) => (
              <span key={ch} className="px-2 py-1 bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300 rounded-md text-[.65rem] font-semibold">
                {ch}: {count}
              </span>
            ))}
          </div>
        </div>
      </div>

      {/* Members table */}
      <div className="overflow-x-auto">
        <table className="w-full text-[.75rem]">
          <thead>
            <tr className="bg-[var(--surface-section-cool)]">
              <th className="text-left px-3 py-2.5 font-bold text-[var(--text-secondary)]">Nome</th>
              <th className="text-left px-3 py-2.5 font-bold text-[var(--text-secondary)]">Capítulo</th>
              <th className="text-center px-3 py-2.5 font-bold text-[var(--text-secondary)]">XP</th>
              <th className="text-center px-3 py-2.5 font-bold text-[var(--text-secondary)]">Presença</th>
              <th className="text-center px-3 py-2.5 font-bold text-[var(--text-secondary)]">🏅</th>
            </tr>
          </thead>
          <tbody>
            {list.map((m: any, i: number) => (
              <tr key={m.id || i} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                <td className="px-3 py-2.5 font-semibold text-navy">{m.name}</td>
                <td className="px-3 py-2.5 text-[var(--text-secondary)]">{m.chapter || '—'}</td>
                <td className="px-3 py-2.5 text-center font-bold">{m.xp_total || 0}</td>
                <td className="px-3 py-2.5 text-center">{Math.round((m.attendance_rate || 0) * 100)}%</td>
                <td className="px-3 py-2.5 text-center text-[.6rem]">
                  {m.cpmai_certified && <span className="px-1.5 py-0.5 bg-amber-100 text-amber-700 rounded font-bold">CPMAI</span>}
                  {m.certifications && <span className="ml-1">{m.certifications}</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── Production Tab ───
function ProductionTab({ production, trends }: { production: any; trends: any }) {
  const statusData = Object.entries(production.by_status || {}).map(([status, count]) => ({
    status, count: count as number, fill: STATUS_COLORS[status] || '#94A3B8',
  }));

  const prodTrend = trends.production_by_month || [];

  return (
    <div className="p-5 space-y-6">
      {/* Pipeline bar */}
      <div>
        <h3 className="text-sm font-bold text-navy mb-3">Pipeline de Produção</h3>
        {production.total_cards === 0 ? (
          <p className="text-sm text-[var(--text-muted)]">Nenhum card na tribo</p>
        ) : (
          <>
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={statusData} layout="vertical">
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
                <XAxis type="number" />
                <YAxis dataKey="status" type="category" width={90} tick={{ fontSize: 11 }} />
                <Tooltip />
                <Bar dataKey="count" name="Cards">
                  {statusData.map((entry, i) => <Cell key={i} fill={entry.fill} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-4">
              <MiniStat label="Submetidos" value={production.articles_submitted} />
              <MiniStat label="Aprovados" value={production.articles_approved} />
              <MiniStat label="Publicados" value={production.articles_published} />
              <MiniStat label="Em Curadoria" value={production.curation_pending} />
            </div>
          </>
        )}
      </div>

      {/* Production trend */}
      {prodTrend.length > 0 && (
        <div>
          <h3 className="text-sm font-bold text-navy mb-3">Tendência de Produção</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={prodTrend}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
              <XAxis dataKey="month" tick={{ fontSize: 10 }} />
              <YAxis />
              <Tooltip />
              <Legend />
              <Bar dataKey="cards_created" fill="#00799E" name="Criados" />
              <Bar dataKey="cards_completed" fill="#10B981" name="Concluídos" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
}

// ─── Engagement Tab ───
function EngagementTab({ engagement, trends }: { engagement: any; trends: any }) {
  const t = usePageI18n();
  const attendanceTrend = trends.attendance_by_month || [];

  return (
    <div className="p-5 space-y-6">
      {/* Attendance trend line */}
      {attendanceTrend.length > 0 && (
        <div>
          <h3 className="text-sm font-bold text-navy mb-3">{t('comp.tribe.attendanceTrend', 'Tendência de Presença')}</h3>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={attendanceTrend}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
              <XAxis dataKey="month" tick={{ fontSize: 10 }} />
              <YAxis domain={[0, 1]} tickFormatter={(v: number) => `${Math.round(v * 100)}%`} />
              <Tooltip formatter={(v: number) => `${Math.round(v * 100)}%`} />
              <Line type="monotone" dataKey="rate" stroke="#00799E" strokeWidth={2}
                    dot={{ fill: '#00799E', r: 4 }} name="Taxa de Presença" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Stats grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <MiniStat label="Reuniões" value={engagement.total_meetings || 0} />
        <MiniStat label="Horas Acumuladas" value={`${engagement.total_hours || 0}h`} />
        <MiniStat label="Média/Reunião" value={`${engagement.avg_attendance_per_meeting || 0} membros`} />
        <MiniStat label="Última Reunião" value={engagement.last_meeting_date || '—'} />
      </div>

      {/* Inactive alert */}
      {engagement.members_inactive_30d > 0 && (
        <div className="bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-xl px-4 py-3 text-sm text-amber-800 dark:text-amber-200">
          ⚠️ <strong>{engagement.members_inactive_30d}</strong> membro(s) sem presença registrada nos últimos 30 dias
        </div>
      )}
    </div>
  );
}

// ─── Gamification Tab ───
function GamificationTab({ gamification, members }: { gamification: any; members: any }) {
  const topContribs = gamification.top_contributors || [];
  const certProgress = gamification.certification_progress || {};

  // XP distribution chart
  const xpData = (members.list || [])
    .filter((m: any) => (m.xp_total || 0) > 0)
    .sort((a: any, b: any) => (b.xp_total || 0) - (a.xp_total || 0))
    .slice(0, 10)
    .map((m: any) => ({ name: m.name?.split(' ')[0] || '?', xp: m.xp_total || 0 }));

  // Certification pie
  const certPie = [
    { name: 'Certificado CPMAI', value: certProgress.cpmai_certified || 0 },
    { name: 'Não certificado', value: Math.max(0, (members.total || 0) - (certProgress.cpmai_certified || 0)) },
  ].filter(d => d.value > 0);

  return (
    <div className="p-5 space-y-6">
      {/* Top contributors */}
      <div>
        <h3 className="text-sm font-bold text-navy mb-3">🏆 Top Contribuidores</h3>
        <div className="space-y-2">
          {topContribs.map((c: any) => (
            <div key={c.rank} className="flex items-center gap-3 p-3 rounded-xl bg-[var(--surface-section-cool)]">
              <span className="text-lg font-extrabold text-navy w-6 text-center">
                {c.rank === 1 ? '🥇' : c.rank === 2 ? '🥈' : c.rank === 3 ? '🥉' : `#${c.rank}`}
              </span>
              <span className="flex-1 font-semibold text-sm text-[var(--text-primary)]">{c.name}</span>
              <span className="font-bold text-amber-600 text-sm">{c.xp} XP</span>
            </div>
          ))}
        </div>
      </div>

      {/* XP distribution */}
      {xpData.length > 0 && (
        <div>
          <h3 className="text-sm font-bold text-navy mb-3">Distribuição de XP</h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={xpData}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
              <XAxis dataKey="name" tick={{ fontSize: 10 }} />
              <YAxis />
              <Tooltip />
              <Bar dataKey="xp" fill="#F59E0B" name="XP" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Certification donut */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <h3 className="text-sm font-bold text-navy mb-3">Certificação CPMAI</h3>
          {certPie.length > 0 ? (
            <ResponsiveContainer width="100%" height={180}>
              <PieChart>
                <Pie data={certPie} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={70} label>
                  {certPie.map((_, i) => <Cell key={i} fill={i === 0 ? '#10B981' : '#E5E7EB'} />)}
                </Pie>
                <Tooltip />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <p className="text-sm text-[var(--text-muted)]">Sem dados</p>
          )}
        </div>
        <div className="flex flex-col justify-center gap-2">
          <MiniStat label="CPMAI Certificados" value={certProgress.cpmai_certified || 0} />
          <MiniStat label="XP Médio da Tribo" value={gamification.tribe_avg_xp || 0} />
          <MiniStat label="XP Total da Tribo" value={gamification.tribe_total_xp || 0} />
        </div>
      </div>
    </div>
  );
}

// ─── Mini stat component ───
function MiniStat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-[var(--surface-section-cool)] rounded-lg px-3 py-2">
      <div className="text-base font-extrabold text-navy">{value}</div>
      <div className="text-[.65rem] font-medium text-[var(--text-secondary)]">{label}</div>
    </div>
  );
}
