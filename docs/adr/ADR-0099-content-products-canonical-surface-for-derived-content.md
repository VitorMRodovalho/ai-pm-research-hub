# ADR-0099 — `content_products` as the canonical surface for derived editorial content

| Field | Value |
|---|---|
| Status | Accepted (2026-05-26 p264.W4g #383) — spec-only; implementation deferred to #382 W4f foundation migration (see §10) |
| Date | 2026-05-26 |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude (Anthropic)) |
| Supersedes | none |
| Amends | none |
| Related | [[ADR-0086]] (curation pipeline / structured peer + leader review) · [[ADR-0078]] (external reviewer onboarding) · [[ADR-0093]] (canonical RPC façade for approval orchestration) · [[ADR-0087]] (`curate_content` V4 action) · [[ADR-0041]] (`participate_in_governance_review` action) · SPEC_GOVERNANCE_DOCUMENTS_END_TO_END §6.1 + §16.5 + §19.5 · p260 Wave 4 audit `docs/audit/p260_wave_4_312_journey_audit.md` D3 + §15.7 |
| Migrations | none (spec-only) — implementation deferred to #382 W4f |
| Closes | #383 (this ADR is the deliverable) |

---

## 1. Context

### 1.1 Why this ADR exists

Three things converged at p260 Wave 4 audit close (2026-05-24):

1. **SPEC §6.1** introduced "instrumento, produto e modo de revisão" as a first-class concept: *uma mesma fonte pode gerar vários produtos* (LinkedIn post, LinkedIn Newsletter, blog/Hub article, magazine submission, governance attachment). The platform must register the **product reviewed**, not just the source file. SPEC §16.5 then ties this to QA smoke 5 (Roberto + Sarah curatorship paths) and to #382 blind-review primitives.

2. **D3 PM decision (p260 audit §15.5)** ratified: *`content_products` deve ser o artefato canônico de produto derivado; `board_items` continua como tracking operacional. Racional: uma tribo pode gerar múltiplos produtos a partir de um documento — LinkedIn, newsletter, artigo, revista, política, template. Isso não deve ficar escondido em board item.*

3. **Sequencing concern (PM 2026-05-26)**: if blind-review primitives (#382) ship before the content-product modeling lands, the blind-review surface risks coupling to `governance_documents`/`document_versions` polymorphically and needing a rework later. ADR-0099 must precede #382 so blind-review's pointer pattern is grounded.

### 1.2 What exists today (live state at p264 close)

Five surfaces touch the "derived editorial output" problem space without owning it canonically:

| Surface | Rows live | Role today | Gap |
|---|---|---|---|
| `governance_documents` + `document_versions` | 16 docs / N versions | Canonical for governed artifacts (Manual, Policy, Charters, Agreements, Templates, Editorial Guide) | NOT the right home for "LinkedIn post derived from Editorial Guide" |
| `publication_ideas` (+ `publication_series`) | 1 row total (`source_type=null`) | Designed in p95 #94 as derived-product pipeline; barely adopted in production | Polymorphic `source_type`/`source_id` text+uuid pair; `proposed_channels text[]` with no enum; no `target_instrument` discriminator; no `review_mode` |
| `publication_submissions` | 37 rows | Submission-stage tracking with `submission_target_type` enum (`pmi_global_conference`, `academic_journal`, `webinar`, `blog_post`, `linkedin_newsletter`, `other`, …) | Submission ≠ product; one product may not have a formal submission step (e.g., a LinkedIn post); FK to `board_item_id` couples operational and product surfaces |
| `board_items` (+ `peer_review_*`, `leader_review_*`, `curation_status`, `curation_review_log`) | 556 rows, ADR-0086 FSM live | Operational tracking + structured peer/leader review per Manual §4.2 | Hides product identity inside a generic operational card; cannot represent "same source → multiple products" cleanly (would require N board_items + a join concept) |
| `governance_documents.document_comments` (visibility, clause_anchor) | live in p256 M2 | Comments scoped to document versions for review chain | Wrong surface for blind-review of an editorial product derived from a doc |

Today, "produce a LinkedIn post derived from the Editorial Guide" has **no canonical home**. It could be:

- a `board_item` with `curation_status` + `peer_review_*`,
- a `publication_idea` (designed for this, but unused),
- a `publication_submission` (only if the LinkedIn post is treated as a submission),
- inferred from `document_comments` activity (not modeled at all).

This split breaks (a) reporting (which products are in flight?), (b) blind-review (no canonical reviewable id), (c) evidence bundles (which artifact does the certificate cite?), and (d) semantic-layer queries (which products derive from which governance documents?).

### 1.3 Why `governance_documents` is not the right home

`governance_documents` is the canonical surface for **governed artifacts**: things ratified through approval chains with `governance_commentary` review mode (Manuals, Policies, Charters, Agreements, Templates, Editorial Guides). Two properties distinguish them from derived editorial outputs:

- **Governance artifacts have authority** — they declare rules, scope, or templates that other artifacts cite.
- **Governance artifacts go through chain ratification** — `approval_chains` + per-gate signoffs (curator → leader_awareness → submitter_acceptance → president_* → witnesses/ratifications).

Derived editorial products do **not** carry authority. A LinkedIn post about the Editorial Guide is communication output, not governance. It deserves curation (peer + leader review per ADR-0086) but **not** an approval chain. Forcing derived products into `governance_documents` would (a) pollute the chain workflow with non-governance traffic and (b) misclassify outputs in the member-facing `/governance/documents` library.

### 1.4 Why `board_items` is not the right home

`board_items` is the operational kanban surface — it tracks **work-in-progress** across teams (research, comms, partners, projects). A board item may *spawn* one or more content products, but the board item is the **task slot**, not the **product**. Per p260 D3: *`board_items` continua como tracking operacional*.

Hiding product identity inside `board_items.metadata` or extra columns creates three problems:

- Cardinality mismatch: one board_item card can spawn N products (LinkedIn + Newsletter + Blog + Magazine from one tribe paper). Modeling N products as N board_items duplicates operational state.
- Review mode mismatch: ADR-0086 already gives `board_items` peer + leader review. Adding blind-review on top mixes governance and non-governance review semantics on the same row.
- Library mismatch: members shouldn't see internal board cards; they should see published products on their own surface.

### 1.5 What this ADR is NOT

This ADR is **spec-only**. It does not ship a migration, table, or RPC. Implementation is deferred to:

- **#382 W4f** foundation migration (likely `20260805000045+` series), which is unblocked once this ADR is Accepted.
- **#314 / #310 / #314 follow-ups** for the member-facing library + admin intake surfaces of content_products (post-#382).

This ADR also does **not** redesign `publication_ideas`, `publication_submissions`, or `board_items`. It defines the canonical shape `content_products` must take when implemented, and how the three existing surfaces map onto it.

---

## 2. Decision

### 2.1 `content_products` is the canonical surface

`content_products` is the **single canonical artifact** for derived editorial outputs. Every derived content piece — LinkedIn post, LinkedIn newsletter, blog/Hub article, magazine article, journal submission, webinar abstract, video script, etc. — gets exactly one `content_products` row.

The row is the **identity** of the product. Its lifecycle (idea → drafted → under_review → approved → published → archived) is independent of its underlying operational state (which `board_item` is tracking the work, which `publication_submission` represents the formal submission).

### 2.2 Source relationship — discriminated FK, NOT polymorphic

A content product is **always derived from** something. The source is captured via **discriminated tagged FK** (NOT `source_type text + source_id uuid` polymorphism — which is the pattern `publication_ideas` uses today and which this ADR retires).

Required columns on `content_products` (canonical shape):

```text
source_kind text NOT NULL CHECK (source_kind IN (
  'governance_document_version',   -- derived from a locked document version
  'board_item',                    -- derived from an operational card (tribe paper, research output)
  'publication_idea',              -- derived from a transitional idea (rare; bridge for legacy data)
  'external',                      -- derived from an external source (interview, news, partner content)
  'none'                           -- standalone product, no prior source (rare; e.g., a one-off opinion piece)
))
source_document_version_id uuid REFERENCES public.document_versions(id) ON DELETE RESTRICT
source_board_item_id       uuid REFERENCES public.board_items(id)       ON DELETE RESTRICT
source_publication_idea_id uuid REFERENCES public.publication_ideas(id) ON DELETE RESTRICT
source_external_uri        text          -- canonical URI for external; e.g., DOI, news URL, partner asset URL
CHECK (
  (source_kind = 'governance_document_version' AND source_document_version_id IS NOT NULL
     AND source_board_item_id IS NULL AND source_publication_idea_id IS NULL AND source_external_uri IS NULL)
  OR (source_kind = 'board_item' AND source_board_item_id IS NOT NULL
        AND source_document_version_id IS NULL AND source_publication_idea_id IS NULL AND source_external_uri IS NULL)
  OR (source_kind = 'publication_idea' AND source_publication_idea_id IS NOT NULL
        AND source_document_version_id IS NULL AND source_board_item_id IS NULL AND source_external_uri IS NULL)
  OR (source_kind = 'external' AND source_external_uri IS NOT NULL
        AND source_document_version_id IS NULL AND source_board_item_id IS NULL AND source_publication_idea_id IS NULL)
  OR (source_kind = 'none'
        AND source_document_version_id IS NULL AND source_board_item_id IS NULL
        AND source_publication_idea_id IS NULL AND source_external_uri IS NULL)
)
```

**Why discriminated FK over polymorphism:**

- Each FK has referential integrity enforced by Postgres (a `governance_document_version` source cannot point at a deleted version).
- Queries that join sources can pick the right join cleanly (`LEFT JOIN document_versions ON cp.source_document_version_id = ...`) without union-or-CASE.
- Adding a new source kind is one new FK column + one CHECK branch; old data does not need backfill of a polymorphic discriminator.
- The `publication_ideas.source_type text + source_id uuid` polymorphic pair already produced operational fragility (1 row live, `source_type=null` — no integrity ever validated). This ADR retires that pattern for `content_products`.

### 2.3 Cardinality

- **One source → N products** (1:N): the Editorial Guide (one `document_version`) can spawn LinkedIn post + Newsletter + Blog + Journal submission as 4 separate `content_products` rows, each linking back via `source_document_version_id`.
- **One product → exactly one source** (N:1): exactly one of the 4 source FKs is populated per row, per the CHECK constraint above.
- **Sibling grouping** via `derived_group_id`:
  - `content_products.derived_group_id uuid REFERENCES public.content_products(id)` (self-FK, nullable).
  - The seed product of a group has `derived_group_id = id` (self-reference indicating "I am the seed"); subsequent siblings point at the seed.
  - Sibling navigation: `SELECT … FROM content_products WHERE derived_group_id = $seed_id`.
  - This avoids a separate join table while keeping cardinality explicit.

### 2.4 `target_instrument` enum

Reuse and extend the existing `submission_target_type` enum from `publication_submissions` (8 values today: `pmi_global_conference`, `pmi_chapter_event`, `academic_journal`, `academic_conference`, `webinar`, `blog_post`, `other`, `linkedin_newsletter`).

**Extensions required for `content_products`:**

```text
'linkedin_post'        -- short-form LinkedIn (distinct from newsletter)
'medium_article'       -- Medium / Substack / external blog (distinct from internal blog_post)
'youtube_video'        -- video output
'podcast_episode'      -- podcast output
'hub_article'          -- Hub-internal article (separate from external blog_post)
'magazine_article'     -- formal magazine submission (distinct from journal)
```

**Strategy:** when #382 implementation lands, rename the live enum (or create a new `content_product_instrument` enum if the name conflict matters) and migrate existing `publication_submissions.target_type` values to the unified enum. Until then, this ADR documents the full target enum as the canonical list.

The instrument list is **deliberately closed** (extension only via migration). Each instrument has a default `review_mode` (see §2.5) and a default `target_language_policy` / `target_length_policy` (advisory; can be overridden per product).

### 2.5 `review_mode` enum (NEW)

Per SPEC §6.1:

| Mode | When used | Visibility property |
|---|---|---|
| `collaborative` | LinkedIn posts, hub articles where comments encadeados help polish | All reviewers see each other's comments + the product |
| `sequential` | LinkedIn Newsletter, blog articles where editorial + curator review happens in sequence | Comments are visible to the team, but review state advances stage-by-stage |
| `independent_blind` | Magazine / journal articles where reviewer A must not see reviewer B's parecer until after they submit theirs | Each reviewer sees the product + their OWN draft parecer; siblings' pareceres revealed only after submission |
| `governance_commentary` | When a content_product IS a governance artifact (rare — only when `source_kind='none'` and target is `policy`/`template`/`manual`). Routes the product through the `approval_chains` workflow instead of curation. | Members see governance comments per `document_comments.visibility` rules |

**Default per instrument** (advisory; per-product override allowed):

```text
linkedin_post        → collaborative
linkedin_newsletter  → sequential
medium_article       → sequential
hub_article          → sequential
blog_post            → sequential
magazine_article     → independent_blind
academic_journal     → independent_blind
academic_conference  → independent_blind
pmi_global_conference→ independent_blind
pmi_chapter_event    → sequential
webinar              → collaborative
youtube_video        → collaborative
podcast_episode      → collaborative
other                → collaborative
```

### 2.6 Minimum status states

```text
'idea'         -- proposed; no draft yet
'drafted'      -- content exists somewhere (Drive doc, board_item description, inline content_html)
'under_review' -- in active curation/blind-review session
'approved'     -- curators signed off; ready to publish
'published'    -- delivered to target_instrument (DOI / URL / handle captured in publication_metadata)
'archived'     -- abandoned without publication; soft-killed (NOT a CHECK violation, NOT deleted)
```

Six states with the FSM:

```
idea → drafted → under_review → approved → published
   ↓        ↓          ↓
                  ↘ archived (terminal)
```

`under_review → drafted` is allowed (review returns; ADR-0086 already does this via `curation_status = leader_review (decision=returned)`). `published → archived` is **not** allowed; published is terminal forward; corrections issue a new product row in `archived` state and a new product targeting the same `source_*` + `target_instrument` (sibling).

### 2.7 Blind-review pointer pattern (the load-bearing decision for #382)

**Rule (mandatory):** any blind-review primitive (#382) MUST FK to `content_products.id` via a single, deterministic `content_product_id uuid` column. Blind-review **never** FKs polymorphically to a source kind.

**Why:**

- Reviewer should see "I am reviewing this product" — a single id, a single payload, deterministic. They should not need to know whether the product derives from a governance_document, a board_item, or an external interview to render the review surface.
- The product → source chain is resolved INSIDE `content_products` (via the discriminated FK described in §2.2). The blind-review reader RPC may choose to expose source identity (if mode=collaborative/sequential) or hide it (if mode=independent_blind), but the **storage anchor** is always the product id.

**Concrete contract for #382:**

```text
public.blind_review_sessions (
  id uuid PRIMARY KEY,
  content_product_id uuid NOT NULL REFERENCES public.content_products(id) ON DELETE RESTRICT,
  review_round smallint NOT NULL,
  -- … session metadata …
);

public.blind_review_assignments (
  session_id uuid NOT NULL REFERENCES public.blind_review_sessions(id) ON DELETE CASCADE,
  reviewer_member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  -- … assignment metadata …
);

public.blind_review_pareceres (
  id uuid PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES public.blind_review_sessions(id) ON DELETE CASCADE,
  reviewer_member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  parecer_body text,
  submitted_at timestamptz,
  -- … parecer fields …
);
```

`blind_review_sessions.content_product_id` is the **only** anchor. Source resolution happens via SECDEF RPC `get_content_product_for_blind_review(p_session_id uuid)` that internally walks `content_products.source_*` based on `content_products.review_mode` and visibility rules (mirror p263 W4d `get_governance_document_reader` pattern).

### 2.8 Library / governance differentiation

Two member-facing surfaces, two distinct routes, two distinct reader RPCs:

| Surface | Route (PT canonical) | Reader RPC | Lists |
|---|---|---|---|
| Governance library | `/governance/documents` | `list_governance_library` (p256 M3) + `get_governance_document_reader` (p263 W4d + p264 W4e curator bypass) | `governance_documents` (Manuals, Policies, Charters, Agreements, Templates, Editorial Guides) |
| Content products library (NEW) | `/content/products` (or `/products`, TBD per UX leader) | `list_content_products` + `get_content_product_reader` (deferred to #382 implementation) | `content_products` (LinkedIn posts, articles, journal/conference submissions, etc.) |

**Cross-link:** when a content product has `source_kind = 'governance_document_version'`, its reader payload may include a back-reference to the governance document (e.g., "this LinkedIn post is derived from Editorial Guide v2.0"). The governance reader does NOT proactively list derived products (separation of concerns; that becomes a sidebar feature later if PM ratifies).

**MCP semantic layer** reads both surfaces independently (mirroring p222 `get_my_context` / `search_nucleo_knowledge` pattern). A single semantic query can return both a governance document and its derived products if the user's intent matches.

### 2.9 Evidence and certificates

Future evidence bundles (#311 Wave 6) and content-output certificates can anchor on `content_products.id` instead of (or in addition to) `document_versions.id`. This is **out of scope for this ADR** — the relevant decision is recorded here: `content_products.id` is a stable, citable artifact id that #311 evidence bundles MAY reference once that work begins.

---

## 3. Consequences

### 3.1 Positive

- **Blind-review (#382) ships with a clean FK contract**: one `content_product_id` per session — no polymorphism at the review surface.
- **Reporting unification**: "which products are in flight?" becomes one query against `content_products` instead of three (publication_ideas + publication_submissions + curation board_items).
- **Semantic layer (#280-class) gains a stable artifact id** for derived content, separating concerns from `governance_documents`.
- **Member surfaces stay clean**: `/governance/documents` lists governed artifacts only; `/content/products` lists editorial outputs.
- **Source integrity is FK-enforced** for the common cases (document_version + board_item + publication_idea); external + none use sentinels (URI text or all-null) with CHECK enforcement.
- **Sibling navigation is canonical**: `derived_group_id` is a self-FK, not a string convention.

### 3.2 Negative / Risks

- **One more table to maintain** (when #382 lands). Adds modeling surface that didn't exist before.
- **`publication_ideas` either migrates or stays as a legacy sibling**. With 1 row live + `source_type=null`, the cheap path is to drop or rename — but the orchestrator RPCs (`fork_blog_orchestrator`, `fork_newsletter_orchestrator`, `fork_idea_to_channel`) reference it. Decision in #382 implementation: either (a) repurpose `publication_ideas → content_products` via ALTER (preserves orchestrator FKs), or (b) ship new `content_products` and migrate the orchestrators to point at it. Both are tractable.
- **`publication_submissions` becomes a sub-shape of `content_products`** for products that reach formal submission (status `published` with `target_instrument IN ('academic_journal','academic_conference','pmi_*','magazine_article')`). #382 must decide whether `publication_submissions` becomes a 1:1 child table linked by `content_product_id`, or whether its data migrates into `content_products.publication_metadata jsonb`. **Recommended:** keep `publication_submissions` as a child table (preserves the 37 live rows + the per-submission lifecycle dates `submission_date / review_deadline / acceptance_date / presentation_date`), add `publication_submissions.content_product_id uuid NOT NULL` as the canonical link.
- **`board_items` curation fields stay** (ADR-0086 contract preserved). A new column `board_items.content_product_id uuid REFERENCES content_products(id) ON DELETE SET NULL` becomes the operational ↔ product bridge. A board_item can track work for at most ONE content product directly; sibling products spawn additional board_items (one per product, mirroring how a tribe paper today spawns N submissions).
- **Migration is non-trivial** when #382 ships. Realistic phasing: (i) create `content_products` empty; (ii) backfill from `publication_submissions` via 1:1 stub products; (iii) wire blind-review to point at content_products; (iv) extend admin intake UI; (v) member-facing library. Each phase is a separate migration.

### 3.3 Sequencing implications

- **#382 W4f blind-review primitives** now starts with the `content_product_id` FK contract instead of a polymorphic source FK. This is the load-bearing reason this ADR ships before #382 (PM 2026-05-26 ratification).
- **#314 Wave 3 (member library)** completed in p258 — no rework on the existing library. New `/content/products` route is additive.
- **#310 Wave 2 (admin intake)** completed in p258 for governance documents. A separate admin intake for content_products ships post-#382 (separate UX flow; reuses no governance intake code).
- **#311 / #308 / #181 Wave 6 (evidence + certificates)** gains an additional anchor option (content_product_id) but no rework — #311 was already deferred post-v1.
- **#301 Wave 5 (Drive grants)** — Drive permission lifecycle for content products mirrors the governance pattern but uses `content_products.id` as the lineage anchor. Out of scope here.
- **#280-class semantic layer** gains a third surface tool (`list_content_products` / `get_content_product_reader`) when #382 ships. Out of scope here.

---

## 4. Alternatives considered

### 4.1 Alternative A — Extend `board_items` with `target_instrument` + `review_mode` (no new table)

**Shape:** add columns to `board_items` so a board_item *is* the product.

**Pros:** zero new tables; reuses ADR-0086 review FSM; orchestrators don't change.

**Cons:**

- Cardinality breaks for "one source → N products" (would force N board_items + a join concept anyway).
- Library surfaces conflate work-in-progress with finished products.
- Blind-review on board_items pollutes the operational kanban semantics.
- p260 audit D3 explicitly rejected this: *`board_items` continua como tracking operacional. Isso não deve ficar escondido em board item.*

**Rejected.** Operational and product surfaces stay disjoint.

### 4.2 Alternative B — Repurpose `publication_ideas` as `content_products` (rename + extend)

**Shape:** ALTER TABLE rename; add `target_instrument`, `review_mode`, discriminated source FK columns; drop the polymorphic `source_type` + `source_id`; preserve orchestrator RPC behavior with renamed references.

**Pros:** preserves orchestrator RPCs; only 1 live row to migrate; minimum schema churn.

**Cons:**

- The name `publication_ideas` ≠ `content_products` semantically — "idea" is a state, "product" is the artifact. Renaming a table is invasive across MCP / contract tests / docs.
- The 1 row + null source_type indicates the existing surface was a stillborn attempt; better to design the canonical surface fresh and migrate the orchestrators to it.
- The orchestrator RPCs (`fork_blog_orchestrator`, `fork_newsletter_orchestrator`) were designed against the polymorphic shape; they need updating either way.

**Conditionally rejected.** Decision deferred to #382 implementation: either rename + extend OR create new + migrate. Both are acceptable per this ADR.

### 4.3 Alternative C — VIEW over (`publication_ideas` ∪ `board_items` ∪ `publication_submissions`)

**Shape:** `CREATE VIEW content_products AS SELECT … FROM publication_ideas UNION ALL SELECT … FROM board_items WHERE curation_status IS NOT NULL UNION ALL SELECT … FROM publication_submissions;`

**Pros:** zero schema change; queries can read a unified surface.

**Cons:**

- VIEWS cannot have FK targets — blind-review's `content_product_id FK` would have nothing to reference (PostgreSQL forbids FKs to views).
- INSERT/UPDATE on a UNION view requires INSTEAD OF triggers; complex and error-prone.
- Source resolution still polymorphic at the UNDERLYING table layer — the view hides it but doesn't solve the problem #382 cares about.

**Rejected.** Views are read-only optimization for cross-surface queries, not a substitute for a canonical table when downstream FKs are required.

### 4.4 Alternative D — Keep the status quo (no canonical surface)

**Shape:** continue using whichever table fits ad-hoc per use case.

**Cons:** the original problem statement (SPEC §6.1 + p260 D3 + #382 sequencing) is the reason this ADR exists. Status quo fails reporting, blind-review, and semantic-layer use cases.

**Rejected.**

---

## 5. Decision summary (one-page)

| Question | Decision |
|---|---|
| Is `content_products` a new canonical surface? | **Yes.** It owns the identity of derived editorial outputs. |
| Does it replace `governance_documents`? | **No.** Disjoint surface. Governance artifacts stay in `governance_documents`. |
| Does it replace `board_items`? | **No.** `board_items` remains operational. New optional FK `board_items.content_product_id` bridges the two surfaces. |
| Does it replace `publication_submissions`? | **No.** `publication_submissions` becomes a child surface of `content_products` (link via new `publication_submissions.content_product_id NOT NULL`). The 37 live submission rows get backfilled with stub products in the #382 migration. |
| What about `publication_ideas`? | Two acceptable paths in #382 implementation: (a) rename + extend (cheapest given 1 live row); (b) create new `content_products` and migrate orchestrators. Either is fine; #382 picks. |
| Cardinality? | 1 source → N products (1:N). 1 product → 1 source (N:1 via discriminated FK + CHECK). Siblings grouped via `derived_group_id` self-FK. |
| Source modeling? | Discriminated tagged FK (5 source kinds, 4 FK columns + 1 URI + CHECK). NOT polymorphic (no source_type text + source_id uuid). |
| Target instrument? | Closed enum. Extended from `submission_target_type` to add `linkedin_post`, `medium_article`, `youtube_video`, `podcast_episode`, `hub_article`, `magazine_article`. Extension only via migration. |
| Review mode? | New enum: `collaborative` / `sequential` / `independent_blind` / `governance_commentary`. Default per instrument. Per-product override allowed. |
| States? | 6: `idea` → `drafted` → `under_review` → `approved` → `published`; or `archived` (terminal). `under_review → drafted` allowed (returns). `published → archived` NOT allowed (corrections issue new product row). |
| Blind-review pointer? | Single FK `content_product_id` on all blind-review tables. Source identity resolved inside `content_products`. No polymorphism at the review surface. |
| Library route? | `/content/products` (new). Disjoint from `/governance/documents`. Optional cross-link from product → source governance doc. |
| Evidence / certificate anchor? | `content_products.id` is a citable artifact id. Wave 6 evidence bundles may reference it once that work starts. |
| Implementation timing? | Deferred to #382 W4f. This ADR is the contract; #382 ships the foundation migration + new RPCs. |

---

## 6. Implementation guidance (for #382 W4f)

When #382 ships its foundation migration, it MUST:

1. Create `public.content_products` per §2.2 + §2.3 + §2.4 + §2.5 + §2.6 column shapes.
2. Add `board_items.content_product_id uuid REFERENCES public.content_products(id) ON DELETE SET NULL` (operational ↔ product bridge; nullable for board_items that don't track a product).
3. Add `publication_submissions.content_product_id uuid NOT NULL REFERENCES public.content_products(id) ON DELETE RESTRICT` (every submission must trace to a product).
4. Backfill the 37 live `publication_submissions` with 1:1 stub `content_products` rows (status='published' if `acceptance_date IS NOT NULL`, else 'under_review'; source_kind='external' with `source_external_uri = COALESCE(doi_or_url, target_url, target_name)`).
5. Decide `publication_ideas` fate: either (a) rename to `content_products` (option B in §4.2) — IF chosen, the schema in §2 directly applies; or (b) keep `publication_ideas` as a legacy sibling and migrate the orchestrators to point at `content_products`.
6. SECDEF reader: `get_content_product_reader(p_product_id uuid) RETURNS jsonb` mirroring p263 W4d + p264 W4e patterns (active-membership gate + visibility + status gate + curator-assigned bypass for review context).
7. SECDEF list: `list_content_products(p_filters jsonb)` mirroring `list_governance_library` shape.
8. Forward-defense contract tests asserting CHECK semantics (exactly one source FK populated per source_kind), enum closed sets, status FSM transitions, sibling self-FK integrity.
9. Update `check_schema_invariants()` with at least one new invariant (e.g., `W_content_product_source_integrity` — every `content_products` row must satisfy the source CHECK; redundant with the CHECK constraint but mirrors V/V'/T pattern for ratchet visibility).

When #382 ships its blind-review primitives, it MUST:

10. Create `blind_review_sessions`, `blind_review_assignments`, `blind_review_pareceres` (or equivalent shapes) all FK to `content_products.id`. **Never** FK to source kind directly.
11. Honor `content_products.review_mode = 'independent_blind'` semantics in the reader RPC (hide sibling pareceres until submission).

---

## 7. References

- SPEC: `docs/specs/SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md` §6.1 (instrumento, produto, modo de revisão) + §16.5 (QA smoke matrix) + §19.5 (Wave 1b carries) + §15.7 (sequência técnica sugerida)
- p260 audit: `docs/audit/p260_wave_4_312_journey_audit.md` §3 + §15.5 D3 PM decision verbatim + §15.7 sequence + §17 carries
- Issue: #383 (this ADR closes it); #382 (consumer); #312 (audit umbrella, stays open); #315 (Governance Documents v1 umbrella, stays open)
- Prior ADRs: ADR-0086 (curation pipeline) · ADR-0078 (external reviewer) · ADR-0093 (RPC façade) · ADR-0087 (`curate_content`) · ADR-0041 (`participate_in_governance_review`)
- PM dispatch: 2026-05-26 (sessão p264 close + #383 dispatch) — sequencing rationale (ADR-0099 before #382 to ground the blind-review FK contract)
