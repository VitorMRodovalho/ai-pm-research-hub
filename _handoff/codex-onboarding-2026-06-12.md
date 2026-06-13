# Codex onboarding & weekend handoff — 2026-06-12

> Authored by the **CODE team** (Claude Code) at end-of-turn, for the **CODEX team**
> (Codex CLI) working this repo solo through **Tuesday 2026-06-17**. Read
> `AGENTS.md` (§"Shared brain & cross-tool sessions") and `CLAUDE.md` first — this
> file does not replace them, it grounds the current state so you start without loss.
>
> **Per-session output:** copy `_handoff/TEMPLATE.md` → `_handoff/codex-<YYYY-MM-DD>.md`,
> fill it, commit it. Do NOT touch the Claude memory namespace. Do NOT post `[LL]`
> issues (record lessons in your handoff file; Tuesday's Claude harvests them into #588).
>
> **Grounding rule (CLAUDE.md, binds you too):** every count/%/metric you state must
> come from a live tool result in YOUR session. The numbers below were live as of
> 2026-06-12 ~19:50 BRT — **re-ground before you rely on them** (queries given in §E).

---

## A. Current state (grounded 2026-06-12)

| Signal | Value (live this session) | Source |
|---|---|---|
| **Build** | ✅ green — `npx astro build` → `[build] Complete!` (exit 0) | ran this session |
| **Test suite** | `npm test` = **3860 tests, 3859 pass, 1 fail** — the 1 fail is a **confirmed flake** (`invariant R correctly detects synthetic breach`, `tests/contracts/volunteer-authority-invariants-behavioural.test.mjs`): the full run hit a 10.8 s DB lock/timeout; re-run **isolated it passed in 1.1 s**. Treat suite as effectively green; the flake is a QA-lane hardening item (§C). | ran this session |
| **`main` HEAD** | `63900da1` — `fix(625): exclude pre-onboarding cohort from admin dashboard KPI + ratification gate denominator (#672)` | `git log` |
| **Your start branch** | `chore/codex-shared-brain-bridge` (`a32b50d5`, adds AGENTS.md + `_handoff/`), open as **PR #673**. This onboarding doc stacks on it. | `git log` / `gh pr list` |
| **Migration head (DB)** | `20260805000158` == local files head — **no drift, no shadow rows** (`schema_migrations` today-rows = none). | `execute_sql` on `supabase_migrations.schema_migrations` |
| **Last RELEASE_LOG entry** | `2026-06-08 — p603 hotfix: selection approval RPC`. **The log is ~4 days behind** (#650/#654/#659/#666/#668/#671/#672 not logged) → a Governance-lane backfill task (§C). | `docs/RELEASE_LOG.md` head |
| **Open issues** | **30** total. `[LL]` intake = **#588**. No `WATCH-*` issues open. | `gh issue list` |
| **Latest council decision doc** | `docs/council/decisions/2026-06-09-legal-qaqc-parecer-vs-revised.md` | `ls -t` |

### Open PRs (live)
| PR | Branch | State | Note |
|---|---|---|---|
| **#673** | `chore/codex-shared-brain-bridge` | OPEN, ready | The Codex bridge (AGENTS.md + `_handoff/`). This onboarding doc is stacked on it. |
| #289 | `agent/p223-version-diff-style-isolation` | OPEN | Old (p223) TAP diff `<style>` leak fix — **stale, do not merge blind** (verify relevance first). |
| #154 | `feat/agents-md-harness-refinement` | OPEN | AGENTS harness gaps (CR-052). May overlap #673 — coordinate, don't merge blind. |
| #142 | `chore/curator-followup-2026-05-09` | DRAFT | Old curator day-7 report. Leave as-is. |

### Just-shipped this session (context, already on `main`, do not redo)
- **#672 `63900da1`** — pre-onboarding cohort excluded from `get_admin_dashboard.active_members`+`adoption_7d` (mig `20260805000157`) and from the `_can_sign_gate('volunteers_in_role_active')` ratification denominator (mig `20260805000158`). Live deltas observed: `active_members` 72→47, gate denominator 55→32. Rebuilt `preview_gate_eligibles_cache`. Contract test `p625-cohort-sweep-dashboard-and-gate`.

---

## B. IN FLIGHT — do NOT touch (reserved for the CODE team / pending PM decision)

1. **AGENTS.md / the bridge (PR #673).** Governance lane owns `AGENTS.md`. While #673 is open, do not edit AGENTS.md or `_handoff/TEMPLATE.md` — coordinate. (You MAY add your own `_handoff/codex-<date>.md` session files — that's the whole point.)
2. **#625 remaining BIG leaves — EPIC A (gamification roster) and C2 (V4-native /admin/members page).** These are the next leaves the PM is choosing between; the CODE team offered them and is awaiting the PM's pick. **Do not start the gamification roster migration or the admin/members filter rework.** Their *small* decision-free sub-parts ARE released to you (§C: C1-b refactor, alumni×inactive UI). The `tribe_selections` "destiny" decision (clean-on-offboard trigger vs retire) is a PM call — do not implement it.
3. **TAP / governance ratification chain `fa5fd11d`** (volunteer_term / CPMAI R01) — a live SEQUENTIAL signing chain awaiting **human signatures** (Vitor signs gate 1 next). Do not edit the chain, the gates, `_can_sign_gate`, `sign_ip_ratification`, or `resolve_default_gates`. The `_can_sign_gate` body was just hardened by #654/#666/#672 — treat it as frozen this window.
4. **Untracked WIP in the working tree:** `docs/drafts/v2.7_p153_tap_cpmai_r01.html` (TAP R01 draft, has an uncommitted B1 edit) and `docs/strategy/deck/__pycache__/` (deck build artifacts). **Do not commit, move, or delete these** — they belong to other processes. Stage files explicitly; never `git add -A`.
5. **Graziele Brescansin onboarding** (new Diretoria de Filiação, `auth_id=NULL`, needs an auth invite to use the #659 panel) — outward-facing, pending PM. Do not send invites or touch member identity rows.
6. **Legal-ops / governance-decision issues** (#570, #571, #572, #573, #574, #334, #335, #638, #639, #641, #642, #646, #645, #634, #632, #633, #661, #660-epic) — these need PM/legal/strategic decisions or live institutional context. **Not pickup-ready for solo work.** Leave them.
7. **Never merge a Dependabot PR** (#611 policy — see §D) and never merge the stale PRs (#289/#154/#142) without re-grounding.

---

## C. RELEASED p201 lanes — pickup-ready (no strategic decision required)

Each task is scoped to be completable solo with the gates in §E. Pick ONE, branch, PR.
Lane scope/labels: see `docs/project-governance/P201_PARALLEL_AGENT_ROADMAP.md` §3.

### Lane: Foundation (DB/RPC/RLS/migrations) — label `data-integrity`
**F1 — #625 C1-b: DRY the `admin_list_members` pre-onboarding rule.**
The RPC computes `is_pre_onboarding` with an **inline LATERAL** instead of calling the canonical helper `member_is_pre_onboarding(person_id, member_status)` (mig `20260805000143`) — a drift window (two copies of the rule).
- *Scope:* one migration that CREATE-OR-REPLACEs `admin_list_members`, replacing the inline LATERAL with the helper call; behavior identical.
- *Files:* new `supabase/migrations/2026080500015 9_*.sql`; touch `tests/contracts/p625-c0-pre-onboarding-cohort.test.mjs` if the body-anchor regex needs updating.
- *AC:* live body calls `member_is_pre_onboarding`; the cohort partition counts are byte-identical before/after (verify with the §E `active_members` query); body-hash drift audit = 0.
- *DoD:* `npx astro build` + `npm test` green; migration applied via `apply_migration` + local file + `migration repair` + `NOTIFY pgrst` (§D); RELEASE_LOG entry.

**F2 — #643: `edit_document_version_draft` cannot edit ANY unlocked draft (RLS pre-SELECT).**
Reported bug: the function/policy fails an RLS SELECT before the update can run. Issue points at "fix mig 147".
- *Scope:* reproduce (a draft author cannot edit their own unlocked draft), find the RLS pre-SELECT that blocks it, fix the policy/RPC.
- *Files:* `supabase/migrations/` (RLS policy on the draft table + possibly the RPC body).
- *AC:* a draft author CAN edit an unlocked draft; a non-author/locked draft is still denied; contract test locks both.
- *DoD:* as F1 + `check_schema_invariants()` clean.

### Lane: Frontend (Astro/React/i18n) — label `ux`
**FE1 — #625 C1-sem (UI only): alumni vs inactive legend + i18n de-conflation.**
The admin/members UI shows 🎓 Alumni / ⛔ Inativo chips but never explains the semantic difference; worse, `admin.adoption.lifecycleAlumni` is literally `'Alumni/Inativos'` (conflates them). *(The canonical RULE — who decides alumni vs inactive at offboard — is a PM/Governance decision; DO NOT document the rule. Only the UI/i18n.)*
- *Scope:* add a tooltip/legend distinguishing alumni (honorable, re-engageable) from inactive (deactivated); split/clarify the conflated i18n key.
- *Files:* `src/components/admin/members/MemberListIsland.tsx`; `src/i18n/pt-BR.ts` + `en-US.ts` + `es-LATAM.ts` (3-dict parity, GC-097).
- *AC:* legend renders; new keys exist in all 3 dicts; no raw `t('...')` without an entry.
- *DoD:* build green; `npm test` green; no new hardcoded strings.

**FE2 — #601: a11y — MemberDrillDown section headers are `<div>`, not semantic `<h4>`.**
- *Scope:* convert section headers to `<h4>` (or appropriate level) without visual regression.
- *Files:* `src/components/.../MemberDrillDown*` (grep for the component).
- *AC:* heading nav works; no Tailwind/visual change; lint clean.

**FE3 — #615: surface PostgREST `error.message` in `/admin/selection` approval catch.**
- *Scope:* the approval catch swallows the PostgREST error; surface `error.message` in the toast/UI (follow-up of #603).
- *Files:* the selection admin island/component under `src/components/admin/` (grep `admin/selection`).
- *AC:* a failed approval shows the real error string; happy path unchanged.

### Lane: QA (tests/contracts/smoke) — label `audit`
**QA1 — Harden the flaky `invariant R` forward-defense test.**
`tests/contracts/volunteer-authority-invariants-behavioural.test.mjs` → `invariant R correctly detects synthetic breach` intermittently times out under DB lock (10.8 s vs 1.1 s isolated).
- *Scope:* make it deterministic — wrap the synthetic breach in a tighter transaction/savepoint with explicit rollback, raise the per-test timeout, or serialize it; do NOT weaken the assertion.
- *Files:* that test file only.
- *AC:* the test passes deterministically across 3 consecutive full `npm test` runs.

**QA2 — Route smoke + contract coverage audit for the #625 surfaces.**
- *Scope:* run `npm run smoke:routes`; verify the new `/admin/members` cohort partition + the dashboard KPI surfaces have route smoke coverage; file gaps as a QA note (not as `[LL]`).
- *Files:* `tests/`, `scripts/smoke-routes.mjs`.
- *AC:* smoke green; a short coverage note committed in your `_handoff/codex-<date>.md`.

### Lane: Governance (docs/release/runbooks) — label `governance`
**G1 — RELEASE_LOG backfill (last entry is 2026-06-08).**
Add dated entries for the merged work since: #650 (cert_director_go gate), #654 (sequential gate write-path), #659 (Filiação panel), #666 (leader-gate scope), #668 (TAP reader logo), #671 (chapter_liaison wiring), #672 (cohort sweep). Numbers must be re-grounded (don't copy this file's deltas — re-run the §E queries).
- *Files:* `docs/RELEASE_LOG.md` (+ `docs/GOVERNANCE_CHANGELOG.md` if an entry rises to a decision).
- *AC:* one entry per shipped PR with scope + validation; em-dash discipline (§D, run `draft-qa`).

**G2 — #640: add LICENSE files (MIT for code + CC-BY-SA 4.0 for docs).**
The licensing is already decided in the issue (Anexo Técnico §2.3) — purely mechanical.
- *Files:* `LICENSE` (MIT), a docs license note (CC-BY-SA 4.0); reference both in `README.md`.
- *AC:* both license texts present and correctly attributed; README links them.

### Lane: MCP/AI — label `mcp-server`
**M1 — MCP contract matrix (P201 §6 P1).**
Generate a `tool → domain → RPC/table → gate → output-shape → smoke` matrix from the live `tools/list` (do not hand-count; the tool count drifts).
- *Files:* a new doc under `docs/` + optionally a generator script under `scripts/`.
- *AC:* matrix is generated from runtime, not memory; `tools/list`/`/health` smoke recorded.

### Lane: Infra/Security — label `infrastructure`
**I1 — Migration-drift / Local-QA doc reconciliation (P201 §6 P1).**
Verify `docs/operations/LOCAL_QA.md` reflects reality: remote-linked QA as default, and document the `supabase db push` drift state (DB head `20260805000158` matches files — confirm there is no pending history drift).
- *Files:* `docs/operations/LOCAL_QA.md`.
- *AC:* doc states the current default + a tested `supabase migration list` reconciliation note.

---

## D. Known traps in THIS repo ("if you touch X, watch out for Y")

- **If you touch SQL/RPC → GC-097 + the apply_migration ritual (CLAUDE.md, `.claude/rules/database.md`).**
  - DDL goes through `apply_migration` (MCP), **never `execute_sql`**. `execute_sql` is read-only / DML only.
  - `apply_migration` (MCP) applies to the remote DB **only** — it does NOT write a local file and does NOT register the version. You MUST: (1) `Write` the matching `supabase/migrations/<ts>_*.sql` with the **exact same SQL**, (2) `supabase migration repair --status applied <ts>`, (3) `NOTIFY pgrst, 'reload schema'` if the PostgREST surface changed.
  - **apply_migration ALWAYS creates a shadow row** (today's `20260612HHMMSS` timestamp). Detect (`version LIKE '20260612%'`) and revert it: `supabase migration repair --status reverted <ts>`. (This session created 2, reverted 2 — DB is clean now.)
  - **Body-hash drift trap (recurring):** reproduce the prior function body **verbatim** (including inline comments) when doing a body-only `CREATE OR REPLACE`; applying a body that differs from the `.sql` file (even just comments) fails the Phase-C drift gate. Verify with `node scripts/audit-rpc-body-drift.mjs` (expect `Drifted DEFINITE: 0`).
  - **`execute_sql` multi-statement = ONE transaction.** A later statement that errors **rolls back the earlier DML**. Run mutating DML **alone**, verify in a separate call. (Bit this session on a cache rebuild.)
  - Column gotchas: `members` uses `name` (not `full_name`), `credly_url` (not `credly_username`); `members.designations` is `text[]` (use `&&`/`array_length`, not jsonb ops); `events.created_by` FK → `auth.users(id)`, not `members(id)`; the pre-onboarding helper takes **`person_id`** (members is a bridge to persons), not `members.id`.
- **If you change `_can_sign_gate` semantics affecting a cacheable doc_type** (`volunteer_term_template`/`volunteer_addendum`) → **rebuild `preview_gate_eligibles_cache`** (ADR-0016 Amd 3). The cache is trigger-maintained on DATA changes only, NOT on function-body semantics. The public `refresh_preview_gate_eligibles_cache_all()` is `auth.uid()`-gated (fails via service_role AND on migration replay) — use the **unguarded** loop `PERFORM _refresh_preview_gate_eligibles_for_member(id)` over active members + orphan-delete. Verify with `_audit_preview_gate_eligibles_drift()` (expect 0 mismatches). *(But per §B, don't touch `_can_sign_gate` this window anyway.)*
- **If CI is red → never `--admin` merge / never direct-push to bypass** (`.claude/rules/bypass-protocol.md`). Threshold is 2 bypasses / 7 days. You almost certainly should NOT bypass at all this window.
- **Never merge a Dependabot PR (#611 policy).** GitHub does not inject repo secrets into Dependabot runs, so `validate` fails forever on them — it is not a flake. Security alerts are resolved by a human/assisted local hygiene PR (where CI runs full with secrets), never by merging the bot PR. `dependabot.yml` runs `open-pull-requests-limit: 0` (alerts-only).
- **If you write user-facing prose / docs → em-dash discipline.** This repo enforces a no-em-dash rule; run the `draft-qa` skill (or grep for `—`) before committing docs. No `🤖 Generated with…` footers.
- **If you touch middleware/auth/MCP POST paths → `checkOrigin: false` + manual CSRF** in `src/middleware.ts` is intentional (Astro's origin check blocks OAuth/MCP POSTs). Do not "fix" it by re-enabling `checkOrigin`.
- **Authority is `can()` / `can_by_member()` (ADR-0007), not role-name checks.** Do not add `operational_role IN (...)` auth gates or seed `engagement_kind_permissions` as a shortcut (privilege-escalation risk; V4 has 3 parallel authority paths — see `docs/reference/V4_AUTHORITY_MODEL.md` before claiming a gap).
- **If you add a route/nav item → 4 things must align:** `src/lib/navigation.config.ts` (minTier/allowedDesignations/lgpdSensitive) + the page in `src/pages/` (+ `/en/` + `/es/` redirect pages) + `PERMISSIONS_MATRIX.md` + `constants.ts`. i18n keys in all 3 dicts.
- **If you add/rename a test → register it in BOTH `"test"` and `"test:contracts"` whitelists in `package.json`** (SEDIMENT-186.C) or CI won't run it.
- **Stage explicitly, never `git add -A`** — the working tree has other processes' untracked WIP (§B.4).

---

## E. Gates + source-of-truth (so you re-ground, not copy my numbers)

### Gate commands
```bash
# env for DB-aware tests (.env has SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)
set -a; . ./.env; set +a

npx astro build            # MUST pass (build gate)
npm test                   # unit + contracts; DB-aware tests run only with the env above
npm run smoke:routes       # if you touched routes/nav
node scripts/audit-rpc-body-drift.mjs   # if you touched any RPC body — expect Drifted DEFINITE: 0
# migrations (DDL): apply_migration (MCP) → Write local file → supabase migration repair --status applied <ts> → NOTIFY pgrst
```

### Where each number actually lives (re-query — do not trust this file's values)
| Number | Source of truth (run it) |
|---|---|
| `active_members` KPI | `SELECT count(*) FROM members WHERE is_active AND current_cycle_active AND NOT member_is_pre_onboarding(person_id, member_status);` — or call RPC `get_admin_dashboard()` (needs a member JWT). |
| pre-onboarding cohort size | same predicate WITHOUT the `AND NOT …` minus WITH it; canonical helper `member_is_pre_onboarding` (mig `…143`). |
| ratification gate denominator | `SELECT count(*) FROM members m WHERE m.is_active AND _can_sign_gate(m.id, <chain_id>, 'volunteers_in_role_active');` per `_gate_threshold_met` 'all' branch. |
| preview cache vs live | `jsonb_array_elements(_audit_preview_gate_eligibles_drift())` → filter `mismatch=true` (expect none). |
| migration head / drift | `SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 1;` vs `ls supabase/migrations | tail -1`; shadow check `version LIKE '20260612%'`. |
| RPC body drift | `node scripts/audit-rpc-body-drift.mjs`. |
| schema invariants | RPC `check_schema_invariants()` (or the `/invariants` skill if you were Claude — you're not, so call the RPC). |
| admin dashboard (MCP) | MCP tool `get_admin_dashboard` (wraps the RPC). |
| open issues / PRs | `gh issue list --state open` / `gh pr list --state open`. |

---

## F. CODEX exit protocol (do this at the end of EACH session)

1. **Fill a per-session handoff:** `cp _handoff/TEMPLATE.md _handoff/codex-<YYYY-MM-DD>.md`, complete every section (Scope/lane, What changed + evidence, Gates run, Numbers observed + their source query, Open threads, Lessons, "what Claude must re-verify"). **Commit it.**
2. **Branch + PR per change.** One concern per commit. Gates (§E) must pass before you open the PR. Let CI run.
3. **Commit attribution (LAST line of body):** `Assisted-By: Codex (OpenAI) <noreply@openai.com>`. **NEVER `Co-Authored-By:`.** Human is sole author of record. No AI footers.
4. **Do NOT post `[LL]` issues or comments.** Record lessons in your handoff file's "Lessons learned" section; Tuesday's Claude reconciles them into #588 + memory.
5. **Never force-push, never `--no-verify`, never merge Dependabot, never `--admin`-bypass.** Stay in your p201 lane.
6. **If a gate fails and you can't fix it:** stop, write what you found in the handoff, leave the branch unmerged. A red main = revert before anything else.

---

## G. CODE team (Claude) Tuesday re-verification checklist

Before trusting any Codex work on 2026-06-17, re-ground:

- [ ] `git log --oneline origin/main` since `63900da1` — every new commit has an `Assisted-By: Codex` trailer (no `Co-Authored-By`), one concern per commit.
- [ ] For each merged Codex PR: CI `validate` was actually **green** (not `--admin`-bypassed) — run the bypass audit query from `.claude/rules/bypass-protocol.md`; check the weekly bypass-audit issue.
- [ ] `npx astro build` + `npm test` green on a fresh `main` (re-confirm the `invariant R` flake didn't become real).
- [ ] Migration hygiene: `schema_migrations` head == local files head; **no `20260612*`/weekend shadow rows**; `node scripts/audit-rpc-body-drift.mjs` → 0 drifted; `_audit_preview_gate_eligibles_drift()` → 0 mismatch; `check_schema_invariants()` clean.
- [ ] **No Dependabot PR was merged** (#611); no stale PR (#289/#154/#142) merged without context.
- [ ] `_can_sign_gate` / `sign_ip_ratification` / `resolve_default_gates` / the `fa5fd11d` chain were NOT touched (§B.3); the TAP draft + deck pycache untracked WIP still intact (§B.4).
- [ ] Reconcile each `_handoff/codex-<date>.md` into the Claude memory namespace + the `[LL]` issue #588 (Codex did NOT post these — you do).
- [ ] Re-ground every number Codex reported via §E before recording it as fact (Codex's numbers were point-in-time too).
- [ ] Confirm the released-lane tasks that Codex picked did not creep into the reserved items (§B) — especially EPIC A / C2 / `_can_sign_gate`.
- [ ] RELEASE_LOG / GOVERNANCE_CHANGELOG updated for anything production-impacting Codex shipped.

---

*CODE→CODEX handoff complete. State crystallized to disk while the Claude session still had context. — 2026-06-12*
