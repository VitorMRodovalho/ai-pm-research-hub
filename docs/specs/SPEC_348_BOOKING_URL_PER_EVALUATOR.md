# SPEC #348 — Booking URL per Evaluator / Committee (v1)

**Issue:** #348 (roadmap: booking URL per-evaluator/track + auto-select in `notify_selection_cutoff_approved` + Hub reschedule/cancel)
**Status:** Draft v1 (spec-only; implementation will land via children to be spawned post-PM-ratification)
**Filed:** 2026-05-24 (p249, post-p248 close)
**Scope of this spec:** Step 2 (schema + routing data model) and Step 3 (auto-select routing inside `notify_selection_cutoff_approved`). **Out of v1:** Step 4 (Hub reschedule/cancel UI), per PM boot directive 2026-05-24.

This spec proposes the schema, routing logic, and migration path for moving cycle-level booking URLs to per-evaluator (researcher track) + cycle-level group (leader track) routing. It captures the p243 short-term decision as the v0 baseline so v1 is purely additive.

---

## 1. Short-term decision (v0 — already shipped p243)

PM unblocked the Cycle 4 cutoff dispatch by populating `selection_cycles.interview_booking_url` with a Núcleo group calendar link:

- `cycle4-2026.interview_booking_url = 'https://calendar.app.google/XPiGWLh9JaLVFKJc6'` (populated 2026-05-24 16:38 UTC)
- 5 above-target dispatches executed via `notify_selection_cutoff_approved(app_id)` (Henrique 227, João 171, Francisleila 164, Cristiano 163, Edinan 157.50; emails sent 16:39:48-16:40:23 UTC).
- The Núcleo link routes to dual interview (Vitor + Fabricio). This is the implicit assumption for ALL Cycle 4 tracks today.

**v1 does NOT remove this column.** The cycle-level URL remains the fallback and the leader-track default. Existing behavior is preserved for cycles that don't opt into per-evaluator routing.

---

## 2. Current state audit

### 2.1 Schema today (verified live 2026-05-24)

| Table | Columns of interest |
|---|---|
| `selection_cycles` | `interview_booking_url text` — single link per cycle, group-level |
| `selection_committee` | `id, cycle_id, member_id, role, can_interview, created_at, organization_id` — per-cycle evaluator roster |
| `members` | NO booking URL column today |
| `selection_interviews` | `calendar_event_id text` — captures the booked event id post-webhook |

### 2.2 Live Cycle 4 evaluator state (de facto vs de jure)

- `selection_committee` rows for cycle4-2026: **0**
- Actual evaluators (from `selection_evaluations`): Vitor (51 evals) + Fabricio (40 evals)
- Implication: PM has been operating via service-role JWT injection (SEDIMENT-226.C pattern) because committee seed was never executed (p226 carry deprioritized). v1 must NOT depend on committee seed being populated to work — graceful fallback to cycle URL when committee is empty.

### 2.3 Email template binding (today)

`supabase/migrations/20260805000011_p228_260_w2_leaf4_selection_cutoff_approved.sql`:

- Template `selection_cutoff_approved` (pt/en/es) hardcodes `{{interview_booking_url}}` as the CTA href.
- `notify_selection_cutoff_approved(app_id)` raises `CUTOFF_NO_BOOKING_URL` (errcode P0020) if `cycle.interview_booking_url` is NULL/empty.
- The variable is passed as `'interview_booking_url', v_cycle.interview_booking_url` into the campaign payload.

v1 changes the RPC body (not the template; the placeholder name stays `{{interview_booking_url}}` for backward compat) so the *value* substituted is track-aware.

---

## 3. v1 scope

### IN

1. New column `members.interview_booking_url text` (nullable). Personal evaluator calendar pool URL.
2. `selection_committee.interview_booking_url text` override (nullable) — committee-cycle-scoped override of the member's global URL when a single committee member runs different calendars per cycle.
3. `notify_selection_cutoff_approved` body extension:
   - **researcher track**: pick a URL from the cycle's committee members where `role='researcher'` AND `can_interview=true` AND a URL is resolvable (committee override → member global → null). Routing policy v1: **round-robin by least-recently-dispatched** (see §5.2 for rationale).
   - **leader track**: use `cycle.interview_booking_url` (group/dual). Per-evaluator URL ignored for leader.
   - **fallback**: when no resolvable per-evaluator URL exists for researcher track (empty committee OR all URLs null), fall back to `cycle.interview_booking_url` (preserves current Cycle 4 behavior without ceremony).
4. New audit row in `selection_dispatch_log` (or similar) capturing `{app_id, resolved_url, resolution_path}` per dispatch so PM can audit which URL was used for which candidate.
5. `selection_cycles.interview_booking_url` semantics clarified via comment + ADR: "group/dual interview link; used for leader track AND as researcher-track fallback when no per-evaluator URL is resolvable".
6. Contract tests:
   - Researcher with seeded committee + URLs → picks per-evaluator.
   - Researcher with empty committee → falls back to cycle URL.
   - Researcher with committee but all URLs null → falls back to cycle URL.
   - Leader → always cycle URL even if member has URL.
   - Round-robin advances on consecutive dispatches.
   - `CUTOFF_NO_BOOKING_URL` raises ONLY when both per-evaluator AND cycle URL are null/empty.
7. UI affordance (admin): `members.interview_booking_url` editable on `/admin/members/[id]` (single field, validate as URL).

### OUT of v1 (deferred to Steps 3+ children)

- Hub-side reschedule/cancel flows (PM directive: Step 4).
- Google Calendar API integration (read availability, create event server-side).
- Per-evaluator availability matrix (today/next-7d busy windows surfaced in UI).
- Round-robin alternatives (least-loaded by open interview count, weighted by capacity, manual sticky).
- Auto-trigger from cron jobid 47 → cutoff dispatch (p230 fast-follow; governance gate question).
- Replacing `cycle.interview_booking_url` deprecation. v1 is additive.
- Committee seed automation (p226 carry remains separate).

---

## 4. Schema proposal (Option B Híbrido — per-cycle + per-member with precedence)

### 4.1 Migration `xxxxxxxxxxxxxx_p_spec_348_v1_booking_url_per_evaluator.sql`

```sql
-- 1. Per-evaluator URL (global, member-level)
ALTER TABLE public.members
  ADD COLUMN interview_booking_url text;

COMMENT ON COLUMN public.members.interview_booking_url IS
  'Personal calendar/booking pool URL for this evaluator. Used by selection auto-dispatch '
  'when this member is on the researcher-track committee. Falls back to cycle-level URL '
  'if NULL. See SPEC #348.';

-- 2. Per-cycle committee override (optional)
ALTER TABLE public.selection_committee
  ADD COLUMN interview_booking_url text;

COMMENT ON COLUMN public.selection_committee.interview_booking_url IS
  'Optional cycle-scoped override of members.interview_booking_url. Use when a single '
  'evaluator runs a different calendar pool for this specific cycle. See SPEC #348.';

-- 3. Dispatch audit (capture which URL was used per dispatch)
CREATE TABLE IF NOT EXISTS public.selection_dispatch_url_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id),
  cycle_id uuid NOT NULL REFERENCES public.selection_cycles(id),
  track text NOT NULL CHECK (track IN ('researcher','leader')),
  resolved_url text NOT NULL,
  resolution_path text NOT NULL CHECK (resolution_path IN (
    'committee_override','member_global','cycle_fallback'
  )),
  resolved_evaluator_id uuid REFERENCES public.members(id),  -- NULL for cycle_fallback / leader
  dispatched_at timestamptz NOT NULL DEFAULT now(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id)
);

CREATE INDEX selection_dispatch_url_log_app_idx
  ON public.selection_dispatch_url_log (application_id);
CREATE INDEX selection_dispatch_url_log_cycle_round_robin_idx
  ON public.selection_dispatch_url_log (cycle_id, track, resolved_evaluator_id, dispatched_at DESC)
  WHERE track = 'researcher';

-- RLS (V4 canonical pair — matches every other selection_* table)
ALTER TABLE public.selection_dispatch_url_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY rpc_only_deny_all
  ON public.selection_dispatch_url_log
  FOR ALL USING (false);

CREATE POLICY selection_dispatch_url_log_v4_org_scope
  ON public.selection_dispatch_url_log
  FOR ALL
  USING ((organization_id = auth_org()) OR (organization_id IS NULL));
```

**RLS policy resolution (p250):** the earlier draft of §4.1 proposed `USING (rls_can('view_selection') OR rls_can('manage_member'))`, but `view_selection` is not in `engagement_kind_permissions` — it would silently deny everyone except `manage_member` holders. The canonical V4 pattern across every `selection_*` table (`selection_applications`, `selection_committee`, `selection_cycles`, `selection_evaluations`, `selection_interviews`, `selection_evaluation_ai_suggestions`, `selection_diversity_snapshots`) is the **deny-all + org-scope pair**: client code reads via SECURITY DEFINER RPCs (admin/audit RPC can be added in Child #2 or later if PM wants direct dashboard SELECTs). Decision ratified by PM 2026-05-24 during p250 boot.

### 4.2 Why Option B (additive per-member + per-committee override) over (a) and (c)

- **(a) Per-member only**: forces every cycle to seed committee + per-member URLs before any dispatch works. Breaks Cycle 4 today (committee empty). Rejected.
- **(b) Per-cycle + per-member with precedence (chosen)**: additive; old cycles keep working; new cycles opt into per-evaluator routing by seeding committee + URLs. Precedence: `committee_override → member_global → cycle_fallback`.
- **(c) Per-committee + per-cycle fallback only**: requires every override URL to live in `selection_committee`, but members usually have a stable personal URL across cycles. Forces redundant data entry. Rejected as default; the `selection_committee.interview_booking_url` override field gives us this capability where genuinely cycle-scoped overrides matter.

---

## 5. Routing logic (Step 3 — RPC body extension)

### 5.1 Decision tree (`notify_selection_cutoff_approved`)

```
Given: app_id → load sa, cycle, member, role_applied

IF sa.role_applied = 'leader':
  url := cycle.interview_booking_url
  path := 'cycle_fallback'
  evaluator := NULL

ELSE IF sa.role_applied = 'researcher':
  candidates := SELECT
                  sc.member_id,
                  COALESCE(sc.interview_booking_url, m.interview_booking_url) AS url,
                  CASE WHEN sc.interview_booking_url IS NOT NULL
                       THEN 'committee_override'
                       ELSE 'member_global' END AS path
                FROM selection_committee sc
                JOIN members m ON m.id = sc.member_id
                WHERE sc.cycle_id = cycle.id
                  AND sc.role = 'researcher'
                  AND sc.can_interview = true
                  AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL

  IF candidates is empty:
    url := cycle.interview_booking_url
    path := 'cycle_fallback'
    evaluator := NULL
  ELSE:
    # Round-robin by least-recently-dispatched (LRD)
    SELECT c.member_id, c.url, c.path
    FROM candidates c
    LEFT JOIN LATERAL (
      SELECT MAX(dispatched_at) AS last
      FROM selection_dispatch_url_log
      WHERE cycle_id = cycle.id
        AND track = 'researcher'
        AND resolved_evaluator_id = c.member_id
    ) l ON true
    ORDER BY l.last NULLS FIRST, c.member_id  -- never-used candidates first; stable tiebreak
    LIMIT 1
    → use this row

IF url IS NULL OR url = '':
  RAISE 'CUTOFF_NO_BOOKING_URL'

INSERT INTO selection_dispatch_url_log (...)  -- before send

call campaign_send_one_off(...) with {{interview_booking_url}} := url
UPDATE selection_applications SET cutoff_approved_email_sent_at = now() WHERE id = app_id
```

### 5.2 Why LRD round-robin (and not random, not least-loaded)

- **Least-loaded by open interviews** would be ideal but requires a `selection_interviews.status IN ('scheduled','pending')` query per dispatch + agreement on what "loaded" means. v1 can't ship without more signal on Fabricio/Vitor's true off-platform commitments.
- **Random** is fast but yields visible streaks (3 in a row to Vitor) that look unfair to candidates/evaluators. PM has been manually balancing — random would feel like a regression.
- **LRD (round-robin by last dispatch timestamp from `selection_dispatch_url_log`)** is deterministic, fair across time, and observable (PM can audit the log). Cost: 1 LEFT JOIN LATERAL per dispatch (sub-ms with the proposed index). Streaks self-correct after each dispatch. Tied evaluators (never used) break by member_id for stable order.

If LRD turns out to give bad results in practice (e.g., one evaluator goes on leave, balance gets stuck), v2 can swap policy without schema change.

### 5.3 Leader track stays cycle-level

PM directive: "leader → Núcleo/dupla". This is intentional dual-interview semantics (preserves p240+p241 partial-submit advance). v1 does NOT touch leader routing — `cycle.interview_booking_url` is the source of truth for leader dispatches, end of story. A separate decision (#348 parallel observation) is needed before leader-track routing changes.

---

## 6. Test plan

### 6.1 Contract tests (offline + DB-gated)

- `tests/contracts/spec-348-v1-booking-url-routing.test.mjs` (~15 assertions):
  - Migration file exists at expected path
  - `members.interview_booking_url` column added (DB-gated)
  - `selection_committee.interview_booking_url` column added (DB-gated)
  - `selection_dispatch_url_log` table + index + RLS exist (DB-gated)
  - RPC body has track-aware branching (text scan + parsing)
  - RPC body has LRD ORDER BY pattern (text scan)
  - Forward-defense regression: leader branch must NOT query `selection_committee.interview_booking_url`
  - Forward-defense regression: researcher branch must include the `LEFT JOIN LATERAL ... dispatched_at` pattern
  - RPC inserts into `selection_dispatch_url_log` before campaign send

### 6.2 Live smoke (post-deploy)

- Seed cycle4-2026 committee (Vitor + Fabricio, both role=researcher + can_interview=true).
- Seed `members.interview_booking_url` for both (use existing Núcleo link as placeholder OR PM-provided personal links).
- Dispatch a new test cutoff → verify LRD picks one, `selection_dispatch_url_log` row created.
- Dispatch a second test cutoff → verify LRD picks the OTHER (round-robin advanced).
- Clear all per-evaluator URLs → verify fallback to cycle URL with `resolution_path='cycle_fallback'`.
- Dispatch a leader-track app → verify cycle URL used and `resolved_evaluator_id IS NULL`.

### 6.3 Smoke must remain green

- `check_schema_invariants()` 19/19=0
- `npm test` baseline updates: +15 assertions (offline) plus DB-gated subset
- `npx astro build` 0 new errors

---

## 7. Decisions ratified by PM (2026-05-24 p249)

All three open decisions ratified as Recommended defaults during spec review.

### Q1 — Routing policy for researcher track → **LRD round-robin** ✓

Decision: Least-recently-dispatched round-robin via `selection_dispatch_url_log` lookback (§5.1 query). Deterministic, fair across time, observable via the audit log, sub-ms cost with proposed index. Streaks self-correct after each dispatch. v2 may swap policy without schema change if LRD turns out poorly in practice.

**Rejected alternatives:** Random (visible streaks), Least-loaded by open interviews (requires defining "loaded" across off-platform commitments — not shippable in v1).

### Q2 — Member URL field name and validation → **`members.interview_booking_url` + app-level regex** ✓

Decision: New column `members.interview_booking_url text` (nullable, no DB CHECK). Validation lives at admin form level via simple `^https?://` regex. Naming is symmetric with `selection_cycles.interview_booking_url` (grep parity).

**Rejected alternatives:** `members.calendar_booking_url` (breaks grep symmetry); DB CHECK constraint (traps future deep-link providers); junction table `member_booking_pools` (overkill — Vitor + Fabricio have 1 pool each today).

### Q3 — Cycle 4 reseed approach → **Seed committee Vitor+Fabricio researcher, URLs NULL** ✓

Decision: SPEC #348 Child #4 = one-shot DML migration seeding `selection_committee` rows for Vitor + Fabricio (`role='researcher'`, `can_interview=true`); does NOT populate `members.interview_booking_url`. Routing falls back to `cycle.interview_booking_url` until PM populates personal URLs. Zero immediate behavior change. Keeps SPEC #348 schema-pure + 1 leaf of DML.

**Rejected alternatives:** Defer committee seed to a separate p226 child (creates orphan leaf); Seed with real URLs (blocked on PM-provided URLs — only Núcleo group link is known today).

---

## 8. Migration plan (post-PM ratification)

If Q1=LRD + Q2=interview_booking_url + Q3=committee-only-no-personal-URL:

1. Child #1 (foundation): migration §4.1 (DDL) + contract tests §6.1 offline assertions
2. Child #2 (RPC body): `CREATE OR REPLACE FUNCTION notify_selection_cutoff_approved` with the decision tree from §5.1 + DB-gated contract assertions
3. Child #3 (admin UI): `/admin/members/[id]` edit field for `interview_booking_url` + i18n keys × 3 langs
4. Child #4 (cycle4 reseed): one-shot DML migration seeding `selection_committee` rows for Vitor + Fabricio (researcher); does NOT touch `interview_booking_url` (PM populates later)

Each child is independently shippable. Child #2 is gated on Child #1. Child #3 + #4 can ship in parallel after Child #2 lands.

---

## 9. Cross-ref

- #348 (this spec's parent issue) — PM 4-step roadmap
- `docs/ops/CYCLE4_CUTOFF_DISPATCH_P243.md` (p243 runbook — v0 baseline)
- `docs/audit/CYCLE4_PERT_CUTOFF_P242_WATCH_240_C.md` (p242 — origin of #348)
- `supabase/migrations/20260805000011_p228_260_w2_leaf4_selection_cutoff_approved.sql` — current RPC body that v1 extends
- p226 carry: cycle4 committee seed (now ready to ship as SPEC #348 Child #4)
- p230 fast-follow: auto-trigger from cron jobid 47 — separate governance decision (cron auto-dispatch threshold)
- `selection_applications.cutoff_approved_email_sent_at` — idempotency tracking (unchanged)
- SEDIMENT-226.C — JWT-claim service-role pattern (no longer needed once committee seeded)

---

## 10. PM A/B/C/D streak

This SPEC is a spec-only deliverable per PM boot directive 2026-05-24:
> "Seguir para #348 booking routing/calendar registry spec: registrar decisão de curto prazo: link Núcleo usado no Cycle 4; desenhar v1 com booking_url por avaliador/comitê; researcher -> Vitor/Fabricio individual; leader -> Núcleo/dupla; deixar reschedule/cancel fora do v1."

All directive constraints honored: v0 decision documented (§1), v1 schema designed (§4), researcher/leader routing differentiated (§5), reschedule/cancel out of v1 (§3 OUT). Implementation deferred to children per §8.
