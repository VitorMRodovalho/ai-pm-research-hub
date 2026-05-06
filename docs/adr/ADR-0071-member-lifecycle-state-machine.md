# ADR-0071: Member Lifecycle State Machine (ARM-9 Foundation + Features)

**Status**: Accepted. Foundation + Features both shipped 2026-05-06.
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

## Amendment 1 — Features shipped (2026-05-06)

Originally Features (G2+G3+G4) eram deferidas para sessão dedicada. PM (Vitor) ratificou continuação na mesma sessão com "tudo na recomendação". Shipped:

### G2 Re-engagement pipeline (migration `20260516850000`)

- ENUM `re_engagement_state ('staged','invited','declined','accepted','cancelled')`
- TABLE `re_engagement_pipeline` com state machine consistency CHECK + partial unique index `(member_id, cycle_code) WHERE state IN ('staged','invited','accepted')` (1 active per cycle, histórico declined/cancelled allowed)
- RLS rpc-only (RESTRICTIVE deny all) — defesa em profundidade
- 5 RPCs:
  - `stage_alumni_for_re_engagement(p_member_id, p_cycle_code, p_source)` — admin queues OR cron-staged. Idempotente.
  - `list_re_engagement_pipeline(p_state, p_cycle_code)` — admin view
  - `invite_alumni_to_re_engage(p_pipeline_id, p_message)` — staged → invited + notification
  - `respond_re_engagement(p_pipeline_id, p_response, p_note)` — alumni self-action (only invited member can respond)
  - `cancel_re_engagement(p_pipeline_id, p_reason)` — admin pre-response cancel
- Trigger `trg_auto_stage_alumni_on_cycle_open` AFTER UPDATE em `cycles` quando `is_current` flips false→true → auto-stages alumni com `return_interest=true`

### G3 Alumni badge auto-emit (migration `20260516860000`)

- `certificates.type` CHECK extended para incluir `alumni_recognition`
- `admin_offboard_member` upgraded: quando `p_new_status='alumni'` AND reason category `preserves_return_eligibility=true`, emite certificate automaticamente
- Graceful degradation: certificate emit failure NÃO bloqueia offboard (try/catch + audit log entry `arm9.alumni_badge_emit_failed`)
- Cycle int extraction safe: `regexp_replace(cycle_code, '[^0-9]', '')::int` com fallback 3

### G4 Inactivity detection cron (migration `20260516870000`)

- `site_config.inactivity_threshold_days` setting (default 180, configurable via UI futuro)
- `detect_inactive_members(p_dry_run)` SECDEF RPC com cron-context auth bypass (ADR-0028 pattern)
  - Heurística: `member_status='active' AND is_active=true AND created_at < now() - threshold AND no attendance.present=true within threshold`
  - Notifications para todos managers + deputy_managers (não auto-transitiona — manager decide)
- Cron `detect-inactive-members-weekly` schedule `'0 12 * * 1'` (Mondays 9h BRT)

### Post-G2: tightened alumni→active (migration `20260516880000`)

- `validate_status_transition` agora **BLOCKS alumni→active** direto (RAISE 22023 com mensagem de workflow)
- `admin_reactivate_member` upgraded com guard: alumni source requires accepted pipeline entry (`state='accepted'`)
  - Guard fail: audit log `admin_reactivate_blocked_no_pipeline` + error retorno com workflow descrito
- Self-transition idempotente preservada
- inactive→active e observer→active mantidos diretos (sabbatical/transition cases)

### Workflow alumni completo

```
[member_status='alumni'] (saída amigável com return_interest=true)
        ↓ trigger trg_auto_stage_alumni_on_cycle_open OR manual stage
[re_engagement_pipeline.state='staged']
        ↓ admin invoke invite_alumni_to_re_engage
[re_engagement_pipeline.state='invited'] + notification + email
        ↓ alumni invoke respond_re_engagement(accepted)
[re_engagement_pipeline.state='accepted'] + manager notification
        ↓ admin invoke admin_reactivate_member (guard: accepted pipeline)
[member_status='active'] + tribe assignment + role
```

### Estado pós-Features (2026-05-06)

- Total 4 migrations ARM-9 (5 com Foundation): `20260516840000` → `20260516880000`
- Invariants ainda 13/13 = 0 violations
- 5 novos RPCs + 1 RPC patched + 1 trigger + 1 cron + 1 site_config setting
- Build clean, tests baseline, no regressions

### Pendentes (não-bloqueantes)

- **MCP exposure** dos 5 RPCs novos (admin domain): `stage_alumni_for_re_engagement`, `list_re_engagement_pipeline`, `invite_alumni_to_re_engage`, `cancel_re_engagement`, `detect_inactive_members`. + 1 alumni-self: `respond_re_engagement`. Defer para próxima sessão (~30min add).
- **Frontend UI** alumni dashboard `/me/re-engagement/[pipeline_id]` para responder convite. Defer para Onda 4 browser session.
- **Frontend admin** `/admin/members?filter=inactive_candidates` view. Defer para Onda 4.
- **i18n**: notifications types novos (`re_engagement_invitation`, `re_engagement_accepted`, `re_engagement_declined`, `arm9_inactivity_alert`) need translations em pt-BR/en-US/es-LATAM se UI for expor.

## References

- Migration: `supabase/migrations/20260516840000_arm9_foundation_g5g6_transition_validation_invariant_n.sql`
- Audit doc: `docs/strategy/ARM_PILLARS_AUDIT_P107.md`
- ADR-0012: schema invariants principles
- ADR-0011: V4 authority (`can_by_member`)
- Reason categories table: `offboard_reason_categories`
- Triggers: `sync_member_status_consistency`, `_offboarding_create_stub`, `notify_offboard_cascade`
