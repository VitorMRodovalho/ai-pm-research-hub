# ADR-0028: Service-Role-Bypass Adapter Pattern for Cron/EF Callers

- **Status**: Accepted (ratified 2026-04-26 via Opção A council-validated)
- **Date**: 2026-04-26 (drafted p63 extended; ratified p64 via council
  multi-agent review — security-engineer + data-architect +
  senior-software-engineer + platform-guardian)
- **Author**: Claude (autonomous draft) + PM (Vitor) ratify
- **Relationship to ADR-0011**: This ADR formalizes the second class of
  exception to the strict V4 `can_by_member`-at-top contract (after
  ADR-0011 Amendment A fast-path stakeholder fan-out). Conceptually
  equivalent to "ADR-0011 Amendment C" but kept as standalone ADR-0028
  for discoverability of the dual-tier surface. ADR-0011 carries a
  back-reference stub.
- **Scope**: Establishes the canonical V4 conversion pattern for the
  **30 `admin_*` SECDEF functions** (Batch 1) plus **7 extended-
  designation SECDEF functions** (Batch 2) that currently use a V3
  OR-chain gate with explicit `auth.role() = 'service_role'` bypass
  for cron/EF callers. Closes the "29 service-role-bypass adapter
  pattern" backlog item from
  `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`.

## Framing (post-council reframe)

The adapter pattern is **not** a hole in the V4 `can_by_member`
authority contract. It is an explicit recognition of the
**machine-caller class boundary**: cron jobs and Edge Functions
authenticate at the infrastructure layer (Supabase service_role JWT,
not user-tier auth.uid). For these callers, `auth.uid()` is NULL by
design, and the V4 gate has no member-id input to evaluate. The
adapter short-circuits to the pre-authenticated service-role trust
boundary — an established Supabase primitive used by the platform's
own system functions and RLS policy exemptions.

The V4 contract remains: **the user-tier gate IS `can_by_member`**.
The adapter ELSE branch enforces it with no exception. The IF branch
recognizes a different caller class entirely, with its own
infrastructure-level auth chain.

What would muddy the V4 model is using the adapter for human callers
who lack `manage_platform`. That risk is contained by:
1. The 4-layer enforcement defense (allowlist + size guard +
   stale-check + COMMENT sentinel + invariant G) detailed in §"Q3
   resolution" below.
2. The explicit ADR rule: service_role bypass is only valid for
   cron/EF callers verified at infrastructure level — never as a
   convenience escape hatch for human-caller permission failures.

## Context

### State em 2026-04-26

Pacotes E-I (p59-p63) modernized 56/246 V3-gated SECDEF functions to
V4 `can_by_member()` authority. Easy-convert backlog (admin_* fns
without service_role bypass + zero privilege expansion) is **0** as of
p63 audit.

The remaining `admin_*` surface includes **30 functions** with a
distinctive pattern: they're called both by:
- **Service-role (cron, EFs, scripts)** for automated ingestion,
  rollback, governance bundle capture, release readiness checks
- **User-facing admin** (manager/deputy_manager/co_gp + sometimes
  chapter_liaison/sponsor) for manual triggers via admin UI

Sample (canonical shape):

```sql
SELECT * INTO v_caller FROM public.get_my_member_record();
IF v_caller IS NULL OR NOT (
    auth.role() = 'service_role'                              -- bypass for cron/EF
    OR v_caller.is_superadmin IS TRUE
    OR v_caller.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_caller.designations), false)
    -- optional extra designations per fn (chapter_liaison, sponsor)
) THEN
  RAISE EXCEPTION 'Project management access required';
END IF;
```

### Domain breakdown — confirmed by 2026-04-26 DB audit

**Total surface: 37 fns (30 Batch 1 clean + 7 Batch 2 extended).**
Original ADR draft estimated 30 (27 + 3); p64 prematch query of
`pg_proc` surfaced 6 additional `exec_*` fns also using the
service_role pattern that were missed in the original audit. All 6
share the extended-designation gate shape (chapter_liaison + sponsor
± curator).

#### Batch 1 — 30 clean `admin_*` fns (gate = manager/dmr/co_gp only)

| Domain | Count | Functions |
|---|---|---|
| Ingestion lock + run lifecycle | 5 | admin_acquire_ingestion_apply_lock, admin_release_ingestion_apply_lock, admin_register_ingestion_run, admin_complete_ingestion_run, admin_check_ingestion_source_timeout |
| Ingestion provenance + alerts | 6 | admin_sign_ingestion_file_provenance, admin_verify_ingestion_provenance_batch, admin_raise_provenance_anomaly_alert, admin_update_ingestion_alert_status, admin_run_ingestion_alert_remediation, admin_set_ingestion_alert_remediation_rule |
| Rollback management | 5 | admin_plan_ingestion_rollback, admin_approve_ingestion_rollback, admin_execute_ingestion_rollback, admin_simulate_ingestion_rollback, admin_append_rollback_audit_event |
| Release readiness | 5 | admin_record_release_readiness_decision, admin_release_readiness_gate, admin_set_release_readiness_policy, admin_check_readiness_slo_breach, admin_run_dry_rehearsal_chain |
| Data quality + snapshots | 3 | admin_capture_data_quality_snapshot, admin_capture_governance_bundle_snapshot, admin_run_post_ingestion_chain |
| Misc | 6 | admin_get_ingestion_source_policy, admin_set_ingestion_source_sla, admin_run_post_ingestion_healthcheck, admin_resolve_remediation_action, admin_suggest_notion_board_mappings, (note: admin_data_quality_audit moved to Batch 2 — extended) |

#### Batch 2 — 7 extended-designation fns (gate widens beyond manage_platform set)

| Function | Extension | Domain |
|---|---|---|
| admin_data_quality_audit | + chapter_liaison + sponsor | Internal audit access |
| exec_governance_export_bundle | + chapter_liaison + sponsor + curator | Governance export |
| exec_partner_governance_summary | + chapter_liaison + sponsor + curator | Partner governance |
| exec_partner_governance_scorecards | + chapter_liaison + sponsor + curator | Partner governance |
| exec_partner_governance_trends | + chapter_liaison + sponsor + curator | Partner governance |
| exec_readiness_slo_by_source | + chapter_liaison + sponsor | SLO drill-down |
| exec_readiness_slo_dashboard | + chapter_liaison + sponsor | SLO dashboard |
| exec_remediation_effectiveness | + chapter_liaison only | Remediation analytics |

**Three extension shapes** require ADR-0029 design:
- **Shape A** (chapter_liaison + sponsor): admin_data_quality_audit,
  exec_readiness_slo_by_source, exec_readiness_slo_dashboard
- **Shape B** (+ curator): exec_governance_export_bundle, exec_partner_governance_*  (×3)
- **Shape C** (chapter_liaison only): exec_remediation_effectiveness

Likely consolidation: a new action `audit_access` granted to
`{chapter_liaison, sponsor, curator}` covers shapes A + B; shape C
narrows to `chapter_liaison` only via designation re-check after
adapter gate. ADR-0029 to formalize.

All 30 Batch 1 fns are under `manage_platform` semantic domain
(platform infrastructure + governance ops). Batch 2 is the
audit/governance-export delegation surface that requires its own
action taxonomy.

### Tensions

1. **Cron/EF must continue working.** Service-role callers (pg_cron via
   external scheduler, EFs invoked by webhook, scripts run by
   service_role JWT) bypass user-tier auth by design. Removing the
   bypass = breaking automated ingestion.

2. **V4 `can_by_member()` requires `auth.uid()`.** Service-role calls
   have `auth.uid()` IS NULL and `auth.role() = 'service_role'`. A
   naive V4 conversion using `SELECT id FROM members WHERE auth_id =
   auth.uid()` would NULL out and trigger `authentication_required`
   exception, breaking cron.

3. **Privilege expansion check is the hard part.** Most fns have
   `manager/deputy_manager/co_gp` (broad pattern) — V4 `manage_platform`
   matches (=2 superadmins). But several extend: `admin_data_quality_audit`
   includes `chapter_liaison` + `sponsor` ("internal audit access").
   Per-fn audit needed to confirm V4 `manage_platform` doesn't contract
   privileges for these designations.

## Decision

### Adapter pattern (canonical)

```sql
CREATE OR REPLACE FUNCTION public.admin_X(...)
RETURNS ...
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  -- Adapter: allow service_role bypass (cron/EF callers)
  IF auth.role() = 'service_role' THEN
    -- Service-role call: skip user-tier gate, proceed to body
    NULL;
  ELSE
    -- User-tier call: V4 gate via can_by_member
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN
      RAISE EXCEPTION 'authentication_required';
    END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'permission_denied: manage_platform required';
    END IF;
  END IF;

  -- BODY UNCHANGED (use COALESCE(v_caller_id, NULL::uuid) where INSERT
  -- needs actor_id to allow service_role to skip member attribution)
  ...
END;
$$;
```

### Privilege expansion safety per-fn

Required per-fn check before applying:

```sql
WITH v3_set AS (
  SELECT id, name FROM members WHERE is_active = true
    AND (
      is_superadmin = true
      OR operational_role IN ('manager', 'deputy_manager')
      OR ('co_gp' = ANY(designations))
      -- + extra designations from this specific fn's V3 OR-chain
    )
),
v4_set AS (
  SELECT id, name FROM members WHERE is_active = true
    AND can_by_member(id, 'manage_platform') = true
)
SELECT
  (SELECT count(*) FROM v3_set) v3,
  (SELECT count(*) FROM v4_set) v4,
  (SELECT array_agg(name) FROM (SELECT name FROM v4_set EXCEPT SELECT name FROM v3_set) x) gain,
  (SELECT array_agg(name) FROM (SELECT name FROM v3_set EXCEPT SELECT name FROM v4_set) x) lose;
```

If `lose` non-null → conversion CONTRACTS privileges → DEFER to
per-domain ADR (e.g., `audit_access` action for chapter_liaison +
sponsor data quality readers).

### Conversion batches (post p64 audit + Phase 1 + P3 ratify)

**SCOPE AMENDMENT (2026-04-26 p64 post-execution)**: Phase 1 audit
revealed that 32 of 37 originally-targeted fns were dead code
referencing missing substrate tables (see `ADR-0029` retroactive
retirement). PM ratified P3 (split): the 5 OK fns identified as
having existing substrate became the actual ADR-0028 conversion scope.
A dependency re-check during implementation reduced this to 4 OK
(admin_capture_data_quality_snapshot is transitively broken via
admin_data_quality_audit dependency).

**Final Pacote M execution (migration `20260427000000`)**:
- **4 OK fns converted** to V4 `manage_platform` with adapter pattern:
  - `admin_check_ingestion_source_timeout(text, timestamptz)`
  - `admin_set_ingestion_source_sla(text, integer, integer, text, boolean)`
  - `admin_set_release_readiness_policy(text, text, integer, integer)`
  - `admin_get_ingestion_source_policy(text)`
- **33 dead-code fns DROPPED** per ADR-0029 (28 admin_* including all
  PARTIAL_BROKEN + admin_capture_data_quality_snapshot transitively
  broken, plus 7 exec_*).
- COMMENT sentinel `'ADR-0028 service-role-bypass adapter (Pacote M, p64)'`
  applied to the 4 surviving fns.
- REVOKE EXECUTE FROM PUBLIC, anon on the 4.
- Original Batch 2 (7 extended exec_*) DROPPED entirely (broken too,
  not just extended-gated). No future ADR-0029 audit_access action
  needed — surface eliminated.

**Phase 4 contract test enhancement** ships separately in same Pacote M
session: extends `tests/contracts/rpc-migration-coverage.test.mjs` to
detect table-level DDL drift (the bug class that allowed the substrate
to be silently dropped without migration capture).

The original 4-layer enforcement defense (allowlist + size guard + stale
check + COMMENT sentinel + invariant G) described in §"Q3 resolution"
remains valid and is implemented for the final 4-fn scope. The size
guard cap is reduced from 30 to 4 reflecting actual scope.

### Migration template (Batch 1)

```sql
DROP FUNCTION IF EXISTS public.admin_X(<args>);
CREATE OR REPLACE FUNCTION public.admin_X(<args>)
RETURNS <type>
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  -- preserve other body declarations
BEGIN
  IF auth.role() = 'service_role' THEN
    NULL;  -- service-role bypass
  ELSE
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
    IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'permission_denied: manage_platform required';
    END IF;
  END IF;

  -- BODY (v_caller.id → COALESCE(v_caller_id, NULL::uuid) where applicable)
  ...
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_X(<args>) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.admin_X(<args>) IS
  'ADR-0028 service-role-bypass adapter (Pacote M, p?): manage_platform
   gate via can_by_member with service_role bypass for cron/EF callers.';
```

## Consequences

### Positivas

- **Closes 30 of 37 fns Phase B'' modernization** in single migration
  (Batch 1) — biggest single-batch progress
- **Pattern reusable** for any future fn with cron/EF + user-facing
  dual access (e.g., future analytics jobs, future bulk operations)
- **Preserves all cron/EF compatibility** — service_role unchanged
  behavior, no risk to scheduled ingestion runs
- **Documents the dual-tier gate** explicitly per-fn in COMMENT
  (sentinel `'ADR-0028'`), so future readers understand "this is
  callable both ways" and the contract test can enforce registration
- **Phase B'' tally bump**: 61/246 (24.8%) → 91/246 (37.0%) post
  Batch 1; further to 98/246 (39.8%) post Batch 2 (ADR-0029)

### Negativas / Custos

- **Body change footprint**: ~30 fns × ~15 lines each = ~450 lines
  changed. Mostly mechanical (template apply), but each needs body
  preservation review (some fns use `v_caller.id` deep in INSERTs;
  must replace with `COALESCE(v_caller_id, NULL::uuid)` to allow
  service_role to skip member attribution).
- **Test exposure**: contract tests like `rpc-v4-auth.test.mjs` may
  flag the adapter pattern as non-canonical (current pattern strict
  `can_by_member` at top). Need test update to recognize adapter as
  valid V4 form for service-role-bypass class.
- **No test for service_role bypass behavior**: contract tests can't
  easily assert service_role bypass works without env (CI doesn't have
  service_role JWT). Document in COMMENT + smoke test in CI via
  service_role key when available.

### Riscos

- **`v_caller_id IS NULL` in INSERT contexts** that expect non-null
  actor_id — could violate FK or NOT NULL. Mitigation: per-fn audit of
  INSERT/UPDATE statements before apply; use `COALESCE(v_caller_id, ...)`
  with sane fallback (e.g., `NULL::uuid` for nullable cols, or skip
  attribution-tracking inserts when service_role).
- **Service-role privilege bypass makes auditing harder** — actor_id
  becomes nullable in audit logs. Mitigation: log `auth.role()` value
  alongside actor_id so post-hoc audit can distinguish "automated cron"
  from "user-initiated".
- **Pattern creep**: future fns that don't actually need bypass might
  copy-paste the pattern, granting unauthenticated access via
  service_role accident. Mitigation: 4-layer defense in §"Q3 resolution"
  below — allowlist + size guard + COMMENT sentinel + invariant G —
  with the contract test rejecting any fn using the bypass without
  explicit allowlist registration.

### Future contraction path (manage_platform reuse caveat)

Reusing `manage_platform` for all 30 Batch 1 fns is the right call
today (zero-overhead privilege diff vs current V3 set; no schema
fragmentation). However, if a future PM decision introduces a narrower
"ingestion operator" persona who must access ingestion-lifecycle fns
WITHOUT having full `manage_platform` authority (e.g., delegated DevOps
role with no member-management or governance authority), the path is:

1. Create new action `manage_ingestion` in `engagement_kind_permissions`.
2. Seed the new action for the existing manage_platform set (compatibility).
3. Migrate all 30 fns in single migration to call
   `can_by_member(v_caller_id, 'manage_ingestion')` instead.
4. Add the new persona kind/role row to seed for `manage_ingestion` only
   (NOT `manage_platform`).

This requires a single consolidated migration, not piecemeal — the
30-fn surface is mechanically rewritable. Document the contraction
trigger explicitly so future PMs do not waste cycles re-litigating
"should we have named it manage_ingestion from the start" — answer:
no, premature taxonomy adds maintenance with no benefit until the
narrower persona materializes.

## Implementation phases (post-ratify)

### Phase 1 — per-fn privilege expansion audit + actor_id NULL strategy (~2h)

Run the V3-set vs V4-set SQL check against all 37 fns. For each fn:
1. Confirm classification (Batch 1 clean vs Batch 2 extended).
2. Read body and identify every `INSERT`/`UPDATE` statement that
   references caller identity (`v_caller.id`, `v_caller_id`,
   `actor_id`, etc.).
3. Decide per-statement: `COALESCE(v_caller_id, NULL::uuid)` (when
   target column is nullable) OR skip-attribution-when-service-role
   pattern (when target column is NOT NULL or has FK to
   `members(id)`).
4. Document strategy per fn in audit output.

Output: `docs/audit/ADR-0028-prematch-audit.md` with per-fn table:
classification, V3 set, V4 set, gain/lose, actor_id strategy.

**PM checkpoint after Phase 1 before Phase 2 migration applies.**

### Phase 2 — Batch 1 migration (~3-4h, 30 clean fns)

Single migration `pacote_m_adr0028_service_role_adapter_batch1.sql`
converting 30 clean fns to adapter pattern. Apply via
`apply_migration` MCP, repair migration history, smoke test contract
tests, commit. Includes:
- Per-fn body preservation per Phase 1 strategy.
- COMMENT sentinel `'ADR-0028 service-role-bypass adapter (Pacote M, p64)'`.
- REVOKE EXECUTE FROM PUBLIC, anon (preserve current security
  baseline).

### Phase 3 — Batch 2 per-fn ADR (ADR-0029) + Pacote O conversion (~per fn, hard deadline)

ADR-0029 formalizes new action `audit_access` granted to
`{chapter_liaison, sponsor, curator}` for the 7 Batch 2 fns. Single
migration `pacote_o_adr0029_audit_access_batch2.sql` after PM ratify.
**Hard deadline: ratify + apply before any non-Pacote-M autonomous
track resumes** (no open-ended defer).

### Phase 4 — contract test enhancement (4-layer defense, same Pacote M session)

Update `tests/contracts/rpc-v4-auth.test.mjs` per Q3 resolution
4-layer defense (allowlist + size guard + stale-check + COMMENT
sentinel). Add invariant G to `check_schema_invariants()`. Both must
ship in same commit as Pacote M migration to maintain test
ratchet.

## Cross-references

- ADR-0011 (V4 authority) — base contract that this extends.
  ADR-0011 carries a back-reference stub pointing to ADR-0028 in its
  Amendments-equivalent section.
- ADR-0012 (schema consolidation) — invariant G new in
  `check_schema_invariants()` follows ADR-0012 invariant-as-test
  pattern.
- ADR-0025 (manage_finance) + ADR-0026 (manage_comms) + ADR-0027
  (governance readers Opção B) — prior Phase B'' patterns.
- ADR-0029 (audit_access — to be drafted) — formalizes Batch 2
  extended-designation surface (7 fns).
- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` — surface inventory.
- `docs/audit/ADR-0028-prematch-audit.md` — Phase 1 per-fn audit
  output (produced same Pacote M session).
- Pacote D-I commits (p59-p63) — easy-convert pattern that this complements.
- p64 carry — Pacote M execution gated by this ADR Accepted status.

## Resolved questions (PM ratify 2026-04-26 via Opção A council-validated)

Decisions resolved unanimously by 4-agent council review
(security-engineer + data-architect + senior-software-engineer +
platform-guardian) and ratified by PM:

### Q1 resolution — Action name: REUSE `manage_platform`

The `engagement_kind_permissions` seed already grants `manage_platform`
to `volunteer × {manager, deputy_manager, co_gp}` — this is the exact
V3 broad set the 30 Batch 1 fns gate against today. Privilege diff =
zero. A new `manage_ingestion` action would require a new seed row, a
new gate call site, and an amendment to ADR-0011 actions table — paid
in perpetuity for zero behavioral difference. See "Future contraction
path" in Consequences for the migration recipe if a narrower ingestion
operator persona ever materializes.

### Q2 resolution — Extended designations: per-fn ADR (Batch 2) with HARD DEADLINE

`chapter_liaison` and `sponsor` have zero rows in
`engagement_kind_permissions` for any write/admin action today. Folding
them into `manage_platform` would be a silent privilege expansion (all
27→30 Batch 1 fns would inherit those designations together) — vetoed.
Keeping V3 indefinitely makes the fns invisible to `rpc-v4-auth`
contract test, repeating the 92-orphan pattern from Track Q (p50) —
vetoed.

Resolution: ADR-0029 to formalize new action `audit_access` (or
scope-refined alternative) for the 7 Batch 2 fns. **Hard deadline:
ADR-0029 must be ratified and Batch 2 migration applied before any
non-Pacote-M autonomous track resumes** — no open-ended defer.

### Q3 resolution — 4-layer pattern enforcement defense

The contract test must enforce the bypass class boundary. PM ratified
the council's full 4-layer defense (each layer catches a different
failure mode at low marginal cost):

1. **Named allowlist constant** in `tests/contracts/rpc-v4-auth.test.mjs`:
   ```javascript
   const V4_SERVICE_ROLE_ADAPTER_ALLOWLIST = new Set([
     'public.admin_acquire_ingestion_apply_lock',
     'public.admin_release_ingestion_apply_lock',
     // ... all 30 Batch 1 fns by full name
   ]);
   ```
   Test extends `usesV4Can()` to return true when body contains both
   `auth.role() = 'service_role'` and `can_by_member` AND the function
   name is in the allowlist. Non-allowlisted fns using the bypass fail
   the test.

2. **Size guard** (hard upper bound):
   ```javascript
   assert.ok(
     V4_SERVICE_ROLE_ADAPTER_ALLOWLIST.size <= 30,
     'ADR-0028 adapter allowlist exceeds the documented Batch 1 bound (30 fns). New entries require ADR-0028 amendment + PM ratify.'
   );
   ```
   (Batch 2 will bump this to 37 after ADR-0029.)

3. **Stale-entry cross-check**: assert every name in the allowlist
   actually appears in a migration file's `CREATE OR REPLACE FUNCTION`
   block. Stale entries (allowlist references a deleted fn) fail fast.

4. **COMMENT sentinel** in every adapter-pattern fn body:
   ```sql
   COMMENT ON FUNCTION public.admin_X(<args>) IS
     'ADR-0028 service-role-bypass adapter (Pacote M, p64): manage_platform
      gate via can_by_member with service_role bypass for cron/EF callers.';
   ```
   Auditable via `grep` over `pg_proc.obj_description`. The contract
   test cross-checks: every fn with `auth.role() = 'service_role'` in
   body must have `'ADR-0028'` in COMMENT, OR be flagged.

5. **Invariant G in `check_schema_invariants()`** (new structural
   invariant — bumps total to 12):
   ```sql
   -- G_service_role_adapter_count_within_bound
   -- Counts SECDEF fns with service_role bypass that are NOT in the
   -- documented ADR-0028 allowlist. Catches drift in production live,
   -- not just at test time.
   SELECT count(*) FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prosecdef = true
     AND pg_get_functiondef(p.oid) ILIKE '%auth.role() = ''service_role''%'
     AND p.proname NOT IN ( /* allowlist names */ );
   ```
   Fires (violation_count > 0) if any future fn outside the allowlist
   adopts the pattern. This is the only mechanical guard that survives
   sessions where the developer never reads ADR-0028.

### Q4 resolution — Standalone Pacote M session (audit + execution same session, with PM checkpoint)

Standalone session (~6h total: ~2h Phase 1 audit + ~3-4h Phase 2
migration). Phase 1 produces `docs/audit/ADR-0028-prematch-audit.md`
with per-fn classification + `actor_id` NULL handling strategy. PM
checkpoint after Phase 1 before Phase 2 migration applies. Single
focused session avoids cognitive context-switch + maintains atomic
rollback granularity for the 30-fn batch.

## Pending

- [x] PM ratify ADR (Proposed → Accepted, 2026-04-26 via Opção A
      council-validated)
- [ ] Phase 1 prematch audit (`docs/audit/ADR-0028-prematch-audit.md`):
      30 clean + 7 extended classification + actor_id NULL strategy per fn
- [ ] **PM checkpoint**: review Phase 1 audit before Phase 2 applies
- [ ] Phase 2 Batch 1 migration + tests + commit (Pacote M)
- [ ] Phase 4 contract test enhancement (4-layer defense)
- [ ] ADR-0029 draft + PM ratify (audit_access action for Batch 2)
- [ ] Batch 2 migration (Pacote O, post ADR-0029)
- [ ] ADR-0011 cross-reference back-stub added (back-link to ADR-0028)
