import { useState, useEffect, useCallback } from 'react';

// #766 H1 — post-promotion journey ("first days of the real role").
// SPEC: docs/specs/SPEC_766_H1_POST_PROMOTION_JOURNEY.md
//
// The static 3-beat roadmap used to live as fixed copy (HBLOCK) INSIDE OnboardingChecklist,
// which vanishes once onboarding completes (`if (allComplete) …`) — exactly at the
// "I signed the term, now what?" dead-end (A4/A5). This island is the persistent, STATEFUL
// replacement: it appears AFTER onboarding completes, reads the real server-side milestones
// (first_attendance, first_deliverable) to check off each beat, and retires itself once both
// milestone-backed beats are achieved. FE-only: zero DB, reuses get_my_onboarding +
// get_my_milestones. Beat 3 (trail/XP) is an OPEN CTA — there is no first_xp milestone
// (PM decision), so it never auto-checks and never blocks completion.
//
// Sibling of (not wrapper around) BuddyBlock: "what I do" (this) and "who supports me"
// (BuddyBlock) are distinct surfaces with their own lifecycles (ux-leader, SPEC §7).

interface Props {
  lang?: string;
}

interface Beat {
  key: string;          // milestone key for trackable beats; '' for the open beat
  label: string;
  cta: string;
  href: string;         // appended to the lang prefix
  open?: boolean;       // beat 3: always a CTA, never auto-checks
  openHint?: string;    // muted helper under the open beat
}

interface Copy {
  title: string;
  intro: string;
  beats: Beat[];
}

// Inline trilingual (OnboardingChecklist idiom — no t(), so no 3-dict surface). Disney tone,
// no invented numbers/points (grounding rule).
const COPY: Record<string, Copy> = {
  'pt-BR': {
    title: '🚀 Seus primeiros passos no Núcleo',
    intro: 'Você já é parte ativa do time. Aqui está o que fazer nos primeiros dias para começar com tudo:',
    beats: [
      { key: 'first_attendance', label: '📅 Participe da sua primeira reunião e registre sua presença — é o que mantém você ativo.', cta: 'Ver reuniões', href: '/attendance' },
      { key: 'first_deliverable', label: '📦 Faça sua primeira entrega com a tribo — a sua primeira contribuição registrada.', cta: 'Minhas atividades', href: '/workspace#wk-my-tasks' },
      { key: '', label: '🎓 Comece a trilha PMI AI e conquiste seu primeiro XP.', cta: 'Ver Trilha', href: '/gamification', open: true, openHint: 'Conquista registrada automaticamente ao avançar na trilha.' },
    ],
  },
  'en-US': {
    title: '🚀 Your first steps at the Hub',
    intro: "You're an active member of the team now. Here's what to do in your first days to hit the ground running:",
    beats: [
      { key: 'first_attendance', label: '📅 Join your first meeting and register your attendance — it\'s what keeps you active.', cta: 'View meetings', href: '/attendance' },
      { key: 'first_deliverable', label: '📦 Ship your first deliverable with your stream — your first recorded contribution.', cta: 'My activities', href: '/workspace#wk-my-tasks' },
      { key: '', label: '🎓 Start the PMI AI trail and earn your first XP.', cta: 'View Trail', href: '/gamification', open: true, openHint: 'Recorded automatically as you progress through the trail.' },
    ],
  },
  'es-LATAM': {
    title: '🚀 Tus primeros pasos en el Núcleo',
    intro: 'Ya eres parte activa del equipo. Esto es lo que debes hacer en tus primeros días para empezar con todo:',
    beats: [
      { key: 'first_attendance', label: '📅 Participa en tu primera reunión y registra tu asistencia — es lo que te mantiene activo.', cta: 'Ver reuniones', href: '/attendance' },
      { key: 'first_deliverable', label: '📦 Realiza tu primera entrega con tu línea — tu primera contribución registrada.', cta: 'Mis actividades', href: '/workspace#wk-my-tasks' },
      { key: '', label: '🎓 Inicia la ruta PMI AI y consigue tu primer XP.', cta: 'Ver Ruta', href: '/gamification', open: true, openHint: 'Se registra automáticamente al avanzar en la ruta.' },
    ],
  },
};
function copyFor(lang: string): Copy {
  if (lang.startsWith('en')) return COPY['en-US'];
  if (lang.startsWith('es')) return COPY['es-LATAM'];
  return COPY['pt-BR'];
}

const A11Y: Record<string, { done: string; current: string; open: string }> = {
  'pt-BR': { done: 'concluído', current: 'próximo passo', open: 'opcional' },
  'en-US': { done: 'done', current: 'next step', open: 'optional' },
  'es-LATAM': { done: 'hecho', current: 'siguiente paso', open: 'opcional' },
};
function a11yFor(lang: string) {
  if (lang.startsWith('en')) return A11Y['en-US'];
  if (lang.startsWith('es')) return A11Y['es-LATAM'];
  return A11Y['pt-BR'];
}

export default function PostPromotionJourney({ lang = 'pt-BR' }: Props) {
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const c = copyFor(lang);
  const a = a11yFor(lang);
  const [achieved, setAchieved] = useState<Set<string> | null>(null);
  const [eligible, setEligible] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const [onb, ms] = await Promise.all([
      sb.rpc('get_my_onboarding'),
      sb.rpc('get_my_milestones'),
    ]);
    // Gate 3: onboarding concluded.
    const allComplete = onb?.data?.all_complete === true;
    // "Achieved" = key present in pending ∪ history (independent of acknowledgement).
    const pending: any[] = ms?.data?.pending || [];
    const history: any[] = ms?.data?.history || [];
    const keys = new Set<string>(
      [...pending, ...history].map((m) => m?.milestone_key).filter(Boolean)
    );
    // Gate 4: the onboarding_complete celebration was already seen (acknowledged → in history,
    // not pending). Avoids overlapping with OnboardingChecklist's celebration card (ux R1).
    const celebrationSeen =
      history.some((m) => m?.milestone_key === 'onboarding_complete') &&
      !pending.some((m) => m?.milestone_key === 'onboarding_complete');
    setEligible(allComplete && celebrationSeen);
    setAchieved(keys);
  }, [getSb]);

  // Boot like the sibling islands: wait for the nav member, then load.
  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) load();
      else setTimeout(boot, 500);
    };
    boot();
  }, [load]);

  if (achieved === null) return null;

  // Read the nav member once. A null member here means it is still loading (not "guest") —
  // treat it as loading so gate 1 does not misfire on a transient remount (code-reviewer M2).
  const member = (window as any).navGetMember?.();
  if (!member) return null;
  // Gates 1 & 2: promoted member (non-guest) with a tribe. GP (no tribe) excluded.
  const opRole = String(member.operational_role || 'guest');
  const hasTribe = member.tribe_id != null;
  if (opRole === 'guest' || !hasTribe || !eligible) return null;

  // Gate 5 / exit: retire once both milestone-backed beats are achieved.
  const trackable = c.beats.filter((b) => b.key);
  if (trackable.every((b) => achieved.has(b.key))) return null;

  // "current" = first trackable beat not yet achieved.
  const currentKey = trackable.find((b) => !achieved.has(b.key))?.key ?? null;

  return (
    <section
      role="region"
      aria-label={c.title}
      className="rounded-2xl border-2 border-teal/30 bg-[var(--surface-card)] p-5 mb-6 shadow-sm"
    >
      <h2 className="text-base font-extrabold text-navy dark:text-teal-200">{c.title}</h2>
      <p className="text-xs text-[var(--text-secondary)] mt-1 leading-relaxed">{c.intro}</p>

      {/* role="list" explicit: Safari strips the implicit list role when list-style is none. */}
      <ol role="list" className="mt-3 space-y-2.5 list-none pl-0">
        {c.beats.map((b, i) => {
          const isDone = !!b.key && achieved.has(b.key);
          const isCurrent = !b.open && b.key === currentKey;
          const descId = `ppj-beat-${i}`;
          return (
            <li
              key={i}
              role="listitem"
              className={`flex items-start gap-3 px-3 py-2.5 rounded-lg border ${
                isDone
                  ? 'border-emerald-200 dark:border-emerald-800 bg-emerald-50/50 dark:bg-emerald-900/15'
                  : isCurrent
                    ? 'border-teal/40 bg-teal/5'
                    : 'border-[var(--border-subtle)] bg-[var(--surface-base)]'
              }`}
            >
              <span
                aria-label={isDone ? a.done : isCurrent ? a.current : b.open ? a.open : undefined}
                className={`flex-shrink-0 mt-0.5 w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold ${
                  isDone
                    ? 'bg-emerald-500 text-white'
                    : isCurrent
                      ? 'bg-teal text-white'
                      : 'bg-teal/15 text-teal'
                }`}
              >
                {isDone ? '✓' : b.open ? '★' : i + 1}
              </span>
              <div className="flex-1 min-w-0">
                <p
                  id={descId}
                  className={`text-[12px] leading-relaxed ${
                    isDone
                      ? 'text-emerald-700 dark:text-emerald-300'
                      : isCurrent
                        ? 'text-[var(--text-primary)] font-semibold'
                        : 'text-[var(--text-secondary)]'
                  }`}
                >
                  {b.label}
                </p>
                {b.open && b.openHint && (
                  <p className="text-[10px] text-[var(--text-muted)] mt-0.5">{b.openHint}</p>
                )}
                {!isDone && (isCurrent || b.open) && (
                  <div className="mt-1.5">
                    <a
                      href={`${lp}${b.href}`}
                      aria-describedby={descId}
                      className={`min-h-[44px] inline-flex items-center px-3 rounded-lg text-[11px] font-bold no-underline ${
                        b.open
                          ? 'bg-amber-100 text-amber-700 hover:bg-amber-200'
                          : 'bg-teal text-white hover:opacity-90'
                      }`}
                    >
                      {b.cta}
                    </a>
                  </div>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    </section>
  );
}
