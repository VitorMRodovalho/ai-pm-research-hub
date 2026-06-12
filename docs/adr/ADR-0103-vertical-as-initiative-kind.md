# ADR-0103 — Vertical (PMI credential community) as an `initiative_kind`

- **Status:** Proposed (draft / skeleton — 2026-06-12)
- **Issue:** #661 ([Discussão] Modelo Verticais × Quadrantes × Tribos)
- **Origin:** Conceptual model `docs/strategy/verticals_x_quadrants_model.md` (a IA como linha de costura entre os silos do PMI). Ratified in principle by PM (Vitor) on 2026-06-12.
- **Refs:** ADR-0005 (`initiative` as domain primitive), ADR-0009 (config-driven `initiative_kinds`), ADR-0004 (`organization_id`), ADR-0007 (`can()` / engagement grants).

## Context

The Núcleo organizes knowledge on three orthogonal axes (see strategy doc):

- **Quadrante** — *what* (knowledge taxonomy; 4 domains). Already modeled.
- **Tribo** — *who produces* (Eixo A). Already an `initiative` of `kind = 'research_tribe'` (ADR-0005).
- **Vertical** — *for whom / where it lands* (Eixo B; a PMI credential community: Construction, PMO, Agile, ESG, Business). **Not yet modeled.**

A vertical is a durable, governed grouping with a partner relationship (Global Construction Ambassadors, PMO Global Alliance, GPM) and an anchor credential (PMI-CP, PMI-PMOCP, PMI-ACP, CSPP, …). Several anchor credentials are *lineages in succession* (PMO-CP → PMI-PMOCP; GPM-b → CSPP), so the model must store the **current** anchor and treat predecessors as history.

The question this ADR settles: **is a vertical a first-class `initiative_kind`, or merely a cross-cutting tag/metadata axis on deliverables?**

## Decision (proposed)

1. **A vertical is an `initiative` of a new `kind = 'community_vertical'`** (config-driven per ADR-0009 — no migration, created via admin). Rationale: a vertical is durable, has governance, a partner, a lifecycle, and sub-work — it is *not* just a label. This matches ADR-0009's own examples (study_group, congress) being kinds.

2. **Sub-work plugs in via `parent_initiative_id`** (ADR-0005 hierarchy): the CPMAI study group, per-community webinars, and workshops become children of their vertical.

3. **Deliverable routing stays N:N via metadata, not containment.** A deliverable produced by a tribe carries `quadrant` (already exists) plus a `verticals text[]` (or join table) routing it to one or more verticals. This preserves the anti-silo principle: *production is the tribe's, distribution is the vertical's — the vertical never owns knowledge.* A vertical does **not** contain the tribe's deliverables; it references them.

4. **`community_vertical` kind config (ADR-0009 `initiative_kinds`)** — proposed `custom_fields_schema`:
   ```
   {
     anchor_credential: text,        -- e.g. 'PMI-PMOCP' (current)
     predecessor_credential: text,   -- e.g. 'PMO-CP' (history, nullable)
     credential_body: text,          -- 'PMI' | 'PMI+GPM' | ...
     partner_org: text,              -- 'PMO Global Alliance' (nullable)
     status: enum,                   -- 'forming' | 'open' | 'paused' (drives the landing CTA)
     pmi_registry_url: text
   }
   ```
   `status` is what the public landing reads to render the "chamada de protagonistas" CTA for *declared-but-not-open* verticals (see strategy doc §CTA). No hardcoded vertical list on the page.

5. **The credential ladder (PMIxAI Champion → CPMAI) is NOT a vertical.** It is the cross-cutting spine shared by all verticals, modeled with the existing gamification/cert primitives (`award_champion`, `cpmai_*`). Verticals reference it; they do not duplicate it.

## Consequences

**Positive**
- Zero schema migration to add a vertical (admin config, per ADR-0009).
- Verticals, tribes, study groups, congresses all share one engine — reports `GROUP BY kind` are natural.
- `status = 'forming'` gives an honest, data-driven "founding cohort" CTA without faking activity.
- Anti-silo invariant is structural: deliverables are referenced, never contained, by verticals.

**Costs / risks**
- `verticals text[]` on deliverables is a new routing field + UI for tagging at publish time.
- Need a guard so a vertical does not accidentally become a parent of a *tribe* (would invert the production/distribution relationship). Constraint: `community_vertical` may parent study_group/webinar/workshop kinds, **not** `research_tribe`.
- Lead capture for `forming` verticals (`capture_visitor_lead` → `application`) needs a `target_vertical` reference.

**Neutral**
- Conceptually a vertical was always a community; this only gives it a home in the existing primitive.

## Alternatives considered

- **(A) Vertical as a pure tag/metadata axis (no initiative).** Rejected: loses governance, partner, lifecycle, and the `forming/open` status that drives the CTA. A tag cannot have a founding cohort.
- **(B) Vertical as a new top-level entity peer to `initiative`.** Rejected: fragments the model, contradicts ADR-0005 (one primitive) and ADR-0009 (config-driven kinds).
- **(C) Vertical contains the tribe's deliverables (containment, not reference).** Rejected: breaks the anti-silo invariant — would make verticals owners of knowledge and recreate the silos.

## Open questions (for council / issue #661)

1. Verticals **curated** (fixed catalog, `max_concurrent_per_org`) or **open** (any community proposes)?
2. `verticals` as `text[]` on the deliverable vs. a `deliverable_verticals` join table (join table if we need per-routing metadata like framing/owner).
3. Does each vertical get its **own** anchor credential *in addition to* the shared Champion→CPMAI ladder (current assumption: yes), or is the ladder the only credential surface?
4. Pilot vertical for Ciclo 4 (institutional timing favors ESG or Agile).

---
*Skeleton authored with PMO (Claude); decision and ratification are the PM/council's. Fill Context constraints against prod before moving to Accepted.*
