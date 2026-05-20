# ADR-0089: `champion_criteria_catalog` CRUD + audit surface

| Field | Value |
|---|---|
| Status | Proposed |
| Date | 2026-05-19 (sessão p202, issue #166 scaffold) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | (none yet — to land in dedicated implementation session) |
| Cross-ref | [ADR-0081](./ADR-0081-gamification-config-driven-and-champions-ledger.md) (config-driven gamification + champions ledger) · [ADR-0084](./ADR-0084-showcase-champion-eligibility-not-constraint.md) (Showcase → Champion eligibility) · `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` §2.2 |
| Closes (proposed) | ADR-0081 amendment thread on champion catalog formalisation |

## Context

ADR-0081 established Champions as a manual award ledger with config-driven gamification rules. ADR-0084 codified Showcase → Champion as an **eligibility nudge, not a hard constraint** — leadership awards the champion title and Showcase appearance is a suggestion, not a requirement.

What's still missing: **the catalog of champion criteria itself has no formal CRUD surface, no audit trail, and no documented authority on who can edit it.** Adding a new champion criterion (e.g., "Most webinars hosted in cycle") today happens via direct database edit or one-shot migration. There's no consistent path between "leadership wants to recognise X" and "the new criterion appears in champion award workflows".

The roadmap §2.2 lists `champion_criteria_catalog` as a dimension table with informal semantics; this ADR formalises it.

## Decision (proposed)

### §1. Define the catalog table

If `champion_criteria_catalog` doesn't yet exist as a table (it may currently be a hardcoded list in code or a single-column lookup), promote it to a first-class table:

```sql
CREATE TABLE champion_criteria_catalog (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,            -- 'best-attendance', 'most-showcases', etc.
  display_name text NOT NULL,
  description text NOT NULL,
  category text NOT NULL CHECK (category IN ('attendance', 'production', 'community', 'leadership', 'innovation')),
  is_active boolean NOT NULL DEFAULT true,
  display_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES members(id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES members(id)
);
```

If a similar table already exists, the implementation session audits its shape and amends rather than recreates.

### §2. CRUD surface via dedicated RPCs

Three RPCs (all SECURITY DEFINER, all log to `admin_audit_log`):

- `create_champion_criterion(p_slug, p_display_name, p_description, p_category)` — insert + audit.
- `update_champion_criterion(p_id, ...)` — partial update + audit (capture before/after diff).
- `archive_champion_criterion(p_id)` — sets `is_active = false`, never DELETE. Preserves historical award references.

All three gated by `can_by_member(p_member_id, 'manage_champion_catalog')` (new action) — see §3 for authority.

### §3. Authority — who can edit

PM Open Question Q2 in `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` §6 is the canonical decision point.

Recommended baseline (subject to PM ratification):

- **Read** (`list_champion_criteria` RPC): all authenticated members.
- **Write** (create/update/archive): `committee_coordinator × {coordinator, leader}` (mirror of ADR-0087 `curate_content` pattern) **PLUS** `manage_platform` (superadmin / GP).
- **NOT** editable by individual `tribe_leader` or `chapter_board` — keeps the catalog organisation-wide, not initiative-scoped.

The PM decision determines whether the new action is `manage_champion_catalog` (catalog-specific) or reuses `curate_content` (broader). Both are valid; the trade-off is naming clarity vs catalog of actions in `engagement_kind_permissions`.

### §4. Audit + history

Every CRUD on the catalog appends a row to `admin_audit_log` with:
- `actor_id` (the member making the change)
- `target_table = 'champion_criteria_catalog'`
- `target_id` (the criterion UUID)
- `action` ('create' | 'update' | 'archive')
- `before` / `after` JSONB diff (for update only)

Champion awards already referencing the criterion stay valid even if the criterion is later archived — `is_active = false` only hides it from new-award workflows.

### §5. Migration of any hardcoded criteria in code

If `nucleo-mcp/index.ts` or any RPC has hardcoded champion categories or criteria strings, the implementation session audits and migrates them to read from the catalog. The MCP `mcp-tool-matrix.json` is the inventory used for this audit.

## Consequences

### Positive

- Catalog becomes self-documenting: a query to `champion_criteria_catalog` shows all current criteria.
- Audit trail closes governance gap (who added/changed what, when).
- Future internationalisation possible (description/display_name can become i18n keys).
- Decouples catalog evolution from code releases — leadership can add a criterion mid-cycle without a deploy.

### Negative / risk

- One more table to migrate; one more set of policies/RLS to maintain.
- If hardcoded strings exist in code, the migration is wider than the schema work suggests.
- New action `manage_champion_catalog` adds to the `engagement_kind_permissions` seed surface; ensure no overlap with `manage_member` or `manage_event`.

### Acceptance test for future session

- [ ] Catalog table exists with at least the criteria currently used by Champion awards (no orphan award rows).
- [ ] Three CRUD RPCs return correct ok/err envelopes and respect the `can_by_member` gate.
- [ ] `admin_audit_log` rows appear for one create + one update + one archive in a synthetic test.
- [ ] If any hardcoded criterion string existed in `nucleo-mcp/index.ts`, it's been replaced by a catalog read; `mcp-tool-matrix.json` shows `champion_criteria_catalog` in the table list of the relevant tool(s).
- [ ] `check_schema_invariants()` 16/16 = 0 violations post-migration.

## Rollback

- Drop the three RPCs; drop the new action from `engagement_kind_permissions`.
- The catalog table can stay (it's just data) — leaving it untouched preserves audit trail.
- If migration replaced hardcoded strings, re-introduce them as a rollback step in the implementation session's revert plan.

## Implementation session checklist

- [ ] PM ratification of Q2 (authority for catalog edit)
- [ ] Schema audit: does `champion_criteria_catalog` already exist? If yes, amend not recreate
- [ ] Migration with backfill of existing criteria
- [ ] Three RPCs + `engagement_kind_permissions` seed
- [ ] Update any caller in `nucleo-mcp/index.ts`
- [ ] GC entry recording the catalog as canonical source
- [ ] Audit log: append a "promotion" entry noting hardcoded→catalog transition
