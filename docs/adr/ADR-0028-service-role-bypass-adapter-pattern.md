# ADR-0028: Service-Role-Bypass Adapter Pattern for Cron/EF Callers

- **Status**: Proposed
- **Date**: 2026-04-26 (drafted p63 extended)
- **Author**: Claude (autonomous draft, awaiting PM ratify)
- **Scope**: Establishes the canonical V4 conversion pattern for the **30
  `admin_*` SECDEF functions** that currently use a V3 OR-chain gate
  with explicit `auth.role() = 'service_role'` bypass for cron/EF
  callers. Closes the "29 service-role-bypass adapter pattern" backlog
  item from `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`.

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

### Domain breakdown of 30 fns

| Domain | Count | Examples |
|---|---|---|
| Ingestion lock + run lifecycle | 7 | admin_acquire/release_ingestion_apply_lock, admin_register/complete_ingestion_run, admin_check_ingestion_source_timeout |
| Ingestion provenance + alerts | 6 | admin_sign_ingestion_file_provenance, admin_verify_ingestion_provenance_batch, admin_raise_provenance_anomaly_alert, admin_update/run_ingestion_alert_remediation, admin_set_ingestion_alert_remediation_rule |
| Rollback management | 5 | admin_plan/approve/execute/simulate_ingestion_rollback, admin_append_rollback_audit_event |
| Release readiness | 5 | admin_record_release_readiness_decision, admin_release_readiness_gate, admin_set_release_readiness_policy, admin_check_readiness_slo_breach, admin_run_dry_rehearsal_chain |
| Data quality + snapshots | 4 | admin_capture_data_quality_snapshot, admin_data_quality_audit, admin_capture_governance_bundle_snapshot, admin_run_post_ingestion_chain |
| Misc | 3 | admin_get_ingestion_source_policy, admin_set_ingestion_source_sla, admin_run_post_ingestion_healthcheck, admin_resolve_remediation_action, admin_run_ingestion_alert_remediation, admin_suggest_notion_board_mappings |

All under `manage_platform` semantic domain (platform infrastructure +
governance ops).

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

### Conversion batches

Batch 1 — clean conversions (zero privilege change, broad V3):
- 27 fns where V3 = `superadmin OR mgr/dmr OR co_gp` exactly
- Convert to V4 manage_platform with adapter pattern
- Single migration

Batch 2 — extended-designations conversions (per-fn ADR):
- 3 fns with extra designations:
  - `admin_data_quality_audit` (+ chapter_liaison + sponsor) — needs
    `audit_access` action OR keep V3 (low risk)
  - Others TBD by per-fn audit
- Per-fn ADR ratify before convert

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

- **Closes 27 of 30 fns Phase B'' modernization** in single migration
  (Batch 1) — biggest single-batch progress
- **Pattern reusable** for any future fn with cron/EF + user-facing
  dual access (e.g., future analytics jobs, future bulk operations)
- **Preserves all cron/EF compatibility** — service_role unchanged
  behavior, no risk to scheduled ingestion runs
- **Documents the dual-tier gate** explicitly per-fn in COMMENT, so
  future readers understand "this is callable both ways"
- **Phase B'' tally bump**: 56/246 (22.8%) → ~83/246 (33.7%) post Batch 1

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
  service_role accident. Mitigation: only add adapter where actually
  needed; default new fns to strict V4 pattern (Pacotes E-I).

## Implementation phases (post-ratify)

### Phase 1 — per-fn privilege expansion audit (~2h)

Run the SQL check against all 30 fns. Group:
- **Clean (Batch 1)**: V3 broad set = V4 manage_platform set
- **Extended designations (Batch 2)**: V3 ⊋ V4 → per-fn decision

Output: docs/audit/ADR-0028-prematch-audit.md

### Phase 2 — Batch 1 migration (~3-4h)

Single migration converting 27 (or so) clean fns. Apply via
`apply_migration` MCP, repair migration history, smoke test contract
tests, commit.

### Phase 3 — Batch 2 per-fn ADRs + conversions (~per fn)

For each extended-designations fn: write ADR (e.g., ADR-0029
`audit_access` action), implement, test.

### Phase 4 — contract test enhancement

Update `rpc-v4-auth.test.mjs` (or add new contract) to recognize
adapter pattern as valid V4 alongside strict `can_by_member` top-level
gate.

## Cross-references

- ADR-0011 (V4 authority) — base contract that this extends
- ADR-0012 (schema consolidation) — related but distinct scope
- ADR-0025 (manage_finance) + ADR-0026 (manage_comms) + ADR-0027
  (governance readers Opção B) — prior Phase B'' patterns
- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` — surface inventory
- Pacote D-I commits (p59-p63) — easy-convert pattern that this complements
- p64 carry — depends on this ADR being Accepted before Pacote M

## Open questions for PM

1. **Action name**: `manage_platform` reuse OK, or new action like
   `manage_ingestion`? Current proposal: reuse `manage_platform` since
   all 30 fns are platform admin ops.
2. **Extended-designations**: how to treat `chapter_liaison` + `sponsor`
   in `admin_data_quality_audit`? New `audit_access` action OR keep V3?
   Current proposal: defer to per-fn ADR (Batch 2).
3. **Pattern accept criteria**: should `rpc-v4-auth.test.mjs` recognize
   adapter as valid V4? Current proposal: yes, with explicit allowlist
   (only 30 ADR-0028 fns, not blanket).
4. **Implementation timing**: do Batch 1 in next session OR batch with
   another track? Current proposal: standalone session (Pacote M, ~4h
   focused work).

## Pending

- [ ] PM ratify ADR (move from Proposed → Accepted)
- [ ] Batch 1 audit (27 fns clean classification)
- [ ] Batch 1 migration + tests + commit (Pacote M)
- [ ] Batch 2 per-fn ADRs (Pacote N+ as needed)
- [ ] Contract test enhancement
