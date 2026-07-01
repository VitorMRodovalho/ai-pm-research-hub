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
}

/** Normalize either membership shape to a { chapterName, expiryDate } object. */
function normalizeMembership(m: PmiMembershipEntry): PmiMembership {
  return typeof m === 'string' ? { chapterName: m, expiryDate: null } : m;
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
      const ts = m.expiryDate ? Date.parse(m.expiryDate) : NaN;
      let expired = false;
      let soon = false;
      if (!Number.isNaN(ts)) {
        const days = Math.ceil((ts - now) / 86400000);
        expired = days < 0;
        soon = days >= 0 && days <= 30;
      }
      return { name: short, expiry: m.expiryDate || null, expired, soon };
    });
}
