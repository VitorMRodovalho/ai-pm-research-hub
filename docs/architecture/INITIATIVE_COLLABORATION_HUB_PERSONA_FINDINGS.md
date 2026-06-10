# Persona findings — Phase 1 discovery (#212)

**Status:** Phase 1 complete (5 personas, 2026-05-20 p206). Phase 2 council pending.
**Companion:** [`INITIATIVE_COLLABORATION_HUB.md`](./INITIATIVE_COLLABORATION_HUB.md) (now provisionally Draft) · [`INITIATIVE_COLLABORATION_HUB_RESEARCH.md`](./INITIATIVE_COLLABORATION_HUB_RESEARCH.md) · [`../adr/ADR-0094-initiative-collaboration-hub-architecture.md`](../adr/ADR-0094-initiative-collaboration-hub-architecture.md) (now Draft, ratification frozen)

**Personas run:** GP-leader · External-partner-liaison · CPMAI-student · CPMAI-alumni · External-speaker/professor

**Concomitant evidence:** [BUG-212.A](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/217) (notification email link 404 — validates external persona G0 finding)

---

## 1. Premises in current spec that personas INVALIDATED

| # | Premise (current spec) | Personas that broke it | Why |
|---|------------------------|------------------------|-----|
| **P1** | "1 engagement INSERT → grant Drive permission on ALL `initiative_drive_links` of that initiative" (§5.3 trigger) | CPMAI-student, CPMAI-alumni | Student paying for cycle 3 would get permission on `study_group_internal_workspace` + `cpmai_alumni_archive` automatically. Internal team revenue/planning data leaks instantly. No audience filter on the trigger. |
| **P2** | "External onboarding is 1-at-a-time via modal" (§4.7 + §6.2) | GP-leader | Vassouras T-11d = ~50 people to add (5 comms + 6 curation + 7 Tribo 3 + 3 PMI-RJ + 30 students). 50 modals × manual consent attestation = unusable. |
| **P3** | "External = `persons.auth_id=NULL`; spec covers external onboarding" (§4) | GP-leader | The Vassouras add list is mostly INTERNAL members (comms, curation, tribe). Spec has ZERO surface for "add existing member to this initiative" — assumes everyone is external. |
| **P4** | "PM-attested checkbox is sufficient LGPD consent for v1" (§4.4 / ADR-0094 G1.2) | External-partner-liaison, CPMAI-student, Speaker | (a) For 30 students it's mass-forgery exposure (Art. 7 §I); (b) for João Coelho he never sees the consent text he allegedly accepted; (c) for speakers it doesn't cover image rights / voice biometric (Art. 11) / YouTube publication. ANPD would consider weak. |
| **P5** | "Notifications work / external knows they were added" | External-partner-liaison + **BUG-212.A live evidence** | `_enqueue_engagement_welcome` writes to outbox but generates 404 URL. Externals have no Núcleo login path either way. Whole external UX is broken silently. |
| **P6** | "Engagement is per-initiative, no further sub-scope" | CPMAI-student, CPMAI-alumni | CPMAI cycle 1/2/3 share one program but need cycle-bound material access + cycle-end retention policy. No `cohort_tag` / cycle sub-scope in spec. |
| **P7** | "Default `default_duration_days` covers all kinds" | Speaker, CPMAI-alumni | Speaker is 1-event (90d wrong); alumni want lifetime (90d wrong). Need `default_duration_mode` enum: `static_days` / `event_date_plus_days` / `cycle_end_plus_days` / `lifetime`. |
| **P8** | "Engagement state transitions are INSERT (add) or revoke" | GP-leader (Sarah↔Fernando) | No `transition_engagement(p_engagement_id, p_new_kind, p_new_role)` RPC. Sarah-style kind/role swaps force revoke + add, creating 5-50min Drive permission gap window. p205 already shipped a `change-função` button in MCP that spec ignores. |
| **P9** | "`engagement_drive_permissions.UNIQUE (engagement_id, drive_folder_id, status)` is sufficient" (§5.1) | GP-leader | Concurrent INSERTs race; role upgrades (observer→leader) need UPDATE path not insert-then-revoke. Spec is INSERT-only. |
| **P10** | "Cascade cleanup is member-level (#209)" (§5.6 G2.4) | GP-leader, CPMAI-student | Engagement-level revoke (committee_member ends, but person still member) doesn't fire any cascade. Students offboard at cycle-end but aren't members → cascade query doesn't match. |

## 2. Premises CONFIRMED by personas (these hold)

| # | Premise | Why it survives |
|---|---------|----------------|
| C1 | `persons.auth_id=NULL` as identity primitive for externals | All 5 personas accepted this; no friction. |
| C2 | `partner_contact` as engagement kind for partner liaison | External-partner-liaison persona walked it; capability tier (view + comment) felt right scoped. |
| C3 | Service account ownership = org-owned (not PM personal) | Reinforced across personas (security risk if PM personal). |
| C4 | `link_initiative_to_drive` + `initiative_drive_links` as the folder-link primitive | All Drive-touching personas built on it; no contradiction. |
| C5 | V4 `can()` as authority gate | No persona suggested bypassing or replacing. |

## 3. NEW decision points (uncovered by personas)

Cross-referenced to current spec gap labels (G1-G4) + new (G0 / G5 / G6):

### G0 — External communication primitive (NEW gap, was missed entirely)
- **G0.1** — External notification channel: (A) extend `notification_outbox` with optional `recipient_email`, (B) new `external_notification_outbox` table, (C) EF direct send no DB row, (D) defer. **Recommend A.**
- **G0.2** — External authentication primitive: (A) magic-link JWT in engagement row + middleware bypass, (B) Google OAuth-on-demand with email match, (C) Drive-only no dashboard surface, (D) defer to v2. **Recommend A** (B as enhancement).

### G1 — External onboarding (expanded)
- **G1.4** — Bulk add UX: (A) CSV import for guests only + per-row modal for partner_contact, (B) spreadsheet-style inline grid, (C) external form link self-attest. **Recommend A.**
- **G1.5** — Internal-member-to-initiative path: (A) extend `add_external_collaborator` with auto-routing (detect existing member, skip person create), (B) new dedicated RPC `add_internal_member_to_initiative`, (C) UI dispatches to p205's `manage_initiative_engagement`. **Recommend A.**
- **G1.6** — Per-engagement LGPD consent: (A) separate `engagement_consent_log` per engagement (Art. 8 §6 specific), (B) global `persons.consent_status` covers all (current spec, simpler but fragile), (C) hybrid — internal kinds reuse, external re-prompt. **Recommend A.**
- **G1.7** — Conflict warning on cross-initiative concurrent engagements: (A) hard block when partner_entity mismatch, (B) soft warning GP confirms, (C) silent allow. **Recommend B.**

### G2 — Drive sync (expanded)
- **G2.5** — Engagement-level (non-member) offboarding cascade: (A) same #209 approval gate fires when ANY engagement→inactive, (B) only member-level cascade, (C) configurable per `engagement_kinds.cascade_drive_on_revoke`. **Recommend A.**
- **G2.6** — Drive permission role transitions: (A) UPDATE-in-place via new `drive_permission_update` job type (zero downtime), (B) revoke+regrant with brief window (current spec implicit), (C) block role transitions on engagements with active permissions. **Recommend A.**
- **G2.7** — Drive folder audience filter: (A) `initiative_drive_links.audience_kinds text[]` declarative, (B) `audience_filter jsonb` rich predicates (kind + role + cohort_tag), (C) per-folder RPC. **Recommend B.**
- **G2.8** — Drive folder partition strategy for partners: (A) per-external-collaborator subfolder, (B) per-purpose folder with role mapping, (C) document-level ACLs, (D) status quo (commenter on primary). **Recommend A for v1 + B for cross-cutting.**
- **G2.9** — Drive API batch operations: (A) `batchUpdate` for bulk-add (1 API call for N permissions), (B) sequential per-row jobs (current spec), (C) hybrid (batch >5 rows). **Recommend C.**

### G3 — Metadata UI (expanded)
- **G3.2** — Engagement transition UI: (A) new `transition_engagement` RPC + UI button, (B) extend `manage_initiative_engagement` p205 MCP, (C) force revoke+add. **Recommend A.**
- **G3.3** — Board card author/PII visibility for externals: (A) full name visible, (B) "Núcleo IA member" placeholder for non-coordinator viewers, (C) initials only, (D) mask all. **Recommend B + audit log of every external view.**

### G5 — Speakers/recording rights (NEW gap area)
- **G5.1** — Recording consent capture timing: (A) at invitation accept (blocks send-of-invite), (B) at event check-in (too late), (C) post-event signed link (legally risky), (D) implicit via invite ToS (reject — not valid LGPD). **Recommend A.**
- **G5.2** — Slide ownership after engagement ends: (A) Núcleo owns + archives + republish, (B) speaker retains, Núcleo gets non-exclusive perpetual educational license, (C) Núcleo only 1 cycle then deletes, (D) speaker chooses per-talk. **Recommend B.**
- **G5.3** — Multi-time speaker model: (A) N separate engagements 1 per event same person_id, (B) one long-running engagement spanning cycles, (C) new `recurring_speaker` kind, (D) recurring_speaker as role in `speaker` kind. **Recommend A.**
- **G5.4** — YouTube deletion default: (A) full delete (file removed from Google CDN) — LGPD-strict, (B) unlist only, (C) speaker chooses at recording-consent capture, (D) tier by content type. **Recommend A.**
- **G5.5** — Audience-in-frame consent: (A) per-attendee opt-in at check-in, (B) recording = implicit consent via event registration (NOT VALID), (C) single-camera speaker lock, (D) post-record blur/crop. **Recommend A.**
- **G5.6** — Speaker bio/photo self-service: (A) signed-token self-service page no auth, (B) speaker creates Núcleo membership, (C) PM proxies all edits, (D) pre-filled from partner_entity if linked. **Recommend A.**
- **G5.7** — `external_reviewer` curriculum review action surface: (A) add `review_curriculum_materials` + `comment_on_wiki_page` actions, (B) reuse `participate_in_governance_review`, (C) new kind `curriculum_reviewer`, (D) status quo PM forwards email. **Recommend A.**

### G6 — Alumni/cohort lifecycle (NEW gap area)
- **G6.1** — Cycle materials retention policy: (A) lifetime via `alumni` engagement + Drive retain flag, (B) 5y default per engagement-end then revoke, (C) tier-based (paid=lifetime, scholarship=2y), (D) per-cycle config on `initiative_kinds.material_retention_policy`. **Recommend D.**
- **G6.2** — Auto-promotion to `alumni` kind: (A) trigger on `study_group_participant.status='completed'`, (B) manual GP, (C) cron weekly sweep, (D) explicit alumni opt-in at cycle-end. **Recommend D** (LGPD Art. 7 separateness).
- **G6.3** — Multi-engagement role precedence: (A) most recent active wins, (B) highest-capability wins, (C) UNION of all capabilities, (D) explicit per-surface in `engagement_kind_permissions`. **Recommend C with carve-out for `view_pii` (intersection).**
- **G6.4** — Communication preferences vs data retention: (A) one consent surface opt-out=anonymize, (B) separate `communication_preferences jsonb` opt-out only flips notification, (C) per-channel granular consent table. **Recommend B v1, C if alumni scales.**
- **G6.5** — Alumni-only initiative architecture: (A) one global alumni initiative per org, (B) per-cycle alumni initiative, (C) hierarchical (program-alumni containing cycle-archive sub-folders), (D) no alumni initiative — board lives in original cycle with re-scope. **Recommend C.**
- **G6.6** — Cross-hub alumni: (A) persons per-org (current); cross-hub = new persons row, (B) shared persons table cross-org, (C) federated directory. **Recommend defer to multi-hub ADR** but flag now to avoid identity-table rework.

### G7 — Engagement state machine (NEW)
- **G7.1** — Cycle/cohort sub-scope: (A) dedicated `cohorts` table linked to initiatives, (B) `auth_engagements.cohort_tag text` free-form, (C) `initiatives.metadata.cohorts jsonb[]`. **Recommend A** (reporting + cron queries).
- **G7.2** — `default_duration_mode`: (A) static_days (current), (B) event_date_plus_days for speakers, (C) cycle_end_plus_days for participants, (D) lifetime for alumni. **Recommend all 4 modes as enum.**
- **G7.3** — Payment integration (CPMAI): (A) external SaaS webhook → `payment_status` table → engagement sync, (B) manual PM toggle, (C) defer to v2. **Recommend A.**
- **G7.4** — Speaker `event_speakers` bridge table: (A) new table linking engagement ↔ event ↔ talk metadata (talk_title, abstract, bio, photo, slides_drive_id, recording_youtube_url), (B) jam into `auth_engagements.metadata jsonb`, (C) reuse `initiatives.metadata.speakers[]`. **Recommend A.**

## 4. Cross-cutting patterns surfaced

| Pattern | What it implies |
|---------|-----------------|
| **No bulk operations anywhere** | Spec is 1-row-at-a-time everywhere. Real ops are bulk (Vassouras 50, CPMAI cycle batch 30). Need bulk RPCs across add/revoke/extend/transition. |
| **No "internal member" add path** | Spec assumes external = new. But >80% of "add to initiative" is existing members. Single biggest framing miss. |
| **No transition primitive** | Sarah↔Fernando p205 already needed this. Spec doesn't acknowledge. Force revoke+add breaks Drive permissions. |
| **No audience filter on Drive trigger §5.3** | CPMAI students would auto-leak into internal workspace. Single biggest LGPD/business risk. |
| **No cycle/cohort sub-scope** | CPMAI requires it. Vassouras one-off doesn't surface this — bias toward Vassouras-only thinking. |
| **No external auth primitive** | `auth_id=NULL` means external can't access dashboard. Drive-only UX strands ~half of G1.1 capability tier (`view_initiative_dashboard` unreachable). |
| **PM-attested consent too weak for batch** | 30 students = mass forgery. Need email-link verification at v1 (not v2) for non-trivial volumes. |
| **No image rights / voice biometric / publication consent** | Speakers + students with recordings + transcription. LGPD Art. 11 (biometric) + civil Art. 20 (image) exposure. Damage R$5k-50k per professor typical. |
| **No retention clock separation** | Alumni community vs cycle-end material vs engagement-end vs persons-anonymization — all collapsed to one clock. Need 3 separate clocks. |
| **No payment-status hook** | CPMAI is revenue. Engagement stays active even on payment lapse. Needs Hotmart/Stripe webhook integration. |

## 5. Spec impact summary

| Section of current spec | Status post-personas |
|-------------------------|---------------------|
| Section 1-3 (purpose/goals/overview) | Mostly holds; add G0 + G5 + G6 to gap inventory |
| Section 4 (G1 external onboarding) | **Heavy rewrite needed** — add bulk RPC, internal-member path, per-engagement consent, audience-aware grants, recording/image consent fields |
| Section 5 (G2 Drive sync) | **Audience filter is the biggest gap.** Add §5.7 audience_kinds/audience_filter to `initiative_drive_links`. Add §5.8 role transition (UPDATE path). Extend cascade to engagement-level (G2.5). Add batch API support (G2.9). |
| Section 6 (G3 metadata UI) | Add transition UI + bulk selectors + audience-filter management |
| Section 7 (G4 Google API gov) | Add `youtube_video_delete` job type. Add image-rights / recording-consent fields capture in EF. Add `_shared/pii-redactor` for `google_api_call_log.payload_summary`. |
| Section 8 (multi-hub) | Add cross-hub identity flag (defer to multi-hub ADR) |
| Section 9 (migration plan) | Add Phase A.5 (G0 notification primitive) BEFORE G1. Add Phase D.5 (G6 alumni) AFTER G2. |
| ADR-0094 G1.1/G2.4/G4.1 locked decisions | **G1.1 partner_contact.liaison perms HOLD** but need additional carve-outs for board_card author masking. **G2.4 cascade default HOLD** but extend to engagement-level (G2.5). **G4.1 service account HOLD** unchanged. |
| ADR-0094 status | **Frozen at Draft** until persona findings synthesized into spec rewrite + council Phase 2 |

## 6. Recommendations for Phase 2 council (5 agents paralelo)

Council agents should consume:
- `INITIATIVE_COLLABORATION_HUB.md` (current spec — what to critique)
- `INITIATIVE_COLLABORATION_HUB_RESEARCH.md` (foundation context)
- `INITIATIVE_COLLABORATION_HUB_PERSONA_FINDINGS.md` (this file — evidence base)
- `ADR-0094-initiative-collaboration-hub-architecture.md` (decision summary)

Per-agent focus:

| Agent | Specific questions |
|-------|---------------------|
| **product-leader** | Bulk operations as v1 must-have? Multi-hub timing now or later? CPMAI as separate spec issue? Prioritization G0-G7 → which slip to v2? |
| **security-engineer** | 2-account split (service vs Gemini personal) — risks? External JWT magic-link — attack surface? Audience filter SQL injection surface? `engagement_drive_permissions` race conditions? Annual key rotation runbook? |
| **data-architect** | Bulk RPC pattern (single audit row vs N rows)? `audience_filter jsonb` vs `audience_kinds text[]`? Cohort as table vs column? Race conditions on Drive permission UPDATE path? Dedup heuristic for `add_external_collaborator` (citext + secondary_emails + members.email)? |
| **legal-counsel** | PM-attested consent enforceability under Art. 7+8? Image rights Art. 20 CC for speakers + audience-in-frame? Voice biometric Art. 11 for transcripts? YouTube Art. 18 deletion vs unlist? Alumni retention LGPD Art. 16 vs legitimate interest? Cross-org `partner_entity` engagement Art. 7 §VI carve-out? |
| **ux-leader** | Bulk add CSV vs grid vs form? Audience filter UI (admin)? Engagement-card list visualization? Transition button vs revoke+add? Speaker self-service portal pattern? External landing-page vs Drive-only UX trade-off? |

Output target: each agent ~600 words structured findings; synthesis merges into final spec rewrite + ADR-0094 ratification cycle.

## 7. Risk register (post-personas)

| Risk | Severity | Mitigation pre-implementation |
|------|----------|-------------------------------|
| Drive trigger §5.3 leaks CPMAI internal data to students | HIGH (business + LGPD) | Add audience filter BEFORE shipping G2. Block trigger if any folder has no audience_filter set. |
| 30-student batch consent forgery | HIGH (LGPD Art. 7) | Mandatory email-link verification for batch size ≥ 5. PM-attested only for ≤4 with high-trust attestation chain. |
| External notifications all 404 (BUG-212.A live) | HIGH (UX + LGPD audit chain) | Fix BUG-212.A (issue #217) BEFORE G1 ships. |
| Speaker recording without explicit Art. 11/20 consent | HIGH (lawsuit) | Speaker invitation flow MUST capture image + voice + publication consent. Block invite send without it. |
| Cycle 2 alumni Drive permission auto-revoked on engagement-end | HIGH (business promise broken) | Implement G6.1 + G6.2 BEFORE first cycle completes. Alumni opt-in at cycle-end ceremony. |
| Cross-initiative person re-uses consent silently | MEDIUM (LGPD Art. 8 §6 specificity) | Implement G1.6 per-engagement consent before adding multi-engagement persons. |
| Sarah↔Fernando-style transitions break Drive | MEDIUM (operational) | Implement G3.2 transition_engagement RPC + G2.6 UPDATE-in-place path BEFORE pattern recurs. |
| `partner_entity` PMI-CE/PMI-RJ mismatch silent | MEDIUM (governance) | Implement G1.7 soft warning before multi-chapter engagements multiply. |

---

**Next:** Phase 2 council review (5 agents paralelo) → synthesis #2 → spec rewrite → ADR-0094 Draft → Proposed ratification cycle → PM signoff → sub-issue spawn.
