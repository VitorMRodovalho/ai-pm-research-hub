# ADR-0127: Canonical chapter entity, and the three concepts that were collapsed into one (chapter, hub, participation)

**Status:** Accepted
**Date:** 2026-08-29
**Source:** Issue [#2083](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2083) (phase 0 of the Hub LATAM lane). Raised while scoping the Spanish-speaking expansion pilot ([#2082](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2082)): every journey the pilot needs (a chapter selection committee seeing only its own candidates, sponsor filtering by chapter, chapter-scoped required attendance, ambassador reach) would today be built on a free-text column.
**Related:** ADR-0005 (`initiatives` as the domain primitive), ADR-0006 (`persons` + `engagements` model identity), ADR-0007 (`can()` is the authority SSOT), [#2084](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2084) (`organization_id` scope never exercised), [#2085](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2085) (region axis and ambassador authority), ADR-0104 (chapter affiliations SSOT, which already supplies the `pmi_memberships` snapshot and the `display_code` convention step 6 depends on).
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
  intersection is **zero**, because one side prefixes the code with `PMI-` and the other
  does not. Strip the prefix and the two sides are a perfect bijection. See "Step 2 is a
  deterministic mapping" below.
- **135** rows of `members` and **129** rows of `selection_applications` carry a `chapter`
  value that matches no registry code, which is every distinct value on both sides. That
  figure is the raw comparison, and it is misleading for the same reason as the one above:
  these columns hold the `PMI-` display form. Normalized, **12 of 14** spellings in
  `members` resolve (128 of 135 rows) and **13 of 16** in `selection_applications` (123 of
  129 rows). The real residue is small and is described under step 6.

`members` is the sharpest illustration: it holds **both** `entry_chapter_code`, which is a
constrained foreign key, **and** `chapter`, which is unconstrained text. The operational
surfaces read the free-text one, and the imbalance is not marginal: **52** `SECURITY
DEFINER` functions read `members.chapter` with no reliable chapter source anywhere in their
body, against **9** functions in the whole schema that mention `entry_chapter_code` at all.
Among the 52 are `get_chapter_dashboard`, `get_chapter_selection_summary`,
`exec_chapter_comparison`, `get_public_leaderboard` and `admin_list_members_with_pii`,
which are precisely the scoped surfaces the pilot's journeys exercise. A scope test written
against that column today compares strings, and passes by accident.

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
2. **Link the two sides** additively: a new canonical column on `partner_chapters`, not a
   rewrite of the existing one. Deterministic; direction settled below.
3. **Foreign key** `partner_chapters.chapter_code` to `chapter_registry(chapter_code)`.
4. **Backfill** `pmi_chapter_code` and the two columns migrated off `chapters`.
5. **Retire `chapters`**, only after step 4 is proven.
6. **Free text to relation** on the two scope-bearing columns.

Steps 1 to 3 are one window, because step 2 needs no human adjudication.

### Step 6 is a code refactor, not a data reconciliation

The `PMI-` prefix is not drift either. `src/lib/chapters.ts` declares `display_code` with
the comment "PMI-GO, PMI-CE, ... (for matching members.chapter)", served by the
`get_active_chapters()` RPC. The convention is deliberate and already modelled, so the two
free-text columns normalize the same way step 2 does. What remains after normalization:

| column | spellings | rows | resolve by prefix | genuine residue |
|---|---:|---:|---|---|
| `members.chapter` | 14 | 135 | 12 spellings, 128 rows | `Externo` (1 row), `Outro` (6 rows) |
| `selection_applications.chapter` | 16 | 129 | 13 spellings, 123 rows | `PMI-EM` (1), `PMI-GOI` (2), `PMI-RIO` (3) |

Two things follow, and they point in opposite directions.

**The data side is small, but the residue resolves per row, not per spelling.** `PMI-GOI`
is Goiás in both rows, corroborated by `chapter_affiliation` and `pmi_memberships`. But
`PMI-RIO` is **not one chapter**: two of its three rows resolve to Rio Grande do Sul and
only one to Rio de Janeiro, each corroborated by that row's own `pmi_memberships` snapshot.
The string "Rio" matches two registry chapters, so any per-spelling rule would have written
the wrong chapter into two rows. `Externo`, `Outro` and `PMI-EM` are not chapters at all.

**The code side is the real cost.** The 52 `SECURITY DEFINER` functions above keep reading a
text column regardless of how clean the data becomes. That is the work step 6 actually
buys, and it is refactor, not reconciliation.

### The foreign-chapter case already exists in the data

The `PMI-EM` row belongs to a member of a non-Brazilian PMI chapter. The model has nowhere
to put it: `chapter_registry` holds 15 Brazilian chapters, and the free-text columns absorb
the case silently. This is the same case the
expansion multiplies, and it argues that the registry needs foreign chapters as rows
before the pilot, not after. Belongs to #2085 together with the code scheme.

### Step 2 is a deterministic mapping

An earlier reading held that step 2 was link creation with no answer key, on the grounds
that the `chapter_code` intersection is zero. The zero is real, but its cause is
formatting, not semantics: `partner_chapters` writes `PMI-GO` where `chapter_registry`
writes `GO`. Measured 2026-08-29:

| check | result |
|---|---:|
| raw `chapter_code` intersection | **0** |
| rows matching after stripping `^PMI-` | **15 of 15** |
| distinct registry targets elected | **15** |
| registry rows left with no partnership | **0** |
| partner rows without the `PMI-` prefix | **0** |

Two further signals corroborate the mapping independently of the code:

- **Name.** `partner_chapters.chapter_name` matches `chapter_registry.state || ', Brazil
  Chapter'`, with exactly one candidate per row. `AM` is the only row that needs
  `vep_name_aliases`, because it is recorded as "Amazonia Chapter"; it is the single
  populated alias row in the table, and it earns its place here.
- **Contract.** The 5 rows with `partnership_status = 'signed'` are `CE, DF, GO, MG, RS`,
  and the 5 registry rows with `cnpj` filled are the same five. Zero divergence between
  the two sets, across two tables and two unrelated columns.

Step 2 is therefore a single deterministic `UPDATE`, not fifteen human assertions, and it
does not gate on review. The 15-row evidence table was produced and checked before this
section was written.

#### Which side normalizes, and why the answer is "neither"

An earlier draft of this ADR left the direction unstated, and the foreign key in decision 2
implied the destructive one: make `partner_chapters.chapter_code` hold the registry form, so
the key can point at it. Measuring the consequence rules that out.

`partner_chapters.chapter_code` holds the **display** form (`PMI-CE`), and so does
`members.chapter`. They join directly today: **128** members match a partner row on equality,
with no conversion. Rewriting `partner_chapters` to the bare form silently drops that join to
zero. It does not raise an error, it starts returning nothing, and the readers are not
hypothetical: **4** functions read `partner_chapters` today (`apply_partner_chapter_tags`,
`enrich_applications_from_csv`, `import_vep_applications`, `parse_vep_chapters`), three of
which also touch a `chapter` column. That is the VEP ingestion path, and the countersign work
in #2104 would join the same way.

Decision: **the link is additive.** `partner_chapters` keeps its existing column, which is a
display code and should eventually be named like one, and gains a **new** canonical column
carrying the registry form, which is what the foreign key in decision 2 points at. Nothing
that reads the display form breaks, the canonical link exists, and the duality stops being
implicit. It is the same pair `src/lib/chapters.ts` already models as `chapter_code` plus
`display_code`.

Two consequences worth stating, because they are easy to get wrong later:

- The rename of the display column is a **separate, later step**, after its four readers
  migrate. Renaming it in this step would recreate the same silent breakage by another route.
- Any new predicate over chapter identity should read the **canonical** column. Any predicate
  that must match `members.chapter` reads the **display** one, until step 6 turns that column
  into a relation and the question disappears.

## Verification contract

- Capture the **before** counts (5 / 15 / 15 / 14 / 16, and the three drift figures) as a
  live baseline, and prove the **after** with a fresh query. Never derive "before" by
  reasoning backward from "after".
- **Mandatory negative control, and it belongs to step 6, not step 2.** Step 2 has a
  deterministic key; step 6 does not, because `members.chapter` (14 spellings) and
  `selection_applications.chapter` (16 values) have none. Inject a chapter with a
  divergent spelling there and prove the linking finds it. A linker that only gets right
  what was already right has not been tested.
- The step 2 mapping was itself exercised against synthetic rows, read-only: a divergent
  alias is found, a non-existent code returns nothing, and a row whose code and name
  disagree is reported as a disagreement instead of being silently resolved. The match is
  case- and accent-sensitive, which is harmless across these 15 uniform rows and is
  exactly what will bite in step 6.
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

**Cost.** Lower than first assessed. Step 2 was expected to need fifteen human
assertions; measurement found a deterministic prefix instead. The same prefix turned out to
govern the two free-text columns, so step 6's data reconciliation is small as well: 13 rows
in total, resolved per row rather than per spelling. The cost that remains is the code
refactor of the 52 `SECURITY DEFINER` functions that read `members.chapter`, and that one
does not shrink.

**Risk accepted.** Retiring `chapters` removes the only table that today carries
`organization_id` and `region` together. That pairing was never used (one organization,
`pmi_chapter_code` NULL throughout), so nothing depends on it, but the retirement is only
safe after step 4 proves the columns landed.

**Risk introduced by the code scheme.** `BA` in the registry is Bahia, and "Buenos Aires"
abbreviates to BA just as naturally. A synthetic probe confirmed that `PMI-BA` carrying an
Argentine name resolves to Bahia on the code signal alone, with only the name signal
objecting. The pilot chapter must therefore not be registered as `BA`. Choosing a code
scheme that survives non-Brazilian chapters belongs to #2085, where the international
grouping is designed.

## What this ADR does not decide

The `can()` gate for the ambassador role. It depends on the international grouping
existing first, and belongs to #2085.
