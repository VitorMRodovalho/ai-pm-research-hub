import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

const DOMAIN_COLORS = ['#7C3AED', '#3B82F6', '#10B981', '#F59E0B', '#EF4444'];

export default function CpmaiLanding() {
  const t = usePageI18n();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [member, setMember] = useState<any>(null);
  const [denied, setDenied] = useState<'login' | 'forbidden' | null>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  // Grupo de Estudos CPMAI · Piloto (GP, 09/10/2026): so participantes engajados e a gestao. O painel decide no
  // servidor e devolve {error} aos demais; nao ha leitura publica nem autoinscricao.
  const loadCourse = useCallback(async (sb: any) => {
    const { data: d } = await sb.rpc('get_cpmai_course_dashboard');
    if (d && !d.error) { setDenied(null); return d; }
    setDenied(d?.error === 'Not authenticated' || !d ? 'login' : 'forbidden');
    return null;
  }, []);

  useEffect(() => {
    let cancelled = false;
    let retries = 0;
    async function boot() {
      const sb = getSb();
      if (!sb && retries < 30) { retries++; setTimeout(boot, 300); return; }
      const m = (window as any).navGetMember?.();
      if (m && !cancelled) setMember(m);
      if (!sb) { if (!cancelled) setLoading(false); return; }
      try {
        const d = await loadCourse(sb);
        if (!cancelled) setData(d);
      } catch (e) { console.warn('CPMAI load error:', e); }
      finally { if (!cancelled) setLoading(false); }
    }
    // O membro pode chegar depois da primeira leitura: recarrega o painel com a parte pessoal.
    const onMember = async (ev: any) => {
      const sb = getSb();
      if (!ev?.detail || !sb || cancelled) return;
      setMember(ev.detail);
      try { const d = await loadCourse(sb); if (!cancelled) setData(d); } catch {}
    };
    window.addEventListener('nav:member', onMember);
    boot();
    return () => { cancelled = true; window.removeEventListener('nav:member', onMember); };
  }, [getSb, loadCourse]);

  if (loading) return <div className="flex justify-center py-20"><div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" /></div>;

  const course = data?.course;
  const domains = data?.domains || [];
  const enrolled = !!data?.my_enrollment;
  const progress = data?.my_progress || [];
  const mockScores = data?.my_mock_scores || [];

  return (
    <div className="space-y-8">
      {/* Hero */}
      <div className="bg-gradient-to-br from-navy to-purple-900 rounded-2xl p-8 text-white">
        <div className="text-xs font-bold uppercase tracking-wider text-white/50 mb-2">PMI-CPMAI™</div>
        <h1 className="text-3xl font-extrabold mb-2">{t('cpmai.title', 'Grupo de Estudos CPMAI · Piloto')}</h1>
        <p className="text-white/70 text-sm max-w-xl">{t('cpmai.subtitle', 'Grupo de estudos do Núcleo IA & GP para a certificação PMI-CPMAI™, em fase piloto.')}</p>
        {enrolled && (
          <div className="mt-4 px-4 py-2 rounded-lg bg-green-500/20 border border-green-400/30 text-green-300 text-sm font-semibold inline-block">
            ✅ {t('cpmai.enrolled', 'Participante')}
          </div>
        )}
      </div>

      {/* Acesso restrito: quem nao participa nem e da gestao nao ve o grupo (o servidor decide) */}
      {!course && (
        <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] px-5 py-4 text-sm text-[var(--text-secondary)]" role="status">
          {denied === 'login'
            ? <>
                <p className="mb-3">{t('cpmai.login_required', 'Entre com a sua conta para ver o grupo de estudos.')}</p>
                <button onClick={() => document.dispatchEvent(new CustomEvent('open-auth'))}
                  className="px-4 py-2 rounded-lg bg-navy text-white font-semibold text-sm cursor-pointer border-0 hover:opacity-90">
                  {t('cpmai.login_cta', 'Entrar')}
                </button>
              </>
            : <p>{t('cpmai.restricted', 'Esta página é só para participantes do grupo de estudos e para a gestão. A entrada no grupo é feita pela gestão do Núcleo.')}</p>}
        </div>
      )}

      {course && (
        <a href={`${(window as any).__LANG_PREFIX || ''}/initiative/${course.id}`}
          className="block rounded-xl bg-teal-50 border border-teal-200 px-4 py-3 text-sm font-semibold text-teal-700 no-underline hover:underline">
          🚀 {t('cpmai.participant_area', 'Área do participante: eventos, materiais e quadro do grupo')} →
        </a>
      )}

      {/* Disclaimer */}
      <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-xs text-amber-900">
        ⚠️ {t('cpmai.disclaimer', 'Este curso NÃO substitui o curso oficial do PMI de 21 horas.')}
      </div>

      {/* 5 Domains */}
      {course && <div>
        <h2 className="text-lg font-extrabold text-navy mb-4">{t('cpmai.progress_by_domain', 'Domínios ECO v8')}</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3">
          {domains.map((d: any, i: number) => {
            const modules = d.modules || [];
            const completed = enrolled ? progress.filter((p: any) => modules.some((m: any) => m.id === p.module_id && p.status === 'completed')).length : 0;
            const total = modules.length;
            const pct = total > 0 ? Math.round(completed / total * 100) : 0;
            return (
              <div key={d.id} className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-4">
                <div className="text-xs font-bold uppercase tracking-wider mb-1" style={{ color: DOMAIN_COLORS[i] }}>D{d.domain_number} · {d.weight_pct}%</div>
                <div className="text-sm font-semibold text-[var(--text-primary)] mb-2">{d.name_pt}</div>
                <div className="text-xs text-[var(--text-muted)] mb-2">{total} módulos</div>
                {enrolled && (
                  <>
                    <div className="h-1.5 rounded-full bg-[var(--border-subtle)] overflow-hidden">
                      <div className="h-full rounded-full transition-all" style={{ width: `${pct}%`, background: DOMAIN_COLORS[i] }} />
                    </div>
                    <div className="text-[10px] font-bold mt-1" style={{ color: DOMAIN_COLORS[i] }}>{pct}%</div>
                  </>
                )}
              </div>
            );
          })}
        </div>
      </div>}

      {/* Mock scores (if enrolled) */}
      {enrolled && mockScores.length > 0 && (
        <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-5">
          <h3 className="text-sm font-bold text-navy mb-3">{t('cpmai.mock_exams_tab', 'Simulados')}</h3>
          <div className="space-y-2">
            {mockScores.map((ms: any) => (
              <div key={ms.id} className="flex items-center justify-between py-2 border-b border-[var(--border-subtle)] last:border-0">
                <div>
                  <span className="text-sm font-bold" style={{ color: ms.score_pct >= 75 ? '#10B981' : ms.score_pct >= 60 ? '#F59E0B' : '#EF4444' }}>{ms.score_pct}%</span>
                  {ms.mock_source && <span className="text-xs text-[var(--text-muted)] ml-2">{ms.mock_source}</span>}
                </div>
                <span className="text-xs text-[var(--text-muted)]">{new Date(ms.taken_at).toLocaleDateString('pt-BR')}</span>
              </div>
            ))}
          </div>
        </div>
      )}

    </div>
  );
}
