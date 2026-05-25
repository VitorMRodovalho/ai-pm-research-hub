# Wave 4 #312 journey audit — review/comment/approval/persona smoke (p260, 2026-05-25)

**Umbrella:** #315 Governance Documents v1 · **Issue:** #312 Auditoria de jornada
**Session:** p260 (next-in-line para v1 close per SPEC §16.5 + §17 + §19.5)
**Author:** Vitor Maia Rodovalho (member `880f736c-3e76-4df4-9375-33575c190305`)
**Scope-confine:** [[feedback_wave_1a_scope_confine_governance]] honored — Wave 4 = READ-ONLY audit jornada. NO MCP grants (Wave 5), NO evidence bundles (Wave 6), NO semantic dashboards (Wave 7). NO close de #312 — output é matriz + child issue plan + PM dispatch.

## 0. Pré-requisitos

| Check | State |
|---|---|
| PR #376 (p259 evidence + GAP-259.A) merged | ✓ 2026-05-25T16:11:56Z |
| main up-to-date, working tree clean | ✓ |
| p259 evidence doc readable | ✓ `docs/audit/p259_frontiers_fixture_96_live_smoke.md` |
| GAP-259.A registered as separate carry (PM Option (a) ratified) | ✓ Wave 1b separate leaf |
| `check_schema_invariants()` violation_count | 21/21 = 0 (live, this session) |
| Live corpus baseline | 16 docs (7 active + 6 under_review + 2 draft + 1 pending_proposer_consent = Frontiers fixture from p259) |

## 1. Executive Summary

### 1.1 Three blockers that surface here, none of them in Wave 4 hands

1. **Gate template coverage gap (BLOCKER for Wave 4 acceptance):** 6 of 11 doc_types have NO gate template registered in `resolve_default_gates(p_doc_type)`. Includes `editorial_guide` (Frontiers fixture from p259), `governance_guideline` (new Wave 1a M2 doc_type), `project_charter` (TAPs ativos), `manual`, `executive_summary`, `framework_reference`. Effect: `DocumentVersionEditor.tsx` line 117 sets `gatesUnsupported=true` and the lock modal is disabled. Without lock → no chain → no comments-by-clause flow exercisable end-to-end. **Wave 4 cannot smoke the editorial_guide persona path until this is closed.**
2. **Blind-review primitive missing (BLOCKER for SPEC §6.1 + §11 persona "Curador independente"):** No `review_mode` column anywhere on `governance_documents`, `document_versions`, `document_comments`, or `approval_chains`. No row-level "submitted_initial_parecer_at" guard. The drawer + RPC trust the same `participate_in_governance_review` capability for ALL reviewers, with no per-version isolation. SPEC §19.5 already DEFERRED this to Wave 1b (`document_comments` blind-review columns "for Wave 4 enforcement of invariant 20"). Wave 4 audit confirms the deferral is correct: nothing in current code can simulate independent_blind.
3. **Review-mode + instrument-aware curadoria entirely unbuilt:** No `target_instrument`, `target_language_policy`, `target_length_policy`, `derived_product_group_id`, `source_artifact_id`, or `content_products` table/column. SPEC §6.1 introduces these as **new** concepts. The current platform conflates "LinkedIn post / Newsletter / Blog / Revista" (research-output domain → `board_items` + `peer_review_log` + `leader_review_log`) with "Documento de governança / Template" (governance domain → `governance_documents` + `approval_chains`). Wave 4 audit must call this out so PM can decide architecture before any Wave 5+ implementation.

### 1.2 What works end-to-end today (smoke-validated by reading code + live corpus)

- **Intake (Wave 2 #310):** `DocumentIntakeWizard` → `create_governance_document_intake` RPC → row in `governance_documents` with correct defaults (verified p259 fixture #96).
- **Library (Wave 3 #314):** `GovernanceLibrary` → `list_governance_library` RPC → 16 cards rendered, filter dropdown exposes 4 of 8 statuses (GAP-259.A — Wave 1b ratified for fix).
- **Member reader:** `/governance/document/[id].astro` loads via table-direct SELECT (RLS-gated by class-aware policy from Wave 1a M2). Works for current_version_id NOT NULL (active docs); empty state for NULL.
- **Admin chain detail + signoff:** `/admin/governance/documents/[chainId].astro` mounts `ReviewChainIsland` with 9 gate kinds + `activeEligibleGates` ordering logic + per-gate sign actions.
- **External-reviewer comment-only:** `/governance/documents/[chainId]/index.astro` mounts same `ReviewChainIsland` with `externalReviewMode=true` — banner + no sign buttons + comment drawer enabled (p220 BUG-219.A Phase 3, 2026-05-22).
- **Clause-level comments:** `ClauseCommentDrawer` reads via `list_document_comments` (auth-scoped via `participate_in_governance_review`), submits via `create_document_comment`, resolves via `resolve_document_comment`.
- **Comment inheritance after recirculation:** `list_document_comments(p_include_prior_versions=true)` returns `is_inherited`/`from_version_id`/`from_version_label` (p93b, 2026-05-16).
- **Recirculation:** `recirculate_governance_doc` RPC (p89, 2026-05-16) + email comment count (p130 T-12, 2026-05-18).
- **Audit export:** `ChainAuditReportIsland` → `get_chain_audit_report` RPC → PDF download (timeline + signoffs + audit_log_entries + integrity_summary). RF-III/RF-V auditor-facing.
- **Member ratification gate:** `gate_kind='member_ratification'` accepts threshold=`all` with eligible_pending list. Signature_hash captured.

### 1.3 Five PM decisions that the audit reveals are needed before Wave 4 closes

| # | Decision | Default if no PM call | Affects |
|---|---|---|---|
| D1 | Are missing gate templates (6 doc_types) a Wave 1b-blocker fix OR a Wave 4-blocker fix? | Wave 1b separate leaf (matches GAP-259.A pattern) | editorial_guide + governance_guideline + project_charter + manual + executive_summary + framework_reference |
| D2 | Is "blind-review" Wave 4-blocker (SPEC §11 row 4 explicit) OR a v1-follow-up (since 5 personas can still be smoked without it)? | Wave 1b separate leaf (defer-block) | Curador independente persona; Revista/article formal instrument |
| D3 | Is the surface for "LinkedIn post / Newsletter / Blog / Magazine" — `board_items` (research-output) or new `content_products` (NEW per SPEC §19.5)? | TBD — needs ADR | Wave 4 acceptance #6 (derived products); Wave 5 MCP wrappers; #308 evidence bundle scope |
| D4 | Should `/governance/document/[id]` reader (table-direct SELECT, no SECDEF) be hardened in Wave 1b OR accepted-as-is in v1? | Wave 1b separate leaf | Reader hardening carry from p259 |
| D5 | Should the 4 "non-canonical" `visibility='public'` comment rows (legacy data from pre-adr_0041) be migrated to `curator_only`, deleted, or kept as historical anchor? | Keep as historical (acknowledge in registry) | Comment surface invariant |

### 1.4 The audit does NOT block on these — Wave 4 sign-off is independent

Wave 4 acceptance per SPEC §16.5 is **documentation + persona matrix + contract test stubs**. It does NOT require all gaps fixed in this PR. It DOES require gaps to be classified + child-issued + sequenced before PM dispatches Wave 5+.

## 2. Methodology

### 2.1 What was checked (read-only)

| Source | What I checked | Evidence |
|---|---|---|
| SPEC `docs/specs/SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md` | §3-§11 (architecture + flow + taxonomy + ack + §6.1 review modes + §11 persona smoke matrix) + §15.1-§15.8 (impact analysis) + §16.5 (Wave 4 QA lane) + §17 Onda 4 (curadoria) + §19.5 (Wave 1a footprint + Wave 1b/5-7 deferrals) | Direct read |
| Components | 9 React/Astro files in `src/components/governance/` + 11 Astro pages under `src/pages/admin/governance/` + `src/pages/governance/` | Direct read |
| RPCs (live) | `list_governance_library`, `resolve_default_gates` (× 11 doc_types), `check_schema_invariants` | curl + service-role JWT |
| Migrations | p256 M1 (org_id backfill, `20260805000035`), p256 M2 (taxonomy + RLS swap + V' invariant, `…000036`), p256 M3 (intake + library RPCs, `…000037`), p257 W1b first leaf (legacy chain backfill + V invariant, `…000038/039`), adr_0041 (9 fns V4 conversion, `20260427233000`), p89 recirculate (`20260516480000`), p195 initiative leaders governance review (`…20260709000000`), p197 peer/leader review for board_items (`20260714000000`), p200 V4 curate_content batch C+D (`20260519183955/184046`) | Direct read |
| Tables (live, service-role bypass) | `governance_documents` (16 rows × 38 columns), `document_versions` (17 columns, no `review_mode`), `document_comments` (43 rows × 12 columns, no `delivered_at`/`submitted_initial_at`), `approval_chains` (31 chains: 13 superseded + 7 active + 7 review + 4 withdrawn), `approval_signoffs` (sample shape inspected), `engagement_kind_permissions` (12 rows for `participate_in_governance_review`), `engagement_kinds` (18 kinds catalog), `members` (sample 15 names + operational_role + designations) | curl + REST |
| Issues | #171, #161, #308, #311, #310, #314, #312 body + PM comments | gh CLI |

### 2.2 What was NOT checked (and why)

| Limit | Reason | Mitigation |
|---|---|---|
| No live execute_sql / apply_migration | Supabase MCP not authenticated in this session | Read M2 migration body verbatim — confirmed 11 doc_types + 8 statuses + 5 visibility + 3 ack_mode CHECKs applied |
| No browser smoke (no Playwright run) | Wave 4 acceptance is documentation, not visual smoke | Cite component file:line for each persona path; live smoke deferred to dispatch |
| No persona-impersonation in DB (no JWT injection here) | apply_migration MCP unavailable | All persona reads cite RPC body + RLS predicate + capability ladder; no false "I clicked it" claims |
| No `_audit_list_public_function_bodies()` deep crawl | Out of audit scope (Phase C drift is ADR-0097 territory) | Phase C body-hash gate is already CI-enforced; this audit trusts current `pg_proc` matches migrations |

### 2.3 Council lens absent on purpose

PM directive at session start specified READ-ONLY audit + matrix + child-issue plan. No agent council invoked (matches scope-confine). If PM wants a council review of the proposed Wave 1b child splits (D1-D5 above), invoke `/council-review` after this PR.

## 3. Live Corpus State (2026-05-25T17:45 UTC)

### 3.1 governance_documents (16 rows)

| Dimension | Distribution |
|---|---|
| **status** | active=7 · under_review=6 · draft=2 · pending_proposer_consent=1 |
| **doc_type** | cooperation_agreement=5 · manual=2 · volunteer_term_template=2 · cooperation_addendum=1 · editorial_guide=1 · executive_summary=1 · framework_reference=1 · policy=1 · project_charter=1 · volunteer_addendum=1 |
| **visibility_class** | active_members=16 (uniform per Wave 1a M2 backfill default; Wave 2 admin UI re-classification deferred) |
| **acknowledgement_mode** | legal_signature=6 · informational=6 · binding=4 (per Wave 1a M2 A1 per-doc_type backfill) |

### 3.2 Cross-tab status × acknowledgement_mode

```
active                × binding         = 1
active                × informational   = 2
active                × legal_signature = 4
draft                 × informational   = 2
pending_proposer_…    × informational   = 1   ← p259 Frontiers fixture
under_review          × binding         = 3
under_review          × informational   = 1
under_review          × legal_signature = 2
```

### 3.3 approval_chains (31 chains)

| Chain status | Count | Note |
|---|---|---|
| superseded | 13 | Closed-history; includes 7 p257 #367 synthetic-chain backfills (legacy DocuSign-era docs anchored to invariant V via `metadata.legacy_migration=true`) |
| active | 7 | 7 docs in `gd.status='active'` have their canonical ratified chain |
| review | 7 | 6 of these match the 6 `gd.status='under_review'` docs; 1 extra (likely a recirculation chain on an already-active doc) |
| withdrawn | 4 | Historical re-drafts |

### 3.4 Six docs currently in flight

```
volunteer_addendum         Adendo Retificativo ao Termo de Adesão
framework_reference        Anexo Técnico — Plataforma Operacional
cooperation_agreement      Acordo de Cooperação Bilateral — Template
cooperation_addendum       Adendo de Propriedade Intelectual aos Acordos
policy                     Política de Governança de PI         ← CR-050!
volunteer_term_template    Termo de Adesão ao Serviço Voluntário
```

**All 6 have `current_version_id` populated → are advancing real chains.** Frontiers Guide (pending_proposer_consent) is NOT in this set — it has no chain yet (Wave 1b sign_proposer_consent RPC pending).

### 3.5 document_comments (43 rows live)

```
total = 43
by visibility = curator_only=37 · public=5 · change_notes=1
                                  ^^^^^^
  Anomaly: 5 rows have visibility='public' but adr_0041 RPC
  create_document_comment REJECTS public (validates ∈
  {curator_only, submitter_only, change_notes}). These 5 rows
  predate adr_0041 (2026-04-27) — legacy data from when the
  visibility CHECK was looser. PM D5 above: how to handle.
resolved = 21 · open = 22
```

### 3.6 engagement_kind_permissions for `participate_in_governance_review` (12 rows)

| kind | role | scope | Note |
|---|---|---|---|
| volunteer | manager | organization | GP/admin canonical |
| volunteer | deputy_manager | organization | Sub-GP/deputy admin |
| volunteer | co_gp | organization | Co-GP track |
| chapter_board | liaison | organization | Chapter representative |
| observer | reviewer | organization | **Canonical V4 curator-equivalent** (per p195 description) |
| observer | curator | organization | Explicit curator role |
| external_reviewer | reviewer | organization | **Angelina/peer-reviewer pattern (comment-only by design — no `_can_sign_gate` designation match)** |
| sponsor | sponsor | organization | Chapter presidents |
| study_group_owner | leader | organization | Initiative leaders (p195) — comment-only |
| workgroup_coordinator | coordinator | organization | Workgroup leader — comment-only |
| committee_coordinator | coordinator | organization | Committee coordinator — comment-only |
| committee_coordinator | leader | organization | Committee leader (alt naming) — comment-only |

**Key insight:** `participate_in_governance_review` is a SINGLE capability action. It does NOT differentiate "can comment" from "can sign" — that gating lives separately in `_can_sign_gate(member_id, gate_kind)` which inspects `members.designations`. The 12 rows above grant ALL comment authority; sign authority is layered on top via designations.

## 4. Surface Inventory

### 4.1 Frontend (React + Astro)

| File | Mounts | RPCs called | V4 gate read | Status |
|---|---|---|---|---|
| `src/components/governance/DocumentIntakeWizard.tsx` | Wave 2 #310 modal | `create_governance_document_intake` | `manage_event` server-side (RPC body) | ✓ Wave 2 shipped |
| `src/components/governance/DocumentVersionEditor.tsx` | Editor / lock modal | `resolve_default_gates`, `upsert_document_version`, `lock_document_version`, `compute_signer_preview` (mounted from preview button); + **TABLE-DIRECT SELECT on `governance_documents` + `document_versions`** (line 100, 123) — RLS-gated (post-M2 swap, only `manage_member` admin bypass remains; curators with `curate_content` lost direct access — carry from p259) | None client-side; RLS+RPC server | ⚠ Carry: curator-draft-access regression (Roberto, Sarah) |
| `src/components/governance/ReviewChainIsland.tsx` | `/admin/governance/documents/[chainId]` + `/governance/documents/[chainId]/index` | `get_chain_workflow_detail`, `list_document_comments`, `recirculate_governance_doc`, `sign_*` per gate_kind, `list_member_signed_gates`, `get_document_content_html`, `get_previous_version_content`, `get_next_draft_content` | `canReviewGovernance` via `can_by_member('participate_in_governance_review')` server-side; sign-button visibility derived from `eligible_pending` list in workflow detail + `activeEligibleGates()` JS function | ✓ Wave 0/1 shipped; **NO review_mode awareness** |
| `src/components/governance/ClauseCommentDrawer.tsx` | Inside ReviewChainIsland | `list_document_comments`, `create_document_comment`, `create_change_note`, `resolve_document_comment` | None client-side (uses `participate_in_governance_review` via RPC) | ✓ shipped; **NO blind-mode peer-comment hiding** |
| `src/components/governance/GovernanceLibrary.tsx` | `/governance/documents` | `list_governance_library` | None (active membership gated in RPC) | ✓ Wave 3 shipped; STATUS_FILTER_OPTIONS exposes only 4 of 8 statuses (drives GAP-259.A symptom) |
| `src/components/governance/ChainAuditReportIsland.tsx` | `/admin/governance/documents/[chainId]/audit-report` + `/governance/documents/[chainId]/audit-report` | `get_chain_audit_report` | None client-side; RPC checks `manage_member` OR auditor designation | ✓ shipped (RF-III/RF-V Conselho Fiscal PMI-GO) |
| `src/components/governance/ChainPDFExportIsland.tsx` + `ChainPDFDocument.tsx` | Same route as audit, separate export path | `get_chain_workflow_detail` + content fetch | Same as ReviewChainIsland | ✓ shipped |
| `src/components/governance/ChainDocxExportIsland.tsx` | `/admin/.../export-docx` + `/governance/.../export-docx` | Same as PDF | Same | ✓ shipped (parity with PDF) |
| `src/components/governance/VersionDiffViewer.tsx` | Inside ReviewChainIsland (Diff tab) | `get_version_diff(p_chain_id, p_version_id, p_include_content)` | None (chain-scoped) | ✓ shipped (p93b inheritance + p148 T-13.b commentsByAnchor) |
| `src/components/governance/CRDetail.tsx` + `CRList.tsx` + `CRSubmitModal.tsx` | `/admin/governance/charters` + IP-ratification | `submit_change_request`, `list_change_requests`, `review_change_request`, `approve_change_request` | RPC body gates | ✓ shipped (orthogonal: CR flow for change requests against active docs) |

### 4.2 Routes — admin shell vs member shell

| Route | Shell | Persona path | Notes |
|---|---|---|---|
| `/admin/governance/documents.astro` | AdminLayout (sidebar) | GP/admin submitter | Wave 2 #310 intake wizard mount + library tile |
| `/admin/governance/documents/[docId]/versions/new.astro` | AdminLayout | GP/admin draft editor | Mounts DocumentVersionEditor |
| `/admin/governance/documents/[chainId].astro` | AdminLayout | GP/admin chain review | Mounts ReviewChainIsland (externalReviewMode=false) |
| `/admin/governance/documents/[chainId]/audit-report.astro` | AdminLayout | GP/admin auditor | ChainAuditReportIsland |
| `/admin/governance/documents/[chainId]/export-{pdf,docx}.astro` | AdminLayout | GP/admin downloader | Chain*ExportIsland |
| `/admin/governance/charters.astro` | AdminLayout | GP/admin charter list | Initiative charters / TAPs list |
| `/admin/governance/ip-ratification.astro` | AdminLayout | GP/admin CR review | IP policy ratification flow |
| `/governance/documents/index.astro` | BaseLayout | Active member library | Wave 3 #314 GovernanceLibrary mount |
| `/governance/documents/[chainId]/index.astro` | BaseLayout | **External reviewer + non-admin governance reviewer** | ReviewChainIsland with `externalReviewMode=true` (p220 BUG-219.A Phase 3) |
| `/governance/documents/[chainId]/audit-report.astro` | BaseLayout | Non-admin auditor (if has designation) | ChainAuditReportIsland |
| `/governance/documents/[chainId]/export-{pdf,docx}.astro` | BaseLayout | Same | Chain*ExportIsland |
| `/governance/document/[id].astro` | BaseLayout | Member reader (single doc preview) | **Table-direct SELECT, no SECDEF — carry from p259** |
| `/governance/glossario.astro` | BaseLayout | Glossary | Static |
| `/governance/ip-agreement.astro` | BaseLayout | IP agreement sign flow | Member-facing CR-050 sign UI |
| `/governance/my-pending.astro` | BaseLayout | Member's pending ratifications | Calls `get_pending_ratifications` |
| `/governance/preview.astro` | BaseLayout | Generic preview shell | Older / probable retire candidate |

**Observation (positive — SPEC §16.5 acceptance criterion 5 honored):** the `/governance/documents/[chainId]/index.astro` route exists and uses the same `ReviewChainIsland` with a feature-flag prop — external reviewers (Angelina pattern) AND non-admin internal reviewers (Roberto if curator engagement is `observer × reviewer`) can enter through the **member shell** without admin sidebar friction. This is the **#171 architecture answer** for "non-admin governance participants".

### 4.3 RPC inventory — what exists vs what's missing

| Surface concern | RPC | Migration | V4 gate | Wave 4 audit verdict |
|---|---|---|---|---|
| **Intake** | `create_governance_document_intake(jsonb)` | p256 M3 `…000037` | `manage_event` | ✓ canonical; Wave 1a M3 |
| **Library (member-facing reader)** | `list_governance_library(jsonb)` | p256 M3 `…000037` | active membership; `manage_member`/`manage_platform` for `admin_only`/`audit_restricted` | ✓ canonical; GAP-259.A pending Wave 1b fix |
| **Doc shell read** | `get_document_detail(uuid)` | `20260510020000` (document_version_read_rpcs) | active membership | ✓ — but `/governance/document/[id]` does NOT consume it (table-direct) — carry |
| **Version list** | `list_document_versions(uuid)` | `20260510020000` | active membership | ✓ |
| **Version diff** | `get_version_diff(p_chain_id, p_from_version_id, p_to_version_id, p_include_content)` | `20260510080000` | chain-scoped | ✓ |
| **Editor save** | `upsert_document_version(p_document_id, p_content_html, p_content_markdown, p_version_label, p_version_id, p_notes)` | p33b IP-3d | curator/manager check (pre-V4 — needs audit if migrated to canFor) | Suspected pre-V4; verify in p260 follow-up |
| **Editor lock** | `lock_document_version(p_version_id, ...)` | IP-3d | curator/manager | Suspected pre-V4; verify |
| **Default gates per doc_type** | `resolve_default_gates(p_doc_type)` | ADR-0016 Amendment 2 | None (PII-free) | ⚠ **6 of 11 doc_types return NULL** (see §5 below) |
| **Comment create** | `create_document_comment(p_version_id, p_clause_anchor, p_body, p_visibility, p_parent_id)` | adr_0041 fn #1 `20260427233000` | `participate_in_governance_review` | ✓ V4; accepts only 3 visibilities (`public` rejected) |
| **Comment read** | `list_document_comments(p_version_id, p_include_resolved, p_include_prior_versions)` | adr_0041 fn #2 + p93b extension | `participate_in_governance_review` OR `c.author_id = caller` | ✓ V4; no review_mode filter |
| **Comment resolve** | `resolve_document_comment(p_comment_id, p_resolution_note)` | adr_0041 fn #3 | `participate_in_governance_review` (+ author or submitter) | ✓ V4 |
| **Change note (chain-scoped)** | `create_change_note(p_chain_id, p_body)` | IP-3c | ? | Suspected V3; verify |
| **Chain workflow detail** | `get_chain_workflow_detail(p_chain_id)` | p93 + p255 + ratificación cache | active membership; chain RLS | ✓ |
| **Sign actions** | `sign_curator`, `sign_leader_awareness`, `sign_submitter_acceptance`, `sign_president_go`, `sign_president_others`, `sign_chapter_witness`, `sign_member_ratification`, `sign_external_signer` (× gate_kind) + `sign_ratification_gate` (gate-kind-generic dispatcher per p204) | Various, consolidated via p204 `20260726000000` (canonical approval orchestration) | `_can_sign_gate(member_id, gate_kind)` via designations matching | ✓ V4 dispatched |
| **Recirculate** | `recirculate_governance_doc(p_chain_id, p_new_version_id, p_email_curators)` | p89 `20260516480000` + p130 T-12 `20260518120000` | `manage_member` OR submitter | ✓ |
| **Manual version 2 of N approval** | `propose_manual_version`, `confirm_manual_version`, `cancel_manual_version_proposal` | adr_0044 `20260514060000` | submitter + curator | ✓ — supplements lock_document_version for ADR-0044 path |
| **Audit report** | `get_chain_audit_report(p_chain_id)` | ip4 chunk3 `20260504060000` | `manage_member` OR audit designation | ✓ |
| **Governance change log** | `get_governance_change_log(p_filters, p_include_payload)` | `20260510030000/090000` | `manage_member` | ✓ |
| **Pending ratifications** | `get_pending_ratifications` | (existing) | active member | ✓ powers `/governance/my-pending` |
| **External reviewer carve-out** | various (see p220 `20260804000000`) | p220 BUG-219.A | active engagement of kind `external_reviewer` | ✓ shipped 2026-05-22 |
| **Submit / list / review / approve change requests** | `submit_change_request`, `list_change_requests`, `review_change_request`, `approve_change_request` | ip1 `20260429030000` + adr_0027 conversion | `manage_member` for review; member for submit | ✓ |
| **Sign proposer consent (in-app)** | **MISSING** — per p256 M3 header: "Real consent flow ships Wave 1b" | — | — | ⚠ Wave 1b first leaf NOT this PR |
| **Comment "submit initial blind parecer"** | **MISSING** — no such RPC exists | — | — | ⚠ Wave 1b deferred per SPEC §19.5 |
| **target_instrument validation / curation product authoring** | **MISSING** — no `content_products` table; no `target_instrument` column | — | — | ⚠ Wave 1b / Wave 4 implementation (per SPEC §17 Onda 4) |

### 4.4 RLS policies on governance tables (post Wave 1a M2 swap)

| Table | Policy | Predicate |
|---|---|---|
| `governance_documents` | `gd_read` (SELECT, authenticated) | class-aware: public/active_members/legal_scoped/admin_only/audit_restricted (per Wave 1a M2 `20260805000036` lines 167-193) |
| `document_versions` | `document_versions_read_published` (SELECT, authenticated) | **HARD-GATE** `locked_at IS NOT NULL OR manage_member`. **Curators with `curate_content`/`manager`/`deputy_manager` operational_role lost the bypass** — they had it pre-M2 (carry from p259, Roberto/Sarah). Mitigation: chain review uses `get_chain_workflow_detail` SECDEF. |
| `document_comments` | (RLS active; need verify if SECDEF RPCs are sole write path) | All writes go through SECDEF RPC `create_document_comment` (good); reads go through SECDEF `list_document_comments` (good) |
| `approval_chains` | (chain RLS gates reads) | `get_chain_workflow_detail` SECDEF resolves cross-table joins |
| `approval_signoffs` | (uses chain RLS chain) | Same |

### 4.5 Invariants in `check_schema_invariants()` (21 total, all 0 violations live)

| Invariant | Description |
|---|---|
| J | `governance_documents.current_version_id` must point to a locked version (unless chain in flight). **Chain-aware.** |
| K | `members.operational_role='external_signer'` must have active engagement `kind=external_signer` |
| V_prime | `status='pending_proposer_consent'` must NOT have non-cancelled chains (#315 P0-Q7 + A2) |
| V_status_chain_coherence | `status IN ('approved','active')` must have `current_ratified_chain_id NOT NULL` (#315 P0-Q6; p257 #367 backfilled 7 legacy docs with synthetic chains) |

(The other 17 invariants — A1/A2/A3/B/C/D/E/F/L/M/N/O/P/Q/R/S/T — are member/engagement/selection invariants, not governance.) Wave 1b NEXT invariant per SPEC §19.5: **invariant 20** = blind-review enforcement (one row "submitted_initial_parecer" per (chain, reviewer) precondition for visibility of peer comments).

## 5. Gate Template Coverage Matrix (by doc_type)

`resolve_default_gates(p_doc_type)` live probe:

| doc_type | Gate template | Wave 4 impact |
|---|---|---|
| manual | ❌ NULL | gatesUnsupported; locks disabled; 2 docs in corpus (1 active legacy + 1 draft R3) |
| policy | ✅ 5 gates: curator(all), leader_awareness(0), submitter_acceptance(1), president_go(1), president_others(4) | CR-050 under_review smoke OK |
| project_charter | ❌ NULL | gatesUnsupported; 1 doc active in corpus — likely legacy chain pre-templates |
| executive_summary | ❌ NULL | gatesUnsupported; 1 active doc |
| framework_reference | ❌ NULL | gatesUnsupported; 1 doc under_review!! → chain seeded via direct SQL or pre-template era |
| cooperation_agreement | ✅ 6 gates: curator(all), leader_awareness(0), submitter_acceptance(1), chapter_witness(5), president_go(1), president_others(4) | Most active docs (5/16) |
| cooperation_addendum | ✅ 6 gates (same as cooperation_agreement) | 1 active doc |
| volunteer_term_template | ✅ 5 gates: curator(all), leader_awareness(0), submitter_acceptance(1), president_go(1), volunteers_in_role_active(all) | 2 docs (1 active + 1 under_review) |
| volunteer_addendum | ✅ 5 gates (same as volunteer_term_template) | 1 doc under_review |
| **editorial_guide** | ❌ **NULL** | **Frontiers fixture from p259 — cannot advance until template added** |
| **governance_guideline** | ❌ **NULL** | New Wave 1a M2 doc_type — 0 docs yet, but next intake will hit blocker |

**Wave 4 verdict:** **5 of 11 doc_types are fully covered for end-to-end chain workflow. 6 of 11 are NOT.** The audit cannot smoke the persona path for any of those 6 doc_types beyond intake → draft. PM decision D1 (above) sets the resolution wave.

**Note:** The 4 under_review docs WITHOUT template (`framework_reference`) and the 4 active docs WITHOUT template (`manual`, `executive_summary`, `project_charter`, plus the 2 manual one) prove there's a **legacy seeding path** — chains for those docs exist but were created via direct SQL (probably during early IP-1/IP-3 era) before `resolve_default_gates` became canonical. Going forward, any NEW lock attempt via DocumentVersionEditor for these doc_types will be blocked.

## 6. Persona × Shell × Capability Matrix (SPEC §11 + §16.5)

Maps each of SPEC §11's 8 personas to: which engagement kind grants them governance review authority; which shell they enter (admin vs member); which RPCs they can/cannot call; what acceptance criterion they must satisfy.

| # | Persona (SPEC §11) | Engagement / capability | Shell entry | Can READ docs | Can COMMENT | Can SIGN | Can RECIRCULATE | Can EXPORT audit | Gap |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **GP/admin submitter** | volunteer × manager / co_gp / deputy_manager — `can('manage_member')=true` | `/admin/governance/*` | All (all visibility classes) | Yes (`participate_in_governance_review`) | Yes (multiple gates via designations) | Yes (`manage_member`) | Yes | None for governance flow itself; **gate templates missing for 6/11 doc_types blocks lock for new docs** |
| 2 | **Autor/proponente** (Fabricio-like, NOT submitter) | Any active member; declared via intake payload `author_label` + optional `proposer_member_id` | `/governance/document/[id]` reader + `/governance/documents/[chainId]` if engaged | Yes (active_members + own legal_scoped sigs) | Conditional (needs `participate_in_governance_review` engagement) | No (designations needed) | No | Conditional | **`sign_proposer_consent` RPC MISSING** (Wave 1b first leaf) — Fabrício cannot self-attest in-app yet; A2 status `pending_proposer_consent` reflects this |
| 3 | **Curador** (Roberto, Sarah) | observer × reviewer OR observer × curator → `participate_in_governance_review=true` | `/governance/documents/[chainId]` (member shell, externalReviewMode=false) — current path via `/admin/...` if they have admin sidebar access | Yes | Yes | Yes if has designation `curator` matching `_can_sign_gate('curator')` | No | Conditional (`audit` designation) | **#161 cross-cut:** UI gate on admin sidebar / sensitive surfaces should `canFor()` not `hasPermission()`. **Carry from p259:** Roberto/Sarah lost direct `document_versions` SELECT on UNLOCKED drafts (M2 RLS regression) — DocumentVersionEditor table-direct read fails; chain view OK via SECDEF |
| 4 | **Curador independente (blind)** | Same as #3 + would need `review_mode=independent_blind` enforcement | Same as #3 | Yes | **CRITICAL GAP:** Yes (can see ALL peer comments) — drawer + `list_document_comments` do NOT filter by "I haven't submitted my initial parecer yet" | Yes (same designation gate) | No | Same as #3 | **BLOCKER per SPEC §11 row 4:** no `review_mode` column on `governance_documents`/`approval_chains`; no `submitted_initial_at` on `document_comments`. Wave 1b deferred per §19.5 |
| 5 | **Revisor externo** (Angelina) | external_reviewer × reviewer → `participate_in_governance_review=true` BUT `_can_sign_gate` returns false (no curator/legal_signer/chapter_board designation) | `/governance/documents/[chainId]` with externalReviewMode=true banner | Yes | Yes | **No (correct per design)** — comment-only | No | No (no audit designation) | ✓ Correctly implemented (p220 BUG-219.A Phase 3, 2026-05-22). No gap. |
| 6 | **Líder de tribo** | volunteer × manager in tribe scope (operational_role='tribe_leader') | `/governance/document/[id]` + `/governance/my-pending` for ratifications | Yes (active_members) | **Conditional** — only if has `participate_in_governance_review` (volunteer × manager/co_gp grant this) | Conditional — `member_ratification` gate accepts threshold='all' across all members → tribe leader can sign | No | No | **#171 acceptance gap (Ana Carla case):** if tribe leader is NOT engaged as governance reviewer, they hit `not_authorized` from comment RPCs. Reader still works (active_members visibility). Acceptance #5/#7 of SPEC §16.5 OK; Acceptance #6 (no admin shell required) is OK via `/governance/...` routes. Specific bug surface needs verification in Ana Carla incident detail |
| 7 | **Membro ativo** (general) | Any active membership without special designations | `/governance/documents` library + `/governance/document/[id]` reader + `/governance/my-pending` for ratification gates of threshold='all' | Yes (active_members), No (admin_only, audit_restricted) | No (no `participate_in_governance_review`) | Conditional — only `member_ratification` (threshold=all gate) | No | No | ✓ Correctly gated. **GAP-259.A symptom:** library default view leaks `draft`/`pending_proposer_consent`/`withdrawn`/`revoked` — PM ratified Option (a) Wave 1b fix |
| 8 | **Auditor privilegiado** | manage_platform OR specific audit designation | `/admin/governance/documents/[chainId]/audit-report` OR `/governance/documents/[chainId]/audit-report` | Yes (incl. audit_restricted) | No (read-only) | No | No | Yes (`get_chain_audit_report`) | ✓ Correctly gated. Verify audit_restricted visibility class predicate (live corpus has 0 docs of this class — defer real smoke until first doc lands) |

### 6.1 Composite scoreboard

```
Persona                          Smoke Verdict
─────────────────────────────────────────────────────────────────
1. GP/admin submitter             ✓ end-to-end OK (limited by D1 gate templates)
2. Autor/proponente              ⚠ blocked at sign_proposer_consent (Wave 1b)
3. Curador (Roberto/Sarah)        ⚠ #161 cross-cut + draft-read regression
4. Curador independente (blind)   ✗ BLOCKER — no review_mode primitives
5. Revisor externo (Angelina)     ✓ comment-only path correctly wired
6. Líder de tribo (Ana Carla)     ⚠ specific bug surface — verify #171 RC
7. Membro ativo                   ✓ + GAP-259.A pending (Wave 1b)
8. Auditor privilegiado           ✓ (predicate untested live for audit_restricted)
```

**Wave 4 acceptance gates (SPEC §16.5):**
- [x] Smoke per persona produced (this doc + above table)
- [x] Routes admin vs member-facing mapped (§4.2)
- [x] Comments + recirculation + export documented end-to-end
- [x] Ack/ratification/signature cases distinguished (per acknowledgement_mode column)
- [ ] Review modes per instrument exercised — **3 of 4 modes (collaborative, sequential, governance_commentary) trivially supported by current canvas. `independent_blind` BLOCKED** (D2)
- [ ] Derived products (source → post + newsletter + blog + revista) — **NOT BUILT** (D3)

## 7. Instrument × review_mode × ack_mode × visibility_class Matrix (SPEC §6.1)

This is the core matrix that #312's PM comments demand. Each cell asks: "Does the current platform support this combination end-to-end?"

| Instrument (SPEC §6.1) | Default review_mode | Likely target acknowledgement_mode | Likely target visibility_class | Status in code (today) |
|---|---|---|---|---|
| **LinkedIn post** | collaborative | informational | public | ✗ **NOT in governance_documents domain.** This is `board_items.communication_channel='linkedin_post'` territory. `board_items.peer_review_waived=true` for collaborative articles per p197. **NO single canvas owns "LinkedIn post curation as derived product of a source artifact"** — SPEC §19.5 defers `content_products` table to Wave 1b. |
| **LinkedIn Newsletter** | sequential or collaborative | informational | public | ✗ Same — `publication_ideas.metadata.channel='newsletter'` exists (p95 #94 W2 + W3-2 fork_newsletter orchestrator `20260516680000`) but no review_mode column |
| **Blog/Hub article** | sequential | informational | active_members or public | ✗ Same — `publication_ideas.metadata.channel='blog'` exists (p95 #94 W3-1 fork_blog orchestrator `20260516670000`) but no review_mode column |
| **Revista/artigo formal** | **independent_blind** | informational | public (post-publication) | ✗ **HARDEST GAP** — `board_items.peer_review_*` rounds (p197) gate on `_can_sign_gate('peer_review')` per submission but do NOT enforce "hide other curators' parecer until I submit my initial". Closest current primitive is `selection_phase_blind_review_anti_bias` (adr_0059 `20260514290000`) — but that's for SELECTION COMMITTEE, not governance/article curation. **No reuse path.** |
| **Documento de governança** | governance_commentary (per SPEC §6.1) | varies by doc_type per A1 | varies — 4 ack_mode + 5 visibility classes | ✓ **Current platform IS this domain.** ClauseCommentDrawer + ReviewChainIsland + signoff chain = the governance_commentary mode. |
| **Template** | governance_commentary | varies | varies | ✓ Same as Documento — `volunteer_term_template` (2 docs in corpus) is a doc_type that uses this domain |

### 7.1 Surface mapping clarified — TWO domains, NOT ONE

The SPEC §6.1 list mixes domains. Audit reframes:

| Domain | Surface | review_mode owner | Personas |
|---|---|---|---|
| **Research output / publication** (LinkedIn post / Newsletter / Blog / Revista) | `board_items` + `publication_ideas` + `peer_review_log` + `leader_review_log` | NEW `content_products.review_mode` column or `board_items.review_mode` (Wave 1b deferred per SPEC §19.5 Wave 1b) | Researchers, tribe authors, peer reviewers, leader reviewers, GP, communications lead |
| **Governance instrumentation** (Manual, Policy, Charter, Cooperation Agreement, Template, Editorial Guide) | `governance_documents` + `document_versions` + `document_comments` + `approval_chains` + `approval_signoffs` | `governance_commentary` IS the only mode currently supported; if SPEC wants `independent_blind` for the governance-side curation of an Editorial Guide, that's NEW primitive | GP/admin, curator, external reviewer, chapter witness, tribe leader (acknowledgement), member ratifier, auditor |

**Wave 4 audit verdict:** PM must decide D3 (above) — **is the `target_instrument` + `review_mode` matrix a property of board_items (research output) OR governance_documents (instrumentation) OR a NEW joining table?**

Recommendation (informational, not blocking): **Two surfaces stay disjoint.** Add `review_mode` column to `board_items` (or new `content_products` table) for the research-output side; KEEP `governance_documents` review flow as governance_commentary only. The "same source → derived products" relationship lives in `derived_product_group_id` on the research-output side, NOT in governance_documents. Editorial Guide (Frontiers) is governance_commentary; the LinkedIn Newsletter it spawns is research-output.

## 8. Comment Surface Audit

### 8.1 Visibility enum drift (RPC vs Drawer vs Live)

| Layer | Visibility values |
|---|---|
| **Drawer type** (`ClauseCommentDrawer.tsx:6-7`) | `curator_only` · `submitter_only` · `change_notes` · **`public`** |
| **Drawer UI dropdown** (line 79-86 `visibilityLabel/visibilityCls`) | All 4 rendered, including `public='Público'` |
| **RPC `create_document_comment`** (adr_0041 fn #1, line 39-41) | `IF p_visibility NOT IN ('curator_only','submitter_only','change_notes')` — **rejects public** |
| **Live data** | 43 rows: 37 curator_only + 5 public + 1 change_notes — **5 public rows pre-date adr_0041 (2026-04-27)** |

**Audit verdict:** D5 above. Three resolutions possible:
- **(a) Strict deprecate (recommended):** drawer dropdown drops `public` option; UPDATE legacy rows → migrate to `curator_only` with audit row.
- **(b) Re-allow:** RPC body extended to accept `public` (add to whitelist); drawer keeps option. Justification: "public" means visible to all GD readers via active_members RLS — distinct from curator_only (only members with `participate_in_governance_review`).
- **(c) Mark historical:** Keep 5 rows; remove from drawer; document the legacy in registry.

PM call needed.

### 8.2 Comment lineage on recirculation

Confirmed working: `list_document_comments(p_include_prior_versions=true)` returns `is_inherited`, `from_version_id`, `from_version_label`. Drawer shows resolved comments with opacity-60 + lineage badge.

p93b shipped this 2026-05-16 (commit referenced inline in `ClauseCommentDrawer.tsx:92-98`). Bug-4-class reproduction (5 inherited comments invisible) is FIXED in current code.

### 8.3 Comment author visibility logic

`list_document_comments` filter (adr_0041 fn #2, line 93-96):

```sql
AND (
  v_can_see_all                  -- has participate_in_governance_review
  OR c.author_id = v_member.id   -- always sees own
)
```

So:
- GP/admin with `participate_in_governance_review` = sees all comments
- Curator (Roberto, Sarah) = sees all
- External reviewer (Angelina) = sees all (her engagement grants the capability)
- Tribe leader (Ana Carla, if engaged as observer/volunteer leader) = sees all
- Anyone WITHOUT the cap, but who authored a comment = sees only own comments

**No `independent_blind` filter.** No "submitted initial parecer" precondition. If a curator submits parecer-1 and then logs out and back in, they see parecer-1 (their own) PLUS parecer-2 from the other curator — even if the SPEC intent says they should NOT have seen parecer-2 before submitting their own.

## 9. Acknowledgement / Ratification / Signature Flow

Per SPEC §6, three levels of "evidence of attention":

| Event | acknowledgement_mode | Bloqueia vigência? | Capture |
|---|---|---|---|
| Read access | n/a | No | Optional log |
| `acknowledge` / ciência | `informational` | No, unless explicit | `approval_signoffs.signoff_type=acknowledge` |
| Ratificação | `binding` | Yes | `approval_signoffs` + snapshot |
| Assinatura legal | `legal_signature` | Yes | `approval_signoffs` + `member_document_signatures` / certificado |

**Current corpus distribution:** 6 informational + 6 legal_signature + 4 binding (16 total).

**Surface audit:**

| acknowledgement_mode | RPC for the canonical capture | Gate kind that captures it | Frontend |
|---|---|---|---|
| `informational` | `sign_ratification_gate(p_chain_id, p_gate_kind='member_ratification' OR 'leader_awareness', p_signoff_type='acknowledge', ...)` (p204 canonical) | `member_ratification` (threshold=all) OR `leader_awareness` (threshold=0 informativo) | `/governance/my-pending` + ReviewChainIsland sign button |
| `binding` | Same RPC, threshold=all required | `member_ratification` | `/governance/my-pending` |
| `legal_signature` | Same RPC + `member_document_signatures` row (CR-050 / IP agreement flow lives at `/governance/ip-agreement.astro` for specific case) | `chapter_witness` (5), `president_go` (1), `president_others` (4), `external_signer` if engaged | ReviewChainIsland for chains; ip-agreement.astro for one-off CR-050 flow |

**Wave 4 verdict:** Three modes are **distinct in column + chain config**; capture happens via `approval_signoffs.signoff_type` enum (`acknowledge` for informational/binding, gate-specific for legal). **No code conflates them.** ✓ acceptance criterion 4 of §16.5 satisfied.

## 10. Gap Inventory (Wave-classified)

### 10.1 v1 must-have (cannot ship #315 without these)

| Gap | Severity | Resolution | Wave |
|---|---|---|---|
| Gate templates for 6 doc_types | high | Extend `resolve_default_gates(p_doc_type)` body with CASE for editorial_guide, governance_guideline, project_charter, manual, executive_summary, framework_reference | Wave 1b separate leaf |
| `sign_proposer_consent` RPC | high | New SECDEF RPC: gates on caller=proposer_member_id; inserts proposer_consent signoff; transitions doc `pending_proposer_consent → draft` | Wave 1b first leaf (next dispatch after this audit) |
| GAP-259.A library default unfiltered status | medium | PM Option (a) ratified — server-side default exclusion of `draft`/`pending_proposer_consent`/`withdrawn`/`revoked` in `list_governance_library` | Wave 1b separate leaf |
| `/governance/document/[id]` reader hardening (SECDEF) | medium | Replace table-direct SELECT with new `get_member_governance_doc(p_doc_id)` SECDEF RPC; rely on class-aware visibility computed server-side | Wave 1b separate leaf |
| Curator draft-read regression (Roberto/Sarah/curate_content) | medium | New policy `document_versions_read_unlocked_curator` OR new SECDEF `get_unlocked_draft_for_curator` | Wave 1b separate leaf |

### 10.2 v1 follow-up (can ship #315 with this in v1.1)

| Gap | Severity | Resolution | Wave |
|---|---|---|---|
| Comment visibility legacy `public` rows | low | PM D5 decision; if (a) strict, write migration to UPDATE 5 rows + audit | follow-up after PM decision |
| Comment visibility drawer drift (4 in UI vs 3 in RPC) | low | Drawer drops `public` option from dropdown to match RPC; OR RPC adds `public` if D5 picks (b) | follow-up after PM decision |
| `audit_restricted` visibility class smoke (live corpus has 0 docs of this class) | low | Add 1 fixture doc OR ratify deferral until first such doc lands | follow-up |
| Editor RPCs V4 alignment audit (`upsert_document_version`, `lock_document_version`, `create_change_note`) — likely pre-V4 | medium | Inspect bodies; if `manage_member` not used, migrate; #161 cross-cut | follow-up (parallel #161) |

### 10.3 Wave 1b / Wave 4 (NEXT spec onda) implementation

| Gap | Severity | Resolution | Wave |
|---|---|---|---|
| `review_mode` column + `submitted_initial_parecer_at` on document_comments | high | New M-W4-A1 migration: ALTER governance_documents ADD COLUMN review_mode text; ALTER document_comments ADD COLUMN submitted_initial_parecer_at timestamptz; rewrite `list_document_comments` to filter peer comments when review_mode=independent_blind AND caller hasn't submitted | Wave 1b document_comments blind columns (SPEC §19.5 explicit) → SPEC §17 Onda 4 first item |
| `target_instrument` + derived product surface | high | New `content_products` table OR `board_items.metadata.target_instrument` JSON path — PM D3 architecture call needed | SPEC §17 Onda 4 |
| LinkedIn size/language pre-curation validation | medium | New validator RPC OR client-side check in submission UI | SPEC §17 Onda 4 |
| Release/consolidação de pareceres (blind → visible) | medium | RPC `release_blind_reviews(p_chain_id)` flips visibility for all peers in chain after threshold | SPEC §17 Onda 4 |

### 10.4 Wave 5 (MCP/API) — DO NOT pull into Wave 4

| Gap | Wave | Reason |
|---|---|---|
| `create_governance_document_intake` MCP tool | 5 | Per SPEC §17 Onda 5 acceptance criterion 1 |
| `list_governance_library` MCP tool | 5 | Per SPEC §17 Onda 5 acceptance criterion 2 |
| Drive metadata/grants per #301 | 5 | Per SPEC §17 Onda 5 |
| Per-persona notification routing audit | 5 | Per SPEC §17 Onda 5 acceptance criterion 4 |

### 10.5 Wave 6 (Evidence bundles + certificates) — DO NOT pull

| Gap | Wave | Reason |
|---|---|---|
| `evidence_bundles` + `evidence_bundle_items` tables | 6 | SPEC §17 Onda 6 |
| Curator evidence bundle scope (#308) | 6 | SPEC §17 Onda 6 |
| Function/action evidence bundles (#311) | 6 | SPEC §17 Onda 6 |
| Certificate/declaration verify page | 6 | SPEC §17 Onda 6 |
| Bilingual PT-BR / EN-US certificate output | 6 | SPEC §17 Onda 6 |

### 10.6 Wave 7 (Semantic + backfill) — DO NOT pull

| Gap | Wave | Reason |
|---|---|---|
| Semantic dims/facts | 7 | SPEC §17 Onda 7 |
| Dashboard documentos vigentes/pendentes/acknowledgements | 7 | SPEC §17 Onda 7 |
| Backfill Manual + PI + Privacy + Termos + acordos + charters + Frontiers + templates | 7 | SPEC §17 Onda 7 |

## 11. Child Issue Plan (proposed splits for PM dispatch)

These splits keep scope-confine honored. They DO NOT close #312 — #312 stays OPEN as the audit umbrella until PM ratifies the splits.

### 11.1 v1 must-have leaves (Wave 1b separate leaves, dispatched serially after this audit)

| Proposed leaf | Scope | Estimated session size |
|---|---|---|
| `#312-W4a` Gate templates for 6 doc_types | Migrate `resolve_default_gates` CASE expansion with editorial_guide / governance_guideline / project_charter / manual / executive_summary / framework_reference; 6 contract assertions; smoke = `resolve_default_gates(t)` returns non-NULL for all 11 doc_types | 1 small (single migration, no JSX) |
| `#312-W4b` `sign_proposer_consent` RPC | New SECDEF RPC; gates on caller=proposer_member_id NOT submitter; status transition pending_proposer_consent→draft; admin_audit_log row; ~8 contract assertions including FK-source per SEDIMENT-239b.A | 1 small (single migration + 1 contract test) |
| `#312-W4c` GAP-259.A default-status exclusion | `list_governance_library` body extension with `(v_filter_status IS NOT NULL OR gd.status IN (active,approved,under_review,superseded))`; forward-defense test asserts member-context unfiltered call excludes draft/withdrawn/revoked; admin override (`p_filters.status='draft'`) still works | 1 small (RPC body change + 2 tests) |
| `#312-W4d` `/governance/document/[id]` reader hardening | New SECDEF `get_member_governance_doc(p_doc_id)`; replace table-direct SELECT in [id].astro; class-aware response; same payload shape (no file_id/drive_url per P0-Q8) | 1 small (1 RPC + 1 page change + 1 test) |
| `#312-W4e` Curator draft-read mitigation | Per SPEC §19.5 carry: new policy `document_versions_read_unlocked_curator` (USING locked_at IS NULL AND can_by_member(m.id, 'participate_in_governance_review'))` — OR new SECDEF `get_unlocked_draft_for_curator`. PM picks pattern | 1 small (1 migration + 1 test) |

### 11.2 v1 follow-up / Wave 4 implementation (deferred)

| Proposed leaf | Scope | Estimated size |
|---|---|---|
| `#312-W4f` `independent_blind` primitives | New columns + RPC body rewrite + `release_blind_reviews` RPC + 1 invariant (#20) + contract tests | medium (multi-migration + RPC changes + 1 invariant) |
| `#312-W4g` target_instrument + derived products | PM D3 ADR decision FIRST; then schema delta + intake validation + smoke matrix | large (needs ADR + 1-2 migrations + JSX) |

### 11.3 Editor V4 alignment (parallel #161 lane)

| Proposed leaf | Scope |
|---|---|
| `#161-W4` Editor RPC V4 audit | Audit `upsert_document_version`, `lock_document_version`, `create_change_note` body for `manage_member` usage; if pre-V4 detected, write migration to align; cross-ref with #161 |

## 12. Carries (pre-existing, unchanged from p259)

| Carry | Source | Status post p260 |
|---|---|---|
| Curator-draft-access mitigation (Roberto/Sarah) | p259 #258 close | NOW WAVE 1b leaf candidate: `#312-W4e` proposed |
| `/governance/document/[id].astro` reader hardening | p259 #258 close | NOW WAVE 1b leaf candidate: `#312-W4d` proposed |
| `list_governance_library` payload extension for `depends_on` / templates | p259 Wave 1b expansion | Wave 1b second-batch leaf — separate from `#312-W4*` |
| GAP-259.A list_governance_library default exclusion | p259 PM Option (a) | NOW WAVE 1b leaf candidate: `#312-W4c` proposed |
| #171 Ana Carla access bug specific root cause | #171 open | Verify under #312 audit: is it route visibility (active_members predicate works), engagement (tribe_leader needs participate_in_governance_review?), or Drive grant? Not in #312 scope to fix; refer to #171 if it's behind RLS / route, or escalate to operational fix if Drive |
| #161 V4 UI gate audit | #161 open | Parallel lane; `#312-W4` (Editor V4 alignment) is a small spike within #161 |

## 13. What This Audit Does NOT Close

- ❌ NOT closing #312 (this is the audit; the umbrella stays open through child-issue dispatch + Wave 1b ratchet)
- ❌ NOT closing #315 (Wave 4 audit is one phase of umbrella; backfill + post-v1 dashboards still pending)
- ❌ NOT closing #96 (Frontiers launch umbrella — depends on legal/editorial Gate 0 blockers fully orthogonal to audit)
- ❌ NOT closing #308/#311 (curator + function/action evidence bundles — Wave 6 strict)
- ❌ NOT closing #171/#161 (tracked separately; audit cross-refs only)
- ❌ NOT implementing any of D1-D5 — those are PM calls
- ❌ NOT executing any persona impersonation against live DB (read-only audit only)
- ❌ NOT pulling MCP wrappers / Drive grants / evidence bundles / semantic dashboards into v1 sprint

## 14. Next Dispatch Options (PM call)

Listed in suggested priority (PM may reorder):

1. **PM ratifies D1-D5** (above) so child issues can be opened with correct wave assignment.
2. **`#312-W4b` `sign_proposer_consent` RPC** — unblocks Fabrício / Frontiers fixture in-app consent (canonical A2 path completion). This is the highest-leverage Wave 1b leaf because it converts `pending_proposer_consent` → `draft` and unblocks the editorial_guide doc that's been waiting since p259.
3. **`#312-W4a` Gate templates for 6 doc_types** — unblocks lock for editorial_guide (Frontiers), governance_guideline, project_charter (TAPs!), manual, executive_summary, framework_reference. Otherwise Fabrício can sign consent but the doc still can't advance.
4. **`#312-W4c` GAP-259.A default-status exclusion** — already PM-ratified Option (a) in p259, just awaits dispatch.
5. **`#312-W4d` `/governance/document/[id]` reader hardening** — closes p259 carry.
6. **`#312-W4e` Curator draft-read mitigation** — closes p259 Roberto/Sarah carry.
7. **`#161` Editor V4 alignment small spike** — orthogonal but parallel; audit `upsert_document_version` + `lock_document_version` + `create_change_note`.
8. **PM D3 ADR for derived products surface** — before any Wave 4 implementation leaf (Onda 4 SPEC §17 work).
9. **`#312` itself**: stays OPEN. Closes after `#312-W4a` + `#312-W4b` + `#312-W4c` ship (the three v1 must-haves) AND PM ratifies #312-W4d/W4e/W4f/W4g as documented v1.1+ leaves. Frontiers Guide can then complete intake → proposer consent → draft → lock → review → approval → active — the full SPEC §11 smoke matrix.

## 15. Council Lens (optional, not invoked this session)

If PM wants a council review of the proposed Wave 1b leaf splits + D1-D5 decisions, invoke `/council-review` after this PR. Suggested council:
- `data-architect` — review `review_mode` column placement + invariant #20 design
- `ux-leader` — review the persona × shell matrix + #171 acceptance
- `accountability-advisor` — review the wave classification for Frontiers (CR-050 + #96 + ADR-0021 cross-refs)
- `product-leader` — ratify the v1-must vs v1-follow-up split

## 15.5 PM ratification appendix (2026-05-25, post-audit)

PM ratified D1-D5 + dispatch sequence at audit close. Captured here verbatim for handoff anchor:

### D1 — Missing gate templates → **v1-must, Wave 4a**
Criar gate templates mínimos para os 6 doc_types sem suporte: `editorial_guide` · `governance_guideline` · `project_charter` · `manual` · `executive_summary` · `framework_reference`. Racional: sem isso o editor não consegue lock/version workflow para Frontiers e outros documentos reais.

### D2 — Blind-review primitives → **v1-follow-up, registrar como #312-W4f**
Não bloquear v1 operacional. Não implementar junto com W4a/W4b. Racional: é requisito importante para revisão independente, mas exige modelagem própria e não deve contaminar o fluxo básico de consent/gates.

### D3 — Derived products surface → **ADR obrigatório antes de implementação**
Recomendação PM: `content_products` deve ser o artefato canônico de produto derivado; `board_items` continua como tracking operacional. Racional: uma tribo pode gerar múltiplos produtos a partir de um documento — LinkedIn, newsletter, artigo, revista, política, template. Isso não deve ficar escondido em board item.

### D4 — Reader hardening → **v1-must, Wave 4d**
Criar leaf separado para substituir table-direct SELECT de `/governance/document/[id].astro` por RPC/SECDEF canônico. Racional: depois de Wave 1a/3, leitura de documento deve respeitar `visibility_class` e contrato server-side.

### D5 — 5 legacy `visibility='public'` comment rows → **preservar, não deletar, não reinterpretar**
Marcar como legacy/public historical comments em migração ou documentação, e excluir de qualquer semântica futura de blind review. Racional: apagar perde histórico; converter para blind review falsifica contexto. O correto é preservar como legado explícito.

### Sequência ratificada (PM, p260 close)

1. **#312-W4b** `sign_proposer_consent` RPC → destrava Frontiers de `pending_proposer_consent` para `draft` — issue: **#377**
2. **#312-W4a** gate templates → destrava lock/version para editorial_guide e os outros 5 tipos — issue: **#378**
3. **#312-W4c** GAP-259.A → biblioteca membro não lista `draft`/`pending_proposer_consent`/`withdrawn`/`revoked` por default — issue: **#379**
4. **#312-W4d** reader hardening — issue: **#380**
5. **#312-W4e** curator draft-read mitigation — issue: **#381**
6. **#312-W4f** blind-review primitives como follow-up modelado — issue: **#382**
7. **#312-W4g** derived products ADR antes de implementação — issue: **#383**

### D5 disposition (operational note)

The 5 legacy `visibility='public'` rows in `document_comments` (predate adr_0041 catálogo seed of 2026-04-27) are **preserved as-is**. Future migrations MUST NOT delete, migrate, or reinterpret them. Optional housekeeping: a follow-up annotation could write a single `admin_audit_log` row with action `governance.legacy_public_comments_annotated` listing the 5 comment IDs as a historical anchor — but this is NOT required and NOT a separate issue.

## 16. Evidence Anchors

| Source | Anchor |
|---|---|
| SPEC | `docs/specs/SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md` (§6.1, §10, §11, §16.5, §17 Onda 4, §19.5) |
| p259 fixture | `docs/audit/p259_frontiers_fixture_96_live_smoke.md` |
| Wave 1a M1 | `supabase/migrations/20260805000035_p256_wave1a_315_m1_governance_org_id_backfill.sql` |
| Wave 1a M2 | `supabase/migrations/20260805000036_p256_wave1a_315_m2_taxonomy_visibility_status_rls_vprime.sql` |
| Wave 1a M3 | `supabase/migrations/20260805000037_p256_wave1a_315_m3_intake_library_rpcs.sql` |
| Wave 1b first leaf | `supabase/migrations/20260805000038_p257_315_w1b_legacy_chain_backfill.sql` + `…000039_p257_315_w1b_v_invariant_activation.sql` |
| adr_0041 9 fns V4 conversion | `supabase/migrations/20260427233000_adr_0041_governance_review_action_and_9_fns.sql` |
| p195 initiative leaders governance review | `supabase/migrations/20260709000000_p195_initiative_leaders_governance_review.sql` + `…20260519000644/734/1733` |
| ReviewChainIsland 9-gate kinds + activeEligibleGates | `src/components/governance/ReviewChainIsland.tsx:81-103,118-151` |
| ClauseCommentDrawer 4-visibility type (drift vs RPC) | `src/components/governance/ClauseCommentDrawer.tsx:3-20,79-86,139-149` |
| DocumentVersionEditor table-direct SELECT (carry) | `src/components/governance/DocumentVersionEditor.tsx:100-108,123-141` |
| GovernanceLibrary STATUS_FILTER_OPTIONS (GAP-259.A) | `src/components/governance/GovernanceLibrary.tsx:69` |
| `/governance/document/[id]` table-direct SELECT (carry) | `src/pages/governance/document/[id].astro:82-97` |
| external_reviewer comment-only path | `src/pages/governance/documents/[chainId]/index.astro:18-22` |
| Live invariant count | 21/21 violation_count=0 via REST RPC `check_schema_invariants` |
| Live corpus | 16 docs via REST GET `/governance_documents` |
| Live gate-template coverage | 5/11 doc_types via REST RPC `resolve_default_gates` × 11 calls |
