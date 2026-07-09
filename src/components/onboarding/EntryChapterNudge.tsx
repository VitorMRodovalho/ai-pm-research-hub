import { useState, useEffect, useCallback } from 'react';

// Entry-chapter nudge — #1224 PR2 (bucket-aware) on top of #625 / ADR-0104 Wave 3b-i.
//
// The /profile entry-chapter CARD lets a member choose the chapter they enter the Núcleo
// through (set_my_entry_chapter). This island PULLS the member to the right action from a
// dismissible banner on /workspace. It renders one of two families of message:
//
//   1. PMI-side diagnosis (#1224): get_my_entry_chapter_diagnosis() classifies the caller's
//      selection application against the PMI enrichment (SSOT — pmi_memberships, never free
//      text). When the entry chapter still cannot be derived, the bucket tells the member
//      exactly what to fix on their community.pmi.org profile:
//        - profile_private → make the PMI profile public
//        - no_fetch        → create / link the PMI profile
//        - not_affiliated  → regularize PMI membership
//      For these the action is on PMI's site, so the CTA opens community.pmi.org.
//
//   2. Choice fallback (#625): when the diagnosis is not one of the PMI-side buckets and no
//      entry chapter is set yet, we fall back to the affiliation-based prompt (the member has
//      >= 1 BR chapter affiliation but has not chosen which one is the entry chapter — e.g. an
//      established member, or an ambiguous cohort member who has not self-declared). CTA links
//      straight to the /profile choice card.
//
// Once entry_chapter_code is set the banner disappears on its own (diagnosis short-circuits and
// the affiliation check finds is_entry). Dismissal is a per-device localStorage flag with a
// 14-day TTL — a fat-finger dismiss must not silence a governance nudge forever (ux-leader R2).

const DISMISS_KEY = 'nucleo:entryChapterNudgeDismissed';
const DISMISS_TTL_MS = 14 * 24 * 60 * 60 * 1000;

// PMI community site — where profile visibility / membership are fixed.
const PMI_COMMUNITY_URL = 'https://community.pmi.org';

interface Affiliation {
  chapter_code: string;
  is_entry: boolean;
}

interface Diagnosis {
  bucket: string;
  active_br_codes: string[];
  entry_chapter_code: string | null;
  member_chapter: string | null;
}

// Which diagnosis buckets need a PMI-side fix (CTA → community.pmi.org).
type PmiVariant = 'profile_private' | 'no_fetch' | 'not_affiliated';
const PMI_BUCKETS: readonly PmiVariant[] = ['profile_private', 'no_fetch', 'not_affiliated'];

type Variant = PmiVariant | 'choose';

interface Message {
  title: string;
  body: string;
  cta: string;
}

interface Copy {
  dismiss: string;
  ariaLabel: string;
  variants: Record<Variant, Message>;
}

const COPY: Record<string, Copy> = {
  'pt-BR': {
    dismiss: 'Agora não',
    ariaLabel: 'Aviso sobre seu capítulo de entrada',
    variants: {
      choose: {
        title: 'Defina seu capítulo de entrada',
        body: 'Escolha por qual capítulo do PMI você entra no Núcleo. Leva um clique e ajuda na governança e nos indicadores do seu capítulo.',
        cta: 'Escolher meu capítulo',
      },
      profile_private: {
        title: 'Deixe seu perfil PMI público',
        body: 'Seu perfil no community.pmi.org está privado, então não conseguimos ler seus capítulos para definir seu capítulo de entrada. Deixe o perfil público e nós atualizamos automaticamente.',
        cta: 'Abrir meu perfil PMI',
      },
      no_fetch: {
        title: 'Vincule seu perfil PMI',
        body: 'Ainda não localizamos seu perfil no community.pmi.org. Se você tem filiação PMI, confira se o perfil está criado e público para confirmarmos seu capítulo de entrada automaticamente.',
        cta: 'Abrir community.pmi.org',
      },
      not_affiliated: {
        title: 'Confirme sua filiação PMI',
        body: 'Não conseguimos confirmar uma filiação PMI ativa no seu perfil do community.pmi.org. Verifique se sua filiação está ativa e se o capítulo aparece no perfil. Assim que estiver regular, atualizamos automaticamente.',
        cta: 'Abrir meu perfil PMI',
      },
    },
  },
  'en-US': {
    dismiss: 'Not now',
    ariaLabel: 'Notice about your entry chapter',
    variants: {
      choose: {
        title: 'Set your entry chapter',
        body: 'Pick which PMI chapter you join the Núcleo through. It takes one click and supports your chapter’s governance and metrics.',
        cta: 'Choose my chapter',
      },
      profile_private: {
        title: 'Make your PMI profile public',
        body: 'Your community.pmi.org profile is private, so we cannot read your chapters to set your entry chapter. Make the profile public and we update it automatically.',
        cta: 'Open my PMI profile',
      },
      no_fetch: {
        title: 'Link your PMI profile',
        body: 'We could not find your community.pmi.org profile yet. If you hold a PMI membership, check that the profile is created and public so we can confirm your entry chapter automatically.',
        cta: 'Open community.pmi.org',
      },
      not_affiliated: {
        title: 'Confirm your PMI membership',
        body: 'We could not confirm an active PMI membership on your community.pmi.org profile. Check that your membership is active and the chapter shows on the profile. Once it is current, we update automatically.',
        cta: 'Open my PMI profile',
      },
    },
  },
  'es-LATAM': {
    dismiss: 'Ahora no',
    ariaLabel: 'Aviso sobre tu capítulo de entrada',
    variants: {
      choose: {
        title: 'Define tu capítulo de entrada',
        body: 'Elige por cuál capítulo del PMI ingresas al Núcleo. Toma un clic y apoya la gobernanza y los indicadores de tu capítulo.',
        cta: 'Elegir mi capítulo',
      },
      profile_private: {
        title: 'Haz público tu perfil PMI',
        body: 'Tu perfil en community.pmi.org está privado, así que no podemos leer tus capítulos para definir tu capítulo de entrada. Hazlo público y lo actualizamos automáticamente.',
        cta: 'Abrir mi perfil PMI',
      },
      no_fetch: {
        title: 'Vincula tu perfil PMI',
        body: 'Todavía no localizamos tu perfil en community.pmi.org. Si tienes membresía PMI, verifica que el perfil esté creado y público para confirmar tu capítulo de entrada automáticamente.',
        cta: 'Abrir community.pmi.org',
      },
      not_affiliated: {
        title: 'Confirma tu membresía PMI',
        body: 'No pudimos confirmar una membresía PMI activa en tu perfil de community.pmi.org. Verifica que tu membresía esté activa y que el capítulo aparezca en el perfil. Cuando esté al día, lo actualizamos automáticamente.',
        cta: 'Abrir mi perfil PMI',
      },
    },
  },
};

interface Props {
  lang?: string;
}

export default function EntryChapterNudge({ lang = 'pt-BR' }: Props) {
  const copy = COPY[lang] || COPY['pt-BR'];
  const [variant, setVariant] = useState<Variant | null>(null);

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

    // 1. PMI-side diagnosis (SSOT = PMI enrichment). If the entry chapter is already set,
    //    nothing to nudge. If a PMI-side bucket, render its specific fix.
    const { data: diag } = await sb.rpc('get_my_entry_chapter_diagnosis');
    const d: Diagnosis | null = diag && typeof diag === 'object' ? diag : null;
    if (d?.entry_chapter_code) return;
    if (d && PMI_BUCKETS.includes(d.bucket as PmiVariant)) {
      setVariant(d.bucket as PmiVariant);
      return;
    }

    // 2. Choice fallback (#625): has BR affiliations but no entry chapter chosen yet.
    const { data, error } = await sb.rpc('get_my_chapter_affiliations');
    if (error) return;
    const affils: Affiliation[] = Array.isArray(data) ? data : [];
    if (affils.length === 0) return;
    if (affils.some((a) => a.is_entry === true)) return;
    setVariant('choose');
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
    setVariant(null);
  }, []);

  if (!variant) return null;

  const msg = copy.variants[variant];
  const isPmi = PMI_BUCKETS.includes(variant as PmiVariant);
  const ctaHref = isPmi ? PMI_COMMUNITY_URL : `/profile?lang=${lang}#entry-chapter-card`;
  // PMI-side CTA leaves the platform → new tab + noopener; internal choice stays in place.
  const ctaExtra = isPmi ? { target: '_blank', rel: 'noopener noreferrer' } : {};

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
            <h2 className="text-base font-extrabold text-navy dark:text-teal">{msg.title}</h2>
            <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{msg.body}</p>
            <div className="mt-3 flex items-center gap-2 flex-wrap">
              <a
                href={ctaHref}
                {...ctaExtra}
                className="min-h-[44px] inline-flex items-center px-4 rounded-lg bg-teal text-white text-sm font-bold no-underline hover:bg-teal/90"
              >
                {msg.cta}
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
