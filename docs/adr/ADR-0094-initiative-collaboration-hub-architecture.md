# ADR-0094 — Initiative Collaboration Hub architecture

**Status:** Proposed
**Date:** 2026-05-20
**Source:** Issue [#212](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/212)
**Related:** ADR-0005, ADR-0006, ADR-0007, ADR-0008, ADR-0009, ADR-0011, ADR-0018
**Hard dependency:** Issue #209 (Drive offboarding cascade) — must ship first or be coordinated.

---

## Context

PR #203 (p205) seeded the Vassouras initiative (`IA & Competências 2026 — Mesa Redonda Universidade de Vassouras`) via a direct INSERT migration. The shipping process surfaced five gaps that span identity, integration, authority, and UX:

- **G1** — How do we onboard external collaborators (PMI-RJ chapter board, university coordinators, students) without forcing them into Núcleo membership?
- **G2** — When someone joins or leaves an initiative engagement, why doesn't their Drive folder access reflect that automatically?
- **G3** — Why is initiative metadata (WhatsApp URL, Drive folder, recurring meeting time, YouTube, sponsorship) only editable via CLI/SQL when the DB stores it natively?
- **G4** — When the platform calls Google APIs (Drive, Calendar, Meet), what's the governance — whose service account, what audit, what rate limiting?
- **G5** — Recurring meeting time UI (deferred per #212 scope).

These gaps were filed separately as #209/#210/#211 + tactical issues, but those issues fight symptoms. The structural answer requires a coherent architecture sitting on top of the V4 domain model (ADR-0005..0009).

PM filed #212 to consolidate the architecture before implementation begins. Three architectural decisions were locked via interactive AskUserQuestion (2026-05-20); seven adjacent decisions were ratified inline in the architecture document based on staff recommendations.

This ADR records those decisions and their consequences.

---

## Decision

The **Initiative Collaboration Hub** architecture sits on three principles:

### Principle 1 — Engagements drive everything

Identity (G1), Drive permissions (G2), metadata authority (G3), and integration triggers (G4) are all functions of `auth_engagements` rows. No side-channels, no parallel grants, no per-feature identity model. New external collaborators are `persons` rows with `auth_id=NULL` (already supported per ADR-0006) plus `auth_engagements` rows of kind `partner_contact` / `external_reviewer` / `external_signer` / `speaker` / `guest`. Capability comes from `engagement_kind_permissions` seeds, not from new authority models.

### Principle 2 — Queue + cron + Edge Function for Google APIs

Postgres triggers never call Google APIs directly. They write rows to a new `google_api_jobs` queue table. A cron EF (`process-google-api-jobs`) drains the queue every minute, calls Google APIs via a shared client library, and writes audit rows to `google_api_call_log`. User-driven actions (e.g., "Create Drive folder now") call EF endpoints directly and bypass the queue, but still write to the audit log. This decouples Postgres transaction latency from Google API variability, gives us retry + dead-letter + audit, and isolates the service-account credential to a single EF runtime.

### Principle 3 — Reuse existing primitives ruthlessly

`persons.auth_id` is nullable today — use it for external identity rather than creating a new table. `engagement_kind_permissions` gates capability today — seed new rows rather than introducing a new authority model. `initiative_drive_links` records folder ↔ initiative — extend with engagement-level permission rows rather than restructuring. The hub adds three new tables (`engagement_drive_permissions`, `google_api_jobs`, `google_api_call_log`), one new RPC (`add_external_collaborator`), one new column on `engagement_kinds` (`retain_access_after_member_offboard`), one new column on `board_items` (`assignee_engagement_id`), one new action (`write_board_assigned`), and one new column on `initiative_kinds` (`auto_provision_drive_folder`). Everything else is seeds + triggers + UI.

---

## Locked decisions (PM 2026-05-20)

### G1.1 — External member capability tier

**Decision:** `partner_contact.liaison` engagement grants `view_initiative_dashboard` + `write_board_assigned`. The second is a NEW action that allows board write only on items where `board_items.assignee_engagement_id` references the caller's engagement.

**Rationale:** view-only is too restrictive for teaching use cases (Vassouras students collaborate on board cards). Full `write_board` + `view_pii` leaks PII to externals (LGPD risk). Scoped write hits the right balance — externals participate in their own work without seeing membership data.

**Implementation surface:** new action seed; new column on `board_items`; RLS extension on `board_items`; `can()` matcher for `write_board_assigned`.

### G2.4 — Cascade direction on Núcleo offboarding

**Decision:** Yes by default. When a Núcleo member is offboarded (member_status → inactive/alumni), all their active initiative-level engagement Drive permissions enter `pending_revoke` and flow through the same #209 approval batch. An override config `engagement_kinds.retain_access_after_member_offboard boolean default false` allows future engagement kinds (e.g., `alumni`) to opt out.

**Rationale:** LGPD Art. 16 (data elimination on termination) requires it for compliance. Coupling cascades through `engagement_kinds` config respects ADR-0009 (config not code) and lets future cases (alumni keeping history access) override without code changes.

**Implementation surface:** new column on `engagement_kinds`; #209's cron query filtered by the new column; `drive_offboarding_audit` extended with `engagement_id`.

### G4.1 — Service account ownership

**Decision:** An org-owned dedicated Google Workspace identity. PM provisions a Workspace user account (or service account inside Workspace) on a Núcleo-IA-controlled domain. The service-account credential is stored in Supabase Vault, accessed only by EFs, never by RPCs or frontend.

**Rationale:** PM's personal Google account creates a single point of failure — if PM departs, the revocation infrastructure breaks and the LGPD audit chain ruptures. Per-chapter service accounts are over-engineered for current scale (one active hub). Org-owned dedicated identity scales to the multi-hub future (each hub provisions its own Workspace tenant).

**Implementation surface:** PM operational task (provision Workspace + Vault entries) — blocks Phase B-D start. No code change beyond Vault key naming convention (`google_service_account_key_<organization_id>` for multi-hub).

---

## Ratified-inline decisions (architecture doc §11)

The following were staff recommendations accepted without separate AskUserQuestion. PM may override in PR review.

| # | Decision | Resolution |
|---|----------|------------|
| G1.2 | LGPD consent capture flow | PM-attested checkbox v1; email-link verification deferred to v2 |
| G1.3 | Multi-email model for `persons` | Reuse `persons.secondary_emails text[]`; generalize to `person_emails` only if external use cases reveal need |
| G2.1 | Engagement → Drive permission cardinality | 1 engagement → N folder permissions (one row per pair) |
| G2.2 | External member without Google account | Share-link fallback (`permission_type='anyone_with_link'`) + UI warning + audit |
| G2.3 | Drive folder auto-creation on initiative INSERT | Auto by default; per-kind opt-out via `initiative_kinds.auto_provision_drive_folder` |
| G3.1 | Permission to edit initiative metadata | New V4 action `manage_initiative` seeded for managers + initiative-scoped owners |
| G4.2 | Google API call envelope | Hybrid: queue+cron for trigger/batch flows, direct EF call for user-driven actions |
| M1 | Multi-hub readiness timing | Design from day one (every new table carries `organization_id`); defer implementation until 2nd hub is real |
| M2 | #211 status post-#212 | Keep #211 OPEN as G3 metadata-fields sub-issue; new G3 sub-issue covers composite flows |
| M3 | Vassouras workaround | Manual runbook documented in research foundation §7; can execute any time, no code dependency |

---

## Consequences

### Positive

- **One coherent surface for external collaboration.** Partner orgs, academic reviewers, event speakers, and student visitors all flow through the same identity (`persons`) + authority (`engagements`) layer. No fragmented per-use-case identity models.
- **Drive permission state is observable in DB.** `engagement_drive_permissions` mirrors Drive ground truth (after the cron drains). Audit + drift recovery + post-hoc analysis become possible without Drive API archeology.
- **LGPD compliance by construction.** Engagement-driven cascades + audit log mean Art. 16 (data elimination), Art. 18 (subject rights), and Art. 37 (DPO/audit) are all addressed structurally, not as bolt-ons.
- **Multi-hub future is unblocked.** Each new table carries `organization_id` from day one; the service-account model is per-org-keyed in Vault.
- **#209 becomes a load-bearing dependency** — its service-account + audit infra is the foundation for G2 + G4. Coordinated launch is cleaner than #209 alone.
- **Reduces ad-hoc CLI/SQL workload on PM.** Metadata edits + external onboarding move from PM-only to initiative-owner-self-service, enabling multi-hub scale.

### Negative / risk

- **Coupling to Google.** Drive + Calendar + Meet integration are now load-bearing for the collaboration UX. Google API outages or quota issues cascade into platform-visible failures. Mitigation: queue + retry + dead-letter + GP notification on failure.
- **One service-account credential is a high-value secret.** Compromise means an attacker could enumerate or revoke arbitrary Drive permissions. Mitigation: Vault-only storage, annual rotation, narrow scopes, audit log of every API call.
- **Schema mass increases.** Three new tables + three new columns + N new permission rows + new action. Each carries migration burden, contract test surface, and check_schema_invariants check. Mitigation: bundle migrations per phase (A-F in arch doc §9); maintain Phase C body-hash drift gate.
- **External member capability scope (`write_board_assigned`) requires new RLS logic.** Existing `write_board` RLS doesn't know about engagement-scoped assignment. New code surface; new audit surface. Mitigation: small, additive change; covered by contract tests for the G1 sub-issue.
- **`#209` becomes a critical path blocker.** If #209 slips, G2 + G4 slip. Mitigation: explicit coordination in milestone planning; consider shipping #209 + G2 + G4 as one wave.
- **PM operational dependency for service account.** Phase B-D cannot start until the Workspace tenant + service account are provisioned. Mitigation: scope this as a discrete PM task tracked separately (G4 sub-issue includes it as prerequisite).

### Neutral

- The hub doesn't break any existing feature. All new surfaces; existing RPCs and UI continue working unchanged.
- The hub doesn't constrain future architecture (e.g., a future "external community" tier could layer on top without reshaping these primitives).

---

## Alternatives considered (and rejected)

### Alternative 1 — Create a new `external_persons` or `external_collaborators` table

**Rejected because** `persons.auth_id` is already nullable, designed exactly for this case. Introducing a parallel table duplicates LGPD consent surface, fragments queries (`SELECT FROM persons UNION external_persons`), and violates ADR-0006's identity model principle.

### Alternative 2 — Add `external_collaborator` to `engagement_kinds`

**Rejected because** existing kinds (`partner_contact`, `external_reviewer`, `external_signer`, `speaker`, `guest`) already cover the use cases at different capability tiers. A new generic kind would either duplicate one of these or muddy the taxonomy. Following ADR-0009, the right move is to seed permissions on existing kinds.

### Alternative 3 — Skip the queue; call Drive API directly from triggers via `pg_net`

**Rejected because** Drive API latency (typically 200-500ms, occasionally seconds during quota throttling) would extend Postgres transaction times unpredictably, blocking everything else on the transaction. Failures would have to be caught in trigger logic, with no good place to log them. Queue + cron is the standard pattern for this exact case.

### Alternative 4 — Use PM's personal Google account as service account (status quo)

**Rejected because** it creates a single point of failure tied to a person's continued tenure, violates multi-hub readiness, and intermingles personal data residency with org infrastructure.

### Alternative 5 — Bundle G2 (engagement-Drive sync) into #209 directly

**Considered, partially adopted.** G2 extends #209's `drive_offboarding_audit` table and shares its revoke EF. But G2 has unique triggers (engagement INSERT/UPDATE, not just member offboard) and unique table (`engagement_drive_permissions`). Folding everything into #209 would inflate its scope past where PM scoped it. Keep them as separate sub-issues with explicit hard-dependency.

### Alternative 6 — Auto-grant Drive permissions without GP approval gate

**Rejected because** #209 already mandates per-row GP approval for revokes (LGPD audit + reversibility). Symmetric treatment for grants — at least for v1 — protects against errant trigger logic dumping permissions in bulk before review. Grants currently auto-execute; revokes go through approval gate; this asymmetry mirrors #209's approval-on-removal model.

### Alternative 7 — Build per-organization `tribe`-style hub instead of generalizing `initiative`

**Rejected because** ADR-0005 made `initiative` the domain primitive; `tribe` is a bridge for legacy compatibility. Reverting to per-feature tables (`tribe_collaborations`, `workgroup_collaborations`, etc.) duplicates work and contradicts the V4 consolidation.

---

## Implementation roadmap

See `docs/architecture/INITIATIVE_COLLABORATION_HUB.md` §9 for full phase-by-phase migration plan. Summary:

- **Phase A** — #209 ships, PM provisions Workspace + service account (parallel)
- **Phase B** — G4 infrastructure (queue table + audit log + cron EF skeleton)
- **Phase C** — G1 external onboarding (RPC + permissions seed + RLS + new column on `board_items`)
- **Phase D** — G2 engagement-Drive sync (table + triggers + EF extensions)
- **Phase E** — G3 metadata UI polish (#211 implementation + composite flow UI)
- **Phase F** — Vassouras tactical workaround (independent, can run any time)

Each phase is one or two sub-issues. The architecture doc identifies four sub-issues to spawn from #212 (G1, G2, G3, G4) covering Phases B-E.

---

## Open items (PM final pass before this ADR moves to Accepted)

1. Confirm locked decisions G1.1, G2.4, G4.1 accurately captured.
2. Accept or flag the ten ratified-inline decisions (table in arch doc §11 / above in this ADR).
3. Decide whether #209 must ship before G2 starts, or whether they ship as one wave.
4. Provide service-account provisioning timeline (Phase B-D blocker).
5. Approve spawning the four G1/G2/G3/G4 sub-issues from this architecture.

When PM signs off on all five, this ADR moves to Accepted and implementation begins.

---

## References

- Architecture doc: `docs/architecture/INITIATIVE_COLLABORATION_HUB.md`
- Research foundation: `docs/architecture/INITIATIVE_COLLABORATION_HUB_RESEARCH.md`
- Issue #212 (source) · #209 (hard dep) · #211 (subsumed by G3) · #204 (parent umbrella)
- ADR-0005 initiative-as-domain-primitive · ADR-0006 person-engagement-identity-model · ADR-0007 authority-as-engagement-grant · ADR-0008 per-kind-engagement-lifecycle · ADR-0009 config-driven-initiative-kinds · ADR-0011 V4 auth pattern · ADR-0018 MCP threat model (extended in arch doc §7.5)

---

**Assisted-By:** Claude (Anthropic)
