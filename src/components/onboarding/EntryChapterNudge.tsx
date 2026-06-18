import { useState, useEffect, useCallback } from 'react';

// Entry-chapter adoption nudge (#625 follow-up / ADR-0104 Wave 3b-i).
//
// The /profile entry-chapter CARD already exists (set_my_entry_chapter), but adoption among the
// established membership is 0/48 live (the screen is passive — you only see it if you go look).
// This island PULLS the member to it: a dismissible banner on /workspace that links straight to
// the card. PM decision 2026-06-18: FE-only, no new DB state.
//
// Eligibility mirrors what the /profile card itself can act on, so the nudge never dead-ends:
//   - non-guest, active member (guests have their own pre-onboarding flow + islands)
//   - get_my_chapter_affiliations() returns >= 1 BR affiliation (the RPC is BR-only)
//   - none of those affiliations is already the entry chapter (is_entry === false for all)
// Live grounding 2026-06-18: 48/48 eligible members have >= 1 BR affiliation → 0 dead-ends.
//
// Dismissal is a localStorage flag ("not now", per device) with a 14-day TTL — a fat-finger
// dismiss should not silence a 0/48-adoption governance nudge forever (ux-leader R2). Once an
// entry chapter is chosen, is_entry flips true on the next load and the banner disappears on its
// own regardless of the flag — dismiss is only for members who want to defer.

const DISMISS_KEY = 'nucleo:entryChapterNudgeDismissed';
const DISMISS_TTL_MS = 14 * 24 * 60 * 60 * 1000;

interface Affiliation {
  chapter_code: string;
  is_entry: boolean;
}

interface Copy {
  title: string;
  body: string;
  cta: string;
  dismiss: string;
  ariaLabel: string;
}

const COPY: Record<string, Copy> = {
  'pt-BR': {
    title: 'Defina seu capítulo de entrada',
    body: 'Escolha por qual capítulo do PMI você entra no Núcleo. Leva um clique e ajuda na governança e nos indicadores do seu capítulo.',
    cta: 'Escolher meu capítulo',
    dismiss: 'Agora não',
    ariaLabel: 'Aviso: defina seu capítulo de entrada',
  },
  'en-US': {
    title: 'Set your entry chapter',
    body: 'Pick which PMI chapter you join the Núcleo through. It takes one click and supports your chapter’s governance and metrics.',
    cta: 'Choose my chapter',
    dismiss: 'Not now',
    ariaLabel: 'Notice: set your entry chapter',
  },
  'es-LATAM': {
    title: 'Define tu capítulo de entrada',
    body: 'Elige por cuál capítulo del PMI ingresas al Núcleo. Toma un clic y apoya la gobernanza y los indicadores de tu capítulo.',
    cta: 'Elegir mi capítulo',
    dismiss: 'Ahora no',
    ariaLabel: 'Aviso: define tu capítulo de entrada',
  },
};

interface Props {
  lang?: string;
}

export default function EntryChapterNudge({ lang = 'pt-BR' }: Props) {
  const copy = COPY[lang] || COPY['pt-BR'];
  const [show, setShow] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const evaluate = useCallback(async () => {
    // Per-device "not now" with a 14-day TTL (older flag = re-nudge once).
    try {
      const raw = localStorage.getItem(DISMISS_KEY);
      if (raw) {
        const ts = Number(JSON.parse(raw)?.ts);
        if (Number.isFinite(ts) && Date.now() - ts < DISMISS_TTL_MS) return;
      }
    } catch { /* localStorage blocked / corrupt — proceed without the dismiss flag */ }

    const m = (window as any).navGetMember?.();
    // Guests have their own pre-onboarding flow; alumni/inactive are out of cohort.
    if (!m || m.operational_role === 'guest') return;
    if (m.member_status && m.member_status !== 'active') return;

    const sb = getSb();
    if (!sb) return;
    const { data, error } = await sb.rpc('get_my_chapter_affiliations');
    if (error) return;
    const affils: Affiliation[] = Array.isArray(data) ? data : [];
    // BR-only RPC. Eligible = has affiliations AND none is already the entry chapter.
    if (affils.length === 0) return;
    if (affils.some((a) => a.is_entry === true)) return;
    setShow(true);
  }, [getSb]);

  // Boot like the sibling islands: wait for the nav member, then evaluate once.
  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) evaluate();
      else setTimeout(boot, 500);
    };
    boot();
  }, [evaluate]);

  const dismiss = useCallback(() => {
    try { localStorage.setItem(DISMISS_KEY, JSON.stringify({ ts: Date.now() })); } catch { /* ignore */ }
    setShow(false);
  }, []);

  if (!show) return null;

  return (
    <section role="region" aria-label={copy.ariaLabel} className="mb-6">
      <div className="rounded-2xl border border-teal/40 bg-teal/5 p-5">
        <div className="flex items-start gap-3">
          {/* map-pin (heroicons) — consistent with the chapter context icon used elsewhere. */}
          <svg className="w-6 h-6 text-teal flex-shrink-0" fill="none" viewBox="0 0 24 24" strokeWidth="1.8" stroke="currentColor" aria-hidden="true">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
            <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1 1 15 0Z" />
          </svg>
          <div className="flex-1 min-w-0">
            <h2 className="text-base font-extrabold text-navy dark:text-teal">{copy.title}</h2>
            <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{copy.body}</p>
            <div className="mt-3 flex items-center gap-2 flex-wrap">
              <a
                href={`/profile?lang=${lang}#entry-chapter-card`}
                className="min-h-[44px] inline-flex items-center px-4 rounded-lg bg-teal text-white text-sm font-bold no-underline hover:bg-teal/90"
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
