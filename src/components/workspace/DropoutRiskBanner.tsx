import { useState, useEffect } from 'react';
import { AlertTriangle, ChevronDown, ChevronUp } from 'lucide-react';

function getSb() { return (window as any).navGetSb?.(); }

interface RiskMember {
  member_id: string;
  member_name: string;
  tribe_id: number | null;
  tribe_name: string | null;
  operational_role: string;
  last_attendance_date: string | null;
  days_since_last: number;
  missed_events: number;
}

interface MemberInfo {
  id: string; tribe_id: number | null;
  operational_role: string; is_superadmin: boolean;
}

export default function DropoutRiskBanner() {
  const [member, setMember] = useState<MemberInfo | null>(null);
  const [risks, setRisks] = useState<RiskMember[]>([]);
  const [expanded, setExpanded] = useState(false);
  const [loaded, setLoaded] = useState(false);

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

  const isGP = member?.is_superadmin || ['manager', 'deputy_manager'].includes(member?.operational_role || '');
  const isLeader = member?.operational_role === 'tribe_leader';

  useEffect(() => {
    if (!member) return;
    if (!isGP && !isLeader) { setLoaded(true); return; }

    (async () => {
      const sb = getSb();
      if (!sb) return;
      const { data } = await sb.rpc('get_dropout_risk_members', { p_threshold: 3 });
      if (data) {
        let filtered = data as RiskMember[];
        // Leader sees only their tribe
        if (isLeader && !isGP) {
          filtered = filtered.filter(r => r.tribe_id === member.tribe_id);
        }
        setRisks(filtered);
      }
      setLoaded(true);
    })();
  }, [member]);

  // Don't render if not loaded, not authorized, or no risks
  if (!loaded || (!isGP && !isLeader) || risks.length === 0) return null;

  const fmtDate = (d: string | null) => {
    if (!d) return 'Nunca';
    return new Date(d + 'T12:00:00').toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });
  };

  return (
    <div className="rounded-2xl border-2 border-amber-300 bg-amber-50 overflow-hidden" style={{ '--dark-bg': 'rgba(180, 83, 9, 0.1)', '--dark-border': 'rgba(253, 211, 77, 0.3)' } as React.CSSProperties}>
      {/* Banner header */}
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center justify-between px-4 py-3 bg-transparent border-0 cursor-pointer text-left"
      >
        <div className="flex items-center gap-2.5">
          <AlertTriangle size={18} className="text-amber-600 flex-shrink-0" />
          <div>
            <span className="text-sm font-bold text-amber-900">
              {risks.length} membro{risks.length > 1 ? 's' : ''} em risco de dropout
            </span>
            <span className="text-xs text-amber-700 ml-2">
              (3+ reuniões consecutivas sem presença)
            </span>
          </div>
        </div>
        <div className="flex items-center gap-1 text-xs font-semibold text-amber-700">
          {expanded ? 'Ocultar' : 'Ver lista'}
          {expanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
        </div>
      </button>

      {/* Expandable table */}
      {expanded && (
        <div className="border-t border-amber-200 overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-amber-100/50">
                <th className="text-left px-4 py-2 font-semibold text-amber-800">Nome</th>
                <th className="text-left px-3 py-2 font-semibold text-amber-800">Tribo</th>
                <th className="text-center px-3 py-2 font-semibold text-amber-800">Última presença</th>
                <th className="text-center px-3 py-2 font-semibold text-amber-800">Dias sem comparecer</th>
                <th className="text-center px-3 py-2 font-semibold text-amber-800">Faltas consecutivas</th>
              </tr>
            </thead>
            <tbody>
              {risks.map(r => (
                <tr key={r.member_id} className="border-t border-amber-200/60 hover:bg-amber-100/30 transition-colors">
                  <td className="px-4 py-2 font-semibold text-amber-900">{r.member_name}</td>
                  <td className="px-3 py-2 text-amber-800">
                    {r.tribe_name ? `T${r.tribe_id} — ${r.tribe_name}` : '—'}
                  </td>
                  <td className="px-3 py-2 text-center text-amber-800">{fmtDate(r.last_attendance_date)}</td>
                  <td className="px-3 py-2 text-center">
                    <span className={`font-bold ${r.days_since_last > 60 ? 'text-red-700' : 'text-amber-800'}`}>
                      {r.days_since_last}d
                    </span>
                  </td>
                  <td className="px-3 py-2 text-center font-bold text-red-700">{r.missed_events}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
