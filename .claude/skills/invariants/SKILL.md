---
name: invariants
description: Fast path para rodar check_schema_invariants() via Supabase MCP e interpretar resultado. Use mid-session para confirmar que nenhuma mudança quebrou as 8 invariantes estruturais (ADR-0012). Não dispara guardian completo — é um check rápido.
user_invocable: true
---

Call the Supabase MCP `execute_sql` tool on project `ldrfrvwhxsmgaabwmaik`:

```sql
SELECT invariant_name, severity, violation_count, sample_ids, description
FROM public.check_schema_invariants()
ORDER BY
  CASE severity WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
  invariant_name;
```

Expected: 8 rows, all `violation_count = 0`.

Interpret:
- **All 0** → ✅ Clean. Report in 1 line and continue.
- **Any ≠ 0** → ❌ BLOCK. Report:
  - Which invariant(s) violated
  - severity + violation_count + sample_ids (limit 10)
  - Probable cause (map to trigger/RPC that should have maintained it):
    - A1/A2: B7 trigger `sync_member_status_consistency`
    - A3: cache trigger `sync_operational_role_cache`
    - B/C: B7 trigger (same)
    - D: no trigger — ghost resolution via `try_auto_link_ghost()`
    - E: no trigger — enforced by `admin_offboard_member` RPC
    - F: no trigger — enforced at initiative delete (not implemented)
  - Recommend: investigate recent migrations or service_role UPDATEs that may have bypassed.

See `supabase/migrations/20260425010000_b10_schema_invariants.sql` for the canonical definitions.
See ADR-0012 (`docs/adr/ADR-0012-schema-consolidation-principles.md`) for rationale.

Do NOT attempt to auto-fix violations. Decision on how to reconcile (backfill vs rollback vs new trigger) belongs to the human.
