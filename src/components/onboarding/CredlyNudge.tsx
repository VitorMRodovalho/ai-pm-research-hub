import { useState, useEffect, useCallback } from 'react';

// Credly adoption nudge (F2 #740 follow-up).
//
// The /profile Credly card already exists (the input + "Verify" button + the 3-step inline guide
// shipped as "W4 Block F — Credly guide", PR #762). But the screen is passive: a member only links
// their Credly if they go look. Live grounding 2026-06-19: 8/8 of the research-tribe members without
// a credly_url are active researchers — they surface no PMI badges, so they earn no badge XP. This
// island PULLS them to the field: a dismissible /workspace banner that deep-links to it. PM decision
// 2026-06-19: FE-only, no new DB state (mirrors EntryChapterNudge #625).
//
// Eligibility mirrors what the /profile Credly field can act on, so the nudge never dead-ends, and is
// scoped to the measured cohort (the engaged research population) so it does not spam the wider base:
//   - registered member (has id), not a guest (guests have their own pre-onboarding flow + islands)
//   - active member_status (mirror #788: only exclude when the field is present and not 'active')
//   - not alumni (off-ramp — nudging badge XP to someone who left is wrong)
//   - in a research tribe (tribe_id) — the engaged cohort; tribe_leaders already all have a link
//   - no credly_url yet
// All signals come from the in-memory nav member (get_member_by_auth already returns credly_url,
// operational_role, member_status, tribe_id), so the island needs NO network call.
// Live grounding 2026-06-19: this predicate matches exactly the 8 researchers without a Credly link.
//
// Dismissal is a localStorage flag ("not now", per device) with a 14-day TTL — a fat-finger dismiss
// should not silence the nudge forever (ux-leader R2). Once a credly_url is saved, the member object
// carries it on the next load and the banner disappears on its own regardless of the flag.

const DISMISS_KEY = 'nucleo:credlyNudgeDismissed';
const DISMISS_TTL_MS = 14 * 24 * 60 * 60 * 1000;

interface Copy {
  title: string;
  body: string;
  cta: string;
  dismiss: string;
  ariaLabel: string;
}

const COPY: Record<string, Copy> = {
  'pt-BR': {
    title: 'Conecte seu Credly e ganhe XP',
    body: 'Adicione seu link público do Credly ao perfil. Quando você ganha badges PMI, o XP entra automático — configure agora para não perder nenhum.',
    cta: 'Conectar meu Credly',
    dismiss: 'Agora não',
    ariaLabel: 'Aviso: conecte seu Credly para ganhar XP pelas suas badges PMI',
  },
  'en-US': {
    title: 'Connect your Credly and earn XP',
    body: 'Add your public Credly link to your profile. When you earn PMI badges, the XP flows in automatically — set it up now so you don\'t miss any.',
    cta: 'Connect my Credly',
    dismiss: 'Not now',
    ariaLabel: 'Notice: connect your Credly to earn XP from your PMI badges',
  },
  'es-LATAM': {
    title: 'Conecta tu Credly y gana XP',
    body: 'Agrega tu enlace público de Credly al perfil. Cuando obtienes badges PMI, el XP entra automático — configúralo ahora para no perder ninguno.',
    cta: 'Conectar mi Credly',
    dismiss: 'Ahora no',
    ariaLabel: 'Aviso: conecta tu Credly para ganar XP por tus badges PMI',
  },
};

interface Props {
  lang?: string;
}

export default function CredlyNudge({ lang = 'pt-BR' }: Props) {
  const copy = COPY[lang] || COPY['pt-BR'];
  const [show, setShow] = useState(false);

  const evaluate = useCallback(() => {
    // Per-device "not now" with a 14-day TTL (older flag = re-nudge once).
    try {
      const raw = localStorage.getItem(DISMISS_KEY);
      if (raw) {
        const ts = Number(JSON.parse(raw)?.ts);
        if (Number.isFinite(ts) && Date.now() - ts < DISMISS_TTL_MS) return;
      }
    } catch { /* localStorage blocked / corrupt — proceed without the dismiss flag */ }

    const m = (window as any).navGetMember?.();
    // Registered member only; guests have their own pre-onboarding flow; alumni are an off-ramp.
    if (!m || !m.id) return;
    if (m.operational_role === 'guest' || m.operational_role === 'alumni') return;
    if (m.member_status && m.member_status !== 'active') return;
    // Scope to the engaged research cohort (the measured 8); the screen is the same for all.
    if (!m.tribe_id) return;
    // Already linked → nothing to nudge.
    const hasCredly = typeof m.credly_url === 'string' && m.credly_url.trim().length > 0;
    if (hasCredly) return;
    setShow(true);
  }, []);

  // Boot like the sibling islands: wait for the nav member, then evaluate once. Capped retries so an
  // anon/ghost session (member never populates) gives up instead of looping forever (code-reviewer MEDIUM).
  useEffect(() => {
    const boot = (tries: number) => {
      const m = (window as any).navGetMember?.();
      if (m) evaluate();
      else if (tries > 0) setTimeout(() => boot(tries - 1), 500);
    };
    boot(30); // ~15s cap
  }, [evaluate]);

  const dismiss = useCallback(() => {
    try { localStorage.setItem(DISMISS_KEY, JSON.stringify({ ts: Date.now() })); } catch { /* ignore */ }
    setShow(false);
  }, []);

  if (!show) return null;

  return (
    <section role="region" aria-label={copy.ariaLabel} className="mb-6">
      <div className="rounded-2xl border border-amber/40 bg-amber/5 p-5">
        <div className="flex items-start gap-3">
          {/* trophy (heroicons) — reward/XP, unambiguous vs the academic-cap used for CPMAI elsewhere (ux [2]). */}
          <svg className="w-6 h-6 text-amber flex-shrink-0" fill="none" viewBox="0 0 24 24" strokeWidth="1.8" stroke="currentColor" aria-hidden="true">
            <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 18.75h-9m9 0a3 3 0 0 1 3 3h-15a3 3 0 0 1 3-3m9 0v-3.375c0-.621-.503-1.125-1.125-1.125h-.871M7.5 18.75v-3.375c0-.621.504-1.125 1.125-1.125h.872m5.007 0H9.497m5.007 0a7.454 7.454 0 0 1-.982-3.172M9.497 14.25a7.454 7.454 0 0 0 .981-3.172M5.25 4.236c-.982.143-1.954.317-2.916.52A6.003 6.003 0 0 0 7.73 9.728M5.25 4.236V4.5c0 2.108.966 3.99 2.48 5.228M5.25 4.236V2.721C7.456 2.41 9.71 2.25 12 2.25c2.291 0 4.545.16 6.75.47v1.516M7.73 9.728a6.726 6.726 0 0 0 2.748 1.35m8.272-6.842V4.5c0 2.108-.966 3.99-2.48 5.228m2.48-5.492a46.32 46.32 0 0 1 2.916.52 6.003 6.003 0 0 1-5.395 4.972m0 0a6.726 6.726 0 0 1-2.749 1.35m0 0a6.772 6.772 0 0 1-3.044 0" />
          </svg>
          <div className="flex-1 min-w-0">
            <h2 className="text-base font-extrabold text-navy dark:text-amber">{copy.title}</h2>
            <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{copy.body}</p>
            <div className="mt-3 flex items-center gap-2 flex-wrap">
              <a
                href={`/profile?lang=${lang}#credly`}
                className="min-h-[44px] inline-flex items-center px-4 rounded-lg bg-amber text-white text-sm font-bold no-underline hover:bg-amber/90"
              >
                {copy.cta}
              </a>
              <button
                type="button"
                onClick={dismiss}
                className="min-h-[44px] px-4 rounded-lg border border-[var(--border-subtle)] text-[var(--text-secondary)] text-sm font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]"
              >
                {copy.dismiss}
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
