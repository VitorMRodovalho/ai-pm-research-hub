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
  'pt-BR': { title: 'Complete seu Onboarding', progress: 'concluídos', expand: 'Ver todos', collapse: 'Minimizar', hide: 'Dispensar', done: 'Concluído', pending: 'Pendente', accept: 'Li e aceito', complete: 'Onboarding concluído! 🎉', markDone: 'Marcar como feito', visitTribe: 'Visitar tribo', viewTrail: 'Ver Trilha', step: 'Passo', of: 'de', attendanceCta: '📅 Ver reuniões' },
  'en-US': { title: 'Complete your Onboarding', progress: 'completed', expand: 'View all', collapse: 'Minimize', hide: 'Dismiss', done: 'Done', pending: 'Pending', accept: 'I have read and accept', complete: 'Onboarding complete! Welcome! 🎉', markDone: 'Mark as done', visitTribe: 'Visit stream', viewTrail: 'View Trail', step: 'Step', of: 'of', attendanceCta: '📅 View meetings' },
  'es-LATAM': { title: 'Complete su Integración', progress: 'completados', expand: 'Ver todos', collapse: 'Minimizar', hide: 'Descartar', done: 'Hecho', pending: 'Pendiente', accept: 'He leído y acepto', complete: '¡Integración completa! 🎉', markDone: 'Marcar como hecho', visitTribe: 'Visitar línea', viewTrail: 'Ver Ruta', step: 'Paso', of: 'de', attendanceCta: '📅 Ver reuniones' },
};

// Steps that carry a bespoke CTA below. Any other step (e.g. the #1103 role-scoped
// leader steps — leader_refine_theme/roadmap/capture_video/review_tribe) falls through
// to the generic "visit tribe + mark done" affordance, so no step is ever a dead-end.
const BESPOKE_CTA_STEPS = new Set([
  'code_of_conduct', 'complete_profile', 'meet_tribe', 'start_trail',
  'volunteer_term', 'first_meeting', 'vep_acceptance',
]);

// #766 H1 — the static "first days" 3-beat roadmap that used to live here was promoted to a
// persistent, stateful island: src/components/onboarding/PostPromotionJourney.tsx. It lives
// OUTSIDE this card so it survives onboarding completion (this card vanishes at allComplete),
// resolving the "I signed the term, now what?" dead-end. The `attendanceCta` label it shared
// with the first_meeting step below now lives in the `L` dict.

// J5 #740 — "Disney tone": celebrate the onboarding-complete milestone instead of the
// checklist silently vanishing. Shown once (server-side gated via member_milestones) when all steps are done.
interface Celebrate { title: string; body: string; cta: string; dismiss: string }
const CELEBRATE: Record<string, Celebrate> = {
  'pt-BR': {
    title: '🎉 Onboarding concluído!',
    body: 'Parabéns! Você completou todas as etapas e agora faz parte ativa do Núcleo. Bora construir IA aplicada a projetos com a gente!',
    cta: '🚀 Explorar a plataforma',
    dismiss: 'Fechar',
  },
  'en-US': {
    title: '🎉 Onboarding complete!',
    body: 'Congratulations! You\'ve finished every step and you\'re now an active member of the Hub. Let\'s build AI applied to projects together!',
    cta: '🚀 Explore the platform',
    dismiss: 'Close',
  },
  'es-LATAM': {
    title: '🎉 ¡Integración completa!',
    body: '¡Felicitaciones! Completaste todos los pasos y ya eres parte activa del Núcleo. ¡Vamos a construir IA aplicada a proyectos juntos!',
    cta: '🚀 Explorar la plataforma',
    dismiss: 'Cerrar',
  },
};
function celebrate(lang: string): Celebrate {
  if (lang.startsWith('en')) return CELEBRATE['en-US'];
  if (lang.startsWith('es')) return CELEBRATE['es-LATAM'];
  return CELEBRATE['pt-BR'];
}

export default function OnboardingChecklist({ lang = 'pt-BR' }: Props) {
  const l = L[lang] || L['pt-BR'];
  // p123 i18n nav: prefix preserves /en /es when navigating between sections
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [steps, setSteps] = useState<Step[]>([]);
  const [total, setTotal] = useState(0);
  const [completed, setCompleted] = useState(0);
  const [allComplete, setAllComplete] = useState(false);
  const [expanded, setExpanded] = useState(true); // auto-expand for new members
  const [loading, setLoading] = useState(true);
  // J5 #740 / #766 PR1 — the celebration "seen" state now persists SERVER-SIDE
  // (member_milestones via get_my_milestones/acknowledge_milestone): cross-device +
  // auditable, replacing the old localStorage flag `nia_onboarding_celebrated`.
  // `celebrationPending` = onboarding_complete milestone exists and is unacknowledged.
  // `sessionHidden` = transient ✕ on the working checklist (not persisted).
  const [celebrationPending, setCelebrationPending] = useState(false);
  const [sessionHidden, setSessionHidden] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    // #766 PR1 — fetch onboarding + the server-side celebration state in PARALLEL so
    // `allComplete` and `celebrationPending` resolve together (no flicker window where
    // allComplete=true but celebrationPending still false on slow networks; ux R1).
    const [onb, ms] = await Promise.all([
      sb.rpc('get_my_onboarding'),
      sb.rpc('get_my_milestones'),
    ]);
    const data = onb?.data;
    if (data?.steps) {
      setSteps(data.steps);
      setTotal(data.total_steps || 0);
      setCompleted(data.completed_steps || 0);
      setAllComplete(data.all_complete || false);
    }
    const pending = ms?.data?.pending;
    setCelebrationPending(
      Array.isArray(pending) && pending.some((p: any) => p.milestone_key === 'onboarding_complete')
    );
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

  if (loading) return null;
  if (steps.length === 0) return null;

  // J5 #740 / #766 PR1 — celebrate the onboarding-complete milestone once. The "seen"
  // state is server-side (member_milestones): show only while the milestone is pending
  // (unacknowledged). Backfilled / already-seen members have it acknowledged and skip
  // the card (cross-device, no localStorage). Dismiss persists via acknowledge_milestone.
  if (allComplete) {
    if (!celebrationPending) return null;
    const c = celebrate(lang);
    const dismissCelebration = () => {
      setCelebrationPending(false);
      getSb()?.rpc('acknowledge_milestone', { p_milestone_key: 'onboarding_complete' });
    };
    return (
      <div role="status" className="rounded-2xl border-2 border-emerald-300 dark:border-emerald-800 bg-emerald-50/40 dark:bg-emerald-900/15 p-5 mb-6 shadow-sm text-center">
        <h2 className="text-base font-extrabold text-emerald-700 dark:text-emerald-300">{c.title}</h2>
        <p className="text-xs text-emerald-800 dark:text-emerald-200 mt-1.5 leading-relaxed">{c.body}</p>
        <div className="mt-3 flex items-center justify-center gap-2">
          <a href={`${lp}/gamification`} className="px-3 py-1.5 rounded-lg bg-emerald-600 text-white text-[0.6875rem] font-bold no-underline hover:bg-emerald-700">{c.cta}</a>
          <button onClick={dismissCelebration} className="px-3 py-1.5 rounded-lg border border-emerald-300 dark:border-emerald-700 text-emerald-700 dark:text-emerald-300 text-[0.6875rem] font-semibold bg-transparent cursor-pointer hover:bg-emerald-100/50">{c.dismiss}</button>
        </div>
      </div>
    );
  }

  if (sessionHidden) return null;

  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;
  const member = (window as any).navGetMember?.();
  // A3 #740 — linear stepper: communicate the sequence, not just a %% bar.
  const firstIncomplete = steps.findIndex((s) => s.status !== 'completed');
  const currentStep = firstIncomplete === -1 ? steps.length : firstIncomplete + 1;

  return (
    <div className="rounded-2xl border-2 border-teal/30 bg-[var(--surface-card)] p-5 mb-6 shadow-sm">
      {/* #766 H1 — the "first days" 3-beat roadmap moved to <PostPromotionJourney> (a persistent
          island that survives onboarding completion). It is no longer rendered inside this card. */}

      {/* Header */}
      <div className="flex items-center justify-between mb-3">
        <div>
          <h2 className="text-base font-extrabold text-navy">{l.title}</h2>
          <span className="text-xs text-[var(--text-muted)]">
            <span className="font-semibold text-teal">{l.step} {currentStep} {l.of} {steps.length}</span>
            <span className="mx-1.5">·</span>
            {completed}/{total} {l.progress}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setExpanded(!expanded)}
            className="text-[10px] text-teal font-semibold cursor-pointer bg-transparent border-0 hover:underline">
            {expanded ? l.collapse : l.expand}
          </button>
          <button onClick={() => setSessionHidden(true)} aria-label={l.hide}
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
          {steps.map((s, i) => (
            <div key={s.step_id} className={`flex items-start gap-3 px-3 py-2.5 rounded-lg border ${s.status === 'completed' ? 'border-emerald-200 bg-emerald-50/50' : 'border-[var(--border-subtle)] bg-[var(--surface-base)]'}`}>
              <span className={`flex-shrink-0 mt-0.5 w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold ${s.status === 'completed' ? 'bg-emerald-500 text-white' : 'bg-teal/15 text-teal'}`}>
                {s.status === 'completed' ? '✓' : i + 1}
              </span>
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
                      <a href={`${lp}/profile`} className="px-2.5 py-1 rounded-lg bg-blue-100 text-blue-700 text-[10px] font-semibold no-underline hover:bg-blue-200">
                        👤 {l.markDone}
                      </a>
                    )}
                    {s.step_id === 'meet_tribe' && member?.tribe_id && (
                      <a href={`${lp}/tribe/${member.tribe_id}`} className="px-2.5 py-1 rounded-lg bg-purple-100 text-purple-700 text-[10px] font-semibold no-underline hover:bg-purple-200">
                        🔬 {l.visitTribe}
                      </a>
                    )}
                    {s.step_id === 'start_trail' && (
                      <a href={`${lp}/gamification`} className="px-2.5 py-1 rounded-lg bg-amber-100 text-amber-700 text-[10px] font-semibold no-underline hover:bg-amber-200">
                        🎓 {l.viewTrail}
                      </a>
                    )}
                    {s.step_id === 'volunteer_term' && (
                      <a href={`${lp}/volunteer-agreement`} className="px-2.5 py-1 rounded-lg bg-navy text-white text-[10px] font-semibold no-underline hover:opacity-90">
                        📄 {l.accept}
                      </a>
                    )}
                    {s.step_id === 'first_meeting' && (
                      <a href={`${lp}/attendance`} className="px-2.5 py-1 rounded-lg bg-green-100 text-green-700 text-[10px] font-semibold no-underline hover:bg-green-200">
                        {l.attendanceCta}
                      </a>
                    )}
                    {s.step_id === 'vep_acceptance' && (
                      <button onClick={() => completeStep(s.step_id)}
                        className="px-2.5 py-1 rounded-lg border border-[var(--border-default)] text-[var(--text-secondary)] text-[10px] font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]">
                        ✓ {l.markDone}
                      </button>
                    )}
                    {/* #1103: generic fallback for role-scoped leader steps (no bespoke CTA) */}
                    {!BESPOKE_CTA_STEPS.has(s.step_id) && (
                      <>
                        {member?.tribe_id && (
                          <a href={`${lp}/tribe/${member.tribe_id}`} className="px-2.5 py-1 rounded-lg bg-purple-100 text-purple-700 text-[10px] font-semibold no-underline hover:bg-purple-200">
                            🔬 {l.visitTribe}
                          </a>
                        )}
                        <button onClick={() => completeStep(s.step_id)}
                          className="px-2.5 py-1 rounded-lg border border-[var(--border-default)] text-[var(--text-secondary)] text-[10px] font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]">
                          ✓ {l.markDone}
                        </button>
                      </>
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
