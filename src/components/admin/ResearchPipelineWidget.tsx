import { useState, useEffect, useCallback } from 'react';

interface Props { lang?: string; }

interface PipelineItem {
  id: string;
  title: string;
  status: string;
  due_date: string | null;
  updated_at: string;
  tribe_name: string | null;
  tribe_id: number | null;
  authors: string | null;
}

const STATUS_STYLE: Record<string, { bg: string; label: string }> = {
  in_progress: { bg: 'bg-blue-100 text-blue-700', label: 'Em andamento' },
  review: { bg: 'bg-purple-100 text-purple-700', label: 'Revisao' },
};

function timeAgo(dateStr: string): string {
  const d = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (d === 0) return 'hoje';
  if (d === 1) return 'ontem';
  return `${d}d`;
}

export default function ResearchPipelineWidget({ lang }: Props) {
  const [data, setData] = useState<{ in_progress: PipelineItem[]; recently_done: any[]; summary: Record<string, number> } | null>(null);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m || !(m.is_superadmin || ['manager', 'deputy_manager'].includes(m.operational_role))) return;
    const { data: result } = await sb.rpc('get_global_research_pipeline');
    if (result && !result.error) setData(result);
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!data) return null;

  const items = data.in_progress || [];
  const done = data.recently_done || [];
  const summary = data.summary || {};

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      <h3 className="text-sm font-extrabold text-navy mb-3 flex items-center gap-2">
        <span className="text-lg">📄</span> Pipeline de Pesquisa
        <div className="ml-auto flex gap-2 text-[10px]">
          {Object.entries(summary).map(([s, c]) => (
            <span key={s} className={`px-1.5 py-0.5 rounded-full font-semibold ${STATUS_STYLE[s]?.bg || 'bg-gray-100 text-gray-600'}`}>
              {c} {STATUS_STYLE[s]?.label || s}
            </span>
          ))}
        </div>
      </h3>

      {items.length > 0 ? (
        <div className="space-y-2">
          {items.map((item) => {
            const st = STATUS_STYLE[item.status] || { bg: 'bg-gray-100 text-gray-600', label: item.status };
            return (
              <a
                key={item.id}
                href={item.tribe_id ? `/tribe/${item.tribe_id}?tab=board&card=${item.id}` : '#'}
                className="block rounded-lg border border-[var(--border-subtle)] p-2.5 hover:bg-[var(--surface-hover)] transition-colors no-underline"
              >
                <div className="flex items-start gap-2">
                  <div className="flex-1 min-w-0">
                    <div className="text-[12px] font-semibold text-[var(--text-primary)] truncate">{item.title}</div>
                    <div className="text-[10px] text-[var(--text-muted)] mt-0.5">
                      {item.tribe_name || '—'} {item.authors ? `· ${item.authors.split(',').map(a => a.trim().split(' ')[0]).join(', ')}` : ''} · {timeAgo(item.updated_at)}
                    </div>
                  </div>
                  <span className={`text-[8px] font-bold px-1.5 py-0.5 rounded-full ${st.bg}`}>{st.label}</span>
                </div>
              </a>
            );
          })}
        </div>
      ) : (
        <p className="text-xs text-[var(--text-muted)] py-4 text-center">Nenhum card em andamento ou revisao.</p>
      )}

      {done.length > 0 && (
        <div className="mt-3 pt-3 border-t border-[var(--border-subtle)]">
          <div className="text-[10px] font-semibold text-[var(--text-muted)] uppercase mb-1">Concluidos recentes</div>
          {done.map((d: any) => (
            <div key={d.id} className="text-[11px] text-[var(--text-secondary)] py-0.5">
              ✅ {d.title} <span className="text-[var(--text-muted)]">({d.tribe_name})</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
