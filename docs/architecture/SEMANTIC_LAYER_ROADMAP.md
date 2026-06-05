# Semantic Layer Roadmap — Núcleo IA & GP

**Owner:** Vitor Maia Rodovalho (GP)
**Status:** Adopted (p202, 2026-05-19) — issue #166
**Effort:** Roadmap-only; implementation triggers separate sessions per ADR
**Cross-refs:** ADR-0011 (V4 auth), ADR-0012 (schema consolidation), ADR-0015 (tribe bridge), ADR-0080 (V4 engagement canonical), ADR-0085 (cross-init metric scoping), ADR-0087 (V4 curate_content), `docs/reference/MCP_TOOL_MATRIX.md` (293-tool matrix)

---

## 1. Why this exists

The platform's domain model is healthy at runtime (`check_schema_invariants()` 16/16 = 0 violations, 293 MCP tools live, 0 `mcp_usage_log` failures last 14 days) but the **semantic contracts that bind MCP tools to facts/dimensions/snapshots are still mostly implicit**. The MCP audit p201 + the 293-tool matrix shipped in #162 expose three recurring drift classes:

1. **Direct-table-access drift** — 24 MCP tools call `sb.from("...")` instead of an RPC envelope (top tables: `members` 5, `board_items` 4, `project_boards` 3, `events` 3). When the underlying table mutates (column rename, new constraint, RLS swap), the failure is HTTP 200 with garbage in the JSON payload — invisible to dashboards.
2. **Missing scoping columns on facts** — `gamification_points` has no `initiative_id`, so cross-initiative XP comparison in `exec_cross_initiative_comparison` (ADR-0085) must use cohort-scoping (members-of-initiative XP) instead of strict event-scoping. Same shape may exist in adjacent facts (TBD audit).
3. **V3→V4 authority carries** — `document_*` RLS policies still gate on `operational_role IN ('manager','deputy_manager','tribe_leader')` (carry from ADR-0087 sweep); designation-based gates for `chapter_board`/`chapter_witness` co-exist with `can_by_member()` V4 routes. The two model interplay is not formally documented.

This roadmap turns those drifts into a **prioritised work-list with explicit ADRs**. Each P1 item gets a scaffold ADR (Proposed status) in this PR; ratification + implementation each trigger their own session.

---

## 2. Inventory

### 2.1 Facts (high-volume, event-shaped)

| Fact table | Grain | Scoping columns (current) | Missing scoping | Drift risk |
|---|---|---|---|---|
| `events` | one row per scheduled event instance | `initiative_id`, `cycle_id`, `event_date`, `status` | — | Low (V4 canonical) |
| `attendance` | (member, event) pair | event → `initiative_id` via JOIN | — | Low |
| `gamification_points` | one row per XP grant | `member_id`, `cycle_id`, `rule_id`, `event_id` (optional), `awarded_at` | **`initiative_id`** (when grant is initiative-scoped vs global) | **MEDIUM** — see `ADR-0088` |
| `mcp_usage_log` | one row per tool call | `tool_name`, `member_id`, `success`, `error`, `started_at` | — | Low (informational only) |
| `card_lifecycle_events` / `board_lifecycle_events` | one row per state change | `card_id`/`board_item_id`, `event_type`, `actor_id` | — | Low (V4 via ADR-0019) |

### 2.2 Dimensions (slowly-changing)

| Dimension | Purpose | V4 status |
|---|---|---|
| `members` | active person snapshot | V4 — bridges via `engagements` (ADR-0006) |
| `persons` | identity primitive | V4 canonical (ADR-0006) |
| `engagements` | N:N person ↔ initiative ↔ role | V4 canonical (ADR-0080) |
| `initiatives` | all org units (research_tribe / committee / workgroup / etc.) | V4 canonical (ADR-0005, ADR-0009) |
| `cycles` | annual operating cycle | V4 canonical |
| `tribes` | research_tribe subset of `initiatives` | Bridge-locked (ADR-0015 — see `ADR-0091`) |
| `gamification_rules` | XP rule catalog | Config-driven (ADR-0081) |
| `champion_criteria_catalog` | champion eligibility rules | **Informal** — see `ADR-0089` |

### 2.3 Snapshots (history / point-in-time)

| Snapshot | What it freezes | V4 status |
|---|---|---|
| `member_cycle_history` | (member, cycle, role, tribe) per cycle | V4 (ADR-0001) |
| `member_status_transitions` | one row per status change with reason | V4 canonical |
| `pmi_video_screenings.transcription` | audit-grade transcription artifact | V4 canonical (ADR-0079) |
| `document_versions` | governance doc version freeze | V4 canonical (ADR-0016) |

### 2.4 Cross-cutting helpers (not yet existing)

| Helper | Purpose | Status |
|---|---|---|
| `effective_cycle_bounds(member_id)` | "is this person active in this cycle and from when to when" | **Not yet defined** — see `ADR-0090` |
| `_current_cycle()` | current cycle context | Exists, used inconsistently |
| `can_by_member(member, action, scope)` | V4 authority | Exists (ADR-0007) |

---

## 3. Drift risks (current, ranked by severity)

| Rank | Risk | Evidence | Tracked by |
|---|---|---|---|
| 1 | `gamification_points` cannot strict-scope by initiative | ADR-0085 §3 explicit limitation; cross-initiative XP misattribution possible when one person earns XP across two tribes | `ADR-0088` (P1) |
| 2 | `document_*` RLS V3 gates | Migration `20260721000000` preserves carry policies | `ADR-0092` (P1) |
| 3 | 24 direct-table MCP tools | `docs/reference/MCP_TOOL_MATRIX.md` — top tables `members`/`board_items`/`project_boards`/`events` | Item #38 (this roadmap §5) |
| 4 | `champion_criteria_catalog` semantics informal | No formal CRUD surface or audit, ad-hoc edits | `ADR-0089` (P1) |
| 5 | "Active in cycle" semantics duplicated across RPCs | Each RPC re-implements cycle filtering | `ADR-0090` (P1) |
| 6 | Tribe bridge still required in 7 tables | ADR-0015 C2 set (member_cycle_history etc.) | `ADR-0091` (P1) |
| 7 | `cycles.start_date`/`end_date` interpretation not formalised | Different RPCs use inclusive vs exclusive bounds | Subsumed by `ADR-0090` |

---

## 4. Prioritisation

### 4.1 P0 (blockers shipped in p201 already)

- ADR-0011 V4 authority canonical — ✅ Accepted
- ADR-0012 schema consolidation principles — ✅ Accepted
- ADR-0087 V4 `curate_content` action sweep — ✅ Accepted (p200), but `document_*` carry remains → P1 (`ADR-0092`)

### 4.2 P1 (scaffold ADRs land in this PR)

| ADR | Title | Effort | Trigger |
|---|---|---|---|
| `ADR-0088` | `gamification_points.initiative_id` scoping contract | M (schema + backfill + trigger + RPC update) | GAP-194.B + audit #34 |
| `ADR-0089` | `champion_criteria_catalog` CRUD + audit surface | S-M (catalog table + RPC + UI) | ADR-0081 amendment thread |
| `ADR-0090` | `effective_cycle_bounds` view/helper | S (one VIEW + grant + cross-ref) | Roadmap §3 rank 5 |
| `ADR-0091` | Tribe bridge remaining (ADR-0015 carry) | M (audit + drop plan or accept-permanent decision) | ADR-0015 C2 → C4 sequence |
| `ADR-0092` | Document permissions V4 sweep (ADR-0087 carry) | M (RLS swap + smoke + rollback) | Audit #29 + ADR-0087 carry |

Each scaffold ships with: Context, Decision (proposed), Consequences (positive + negative + risk), Acceptance test for future implementation session, Rollback.

### 4.3 P2 (next roadmap pass — not in this PR)

- Direct-table-MCP-tools triage (24 tools → encapsulate vs accept vs retire). Depends on `ADR-0088`/`0090`/`0092` being shipped (so the encapsulation targets are stable).
- MCP envelope contracts per domain (one canonical envelope shape per `member`/`board`/`event`/`selection`/etc.).
- Smoke tests per domain calling one representative tool + asserting envelope shape + zero `mcp_usage_log.success=false`.
- `nucleo-mcp/index.ts` per-domain module split (separate issue if PM wants — not strictly semantic).

### 4.4 Non-goals

- This roadmap does NOT propose merging `tribes` into `initiatives` immediately (ADR-0015 stays the canonical bridge plan; `ADR-0091` is the carry decision).
- It does NOT add a query language / view layer abstraction beyond the existing RPC pattern.
- It does NOT touch `mcp_usage_log` aggregation or analytics RPCs (out of scope per brief).

---

## 5. Cross-cutting principles (apply to every P1 ADR)

1. **Backfill before constraint.** New columns get `DEFAULT NULL` or backfill via deterministic source before any `NOT NULL`/`CHECK`/FK landing.
2. **Trigger as cache, not control.** When a new scoping column is derivable (e.g., `gamification_points.initiative_id` from `event_id → events.initiative_id`), a trigger maintains the cache; the authoritative source remains the parent.
3. **RLS swap with shadow window.** Document permissions V4 sweep keeps the V3 policy enabled in shadow mode for 48-72h before disable (ADR-0011 §4 pattern).
4. **Acceptance test before merge.** Each implementation session must include a contract test that fails before the migration and passes after.
5. **Rollback documented in migration header.** Every migration that lands as part of these ADRs has its rollback DDL inline.

---

## 6. Open questions for PM ratification

| Q | Decision needed |
|---|---|
| Q1 | Should `gamification_points.initiative_id` be NULLable forever, or eventually NOT NULL with backfill? Affects `ADR-0088` rollout window. |
| Q2 | Is `champion_criteria_catalog` editable by `committee_coordinator + leader` (V4 `curate_content` mirror) or `manage_platform`-only? Affects `ADR-0089`. |
| Q3 | Should `ADR-0091` accept the C2 tribe bridge as permanent (no further drop), or commit to C4 (drop `members.tribe_id` after engagements coverage proven 100%)? |
| Q4 | What's the deprecation horizon for V3 `document_*` policies — 1 cycle, 2 cycles, or until first chapter-board access denial reported? |

Each implementation session for the corresponding ADR must record the decision in `docs/GOVERNANCE_CHANGELOG.md`.

---

## 7. How this roadmap consumes the MCP matrix (#162 output)

`docs/reference/mcp-tool-matrix.json` is the canonical inventory of which MCP tools touch which tables/RPCs/gates. For each P1 ADR, the implementation session must:

1. Query the matrix JSON for tools touching the affected table/RPC.
2. Identify tools that need callsite updates after the migration.
3. Run `node scripts/audit-mcp-tool-matrix.mjs --runtime` post-migration to confirm drift remains 0.

Example: when `ADR-0088` lands, the matrix should show no tool listing `gamification_points` as a direct-table read except those explicitly using `initiative_id` — any new drift is a regression.

---

## 8. Closing the loop

- This roadmap is `Adopted` once PM ratifies the prioritisation (issue #166 close).
- Each P1 ADR moves from `Proposed` (scaffolded here) → `Accepted` in its own implementation session (with full Context/Decision/Consequences fleshed out and migrations landed).
- Audit log items #34, #38 (this roadmap is the resolution of the opportunity), and #29 (covered by `ADR-0092`) get closed as each corresponding ADR lands.
- P2 items get their own roadmap update once P1 is 100% landed.

---

## Appendix A — Matrix snapshot (informational, generated 2026-05-19)

| Domain | Tool count |
|---|---|
| `tribe` | 87 |
| `board` | 64 |
| `selection` | 24 |
| `governance` | 22 |
| `personal` | 20 |
| `events` | 15 |
| `health` | 14 |
| `gamification` | 12 |
| `comms` | 12 |
| `knowledge` | 11 |
| `partners` | 11 |
| `admin` | 1 |
| **Total** | **293** |

Direct-table-access ranking (top): `members` 5 · `board_items` 4 · `project_boards` 3 · `events` 3 · `initiatives` 2 · `engagements` 2 · `initiative_invitations` 2

Full data: `docs/reference/mcp-tool-matrix.json`.
