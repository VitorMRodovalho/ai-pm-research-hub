# Backlog Reconciliation — 2026-06-12

**Status:** operational overlay on top of `BACKLOG_ROADMAP_2026-06.md`.
**Source of truth queried this session:** `gh issue list --state open --limit 1000`.
**Scope:** current open GitHub issues plus the June roadmap deltas. This file does not replace the ratified June roadmap; it rebases its execution queue.

## Live Snapshot

Live open issues: **75**.

Priority-label distribution:

| Priority label | Count |
|---|---:|
| `priority:high` | 22 |
| `priority:medium` | 22 |
| `priority:low` | 7 |
| no `priority:*` label | 24 |

Issues created since `2026-06-02`: **31**.

Implication: the ratified roadmap remains useful as the strategic map, but the active queue must be rebased. Several original Wave 0/Wave 1 issues have since closed, and a new governance/legal/onboarding cluster has appeared.

## Reconciliation Rule

Use this order when choosing work:

1. **Live breakage / trust defects**: RLS, governance signing, member state, event visibility, data shown incorrectly.
2. **Legal/compliance preconditions**: DPA/PostHog, legal instrument readiness, LGPD/IP registry, material-change backbone.
3. **Fan-out gates**: small decisions or specs that unblock multiple issues.
4. **Operational product flow**: onboarding, directors/focal-point access, selection and meetings.
5. **Polish / low-risk follow-ups**: a11y, minor UX, performance, deferred integrations.

Meta issues, tracking issues, discussions, and epics should not compete with leaf implementation items.

## P0 Queue

These are the next executable items. They either fix live breakage or unblock immediate institutional/legal work.

| Issue | Lane | Why now | Next action |
|---|---|---|---|
| #643 | Foundation / Integration | `edit_document_version_draft` was a hard blocker for draft governance edits. The issue body says migration `20260805000147` was already applied, but the issue is still open. | Verify local migration/test state, run the relevant contract gate, then close/update the issue if shipped. |
| #651 | Foundation + Frontend | Parallel governance gates are modeled incorrectly in UI and notification logic. This is latent now, but it will break any future same-order gate chain. | Fix grouped `order` semantics in `ReviewChainIsland`, `GovernancePipelineBar`, admin document loops, and `_enqueue_gate_notifications`; add a parallel-gate contract test. |
| #625 | Foundation + Frontend | `/admin/members` mixes active members with pre-onboarding, inflating active counts and confusing V4 member state. It is the core bug under the onboarding epic #660. | Ship Camada 0 first: derived `pre-onboarding` display state, separate counters, and a contract test for the cohort rule. Defer full V4-native member page filters. |
| #642 | Governance + Integration | PostHog PII and sub-operator inventory are factual prerequisites before signing the DPA. This is not just documentation polish. | Stop sending direct name/email person properties, define pseudonymous identity behavior, and produce the sub-operator inventory for Anexo I. |
| #630 | Foundation / Frontend | Agenda da Semana still has structural drift from `events`, and `retention_rate` still intersects the #625 pre-onboarding denominator bug. | Split: PM confirmation for T4/T6 recurrence, then engineering decision on derived-from-events vs reconciliation cron. Fold the retention fix into #625. |
| #670 | Frontend / Governance | Institutional designations such as `chapter_liaison`, `voluntariado_director`, and `certificacao_director` are not function-anchored consistently. It causes real focal-point visibility gaps. | Start with the narrow `chapter_liaison` designation permission wiring and contract test. Queue director panels separately. |

## P1 Queue

Important, but should follow or run in parallel only when the P0 owner lane is not blocked.

| Issue | Lane | Recommended disposition |
|---|---|---|
| #632 | Governance | Keep as a clean-session umbrella for platform-readiness docs. Do not implement as one large PR. Dispatch leaves for inventory, redirect/domain, import-as-v0, and `/library` decision. |
| #645 | Foundation / Frontend | Required before real chapter signatures, but after lock-v0/legal return. Prepare catalog/spec now; implementation after document versions stabilize. |
| #646 | Foundation / Frontend | Valuable preview/export capability for reviewers. Align with ADR-0102 and draft-reader security; do not rush before #651/#654-style gate hardening is fully stable. |
| #641 | Governance / Legal Ops | Prepare the skeleton for Manual R3 data clauses, but final text is gated on G12/legal return. |
| #638 | Governance / Legal Ops | Engineering exists; operation is gated on legal/PM decisions. Prepare the asset inventory plan, then wait for the hold to lift before registering declarations. |
| #640 | Governance / DevOps | Add LICENSE after confirming dual-license wording: MIT for code and CC-BY-SA 4.0 for docs. Low technical risk, but should be reviewed for IP consistency. |
| #639 | DevOps / Legal Ops | Release stamping is useful but should follow #638/#640 so the object being stamped and licensing stance are settled. |
| #633 | Foundation / Frontend | Events hygiene after #631. Good P1/P2 operational cleanup; avoid mixing with #630 unless the same migration/RPC surface is touched. |
| #234 | MCP / Integration | Still relevant for connector refresh/listing strategy; sequence after the governance/legal P0s unless active connector failure recurs. |

## PM Decision / Blocked

These should stay visible, but they are not first leaf work until the gate is answered.

| Issue | Gate |
|---|---|
| #660 | Epic/tracker, not a leaf. Execute its sequence through #625 and #106 rather than coding directly against the epic. |
| #661 | Strategic discussion. Convert to specs/leaves only after PM chooses the model. |
| #617 | Blocked by the `pmigo-plataforma` track. |
| #574 | Blocked legal-ops periodic oversight; keep for compliance planning. |
| #573 | Medium-priority legal feature; can wait behind #642/#571/#572. |
| #334 | External/legal G12 path. Keep open and timestamp the actual validated send when it happens. |
| #333 / #335 | Still blocked by prior sequencing and ratification gates. |
| #233 | Blocked analytics rebuild; needs canonical source/spec decision. |
| #108 / #109 | PM data collection, not engineering-first. |

## Meta / Tracking

Do not pick these as implementation leaves:

- #478 — roadmap tracking umbrella.
- #588 — lessons-learned intake.
- #612 — remote branch triage chore.
- #660 — onboarding epic; dispatch children.
- #632 — platform-readiness umbrella; dispatch leaves.

## Recommended Next Sprint Shape

Run at most three lanes in parallel:

1. **Foundation lane:** #643 verification/closure, then #651.
2. **Frontend/Foundation lane:** #625 Camada 0, coordinated with #630 retention denominator.
3. **Governance/Legal lane:** #642 inventory/remediation, with #641/#638 prepared but not forced through legal gates.

After those, pull #670 as the next narrow least-privilege access fix, then decide whether to spend a clean session on #632 or continue onboarding via #660 -> #106.

## Gate Reminder

For any implementation PR spawned from this reconciliation:

- SQL/RPC changes follow GC-097 and must include migrations plus relevant contract tests.
- i18n changes require all three dictionaries.
- Route/nav changes must update `navigation.config.ts`, admin constants, and `PERMISSIONS_MATRIX.md` when applicable.
- Final gates remain `npm test`, `npm run build`, and route smoke when relevant.
