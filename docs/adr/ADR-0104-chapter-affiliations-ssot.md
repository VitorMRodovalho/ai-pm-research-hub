# ADR-0104: Chapter Affiliations — Single Source of Truth

| Field | Value |
|---|---|
| Status | Accepted (Wave 3a-0 lands the display + this direction; durable model lands in Wave 3a/3b) |
| Date | 2026-06-16 |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | 20260805000189_w3a0_get_selection_dashboard_pmi_memberships.sql (surface step; durable model migrations land in Wave 3a) |
| Cross-ref | [ADR-0006](./ADR-0006-persons-engagements-identity.md) · [ADR-0009](./ADR-0009-initiative-types-as-config.md) · [ADR-0012](./ADR-0012-schema-consolidation-principles.md) |
| Refs | Issue #740 (pre-onboarding journey) Wave 3 |

## Context

A member's PMI chapter is represented in **four inconsistent ways** today, none of
which is canonical, and they contradict each other. For the same applicant (the
Henrique Diniz case raised by the PM — a Pernambuco member):

1. **`selection_applications.pmi_memberships`** (jsonb) — the COMPLETE, reliable
   multi-chapter snapshot taken by the `pmi-vep-sync` worker (e.g. `["PMI Global",
   "Distrito Federal, Brazil Chapter", "Pernambuco, Brazil Chapter", "Bahia, Brazil
   Chapter", ...]`). The worker double-encoding bug that once left this NULL was fixed
   (`script-mapper.ts:78`), so the array is now trustworthy. **It was populated but
   ignored by the headline display.**
2. **`selection_applications.chapter`** (text) — a single COLLAPSED value (e.g.
   `PMI-DF`) backfilled by a p87 regex over free-text; lossy and arbitrary.
3. **`pmi_canonical.chapter_canonical`** — NOT a column. It is computed on read inside
   `get_selection_dashboard` as the **first non-"PMI Global" token of the free-text
   `service_history_chapters` string**. Order-dependent and arbitrary: for the
   Pernambuco member above, `service_history_chapters` happens to list "Goiás, Brazil
   Chapter" first, so the column displayed **PMI-GO** — demonstrably wrong.
4. **`members.chapter` / `member_affiliation_verifications.chapter_verified`** — yet
   another single value on the member side.

Without a canonical source, every report and admin panel silently picks one of these
and they disagree.

## Decision

### Target SSOT (durable model — Wave 3a/3b)

Two canonical sources, separating **fact** from **governance choice**:

- **`member_chapter_affiliations`** (N:N, FACT) — one row per chapter the member is
  affiliated with, fed from the reliable `pmi_memberships` snapshot. This is the truth
  about *which chapters a member belongs to* (multi-valued). A `z_archive`-only table
  of the same name exists from an abandoned earlier attempt with a different shape; the
  Wave 3a table is a fresh `public` relation (`person_id` FK, `chapter_code` FK
  `chapter_registry`, `source`, `is_primary`, RLS-enabled, no anon access — LGPD).
- **`members.entry_chapter_code`** (single, GOVERNANCE) — the member's **explicit,
  self-chosen chapter of entry** into the Núcleo, restricted to participating **BR**
  chapters. This is the headline value once it exists. It is a *choice*, not derived
  from the affiliation list.
- **`members.chapter`** becomes a compat/derived value
  (`COALESCE(entry_chapter_code "PMI-prefixed", primary affiliation)`); reports
  reference `entry_chapter_code`, not the free-text duplicate.

### What is retired

- **`chapter_canonical` is retired as the authoritative display.** It is no longer
  treated as a verified "✓ canonical from PMI" value anywhere in the UI. The key
  remains in the `get_selection_dashboard` payload for backward compatibility (and as a
  weak service-history hint), but the frontend no longer reads it as the headline.
- The "first-token-of-service_history" heuristic is recognized as **arbitrary** and is
  never used to claim a member's chapter.

### Wave 3a-0 (this step — display + direction, no new tables)

To stop the wrong display **now**, without waiting for the durable model:

- `get_selection_dashboard` surfaces one additive key
  `pmi_canonical.pmi_memberships` (the reliable snapshot array) per application
  (migration `20260805000189`). Additive jsonb key — no signature change, no-op for
  existing consumers.
- `/admin/selection` (list + modal) now derives the chapter display from
  `pmi_memberships`:
  - **BR affiliations** (names ending in `", Brazil Chapter"`, robust even where the
    name→code map lacks an entry) are mapped to `PMI-XX` codes and shown as a list.
  - **Headline** = the form-declared `chapter` *when it is one of the real
    affiliations*, else the first BR affiliation. (Once `entry_chapter_code` exists in
    Wave 3a, it becomes the headline.)
  - **Form-declared** values are labelled "declared, unverified" and **never** endorsed
    as canonical; a divergence badge (⚠) marks a form value absent from the real
    affiliations.
  - **Non-BR affiliations** (Angola, Portugal, etc.) are surfaced but flagged as
    "outside Brazil (not eligible for entry)" (I7), not silently dropped.

## Consequences

- The Henrique case now displays his real BR affiliations (DF · PE · BA · RJ · SP ·
  Sergipe) with the form value marked, instead of an arbitrary "PMI-GO".
- The chapter→code map gains the missing `Sergipe, Brazil Chapter → PMI-SE` entry
  (grounded against the live distinct set of `pmi_memberships` tokens).
- This ADR is the home for the chapter-SSOT decision; Wave 3a/3b amend it as the
  durable table + `entry_chapter_code` + the `sign_volunteer_agreement` PMI-GO-explicit
  signatory (C3) land. Do not create a competing ADR.
- `member_status`-style derivations and `get_chapter_*` read-sites are repointed to the
  canonical sources in Wave 3a (out of scope for 3a-0).
