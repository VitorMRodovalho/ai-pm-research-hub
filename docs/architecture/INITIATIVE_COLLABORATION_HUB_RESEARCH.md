# Initiative Collaboration Hub — Research Foundation

**Status:** Research draft for issue [#212](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/212) spec breakdown. Not an ADR. Not implementation. Other agent instance + PM consume this to produce the companion files below.

**Scope of this file:** cross-reference synthesis + gap analysis matrix + decision-point inventory. Effort budgeted ~1.5–2h.

**Out of scope (other instance / next phase):**
- `docs/architecture/INITIATIVE_COLLABORATION_HUB.md` — architecture doc
- `docs/adr/ADR-00XX-initiative-collaboration-hub-architecture.md` — ADR draft (Proposed)
- Sub-issue specs G1-G4 spawned on GitHub
- PM signoff before implementation

**Generated:** session p206 (2026-05-20)
**Companion instance:** parallel claude-code session, paired with PM
**Coordination model:** this file is read-only foundation; other instance writes derived artifacts.

---

## 0. Why this file exists

PM filed #212 at p205 #169 close (2026-05-20) to consolidate 5 gaps that surfaced post-PR #203 Vassouras seed migration (`IA & Competências 2026` initiative, Universidade de Vassouras × PMI-RJ, T-11d event on 02-Jun).

Per PM brief, two agent instances pair on #212. To avoid duplicate cross-reference work, this instance produces the foundation; the other instance produces the architecture doc + ADR + sub-issue specs.

### Operational data preserved here (do not lose)

- **Vassouras initiative_id**: `6e9af7a8-1696-4169-a1a1-c0e160600002`
- **Vassouras WhatsApp planning URL**: `https://chat.whatsapp.com/LKgHRGkZWF88TGnSBtZ9pv` (per PM brief — at survey time `initiatives.metadata.whatsapp_url=null`, save deferred)
- **Vassouras partner_entity_id** (`origin_partner_entity_id`): `6e9af7a8-1696-4169-a1a1-c0e160600001`
- **Vassouras seed migration**: `20260728000000` — created via direct INSERT, bypassed any Drive auto-creation hook (gap surfaced).

---

## 1. Executive summary — three findings that change the framing

### Finding A — `persons.auth_id` is already NULLABLE; G1 needs no new identity table

The `persons` table already supports identities without a Núcleo auth login:
```
persons.id          uuid NOT NULL
persons.auth_id     uuid NULLABLE   ← key insight
persons.email       text NOT NULL
persons.secondary_emails text[] NOT NULL DEFAULT '{}'
persons.consent_status text NOT NULL DEFAULT 'pending'
```

External collaborators (PMI-RJ board, university coordinators, students) are persons with `auth_id=NULL`, `consent_status='accepted'`, and engagements scoped to specific initiatives. G1 reduces to: **which existing `engagement_kind(s)` do we use, and what permissions to seed?**

### Finding B — 7 of 18 `engagement_kinds` slugs exist with zero `engagement_kind_permissions` rows

Existing slugs without seeded permissions:
- `alumni`, `ambassador`, `candidate`, `external_signer`, `guest`, **`partner_contact`**, `speaker`

`partner_contact` is the natural surface for external collaborators tied to a `partner_entity` (PMI-RJ chapter, Universidade de Vassouras). `external_reviewer` is already permissioned (for governance review). `speaker` is for one-off event participants. `guest` is for low-capability viewers.

**G1 implementation is config (engagement_kind_permissions seed migration) + RPC entrypoint, not new domain primitives.**

### Finding C — `initiative_drive_links` is metadata-only; no Google Drive API integration ships today

Current state of Drive integration:
- ✅ `initiative_drive_links` table exists with soft-unlink (`unlinked_at`/`unlinked_by`)
- ✅ `link_initiative_to_drive`, `get_initiative_drive_links`, `unlink_initiative_from_drive` RPCs live
- ✅ `board_drive_links` parallel surface (Mayanna #110)
- ❌ NO service-account integration with Google Drive API
- ❌ NO auto-creation hook on `create_initiative`
- ❌ NO permission grant/revoke calls on engagement lifecycle events

G2 (engagement-level Drive sync) + G4 (Google API governance) must ship together. **#209 (member-level Drive revoke cascade) is the natural foundation** — it introduces the service-account, audit table, and approval gate model. G2 extends to engagement-level by adding `engagement_id` column to `drive_offboarding_audit` and triggering on engagement INSERT/UPDATE/soft-delete.

### Recommended high-level direction (one-liner per gap)

| Gap | Direction | Rationale |
|-----|-----------|-----------|
| G1 — external members | Seed `partner_contact` + `external_reviewer` permissions, reuse `persons` with `auth_id=NULL`, gate via `consent_status` | No new domain primitives needed; respects ADR-0006 + ADR-0009 |
| G2 — Drive permission sync | Extend #209 audit table with `engagement_id`; trigger on engagement INSERT/soft-delete; share-link fallback for non-Google emails | #209 service-account ships first; G2 piggybacks |
| G3 — metadata UI | Implement #211 as-planned + add "Add external collaborator" flow that creates `partner_contact` engagement and (optionally) grants Drive permission | #211 already scoped; #212 G3 adds composite flow |
| G4 — Google API governance | Mirror #209's service-account pattern; one EF per API surface; Antigravity/Gemini = enhancement not blocker | Don't conflate AI experiments with structural integration |
| G5 — recurring meeting time | Defer per #212 explicit out-of-scope | Mention only |

---

## 2. Cross-reference synthesis

### Dependency graph

```
#205 (member_emails RPC)  ──┬─→ #210 (calendar cleanup)
                             └─→ G1 (#212 — multi-email pattern reuse, soft dep)

#209 (Drive cascade member) ─┬─→ G2 (#212 — extend with engagement_id, HARD dep)
                              └─→ G4 (#212 — share service account, HARD dep)

#211 (metadata UI)  ─────────→ G3 (#212 — adds G1+G2 composite flows)
#208 (meet transcripts)  ────→ G4 (#212 — same service-account + audit pattern)
#110 (board Drive — DONE)  ──→ G2 (different scope, complementary primitive)
#204 (umbrella, parent)  ────→ all above
```

### Per-issue notes

#### #204 — Initiative gemini integration + drive/calendar governance (parent umbrella, P2)
- Status: OPEN
- Coordinates 6 sub-issues (#205-#210) Mai→Jul 2026
- **Not a blocker for #212** — same scope umbrella, complementary timing
- Cross-cuts: G4 of #212 sits inside #204's umbrella

#### #205 — `member_emails` + `resolve_member_by_email` (P1, blocks #210)
- Status: OPEN, not implemented
- New table `member_emails` (1 member → N emails) + `member_resolve_email(p_email) RETURNS uuid` RPC
- Use case: Roberto Macêdo has 2 emails (one personal primary + one chapter institutional address); see #205 for verbatim values
- **G1 implication:** external members may also have multiple emails (institutional in Calendar vs personal in `persons.email`). Recommend G1 reuses the `member_emails` pattern, possibly generalizing to `person_emails` if persons need it too.
- **NOT a hard blocker for G1** — `persons.secondary_emails text[]` already exists. Could be sufficient.

#### #208 — Meet transcripts → `create_meeting_notes` pipeline (P2)
- Status: OPEN
- Pipeline reads Drive folder `1JHbKSD_bxmDlVz1yzp42Zj1Ft-U_U2e7` (Meet Recordings, owner GP)
- Claude Haiku 4.5 for JSON structured output
- Privacy gate per-file (GP marks `process`/`skip`/`private`)
- **G4 implication:** shares Drive service-account context. If G4 establishes the service-account pattern, #208 reuses it.

#### #209 — Drive permission revocation cascade (P1 LGPD, member-level)
- Status: OPEN
- Cron weekly cross `members WHERE member_status IN ('inactive','alumni') AND offboarded_at IS NOT NULL` × Drive permissions
- Tables: `drive_offboarding_audit` (member_id FK, drive_file_id, permission_id, revoked_at, approved_by, status)
- EFs: `audit-drive-offboarding-access` (cron) + `revoke-drive-permission` (post-approval)
- MCP tools: `list_drive_revocation_pending`, `approve_drive_revocation`, `bulk_approve_drive_revocations`
- **G2 HARD DEPENDENCY:** G2 extends this audit table to engagement-level. Decision needed: same table with optional `engagement_id` column, or separate `engagement_drive_offboarding_audit`?
  - **Recommend:** same table with `engagement_id` nullable + check `member_id OR engagement_id NOT NULL`. Single audit trail; one revoke EF; one MCP surface.

#### #210 — Calendar recurrence cleanup (P2, blocked by #205)
- Status: OPEN, blocked
- Audit attendees of recurring Calendar events; classify via `member_resolve_email`; CSV report → GP line-by-line approve → Calendar API patch
- **#212 implication (principle):** DB-driven classification, no client-side regex. Same principle applies to G2 — Drive permission grants driven by `engagements` table state, not email pattern matching.

#### #211 — Initiative edit-metadata UI (P1, ux)
- Status: OPEN
- Fields: `whatsapp_url`, `drive_folder`, `recurring_meeting_time`, `youtube_channel`, `sponsorship_details`, generic `metadata` jsonb
- New RPC `manage_initiative_metadata` OR extend `update_initiative` (already exists, accepts `p_metadata jsonb`)
- **#212 G3 RELATIONSHIP:** #211 is the natural implementation issue for G3 metadata UI scope. #212 G3 extends with: "Add external collaborator" flow + "Provision Drive folder" button (G1 + G2 integration touchpoints).
- **Recommend:** keep #211 as-filed; new sub-issue for #212 G3 layers on top.

#### #110 — Mayanna Drive integration (board-level, DONE)
- Status: Implemented (Opção B per PM decision)
- Tables: `board_drive_links`
- RPCs: `link_board_to_drive`, `get_board_drive_links`, `unlink_board_from_drive`
- **#212 G2 RELATIONSHIP:** complementary primitive at board granularity. Initiative-level Drive (#212 G2) sits one level up. Don't conflate.

---

## 3. Schema state snapshot (what exists today)

### 3.1 Identity layer

| Table | Purpose | Key columns | #212 relevance |
|-------|---------|-------------|---------------|
| `persons` | Canonical identity (V4) | `id`, `auth_id NULLABLE`, `email`, `secondary_emails text[]`, `consent_status`, `legacy_member_id` | G1 host table |
| `members` | Legacy bridge | `id`, `auth_id`, `person_id`, `email`, `secondary_emails text[]`, `operational_role`, `designations text[]`, `member_status` | G1 — external members are NOT members; this table NOT touched |
| `visitor_leads` | Marketing/funnel intake | `id`, `email`, `lgpd_consent`, `status`, `promoted_to_application_id`, `dedupe_email_normalized` | Out of G1 scope — leads ≠ collaborators |
| `partner_entities` | Org-level partners | `id`, `name`, `entity_type`, `chapter`, `contact_email`, `contact_name`, `mou_stage` | G1 host for organizational partner (PMI-RJ chapter, Universidade de Vassouras) |
| `partner_contacts` | (table) NOT FOUND | — | — |

**Note:** No separate `partner_contacts` TABLE found. The `partner_contact` is an `engagement_kind`, not a table. External contacts are modeled as `persons` + `auth_engagements(kind='partner_contact', initiative_id=...)`. The `partner_entities.contact_email`/`contact_name` are convenience denormalized fields, not a separate contacts table.

### 3.2 Engagement layer (V4 authority)

| Table | Purpose | Key columns | #212 relevance |
|-------|---------|-------------|---------------|
| `auth_engagements` | Authority grants | `engagement_id`, `person_id`, `organization_id`, `initiative_id`, `kind`, `role`, `status`, `start_date`, `end_date`, `legal_basis`, `is_authoritative`, `agreement_certificate_id`, `requires_agreement` | G1 + G2 — engagements drive Drive permission sync |
| `engagement_kinds` | Kind config (per ADR-0009) | `slug`, `display_name`, `legal_basis`, `requires_agreement`, `default_duration_days`, `retention_days_after_end (default 1825)`, `auto_expire_behavior`, `initiative_kinds_allowed text[]`, `metadata_schema jsonb` | G1 — `partner_contact` already exists |
| `engagement_kind_permissions` | V4 perms matrix | `kind`, `role`, `action`, `scope (global/organization/initiative)` | G1 — need seed rows for `partner_contact` |

### 3.3 Engagement kinds taxonomy (18 slugs)

| Slug | Display | `requires_agreement` | Has perms rows? | #212 relevance |
|------|---------|---------------------|----------------|---------------|
| alumni | Alumni | — | No | Out of scope |
| ambassador | Embaixador | yes | No¹ | Out of scope |
| candidate | Candidato | — | No | Out of scope (selection pipeline) |
| chapter_board | Diretoria de Capítulo | — | Yes | **Relevant — PMI-RJ board directors** |
| committee_coordinator | Coordenador de Comite | — | Yes | Out of scope |
| committee_member | Membro de Comite | — | Yes | Out of scope |
| external_reviewer | Revisor Externo | yes | Yes (1 role) | **Relevant — academic reviewers** |
| external_signer | Signatario Externo | — | No | Possibly relevant — partner MOU signers |
| guest | Convidado | — | No | **Relevant — student visitors / low-capability** |
| observer | Observador | — | Yes | Out of scope |
| **partner_contact** | **Contato Parceiro** | — | **NO** | **PRIMARY — main G1 surface** |
| speaker | Palestrante | — | No | Relevant — event speakers |
| sponsor | Patrocinador | — | Yes | Out of scope |
| study_group_owner | GP Grupo de Estudos | yes | Yes | Out of scope |
| study_group_participant | Participante GE | yes | Yes | Out of scope |
| volunteer | Voluntário Ativo | yes | Yes (heavy) | Out of scope |
| workgroup_coordinator | Coordenador de Equipe | — | Yes | Out of scope |
| workgroup_member | Membro de Equipe | — | Yes | Out of scope |

¹ `ambassador` has agreement but no perms — perms are implicit/elsewhere.

### 3.4 Drive integration layer (initiative-level)

| Table | Purpose | Status | #212 relevance |
|-------|---------|--------|---------------|
| `initiative_drive_links` | Initiative → Drive folder metadata | LIVE (`id`, `initiative_id`, `drive_folder_id`, `drive_folder_url`, `drive_folder_name`, `link_purpose`, `unlinked_at`, `unlinked_by`) | G2 — host table for engagement sync |
| `drive_discoveries` | Files discovered in linked folder | Exists | Read-only for G2 |
| `board_drive_links` | Board → Drive folder | LIVE (#110 done) | Out of #212 scope — board granularity |
| `card_drive_files` | Per-card file references | LIVE | Out of #212 scope |
| `partner_attachments` | Files attached to partner records | LIVE | Out of #212 scope |
| `drive_offboarding_audit` | (#209 future) | NOT YET — #209 introduces | **G2 dependency — extend with engagement_id** |
| Google service account creds | Vault | NOT YET — #209 introduces | **G4 dependency** |

### 3.5 Relevant RPCs

Drive:
- ✅ `link_initiative_to_drive(p_initiative_id, p_drive_folder_id, p_drive_folder_url, p_drive_folder_name, p_link_purpose)`
- ✅ `get_initiative_drive_links(p_initiative_id)`
- ✅ `unlink_initiative_from_drive(p_link_id)`
- ✅ `record_drive_discovery(p_initiative_drive_link_id, ...)`
- ✅ `list_drive_discoveries(p_initiative_id, p_status_filter, p_limit, p_offset)`
- ✅ `get_drive_discovery_health()`
- ❌ `grant_engagement_drive_permission(p_engagement_id)` — NOT YET (G2)
- ❌ `revoke_engagement_drive_permission(p_audit_id)` — NOT YET (G2, depends #209)

Engagement:
- ✅ `manage_initiative_engagement(p_initiative_id, p_person_id, p_kind, p_role, p_action)`
- ✅ `create_initiative_invitations(...)`, `respond_to_initiative_invitation(...)`, `review_initiative_request(...)`, `request_to_join_initiative(...)`, `withdraw_from_initiative(...)`
- ✅ `join_initiative(p_initiative_id, p_motivation, p_metadata)`
- ❌ `add_external_collaborator(p_initiative_id, p_email, p_name, p_kind, p_capabilities)` — NOT YET (G1 entrypoint)

Initiative metadata:
- ✅ `update_initiative(p_initiative_id, p_title, p_description, p_status, p_metadata)`
- ✅ `validate_initiative_metadata(p_kind, p_metadata)` + trigger `trg_validate_initiative_metadata_fn`
- (no separate `manage_initiative_metadata` — #211 should likely extend `update_initiative` rather than create new)

Auth:
- ✅ `can_by_member(p_member_id, p_action, p_resource_type, p_resource_id)`
- ✅ `rls_can_for_initiative(p_action, p_initiative_id)`

---

## 4. Gap analysis matrix

### G1 — External member onboarding to an initiative

| Dimension | Current state | Proposed direction (Recommended) | Alternatives considered |
|-----------|---------------|----------------------------------|-------------------------|
| Identity primitive | `persons` table with `auth_id` nullable already supports identities without auth login | **Reuse `persons` (no new table)**. External collaborators get `persons` row with `auth_id=NULL`, `consent_status='pending'→'accepted'` flow. | New `external_persons` table (rejected — duplicates ADR-0006). Reuse `members` (rejected — externals are not members; LGPD scope differs). |
| Engagement kind | `partner_contact`, `external_reviewer`, `external_signer`, `speaker`, `guest` slugs exist; only `external_reviewer` has perms seeded | **Seed `engagement_kind_permissions` for `partner_contact`** (primary) + extend `external_reviewer`, add minimal seed for `guest`. | Single new `external_collaborator` kind (rejected — violates ADR-0009 config-driven; existing kinds already cover use cases). |
| Tier of capability | None (no perms seeded) | **Three tiers (Recommended):**<br>- `partner_contact` role=`liaison`: view initiative + comment on board cards + view assigned items<br>- `external_reviewer` role=`reviewer`: existing (participate_in_governance_review)<br>- `guest` role=`participant`: view-only initiative dashboard | View-only across all (too restrictive for teaching). Full board write (too permissive). |
| LGPD consent | `persons.consent_status` exists; flows for `visitor_leads.lgpd_consent` | **Reuse `persons.consent_status`** + new flow "Add external collaborator" requires consent acceptance via signed link OR PM-attested checkbox | Out-of-band paper consent (rejected — won't scale to N students). |
| Lifecycle | `engagement_kinds` has `default_duration_days`, `auto_expire_behavior`, `notify_before_expiry_days` | **For `partner_contact`/`guest`/`speaker`: `default_duration_days=90`, `auto_expire_behavior=offboard`**. For `external_reviewer`: per existing config. | Persist forever (LGPD violation — Art. 16 retention). Manual offboard (forgets). |
| Entrypoint RPC | None | **New `add_external_collaborator(p_initiative_id, p_email, p_name, p_kind, p_role, p_partner_entity_id NULLABLE, p_consent_attested boolean) RETURNS jsonb`** — creates/upserts `persons` row + `auth_engagements` row + audit log | Extend `manage_initiative_engagement` (rejected — that's for existing person_id; external onboarding is a different flow). Multiple steps via existing RPCs (rejected — too leaky). |
| MCP exposure | None | New MCP tool `add_external_collaborator` (mirrors RPC) + extend `list_initiative_engagements` to show external collaborators clearly | — |
| UI | None | New section in `/initiative/[id]` Settings → "Colaboradores externos" with add-form; lists with edit/remove | — |
| Effort | — | **M~6-8h** (1 migration kinds perms + 1 migration RPC + tests + MCP tool + UI form) | — |
| Hard dependencies | — | None | — |
| Soft dependencies | — | #205 multi-email pattern (if persons need it); #209 service-account (only if granting Drive on add) | — |
| Blocking | — | G2 (G2 needs engagement to exist before granting Drive permission) | — |

### G2 — Initiative-participation ↔ Drive folder permission sync

| Dimension | Current state | Proposed direction (Recommended) | Alternatives considered |
|-----------|---------------|----------------------------------|-------------------------|
| Sync trigger model | No sync today | **Trigger-based** on `auth_engagements` INSERT (grant) + UPDATE-status-to-revoked (revoke) + soft-delete (revoke) | Cron-based diff (slower feedback, used as backstop only). Hybrid (trigger + cron reconciliation weekly) — actually recommend this combo: trigger for fast path, cron for drift recovery. |
| Permission grant primitive | None | **New `engagement_drive_permissions` table** (FK `auth_engagements.engagement_id`, `drive_folder_id`, `permission_id` from Google, `granted_at`, `granted_by`, `revoked_at`, `audit_status`) | Extend `initiative_drive_links` directly (rejected — N permissions per link breaks 1-row-per-folder semantic). |
| Revoke audit | None | **Extend #209's `drive_offboarding_audit`** with nullable `engagement_id` column + CHECK `(member_id IS NOT NULL OR engagement_id IS NOT NULL)`. Single audit trail, single approval gate, single revoke EF. | Separate `engagement_drive_offboarding_audit` table (rejected — duplicates infra). |
| Approval gate | None (today) | **Per-engagement-row GP approval**, mirroring #209 pattern. Mass actions (e.g., event ends, 50 students offboard) batch into single approval request. | Auto-revoke on engagement end (rejected — too risky; GP must see what's revoked). |
| External member (no Google account) | Not modeled | **Detect Google account by domain or explicit `persons.google_account_email` field**. If present → grant permission. If absent → share-link generation with audit log entry. | Always grant (fails for non-Google emails). Always share-link (loses access control granularity). |
| Drive folder auto-creation on initiative INSERT | None (Vassouras was bypassed) | **Add post-insert trigger on `initiatives`** (or RPC `create_initiative` wrapper) that enqueues Drive folder creation via EF | Manual button in UI only (rejected — easy to forget). |
| Service account | None today (#209 will introduce) | **Reuse #209 service account** + Drive scopes for: create folder, list permissions, add permission, delete permission, create share link | Per-feature service accounts (rejected — quota mgmt nightmare). |
| Effort | — | **L~10-12h** (assumes #209 has shipped first; otherwise add ~6h for service-account groundwork) | — |
| Hard dependencies | — | **#209 service-account + audit table + revoke EF** | — |
| Soft dependencies | — | G1 (for external members needing Drive access) | — |
| Blocking | — | G3 "Add external collaborator with Drive permission" composite flow | — |

### G3 — Initiative metadata UI (subsumes #211, extends with G1+G2)

| Dimension | Current state | Proposed direction (Recommended) | Alternatives considered |
|-----------|---------------|----------------------------------|-------------------------|
| Scope | None today; #211 filed | **#211 ships first** (WhatsApp + Drive folder + recurring time + YouTube + sponsorship); **#212 G3 layers** "Add external collaborator" + "Provision Drive folder" buttons on top | Bundle everything into one mega-issue (rejected — too big). |
| Entry point | None | `/initiative/[id]` → new "⚙️ Configurações" tab/panel | Admin-only via `/admin/initiatives/[id]` (rejected — initiative owners need self-service) |
| RPC backend | `update_initiative` exists, accepts `p_metadata jsonb` | **Reuse `update_initiative`** with extended metadata schema validation via `validate_initiative_metadata` | New `manage_initiative_metadata` RPC (rejected — duplicates update_initiative purpose) |
| External collab button | None | "Adicionar colaborador externo" → modal calling G1's `add_external_collaborator(...)` | Inline form per initiative member list (rejected — collaborator add is a deliberate action, modal is right pattern) |
| Drive provision button | None | "Criar pasta Drive" → EF call (G2/G4 territory); if folder exists, shows "Pasta linkada: <url>" | Auto-trigger on initiative INSERT (rejected for opt-in clarity; PM can override per-initiative) |
| Permissions for metadata edit | None | **Initiative owner/coordinator OR `manage_initiative` action via V4** | Admin-only (rejected — doesn't scale to multi-hub) |
| Audit | None | Every metadata edit → `admin_audit_log` row, `kind='initiative_metadata_updated'`, `details` jsonb of diff | — |
| Effort | — | **#211 implementation S-M ~4-6h; #212 G3 additions M ~3-4h** | — |
| Hard dependencies | — | #211 (or merge them into single bigger issue) | — |
| Soft dependencies | — | G1 (for collab button); G2 (for Drive provision button) | — |
| Blocking | — | None (frontend slice) | — |

### G4 — Google API + Antigravity integration governance

| Dimension | Current state | Proposed direction (Recommended) | Alternatives considered |
|-----------|---------------|----------------------------------|-------------------------|
| Service account ownership | None today | **#209 introduces; G4 ratifies the pattern as canonical** | Per-feature service accounts (rejected) |
| API call location | N/A | **Edge Functions** (one EF per API surface: `drive-permissions`, `drive-folders`, `calendar-attendees`, `meet-transcripts`). RPCs call EFs via pg_net only for synchronous needs; trigger-driven Drive work goes via job queue | RPC → pg_net direct (rejected for complex flows). Worker (rejected — keep EF for Google integrations) |
| Auth model | N/A | **Service account JWT in Supabase Vault**; rotated per Google security best practice; EF reads secret only from Vault, never from env in code | Env vars (rejected — rotation friction). OAuth user-token (rejected — couples to PM's personal Google) |
| Quota + rate limiting | N/A | **EFs implement exponential backoff + dead-letter queue table `google_api_failures`** for batch jobs (e.g., 50 students join in one minute). Per-EF concurrency limit | Hammer the API + accept 429s (rejected) |
| Audit trail | `ai_processing_log` exists (LGPD Art. 37) | **New `google_api_call_log`** (or extend `ai_processing_log` with `purpose='google_api'`) — every call logged with endpoint, person/initiative context, success/fail, duration | No audit (rejected — LGPD + ops blind) |
| Antigravity / Gemini 3.5 multimodal | Tracked separately under #206 | **Out of G4 scope** — Antigravity is AI workload experimentation; G4 is structural integration. Cross-reference but don't bundle. | Bundle (rejected — different cadence + risk profile) |
| MCP tools | None for Drive permissions | New tools: `list_initiative_drive_permissions`, `revoke_engagement_drive_permission`, `approve_drive_revocation` (mirrors #209 patterns) | — |
| Threat model | ADR-0018 exists for MCP threat model | **New ADR or extension** covering Google API attack surface (service account compromise, quota exhaustion, audit log tampering) | — |
| Effort | — | Spec already covered by #209; G4 = ratify pattern + add new EFs as G2 lands. **No standalone implementation** outside G2's work. | — |
| Hard dependencies | — | #209 | — |
| Soft dependencies | — | #208 (shares same service-account pattern) | — |
| Blocking | — | G2 directly | — |

### G5 — Recurring meeting time / cadence (DEFER per #212)

Out of #212 first spec scope. Mention only. `events` table covers individual occurrences. Future ARM-5/ARM-6 follow-up.

---

## 5. Decision points (open architecture questions)

Each item below names a specific decision that the architecture doc + ADR MUST resolve.

### G1.1 — Capability tier for `partner_contact` engagement
**Question:** What actions does `engagement_kind_permissions(kind='partner_contact', role='liaison', action=?, scope='initiative')` get seeded with?

**Options:**
- A (**Recommended**): `view_initiative_dashboard`, `write_board` (on assigned board items only — requires RLS extension)
- B: `view_initiative_dashboard` only
- C: full `write_board` + `view_pii` (mirror committee_member.participant)

**Trade-offs:** A balances teaching opportunity (students can comment) with safety (can't escalate). B is too restrictive for the Vassouras teaching case. C leaks PII to external collaborators, LGPD risk.

### G1.2 — Consent capture flow for external members
**Question:** How does `persons.consent_status='pending'→'accepted'` happen for an external collaborator?

**Options:**
- A (**Recommended**): PM/initiative-owner-attested checkbox in "Add external collaborator" form ("Confirmo que o colaborador externo aceitou os termos de tratamento de dados") + audit log records who attested
- B: Email-link consent (collaborator clicks link, accepts via public page, returns to flow). Slower; better paper trail.
- C: Both — A as fast path for trusted partner, B for unknown contacts

**Trade-offs:** A is faster and matches Vassouras urgency (T-11d). B is LGPD-strongest. C is best long-term but more code. **Recommend A for v1, B as enhancement**.

### G1.3 — Multi-email model for `persons`
**Question:** Does `persons.secondary_emails text[]` suffice, or do we need a `person_emails` table mirroring #205's `member_emails`?

**Options:**
- A (**Recommended**): Use `persons.secondary_emails` for v1; promote to `person_emails` if external collab use cases reveal need (multi-domain verification, per-email kind tracking)
- B: Build `person_emails` upfront mirroring `member_emails`

**Trade-offs:** A is YAGNI-aligned; B is consistent with #205 pattern. **Recommend A**; #205's `member_resolve_email` can be generalized later if needed.

### G2.1 — Engagement → Drive permission mapping cardinality
**Question:** How many Drive folder permissions does one engagement grant?

**Options:**
- A (**Recommended**): 1 engagement → N folders (all `initiative_drive_links` for the initiative). Permission row per (engagement, folder).
- B: 1 engagement → 1 root folder per initiative; subfolders inherit via Google Drive cascade
- C: Per-engagement custom folder selection

**Trade-offs:** A is most explicit and aligns with audit. B is Google-native but harder to revoke surgically. C is over-engineered for v1. **Recommend A**.

### G2.2 — External member without Google account: share-link vs deny
**Question:** External collaborator's email is not a Google account (e.g., university `.edu.br` Microsoft mailbox). What does G2 do?

**Options:**
- A (**Recommended**): Generate a "Anyone with the link can view" share link, log to `engagement_drive_permissions` with `permission_type='anyone_with_link'`, send to collaborator's email. On revoke, delete the share link.
- B: Deny — collaborator can't access Drive
- C: Convert to Google personal account (require collaborator to sign up)

**Trade-offs:** A is functional but less granular access control. B blocks the Vassouras teaching case. C adds friction. **Recommend A with audit + warning**.

### G2.3 — Drive folder auto-creation on initiative INSERT
**Question:** Should creating an initiative trigger Drive folder provisioning automatically?

**Options:**
- A (**Recommended**): Yes, via EF call enqueued post-INSERT. Folder named `[initiative_kind] - [title]` in shared drive root. Initiative owner gets editor permission immediately.
- B: No, manual button in metadata UI only (per G3)
- C: A for some kinds (`congress`, `tribe`, `workgroup`); B for others (`alumni_event`, `pilot`)

**Trade-offs:** A is full automation but spawns folders for every initiative (clutter risk). B is opt-in but easy to forget (Vassouras case). C is best of both but more config. **Recommend A as default + add `kind.metadata_schema.drive_provisioning='auto'|'manual'` config to allow opt-out per kind**.

### G2.4 — Cascade direction on Núcleo offboarding
**Question:** When a Núcleo member is offboarded (#209's primary case), do their initiative-level engagement Drive permissions also revoke?

**Options:**
- A (**Recommended**): Yes — Núcleo offboarding cascades through all active engagements; each engagement-level permission flagged for revocation in the same #209 approval batch.
- B: Only Núcleo-wide Drive permissions revoke; initiative-level engagements continue (decoupling)
- C: Configurable per engagement_kind (some kinds keep access after Núcleo offboarding, e.g., `alumni`)

**Trade-offs:** A is LGPD-strict. B breaks the cascade promise of #209. C is correct long-term — alumni access to history is a legit case. **Recommend A for v1 + add `engagement_kinds.retain_access_after_member_offboard boolean` for future C-style override (default false)**.

### G3.1 — Permission for editing initiative metadata
**Question:** Who can edit initiative.metadata?

**Options:**
- A (**Recommended**): V4 `can(p_action='manage_initiative', p_resource_id=initiative_id)` — gated to owner/coordinator role on that initiative engagement
- B: Org admin only
- C: Anyone with `write` action on initiative

**Trade-offs:** A matches multi-hub self-service goal. B blocks scale. C is too permissive. **Recommend A** — requires seeding `manage_initiative` action in `engagement_kind_permissions` for relevant roles.

### G4.1 — Service-account ownership
**Question:** Whose Google account owns the service account?

**Options:**
- A (**Recommended**): A dedicated Google Workspace user (e.g., a `nucleo-platform` service identity on an org-owned domain), owned by the org not by PM personally
- B: PM's personal Google account (current convenience)
- C: Per-chapter service account (for multi-hub future)

**Trade-offs:** A is correct long-term + sets the multi-hub pattern. B is single-point-of-failure (PM leaves → revocation cascade broken). C is over-engineered for current scale. **Recommend A** — establish nucleo-platform Google Workspace account before G4 ratifies.

### G4.2 — Google API call envelope
**Question:** RPCs in Postgres can't call Google APIs directly. What's the bridge?

**Options:**
- A (**Recommended**): RPC writes a row to `google_api_jobs` queue table; cron EF (`process-google-api-jobs`, every 1 min) drains and calls Google API; success/fail back to row. UI polls or subscribes via Realtime.
- B: RPC → `pg_net` → EF synchronous (blocks until Drive responds — risk of long lock)
- C: Frontend calls EF directly (no RPC trip)

**Trade-offs:** A is best for batch + ops visibility + retry. B for low-latency single calls. C for user-driven actions (e.g., "Create folder now"). **Recommend hybrid: A for batch/trigger flows (G2 cascade), C for user-driven actions (G3 "Create folder" button)**.

---

## 6. Sub-issue boundary sketch

Preliminary scope for the four sub-issues the other instance should spawn. Each ready for `gh issue create` with full acceptance criteria after PM signoff.

### Sub-issue G1: external member onboarding to initiative
- **Label:** `governance, ux, type:task, priority:high`
- **In scope:** seed `engagement_kind_permissions` for `partner_contact`+`guest`+extend `external_reviewer`; new RPC `add_external_collaborator`; new MCP tool; modal in `/initiative/[id]` settings; LGPD consent flow A (PM-attested)
- **Out of scope:** consent flow B (email-link); `person_emails` table; multi-domain verification
- **Effort:** M ~6-8h
- **Hard deps:** none
- **Cross-ref:** #212 G1 + ADR-0006/0009

### Sub-issue G2: engagement-level Drive permission sync
- **Label:** `governance, audit-trail, type:task, priority:high`
- **In scope:** new `engagement_drive_permissions` table; trigger on `auth_engagements` INSERT/soft-delete; extend `drive_offboarding_audit` with `engagement_id`; new EF `grant-engagement-drive-permission`; share-link fallback for non-Google emails; auto-create folder on initiative INSERT; MCP tools (3)
- **Out of scope:** Calendar/Meet sync (separate issues); per-card permission granularity
- **Effort:** L ~10-12h
- **Hard deps:** **#209** (service-account + audit infra)
- **Cross-ref:** #212 G2 + #209

### Sub-issue G3: initiative metadata UI (extends #211)
- **Label:** `ux, type:task, priority:high`
- **In scope:** "Add external collaborator" modal (calls G1); "Provision Drive folder" button (calls G2); polish #211's WhatsApp/recurring-time/YouTube fields; permission gate `manage_initiative`
- **Out of scope:** bulk edit; template defaults; multi-hub config sync
- **Effort:** M ~3-4h (on top of #211's M ~4-6h)
- **Hard deps:** #211, G1, G2 (composite flows need these)
- **Cross-ref:** #212 G3 + #211

### Sub-issue G4: Google API integration governance + nucleo-platform service account
- **Label:** `governance, infrastructure, type:task, priority:high`
- **In scope:** create nucleo-platform Google Workspace account; provision service account; store in Vault; new ADR ratifying #209's service-account pattern; `google_api_jobs` queue table; `process-google-api-jobs` cron EF skeleton; `google_api_call_log` (or extend `ai_processing_log`)
- **Out of scope:** Antigravity/Gemini integration; Calendar API beyond what #210 needs; Meet beyond what #208 needs
- **Effort:** M-L ~6-8h
- **Hard deps:** #209 (to inherit/share its service-account setup); decision on service-account ownership (G4.1 above)
- **Cross-ref:** #212 G4 + #204 + #208 + #209 + #210

---

## 7. Vassouras tactical implications (T-11d to 02-Jun event)

Vassouras event is on 2026-06-02. Today is 2026-05-20. T-11d. PM noted at #212: "Vassouras specifically may need a quick-win manual workaround for adding external members, while spec evolves for the structural fix."

### What can ship in <1 day to unblock the event without G1-G4 architecture work

**Manual workaround pattern (recommended for T-11d):**

1. **PMI-RJ board director / university coordinator:**
   - Create `persons` row manually via SQL/MCP (`auth_id=NULL`, `consent_status='accepted'`, `email='<institutional>'`)
   - Insert `auth_engagements(person_id, initiative_id='6e9af7a8-...', kind='partner_contact', role='liaison', status='active', start_date='2026-05-20', end_date='2026-06-10')`
   - Manually grant Drive folder permission via Drive UI (no auto-sync yet)
   - Audit row: `admin_audit_log` manual entry citing #212 workaround
   - PM-attested consent on file (paper or email confirmation)

2. **Students (batch):**
   - One `persons` row each
   - Grant via share-link (existing Drive folder of Vassouras initiative) — no permission management needed
   - Send share-link via WhatsApp planning group (`https://chat.whatsapp.com/LKgHRGkZWF88TGnSBtZ9pv`)
   - No engagement row needed for view-only students; they're guests at the event level, not initiative collaborators

3. **WhatsApp URL save:**
   - Run SQL: `UPDATE initiatives SET metadata = metadata || jsonb_build_object('whatsapp_url', 'https://chat.whatsapp.com/LKgHRGkZWF88TGnSBtZ9pv') WHERE id = '6e9af7a8-1696-4169-a1a1-c0e160600002';`
   - PM intended this at p205 but at survey time the field was still null. Either PM hadn't run it yet, or save reverted. **Verify before publishing this doc.**

4. **Drive folder for Vassouras initiative:**
   - Currently NOT auto-created (Vassouras seed via direct INSERT bypassed any hook)
   - Manually create Drive folder + run `link_initiative_to_drive(initiative_id='6e9af7a8...', drive_folder_id, drive_folder_url, drive_folder_name, link_purpose='primary_workspace')`

These workarounds preserve LGPD compliance (persons + consent), audit trail (admin_audit_log), and don't pollute schema with hacks. They become the test case for the eventual G1+G2 automation.

### What MUST be in spec before Vassouras event
- None — event can run on manual workarounds
- Post-event: lessons learned feed into G1/G2 sub-issue acceptance criteria refinement

---

## 8. Handoff to other instance + PM

### What the other instance + PM should produce next

1. **`docs/architecture/INITIATIVE_COLLABORATION_HUB.md`** — architecture doc
   - Lift findings + decision recommendations from sections 1, 4, 5 above
   - Add: state machines for engagement lifecycle (especially auto-expire flow); sequence diagrams for "Add external collaborator + Drive permission" composite flow
   - Add: multi-hub readiness section (how does this scale to PMI-CE, PMI-MG, etc.?)

2. **`docs/adr/ADR-00XX-initiative-collaboration-hub-architecture.md`** — ADR draft Proposed status
   - Decision: reuse `persons` + `engagement_kind_permissions` config, no new identity tables
   - Decision: G2 extends #209 `drive_offboarding_audit`; single approval gate
   - Decision: G4 establishes nucleo-platform service account ownership (per G4.1 recommendation)
   - Consequences: requires #209 to ship first OR coupled launch
   - Trade-offs: full automation vs manual button per metadata field

3. **Sub-issues G1-G4** on GitHub via `gh issue create`
   - Use section 6 sketches as starting body
   - Add acceptance criteria checklists matching #209/#211 style
   - Cross-reference #212 in body + add as sub-issues of #212

4. **PM signoff loop**
   - PM reviews architecture doc + ADR + matrix
   - Resolves the 9 decision points in section 5 (this doc proposes; PM ratifies)
   - Greenlights sub-issue spawning
   - **Then** implementation begins on individual sub-issues

### What this instance left UNDONE intentionally

- Sequence diagrams (text-only matrix is enough for spec phase)
- Detailed RLS policy text (architecture doc will need this; spec doesn't)
- API surface SQL for new RPCs (acceptance criteria territory, not spec)
- Permission seed exact rows (sub-issue territory)
- Multi-hub configuration sync (G5+ scope, beyond #212)

### Coordination signals to other instance

- This file is the only artifact this instance produced; safe to read without conflict
- If other instance touches this file, prefer ADD-ONLY (append new sections, don't rewrite). Surface conflicts to PM.
- Worktree: this instance did NOT create one (file lives on `main` branch — but the actual commit should land on `agent/issue-212` per the worktree-per-issue convention). PM/other-instance to create the worktree as needed.

---

## Appendix A — Verified live schema facts (p206 survey)

Captured via `mcp__supabase__execute_sql` for traceability:

- `persons.auth_id`: nullable (`is_nullable=YES`)
- `persons.secondary_emails`: `text[]` NOT NULL DEFAULT `'{}'`
- `persons.consent_status`: NOT NULL DEFAULT `'pending'`, CHECK enumeration not surfaced here
- `auth_engagements`: 16 columns including `person_id`, `initiative_id`, `kind`, `role`, `status`, `is_authoritative`, `agreement_certificate_id`, `requires_agreement`, `legacy_member_id`, `auth_id`
- `engagement_kinds`: 18 slugs (see §3.3); `is_initiative_scoped` defaults true; `retention_days_after_end` defaults 1825 (5y, LGPD aligned)
- `engagement_kind_permissions`: scope CHECK = `global|organization|initiative`; 121 rows across 11 kinds (7 kinds have zero rows)
- `partner_entities`: 14 columns; `mou_stage` CHECK has 8 states; no `partner_contacts` table (it's an engagement_kind, not a relational entity)
- `initiative_drive_links`: 10 columns with soft-unlink (`unlinked_at`, `unlinked_by`); no permission management columns
- `initiatives.metadata`: jsonb NOT NULL DEFAULT `'{}'`; validated by `trg_validate_initiative_metadata_fn`
- Vassouras initiative metadata fields observed: `venue`, `audience`, `our_role`, `event_date`, `whatsapp_url` (currently null in DB), `collaborators` (gp_name, leader_name, person_ids), `event_time_start`, `event_time_end`, `open_questions`, `teaching_scope`, `chapters_involved`, `confirmed_speakers`, `confirmed_unavailable`, `proposed_speakers_pending_confirmation`, `youtube_channel_event`, `youtube_channel_nucleo`, `initiative_subtype`, `logistics_external` (sponsorship_status, sympla_registration, audience_reached_youtube)

## Appendix B — Open questions for PM

These are NOT decisions resolved in section 5; they're meta-questions that affect how the spec frames itself.

1. **Multi-hub timing:** Is multi-hub readiness a v1 requirement for this spec, or a "design for it but don't implement yet" caveat? Affects how rigid we are on G4.1 service-account ownership.
2. **Nucleo-platform Google Workspace account:** Does this exist already? If not, PM needs to provision before G4 can advance.
3. **Vassouras manual workaround timing:** Should the workaround SQL/MCP runbook (§7) be drafted now (separate doc) or embedded in G1 sub-issue?
4. **#211 merge vs split:** Should #211 be closed as "subsumed by #212 G3" or kept as the implementation sub-issue?
5. **External member capability tier (G1.1):** PM preference for A (view+comment) vs B (view-only) — heavily influences sub-issue acceptance criteria.

## Appendix C — Cross-reference index

| Doc/Issue | Why it matters | Where referenced |
|-----------|---------------|-------------------|
| #204 | Parent umbrella | §0, §2 |
| #205 | member_emails pattern | §2, §G1.3 (decision) |
| #208 | Meet transcripts (same service-account context) | §2, §G4 |
| #209 | **HARD DEP** for G2 + G4 — service-account + audit infra | §1.C, §G2, §G4 |
| #210 | DB-driven classification principle | §2 |
| #211 | Subsumed by G3 | §2, §G3 |
| #110 | Board-level Drive (complementary) | §2, §3.4 |
| ADR-0005 | initiative-as-domain-primitive | §G2 |
| ADR-0006 | person-engagement-identity-model | §G1 |
| ADR-0007 | authority-as-engagement-grant | §G1 |
| ADR-0008 | per-kind-engagement-lifecycle | §G1 lifecycle |
| ADR-0009 | config-driven-initiative-kinds | §G1 (no new code) |
| ADR-0018 | mcp-threat-model | §G4 (threat model extension) |

---

**End of research foundation.** Next: other instance + PM consume + produce architecture doc, ADR draft, and sub-issues. This file should not need updates unless schema discoveries change (re-survey on boot per [[feedback_handoff_invariants_verify_on_boot]]).
