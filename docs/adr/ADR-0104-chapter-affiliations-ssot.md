# ADR-0104: Chapter Affiliations — Single Source of Truth

| Field | Value |
|---|---|
| Status | Accepted (Wave 3a-0 display + 3a DB foundation + 3a-ii C3 + 3a-iii worker + 3b-i entry-chapter choice + 3b-ii members.chapter derivation/invariant U shipped; 3c B8 signature cycle pending) |
| Date | 2026-06-16 |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | 20260805000189_w3a0_get_selection_dashboard_pmi_memberships.sql (3a-0 surface) · 20260805000190_w3a_member_chapter_affiliations_model.sql (3a DB foundation) · 20260805000191_w3a_c3_explicit_contracting_chapter_signatory.sql (3a-ii C3) · 20260805000193_w3a_iii_upsert_chapter_affiliation_rpc.sql (3a-iii worker write path) · 20260805000194_w3b_i_set_my_entry_chapter.sql (3b-i entry-chapter choice) · 20260805000195_w3b_ii_members_chapter_derivation.sql (3b-ii members.chapter derived + invariant U) |
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

## Amendment — Wave 3a (DB foundation) delivered (2026-06-16, mig `20260805000190`)

The durable model's **schema + backfill** landed (additive, zero behavior change to
existing reads):

- **`public.member_chapter_affiliations`** created (N:N FACT): `(id, person_id FK
  persons ON DELETE CASCADE, chapter_code FK chapter_registry, source CHECK
  in (pmi_vep|admin_import|self_declared|legacy), is_primary, verified_at,
  created_at, updated_at, UNIQUE(person_id, chapter_code))`. Keyed on `person_id`
  (ADR-0006 identity primitive), not `member_id`. Partial unique index enforces one
  primary per person. RLS: `rpc_only_deny_all` (USING false) + anon SELECT revoked —
  reachable only by SECDEF RPCs + the worker (service_role), mirroring `member_emails`
  (ADR-0095). The empty `z_archive.member_chapter_affiliations` predecessor (different
  shape, 0 rows) was left untouched — no collision.
- **`members.entry_chapter_code`** added: FK `chapter_registry` ON DELETE SET NULL,
  nullable, **NULL for everyone initially** (no one has chosen). BR-only enforcement +
  the choice UI land in Wave 3b's `set_my_entry_chapter`. `members.chapter` is **not yet
  repointed** to a derived value — kept as the legacy/compat value to keep this step
  additive.
- **`chapter_registry`** seeded with 8 BR chapters present in live data (PE/PR/RJ/SP/BA/
  ES/SC/SE → 13 BR total). GO remains the **only** `is_contracting_chapter`. legal_name/
  CNPJ for non-contracting chapters are informational (only GO signs).
- **Backfill**: 72 of 73 active members got a `source='legacy'`, `is_primary=true`
  affiliation from `members.chapter` (stripped `PMI-`); the 1 `'Outro'` member was
  skipped (not a registry chapter). Verified live: 0 missing affiliations, one primary
  per person.

**Deferred to follow-on PRs (still Wave 3):** the multi-chapter population from the
reliable `pmi_memberships` snapshot is owned by the **pmi-vep-sync worker (3a-iii)**
(it already maps `"<State>, Brazil Chapter" → PMI-XX`, so the SQL backfill does not
duplicate that map); **C3** (`sign_volunteer_agreement` always PMI-GO signatory) is its
own PR (3a-ii, legal-sensitive); the FE entry-chapter choice + `get_chapter_*` repoint +
`members.chapter` becomes derived are **3b**.

### Prerequisites / contracts for the follow-on PRs (council Tier 1, this PR)

- **Worker one-primary upsert protocol (3a-iii) — MANDATORY.** The partial unique index
  `member_chapter_affiliations_one_primary_idx` forbids two `is_primary=true` rows for
  one `person_id`. A naive `INSERT ... ON CONFLICT (person_id, chapter_code) DO UPDATE
  SET is_primary=true` therefore **fails** when the person already has a *different*
  primary. The worker MUST do it in two steps inside one transaction:
  1. `UPDATE member_chapter_affiliations SET is_primary=false WHERE person_id=$p AND is_primary AND chapter_code <> $new_primary;`
  2. `INSERT ... ON CONFLICT (person_id, chapter_code) DO UPDATE SET is_primary=EXCLUDED.is_primary, source='pmi_vep', verified_at=now(), updated_at=now();`
  Encapsulate in a SECDEF RPC `upsert_chapter_affiliation(p_person_id, p_chapter_code, p_source, p_is_primary)` so the invariant lives in one place.
- **`updated_at` trigger (3a-iii).** No `_set_updated_at` trigger exists yet (the table
  has no UPDATEs in 3a-i). Add it before the worker starts issuing UPDATEs, else
  `updated_at` stays frozen at insert time.
- **`service_role` table grants (3a-iii).** Confirm the worker's `service_role` can
  INSERT/UPDATE (it bypasses RLS but still needs table privileges; default Supabase
  `GRANT ALL ... TO service_role` usually covers this — audit before relying on it).
- **Backfill scope = active members only (intentional).** Alumni/inactive members were
  NOT backfilled (the FACT table seeds from active members; the worker fills the rest as
  it syncs). Decide in 3b whether `members.chapter` derivation needs a primary
  affiliation for non-active members, or whether the legacy `members.chapter` value
  stays authoritative for them.
- **Deferred invariant `U_active_person_has_primary_chapter_affiliation` (3b).** Add to
  `check_schema_invariants()` when `members.chapter` becomes derived: every active
  member's `person_id` must have exactly one `is_primary=true` affiliation, else the
  COALESCE derivation breaks silently. The partial unique index enforces *at most one*;
  this invariant would enforce *exactly one* for active members.
- **RLS is the enforcement; table REVOKE is defense-in-depth.** Verified live: a
  `SET ROLE authenticated; SELECT ...` returns `permission denied`. NB: on the hosted
  Supabase DB, `information_schema.role_table_grants` may still *list* anon/authenticated
  grants (default-privilege artifacts) even though the effective privilege check denies
  access — trust the `SET ROLE` probe, not the catalog view.

## Amendment — Wave 3a-ii (C3) shipped (2026-06-16, mig `20260805000191`)

`sign_volunteer_agreement` now makes the contracting party + signatory **explicit**,
removing the dependency on the `'GO'` vs `'PMI-GO'` format accident. Reviewed by
**legal-counsel** (parecer 2026-06-16); only future certificates are affected (existing
`content_snapshot` + `signature_hash` are immutable — never retroactively rewritten).

- **R1 — contracting party = always the contracting chapter.** The brittle first lookup
  (`chapter_registry.chapter_code = v_member.chapter`, which never matched) is removed;
  the contracting party (`chapter_cnpj` / `chapter_name`) is selected directly
  `WHERE is_contracting_chapter = true` (PMI-GO). Emergency hardcoded fallback kept but
  flagged.
- **R2 — issuer = contracting-chapter board (Opção A).** `issued_by` is now a board
  member of the contracting chapter (`chapter = 'PMI-' || contracting_code`), falling back
  to a manager — so the entity that contracts and the representative who signs are the same
  (CC/2002 arts. 115-120). Opção B (member-chapter board as delegate) was rejected: no
  delegation instrument exists in the cooperation agreements. `content_snapshot` gains
  `contracting_chapter` (PMI-GO), `issuer_chapter`, `issuer_authority_basis`
  (`contracting_chapter_board` | `manager_fallback`); the volunteer's chapter stays as
  `member_chapter` (indicator).
- **R3 — audit observability.** `admin_audit_log` records `chapter_cnpj_source`
  (`chapter_registry` | `hardcoded_emergency_fallback`) + `contracting_chapter`.
- **counter_sign_certificate — UNCHANGED.** It already gates a `chapter_board`
  counter-signer by `content_snapshot->>'contracting_chapter'` (with a member-chapter
  fallback). By now WRITING `contracting_chapter = PMI-GO` at signing, that gate correctly
  requires a PMI-GO board member (or any `manage_member` holder). Verified live: contracting
  party resolves to PMI-GO (CNPJ 06.065.645/0001-99); 6 PMI-GO board members exist for the
  issuer.
- **R4 — frontend confirmed.** `src/lib/certificates/pdf.ts` renders the term header from
  `content_snapshot.chapter_name`/`chapter_cnpj` (the contracting party), not the member's
  profile chapter — so the displayed and signed contracting party match. No FE change.
- **Red flag (carry):** C3 MUST precede any normalization of the `members.chapter` format
  (`'PMI-GO'` → `'GO'`); otherwise the removed lookup would have started matching and
  silently changed behavior.

## Amendment — Wave 3a-iii (worker write path) shipped (2026-06-16, mig `20260805000193`)

The deferred multi-chapter population now lands: the `pmi-vep-sync` worker writes
`member_chapter_affiliations` from the reliable `pmi_memberships` snapshot, through a
single-home upsert RPC. Additive — no behavior change to existing reads.

- **`upsert_chapter_affiliation(p_person_id, p_chapter_code, p_source, p_is_primary)`**
  (SECURITY DEFINER) is the **single home for the one-primary invariant**, resolving the
  council Tier-1 contract. Behaviour validated live (rolled-back probe at apply time):
  - `p_is_primary=true` → demotes any *other* primary first, then forces this one primary
    (the partial unique index forbids two primaries; used by Wave 3b / admin for an
    explicit choice).
  - `p_is_primary=false` (the worker's call) → asserts the FACT only and **never demotes
    an existing primary** (preserves the legacy backfill + the future `entry_chapter_code`
    choice). If the person has **no** primary at all, the row becomes a *provisional* FACT
    primary so the table is never left primary-less — a placeholder, not a headline claim
    (the displayed chapter is `entry_chapter_code`, Wave 3b). The worker deliberately does
    **not** assert a primary: ADR-0104 rejects array-order-based primary selection.
  - `source` is validated against the table CHECK; an invalid value raises.
  - **EXECUTE is granted to `service_role` only** (the worker) and revoked from
    `anon`/`authenticated` — the function can rewrite any person's affiliation, so exposing
    it to authenticated callers would be a privilege-escalation surface (mirrors the
    locked-table RPC pattern, ADR-0095). Verified live: a `SET ROLE authenticated` call
    returns `permission denied`.
- **`updated_at` trigger** added (`set_updated_at_v4()`), before the worker starts issuing
  UPDATEs — closes the contract item.
- **`service_role` table grants** confirmed present (INSERT/UPDATE/SELECT/DELETE) — the
  worker can write.
- **Worker** (`pmi-vep-sync`): a new `parseBrChapterCode(name)` (mapper.ts) maps a single
  `"<State>, Brazil Chapter"` membership to the bare registry code (BR-suffix-gated,
  BR-only), reusing the existing state→`PMI-XX` map (with **Sergipe** added for registry
  parity — it was in the 3a-0 FE map but missing from the worker). `upsertChapterAffiliations`
  (db.ts) dedupes BR codes from the snapshot and calls the RPC with `is_primary=false`. The
  call is wired into the resolved-`person_id` Phase B slot (where the retired #441
  `pmi_chapter_memberships` UPSERT used to be); non-BR tokens (`PMI Global`, `Washington, DC
  Chapter`, Angola) are skipped (chapter_registry is BR-only). Tolerates the **real runtime
  shape** (an array of plain name strings, as actually stored) as well as the declared
  `{ chapterName }` object shape. Idempotent; per-app failures are caught and logged
  (`scope: 'chapter_affiliations'`), counted in the run summary
  (`chapter_affiliations_upserted`).

**Still deferred to Wave 3b:** the FE entry-chapter choice (`set_my_entry_chapter`, BR-only,
must be one of the member's affiliations), `members.chapter` becomes derived
(`COALESCE(entry_chapter, primary affiliation)`), `get_chapter_*` repoint, `lib/chapters.ts`
(drop the hardcoded fallback), and the deferred invariant
`U_active_person_has_primary_chapter_affiliation` (the provisional-primary logic above already
reduces how many actives could be primary-less).

## Amendment — Wave 3b-i (member-facing entry-chapter choice) shipped (2026-06-16, mig `20260805000194`)

The member can now **choose their entry chapter** on `/perfil`. Additive; no behavior
change to existing reads (`members.chapter` stays the legacy/compat value — its derivation
is 3b-ii).

- **`set_my_entry_chapter(p_chapter_code)`** (SECDEF, authenticated, self-scoped via
  `auth.uid()` → `members`). **PM decision (2026-06-16): restricted to a chapter the member
  is already affiliated with** (`member_chapter_affiliations`) — you enter via a chapter you
  belong to, never an arbitrary one. Validates BR + active; raises on non-BR / unknown /
  not-affiliated. **Preserves the affiliation's existing `source`** (a verified `pmi_vep`
  fact is not relabelled `self_declared`) and promotes it to the one primary through
  `upsert_chapter_affiliation(..., is_primary=true)` — keeping the FACT primary aligned with
  the governance choice (and the deferred invariant `U_active_person_has_primary`). Stores
  the bare code on `members.entry_chapter_code`. Behaviour validated live (rolled-back probe):
  demote-then-promote, source preservation, restriction + unknown raise, anon denied,
  authenticated allowed.
- **`get_my_chapter_affiliations()`** (SECDEF, authenticated, self-scoped) lists the caller's
  BR affiliations joined to `chapter_registry`, flagging `is_primary` and `is_entry`, for the
  choice card.
- **`/perfil`** gains an entry-chapter card (`entryChapterHtml`): lists the member's BR
  affiliations with a "set as entry" action per row, badges the current entry chapter, and
  the identity headline now prefers `entry_chapter_code` (falls back to `members.chapter`).
  RPC writes re-fetch affiliations + member and re-render.
- **C5 (privacy farol) — first version**: when the member has **no** BR affiliations (the
  observable symptom of a hidden PMI profile / "Hide my chapter(s)"), the card shows a
  guidance farol (uncheck the option + ping management to re-sync). Precise
  `community_profile_private` detection (the flag lives on `selection_applications`, reachable
  only via the drift-captured `get_my_application_status`) is a follow-up — not folded in here
  to keep 3b-i off that drift-sensitive surface.
- **`lib/chapters.ts`** fallback refreshed from the stale 5 (p83) to the **13 BR registry
  chapters** (grounded live). The RPC `get_active_chapters` remains the source of truth; the
  fallback only covers the RPC-unavailable case.

**Still deferred to Wave 3b-ii:** `members.chapter` becomes derived
(`COALESCE(entry_chapter "PMI-prefixed", primary affiliation)`), `get_chapter_*` + admin
read-site repoint, the `U_active_person_has_primary_chapter_affiliation` invariant in
`check_schema_invariants()`, alumni/inactive handling (backfill was active-only), and the
precise `community_profile_private` C5 detection.

## Amendment — Wave 3b-ii (members.chapter derived + invariant U) shipped (2026-06-16, mig `20260805000195`)

`members.chapter` becomes the **compat/derived value** promised by this ADR. It is now
**maintained by triggers** from the two canonical sources — no per-read-site repoint needed:
`COALESCE('PMI-' || entry_chapter_code, 'PMI-' || primary affiliation code, legacy chapter)`.

- **Why no `get_chapter_*` repoint.** Because `members.chapter` is now kept in sync with the
  canonical sources, every existing read-site (`get_chapter_dashboard`/`needs`/`kpis`,
  `admin_list_members(p_chapter)`, `exec_chapter_webinar_metrics`, `/admin/chapter*.astro`,
  the leaderboards) keeps filtering `WHERE m.chapter = p_chapter` and now automatically sees
  the member's real entry/primary chapter. The entry-chapter choice (3b-i) and the worker (3a-iii)
  propagate straight into those filters. Repoint-as-code was the alternative to a maintained
  column; the maintained column is the lower-risk path and is what "compat/derived value" means.
- **Event-specific triggers (NOT a blanket BEFORE override) — admin edit preserved.** Two admin
  write-paths (`admin_update_member`, `admin_update_member_audited`) set `chapter = COALESCE(p_chapter, chapter)`.
  A blanket `BEFORE UPDATE` recompute would silently override those edits whenever the member has a
  primary affiliation. Instead:
  - **T1** `derive_member_chapter_before()` — `BEFORE UPDATE OF entry_chapter_code ON members`: sets
    `NEW.chapter` from the COALESCE. Fires only when `entry_chapter_code` is in the SET list, so a
    chapter-only admin edit does **not** trigger it (the edit passes through).
  - **T2** `recompute_member_chapter_from_affiliation()` — `AFTER INSERT OR DELETE OR UPDATE OF is_primary
    ON member_chapter_affiliations`: recomputes the affected person's `members.chapter`, guarded by
    `IS DISTINCT FROM` so it only writes (and cascades the other member triggers) when the derived value
    actually changes. The UPDATE it issues sets `chapter`+`updated_at` only (never `entry_chapter_code`),
    so T1 does not fire — no recursion, no double-compute.
  - **Consequence (documented trade-off):** a direct admin free-text edit of `chapter` on a member who
    has a primary affiliation can drift from that primary until the next entry-choice / affiliation
    change re-derives it. Post-SSOT the canonical way to change a member's chapter is the entry-choice or
    the affiliation, not the free-text column. Routing admin chapter edits through the affiliation is a
    follow-up, not folded here.
- **Backfill is a NO-OP.** The 3a backfill seeded affiliations *from* `members.chapter`, so
  `'PMI-' || primary_code` already equals the current `members.chapter` for all 72 active registry
  members. The one-time guarded recompute changed **0 rows** (verified live). Validated live (rolled-back
  probe, prod untouched): primary change → chapter follows; entry choice → chapter follows (entry wins);
  admin chapter-only edit → passes through unchanged.
- **Alumni/inactive decision (resolves the 3a contract).** The legacy `members.chapter` stays
  authoritative for non-active members: they have no affiliations and no entry choice, so the COALESCE
  falls through to the existing value. No affiliation backfill for them; the worker fills any that re-sync.
- **Invariant `U_active_person_has_primary_chapter_affiliation`** added to `check_schema_invariants()`
  (CREATE OR REPLACE, signature unchanged): every **active, registry-chaptered** member's `person_id`
  must have **exactly one** `is_primary=true` affiliation, else the COALESCE derivation breaks silently.
  Non-registry chapters (`Outro`/`Externo`, e.g. the one `Outro` active member) are excluded — they are
  legitimately unaffiliated and fall through to legacy. The partial unique index enforces *at most one*;
  this enforces *exactly one*. Verified live: **0 violations** (total `check_schema_invariants()` = 0).

**Still deferred (small follow-ups, not blockers):** adding `entry_chapter_code` to the
`get_member_by_auth` SELECT (the FE already derives the entry chapter from `get_my_chapter_affiliations().is_entry`
and `members.chapter` is now correct, so this is cosmetic); routing admin chapter edits through the
affiliation/entry; and the precise `community_profile_private` C5 detection (lives on the drift-sensitive
`get_my_application_status` surface). **Next: Wave 3c (B8)** — the in-platform signature cycle
(`rejected`/`superseded` states, reject/reissue, `counter_sign` → `countersigned`, `check_my_tcv_readiness`
ignoring rejected/superseded, admin panel + member screens + archival at engagement).
