# Frontiers fixture #96 — live smoke (p259, 2026-05-25)

**Issue:** #96 (Newsletter Frontiers launch umbrella) · **Umbrella:** #315 Governance Documents v1
**Wave:** validates Wave 2 #310 admin intake + Wave 3 #314 member library end-to-end via the canonical M3 RPC path (no JSX exercised — see "Path" below).
**Author:** Vitor Maia Rodovalho (member `880f736c-3e76-4df4-9375-33575c190305`)

## Path

Live RPC invocation of `create_governance_document_intake` via Supabase MCP `execute_sql`, using the SEDIMENT-226.C JWT-injection pattern: `PERFORM set_config('request.jwt.claims', json_build_object('sub','58675a94-eb44-483b-ab7d-9f8892e4fc3c','role','authenticated','aud','authenticated','iss','p258_fixture_frontiers_96')::text, true)` inside a `WITH jwt AS (...)` CTE so the main `SELECT` evaluates `auth.uid()` to Vitor's `auth.users.id` and passes the RPC's `members.auth_id = auth.uid() AND is_active = true` gate plus `can_by_member(member_id, 'manage_event')` ladder. The wizard JSX (`DocumentIntakeWizard.tsx`) was NOT exercised — same row would result either way; PM may optionally walk through the browser modal later to capture UX evidence.

## Inputs (PM-ratified, p258 AskUserQuestion 3/3 Recommended)

| Field | Value | Source |
|---|---|---|
| `title` | `Guia Editorial Frontiers in AI & Project Mgmt` | SPEC §9 literal |
| `doc_type` | `editorial_guide` | P0-Q1 ratified |
| `author_label` | `Fabricio Costa` | SPEC §9 |
| `visibility_class` | `active_members` | SPEC §9 post-approval target |
| `description` | 701 chars (under 1000 wizard limit) — scope, tracks A/B/C, 9-stage editorial flow, declarations, CR-050/R3-C3/ADR-0021 deps, #96 anchor | drafted from #96 body + SPEC §9 ajustes |
| `proposer_ack_offline` | `false` | PM Recommended — canonical A2 path |
| `proposer_member_id` | `92d26057-5550-4f15-a3bf-b00eed5f32f9` | Fabrício Costa member.id, distinct from caller (guard satisfied) |

## RPC return value

```json
{
  "ok": true,
  "document_id": "18ec4690-4f5a-4cab-904d-451e2c7245bf",
  "status": "pending_proposer_consent",
  "acknowledgement_mode": "informational",
  "note": "Doc awaiting proposer in-app consent (pending_proposer_consent). Wave 1b will ship sign_proposer_consent RPC."
}
```

## Validation matrix (all PASS)

### 1. Row in `governance_documents`

```
id                          = 18ec4690-4f5a-4cab-904d-451e2c7245bf
doc_type                    = editorial_guide
title                       = Guia Editorial Frontiers in AI & Project Mgmt
status                      = pending_proposer_consent     ← canonical A2
visibility_class            = active_members               ← P0-Q2 + SPEC §9
acknowledgement_mode        = informational                ← A1 default for editorial_guide (override allowed=No)
organization_id             = 2b4f58ab-7c45-4170-8718-b77ee69ff906 (Núcleo IA, derived from caller)
desc_len                    = 701 chars
created_utc                 = 2026-05-25 14:22:18.553049
updated_utc                 = 2026-05-25 14:22:18.553049
current_version_id          = NULL                         ← editor will create v1 on save
current_ratified_version_id = NULL                         ← no chain yet
approved_at                 = NULL                         ← not approved
closing_gate_signoff_id     = NULL                         ← no closing gate
effective_from              = NULL
effective_until             = NULL
required_action             = NULL                         ← V4 hook reserved (P0-Q2)
```

All-NULL chain/version/effective fields are expected for fresh intake at `pending_proposer_consent`.

### 2. `list_governance_library('{}'::jsonb)` payload (called as Vitor)

```
total_field      = 16    ← was 15 pre-fixture; +1 = our row
total_returned   = 16

Frontiers entry:
  id                          = 18ec4690-4f5a-4cab-904d-451e2c7245bf
  title                       = Guia Editorial Frontiers in AI & Project Mgmt
  status                      = pending_proposer_consent
  doc_type                    = editorial_guide
  description                 = (full 701 chars present, untruncated server-side)
  effective_from              = null
  effective_until             = null
  visibility_class            = active_members
  current_version_id          = null
  current_ratified_version_id = null
  acknowledgement_mode        = informational
  approved_at                 = null
```

**Forward-defense P0-Q8 honored**: payload contains ZERO of `file_id` / `drive_url` / `content_html` / `pdf_url`. (CI contract test in `p258-314-wave3-member-library.test.mjs` locks this regression class.)

### 3. `check_schema_invariants()` — 21/21 violation_count=0

All 21 invariants reported `violation_count=0`. Specifically relevant to this fixture:

- **V'_prime_pending_proposer_consent_no_open_chain** = 0 → our doc is in `pending_proposer_consent` and has NO row in `approval_chains` (status NOT IN ('cancelled')) — exactly the A2 design.
- **V_status_chain_coherence** = 0 → predicate scopes only on `status IN ('approved','active')`; our doc is outside that set, so doesn't apply. The 7 legacy pre-chain docs remain compliant via synthetic chains from #367 Wave 1b first leaf.
- **A1/A2/A3** (member role consistency) = 0 → no member-side drift introduced.

### 4. `admin_audit_log` — 0 rows for this doc

```
WHERE target_id = '18ec4690-4f5a-4cab-904d-451e2c7245bf'
   OR (metadata->>'document_id') = '18ec4690-4f5a-4cab-904d-451e2c7245bf'
```

returned `count=0`, `actions=null`. **Correct by design**: the RPC only writes an `admin_audit_log` row with `action='governance.proposer_attestation_offline'` when `proposer_ack_offline=true`. Our canonical `false` path skipped that branch. The `proposer_member_id` Fabrício UUID was validated (distinct from caller) but otherwise NOT persisted anywhere — it lives only in the request payload, by design.

### 5. Redirect URL (computed, not browser-tested)

The wizard JSX at `DocumentIntakeWizard.tsx:218` redirects to `${langPrefix}/admin/governance/documents/${docId}/versions/new` on RPC success. For Vitor in pt-BR (langPrefix = ''):

```
/admin/governance/documents/18ec4690-4f5a-4cab-904d-451e2c7245bf/versions/new
```

The page at `src/pages/admin/governance/documents/[docId]/versions/new.astro` mounts `DocumentVersionEditor` React island with `docId` param. The editor enforces `manage_member` capability via RPC — Vitor has `manage_member=true`, so editor opens. Non-admin members would be blocked at RLS/RPC layer (pre-existing curator-draft-access carry deferred to Wave 1b separate leaf).

### 6. Reader URL (computed)

The library card link target is `${langPrefix}/governance/document/${id}` → `/governance/document/18ec4690-4f5a-4cab-904d-451e2c7245bf`. The reader at `src/pages/governance/document/[id].astro` will attempt to load the doc + current version's `content_html`. Since `current_version_id IS NULL`, the reader will likely show the empty state ("Documento não encontrado") — this is acceptable UX for a `pending_proposer_consent` doc with no version yet. Reader hardening for this state is a pre-existing deferred carry (#258 close note, item b).

## NEW gap identified: GAP-259.A (low severity)

**Observation**: `list_governance_library` default unfiltered payload (no `p_filters.status` passed) returns ALL documents with valid `visibility_class` regardless of status — so `pending_proposer_consent` / `draft` / `withdrawn` / `revoked` ALL surface to active members in `/governance/documents` default view.

The `STATUS_FILTER_OPTIONS` in `GovernanceLibrary.tsx:69` deliberately only exposes 4 "operational" statuses in the filter dropdown:

```ts
const STATUS_FILTER_OPTIONS: Status[] = ['active', 'approved', 'under_review', 'superseded'];
```

But the default unfiltered view (when no filter is set) shows all 8 statuses, including the 4 excluded from the dropdown. After this fixture, a member browsing `/governance/documents` will see "Guia Editorial Frontiers in AI & Project Mgmt" with a `pending_proposer_consent` badge.

**Resolution options for follow-up leaf:**

| Option | Description | Trade-off |
|---|---|---|
| (a) Server-side default exclusion | Mirror dropdown in `list_governance_library` RPC body: WHERE `(v_filter_status IS NOT NULL OR gd.status IN ('active','approved','under_review','superseded'))`. Members must explicitly request unfinished statuses. | Cleanest; matches dropdown intent; one-line RPC change; needs forward-defense test. |
| (b) Client-side default | In `GovernanceLibrary.tsx`, if no status filter, send `status='active'` by default. | Limits to single status; less discoverable; doesn't address RPC contract. |
| (c) Document as intentional | Update SPEC §7 to clarify members SHOULD see all statuses; update dropdown to expose all 8. | Lowest-effort; preserves transparency; members may be confused. |

**Recommendation**: Option (a) at PM dispatch — preserves member-facing biblioteca as "ready-to-engage docs only" while keeping the RPC orthogonal to UI choices (an admin-side caller can still request `status=draft` explicitly). Defer to Wave 1b expansion sprint OR a narrow follow-up leaf.

## Carries (pre-existing, unchanged from p258 close)

| Carry | Source | Status |
|---|---|---|
| Curator-draft-access mitigation (Roberto Macêdo + Sarah Faria) | Wave 1a M2 RLS swap removed `curate_content`/`manager`/`deputy_manager` operational_role bypass; only `manage_member` is admin bypass | Wave 1b separate leaf (NOT this PR) |
| `/governance/document/[id].astro` reader hardening | Table-direct SELECT bypass; OPP-153.1 follow-up; behavior post-RLS-swap uncertain | Separate leaf to investigate + harden via SECDEF RPC if needed |
| `list_governance_library` payload extension for `depends_on` / templates | Wave 1b expansion | Deferred until concrete dependency-graph need surfaces |

## SPEC §9 acceptance criteria — honored

| SPEC §9 line | Outcome |
|---|---|
| Documento cadastrado em `governance_documents` | ✓ `18ec4690-…` |
| `doc_type = editorial_guide` (recomendação) | ✓ P0-Q1 ratified |
| Título: `Guia Editorial Frontiers in AI & Project Mgmt` | ✓ verbatim |
| Autor/proponente: Fabricio Costa | ✓ in `author_label` + Fabrício's member UUID validated as `proposer_member_id` (distinct from caller) |
| Submitter: GP/admin por intake assistido | ✓ caller = Vitor (manager + manage_event); RPC enforced |
| Status inicial: `draft` ou `under_review` | ⚠ chose `pending_proposer_consent` (A2 canonical) instead — Fabrício hasn't signed in-app yet; SPEC §9 predates A2 amendment from Wave 0 ratification. PM A2 ratificada supersedes §9 status enumeration. |
| Visibilidade pos-aprovacao: `active_members` | ✓ pre-set at intake; will apply automatically when status advances to active |
| Versao inicial: `v1.0-proposed` | ⚠ no version created yet; editor will create on first save. Wizard does NOT create a version row — it only creates the document shell. |
| Ciencia: informativa para membros ativos | ✓ `acknowledgement_mode='informational'` (A1 default for editorial_guide) |
| Dependencias | ✓ referenced in description text; `document_version_dependencies` table not in Wave 1a scope (deferred Wave 1b expansion per SPEC §19.5) |

## What this fixture does NOT do

- Does NOT close #96 (umbrella covers full launch end-to-end including 5 Gate-0 legal blockers from Claude A analysis — fixture cadastro is just one operational milestone).
- Does NOT close #315 (umbrella stays open until Wave 4 #312 ships + PM v1-vs-post-v1 cut).
- Does NOT close #312 (Wave 4 next-in-line for v1).
- Does NOT exercise the wizard JSX (PM may walk the browser modal separately).
- Does NOT create a `document_versions` row (editor's job; v1 awaits GP author action).
- Does NOT mint a `proposer_consent` signoff (Wave 1b sign_proposer_consent RPC ships that flow).
- Does NOT resolve the curator-draft-access regression (Wave 1b separate leaf).
- Does NOT resolve the reader hardening carry (separate leaf).

## Next dispatch (PM call)

1. Wave 4 #312 audit jornada (review/comment/approval persona smoke + curadoria per instrumento) — next-in-line for v1 close per SPEC §16.5 + §17.
2. GAP-259.A resolution (option a/b/c) — narrow follow-up leaf when PM dispatches.
3. Curator-draft-access mitigation (Roberto + Sarah) — Wave 1b separate leaf.
4. `/governance/document/[id]` reader hardening — separate leaf.
5. Optional: PM walks through `/admin/governance/documents` browser modal to capture wizard UX evidence (visual smoke; not blocking).
