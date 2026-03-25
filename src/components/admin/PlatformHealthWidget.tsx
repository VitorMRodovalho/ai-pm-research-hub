import { useState, useEffect, useCallback } from 'react';

interface Props { lang?: string; }

const L: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Saúde da Plataforma', database: 'Banco de Dados', storage: 'Armazenamento', healthy: 'Saudável', warning: 'Atenção', critical: 'Crítico', tier: 'Tier: Custo Zero', checked: 'Verificado:', members: 'membros', events: 'eventos' },
  'en-US': { title: 'Platform Health', database: 'Database', storage: 'Storage', healthy: 'Healthy', warning: 'Warning', critical: 'Critical', tier: 'Tier: Zero Cost', checked: 'Checked:', members: 'members', events: 'events' },
  'es-LATAM': { title: 'Salud de la Plataforma', database: 'Base de Datos', storage: 'Almacenamiento', healthy: 'Saludable', warning: 'Atención', critical: 'Crítico', tier: 'Tier: Costo Cero', checked: 'Verificado:', members: 'miembros', events: 'eventos' },
};

function useLang(p?: string): string {
  if (p) return p;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
  }
  return 'pt-BR';
}

function ProgressBar({ label, usedMb, limitMb, pct, status }: { label: string; usedMb: number; limitMb: number; pct: number; status: string }) {
  const color = status === 'critical' ? 'bg-red-500' : status === 'warning' ? 'bg-amber-500' : 'bg-emerald-500';
  return (
    <div className="space-y-1">
      <div className="flex justify-between text-[10px]">
        <span className="font-semibold text-[var(--text-secondary)]">{label}</span>
        <span className="text-[var(--text-muted)]">{usedMb} MB / {limitMb} MB</span>
      </div>
      <div className="w-full bg-[var(--surface-section-cool)] rounded-full h-2">
        <div className={`h-2 rounded-full transition-all ${color}`} style={{ width: `${Math.min(pct, 100)}%` }} />
      </div>
      <div className="text-[9px] text-[var(--text-muted)] text-right">{pct}%</div>
    </div>
  );
}

export default function PlatformHealthWidget({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = L[lang] || L['pt-BR'];
  const [data, setData] = useState<any>(null);
  const [authorized, setAuthorized] = useState(false);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m || !(m.is_superadmin || ['manager', 'deputy_manager'].includes(m.operational_role))) return;
    setAuthorized(true);
    const { data: d } = await sb.rpc('get_platform_usage');
    if (d && !d.error) setData(d);
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!authorized || !data) return null;

  const db = data.database || {};
  const st = data.storage || {};
  const counts = data.counts || {};
  const statusLabel = (s: string) => s === 'critical' ? t.critical : s === 'warning' ? t.warning : t.healthy;

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      <div className="flex items-center gap-2 mb-3">
        <span className="text-lg">🖥️</span>
        <h3 className="text-sm font-extrabold text-navy">{t.title}</h3>
        <span className={`ml-auto text-[9px] px-2 py-0.5 rounded-full font-semibold ${
          db.status === 'critical' || st.status === 'critical' ? 'bg-red-100 text-red-700' :
          db.status === 'warning' || st.status === 'warning' ? 'bg-amber-100 text-amber-700' :
          'bg-emerald-100 text-emerald-700'
        }`}>{statusLabel(db.status === 'critical' || st.status === 'critical' ? 'critical' : db.status === 'warning' || st.status === 'warning' ? 'warning' : 'healthy')}</span>
      </div>

      <div className="space-y-3">
        <ProgressBar label={t.database} usedMb={db.used_mb || 0} limitMb={db.limit_mb || 500} pct={db.pct || 0} status={db.status || 'healthy'} />
        <ProgressBar label={t.storage} usedMb={st.used_mb || 0} limitMb={st.limit_mb || 1024} pct={st.pct || 0} status={st.status || 'healthy'} />
      </div>

      <div className="mt-3 pt-2 border-t border-[var(--border-subtle)] flex items-center justify-between text-[9px] text-[var(--text-muted)]">
        <span>👥 {counts.members || 0} {t.members} · 📅 {counts.events || 0} {t.events}</span>
        <span>{t.tier}</span>
      </div>
    </div>
  );
}
