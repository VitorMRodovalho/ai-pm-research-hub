// src/lib/affiliation-chapters.ts
// #659 affiliation queue — BR-chapter parsing from the PMI VEP `pmi_memberships` list.
//
// #995: `pmi_memberships` arrives in TWO shapes and the queue must tolerate BOTH:
//   - plain strings ("<State>, Brazil Chapter") — the VEP worker's "member history strings"
//     form (cloudflare-workers/pmi-vep-sync/src/script-mapper.ts), which has NO expiry; and
//   - enriched objects { chapterName, expiryDate }.
// The VEP worker itself is already string-tolerant (cloudflare-workers/pmi-vep-sync/src/db.ts:
// `typeof m === 'string' ? m : m.chapterName`), but the Filiação queue parser was not — it
// filtered on `m?.chapterName`, so string[] memberships produced an empty result and every
// enriched member fell through to the "verificar manualmente" warning (45/82 live, 2026-07-01).
// Extracted from AffiliationQueueIsland.tsx so the parsing is unit-testable.

export interface PmiMembership {
  chapterName: string;
  expiryDate?: string | null;
}

/** A membership entry may be a plain string OR an enriched object (see #995). */
export type PmiMembershipEntry = string | PmiMembership;

export interface BrChapter {
  name: string;
  expiry: string | null;
  expired: boolean;
  soon: boolean;
  /** #1192 — registry chapter_code when the entry came from the SSOT read-through */
  code?: string;
  /** #1192 — true when the entry is an SSOT row with verified_at (not a raw parse) */
  verified?: boolean;
  /** original PMI membership chapterName (modal prefill fidelity) */
  raw?: string | null;
}

/**
 * #1192 — one SSOT read-through entry from get_affiliation_verification_queue's
 * 'chapter_affiliations' (member_chapter_affiliations × chapter_registry, resolved
 * server-side by resolve_br_chapter_code — the ONE resolver; the client never
 * re-parses names to decide anything). source='vep_raw' marks a raw membership name
 * that resolves via the registry but has no SSOT row yet (provisional).
 */
export interface ChapterAffiliation {
  chapter_code: string;
  chapter_label: string;
  source: string;
  verified_at: string | null;
  is_primary: boolean;
  raw_name: string | null;
  expiry: string | null;
}

/** Normalize either membership shape to a { chapterName, expiryDate } object. */
function normalizeMembership(m: PmiMembershipEntry): PmiMembership {
  return typeof m === 'string' ? { chapterName: m, expiryDate: null } : m;
}

/** expired / soon(≤30d) window for a raw PMI expiry string; both false when unparseable. */
function expiryFlags(expiry: string | null | undefined, now: number): { expired: boolean; soon: boolean } {
  const ts = expiry ? Date.parse(expiry) : NaN;
  if (Number.isNaN(ts)) return { expired: false, soon: false };
  const days = Math.ceil((ts - now) / 86400000);
  return { expired: days < 0, soon: days >= 0 && days <= 30 };
}

/**
 * BR-chapter detail from the PMI VEP membership list (the federated gate: "filiado a um
 * capítulo BR EM DIA"). Returns one entry per `*, Brazil Chapter` membership with parsed
 * expiry state. Tolerant of the string and object forms (#995).
 *
 * `now` is injectable so the expired/soon window is deterministic under test.
 */
export function brChapters(
  memberships: PmiMembershipEntry[] | null | undefined,
  now: number = Date.now(),
): BrChapter[] {
  if (!Array.isArray(memberships)) return [];
  return memberships
    .map(normalizeMembership)
    .filter((m) => typeof m?.chapterName === 'string' && /brazil chapter/i.test(m.chapterName))
    .map((m) => {
      const short = m.chapterName.replace(/,?\s*Brazil Chapter$/i, '').trim();
      const { expired, soon } = expiryFlags(m.expiryDate, now);
      return { name: short, expiry: m.expiryDate || null, expired, soon, raw: m.chapterName };
    });
}

/**
 * #1192 — the member's BR chapters for display/filtering, SSOT-first: when the queue RPC
 * delivered chapter_affiliations (read-through of member_chapter_affiliations, resolved by
 * resolve_br_chapter_code server-side), those win — this is what fixes "Amazônia Chapter"
 * (registry alias, no "Brazil Chapter" suffix) falling into the amber "verificar
 * manualmente" branch. The raw brChapters() parse remains ONLY as display fallback for a
 * row with no resolvable data on either side; it never overrides the SSOT.
 */
export function unifiedBrChapters(
  affiliations: ChapterAffiliation[] | null | undefined,
  memberships: PmiMembershipEntry[] | null | undefined,
  now: number = Date.now(),
): BrChapter[] {
  if (Array.isArray(affiliations) && affiliations.length > 0) {
    return affiliations.map((a) => {
      const { expired, soon } = expiryFlags(a.expiry, now);
      return {
        name: a.chapter_label,
        code: a.chapter_code,
        verified: a.source !== 'vep_raw' && !!a.verified_at,
        expiry: a.expiry || null,
        expired,
        soon,
        raw: a.raw_name || null,
      };
    });
  }
  return brChapters(memberships, now);
}

export type ExpiryStatus = 'expired' | 'soon' | 'ok' | 'none';

export interface ExpirySummary {
  /** raw PMI expiry string of the SOONEST-expiring BR chapter (e.g. "31 Oct 2026") */
  expiry: string | null;
  /** whole days until that expiry (negative = already expired); null when no dated BR chapter */
  days: number | null;
  expired: boolean;
  /** within the 30-day renewal window (and not yet expired) */
  soon: boolean;
  status: ExpiryStatus;
}

/**
 * #1041 — collapse a member's BR-chapter memberships into ONE triage summary: the
 * SOONEST-expiring dated BR chapter (the most urgent renewal). Powers the sortable
 * "Vencimento" column + the provisional (VEP-derived) verification farol. `status='none'`
 * when the member has no BR chapter carrying a parseable expiry.
 */
export function soonestBrExpiry(
  memberships: PmiMembershipEntry[] | null | undefined,
  now: number = Date.now(),
): ExpirySummary {
  return summarizeSoonest(brChapters(memberships, now), now);
}

/**
 * #1192 — soonest-expiry triage over the SSOT-first unified chapter list, so an
 * alias-resolved affiliation (e.g. AM via "Amazônia Chapter") feeds the Vencimento column
 * and the provisional farol exactly like a "<State>, Brazil Chapter" one.
 */
export function soonestChapterExpiry(
  affiliations: ChapterAffiliation[] | null | undefined,
  memberships: PmiMembershipEntry[] | null | undefined,
  now: number = Date.now(),
): ExpirySummary {
  return summarizeSoonest(unifiedBrChapters(affiliations, memberships, now), now);
}

function summarizeSoonest(chapters: BrChapter[], now: number): ExpirySummary {
  let best: string | null = null;
  let bestTs = Infinity;
  for (const c of chapters) {
    if (!c.expiry) continue;
    const ts = Date.parse(c.expiry);
    if (!Number.isNaN(ts) && ts < bestTs) { bestTs = ts; best = c.expiry; }
  }
  if (best === null) return { expiry: null, days: null, expired: false, soon: false, status: 'none' };
  const days = Math.ceil((bestTs - now) / 86400000);
  const expired = days < 0;
  const soon = !expired && days <= 30;
  return { expiry: best, days, expired, soon, status: expired ? 'expired' : soon ? 'soon' : 'ok' };
}
