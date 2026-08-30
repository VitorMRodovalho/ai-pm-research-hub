# ADR-0127: Canonical chapter entity, and the three concepts that were collapsed into one (chapter, hub, participation)

**Status:** Accepted
**Date:** 2026-08-29
**Source:** Issue [#2083](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2083) (phase 0 of the Hub LATAM lane). Raised while scoping the Spanish-speaking expansion pilot ([#2082](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2082)): every journey the pilot needs (a chapter selection committee seeing only its own candidates, sponsor filtering by chapter, chapter-scoped required attendance, ambassador reach) would today be built on a free-text column.
**Related:** ADR-0005 (`initiatives` as the domain primitive), ADR-0006 (`persons` + `engagements` model identity), ADR-0007 (`can()` is the authority SSOT), [#2084](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2084) (`organization_id` scope never exercised), [#2085](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2085) (region axis and ambassador authority).
**SSOT reused:** `chapter_registry.chapter_code`, which is already the target of the only two chapter foreign keys in the schema.

---

## Context

All counts below are live queries against `ldrfrvwhxsmgaabwmaik`, run 2026-08-29.

"Chapter" is not one entity in this database. It is five parallel populations that
nobody reconciled:

| source | count |
|---|---:|
| `chapters` | **5** rows |
| `chapter_registry` | **15** rows |
| `partner_chapters` | **15** rows |
| `members.chapter` (free text) | **14** distinct values |
| `selection_applications.chapter` (free text) | **16** distinct values |
| foreign keys pointing at any chapter table | **2** |

The drift is not marginal, it is total:

- `partner_chapters` and `chapter_registry` both hold 15 rows and their `chapter_code`
  intersection is **zero**. Two tables of the same size that share no key at all.
- **135** rows of `members` carry a `chapter` value that exists in no registry, across
  **14** distinct spellings, which is every distinct value.
- **129** rows of `selection_applications` are likewise outside the registry.

`members` is the sharpest illustration: it holds **both** `entry_chapter_code`, which is
a constrained foreign key, **and** `chapter`, which is free text and has fully drifted.
The operational surfaces read the free-text one. Any scope test written today would be
comparing strings that already diverged, and would pass by accident.

### Why the three tables are not three candidates

Inspecting the columns settles it:

| table | shape | reading |
|---|---|---|
| `chapter_registry` | `chapter_code`, `legal_name`, `cnpj`, `country`, `state`, `is_contracting_chapter`, `is_active`, `vep_name_aliases`, social URLs | the **entity**: identity fields, plus an alias array that absorbs spelling drift (used in 1 of 15 rows today) |
| `partner_chapters` | `chapter_code`, `chapter_name`, `is_active`, `partnership_start`, `partnership_end`, `partnership_status` | the **relationship**: a partnership with a lifecycle, not a chapter |
| `chapters` | `id`, `organization_id`, `code`, `name`, `pmi_chapter_code`, `region`, `status` | the **orphan**: `pmi_chapter_code` is NULL in all 5 rows and no foreign key references it |

Both existing foreign keys point at `chapter_registry`:

```
member_chapter_affiliations.chapter_code -> chapter_registry(chapter_code)  ON DELETE RESTRICT
members.entry_chapter_code               -> chapter_registry(chapter_code)  ON DELETE SET NULL
```

### The modelling error underneath

The five populations exist because **three different concepts were treated as one**:

1. **The chapter** exists in the world, independently of the Núcleo. PMI-GO would exist
   if the Núcleo had never been created. It is external reference data.
2. **The hub** is the product. Today one row in `organizations`.
3. **A chapter's participation in a hub** has a life of its own: it starts, has a state,
   and ends. It is an attribute of neither of the other two.

## Decision

**1. `chapter_registry` is the canonical chapter entity, and it does NOT receive
`organization_id`.** Hanging the tenant on the chapter would assert that the chapter
belongs to the hub, which is false and does not survive a second hub. Stable key:
`chapter_code`.

**2. `partner_chapters` is the participation table, and it is the one that receives
`organization_id`**, plus a foreign key to `chapter_registry(chapter_code)`. It already
carries `partnership_start`, `partnership_end` and `partnership_status`. It was only
missing both ends of the relationship.

**3. `chapters` is retired.** Its two useful columns move to where they belong:
`organization_id` to `partner_chapters` (it describes participation) and `region` to
`chapter_registry` (it describes the chapter). Its 5 rows are not a source: they have no
`pmi_chapter_code` and nothing references them.

**4. `region` does not carry the ambassador scope.** Its current values are Brazilian
macro-regions (Centro-Oeste, Nordeste, Sudeste, Sul), which is a **sub-national**
grouping. "Cono Sur hispanohablante" and "Caribe" are groupings **across countries**, by
language and geography. Forcing one column to mean both mixes two things. `region` keeps
its current sub-national meaning on `chapter_registry`, and the international grouping
becomes its own **many-to-many** structure, because a chapter can belong to more than one
(LATAM and Cono Sur at once). Ambassador authority scopes to a grouping, which is what
lets it become a real `can()` gate instead of a descriptive field. Designed in #2085.

**5. `cnpj` becomes a generic tax identifier** (`tax_id_type` + `tax_id`). It is filled
in 5 of 15 rows today (GO, CE, DF, MG, RS), which is exactly the host chapter plus the
four with a signed agreement, so in practice the column already means "tax id of whoever
has a contract". An Argentine chapter needs CUIT; the wider Spanish-speaking network
needs RUT, RFC, RUC, NIT or CIF. The Bilateral Agreement's qualification block has the
same gap, so one fix serves both.

**6. Free text becomes a relation only where scope depends on it.** The test is whether
the column decides who sees what. `members.chapter` and `selection_applications.chapter`
qualify. Purely descriptive columns stay as they are.

## Migration order

Order matters, because each step depends on the previous one being proven.

1. **Additive only.** `tax_id_type` + `tax_id` and `region` on `chapter_registry`,
   `organization_id` on `partner_chapters`. Nothing breaks, nothing reads it yet.
2. **Create the links.** See the warning below: this is not reconciliation.
3. **Foreign key** `partner_chapters.chapter_code` to `chapter_registry(chapter_code)`.
4. **Backfill** `pmi_chapter_code` and the two columns migrated off `chapters`.
5. **Retire `chapters`**, only after step 4 is proven.
6. **Free text to relation** on the two scope-bearing columns.

Steps 1 to 3 are the first window. Step 4 onward depends on what step 2 produces.

### Step 2 is link creation, not reconciliation

The word matters. *Reconciliation* presupposes that a correspondence exists and the work
is to find it. That is not the case here: the intersection between
`partner_chapters.chapter_code` and `chapter_registry.chapter_code` is **zero**, with 15
rows on each side. There is nothing to reconcile. What exists is **creating the link from
scratch**, deciding for each of the 15 `partner_chapters` rows which registry chapter it
refers to.

Three consequences:

- **A reconciler can be checked against the correspondence it should have found. A link
  creation has no answer key.** Every row is a new assertion about the world.
- **Where the link is not obvious from the name, the decision belongs to the PM**, not to
  an algorithm. A wrong call here writes the wrong chapter into a table that becomes a
  scope source.
- The negative control stops being a robustness check and becomes **the only test** that
  separates a correct link from an invented one.

Before any DDL in step 3, produce the 15-row table of proposed links with the evidence
for each, and submit it for human review. Rows without clear evidence stay blank rather
than receiving a guess.

## Verification contract

- Capture the **before** counts (5 / 15 / 15 / 14 / 16, and the three drift figures) as a
  live baseline, and prove the **after** with a fresh query. Never derive "before" by
  reasoning backward from "after".
- **Mandatory negative control:** inject a chapter with a divergent spelling and prove
  the linking finds it. A linker that only gets right what was already right has not been
  tested.
- Before running the linker, count the divergences **outside** the intended scope, so
  that "it touched something it should not have" is discoverable rather than discovered
  later.
- A guard that rejects a new free-text chapter column on a scope-bearing surface. Prove
  it by injecting the defect, not by watching it stay green.

## Consequences

**Positive.** Chapter scope stops being string comparison. The pilot's journeys (#2087 to
#2093) gain something real to scope against. A second hub becomes possible without
rewriting the chapter model, because the tenant lives on the participation and not on the
chapter. The tax identifier stops being Brazil-only.

**Cost.** Step 2 is manual and needs the PM. Fifteen assertions have to be made and
checked by a person, and no automation removes that.

**Risk accepted.** Retiring `chapters` removes the only table that today carries
`organization_id` and `region` together. That pairing was never used (one organization,
`pmi_chapter_code` NULL throughout), so nothing depends on it, but the retirement is only
safe after step 4 proves the columns landed.

## What this ADR does not decide

The `can()` gate for the ambassador role. It depends on the international grouping
existing first, and belongs to #2085.
