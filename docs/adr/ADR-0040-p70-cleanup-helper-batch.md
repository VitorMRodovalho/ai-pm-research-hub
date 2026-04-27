# ADR-0040: p70 cleanup batch — DROP dead helper + REVOKE-from-anon for 3 internal helpers

- Status: **Accepted** (2026-04-27 — PM Vitor ratified Q1=SIM / Q2=SIM)
- Data: 2026-04-27 (p70)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Pure cleanup batch — zero V4 conversion, zero member-set change.
  - Section A: DROP dead helper `current_member_tier_rank` (0 callers
    confirmed via pg_proc + src/ + supabase/ scan)
  - Section B: REVOKE FROM PUBLIC, anon for 3 internal SECDEF helpers
    (`_can_manage_event`, `_can_sign_gate`, `can_manage_comms_metrics`)
- Implementation:
  - Migration `20260427230000_adr_0040_p70_cleanup_helpers.sql`
- Cross-references: ADR-0011 (V4 auth), Track Q-D charter (defense-in-depth
  REVOKE pattern with pg_policy precondition), p64 incident sediment (only
  REVOKE from anon, NOT authenticated, unless RLS refs verified zero AND
  caller chain proven internal)

---

## Contexto

p70 Q-E parameter-gate full sweep returned **0 matches** beyond the 2
already-fixed cases (ADR-0038 `update_event_duration` + ADR-0039
`register_attendance_batch`). The pattern was effectively eradicated.

Pivoting to helper cluster cleanup: 5 SECDEF helpers identified in p67/p69
audit doc as "caller graph audit needed". p70 caller-graph analysis
revealed:

| Helper | Total callers (SECDEF) | Frontend | RLS refs | ACL anon | Verdict |
|---|---|---|---|---|---|
| `current_member_tier_rank` | 0 | 0 | 0 | NO_X | **DEAD CODE — DROP** |
| `has_min_tier` | 1 (exec_cert_timeline) | 0 | 0 | NO_X | leave-as-is (live) |
| `_can_manage_event` | 3 (event admin fns) | 0 | 0 | HAS_X | **REVOKE-from-anon** |
| `_can_sign_gate` | 8 (cert/governance fns) | 0 | 0 | HAS_X | **REVOKE-from-anon** |
| `can_manage_comms_metrics` | 1 (publish_comms_metrics_batch) | 0 | 0 | HAS_X | **REVOKE-from-anon** |

### Section A — DROP `current_member_tier_rank`

**Verification of dead-code status**:
```bash
$ grep -rn "current_member_tier_rank" --include="*.ts" --include="*.tsx" \
    --include="*.astro" --include="*.sql" src/ supabase/
supabase/migrations/20260425143511_qa_orphan_recovery_triggers_legacy_compute.sql:188:
  CREATE OR REPLACE FUNCTION public.current_member_tier_rank()
```

Single hit: the migration that created it (p52 Q-A orphan recovery
batch — recovered as part of 92 orphan-fn capture but never wired into
any caller). pg_proc caller-graph scan: 0 SECDEF callers.

`has_min_tier` (the natural caller for a tier-rank helper) does NOT call
`current_member_tier_rank` — it has its own inline tier mapping logic.
The two were created in parallel during p52 Q-A recovery but
`current_member_tier_rank` was never adopted.

**Decision**: DROP. Reduces SECDEF surface by 1, removes 1 orphan
authenticated_security_definer advisor entry.

### Section B — REVOKE-from-anon for 3 internal helpers

All 3 helpers have:
- 0 RLS policy refs (Q-D charter pg_policy precondition satisfied)
- 0 frontend `.rpc()` callers (no UI breakage)
- Only SECDEF→SECDEF callers (executes in postgres-definer context)
- anon_HAS_X currently (defense-in-depth gap)

REVOKE FROM PUBLIC, anon is safe because:
1. Internal SECDEF→SECDEF chains execute as definer (postgres role),
   not caller role — calling-role grant irrelevant for chained calls
2. RLS policies don't reference these helpers (verified via
   word-boundary regex on pg_policy.polqual + polwithcheck)
3. Frontend never calls them directly (verified via grep)

**NOT** REVOKE-ing from `authenticated` per p65 charter sediment: only
REVOKE-from-anon is autonomous; REVOKE-from-authenticated requires
broader caller chain verification and is left for explicit charter
sweep.

#### Per-helper rationale

**`_can_manage_event(p_event_id uuid)`** — Used by 3 event admin SECDEF:
- `manage_action_items`
- `upsert_event_agenda`
- `upsert_event_minutes`

Returns boolean indicating whether caller can manage a specific event.
Not user-facing — wrapped by event admin RPCs.

**`_can_sign_gate(p_member_id uuid, p_chain_id uuid, p_gate_kind text,
p_doc_type text, p_submitter_id uuid)`** — Used by 8 cert/governance SECDEF:
- `_enqueue_gate_notifications`, `get_chain_workflow_detail`,
  `get_document_detail`, `get_pending_ratifications`,
  `get_ratification_reminder_targets`, `preview_gate_eligibles`,
  `sign_ip_ratification`, `trg_approval_signoff_notify_fn`

ADR-0016 cert governance helper (signature gate eligibility check). Pure
internal helper.

**`can_manage_comms_metrics()`** — Used by 1 SECDEF:
- `publish_comms_metrics_batch`

Returns boolean for comms metrics management authority. Single internal caller.

### pg_policy precondition (Q-D charter mandatory)

Word-boundary regex `\m` scan on `pg_policy.polqual` + `polwithcheck` for
all 4 fns: **zero references** for each. Safe to proceed without RLS
hotpath risk.

---

## Decisão (proposta)

```sql
-- Section A: DROP dead helper
DROP FUNCTION IF EXISTS public.current_member_tier_rank();

-- Section B: REVOKE-from-anon for 3 internal helpers
REVOKE EXECUTE ON FUNCTION public._can_manage_event(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._can_sign_gate(uuid, uuid, text, text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.can_manage_comms_metrics() FROM PUBLIC, anon;
```

---

## Implications

### Para a plataforma
- 1 fn dropped (`current_member_tier_rank`) — pg_proc count -1, SECDEF
  surface -1, advisor entries -1 (authenticated_executable closure).
- 3 fns REVOKE-from-anon — advisor entries -3 (anon_executable closures).
- Net advisor change: **-4** (778 → 774 in p69 → 770 post-p70).
- Zero V4 conversion. Zero Phase B'' tally bump (orthogonal cleanup track).
- Zero member-set change.
- `current_member_tier_rank` removed from strict V3 candidate list
  (was previously in the 55-candidate count from p68 re-discovery).
- 1 helper item closed in p67 audit doc § "Helpers (caller graph audit
  needed)" cluster (`current_member_tier_rank`); 1 item triaged
  (`has_min_tier` confirmed live, leave-as-is).

### Para members
- Zero net change — pure security/cleanup hygiene.

### Para path A/B/C optionality
- Path A (PMI internal): positivo — security baseline tightened.
- Path B (consultoria): positivo — multi-tenant security hardening.
- Path C (community-only): neutro.

---

## Open Questions (para PM input)

### Q1 — Aceito DROP `current_member_tier_rank`?

Confirmed dead code via comprehensive search. Created in p52 Q-A orphan
recovery batch but never wired into any caller. `has_min_tier` (the
natural caller) has its own inline tier mapping.

Recomendação: **SIM** — pure dead code removal.

### Q2 — Aceito REVOKE-from-anon for 3 internal helpers?

Defense-in-depth pattern. All 3 have zero RLS refs, zero frontend
callers, only SECDEF→SECDEF caller chains. SAFE per Q-D charter
methodology.

Recomendação: **SIM** — security hygiene.

---

## Status / Next Action

- [x] Migration `20260427230000` (DROP + 3 REVOKEs)
- [x] Audit doc update — helper cluster triage + advisor count
- [x] Status ADR → `Proposed` (PM rubber-stamp pending)

**Bloqueador**: nenhum (PM rubber-stamp expected).

### Outcome (post-apply esperado)

- 1 fn dropped (`current_member_tier_rank`).
- 3 fns REVOKE-from-anon (`_can_manage_event`, `_can_sign_gate`,
  `can_manage_comms_metrics`).
- Helper cluster from p67 audit § "Helpers (caller graph audit needed)":
  - `current_member_tier_rank`: DROPPED (dead code).
  - `has_min_tier`: triaged live (1 caller, leave-as-is).
  - `_can_manage_event`, `_can_sign_gate`: triaged live (multi-caller,
    REVOKE-from-anon applied).
  - 2 of 4 helpers from cluster fully closed (DROP'd or REVOKE'd);
    2 remain for V3→V4 body conversion (future ADR — would need to
    convert `_can_manage_event`'s `operational_role IN (...)` check
    and `_can_sign_gate` similarly).
- pg_policy precondition (Q-D charter): zero RLS refs verified for all 4.
- Phase B'' tally unchanged (cleanup track, not Phase B'' track).
- Advisor surface: 778 → ~770 (4 closures).
