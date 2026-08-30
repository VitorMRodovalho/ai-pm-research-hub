# ADR-0128: Chapter identity beyond Brazil (code space, country, default locale, and absence of chapter)

**Status:** Accepted
**Date:** 2026-08-29
**Source:** Issue [#2102](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2102), raised while sizing the migration steps of ADR-0127 for the Hub LATAM lane ([#2082](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2082)). These are not corrections to ADR-0127; they are decisions that ADR-0127 explicitly does not make, and that the pilot needs before a non-Brazilian chapter exists.
**Related:** ADR-0127 (canonical chapter entity), ADR-0104 (chapter affiliations SSOT), ADR-0007 (`can()` is the authority SSOT), [#2085](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2085) (international grouping and ambassador authority), [#2086](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2086) (language typing).
**SSOT reused:** `chapter_registry`, established as the canonical chapter entity by ADR-0127.

---

## Context

All counts are live queries against `ldrfrvwhxsmgaabwmaik`, run 2026-08-29.

ADR-0127 settled which table is the chapter. It did not settle what a chapter looks like
once one of them is not Brazilian. Three gaps surfaced while sizing its migration steps.

### The code space is Brazilian, and two foreign keys depend on it

`chapter_registry` has `PRIMARY KEY (id)` but a standalone `UNIQUE (chapter_code)`, and
both chapter foreign keys in the schema target the code, not the primary key:

```
member_chapter_affiliations.chapter_code -> chapter_registry(chapter_code)  ON DELETE RESTRICT
members.entry_chapter_code               -> chapter_registry(chapter_code)  ON DELETE SET NULL
```

The 15 codes are Brazilian state abbreviations (`GO`, `BA`, `RJ`, ...). `BA` is Bahia, and
"Buenos Aires" abbreviates to BA just as naturally. A synthetic read-only probe confirmed
that a row coded `PMI-BA` carrying an Argentine name resolves to Bahia on the code alone,
with only the chapter name objecting.

### `country` exists and is inert

The column is present and holds `'BR'` in all 15 rows. It is nullable and nothing reads it
as a constraint, so it currently records a fact without enforcing one.

### The journey has no language, and the emitted artifacts disagree about its shape

`chapter_registry` has **0** columns matching `lang|locale|idioma`. The whole public schema
has **5** language columns, all on artifacts the platform *emits*, none on the journey a
person *walks*:

| table | column | default |
|---|---|---|
| `certificates` | `language` | `'pt-BR'` |
| `event_guest_certificates` | `language` | `'pt-BR'` |
| `knowledge_assets` | `language` | `'pt-BR'` |
| `public_publications` | `language` | `'pt-BR'` |
| `campaign_recipients` | `language` | **`'pt'`** |

Four use a full locale tag and one uses a bare subtag. Two value spaces already coexist,
4 to 1. The platform's own dictionaries are `pt-BR`, `en-US` and `es-LATAM` (29, 18 and 12
occurrences of the literal tags in `src/`).

### Some rows are not a chapter at all

`members.chapter` holds 7 rows that name no chapter: `Externo` (1) and `Outro` (6).

## Decision

**1. `chapter_code` stays globally unique, and `country` restricts the code space.** A
chapter with `country <> 'BR'` carries its country in the code (`AR-BUE`, not `BUE` and
never `BA`). `country` becomes `NOT NULL`; the backfill is free because all 15 rows are
already `'BR'`.

*Composite key `(country, chapter_code)` was considered and rejected.* It resolves the
ambiguity inside the reference table and spreads it to every reference: dropping the
standalone unique breaks both foreign keys, and `members.entry_chapter_code = 'BA'` would
stop identifying a chapter without a companion country column on `members`, on
`member_chapter_affiliations`, and in every join over them. The ambiguity is better removed
from the code space than admitted into the key.

*Migrating the foreign keys to `id` was also rejected.* It is the purest surrogate-key
answer, but it costs both foreign keys plus the join logic of 57 functions, and it still
leaves the need for a readable non-colliding code in the interface, which is the thing
being decided here.

**2. `default_locale` on `chapter_registry`, constrained to the platform's three tags**
(`pt-BR`, `en-US`, `es-LATAM`), `NOT NULL`, defaulting to `'pt-BR'`. The backfill is free
for the same reason `country` is.

**The ambiguity this removes is in the journey.** Today nothing in the data says which
language to serve a volunteer entering through a given chapter. The choice falls to guesswork
at render time, and the pilot's Spanish-speaking journey has no defined starting point at
all. With the chapter carrying its own base language, every journey that begins at a chapter
begins in a known language, and the same value drives the transactional mail, the forms and
the selection screens that the journey passes through. That is the point of putting it on the
dimension: the answer is in the row, not reconstructed downstream.

The name carries the second half of the rule. It is a **default**, never a gate. A Brazilian
entering through an Argentine chapter, or an Argentine joining a Portuguese-speaking tribe,
breaks any reading where the chapter decides for the person. The person's locale belongs to
the person; the chapter supplies the starting value and nothing more. Hanging authority on it
would repeat the error ADR-0127 corrected, which is asserting on the entity what belongs to
the relation.

Identity disambiguation is a **separate concern** and stays with decision 1. Language could
not carry it even if asked to, being coarser than country and largely determined by it
(Buenos Aires and Madrid are both `es`).

**3. Absence of chapter is recorded as a reason, not as a null and not as a chapter row.**
When the scope-bearing column becomes a relation (ADR-0127 step 6), a chapter outside the
registry leaves it `NULL`, and a small companion column records why: declared external,
none, or not informed.

*Null alone was rejected* because it collapses "the person told us they are outside" into
"we do not know", and once collapsed no query separates them again. *A sentinel row in the
registry was rejected* because `Externo` would then be an entity: it would appear in
`get_active_chapters()`, in the application form's selector and in the leaderboard, since
all of them read the registry.

**4. A foreign chapter is a registry row, not an absence.** The one non-Brazilian case
already present in the data has a real chapter with a verifiable affiliation snapshot. It
resolves under decision 1 as a registry row with its own country, not under decision 3.

## Migration order

The gate is unchanged: no DDL before the merge queue is clear. These steps go with or after
the first window of ADR-0127 (its steps 1 to 3).

1. **Additive only.** `default_locale` on `chapter_registry` with its default and check.
2. **`country NOT NULL`** plus the code-space check for non-Brazilian rows.
3. **Reason column** for absence of chapter, alongside ADR-0127 step 6.
4. **Foreign chapters as rows**, before the pilot runs a journey against them.

Step 4 has a prerequisite that is not code: confirm at the source whether PMI assigns a
global chapter identifier. `chapters.pmi_chapter_code` exists and is NULL in all 5 rows, so
the schema already reserved a place for one. An official identifier is a better natural key
than any scheme invented here, and checking costs less than migrating away from a scheme
later.

## Verification contract

- Capture the **before** counts (15 rows all `country = 'BR'`, 0 locale columns on the
  registry, 5 language columns in the schema split 4 to 1 between value spaces) as a live
  baseline, and prove the **after** with a fresh query.
- **Guard, proven by defect injection:** a new chapter row whose `country <> 'BR'` and whose
  code does not carry the country must be rejected. Prove it by injecting exactly that row
  and watching it fail, not by watching the guard stay green.
- **Negative control on the locale check:** a value outside the three platform tags must be
  rejected, including the bare subtag `'pt'`, which is the form one existing column already
  uses.
- Before adding a sixth language column, decide `campaign_recipients.language = 'pt'`:
  either align it to the full tag or record it as a known exception. Leaving it undecided
  means "what language is this" has two correct answers depending on the table.

## Consequences

**Positive.** The `BA` collision cannot occur, because the code space excludes it by
construction rather than by convention. `country` stops being inert. The journey gains a
default locale source, which is what #2086 was missing. `chapter_registry` becomes a proper
dimension: identity in one unique code, descriptive attributes beside it.

**Cost.** Three additive migrations and one guard. The code-space rule is a convention that
has to be enforced, and a guard is the only thing that keeps a convention true.

**Risk accepted.** The code scheme may be superseded if PMI turns out to publish a global
chapter identifier. The prerequisite in step 4 exists to find that out before the scheme
spreads, and the cost of switching is bounded while foreign rows are few.

## What this ADR does not decide

The international grouping (many-to-many, across countries) and the ambassador `can()`
gate. Both belong to #2085. This ADR only makes the chapter identifiable outside Brazil so
that the grouping has something well-formed to group.
