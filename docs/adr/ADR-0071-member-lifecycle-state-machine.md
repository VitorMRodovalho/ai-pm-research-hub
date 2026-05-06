# ADR-0071: Member Lifecycle State Machine (ARM-9 Foundation)

**Status**: Accepted (Foundation phase). Features (re-engagement pipeline + alumni badge + inactivity cron) deferred to follow-up session.
**Date**: 2026-05-06
**Decider**: PM Vitor Maia Rodovalho (GP Núcleo IA & GP)
**Trigger**: ARM-9 Offboarding deep dive (sessão p108 pós-ABCD plan ratification)

---

## Context

ARM-9 (Offboarding) foi reportado em maturidade 1 no `ARM_PILLARS_AUDIT_P107.md` baseado em "alumni path formal não existe". Audit mais profundo (sessão p108) revelou que o substrato é muito mais maduro:

- `members.member_status` text + CHECK `IN (active, observer, alumni, inactive, candidate)` — 5 states
- Tracking columns: `offboarded_at`, `offboarded_by`, `status_changed_at`, `status_change_reason`
- `member_offboarding_records` table com 19 campos (exit_interview, return_interest, lessons_learned, attachments)
- `offboard_reason_categories` table com 10 códigos i18n + flags `is_volunteer_fault` + `preserves_return_eligibility`
- 3 triggers ativos em `members`: `sync_member_status_consistency` (BEFORE coerce), `_offboarding_create_stub` (AFTER auto-record), `notify_offboard_cascade` (AFTER notify + orphan card)
- 17 RPCs + 3 crons LGPD-compliant

Maturidade real ARM-9 estava em ~2.5, não 1. O gap real é state machine validation (origem-aware) e re-engagement governance (staged pipeline + alumni badge + inactivity detection) — não infraestrutura básica.

## Decision

### State Machine — 5 states + transition rules

```
         ┌─────────────┐
         │  candidate  │ (pre-membership; selection_applications layer)
         └──────┬──────┘
                │ acceptance
                ▼
         ┌─────────────┐
    ┌────│   active    │────┐
    │    └──────┬──────┘    │
    │           │           │
    │           ▼           │
    │    ┌─────────────┐   │
    │    │  observer   │◄──┤ (downgrade voluntário)
    │    └──────┬──────┘   │
    │           │          │
    │           ▼          │
    │    ┌─────────────┐  │
    └───►│   alumni    │◄─┤ (saída amigável)
         └──────┬──────┘  │
                │         │
                ▼         │
         ┌─────────────┐  │
         │  inactive   │◄─┘ (saída administrativa silenciosa)
         └─────────────┘
```

**Regras Foundation (sessão p108):**

| From → To | Allowed | Notes |
|-----------|---------|-------|
| `candidate → active` | ✓ | Selection acceptance only |
| `candidate → observer/alumni/inactive` | ✗ | Pre-membership cannot transition to terminal directly |
| `* → candidate` | ✗ | Candidate is pre-membership only |
| `active → observer/alumni/inactive` | ✓ | Standard offboard via `admin_offboard_member` |
| `observer/alumni/inactive → active` | ✓ at Foundation | Via `admin_reactivate_member` (preserves p107 #136 anonymized guard) |
| `terminal → terminal (different)` | ✓ | Re-classification allowed (e.g., observer → alumni) |
| Any self-transition | ✓ (idempotent) | Returns no-op |

**Regras adicionais a serem enforced em Features (sessão de follow-up):**

| From → To | Future Restriction |
|-----------|--------------------|
| `alumni → active` | Force flow through `re_engagement_pipeline` (staged → invited → accepted), not direct via `admin_reactivate_member`. Preserve `inactive → active` direct path (sabbatical case). |

### Status semantics

- **`active`**: voluntário em ciclo corrente, com engagement ativo, gerando atividade.
- **`observer`**: membro ainda interessado mas sem engagement ativo (sabático curto, transição). Mantém acesso read-only.
- **`alumni`**: saída amigável, com `preserves_return_eligibility=true` na reason category. Elegível para re-convite via re-engagement pipeline (Features).
- **`inactive`**: saída administrativa silenciosa, com possível ressalva (`policy_violation` reason → `is_volunteer_fault=true` + `preserves_return_eligibility=false`).
- **`candidate`**: pre-membership; vive primariamente em `selection_applications` table; transição para `active` é tratada pelo selection pipeline.

### `withdrawn` status — explicitly NOT added

Considerada mas rejeitada (decisão D1). Razão: `inactive` + reason category `policy_violation` (com `is_volunteer_fault=true` + `preserves_return_eligibility=false`) já comunica saída unilateral/conflitiva. Adicionar 6º status criaria overhead de UI e tradução sem agregar valor semântico distinto.

### Defense-in-depth invariant N

Adicionada invariante 13ª (`N_terminal_status_offboarded_at_present`) ao `check_schema_invariants()`:
```
member_status IN (alumni/observer/inactive) AND anonymized_at IS NULL
  → offboarded_at IS NOT NULL
```

Complementa invariant L (`offboarding_record_present` checa existência de row em `member_offboarding_records`). Defesa em profundidade catches drift se trigger `_offboarding_create_stub` falhar ou for skipped.

## Implementation (Foundation — applied 2026-05-06)

Migration `20260516840000_arm9_foundation_g5g6_transition_validation_invariant_n.sql`:

1. **Backfill**: 14 members em `terminal status` com `offboarded_at IS NULL` setados via `COALESCE(status_changed_at, updated_at, created_at, now())`. Preservou whitelist `VP Desenvolvimento Profissional (PMI-GO)` (placeholder institucional).

2. **`validate_status_transition(p_from text, p_to text)`** RETURNS void:
   - Self-transitions: idempotent (return early, no-op)
   - candidate ↔ terminal: RAISE EXCEPTION 22023
   - All other transitions: allowed
   - IMMUTABLE, SET search_path, GRANT EXECUTE TO authenticated/service_role

3. **`admin_offboard_member`** atualizada para chamar `validate_status_transition` antes do UPDATE. Em caso de violation, registra audit log entry `member.status_transition_blocked` + retorna error com `arm9_gate` flag.

4. **Invariant N** adicionada a `check_schema_invariants()`. Total agora **13 invariantes (was 12)**.

Pós-aplicação: `check_schema_invariants() = 13/13 = 0 violations`.

## Consequences

### Positive

- Documentação formal do state machine (era código implícito + CHECK constraint)
- Defense-in-depth via invariant N catches future trigger drift
- 14 alumni com offboarded_at backfilled (consistência histórica)
- Audit log captura tentativas de transition inválidas (auditability)
- Foundation low-risk: nenhuma mudança user-facing visible (só transitions já-impossible são bloqueadas)
- Path para Features fica claro: re-engagement pipeline herda esse helper

### Negative

- 1 nova função pública (`validate_status_transition`) — pequena surface area
- 1 nova invariante (manutenção marginal)
- alumni→active via `admin_reactivate_member` permanece permitido até Features completarem (debt explícita, não silenciosa)

### Backwards-incompatible

Nenhum. Foundation não modifica nenhuma transição que já era permitida.

## Follow-ups (Features — sessão dedicada)

1. **G2 Re-engagement pipeline**: tabela `re_engagement_pipeline` (staged → invited → declined/accepted) + cron quando `cycles.is_current` flips + RPCs `invite_alumni_to_re_engage` + integração com `admin_reactivate_member` para forçar path correto.
2. **G3 Alumni badge**: `certificates.type='alumni_recognition'` + auto-emit em `admin_offboard_member` quando `p_new_status='alumni'` AND reason category `preserves_return_eligibility=true`.
3. **G4 Inactivity detection cron**: `detect_inactive_members` rodando weekly, threshold configurável via `site_config.inactivity_threshold_days` (default 180), notification para manager propondo transição active→inactive.
4. **Restricted alumni→active**: post-G2, atualizar `validate_status_transition` para BLOCK alumni→active (enforce pipeline path).

## References

- Migration: `supabase/migrations/20260516840000_arm9_foundation_g5g6_transition_validation_invariant_n.sql`
- Audit doc: `docs/strategy/ARM_PILLARS_AUDIT_P107.md`
- ADR-0012: schema invariants principles
- ADR-0011: V4 authority (`can_by_member`)
- Reason categories table: `offboard_reason_categories`
- Triggers: `sync_member_status_consistency`, `_offboarding_create_stub`, `notify_offboard_cascade`
