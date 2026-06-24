# CODE team weekend re-verification — 2026-06-17

> Authored by the CODE team (Claude Code) automated weekend re-verification agent.
> Adversarial check of the work that landed on `main` during the Codex weekend
> window (Fri 2026-06-12 to Tue 2026-06-17), against baseline `63900da1` (PR #672).
> This report is for the LOCAL Claude to fold into memory + the [LL] issue #588.
> It does NOT post to #588, does NOT write the Claude memory namespace, and ran
> ZERO DDL/DML.

---

## TRUST VERDICT: YELLOW (needs-local-review)

**No defects found in anything verifiable from this cloud environment.** Build is
green, the offline test suite is green (0 fail), history builds cleanly and
linearly on the documented baseline (no rewrite), the frozen governance chain was
not modified, reserved items were respected, and no Dependabot/stale PR was merged.

**Why YELLOW and not GREEN:** the Supabase MCP `execute_sql` connector reconnected
mid-run (it and nucleo-ia were initially "Not authenticated"), so the structural DB
checks were ultimately RUN and are CLEAN (preview-gate drift 0; all 40 schema
invariants A1-AJ at 0 violations; `active_members` re-grounds live to 47). What
keeps this YELLOW: (1) the DB-aware contract SUITE could not be run here (no
secrets; 331 tests skipped), and CI `validate` on the PR-merge commit shows
**4 / 4606 DB-aware tests failing on current `main` as of 2026-06-24** (see the
post-window addendum) - these are a week past the verification window and, given the
clean structural checks, look data-dependent, but a LOCAL Claude with secrets must
run the full DB-aware suite, NAME those 4, and confirm they are out-of-window
brittleness and not a 06-17 regression; (2) the live DB head is `20260805000242`
(2026-06-24), 44 versions past the 06-17 file head, so a migration-head/shadow-row
reconciliation against a 06-17 checkout was not performed (the DB reflects a week of
post-window work).

**Headline reconciliation (important):** the task premise ("Codex worked this repo
solo") does not match the merged history. Of the 61 new commits, **zero carry the
`Assisted-By: Codex (OpenAI)` trailer**; all feature/fix commits carry
`Assisted-By: Claude (Anthropic)` and are authored by Vitor Maia Rodovalho. Codex's
actual footprint on `main` is a single integrated PR (#675, "Codex queue",
commit `30bbd4f3`) covering 14 issues + the FE2 leaf, which the CODE team
reviewed, re-QA'd on the full payload, and merged with a Claude trailer. The other
~57 commits (agenda recurring model, SECDEF security fixes, selection fixes,
agenda-viva #700/#701, members #625 C1/C2, governance WS-A, onboarding waves 1-4)
are net-new CODE-team (Claude) work done 06-14 to 06-16, not Codex.

---

## Per-check results

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Every new commit carries `Assisted-By: Codex`, one concern each | **FAIL (literal) / explained** | 61 commits `63900da1..origin/main`. 0 carry `Assisted-By: Codex`. 59 feature/fix commits carry `Assisted-By: Claude (Anthropic)`; 2 bridge commits (`4bab7a50`, `42ae6168`) reference Codex and `42ae6168`/`4bab7a50` also carry a `Co-Authored-By`. The literal requirement is unmet because Codex's work was integrated and re-attributed by the CODE team, not self-merged. Commits are one-concern, conventional-commit, PR-squashed (every subject ends `(#NNN)`). Provenance of the Codex payload is documented in prose in `30bbd4f3` ("Codex weekend queue (GPT-5) across 14 issues"). |
| 2 | Each merged PR: CI `validate` green, not --admin-bypassed; weekly bypass-audit | **PASS / FLAG** | PR #675 merged normally by VitorMRodovalho 2026-06-14, body asserts CI validate + CodeQL green and `npm test` 3932/3932 with DB env. Latest bypass-audit = W25 (issue #715, 2026-06-15): "within threshold (2 <= 2)", **0 --admin merges**, 2 docs-only direct pushes (`040df7bc`, `54ec45c7`, both pre-window). FLAG: the 06-15 to 06-17 commits fall in W26, whose audit cron (Mon 2026-06-22) has not run yet; per-PR CI for all 61 was not individually re-fetched. |
| 3 | Fresh `npm install` + `npx astro build` + `npm test` | **PASS / FLAG** | `npm install` exit 0. `npx astro build` exit 0 ("[build] Complete!", only pre-existing chunk-size + CSS-token warnings). `npm test`: tests 4224, pass 3893, **fail 0**, skipped 331, exit 0. The known `invariant R` flake did NOT fire. FLAG: 331 skips = DB-aware contract tests skipped (no secrets here); LOCAL Claude must re-run with `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`. |
| 4 | DB hygiene (migration head, shadow rows, preview-gate drift, schema invariants) | **PASS (structural, live) / FLAG (suite + temporal)** | `execute_sql` reconnected mid-run and was used (read-only). (c) preview-gate drift = **0** mismatches (live). (d) `check_schema_invariants()` = **0 violations across all 40 invariants** (A1-AJ, incl. post-window AA-AJ) (live). (a) live DB head = `20260805000242` as of 2026-06-24; 06-17 file head = `20260805000198` - the 44-version gap is a week of post-window migrations, not 06-17 drift. (b) 14 `schema_migrations` rows newer than `20260617` (post-window work); no 06-17-window shadow rows surfaced. FLAG: the `audit-rpc-body-drift.mjs` script still needs env that this container lacks, and a head/shadow reconciliation against a 06-17 checkout was not done (DB is at 06-24 state). |
| 5 | No Dependabot PR merged; no stale #289/#154/#142 merged | **PASS** | No dependabot/bump commit in window. None of #289/#154/#142 (nor their branch names version-diff-style / agents-md-harness / curator-followup) appear in merged subjects. |
| 6 | Frozen items not modified (`_can_sign_gate`, `sign_ip_ratification`, `resolve_default_gates`, `_gate_threshold_met`, approval chain, TAP draft html) | **PASS** | `-S` pickaxe over `supabase/`: `sign_ip_ratification`, `resolve_default_gates`, `_gate_threshold_met` not touched. `_can_sign_gate` appears in PR #675 only as **function calls** (migration 159 redefines `_enqueue_gate_notifications` which calls the gate; migration 162 references it in the draft-preview RPC) - the gate body itself is NOT redefined. `docs/drafts/v2.7_p153_tap_cpmai_r01.html` was never committed (untracked WIP, correctly absent from a fresh clone). |
| 7 | Copy each Codex handoff's "Lessons learned" + "what Claude must re-verify" verbatim | **DONE** | See "Codex handoff verbatim extracts" below. Files present: `codex-2026-06-12.md`, `codex-2026-06-13.md` (+ the onboarding doc). |
| 8 | Re-ground each numeric claim in Codex handoffs via onboarding §E queries | **PARTIAL PASS (live) / FLAG** | `execute_sql` re-grounded live on 2026-06-24: `active_members` = **47**, pre-onboarding cohort = **30** (matches the handoff's 47 - stable over the week). Note this is a 2026-06-24 read, NOT a retroactive reproduction of the 06-13 figure; do not treat it as confirming the point-in-time value, only the current one. Still unverified (need §E with secrets / point-in-time context): `retention_rate` 68.1, ratification gate denominator 32, `npm test` 3932/3932 with DB env, PI registry 0/0. |
| 9 | Codex stayed in RELEASED lanes, did NOT touch RESERVED §B items (EPIC A gamification roster/tribe_selections, C2 /admin/members, `_can_sign_gate`) | **PASS** | No new gamification-roster or `tribe_selections` "destiny" migration in window (only pre-baseline `20260425205543_..._tribe_selection_v4_auth.sql`). Codex's #675 touched only the RELEASED #625 C1-b helper (migration 160), not the reserved C2 frontend. The C2 `/admin/members` V4-native work (`bf27d0df` #722, `680b1c29` #725, 06-15) was shipped by the CODE team itself, which is the party that reserved it (§B: "reserved for the CODE team / pending PM decision") - not a Codex violation. `_can_sign_gate` body intact (see #6). |
| 10 | RELEASE_LOG / GOVERNANCE_CHANGELOG updated for production-impacting work | **PARTIAL / FLAG** | Both files updated by PR #675 (`30bbd4f3`); RELEASE_LOG head entry "2026-06-13 - Queue hardening: #234/#625/#630/..." covers Codex's queue. BUT the last RELEASE_LOG entry is 2026-06-13: the CODE team's own 06-14 to 06-16 production-impacting work is NOT logged, including three SECDEF security fixes (`dc743641` #683, `b26152d4` #685, `63001895` #686), the WS-A whatsapp-leak governance fixes, members #625 C2, and onboarding waves 1-4. This is a CODE-team release-log gap, not a Codex gap. |

---

## Codex commit / PR footprint on `main`

Codex's substantive work reached `main` as **one** integrated PR:

- **PR #675** ("Codex queue: governance/legal/MCP/DB hardening - 14 issues"),
  merge commit **`30bbd4f3`**, merged by VitorMRodovalho 2026-06-14T04:21:11Z,
  head branch `codex/fe2-member-drilldown-headings`, base `42ae6168`, 86 files,
  +3833/-225. Issues: #234 #625 #630 #633 #638 #639 #640 #641 #642 #645 #646
  #651 #670 #678 (+ the FE2 #601 MemberDrillDown headings leaf, present in
  `src/components/tribes/TribeGamificationTab.tsx`).
  - 10 migrations: `20260613150200`, `...150634`, `...151535`, `...152719`,
    `...162000` (all `_630_` agenda reconciliation) + `20260805000159`
    (#651 gate notifications), `...160` (#625 c1b helper), `...161` (#630
    retention fold), `...162` (#646 draft preview), `...163` (#639 release
    provenance RPC).

Bridge / scaffolding commits that mention Codex (CODE-team authored):
- **`4bab7a50`** chore: cross-tool shared-brain bridge (AGENTS.md + `_handoff/`), PR #673.
- **`42ae6168`** docs(handoff): CODE->CODEX weekend onboarding package.

Every other commit in `63900da1..origin/main` (57 commits, all `Assisted-By:
Claude`) is net-new CODE-team work, NOT Codex.

Stale Codex branches still on origin (not merged, harmless): `chore/codex-shared-brain-bridge`
(1 ahead / 61 behind), `chore/codex-onboarding-handoff` (4 ahead / 60 behind).

---

## Reconciliation notes (for LOCAL Claude -> memory + [LL] #588)

### Lessons learned, verbatim from Codex handoffs

**From `codex-2026-06-12.md`:**
- (bootstrap) "Codex bootstrapped against AGENTS.md, CLAUDE.md, p201, bypass
  protocol, and the read-only memory namespace before making repo changes. ...
  For repositories with shared-brain rules, make a first-step handoff bootstrap
  checklist explicit before any lane work."
- (FE2) "The first full `npm test` can appear less complete if `.env` is not
  loaded; DB-aware tests skip themselves. ... For Codex handoffs, record both the
  plain test run and the `.env`-loaded run when the first one skipped DB-aware
  tests."

**From `codex-2026-06-13.md`:**
- "Codex attacked multiple GitHub issues and left evidence in repo
  docs/tests/migrations, but did not initially leave progress comments on every
  issue. ... In the parallel-agent operating model, absent issue comments can make
  the team believe an issue is still untouched, causing duplicate investigation or
  duplicate implementation attempts. ... Add a default 'issue work audit' step to
  Codex handoff/closure: for every issue number touched, post a concise issue
  comment with scope, files/migrations, validation, and remaining ambiguity before
  final response."
- "#639 initially proposed using `register_exclusion_asset` directly from
  `release-tag.yml`, but that RPC is intentionally declarant/self-service and
  depends on `auth.uid()` ownership. ... For automation writing into human-governed
  registries, add a narrow service-role RPC with explicit asset type, digest-only
  inputs, and no proof-byte forging; keep human self-service RPCs unchanged."
- "#234 had MCP/OAuth refresh code in Worker SSR routes reading
  `import.meta.env.PUBLIC_SUPABASE_*`, while production deployment only guaranteed
  those values during `npm run build`. ... For Cloudflare Worker SSR OAuth/proxy
  paths, resolve operational credentials from `env` first and add a contract that
  `wrangler.toml` publishes any public runtime vars needed by deployed handlers;
  build-time env alone is not enough."
- "During #678 QA, full Supabase anon JWT literals in `wrangler.toml` were caught
  as a release-blocking pre-commit/token-scanner risk. ... For public JWT-like
  config values, prefer runtime secrets/vars and add a contract asserting no full
  `eyJ...` token appears in deploy config or source."

### "What Claude must re-verify", verbatim from Codex handoffs

**From `codex-2026-06-12.md`:**
- "Re-run `git status --short` before reconciling, because unrelated untracked
  local files existed before this handoff was created."
- "Re-run any counts, metrics, DB state, or test baselines live; this file
  intentionally does not pin them beyond command outputs observed during this
  session."
- "Re-run the FE2 branch tests if this PR sits while `TribeGamificationTab.tsx`
  changes elsewhere."
- "Confirm the UI still looks identical in the gamification member drill-down; this
  change relies on `m-0` preserving heading layout."

**From `codex-2026-06-13.md`:**
- "Verify `git diff` against user-owned changes before committing; worktree
  includes unrelated tracked and untracked strategy/deck files outside the P0/P1
  queue."
- "Re-run route smoke if preparing a PR because nav/middleware changed for #670."

### Numbers to re-ground (do NOT record as fact until re-queried live, per CLAUDE.md grounding rule)
- `active_members` = 47, `retention_rate` = 68.1 (codex-06-13 `get_public_platform_stats`).
- ratification gate denominator = 32; `active_members` 72->47 delta (onboarding §A, from #672).
- `npm test` with DB env = 3932/3932 (codex-06-13 + PR #675 body).
- PI exclusion registry: 0 declarations / 0 assets / 0 confirmed / 0 open (codex-06-13).
- Migration DB head should equal file head `20260805000198`; 0 shadow rows; 0 preview-gate drift; `check_schema_invariants()` 0 violations - ALL still to be confirmed live.

---

## What the LOCAL Claude must still do (this container could not)

1. **Re-run the DB-aware suite with secrets and TRIAGE THE 4 CI FAILURES:**
   `set -a; . ./.env; set +a; npm test`. CI `validate` on PR #765 showed 4 / 4606
   DB-aware tests failing on current `main` (2026-06-24). Name them (pull the full
   raw `validate` log for run/job `83233616390`, grep `not ok`), confirm each is
   out-of-window data-brittleness and NOT a 06-17 regression, and fix or quarantine.
   Re-run the `invariant R` test isolated if it flakes.
2. **DB hygiene (check 4) - structural checks DONE live, residual items remain:**
   - (c) preview-gate drift = 0 (DONE live 2026-06-24). (d) `check_schema_invariants()`
     = 0/40 (DONE live 2026-06-24). No need to re-run unless you want a fresh read.
   - (a/b) RESIDUAL: from a current `main` checkout, confirm DB head `20260805000242`
     equals `ls supabase/migrations | tail -1` and that all 14 post-0617
     `schema_migrations` rows are file-backed (no shadow rows). The 06-17 file head
     was `20260805000198`; the gap is post-window work.
   - Run `node scripts/audit-rpc-body-drift.mjs` with env -> expect `Drifted DEFINITE: 0`
     (still needs secrets the cloud container lacked).
3. **Re-ground every number** in the "Numbers to re-ground" list above via the
   onboarding §E source queries before folding any into memory or #588.
4. **Fold the verbatim lessons above into the Claude memory namespace + post to
   [LL] issue #588** (memory-namespace reconciliation is local-only; this agent
   neither can nor may write `~/.claude/...` and did not post to #588).
5. **RELEASE_LOG / GOVERNANCE_CHANGELOG backfill** for the CODE-team 06-14 to 06-16
   production work that is not logged - prioritize the three SECDEF security fixes
   (#683/#685/#686), the WS-A whatsapp-leak governance fixes, members #625 C2, and
   onboarding waves 1-4.
6. **Confirm W26 bypass-audit** (cron Mon 2026-06-22) shows 0 --admin merges for
   the 06-15 to 06-17 commits; spot-check per-PR `validate` if any doubt.
7. **Decide the attribution posture going forward:** Codex's payload landed under a
   `Assisted-By: Claude` trailer (PR #675). If Codex provenance must be auditable
   from trailers (not just commit-body prose), adjust the integration convention.

---

## Post-window addendum (2026-06-24, from PR #765 CI)

When PR #765 (this report) ran CI, the `validate` check failed: **4606 tests,
4571 pass, 4 fail, 31 skipped** (job `83233616390`, on the PR-merge commit
`4acc0f6f` = this doc + current `main`). Reconciliation:
- This PR adds ONE markdown file, so the 4 failures are NOT introduced by it.
- They are DB-aware tests (they ran because CI has secrets; they SKIP offline -
  the same 331-skip class as the local run). They executed against the LIVE DB as
  of 2026-06-24, a week past the verification window.
- Structural DB state is clean at that same moment: preview-gate drift 0, all 40
  schema invariants 0 violations. So the 4 failures are NOT drift/invariant
  breakage; they read as data-dependent contract assertions that diverged as live
  data evolved over the week, on CURRENT `main`, not the 06-17 work.
- The exact 4 test names could not be extracted here: the GitHub MCP `get_job_logs`
  returns only the last ~308k chars (all passing TAP tail); the inline `not ok`
  lines are earlier in the full log and unreachable via this tool.
- This is a pre-existing failure on `main`, out of scope for a verification-report
  PR. It is NOT being "fixed" or re-kicked here. A LOCAL Claude (or a full raw-log
  pull) must name and triage the 4 before declaring `main`'s DB-aware suite green.

## Method note
The initial fetch produced a SHALLOW clone (boundary commits `be5af1b7`, `d9aad41a`),
which made `origin/main` look like an orphan history with no common ancestor to
`63900da1` (a false force-push signal). After `git fetch --unshallow`, `63900da1`
is confirmed as the exact merge-base and ancestor of `origin/main` (0 commits on the
baseline side absent from main); the build-on is clean and linear. Recorded here so
the next agent does not re-trip on the shallow artifact.

— CODE team re-verification complete, 2026-06-17.
