import { useState, useEffect, useCallback, useRef } from 'react';

interface Props {
  lang?: string;
}

// #766 PR3 — generic server-side milestone celebration surface. Reads
// get_my_milestones().pending and celebrates the milestones that fire OUTSIDE the
// onboarding checklist (first_attendance, first_deliverable). It is mounted globally in
// BaseLayout because those events happen on the attendance / tribe pages, not on the
// workspace checklist. The "seen" state is server-side (acknowledge_milestone), so it is
// cross-device and shown once. Disney tone, ZERO numbers (grounding rule).
//
// Scope boundaries (ux-leader, PR3):
//  - onboarding_complete stays owned by OnboardingChecklist's own card (no double card).
//  - term_signed stays deferred — the HBLOCK "first days" card on the checklist already
//    owns the just-signed beat. Folding it here would double-celebrate.
//  - promotion (PR4) is owned here: it fires when operational_role is elevated to tribe_leader
//    (no competing card), so the generic surface is its natural home.
//  - profile_complete (PR5) is owned here: it fires when the member first saves their profile
//    (members.profile_completed_at NULL -> NOT NULL), which can happen on any page, so the global
//    surface is its natural home. Copy celebrates the completed profile — NO points mention (the
//    "+50pts" award does not exist; SPEC §2 grounding).
interface Copy {
  title: string;
  body: string;
  cta: string;
  ctaHref: string | null; // null = derive at render time (or suppress) — see first_deliverable
  dismiss: string;
}

const MILESTONE_COPY: Record<string, Record<string, Copy>> = {
  first_attendance: {
    'pt-BR': { title: '🎉 Primeira presença registrada!', body: 'Você apareceu — e isso faz toda a diferença. Bem-vindo(a) à rotina do Núcleo!', cta: '🏆 Ver meu ranking', ctaHref: '/gamification', dismiss: 'Fechar' },
    'en-US': { title: '🎉 First attendance logged!', body: 'You showed up — and that makes all the difference. Welcome to the rhythm of the Hub!', cta: '🏆 See my ranking', ctaHref: '/gamification', dismiss: 'Close' },
    'es-LATAM': { title: '🎉 ¡Primera asistencia registrada!', body: 'Apareciste — y eso marca la diferencia. ¡Bienvenido(a) al ritmo del Núcleo!', cta: '🏆 Ver mi ranking', ctaHref: '/gamification', dismiss: 'Cerrar' },
  },
  first_deliverable: {
    'pt-BR': { title: '🚀 Primeiro entregável concluído!', body: 'Uma entrega real, do zero. É assim que o Núcleo constrói — passo a passo, juntos.', cta: '🔬 Ver minha tribo', ctaHref: null, dismiss: 'Fechar' },
    'en-US': { title: '🚀 First deliverable complete!', body: 'A real output, from scratch. This is how the Hub builds — step by step, together.', cta: '🔬 See my stream', ctaHref: null, dismiss: 'Close' },
    'es-LATAM': { title: '🚀 ¡Primer entregable completado!', body: 'Un resultado real, desde cero. Así construye el Núcleo — paso a paso, juntos.', cta: '🔬 Ver mi línea', ctaHref: null, dismiss: 'Cerrar' },
  },
  promotion: {
    'pt-BR': { title: '🌟 Você é liderança no Núcleo!', body: 'Assumir a frente é um voto de confiança da comunidade — e a sua trajetória mostra que você está pronto(a). Conte com a gente nessa nova jornada.', cta: '🧭 Abrir meu espaço', ctaHref: '/workspace', dismiss: 'Fechar' },
    'en-US': { title: '🌟 You are a leader at the Hub now!', body: 'Stepping up is a vote of confidence from the community — and your path shows you are ready. We have got your back on this new journey.', cta: '🧭 Open my workspace', ctaHref: '/workspace', dismiss: 'Close' },
    'es-LATAM': { title: '🌟 ¡Ahora lideras en el Núcleo!', body: 'Dar el paso al frente es un voto de confianza de la comunidad — y tu trayectoria muestra que estás listo(a). Cuenta con nosotros en este nuevo camino.', cta: '🧭 Abrir mi espacio', ctaHref: '/workspace', dismiss: 'Cerrar' },
  },
  profile_complete: {
    'pt-BR': { title: '✨ Perfil completo!', body: 'Seu perfil está pronto — agora a comunidade conhece você melhor e as conexões certas ficam mais fáceis. Que bom ter você por inteiro aqui!', cta: '🧭 Abrir meu espaço', ctaHref: '/workspace', dismiss: 'Fechar' },
    'en-US': { title: '✨ Profile complete!', body: 'Your profile is all set — now the community knows you better and the right connections come easier. So glad to have the whole you here!', cta: '🧭 Open my workspace', ctaHref: '/workspace', dismiss: 'Close' },
    'es-LATAM': { title: '✨ ¡Perfil completo!', body: 'Tu perfil está listo — ahora la comunidad te conoce mejor y las conexiones correctas son más fáciles. ¡Qué bueno tenerte completo aquí!', cta: '🧭 Abrir mi espacio', ctaHref: '/workspace', dismiss: 'Cerrar' },
  },
};

// Milestones this surface owns. Anything pending but not listed here is ignored (owned
// elsewhere or deferred). Keep in sync with MILESTONE_COPY.
const OWNED_KEYS = ['first_attendance', 'first_deliverable', 'promotion', 'profile_complete'];

function copyFor(key: string, lang: string): Copy | null {
  const m = MILESTONE_COPY[key];
  if (!m) return null;
  if (lang.startsWith('en')) return m['en-US'];
  if (lang.startsWith('es')) return m['es-LATAM'];
  return m['pt-BR'];
}

export default function MilestoneCelebration({ lang = 'pt-BR' }: Props) {
  // p123 i18n nav prefix: preserve /en /es on CTA links
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [queue, setQueue] = useState<string[]>([]); // pending owned milestone keys, FIFO
  const [current, setCurrent] = useState<string | null>(null);
  const dismissRef = useRef<HTMLButtonElement>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.rpc('get_my_milestones');
    const pending = data?.pending;
    if (!Array.isArray(pending)) return;
    const owned = pending
      .map((p: any) => p.milestone_key)
      .filter((k: string) => OWNED_KEYS.includes(k));
    if (owned.length > 0) {
      setQueue(owned);
      setCurrent(owned[0]); // one at a time
    }
  }, [getSb]);

  // Boot the same way as OnboardingChecklist: wait for the nav member to resolve, then load.
  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) load();
      else setTimeout(boot, 500);
    };
    boot();
  }, [load]);

  const dismiss = useCallback(() => {
    setCurrent((cur) => {
      if (!cur) return null;
      getSb()?.rpc('acknowledge_milestone', { p_milestone_key: cur }); // persist "seen" server-side
      setQueue((q) => {
        const next = q.filter((k) => k !== cur);
        // 300ms cooldown before the next card so a fast mobile tap doesn't cascade onto it.
        if (next.length > 0) setTimeout(() => setCurrent(next[0]), 300);
        return next;
      });
      return null;
    });
  }, [getSb]);

  // a11y: move focus to the dismiss button when a card appears (keyboard users).
  useEffect(() => {
    if (current) dismissRef.current?.focus();
  }, [current]);

  // a11y: Escape closes the current card (consistent with HelpFloatingButton).
  useEffect(() => {
    if (!current) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') dismiss(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [current, dismiss]);

  if (!current) return null;
  const c = copyFor(current, lang);
  if (!c) return null;

  // CTA href: first_deliverable points to the member's tribe (suppressed if unknown); other
  // milestones use the static ctaHref with the locale prefix.
  let href = c.ctaHref;
  if (current === 'first_deliverable') {
    const tribeId = (window as any).navGetMember?.()?.tribe_id;
    href = tribeId ? `${lp}/tribe/${tribeId}` : null;
  } else if (href) {
    href = `${lp}${href}`;
  }

  return (
    <div
      role="status"
      aria-live="polite"
      className="fixed bottom-4 left-4 z-40 w-[calc(100vw-2rem)] max-w-sm rounded-2xl border-2 border-emerald-300 dark:border-emerald-800 bg-emerald-50 dark:bg-emerald-900/30 p-4 shadow-lg"
    >
      <h2 className="text-sm font-extrabold text-emerald-700 dark:text-emerald-300">{c.title}</h2>
      <p className="text-xs text-emerald-800 dark:text-emerald-200 mt-1.5 leading-relaxed">{c.body}</p>
      <div className="mt-3 flex items-center gap-2 flex-wrap">
        {/* Dismiss is the primary action (keep working); it receives focus on appear. */}
        <button
          ref={dismissRef}
          onClick={dismiss}
          aria-label={c.dismiss}
          className="min-h-[44px] px-4 rounded-lg bg-emerald-600 text-white text-xs font-bold cursor-pointer border-0 hover:bg-emerald-700"
        >
          {c.dismiss}
        </button>
        {href && (
          <a
            href={href}
            className="min-h-[44px] inline-flex items-center px-4 rounded-lg border border-emerald-300 dark:border-emerald-700 text-emerald-700 dark:text-emerald-300 text-xs font-semibold no-underline hover:bg-emerald-100/50"
          >
            {c.cta}
          </a>
        )}
      </div>
    </div>
  );
}
