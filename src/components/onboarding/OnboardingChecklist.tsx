import { useState, useEffect, useCallback } from 'react';

interface Step {
  step_id: string;
  step_order: number;
  label_pt: string;
  label_en: string;
  label_es: string;
  description_pt: string;
  description_en: string;
  description_es: string;
  icon: string;
  is_required: boolean;
  status: string;
  completed_at: string | null;
}

interface Props {
  lang?: string;
}

function getLabel(s: Step, lang: string): string {
  if (lang.startsWith('en')) return s.label_en || s.label_pt;
  if (lang.startsWith('es')) return s.label_es || s.label_pt;
  return s.label_pt;
}

function getDesc(s: Step, lang: string): string {
  if (lang.startsWith('en')) return s.description_en || s.description_pt;
  if (lang.startsWith('es')) return s.description_es || s.description_pt;
  return s.description_pt;
}

const L: Record<string, Record<string, string>> = {
  'pt-BR': { title: 'Complete seu Onboarding', progress: 'concluídos', expand: 'Ver todos', collapse: 'Minimizar', done: 'Concluído', pending: 'Pendente', accept: 'Li e aceito', complete: 'Onboarding concluído! 🎉', markDone: 'Marcar como feito', visitTribe: 'Visitar tribo', viewTrail: 'Ver Trilha' },
  'en-US': { title: 'Complete your Onboarding', progress: 'completed', expand: 'View all', collapse: 'Minimize', done: 'Done', pending: 'Pending', accept: 'I have read and accept', complete: 'Onboarding complete! Welcome! 🎉', markDone: 'Mark as done', visitTribe: 'Visit stream', viewTrail: 'View Trail' },
  'es-LATAM': { title: 'Complete su Integración', progress: 'completados', expand: 'Ver todos', collapse: 'Minimizar', done: 'Hecho', pending: 'Pendiente', accept: 'He leído y acepto', complete: '¡Integración completa! 🎉', markDone: 'Marcar como hecho', visitTribe: 'Visitar línea', viewTrail: 'Ver Ruta' },
};

export default function OnboardingChecklist({ lang = 'pt-BR' }: Props) {
  const l = L[lang] || L['pt-BR'];
  const [steps, setSteps] = useState<Step[]>([]);
  const [total, setTotal] = useState(0);
  const [completed, setCompleted] = useState(0);
  const [allComplete, setAllComplete] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [loading, setLoading] = useState(true);
  const [dismissed, setDismissed] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.rpc('get_my_onboarding');
    if (data?.steps) {
      setSteps(data.steps);
      setTotal(data.total_steps || 0);
      setCompleted(data.completed_steps || 0);
      setAllComplete(data.all_complete || false);
    }
    setLoading(false);
  }, [getSb]);

  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) load();
      else setTimeout(boot, 500);
    };
    boot();
  }, [load]);

  const completeStep = async (stepId: string, metadata?: any) => {
    const sb = getSb();
    if (!sb) return;
    await sb.rpc('complete_onboarding_step', { p_step_id: stepId, p_metadata: metadata || {} });
    load();
    (window as any).toast?.(l.done + '!', 'success');
  };

  if (loading || allComplete || dismissed) return null;
  if (steps.length === 0) return null;

  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;
  const member = (window as any).navGetMember?.();

  return (
    <div className="rounded-2xl border-2 border-teal/30 bg-[var(--surface-card)] p-5 mb-6 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between mb-3">
        <div>
          <h2 className="text-base font-extrabold text-navy">{l.title}</h2>
          <span className="text-xs text-[var(--text-muted)]">{completed}/{total} {l.progress}</span>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setExpanded(!expanded)}
            className="text-[10px] text-teal font-semibold cursor-pointer bg-transparent border-0 hover:underline">
            {expanded ? l.collapse : l.expand}
          </button>
          <button onClick={() => setDismissed(true)}
            className="text-[var(--text-muted)] hover:text-[var(--text-primary)] bg-transparent border-0 cursor-pointer text-sm">✕</button>
        </div>
      </div>

      {/* Progress bar */}
      <div className="w-full bg-[var(--surface-section-cool)] rounded-full h-2 mb-3">
        <div className="bg-teal h-2 rounded-full transition-all duration-500" style={{ width: `${pct}%` }} />
      </div>

      {/* Steps */}
      {expanded && (
        <div className="space-y-2">
          {steps.map((s) => (
            <div key={s.step_id} className={`flex items-start gap-3 px-3 py-2.5 rounded-lg border ${s.status === 'completed' ? 'border-emerald-200 bg-emerald-50/50' : 'border-[var(--border-subtle)] bg-[var(--surface-base)]'}`}>
              <span className="text-base flex-shrink-0 mt-0.5">{s.icon}</span>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className={`text-[12px] font-semibold ${s.status === 'completed' ? 'text-emerald-700 line-through' : 'text-[var(--text-primary)]'}`}>
                    {getLabel(s, lang)}
                  </span>
                  {s.status === 'completed' && <span className="text-emerald-600 text-[10px]">✅</span>}
                </div>
                <p className="text-[10px] text-[var(--text-muted)] mt-0.5">{getDesc(s, lang)}</p>
                {s.status !== 'completed' && (
                  <div className="mt-1.5 flex gap-2 flex-wrap">
                    {s.step_id === 'code_of_conduct' && (
                      <button onClick={() => completeStep('code_of_conduct', { accepted: true })}
                        className="px-2.5 py-1 rounded-lg bg-teal text-white text-[10px] font-semibold cursor-pointer border-0 hover:opacity-90">
                        {l.accept}
                      </button>
                    )}
                    {s.step_id === 'complete_profile' && (
                      <a href="/profile" className="px-2.5 py-1 rounded-lg bg-blue-100 text-blue-700 text-[10px] font-semibold no-underline hover:bg-blue-200">
                        👤 {l.markDone}
                      </a>
                    )}
                    {s.step_id === 'meet_tribe' && member?.tribe_id && (
                      <a href={`/tribe/${member.tribe_id}`} className="px-2.5 py-1 rounded-lg bg-purple-100 text-purple-700 text-[10px] font-semibold no-underline hover:bg-purple-200">
                        🔬 {l.visitTribe}
                      </a>
                    )}
                    {s.step_id === 'start_trail' && (
                      <a href="/gamification" className="px-2.5 py-1 rounded-lg bg-amber-100 text-amber-700 text-[10px] font-semibold no-underline hover:bg-amber-200">
                        🎓 {l.viewTrail}
                      </a>
                    )}
                    {['volunteer_term', 'vep_acceptance'].includes(s.step_id) && (
                      <button onClick={() => completeStep(s.step_id)}
                        className="px-2.5 py-1 rounded-lg border border-[var(--border-default)] text-[var(--text-secondary)] text-[10px] font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]">
                        ✓ {l.markDone}
                      </button>
                    )}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
