# ADR-0092: Document permissions V4 sweep (ADR-0087 carry)

| Field | Value |
|---|---|
| Status | Proposed |
| Date | 2026-05-19 (sessão p202, issue #166 scaffold) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | (none yet — to land in dedicated implementation session) |
| Cross-ref | [ADR-0011](./ADR-0011-v4-auth-pattern-rpcs-mcp.md) (V4 auth canonical) · [ADR-0087](./ADR-0087-v4-curate-content-action.md) (V4 curate_content) · `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #29 · Migration `20260721000000_p201_gap_200_a_v4_curator_rls_swap.sql` |
| Closes (proposed) | Audit item #29 + ADR-0087 §5 doc permissions carry |

## Context

ADR-0087 (V4 `curate_content` action) swept 14 functions from V3 designation-based gates (`'curator' = ANY(designations)`) to V4 `can_by_member` calls. Three `document_*` RLS policies were **explicitly deferred** and tracked separately in audit item #29:

> Migration `20260721000000_p201_gap_200_a_v4_curator_rls_swap.sql` explicitly preserves three `document_*` policies with `operational_role IN ('manager','deputy_manager','tribe_leader')` and `chapter_board` / `chapter_witness` designation checks, marked as out of scope for ADR-0087 and "tracked separately".

The reason for the deferral was scope discipline: ADR-0087 was about the `curate_content` action sweep, while the document-permission gates additionally encode **chapter-board governance** (witness signatures, chapter director approval) which has its own authority chain not yet codified in V4 actions.

V4 chapter-board authority does exist as designations (`chapter_board`, `chapter_witness`) and can flow through `can_by_member` once the corresponding V4 actions are seeded. The carry exists because that seeding work wasn't done in p200.

## Decision (proposed)

### §1. Identify the three deferred policies

The implementation session must enumerate exactly which `document_*` policies have V3 carry:

```sql
SELECT schemaname, tablename, policyname, qual, with_check
FROM pg_policies
WHERE tablename LIKE 'document_%'
  AND (qual::text LIKE '%operational_role%' OR qual::text LIKE '%chapter_board%' OR qual::text LIKE '%chapter_witness%');
```

Expected: 3 policies on `governance_documents`, `document_versions`, and one related (e.g., `document_comments` or `document_signatures`).

### §2. Map V3 gates to V4 actions

For each V3 gate found, determine the V4 equivalent action and seed `engagement_kind_permissions` if not yet present:

| V3 gate clause | V4 action (proposed) | Notes |
|---|---|---|
| `operational_role IN ('manager','deputy_manager','tribe_leader') AND chapter_id = ...` | `view_governance_document` (read) / `edit_governance_document` (write) — scoped to chapter | New actions or reuse `view_pii`-style gates |
| `'chapter_board' = ANY(designations)` | `sign_governance_document_as_board` | Sign action specific |
| `'chapter_witness' = ANY(designations)` | `sign_governance_document_as_witness` | Sign action specific |

Names are illustrative — the implementation session picks the final action names that fit `engagement_kind_permissions` conventions.

### §3. Seed actions in `engagement_kind_permissions`

For each new action, INSERT rows per engagement kind that should grant it. Example (subject to revision):

```sql
INSERT INTO engagement_kind_permissions (kind, role, action, scope) VALUES
  ('chapter_governance', 'manager',          'view_governance_document', 'chapter'),
  ('chapter_governance', 'deputy_manager',   'view_governance_document', 'chapter'),
  ('chapter_governance', 'tribe_leader',     'view_governance_document', 'chapter'),
  ('chapter_governance', 'board_member',     'sign_governance_document_as_board', 'chapter'),
  ('chapter_governance', 'witness',          'sign_governance_document_as_witness', 'chapter');
```

(Exact kind/role values depend on current engagement schema — implementation session audits.)

### §4. Swap policies to V4

For each identified policy:

1. Create the V4 replacement policy (referencing `can_by_member(member_id, 'view_governance_document', 'chapter:'||chapter_id)` or similar) with a different name.
2. Run shadow window 48-72h with both policies enabled (V4 OR V3) — confirm no access denials.
3. Smoke: simulate a chapter-board access path for each action.
4. Drop the V3 policy. The V4 policy is now the only gate.
5. Verify `mcp_usage_log` shows no new failures from the affected tools.

### §5. Acceptance criteria for the swap

- Every previous V3 access path has an equivalent V4 path.
- No `chapter_board` / `chapter_witness` user is silently denied access during shadow.
- Removing the V3 policy doesn't break any of the 22 MCP tools in the `governance` domain (see `mcp-tool-matrix.json`).

## Consequences

### Positive

- Closes the last V3 designation-based RLS in the document subsystem.
- Aligns with ADR-0087 spirit (V4 actions for fine-grained authority).
- Future chapter-board changes (new designations, new actions) only need `engagement_kind_permissions` updates, not policy rewrites.

### Negative / risk

- Three policies on governance tables — getting the swap wrong silently denies access to chapter-board signers. Shadow window is non-negotiable.
- The new actions must not collide with existing seeded actions; audit before INSERT.
- 22 governance-domain MCP tools must all be re-smoked post-swap.

### Acceptance test for future session

- [ ] List of identified V3 policies + their exact `qual`/`with_check` text captured before any change.
- [ ] V4 actions seeded; `engagement_kind_permissions` row count delta documented.
- [ ] Shadow window completed with no anomalies in `admin_audit_log` (access denied events for chapter-board users = 0).
- [ ] Each affected MCP tool re-smoked; `mcp_usage_log.success=false` count = 0 for governance domain post-swap.
- [ ] `check_schema_invariants()` 16/16 = 0 violations.
- [ ] `mcp-tool-matrix.json` regenerated; no new direct-table drift introduced.

## Rollback

For each policy swap:

- Re-create the V3 policy from the captured `pg_policies` snapshot.
- Drop the V4 policy.
- Remove the seeded actions from `engagement_kind_permissions` (cascade to dependents).

Rollback should be reversible within 24h of cutover; after that, any new V4 access patterns may make rollback partial.

## Implementation session checklist

- [ ] Identify exact 3 policies via `pg_policies` query
- [ ] Map V3 gates to V4 actions; review naming with PM
- [ ] Seed `engagement_kind_permissions`
- [ ] Migration: V4 policies (shadow mode)
- [ ] 48-72h shadow window with `admin_audit_log` monitoring
- [ ] Migration: drop V3 policies
- [ ] Re-smoke 22 governance MCP tools
- [ ] `check_schema_invariants()` 16/16 = 0 violations
- [ ] GC entry recording the V4 sweep completion
- [ ] Audit log item #29 marked RESOLVED with V4 actions referenced
- [ ] ADR-0087 §5 carry note updated to point to this ADR as resolution
