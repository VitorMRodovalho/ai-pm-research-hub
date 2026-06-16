import { useState, useEffect, useCallback } from 'react';
import { isRegisteredMember, getMemberRole } from '../../lib/routing';

// A1 #740 — route pre-onboarding members to the single /workspace cockpit.
// Pre-onboarding members carry operational_role='guest' (see routing.js) and
// otherwise land on the marketing home with no path to their checklist.
// Decision (PM 2026-06-16): "both" — redirect on first access, sticky banner
// thereafter. "First access" is tracked per-device via localStorage (Wave 1
// avoids a migration); a returning member sees a gentle, dismissible banner.

interface Props { lang?: string }

const SEEN_KEY = 'nucleo_cockpit_seen';
const DISMISS_KEY = 'nucleo_cockpit_nudge_dismissed';

const L: Record<string, { msg: string; cta: string; steps: string }> = {
  'pt-BR':    { msg: 'Você tem seu onboarding pendente.', cta: 'Continuar onboarding →', steps: 'passos' },
  'en-US':    { msg: 'You have onboarding to finish.',    cta: 'Continue onboarding →',   steps: 'steps' },
  'es-LATAM': { msg: 'Tienes tu integración pendiente.',  cta: 'Continuar integración →', steps: 'pasos' },
};

export default function OnboardingCockpitNudge({ lang = 'pt-BR' }: Props) {
  const l = L[lang] || L['pt-BR'];
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const workspaceUrl = `${lp}/workspace`;
  const [show, setShow] = useState(false);
  const [progress, setProgress] = useState<{ completed: number; total: number } | null>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const act = useCallback((m: any) => {
    // Only pre-onboarding (guest) registered members are nudged. Visitors and
    // already-promoted members (who see the checklist inside /workspace) are not.
    if (!isRegisteredMember(m) || getMemberRole(m) !== 'guest') return;

    let seen: string | null = null;
    try { seen = localStorage.getItem(SEEN_KEY); } catch { /* blocked */ }
    if (!seen) { try { seen = sessionStorage.getItem(SEEN_KEY); } catch { /* blocked */ } }
    if (!seen) {
      // First access post-approval → take them straight to the cockpit. Persist
      // the "seen" flag so the next visit nudges with a banner (not a redirect);
      // fall back to sessionStorage when localStorage is blocked (enterprise
      // policy) so a storage-blocked guest is not redirected on every home view.
      let stored = false;
      try { localStorage.setItem(SEEN_KEY, '1'); stored = true; } catch { /* blocked */ }
      if (!stored) { try { sessionStorage.setItem(SEEN_KEY, '1'); } catch { /* blocked */ } }
      window.location.href = workspaceUrl;
      return;
    }
    // Returning visit → gentle sticky banner (unless dismissed this session).
    let dismissed: string | null = null;
    try { dismissed = sessionStorage.getItem(DISMISS_KEY); } catch { /* ignore */ }
    if (dismissed) return;
    setShow(true);
    // Best-effort progress for the banner (non-blocking; banner shows regardless).
    const sb = getSb();
    sb?.rpc('get_candidate_onboarding_progress').then((res: any) => {
      const p = res?.data?.pre_onboarding;
      if (p && typeof p.total === 'number') setProgress({ completed: p.completed || 0, total: p.total });
    }).catch(() => { /* ignore */ });
  }, [getSb, workspaceUrl]);

  useEffect(() => {
    const existing = (window as any).navGetMember?.();
    if (existing) { act(existing); return; }
    // Nav not resolved yet (or visitor) — catch the member when it loads.
    // Visitors never fire nav:member, so the listener simply never runs.
    const onMember = (evt: Event) => act((evt as CustomEvent).detail);
    window.addEventListener('nav:member', onMember as EventListener, { once: true });
    return () => window.removeEventListener('nav:member', onMember as EventListener);
  }, [act]);

  if (!show) return null;

  const dismiss = () => {
    try { sessionStorage.setItem(DISMISS_KEY, '1'); } catch { /* ignore */ }
    setShow(false);
  };

  return (
    <div className="sticky top-14 z-[150] bg-gradient-to-r from-teal/95 to-blue-600/95 backdrop-blur text-white shadow-md">
      <div className="max-w-5xl mx-auto px-4 py-2.5 flex items-center gap-3">
        <span className="text-lg flex-shrink-0">📋</span>
        <div className="flex-1 min-w-0 text-[13px] font-semibold">
          {l.msg}
          {progress && (
            <span className="ml-2 font-normal opacity-90">· {progress.completed}/{progress.total} {l.steps}</span>
          )}
        </div>
        <a href={workspaceUrl}
          className="flex-shrink-0 px-3 py-1.5 rounded-lg bg-white text-teal text-[12px] font-bold no-underline hover:bg-white/90 transition-colors">
          {l.cta}
        </a>
        <button onClick={dismiss} aria-label="Dismiss"
          className="flex-shrink-0 text-white/80 hover:text-white bg-transparent border-0 cursor-pointer text-base leading-none">✕</button>
      </div>
    </div>
  );
}
