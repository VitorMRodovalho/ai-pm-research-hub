import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

const DOMAIN_COLORS = ['#7C3AED', '#3B82F6', '#10B981', '#F59E0B', '#EF4444'];

export default function CpmaiLanding() {
  const t = usePageI18n();
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [member, setMember] = useState<any>(null);
  const [enrolling, setEnrolling] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [motivation, setMotivation] = useState('');
  const [aiExp, setAiExp] = useState('beginner');

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  useEffect(() => {
    let cancelled = false;
    let retries = 0;
    async function boot() {
      const sb = getSb();
      const m = (window as any).navGetMember?.();
      if ((!sb || !m) && retries < 30) { retries++; setTimeout(boot, 300); return; }
      if (m && !cancelled) setMember(m);
      if (!sb) { if (!cancelled) setLoading(false); return; }
      try {
        const { data: d } = await sb.rpc('get_cpmai_course_dashboard');
        if (!cancelled) setData(d);
      } catch (e) { console.warn('CPMAI load error:', e); }
      finally { if (!cancelled) setLoading(false); }
    }
    boot();
    return () => { cancelled = true; };
  }, [getSb]);

  const handleEnroll = async () => {
    if (!data?.course?.id) return;
    setEnrolling(true);
    try {
      const sb = getSb();
      const { data: res } = await sb.rpc('enroll_in_cpmai_course', {
        p_course_id: data.course.id, p_motivation: motivation || null, p_ai_experience: aiExp,
      });
      if (res?.error) throw new Error(res.error);
      (window as any).toast?.('Inscrito com sucesso!', 'success');
      setShowForm(false);
      const { data: d } = await sb.rpc('get_cpmai_course_dashboard');
      setData(d);
    } catch (e: any) { (window as any).toast?.(e.message || 'Erro', 'error'); }
    finally { setEnrolling(false); }
  };

  if (loading) return <div className="flex justify-center py-20"><div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" /></div>;

  const course = data?.course;
  const domains = data?.domains || [];
  const enrolled = !!data?.my_enrollment;
  const canEnroll = course?.status === 'enrollment_open' || course?.status === 'in_progress';
  const progress = data?.my_progress || [];
  const mockScores = data?.my_mock_scores || [];

  return (
    <div className="space-y-8">
      {/* Hero */}
      <div className="bg-gradient-to-br from-navy to-purple-900 rounded-2xl p-8 text-white">
        <div className="text-xs font-bold uppercase tracking-wider text-white/50 mb-2">PMI-CPMAI™</div>
        <h1 className="text-3xl font-extrabold mb-2">{t('cpmai.title', 'Preparatório CPMAI')}</h1>
        <p className="text-white/70 text-sm max-w-xl">{t('cpmai.subtitle', 'Curso preparatório para a certificação PMI-CPMAI™')}</p>
        {course && (
          <div className="flex flex-wrap gap-3 mt-4 text-xs">
            <span className="px-2.5 py-1 rounded-full bg-white/10">{course.status === 'draft' ? 'Em preparação' : course.status}</span>
            {data.enrollment_count > 0 && <span className="px-2.5 py-1 rounded-full bg-white/10">{data.enrollment_count} inscritos</span>}
            {course.max_capacity && <span className="px-2.5 py-1 rounded-full bg-white/10">Máx. {course.max_capacity} vagas</span>}
          </div>
        )}
        {enrolled ? (
          <div className="mt-4 px-4 py-2 rounded-lg bg-green-500/20 border border-green-400/30 text-green-300 text-sm font-semibold inline-block">
            ✅ {t('cpmai.enrolled', 'Inscrito')}
          </div>
        ) : canEnroll && member ? (
          <button onClick={() => setShowForm(true)}
            className="mt-4 px-6 py-2.5 rounded-lg bg-white text-navy font-bold text-sm cursor-pointer border-0 hover:opacity-90">
            {t('cpmai.enroll_cta', 'Inscrever-se')}
          </button>
        ) : null}
      </div>

      {/* Disclaimer */}
      <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-xs text-amber-900">
        ⚠️ {t('cpmai.disclaimer', 'Este curso NÃO substitui o curso oficial do PMI de 21 horas.')}
      </div>

      {/* 5 Domains */}
      <div>
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
      </div>

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

      {/* Enrollment form modal */}
      {showForm && (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 p-4" onClick={() => setShowForm(false)}>
          <div className="bg-[var(--surface-elevated)] rounded-2xl border border-[var(--border-default)] shadow-2xl w-full max-w-md p-6" onClick={e => e.stopPropagation()}>
            <h3 className="text-base font-bold text-navy mb-4">{t('cpmai.enroll_cta', 'Inscrever-se')}</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-bold text-navy mb-1">{t('cpmai.motivation', 'Motivação')}</label>
                <textarea value={motivation} onChange={e => setMotivation(e.target.value)} rows={3}
                  className="w-full px-3 py-2 text-sm rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] resize-y" />
              </div>
              <div>
                <label className="block text-xs font-bold text-navy mb-1">{t('cpmai.ai_experience', 'Experiência com IA')}</label>
                <select value={aiExp} onChange={e => setAiExp(e.target.value)}
                  className="w-full px-3 py-2 text-sm rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)]">
                  <option value="none">Nenhuma</option>
                  <option value="beginner">Iniciante</option>
                  <option value="intermediate">Intermediário</option>
                  <option value="advanced">Avançado</option>
                </select>
              </div>
            </div>
            <div className="flex gap-2 justify-end mt-4">
              <button onClick={() => setShowForm(false)} className="px-4 py-2 rounded-lg border border-[var(--border-default)] text-sm font-semibold cursor-pointer bg-transparent text-[var(--text-secondary)]">Cancelar</button>
              <button onClick={handleEnroll} disabled={enrolling} className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold cursor-pointer border-0 disabled:opacity-50">{enrolling ? '...' : t('cpmai.enroll_cta', 'Inscrever-se')}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
