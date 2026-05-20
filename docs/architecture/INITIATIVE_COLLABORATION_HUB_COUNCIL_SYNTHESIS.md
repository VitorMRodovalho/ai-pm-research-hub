# Council Synthesis — Phase 2 final findings (#212)

**Status:** Phase 2 complete (5 council agents, 2026-05-20 p206). Ready for PM signoff loop.

**Inputs synthesized:**
- 5 persona findings (Phase 1 — `INITIATIVE_COLLABORATION_HUB_PERSONA_FINDINGS.md`)
- 5 council reviews (Phase 2 — product-leader · security-engineer · data-architect · legal-counsel · ux-leader)
- Original architecture spec (`INITIATIVE_COLLABORATION_HUB.md`)
- ADR-0094 (currently demoted to Draft)
- BUG-212.A (#217 — notification 404 confirmed live)

**Companion files** (read in this order):
1. This file — actionable consolidation
2. `INITIATIVE_COLLABORATION_HUB_PERSONA_FINDINGS.md` — evidence base
3. `INITIATIVE_COLLABORATION_HUB.md` — original architecture (now subject to rewrite)
4. `INITIATIVE_COLLABORATION_HUB_RESEARCH.md` — schema/cross-ref foundation
5. `../adr/ADR-0094-initiative-collaboration-hub-architecture.md` — Draft, awaiting rewrite

---

## 1. Executive verdict — council vote tally

| Council member | Vote | Headline |
|----------------|------|----------|
| product-leader | **SCOPE-CUT** | "Spec conflates 2 products. Ship Vassouras-only v1 with internal-member path; spawn #212.b for CPMAI" |
| security-engineer | **BLOCK on 3 items** | "Drive trigger w/o audience filter + write_board_assigned RLS absent + speaker consent fields absent — non-shippable" |
| data-architect | **BLOCK on G2** | "Audience filter mandatory pre-trigger. UNIQUE constraint logically broken. 11-migration ordered roadmap required." |
| legal-counsel | **NÃO SHIPPAR v1** | "4 LGPD show-stoppers including a RETROATIVE one (Whisper voice biometric in prod without Art. 11)" |
| ux-leader | **GO-WITH-CHANGES** | "4 critical UX gaps + 6 new UI components to design before implementation" |

**Verdict:** ADR-0094 stays Draft. Spec needs structural rewrite (not patches). 4 of 5 council members recommend BLOCK or major rework. UX is the most permissive but identifies 4 must-fix gaps before any UI ships.

---

## 2. Consensus v1 blockers (cannot ship without resolving)

| # | Blocker | Severity | Endorsed by | Source |
|---|---------|----------|-------------|--------|
| **B1** | `_enqueue_engagement_welcome` generates `/iniciativas/[id]` (404) | HIGH UX + LGPD audit chain | All 5 council | [#217](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/217) live evidence |
| **B2** | Drive trigger §5.3 has zero audience filter — CPMAI internal-data leak on first student INSERT | CRITICAL LGPD Art. 6 §I + §III | security, data, legal, ux, product | Persona P1 + arch §5.3 |
| **B3** | `write_board_assigned` RLS extension does NOT exist in any migration; capability silently broken OR force-widened to full `write_board` | CRITICAL (broken access ctrl A01) | security, data | Migration scan |
| **B4** | PM-attested consent for batch ≥5 = mass-forgery liability under Art. 7 §I | CRITICAL legal (R$50M cap fine) | legal, security, product | Vassouras 30-student case |
| **B5** | Whisper transcription (p197d) live processing voice biometric WITHOUT Art. 11 explicit consent — RETROACTIVE show-stopper | CRITICAL legal | legal | Live in prod |
| **B6** | Speaker engagement RPC has no `recording_consent`/`image_consent`/`youtube_publication_consent` fields | CRITICAL legal (Art. 11 + CC Art. 20 + Art. 18) | legal, security | Persona Speaker findings |
| **B7** | No "add existing internal member to initiative" path — 80% of Vassouras adds are internal, spec is 100% external-first | HIGH operational (T-11d blocker) | product, ux | Persona GP-leader P3 |
| **B8** | No bulk operations — 1-modal-at-a-time forces SQL workaround for any N>3 | HIGH operational | product, ux, data | Persona GP-leader P2 + Vassouras T-11d |
| **B9** | External `auth_id=NULL` person cannot reach `/initiative/[id]` (middleware blocks). `view_initiative_dashboard` capability is phantom. | HIGH UX | ux, security | Persona External-partner-liaison G0.2 |

### What B5 (Whisper) means in practice

`analyze_application_video` EF (p197d) is currently transcribing voice for candidate evaluations. LGPD Art. 11 §I treats voice as dado sensível biométrico. Art. 11 §II hypotheses are taxative — "finalidade educacional" / "legítimo interesse" NOT included. Only basis available: consent explicit + destacado per Art. 11 §I + Art. 8 §§1-6. **No such consent capture exists today** for the candidate or speaker flow.

**Immediate action required (legal counsel call):**
- Block new transcriptions until consent field exists
- Notify candidates/speakers already transcribed of the data treatment + offer deletion (Art. 18 §IV)
- Add the consent capture before any new INSERT into `pmi_video_screenings` or `selection_evaluation_ai_suggestions` with `evaluation_type='video'`

This is NOT a #212 issue per se — it's a cross-cutting LGPD remediation that #212 surfaced. File as separate critical-priority issue.

---

## 3. Critical surprises (not in original spec)

| # | Surprise | Impact | Source |
|---|----------|--------|--------|
| **S1** | **ADR-0078 magic-link pattern already exists** for `external_reviewer`. G0.2 should REUSE it, NOT build custom 90d JWT | Avoids 90d revocable-credential class; reuses ratified pattern | security |
| **S2** | **`engagement_drive_permissions` UNIQUE constraint logically broken** — partial UNIQUE on status allows concurrent INSERT race | Spec UNIQUE redesign mandatory before any INSERT path ships | data |
| **S3** | **`view_pii` should be INTERSECTION, not UNION** in multi-engagement composition — fail-closed for PII | New `_can_all()` helper; existing `can()` hot path unchanged | data |
| **S4** | **`initiative_kinds` likely NOT a table** today — probably CHECK constraint on `initiatives.kind`. Need `initiative_kind_config` table in Phase A.5 | Migration ordering depends on this. Verify via information_schema | data |
| **S5** | **Drive trigger §5.3 fires on direct SQL INSERT bypassing add_external_collaborator gate checks** | RAW `INSERT INTO auth_engagements` from MCP/admin silently grants Drive without consent validation | security |
| **S6** | **Drive API `batchUpdate` NOT OPTIONAL** for bulk N≥10 — sequential 50× 250ms = 37.5s wall, hits Supabase EF limit | G2.9 batch is must-have, not enhancement | data |
| **S7** | **Service account DWD (Domain-Wide Delegation) risk** not surfaced — if granted, blast radius = ALL org data (not just Núcleo folders) | Provisioning runbook MUST explicitly forbid DWD + restrict to `drive.file` scope (not `drive` full-access) | security |

---

## 4. Revised v1 scope (council consensus)

### MUST SHIP v1 (Vassouras wave)
1. **B1 fix: #217 — `_enqueue_engagement_welcome` URL `/iniciativas/` → `/initiative/`** (1-line migration, 30min effort)
2. **G3 metadata UI #211** — WhatsApp + Drive folder + YouTube + recurring meeting time + sponsorship (independent of G1/G2, M~4-6h)
3. **G1-internal-member path (P3)** — extend existing `manage_initiative_engagement` (p205 MCP) for "add existing member to initiative" via UI button. Reuse existing `change-função` modal pattern. (M~3-4h)
4. **G1 bulk add for partner_contact ≤10 + external students public form `/join/[initiative_id]`** (M~6-8h)
5. **G4 service account provisioning (PM ops task)** — blocks all Drive work. PM provisions org-owned Workspace identity. No DWD. `drive.file` scope only. (PM 2-4h ops)
6. **BUG p197d Whisper consent retroactive** — separate critical-priority issue, blocks new transcriptions until consent gate ships
7. **MOU with Universidade de Vassouras** (legal ops task, ~3-5 dias minuta) — institutional consent base for 30 students (Art. 7 §V), avoids individual self-attestation friction for T-11d

### SHIP v2 (post-Vassouras, sequenced wave)
1. **G2 engagement-Drive sync** — ONLY after audience filter (B2 fix) + `write_board_assigned` RLS (B3 fix) + UNIQUE redesign (S2 fix) + `#209` drive_offboarding_audit base
2. **G0.2 external auth primitive** — reuse ADR-0078 magic-link (S1) — NOT custom JWT
3. **G3 composite flows** — "Add external collaborator" modal + "Provision Drive folder" button (depends on G1 + G2)
4. **G7.2 default_duration_mode enum** + `engagement_consent_log` table — per-engagement LGPD consent (Art. 8 §6)

### DEFER to dedicated CPMAI spec (#212.b — spawn now as stub)
1. **G6 alumni/cohort lifecycle** — entire section is CPMAI-prerequisite. No alumni exist yet.
2. **G7.1 cohorts table** — CPMAI-prerequisite
3. **G7.3 payment integration** (Hotmart/Stripe) — separate product
4. **G5 speaker rights full spec** — Vassouras 2-3 speakers don't justify 7 decision points; minimal Termo de Speaker form covers risk
5. **G6.6 cross-hub alumni identity** — defer to multi-hub ADR, flag in ADR-0094 as known-deferred

### NEVER (rejected per legal/security)
1. **PM-attested consent for batch ≥5** — rejected by legal (R$50M risk). Replace with email-link verification OR institutional MOU (Universidade Vassouras).
2. **Custom 90d JWT for external auth** — rejected by security (no revocation path, phishing surface). Use ADR-0078 pattern.
3. **YouTube unlist as Art. 18 deletion** — rejected by legal. Full delete or hosting on Drive privado.
4. **Service account with DWD** — rejected by security (blast radius unacceptable). `drive.file` scope only.

---

## 5. Decision points matrix — DEDUPLICATED (final list, 26 decisions)

After deduplicating across 5 personas + 5 council outputs:

### Identity + onboarding (G0, G1)
| ID | Decision | Recommended | Source |
|----|----------|-------------|--------|
| **G0.1** | External notification channel | extend `notification_outbox` with optional `recipient_email` | Persona + security |
| **G0.2** | External authentication primitive | **REUSE ADR-0078 magic-link** (NOT custom JWT) | security (S1) |
| **G1.1** | partner_contact.liaison capability | view + `write_board_assigned` (assigned cards only) | PM locked 2026-05-20 |
| **G1.2** | LGPD consent capture (size ≤4) | PM-attested with evidence (email confirm / WhatsApp screenshot) | legal |
| **G1.3** | LGPD consent capture (size ≥5) | email-link verification MANDATORY v1 (not v2) | legal, product |
| **G1.4** | Bulk add UX | inline multi-row form ≤10; public `/join/[id]?token=` form for students | ux |
| **G1.5** | Internal-member-to-initiative path | extend `add_external_collaborator` with auto-routing (members.email FIRST → existing flow) | data, product |
| **G1.6** | Per-engagement consent storage | new `engagement_consent_log` table (Art. 8 §6 specificity) | legal, data |
| **G1.7** | Cross-org partner_entity conflict | soft warning + GP confirm | data |
| **G1.8** | Multi-email model for persons | `secondary_emails text[]` v1 (defer `person_emails` table) | data |

### Drive sync (G2)
| ID | Decision | Recommended | Source |
|----|----------|-------------|--------|
| **G2.1** | Engagement→permission cardinality | 1 engagement → N folder permissions | persona |
| **G2.2** | External w/o Google account | share-link fallback + UI warning + audit | persona |
| **G2.3** | Drive folder auto-creation | auto + per-kind opt-out via `initiative_kind_config.auto_provision_drive_folder` | persona |
| **G2.4** | Cascade default direction | yes default + `engagement_kinds.retain_access_after_member_offboard` override | PM locked 2026-05-20 |
| **G2.5** | Engagement-level non-member offboarding cascade | same #209 approval gate fires when ANY engagement→inactive | data, security |
| **G2.6** | Role transitions Drive permission | UPDATE-in-place via new `drive_permission_update` job type (PATCH permissions/{id}) | data, ux |
| **G2.7** | Audience filter representation | **`audience_filter jsonb` rich predicates** + GIN index (NOT text[]) | data |
| **G2.7.b** | Default audience for new folder | **"Nenhum acesso configurado" (opt-in, NOT opt-out)** | ux |
| **G2.8** | Drive folder partition for partners | per-external-collaborator subfolder + role-mapped purpose | ux, security |
| **G2.9** | Drive API batch operations | `batchUpdate` MANDATORY for N≥10 (NOT enhancement) | data |
| **G2.10** | UNIQUE constraint design | drop partial filter; state machine + `ON CONFLICT DO UPDATE` | data (S2) |

### Metadata + governance (G3, G4)
| ID | Decision | Recommended | Source |
|----|----------|-------------|--------|
| **G3.1** | Permission to edit metadata | new V4 `manage_initiative` action seeded for managers + initiative-scoped owners | PM ratified |
| **G3.2** | Engagement transition UI | extend p205 `manage_initiative_engagement` modal with `transition_engagement` RPC | ux |
| **G3.3** | External viewer PII masking on board cards | "Núcleo IA member" placeholder for non-coordinators + audit each view | persona, legal |
| **G4.1** | Service account ownership | **org-owned dedicated identity, NO DWD, `drive.file` scope only** | PM locked + security (S7) |
| **G4.2** | Google API call envelope | hybrid (queue for triggers, direct EF for user-driven) | persona |
| **G4.3** | `google_api_call_log` PII redactor | hardcoded `jsonb_build_object` at EF (NEVER include emailAddress raw) | security, data |

### Speakers + LGPD (G5)
| ID | Decision | Recommended | Source |
|----|----------|-------------|--------|
| **G5.1** | Recording/image/voice consent capture | at invitation accept (blocks send-of-invite without it) | legal, persona |
| **G5.2** | Slides IP licensing | speaker retains + Núcleo non-exclusive educational license (Lei 9.610/98) | legal |
| **G5.4** | YouTube deletion default | full delete (NOT unlist) — Art. 18 §IV | legal |
| **G5.5** | Audience-in-frame consent | per-attendee opt-in at check-in (or speaker-only camera lock) | legal |
| **G5.6** | Speaker bio/photo self-service | signed-token portal `/speakers/edit/<token>` (no auth) | ux, persona |

### Multi-hub + meta (M)
| ID | Decision | Recommended | Source |
|----|----------|-------------|--------|
| **M1** | Multi-hub readiness timing | design from day one (organization_id everywhere), defer impl until 2nd hub real | product |
| **M2** | #211 status | keep open as G3 metadata-fields sub-issue | PM ratified |
| **M3** | CPMAI scope | **spawn #212.b stub NOW with persona findings G6/G7 content** | product |
| **M4** | Vassouras T-11d unblock | use manual workaround runbook (RESEARCH §7) — NOT block on G1-G4 | product |
| **M5** | initiative_kinds as table | create `initiative_kind_config` in Phase A.5 (verify via information_schema first) | data (S4) |

---

## 6. Migration plan revision (11 ordered migrations + 4 contract tests)

Per data-architect (definitive ordering):

| Phase | Migration file | Content | Dependencies |
|-------|---------------|---------|--------------|
| **A.5** | `create_initiative_kind_config.sql` | Create `initiative_kind_config` table, seed existing kind slugs, add FK from `initiatives.kind` | precondition for B,C,E |
| **B.1** | `create_google_api_tables.sql` | `google_api_jobs` + `google_api_call_log` + `drive_permission_update` job type | A.5 |
| **C.1** | `add_audience_filter_to_drive_links.sql` | `initiative_drive_links.audience_filter jsonb NOT NULL DEFAULT '{}'` + GIN index + backfill existing rows | B.1 |
| **C.2** | `cohorts_and_engagement_consent_log.sql` | `cohorts` table + `auth_engagements.cohort_id` FK + `engagement_consent_log` + GIN indexes on `secondary_emails` | A.5 |
| **C.3** | `engagement_kinds_duration_and_cascade.sql` | `default_duration_mode` enum + `retain_access_after_member_offboard` + kind-specific seed updates | A.5 |
| **C.4** | `g1_permissions_seed_and_board_items.sql` | engagement_kind_permissions seed + new `write_board_assigned` action + `board_items.assignee_engagement_id` + RLS extension | C.3 |
| **C.5** | `add_external_collaborator_rpc.sql` | New RPC with internal-member auto-routing + bulk variant `add_initiative_engagements_bulk` | C.1, C.2, C.4 |
| **D.1** | `engagement_drive_permissions_table.sql` | Table with REVISED `UNIQUE(engagement_id, drive_folder_id)` (non-partial) + `drive_offboarding_audit` extension | C.1, C.4 |
| **D.2** | `engagement_drive_sync_triggers.sql` | `_trg_engagement_drive_sync_grant` (audience-filter-aware) + revoke mirror + raw-INSERT guard | D.1 + C.1 audience filter backfilled |
| **E.1** | `initiative_kind_config_auto_provision.sql` | `auto_provision_drive_folder boolean` column + seed | A.5 |
| **E.2** | `register_hub_invariants.sql` | DROP+CREATE `check_schema_invariants()` adding R.hub.1 through R.hub.5 | D.1, D.2 |

**Contract tests to add:**
- `tests/contracts/audience_filter.test.mjs` — 4 cases (kinds-only, kind+role, cohort_tag-only, empty)
- `tests/contracts/engagement_drive_permissions_race.test.mjs` — concurrent INSERT scenarios
- `tests/contracts/add_external_collaborator_dedup.test.mjs` — 5-step heuristic edge cases
- `tests/contracts/multi_engagement_can.test.mjs` — view_pii intersection + UNION for other actions

---

## 7. UI components to design (6 new, ux-leader-defined)

| Component | Purpose | Complexity | Mobile (375px)? |
|-----------|---------|------------|-----------------|
| `ExternalCollaboratorRowForm.tsx` | Multi-row inline form for 2-10 partner_contact adds w/ per-row consent | Medium | 2-row layout required |
| `DriveAudienceFilterChips.tsx` | Per-folder chip multi-select for `audience_kinds`; amber warning if empty | Low-medium | Touch-safe chip group |
| `EngagementTransitionModal.tsx` | Replaces inline change-kind action; calls `transition_engagement` RPC + Drive UPDATE warning | Medium | Existing modal pattern |
| `ExternalPortalPage.astro` | New route `/external-portal?token=<jwt>`; no BaseLayout; stripped initiative summary | HIGH | Naturally mobile-first |
| `SpeakerSelfServicePage.astro` | New route `/speakers/edit/<token>`; single-page, 5 sections, 3 mandatory consent checkboxes; Drive upload via Worker proxy | HIGH | 44x44px tap targets |
| `BulkStudentInviteForm.astro` | New public route `/join/[initiative_id]?token=`; no auth; individual self-attestation per student | Medium-high | LGPD-correct consent UX |

**i18n + mobile + a11y review** required per UX before any of the 6 ships. Configurações tab uses **gear icon on mobile** (no text label) to fit 7+ tab row.

---

## 8. Documentation to create (legal-counsel-mandated)

| Doc | Purpose | Effort |
|-----|---------|--------|
| **Aviso de Privacidade para Colaboradores Externos** | Per-purpose data treatment notice; LGPD Art. 9 mandatory; referenced in all consent email-links | 4-6h legal review |
| **Termo de Participação Speaker** | Consolidates image (CC Art. 20) + voice biometric (Art. 11) + YouTube vs Drive publication + slides license (Lei 9.610/98) + revogabilidade | 6-8h legal review |
| **Acordo de Cooperação Institucional (template)** | For partner orgs (Universidade Vassouras, future chapters); covers batch institutional consent + Art. 7 §V execution-of-contract base | 4-6h legal review + per-partner customization |
| **Política de Retenção e Ciclo de Vida de Dados** | Formalizes 3 separate clocks (materials / communications / identity); base for cron config | 2-3h |
| **Adendo Política de Privacidade Principal** | Section on event recordings + AI transcription + YouTube deletion rights | 2-3h |

**Legal counsel call:** ANPD has explicit guidance on Art. 11 biometric — get advogada Angeline review on Termo de Speaker before any new transcription INSERT.

---

## 9. ADR-0094 next steps

Current state: **Draft (demoted from Proposed 2026-05-20 p206 after persona findings)**.

To move Draft → Proposed → Accepted, the following amendments required:

1. **Section "Decisions" update**: replace G1.2 (PM-attested only) with G1.2+G1.3 threshold (≤4 attested, ≥5 email-link)
2. **Add Section "Locked from council" (new)** with G2.7 audience filter + G2.10 UNIQUE redesign + G2.9 batchUpdate mandatory + S1 ADR-0078 reuse + S7 service account no-DWD
3. **Add Section "Deferred to #212.b"** with G6 + G7.1 + G7.3 + G5 full spec
4. **Migration roadmap section**: replace original Phase A-F with revised 11-migration order from §6 above
5. **Move Section "Open items" → "Resolved + Open"** with status per decision
6. **Update References**: add ADR-0078 (magic-link pattern reuse), ADR-0060 (G7 welcome email — context for BUG-212.A), Lei 9.610/98 (IP), CC Art. 20

ADR-0094 should NOT be ratified until:
- B5 (Whisper retroactive Art. 11) has its own remediation issue filed + first migration applied (block new transcriptions)
- Universidade Vassouras MOU signed OR alternative individual-consent path implemented
- Council findings #2 (this doc) reviewed by PM
- B7 P3 internal-member-path resolved at spec level

---

## 10. Sub-issues to spawn (revised from original 4 → 8)

| # | Sub-issue | Was | Now | Spawn timing |
|---|-----------|-----|-----|--------------|
| 1 | BUG-212.A welcome URL fix | — | **#217 (already filed)** | NOW — independent |
| 2 | Whisper Art. 11 consent gate (retroactive) | — | NEW issue (legal-blocker) | NOW — independent |
| 3 | G1 external onboarding + bulk + internal-member | G1 (M ~6-8h) | G1 (L ~10-14h after re-scope) | After PM signoff |
| 4 | G2 engagement-Drive sync + audience filter atomic | G2 (L ~10-12h) | G2 (L ~14-18h with audience filter + race fix) | After #217 + #209 + G1 |
| 5 | G3 Configurações tab + metadata UI (subsumes #211) | G3 (M ~3-4h) | G3 (M ~6-8h with composite flows) | Concurrent with G1 |
| 6 | G4 service account + queue + audit (subsumes #209 partially) | G4 (M-L ~6-8h) | G4 (M-L ~8-10h with no-DWD constraint + PII redactor) | NOW (PM ops blocker) |
| 7 | #212.b CPMAI architecture (G6 + G7.1 + G7.3 + G5 full) | — | NEW spec issue (L ~6-10h) | NOW as stub, populate later |
| 8 | Universidade Vassouras MOU | — | Legal/governance issue | NOW (T-11d blocker) |

Sub-issue bodies for G1-G4 (revised) require rewrite from `INITIATIVE_COLLABORATION_HUB_SUB_ISSUES.md` — preserved as v0 reference; v1 spec rewrite needed before spawn.

---

## 11. Open items for PM final pass

Before this synthesis converts to ratified spec + sub-issue spawn:

1. **Confirm scope-cut to Vassouras-only v1** (per product-leader recommendation) — or override with broader v1 scope
2. **Whisper Art. 11 RETROACTIVE remediation** — agreed to file as critical-priority separate issue + block new INSERTs?
3. **MOU with Universidade Vassouras** — legal-ops timeline acceptable (3-5 dias)? Who drafts (Angeline / Vitor)?
4. **Service account provisioning** — PM ops task timeline; confirm `drive.file` scope + no DWD constraint
5. **Spawn #212.b stub NOW** for CPMAI — or wait until first CPMAI cycle commits?
6. **PR #214 disposition** — merge as Draft, or keep open until ADR-0094 ratifies?
7. **`SUB_ISSUES.md` revision** — rewrite before spawn, or PM uses council synthesis directly?
8. **G1.3 email-link verification implementation** — reuse ADR-0078 pattern (Supabase Auth magic-link)?

---

## 12. Effort estimate (revised v1)

Original estimate: ~30h across G1-G4 sub-issues.
Revised v1 estimate (council scope-cut + new prereqs):

| Item | Effort |
|------|--------|
| BUG-212.A fix #217 | 0.5h |
| Whisper Art. 11 gate (retroactive) | 2-3h (migration + EF guard + consent capture form) |
| G4 service account ops (PM) | 2-4h ops |
| G4 queue + audit + PII redactor | 8-10h |
| G3 #211 metadata UI | 4-6h |
| G1 internal-member-path + bulk ≤10 + public student form | 10-14h |
| G2 engagement-Drive sync with audience filter | 14-18h (depends on #209 base — could be 22-26h if both at once) |
| Universidade Vassouras MOU | 3-5 dias legal-ops |
| 5 LGPD docs (privacy notice + speaker term + cooperation template + retention policy + privacy adendum) | 18-26h legal review |
| ADR-0094 rewrite + ratification | 4-6h |
| **TOTAL v1** | **~65-90h dev + 3-5 dias legal-ops** |

v2 wave (G2 hardening + G0.2 external auth + composite flows + #212.b CPMAI): estimated ~40-60h additional.

---

**End of synthesis.** Next: PM review of this doc + 8 open items in §11 → ADR-0094 amendment cycle → revised sub-issue spawn → implementation.

Council, personas, BUG-212.A, ADR-0078 reference, and all reviewed files documented above. No further synthesis pending.
