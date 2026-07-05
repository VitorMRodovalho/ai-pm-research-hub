# Backlog Reconciliation — 2026-06-28

| Metric | Count |
|---|---|
| Open issues | 77 |
| priority:high | 11 |
| priority:medium | 21 |
| priority:low | 6 |
| unlabeled (no priority label) | 39 |

(Numbers grounded live this session via `gh issue list`.)

> **Method:** 10 triage agents read full body + comments of ~8 issues each (live `gh issue view`), classified against the Reconciliation Rule, and flagged already-shipped close-candidates. Each close-candidate was then adversarially verified (refute "it's done"; default keep-open on residual). Synthesis produced the queues below.

## ⚠️ Verification addendum — #785 is a live confidentiality leak (verified 2026-06-28)

The #785 close-candidate verifier flagged an **active P0 confidentiality leak**. Independently re-grounded with live SQL this session:

- **1** initiative has `visibility='confidential'` (of 27), with **1 board, 23 board_items, 10 events** of real content (the Cadência Presidência×GP case).
- **8 SECURITY DEFINER reader RPCs** that surface that content (`list_active_boards`, `list_board_items`, `get_board_members`, `get_board_activities` [overloaded x2], `get_item_assignments`, `get_card_full_history`, `get_card_timeline`, `list_meeting_action_items`) — **none** call `rls_can_see_initiative()` / filter `confidential`.
- `list_active_boards()` body is `SELECT ... FROM project_boards WHERE is_active=true` with **zero caller check** → returns the confidential board to any authenticated member, **no id-guessing**.

This violates CLAUDE.md Key Decision #5 ("Any new SECDEF read RPC over initiative-linked tables MUST apply the gate") and #785 acceptance invariant #6. **Do not disclose in a public GitHub issue before the fix** (public repo; mirror the #869 no-pre-fix-disclosure pattern).

## What changed since 2026-06-12

`priority:high` dropped **22 → 11** and unlabeled grew **24 → 39** — the queue got less "everything is urgent" and more "nobody labeled it." Of the prior **P0 = [643, 651, 625, 642, 630, 670]**, five CLOSED (643, 651, 625, 642, 630); only **670** is still open. Of the prior **P1 = [632, 645, 646, 641, 638, 640, 639, 633, 234]**, four are still open (**632, 641, 638, 633**) and five CLOSED (645, 646, 640, 639, 234). The legal-ops cluster (632/638/641) remains stuck behind the same G12 legal-counsel return; 633 is now down to a low-risk historical reclassification. Net: live-trust and legal-precondition work dominates the real queue, and 39 issues need a priority label before any of this is legible.

## Close-candidates (verify before closing)

| Issue | Verdict | Evidence / Residual | Action |
|---|---|---|---|
| **785** | keep-open-residual | **P0 SECURITY LEAK live in prod** (verified above). ~8 SECURITY DEFINER readers bypass `rls_can_see_*` and leak the confidential GP×Presidência board to any non-engaged member, **no id-guessing**. 3rd recurrence of the under-enumeration pattern. | **DO NOT CLOSE. Split a new P0 security issue NOW**: gate the ~8 confirmed RPCs, audit all ~86 SECDEF readers over the 8 initiative-linked tables, add a contract test that fails on ANY ungated SECDEF reader, re-prove non-engaged=0. File PI-track follow-up. |
| 816 | keep-open-residual | History rewrite executed on `main`, but `refs/pull/677/head` still resolves with sensitive PDFs/agreements (~530 `refs/pull/*` remain); GitHub Support ticket pending. 2 sensitive docs still tracked + unignored on main (`docs/drafts/p269_briefing_…pdf`, `docs/drafts/p277_email_desligamento_alumni_…md`). 2nd-pass review + optional CI guard not done. | Keep open, **scoped**: (a) forward-protection for the 2 still-tracked docs now; (b) file/confirm GH Support refs/pull ticket; (c) split residual REVIEW + CI guard into a small issue. |
| 676 | keep-open-residual | AC#1–7 shipped; #696 delivered the leader self-service follow-up but used "Refs #676" (never reconciled). AC#8 unmet: no governance doc describes recurring-agenda source-of-truth/reconciliation routine. | Reconcile: tick AC#1–7, record #696, write the one AC#8 governance paragraph, then close. Near-zero effort. |
| 753 | keep-open-residual | All 4 hardening items shipped + LIVE (migs 192/256/257; commits d475368d, 80e6fb2d on main). Only residual: the discretionary "review member-photos posture" sub-note (still `public=true`) was never recorded. | **Safe to close with one decision line** (keep member-photos public, or flip to private+signed). One-liner closes it. |
| 902 | keep-open-residual | Headline (#903) + Fase 1 (#904, dormant) shipped. Fase 2 re-anchor explicitly deferred to cycle5+new ADR. Derived issues #905/#906 remain open (already tracked separately below). | **Close**; spawn deferred Fase 2 under a fresh cycle5 issue/ADR. |

## P0 Queue (executable now)

Live breakage / trust defects + fan-out. Excludes close-candidates, Meta, Blocked. (Note: the #785 security split is the de-facto P0-zero — see addendum.)

| Issue | Lane | Why now | Effort | Next action |
|---|---|---|---|---|
| **906** | Selection | Live trust defect: committee-lead without `manage_platform` gets `success:true/approved:0` and believes a candidate was approved (silent rollback). | S | Add outer-gate check in `finalize_decisions`: require `manage_platform` up front when any decision is `approved`, else per-decision error; contract test (ADR-0007). |
| **670** | Foundation | Institutional designations grant access silently-broken when held alone; chapter_liaison fixed, but `voluntariado_director` + `certificacao_director` wiring + panels unshipped — same access-defect class, 7 non-keyed directors. | M | Wire both directors in `DESIGNATION_PERMISSIONS` mirroring `filiacao_director` (#659) + contract test; scope Certificação/Voluntários (#106) panels. |
| **692** | Analytics | Data-correctness defect + fan-out: retention shows 68% vs 98.6% on a KPI headed for external PMI-LATAM decks; unblocks deck + public-impact page + annual-KPI labeling. | M | Trace both formulas via `execute_sql`, pick + document canonical denominator, relabel both surfaces, audit `get_public_impact_data`. |
| **806** | MCP/Integration | Live code defect: `create_external_speaker_engagement` still silently drops the partner→initiative link every run (no fix commit; live body never writes `metadata.partner_entity_id`). | L | Implement G1: persist `origin_partner_entity_id` FK + `metadata.partner_entity_id`; add partner-reuse guard; align `manage_partner` enum (pmi_global/academic). |

## P1 Queue

Important; parallels/follows P0. Legal preconditions whose build mechanism is unblocked + cheap proactive hardening.

| Issue | Lane | Why now | Effort | Next action |
|---|---|---|---|---|
| **928** | Comms | Latent auth trap (the #738/#849 class that broke prod twice) in the now-live daily IG publishing EF; works only while callers present the env key. Cheap proactive fix. | S | Replace literal env-key compare in `publish-instagram/index.ts` (~L156–162) with `isServiceRoleToken()` from `_shared/service-auth.ts` (mirror commit 813d137). |
| **570** | Gov/Legal | LGPD image/voice consent opt-in (Parecer 01/2026 rec e); mechanism is self-contained + unblocked, only the public clause go-live waits on G12. | M | ALTER `consent_records` + opt-in/revogação RPCs reusing #568 immutable flow; surface in `export_my_data`; gate only clause go-live behind G12. |
| **905** | Gov/Legal | Real LGPD minimization gap (Art.6,III): member-anchored anonymize cron never reaches pre-member rejected/withdrawn applicants → PII retained indefinitely. Cron buildable in parallel with legal input. | M | Build `created_at`/cycle-close-anchored anonymization cron with `NOT EXISTS` member check (preserve scores, scrub identifiers); confirm window with legal-counsel. |
| **572** | Gov/Legal | LGPD Art.18 subject-rights / institutional portability; Slice A buildable now (Block C cron already live). | L | Scope Slice A (institutional dump JSON/CSV/SQL + data dictionary + self-audit entry); coordinate export body with #569 Slice 4 to avoid duplicating `export_my_data`. |
| **573** | Gov/Legal | Conditional international-transfer clauses (GDPR/SCC/IDTA); rendering/log/metric plumbing ships ahead of the gated legal copy. | M | Add residence field, condition clause assembly on residence∈{EEA,UK}, record rendered variant in signed-instrument audit trail, expose EEA-active count. |
| **574** (Slice A) | Gov/Legal | DPO-designation half is Blocked on #334/G12, but the audit-log hash-chain integrity slice is self-contained. | L | Land Slice A (hash-chain integrity over audit log, reusing `check_schema_invariants`); defer DPO/committee audit-access role to post-#334. |
| **571** | Gov/Legal | Material-change backbone is the governance-versioning precondition; XL → the SPEC decomposition is itself the fan-out gate. | L | Author SPEC decomposing into ~4 slices (re-accept state machine, version pin, ratification quorum gate, per-obra audit trail) before any build. |

## P2 / Later

| Issue | Lane | One-liner |
|---|---|---|
| 105 | Frontend | `/me/reunioes` widget; backend ready, ~2–3h UI build. |
| 165 | Gov/Legal | Governance/release backfill p40–p201 (docs hygiene). |
| 172 | Comms | Reconcile stale May webinar calendar vs live comms surface (#924/#909). |
| 173 | Onboarding | Rogério Peixoto reintegration as observer (single lifecycle action). |
| 200 | Analytics | Cloudflare traffic tab on `/admin/analytics` (server-side, no client tokens). |
| 206/207/208 | MCP/AI | Gemini-3.5-Flash eval → YouTube ingest / Meet transcripts; re-ground model claims first. |
| 210 | Gov/Legal | Calendar recurrence cleanup; blocker (member_resolve_email) now live. |
| 235 | DevOps | bypass-audit v2 counting refinement (noise, not defect). |
| 311 | Gov/Legal | Generalized evidence_bundle SPEC; reconcile with #308. |
| 335 | Gov/Legal | Remove stale `status:blocked`; run §Open-items + Tier-3 review, flip ADR-0094 Proposed→Accepted. |
| 455 | Foundation | Backfill 17 legacy alumni certs via reusable `issue_alumni_certificate` RPC. |
| 485 | MCP | Only Part 3 (GCal import/sync) remains; split + close umbrella. |
| 587 | Foundation | Bulk `link_events_to_initiative` to kill N+1 (low urgency). |
| 591 | Frontend | Gamification toggle persistence — gated on cohort telemetry. |
| 601 | Frontend | MemberDrillDown `<div>`→`<h4>` a11y (heading-nav). |
| 612 | DevOps | Triage ~30 legacy `agent/p*` branches. |
| 633 | Foundation | Reclassify legacy `type='geral'` events (PM list). |
| 704 | Selection | Onboarding-boundary fuzzy-match dedup guard (n=1, latent). |
| 707 | MCP | `create_initiative`/`get_webinar`/`link_webinar_to_initiative` MCP slice (fan-out enabler). |
| 718 | Analytics | Split protagonismo XP bucket — deferred (0 XP today). |
| 727 | Frontend | `/admin/members` state/country + PMI-affiliation filters. |
| 729 | Gov/Legal | Cláusula-11 isolated image-consent revocation field (latent LGPD). |
| 736 | Foundation | Move claim/verify token query→fragment hash. |
| 737 | Onboarding | `/claim` auto-refresh session post-confirm. |
| 811 | Frontend | R-NEWS showcase feed on landing (scope decision first). |
| 880 | Comms | LinkedIn org-publishing Phase 2 (new scope + UI). |
| 885 | MCP | Comms member-asset bundle (legal-counsel gate on Cláusula 11). |
| 888 | Frontend | Drop double-rocket emoji + `.maybeSingle()` in ChaptersSection. |
| 901 | Gov/Legal | ZZ bucket k-floor wording — batched to 2026-07-26 /privacy review. |
| 909 | Comms | Auto-mirror/sync governed for Newsletter board (workaround exists). |
| 911 | Comms | SLA/visibility for items stuck in `leader_review`. |
| 912 | MCP | `set_event_recording` MCP tool over existing `update_event`. |

## Blocked / PM-decision

| Issue | Gate |
|---|---|
| 96 | G12 legal (IP policy + Termo de Adesão under_review) + "Frontiers" trademark clearance. |
| 108 | 8 permanent Google Meet links from tribe leaders (WhatsApp). |
| 132 | PM scope decision (chapter_shared_resources table vs Drive folder). |
| 183 | Approval/agreement RPCs must stabilize; term template held for redesign (#873). |
| 233 | `status:blocked` + PM spec (canonical source per card, ROI window, quality criteria). |
| 334 | Angeline (legal-counsel) async clock: ANPD Art.48, Art.18 template, DPO designation, Adendo Privacidade. |
| 574 (DPO half) | #334 DPO designation act (Slice A is in P1 above). |
| 617 | External pmigo-plataforma snapshot DB not running. |
| 634 | DNS zone `pmigo.org.br` on HostGator; deferred until chapter address is primary. |
| 638 | doc7/term HOLD (#625) + G12 + PM asset-scope decision. |
| 641 | G12 legal final annex language before Manual R3. |
| 809 | PM product design decision (self-service draft vs PM-offline) + Cycle 4 timing + ADR-0103. |

## Meta / Trackers (do not pick as leaves)

- **92** — calendar integration umbrella (folded #416; blocks #210).
- **93** — APM/WhatsApp-MCP/Briefing/Akita opportunity tracker (→ 4 sub-issues on PM pick).
- **109** — consolidated PM-action tracker (meeting-link/cadence backfills).
- **204** — Gemini + Drive/calendar governance epic (#205–#210).
- **212** — initiative-as-collaboration-hub spec (ADR-0094; spawns G1–G4).
- **280** — Semantic MCP Gateway spec/tracker (alpha shipped; further waves).
- **300** — external_reviewer onboarding refactor (10 gaps; split on PM escalation).
- **308** — curator evidence-bundle planning issue (reconcile with #311).
- **348** — booking-URL roadmap (v1 shipped; only Step 4 remains → spawn + close).
- **588** — standing `[LL]` lessons-learned intake; never close.
- **632** — platform-readiness umbrella (lock-v0 gated on G12).
- **660** — Filiado→Voluntário onboarding EPIC (active operational thread; do #670 first).
- **661** — Verticais×Quadrantes×Tribos discussion (leadership ratification).
- **873** — pré-onboarding gamification EPIC (4 PM product decisions).
- **883** — /admin/comms audit umbrella (PR-3..PR-8 roadmap).

## Unlabeled triage (39 issues)

Apply these `priority:*` labels. Tier shown for routing.

**Suggested priority:high (4)**
| Issue | Suggested | Tier |
|---|---|---|
| 660 | high | Meta (EPIC) |
| 753 | high | Close-candidate (→close) |
| 785 | high | Close-candidate (→split P0 security) |
| 816 | high | Close-candidate (→keep scoped) |

**Suggested priority:medium (19)**
| Issue | Suggested | Tier |
|---|---|---|
| 455 | medium | P2 |
| 632 | medium | Meta |
| 638 | medium | Blocked |
| 641 | medium | Blocked |
| 661 | medium | Meta |
| 670 | medium | **P0** |
| 692 | medium | **P0** |
| 707 | medium | P2 |
| 727 | medium | P2 |
| 729 | medium | P2 |
| 811 | medium | P2 |
| 883 | medium | Meta |
| 885 | medium | P2 |
| 902 | medium | Close-candidate (→close) |
| 905 | medium | **P1** |
| 906 | medium | **P0** |
| 909 | medium | P2 |
| 911 | medium | P2 |
| 928 | medium | **P1** |

**Suggested priority:low (16)**
| Issue | Suggested | Tier |
|---|---|---|
| 348 | low | Meta |
| 587 | low | P2 |
| 588 | low | Meta ([LL]) |
| 591 | low | P2 |
| 612 | low | P2 |
| 633 | low | P2 |
| 634 | low | Blocked |
| 704 | low | P2 |
| 736 | low | P2 |
| 737 | low | P2 |
| 809 | low | Blocked |
| 873 | low | Meta (EPIC) |
| 880 | low | P2 |
| 888 | low | P2 |
| 901 | low | P2 |
| 912 | low | P2 |

## Recommended next-sprint shape

Three parallel lanes; pull the named issue first in each.

0. **(P0-zero) #785 SECDEF confidentiality leak** — gate the ~8 ungated readers + audit all SECDEF readers over the 8 initiative-linked tables + contract test. This precedes lane 1.
1. **Trust & security.** **#906** (selection silent no-op, S) → **#670** (director access wiring, M) → **#692** (canonical retention metric, M, unblocks the PMI-LATAM deck).
2. **LGPD / legal-precondition build-ahead.** **#570** (image/voice consent mechanism) → **#905** (pre-member anonymization cron) → **#572** Slice A (institutional export). All buildable now; only public clause/copy waits on G12.
3. **Close-out & cheap wins.** Close **#753** (one-line member-photos decision) and **#902** (spawn cycle5 follow-up); reconcile **#676** (record #696 + write AC#8 doc); land **#928** (S, `isServiceRoleToken` in publish-instagram). Forward-protect the 2 still-tracked sensitive docs from **#816**.
