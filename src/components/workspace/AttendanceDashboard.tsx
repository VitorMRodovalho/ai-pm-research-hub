import { useState, useEffect } from 'react';
import { AlertTriangle, TrendingDown, TrendingUp, Filter } from 'lucide-react';
import { hasPermission } from '../../lib/permissions';

function getSb() { return (window as any).navGetSb?.(); }

interface AttRow {
  member_id: string; member_name: string;
  tribe_id: number | null; tribe_name: string | null;
  operational_role: string;
  general_mandatory: number; general_attended: number; general_pct: number;
  tribe_mandatory: number; tribe_attended: number; tribe_pct: number;
  combined_pct: number; last_attendance: string | null;
  dropout_risk: boolean;
}

interface MemberInfo {
  id: string; tribe_id: number | null;
  operational_role: string; is_superadmin: boolean;
  name: string;
}

const INDICATOR = (pct: number) => {
  if (pct === 0) return { color: 'bg-gray-800', label: '⚫', text: 'Sem dados' };
  if (pct < 50) return { color: 'bg-red-500', label: '🔴', text: 'Crítico' };
  if (pct < 75) return { color: 'bg-yellow-500', label: '🟡', text: 'Atenção' };
  return { color: 'bg-green-500', label: '🟢', text: 'Regular' };
};

function ProgressBar({ pct, color }: { pct: number; color: string }) {
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 h-2 rounded-full bg-[var(--border-subtle)] overflow-hidden">
        <div className={`h-full rounded-full transition-all ${color}`} style={{ width: `${Math.min(pct, 100)}%` }} />
      </div>
      <span className="text-xs font-bold text-[var(--text-primary)] w-10 text-right">{pct}%</span>
    </div>
  );
}

export default function AttendanceDashboard() {
  const [member, setMember] = useState<MemberInfo | null>(null);
  const [rows, setRows] = useState<AttRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [tribeFilter, setTribeFilter] = useState<number | null>(null);
  const [tribes, setTribes] = useState<{ id: number; name: string }[]>([]);

  // Get member from nav
  useEffect(() => {
    const tryGet = () => {
      const m = (window as any).navGetMember?.();
      if (m) { setMember(m); return true; }
      return false;
    };
    if (tryGet()) return;
    const handler = ((e: CustomEvent) => { if (e.detail) setMember(e.detail); }) as EventListener;
    window.addEventListener('nav:member', handler);
    return () => window.removeEventListener('nav:member', handler);
  }, []);

  const isGP = !!member && hasPermission(member, 'admin.access');
  const isLeader = !!member && hasPermission(member, 'event.create');
  const isResearcher = !isGP && !isLeader;

  useEffect(() => {
    if (!member) return;
    (async () => {
      const sb = getSb();
      if (!sb) return;

      const { data: rawData } = await sb.rpc('get_attendance_panel');
      // Filter for leader's tribe client-side (RPC returns all active members)
      const data = (isLeader && !isGP && member.tribe_id)
        ? (rawData || []).filter((r: AttRow) => r.tribe_id === member.tribe_id)
        : rawData;
      if (data) {
        setRows(data as AttRow[]);
        const tMap = new Map<number, string>();
        (data as AttRow[]).forEach(r => {
          if (r.tribe_id && r.tribe_name) tMap.set(r.tribe_id, r.tribe_name);
        });
        setTribes(Array.from(tMap, ([id, name]) => ({ id, name })).sort((a, b) => a.id - b.id));
      }
      setLoading(false);
    })();
  }, [member]);

  if (!member || loading) {
    return (
      <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-6">
        <div className="animate-pulse space-y-3">
          <div className="h-4 bg-[var(--border-subtle)] rounded w-48" />
          <div className="h-3 bg-[var(--border-subtle)] rounded w-full" />
          <div className="h-3 bg-[var(--border-subtle)] rounded w-full" />
        </div>
      </div>
    );
  }

  // ── View C: Researcher — own stats only ──
  if (isResearcher) {
    const myRow = rows.find(r => r.member_id === member.id);
    if (!myRow) {
      return (
        <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-6 text-center">
          <p className="text-sm text-[var(--text-secondary)]">Sem dados de presença disponíveis ainda.</p>
        </div>
      );
    }

    // Calculate averages
    const tribeRows = rows.filter(r => r.tribe_id === member.tribe_id);
    const tribeAvg = tribeRows.length > 0
      ? Math.round(tribeRows.reduce((s, r) => s + r.combined_pct, 0) / tribeRows.length * 10) / 10
      : 0;
    const geralAvg = rows.length > 0
      ? Math.round(rows.reduce((s, r) => s + r.combined_pct, 0) / rows.length * 10) / 10
      : 0;

    const myPct = myRow.combined_pct;
    const belowTribe = myPct < tribeAvg;
    const tribeBelowGeral = tribeAvg < geralAvg;

    return (
      <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl p-5 space-y-4">
        <h3 className="text-sm font-bold text-[var(--text-primary)] flex items-center gap-2">
          📊 Minha Participação
        </h3>

        <div className="space-y-3">
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="font-semibold text-[var(--text-primary)]">Você</span>
              <span className="font-bold text-[var(--text-primary)]">{myPct}%</span>
            </div>
            <ProgressBar pct={myPct} color={INDICATOR(myPct).color} />
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="text-[var(--text-secondary)]">Média da Tribo</span>
              <span className="font-semibold text-[var(--text-secondary)]">{tribeAvg}%</span>
            </div>
            <ProgressBar pct={tribeAvg} color="bg-blue-400" />
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="text-[var(--text-secondary)]">Média Geral</span>
              <span className="font-semibold text-[var(--text-secondary)]">{geralAvg}%</span>
            </div>
            <ProgressBar pct={geralAvg} color="bg-purple-400" />
          </div>
        </div>

        <div className="text-xs text-[var(--text-secondary)] pt-2 border-t border-[var(--border-subtle)] space-y-1">
          {belowTribe ? (
            <p className="flex items-center gap-1">
              <TrendingDown size={12} className="text-amber-500" />
              Sua participação está abaixo da média da tribo. Participando das próximas reuniões, você fortalece a nota do grupo.
            </p>
          ) : (
            <p className="flex items-center gap-1">
              <TrendingUp size={12} className="text-green-500" />
              Sua participação está acima da média da tribo — parabéns!
            </p>
          )}
          {tribeBelowGeral ? (
            <p className="flex items-center gap-1">
              <TrendingDown size={12} className="text-amber-500" />
              Sua tribo está abaixo da média geral do núcleo.
            </p>
          ) : (
            <p className="flex items-center gap-1">
              <TrendingUp size={12} className="text-green-500" />
              Sua tribo está acima da média geral — excelente trabalho coletivo!
            </p>
          )}
        </div>
      </div>
    );
  }

  // ── Views A & B: GP / Leader table ──
  const filtered = tribeFilter ? rows.filter(r => r.tribe_id === tribeFilter) : rows;
  const atRisk = filtered.filter(r => r.dropout_risk).length;
  const inactive = filtered.filter(r => (r.general_mandatory + r.tribe_mandatory) > 0 && r.combined_pct === 0).length;

  const fmtDate = (d: string | null) => {
    if (!d) return '—';
    return new Date(d + 'T12:00:00').toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
  };

  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-subtle)] rounded-2xl overflow-hidden">
      <div className="p-4 border-b border-[var(--border-subtle)]">
        <div className="flex items-center justify-between flex-wrap gap-3">
          <h3 className="text-sm font-bold text-[var(--text-primary)] flex items-center gap-2">
            📊 Painel de Presença {isLeader ? '(Minha Tribo)' : ''}
          </h3>

          {/* Tribe filter (GP only) */}
          {isGP && (
            <div className="flex items-center gap-2">
              <Filter size={14} className="text-[var(--text-muted)]" />
              <select
                className="text-xs px-2 py-1 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] outline-none"
                value={tribeFilter || ''}
                onChange={e => setTribeFilter(e.target.value ? Number(e.target.value) : null)}
              >
                <option value="">Todas as tribos</option>
                {tribes.map(t => (
                  <option key={t.id} value={t.id}>Tribo {t.id} — {t.name}</option>
                ))}
              </select>
            </div>
          )}
        </div>

        {/* Alert banner */}
        {(atRisk > 0 || inactive > 0) && (
          <div className="mt-3 flex items-center gap-2 text-xs p-2.5 rounded-xl bg-red-50 border border-red-200 text-red-700">
            <AlertTriangle size={14} />
            <span className="font-semibold">
              {atRisk > 0 && `${atRisk} membro${atRisk > 1 ? 's' : ''} em risco de dropout`}
              {atRisk > 0 && inactive > 0 && ' · '}
              {inactive > 0 && `${inactive} sem presença registrada`}
            </span>
          </div>
        )}
      </div>

      {/* Table */}
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="bg-[var(--surface-base)]">
              <th className="text-left px-4 py-2.5 font-semibold text-[var(--text-secondary)]">Nome</th>
              {isGP && <th className="text-left px-3 py-2.5 font-semibold text-[var(--text-secondary)]">Tribo</th>}
              <th className="text-center px-3 py-2.5 font-semibold text-[var(--text-secondary)]">Geral</th>
              <th className="text-center px-3 py-2.5 font-semibold text-[var(--text-secondary)]">Tribo</th>
              <th className="text-center px-3 py-2.5 font-semibold text-[var(--text-secondary)]">Combinado</th>
              <th className="text-center px-3 py-2.5 font-semibold text-[var(--text-secondary)]">Indicador</th>
              <th className="text-center px-3 py-2.5 font-semibold text-[var(--text-secondary)]">Última</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map(r => {
              const ind = INDICATOR(r.combined_pct);
              return (
                <tr key={r.member_id} className="border-t border-[var(--border-subtle)] hover:bg-[var(--surface-hover)] transition-colors">
                  <td className="px-4 py-2.5 font-semibold text-[var(--text-primary)] whitespace-nowrap">{r.member_name}</td>
                  {isGP && (
                    <td className="px-3 py-2.5 text-[var(--text-secondary)] whitespace-nowrap">
                      {r.tribe_name ? `T${r.tribe_id}` : '—'}
                    </td>
                  )}
                  <td className="px-3 py-2.5 text-center">
                    <span className="text-[var(--text-secondary)]">{r.general_attended}/{r.general_mandatory}</span>
                    <span className="ml-1 font-semibold text-[var(--text-primary)]">({r.general_pct}%)</span>
                  </td>
                  <td className="px-3 py-2.5 text-center">
                    <span className="text-[var(--text-secondary)]">{r.tribe_attended}/{r.tribe_mandatory}</span>
                    <span className="ml-1 font-semibold text-[var(--text-primary)]">({r.tribe_pct}%)</span>
                  </td>
                  <td className="px-3 py-2.5 text-center font-bold text-[var(--text-primary)]">{r.combined_pct}%</td>
                  <td className="px-3 py-2.5 text-center">
                    <span className="text-sm" title={ind.text}>{ind.label}</span>
                  </td>
                  <td className="px-3 py-2.5 text-center text-[var(--text-secondary)]">{fmtDate(r.last_attendance)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="px-4 py-2.5 border-t border-[var(--border-subtle)] text-[10px] text-[var(--text-muted)]">
        Fórmula: 40% presença geral + 60% presença tribo · Peso configurável em site_config
      </div>
    </div>
  );
}
