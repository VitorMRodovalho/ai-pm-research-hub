# ADR-0129: The knowledge layer is authored in the platform, classified by Diátaxis, and fed before it is extended

**Status:** Proposed
**Date:** 2026-09-13
**Source:** Discussion in the Núcleo general WhatsApp group on 2026-09-13 (glossary raised by a researcher; tool-vs-process split proposed by a tribe leader), the `Nucleo_Wiki_Fluxo_Conhecimento_V1` deck of the same date, and a live survey of the knowledge tables run while analysing it.
**Related:** ADR-0010 (wiki content is narrative and non-personal), ADR-0105 (confidential initiative visibility), [#2208](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2208) (YouTube archive without captions).
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

## References

- [Diátaxis](https://diataxis.fr/) · [Canonical's adoption](https://ubuntu.com/blog/diataxis-a-new-foundation-for-canonical-documentation)
- `llms.txt` adoption among developer-facing organisations ([2026 guide](https://codersera.com/blog/llms-txt-complete-guide-2026/)). Núcleo's MCP surface already exceeds what a static `llms.txt` provides: it is a live, authority-aware query rather than a file an agent downloads.
