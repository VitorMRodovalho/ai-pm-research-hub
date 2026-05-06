# ADR-0070 — External Speaker Artifact Conventions

**Status:** Accepted
**Date:** 2026-05-05 (p95)
**Context:** Issue #97 G6 — closes "portfolio artifact convention not documented"
**Related:** ADR-0066 (PMI Journey v4) · ADR-0019 (Portfolio as Projection) · spec `docs/specs/p87-external-engagement-lifecycle.md`

---

## Context

External speaker engagements (PMI congress submissions, ProjectManagement.com articles, partner webinars) generate 4 distinct classes of artifacts across their lifecycle:

1. Pre-submission preview (draft video, outline)
2. Stage 1 review materials (draft slides, narrative deck)
3. Stage 2 final materials (final slides, recording rehearsals)
4. Post-event public artifacts (official PMI recording, public deck)

Without a documented convention, the team diverges on **which schema target stores which artifact** and **what visibility applies**. LATAM LIM 2026 (Roberto + Ivan) surfaced this divergence concretely. Replays for next submissions (LIM 2027, ProjectManagement.com articles, partner workshops) need predictable mapping.

## Decision

Adopt the following table as the canonical mapping for external speaker artifacts:

| Stage | Artifact | Schema target | Visibility | Notes |
|---|---|---|---|---|
| Pre-submission | Draft video preview | `meeting_artifacts` | Comitê (privado) | Used to validate speaker style + content fit. Often pre-existing (e.g., Macedo_Antonio_AI_Research_Hub.mp4) |
| Stage 1 review | Draft slides PPT | `meeting_artifacts` | Reviewers (T6 leader + committee_coord) | First reviewable structure. Linked to `board_items.checklist` for SME feedback iteration |
| Stage 2 final | Final slides PPT | `meeting_artifacts` | Comitê + curador | Locked version submitted to partner (e.g., PMI Stage 2). Optional snapshot in `document_versions` if formal review chain needed |
| Post-event | Official partner recording | `public_publications` (kind='video') | Público | Released by partner (e.g., PMI uploads to PMI.org/event-archive). Núcleo links via URL, doesn't re-host |
| Post-event | Public final deck | `public_publications` (kind='deck') | Público (CC-BY-SA opcional) | Speaker decision: re-publish slides under license, or keep private. Default: private unless speaker opts in |

## Consequences

### Positive
- **Predictable target** for any artifact — no schema decision per submission
- **Replay-friendly** for upcoming submissions (LIM 2027, etc.) reduces ad-hoc decisions
- **Cross-cuts cleanly** with publication_ideas pipeline (#94) — Stage "Palestras & Keynotes" inherits this convention
- **Visibility separation** preserves draft confidentiality while enabling post-event public reach
- Aligns with ADR-0019 (Portfolio as Projection) — `meeting_artifacts` is internal projection; `public_publications` is external surface

### Negative
- Doesn't cover edge cases (e.g., webinar recordings vs congress recordings — both treated as `public_publications kind='video'`; differentiation lives in metadata)
- Requires manual classification per artifact (no automatic stage detection)
- Future: if `meeting_artifacts` retention conflicts with archival of post-submission artifacts, may need new table `external_submission_artifacts`

### Neutral
- Uses existing schema (zero migration needed for this ADR)
- Optional `document_versions` snapshot at Stage 2 final is opt-in, not required

## Implementation

This ADR is **doc-only** — no schema changes. The convention applies to:
- **#97 W2** — `board_items.source_type='external_partner'` items inherit this artifact mapping via convention
- **#94** — publication_ideas pipeline 6th seed "Palestras & Keynotes" uses this table as input contract
- **Future**: when MCP tool `create_external_speaker_engagement_v1` (#97 G4) lands, its prompt explains this convention to LLM agents.

## Examples (LATAM LIM 2026)

| Artifact | Stage | Storage |
|---|---|---|
| Macedo_Antonio_AI_Research_Hub.mp4 | Pre-submission | `meeting_artifacts` row, linked to initiative `a68fcc06-...`, visibility=comitê |
| Draft Stage 1 slides | Stage 1 (M3 board_item) | `meeting_artifacts`, reviewers Fabricio + Sarah |
| Final Stage 2 slides | Stage 2 final (M5 board_item) | `meeting_artifacts`, committee + curator |
| PMI official recording | Post-event (M7 portfolio_item) | `public_publications kind='video'`, public, URL link to PMI |
| Public final deck (optional) | Post-event | `public_publications kind='deck'`, CC-BY-SA if speaker opts in |

## References

- Spec source: `docs/specs/p87-external-engagement-lifecycle.md` §G6
- Issue #97 §G6 + cross-ref §#94 W1
- ADR-0019 (Portfolio as Projection) — projection vs surface separation
- ADR-0066 (PMI Journey v4) — engagement subsystem reference
