# ADR-0129: The knowledge layer is authored in the platform, classified by Diátaxis, and fed before it is extended

**Status:** Accepted on 2026-09-27, with the three amendments below (the third of 2026-09-28)
**Date:** 2026-09-13 (proposed) · 2026-09-27 (accepted)
**Source:** Discussion in the Núcleo general WhatsApp group on 2026-09-13 (glossary raised by a researcher; tool-vs-process split proposed by a tribe leader), the `Nucleo_Wiki_Fluxo_Conhecimento_V1` deck of the same date, and a live survey of the knowledge tables run while analysing it.
**Related:** ADR-0010 (wiki content is narrative and non-personal), ADR-0105 (confidential initiative visibility), [#2208](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2208) (YouTube archive without captions), [#2495](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2495) (living wiki: architecture and gap assessment).
**SSOT reused:** `wiki_pages`, `knowledge_assets`, `knowledge_chunks`, `knowledge_ingestion_runs`, `search_nucleo_knowledge` (MCP).

---

## Context

All counts are live queries against `ldrfrvwhxsmgaabwmaik`, run 2026-09-13.

The group concluded that the **tool** is solved and the **process** is open. The survey says the
tool is solved more completely than anyone in the discussion believed, and that the open problem is
narrower and different from the one being debated.

### The knowledge layer already exists in all four layers

| layer | artefact |
|---|---|
| webpage | `src/pages/governance/glossario.astro`, `src/pages/admin/knowledge.astro` (both with `/en` and `/es`) |
| API | `knowledge_search`, `knowledge_search_text`, `knowledge_assets_latest`, `get_governance_glossary`, `can_manage_knowledge` |
| cron | 58 runs triggered by `github_actions`, most recent 2026-09-10 |
| MCP | `search_nucleo_knowledge`, a unified intent over hub resources, wiki pages and assets, with citations |

A glossary RPC (`get_governance_glossary`) and an authority gate (`can_manage_knowledge`) already
exist. The group's proposal to *create* a glossary is, in part, a proposal to populate one.

### The conveyor runs empty and reports success

| source | trigger | runs | rows received | rows upserted |
|---|---|---:|---:|---:|
| `insights` | **github_actions** | **58** | **16** | **2** |
| `youtube` | manual_smoke | 3 | 2 | 1 |
| `insights` | manual / debug | 2 | 1 | 0 |

**All 62 runs have status `success`.** Fifty-eight automated runs across six months received sixteen
rows. `knowledge_assets` holds **1** row and `knowledge_chunks` holds **1**.

The YouTube rail — the source that holds every recorded general meeting — was smoke-tested once on
2026-03-08 and never wired.

This is an absence that reads as benign: a green run does not distinguish *processed everything* from
*nothing arrived*. Nothing alerts, so nobody looks.

### The supply exists and is outside

| available | count |
|---|---:|
| meetings with a catalogued recording | 26 |
| events carrying minutes | 30 |
| wiki pages | 151 |
| governance documents | 22 |
| meeting artefacts | 12 |
| **in the library** | **1** |

### The authoring barrier is real, and measured

`wiki_pages` carries `source_repo`, `source_sha` and `synced_at`: it is a mirror of the
`nucleo-ia-gp/wiki` repository, maintained by `sync-wiki`, a GitHub **push webhook** receiver. There
is no cron on our side and **no write RPC**: the three wiki functions are `get_wiki_page`,
`search_wiki_pages` and `wiki_health_report`.

The mirror's last sync is **2026-08-03**. The wiki repository's last commit is the **same day**, and
the thirteen distinct sync dates each match a commit. **The webhook works; nobody writes.**

Forty-one days of silence from the people who already have the ability to write is the measurement
that makes the barrier concrete rather than hypothetical: publishing a page requires exactly the
GitHub the group concluded no member should need to understand.

### The current taxonomy is organised around the writer

| folder | pages | without `summary` |
|---|---:|---:|
| `migrated-from-public-816` | 66 | 66 |
| `strategy` | 20 | 20 |
| `governance` | 19 | 4 |
| `platform` | 11 | 2 |
| `iniciativas` | 8 | 8 |
| `tribes` | 8 | 0 |
| `partnerships` | 8 | 1 |
| `research` | 5 | 4 |
| `onboarding` | 2 | 0 |

**107 of 151 pages carry no summary**, and the summary is what a search result displays. The folders
name who produced the page, not what a reader wants to do.

## Decision

### 1. Knowledge pages are authored in the platform. Git stays, but stops being the door.

Every reference organisation keeps documentation in git and reviewed like code — the Linux kernel,
GitHub's own docs, Supabase and Cloudflare. **None of them require the reader to touch git**;
authoring in git is paired with a built site, a search surface and an API for consumption.

Núcleo's authors are volunteers, not maintainers of the repository, so the pairing breaks: the
authoring half of that pattern is the barrier. The decision is therefore to **add a platform
authoring path**, not to remove the git mirror.

### 2. The GitHub mirror stays one-way. No reverse sync.

Pages authored in the platform live under a path namespace the repository never uses, and are
discriminated by `source_repo`.

This is safe by construction, not by convention: `sync-wiki` deletes only paths listed in a push
payload's `commit.removed`, and **never reconciles**. A row whose `path` never appears in a push is
never touched by the sync. The Obsidian vault continues to be mirrored; the platform gains its own
authorship; neither writes over the other.

Bidirectional documentation sync is rejected explicitly (see Alternatives).

### 3. The taxonomy is Diátaxis, classified by the reader's goal.

Pages are typed **tutorial · how-to · reference · explanation**, not filed by owning area. The
framework is adopted by Canonical, Cloudflare and others precisely because it organises by what the
reader is trying to do.

Concretely: a page derived from a general meeting is an **explanation**, not "a page about LGPD filed
under governance". That typing is what makes it findable by a researcher from another tribe, which is
the group's own acceptance criterion.

`summary` becomes mandatory for platform-authored pages, because it is the search surface.

### 4. Supply before surface.

No new authoring surface is built before the rails that already exist are fed. The ingestion pipeline
is not missing a design; it is missing input.

### 5. A green run that received nothing must stop reading as success.

`knowledge_ingestion_runs` records `rows_received`. Fifty-eight successful runs receiving sixteen rows
produced no signal anywhere. Any rail wired under decision 4 carries a detector on the **denominator**,
not only on the exit status — otherwise a new rail fails exactly as silently as the current one.

## Consequences

- Two authoring surfaces write to one table. `source_repo` already discriminates them; a constraint
  should prevent a platform path from colliding with a repository path.
- Diátaxis reclassification is work on 151 existing pages. It does not need to be done at once: new
  pages are typed from the first one, and the 66 `migrated-from-public-816` pages are a separate
  decision (they carry no summary and degrade search for a non-technical reader).
- Platform authoring requires a write RPC gated by `can_manage_knowledge`, which already exists.
- ADR-0010 still binds: a page derived from a meeting is about the **subject**, never a second set of
  minutes with attributed speech. This changes what curation means and must be stated before anyone
  writes the first page.

## Alternatives rejected

**Bidirectional sync between platform and repository.** A write RPC that commits back to the wiki
repository. Rejected: two-way documentation sync is a known foot-gun, and it violates the group's own
design criterion — repairable by an average mechanic with common tools, under pressure.

**Commit from the platform via a GitHub App.** Keeps a single source but adds an integration,
credentials and a failure mode between the author and their page.

**Accepting that curators use the repository.** This is the status quo, and the status quo produced
forty-one days of silence.

**A new destination (a Drive folder, a new wiki).** Rejected on the group's own ground: the problem is
not a shortage of places.

## What this ADR does NOT decide

- Where the retroactive archive fits (recordings exist publicly since Cycle 2).
- Whether curation belongs to the existing Curation Committee or to a new initiative.
- The access model for `observer` and `sponsor` kinds, which is a separate governance decision:
  `join_policy` accepts `'open'` in its CHECK, **0 of 36 initiatives use it**, and
  `request_to_join_initiative` treats `'open'` identically to `request_to_join`.
- Whether an active dissemination layer (workshop, learning trail) belongs here or to the tribe
  already running the culture research.

## Amendment (GP decisions, 2026-09-26 and 2026-09-27)

Accepted together with these decisions. Where the text above and this section differ, this section wins.

1. **Curation belongs to the existing Curation Committee, organised by domain.** This closes the first
   open point of "What this ADR does NOT decide". Each domain has a curator and a substitute, named as
   roles, never as a single person.
2. **Media is a cited source, never a copy.** Video, PDF, podcast and webinar stay where they live (Drive,
   YouTube) and enter the wiki as a link in the note's sources. Nothing is duplicated into the repository
   or into `wiki_pages`.
3. ~~Proposals in the pilot use the existing curation machinery for board items.~~ **Superseded by
   Amendment 2** (publish first, audit after).
4. **The pilot domain is `tribes`.**
5. **The 66 `migrated-from-public-816` pages and the 20 `strategy` pages were working documents, not
   narrative knowledge.** On 2026-09-27 they moved to a private management archive, and the push webhook
   removed them from `wiki_pages`, leaving 65 pages. This resolves the corresponding item under
   Consequences.
6. **Reading the wiki requires an active member.** `wiki_pages_read` moves from `rls_is_member()` (any
   member row for the login, active or not) to `rls_is_authoritative_member()`, the canonical gate of the
   RLS phase 2 read policies. The other policies that still use `rls_is_member()` are unchanged by this
   decision.

## Amendment 2 (GP decision, 2026-09-27): publish first, audit after

Replaces item 3 of the first amendment for the wiki. Publications meant for outside the Núcleo (articles,
congress submissions) keep the existing pre-publication curation: two reviews, rubric, 7-day SLA. The
wiki is internal and reversible, and the measured bottleneck is people, not control: four members hold
curation authority, and the wiki had one author in three months.

1. **The leader of a tribe is the first curator of that tribe's pages.** A page the leader approves is
   published at once.
2. **Four eyes.** When the author is the leader, the Curation Committee approves before publication. Today
   each active tribe has exactly one leader and no deputy.
3. **Automatic gate before publishing.** A page that the health check flags for personal data does not
   publish directly; it goes to the committee.
4. **Governance pages keep approval before publication** by the committee and the GP (normative content:
   volunteer term, IP policy, LGPD).
5. **The committee audits every published page within 14 days** and keeps, alters or unpublishes it, always
   with a written reason. Until then the page shows "published by the tribe, audit pending", to readers and
   to the assistant.
6. **Every publication, alteration and unpublishing is an append-only page version.** A committee change is a
   new version, never an overwrite, and author and leader are notified at once.
7. **Consequence for the design:** the unit of review is the page version, not a board card. A light version
   table (option 3a in #2495) replaces the card-based proposals.

## Amendment 3 (GP decision, 2026-09-28): the wiki covers every initiative, not only tribes

Replaces item 4 of the first amendment ("the pilot domain is `tribes`") for authoring. Measured the same day:
the database has 14 research tribes (12 active; tribes 2 and 3 archived), 10 working groups, 5 verticals and
1 study group, while the wiki's home listed only the 7 tribes that already had a page, and only tribes could
write.

1. **Working groups, verticals and the study group write their own page**, like the tribes. Congresses and
   committees do not get a page.
2. **Leadership is `leader` or `coordinator`; writers are also `participant`, `researcher` and `reviewer`;
   `observer` only reads.** Measured before deciding: tribes have neither coordinators nor participants nor
   reviewers, so nothing changes for them. The four-eyes rule of Amendment 2 is unchanged: when the author is
   part of the leadership, the Curation Committee approves before publication.
3. **Pages of non-tribe initiatives live in the `initiatives` domain, under `nucleo/iniciativas/<id>`.**
4. **The home lists every tribe (archived ones marked as frozen) and every other initiative from the
   initiatives catalogue, not from the pages that exist**, with the page state of each: on the platform, old
   version from the repository, or no page yet. An initiative with no engaged team (measured: the 5 verticals
   and one working group) shows that, and only the Curation Committee can write for it until someone is
   engaged.

## References

- [Diátaxis](https://diataxis.fr/) · [Canonical's adoption](https://ubuntu.com/blog/diataxis-a-new-foundation-for-canonical-documentation)
- `llms.txt` adoption among developer-facing organisations ([2026 guide](https://codersera.com/blog/llms-txt-complete-guide-2026/)). Núcleo's MCP surface already exceeds what a static `llms.txt` provides: it is a live, authority-aware query rather than a file an agent downloads.
