// #1132 — Shared status "farol" (🔴🟡🟢) tokens.
//
// Single source of truth for the status→colour mapping that three admin screens
// were each reimplementing (and had already diverged):
//   - src/components/admin/AffiliationQueueIsland.tsx  (validity farol + term + VEP + cohort)
//   - src/components/admin/VepReconciliationIsland.tsx (NUCLEO_STATUS_COLOR + VEP_STATUS_COLOR)
//   - src/pages/admin/selection.astro                  (STATUS_GROUPS + STATUS_BADGE)
//
// Framework-agnostic (plain TS, no React) so it is importable from both the
// `.tsx` islands AND the bundled `<script>` in selection.astro. Colour is NEVER
// the sole channel — callers keep the emoji + text label (WCAG). This module
// owns only the palette + status→tone maps, not the wording (see #1133 for i18n).
//
// Rule: smart code, no hardcode, reuse centralized libs
// (feedback-smart-code-no-hardcode-reuse-centralized). Guarded by
// tests/contracts/1132-status-farol-ssot.test.mjs (the three screens must derive
// their palettes from here, not redefine local colour maps).

/** Semantic tone → the one Tailwind class pair that renders it everywhere. */
export type StatusTone =
  | 'neutral'   // not started / informational-neutral
  | 'info'      // in progress, early stage (screening / evaluation)
  | 'attention' // needs a human step soon (interview stage)
  | 'noshow'    // missed / no-show
  | 'warn'      // caution / expiring / offer extended / waitlist
  | 'decision'  // under final decision
  | 'positive'  // approved / active / verified / valid
  | 'negative'  // terminal-negative (rejected / withdrawn / expired / inactive)
  | 'cohort'    // current-selection cohort
  | 'muted'     // unknown / unverified / none
  | 'mutedInk'; // non-selection cohort (slightly darker muted ink)

/** The palette. Change a colour here and all three screens move together. */
export const TONE_BADGE: Record<StatusTone, { bg: string; text: string }> = {
  neutral:   { bg: 'bg-gray-100',    text: 'text-gray-700' },
  info:      { bg: 'bg-blue-50',     text: 'text-blue-700' },
  attention: { bg: 'bg-yellow-50',   text: 'text-yellow-700' },
  noshow:    { bg: 'bg-orange-50',   text: 'text-orange-700' },
  warn:      { bg: 'bg-amber-50',    text: 'text-amber-700' },
  decision:  { bg: 'bg-indigo-50',   text: 'text-indigo-700' },
  positive:  { bg: 'bg-emerald-50',  text: 'text-emerald-700' },
  negative:  { bg: 'bg-red-50',      text: 'text-red-700' },
  cohort:    { bg: 'bg-teal-50',     text: 'text-teal-700' },
  muted:     { bg: 'bg-slate-100',   text: 'text-slate-500' },
  mutedInk:  { bg: 'bg-slate-100',   text: 'text-slate-600' },
};

/** `"bg-… text-…"` for a tone — the shape most callers want. */
export function toneClasses(tone: StatusTone): string {
  const b = TONE_BADGE[tone];
  return `${b.bg} ${b.text}`;
}

// ── Selection-application status (Núcleo side) ───────────────────────────────
// Canonical map. Previously duplicated in selection.astro STATUS_BADGE and
// VepReconciliationIsland NUCLEO_STATUS_COLOR, which had diverged:
//   - final_eval was indigo in selection.astro but purple in VepReconciliation → indigo (canonical);
//   - cancelled was neutral-gray in VepReconciliation but red in selection.astro → negative (it is terminal).
export const SELECTION_STATUS_TONE: Record<string, StatusTone> = {
  submitted:           'neutral',
  screening:           'info',
  objective_eval:      'info',
  objective_cutoff:    'info',
  interview_pending:   'attention',
  interview_scheduled: 'attention',
  interview_done:      'attention',
  interview_noshow:    'noshow',
  final_eval:          'decision',
  approved:            'positive',
  converted:           'positive',
  rejected:            'negative',
  cancelled:           'negative',
  withdrawn:           'negative',
  waitlist:            'warn',
};

// ── VEP raw status ───────────────────────────────────────────────────────────
// Canonical map. Previously in VepReconciliationIsland VEP_STATUS_COLOR (with a
// heavier -100 shade) and AffiliationQueueIsland VEP_CLS (a -50 subset). Unified
// to the -50 family so a VEP badge reads the same on both screens.
export const VEP_STATUS_TONE: Record<string, StatusTone> = {
  Submitted:        'info',
  OfferExtended:    'warn',
  Active:           'positive',
  Withdrawn:        'negative',
  Declined:         'negative',
  OfferNotExtended: 'negative',
  OfferExpired:     'negative',
  Complete:         'neutral',
};

// ── Validity farol (filiação / termo de voluntário) ──────────────────────────
/** The 🔴🟡🟢⚪ traffic light. `expiring`/`valid` alias `soon`/`ok` for the term badge. */
export type ValidityKey = 'expired' | 'soon' | 'expiring' | 'ok' | 'valid' | 'unverified' | 'none';

export const VALIDITY_FAROL: Record<ValidityKey, { emoji: string; tone: StatusTone }> = {
  expired:    { emoji: '🔴', tone: 'negative' },
  soon:       { emoji: '🟡', tone: 'warn' },
  expiring:   { emoji: '🟡', tone: 'warn' },
  ok:         { emoji: '🟢', tone: 'positive' },
  valid:      { emoji: '🟢', tone: 'positive' },
  unverified: { emoji: '⚪', tone: 'muted' },
  none:       { emoji: '⚪', tone: 'muted' },
};

/** `{ emoji, cls }` for a validity key, colour + emoji from the single source. */
export function validityFarol(key: ValidityKey): { emoji: string; cls: string } {
  const f = VALIDITY_FAROL[key];
  return { emoji: f.emoji, cls: toneClasses(f.tone) };
}

// ── Cohort class (#1129) ─────────────────────────────────────────────────────
export type CohortClass = 'current_selection' | 'carryover' | 'non_selection';

export const COHORT_TONE: Record<CohortClass, StatusTone> = {
  current_selection: 'cohort',
  carryover:         'decision',
  non_selection:     'mutedInk',
};

// ── Selection status-group buckets (selection.astro STATUS_GROUPS) ────────────
export const GROUP_TONE: Record<string, StatusTone> = {
  submitted:  'neutral',
  evaluation: 'info',
  interview:  'attention',
  approved:   'positive',
  rejected:   'negative',
};
