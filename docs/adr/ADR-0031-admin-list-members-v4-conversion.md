# ADR-0031: `admin_list_members` V4 conversion — Opção B reuse `view_internal_analytics`

- Status: **Accepted** (2026-04-26 p66 — PM rubber-stamp Q1=SIM / Q2=SIM / Q3=SIM / Q4=p66)
- Data: 2026-04-26 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track — fecha 1 fn V3 (admin_list_members)
  via reuso de action V4 existente
- Implementation:
  - Migration `20260427121244_adr_0031_admin_list_members_v4_view_internal_analytics.sql`
  - Migration `20260427121249_adr_0031_admin_list_members_revoke_anon.sql`
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (V4 auth pattern),
  ADR-0027 (governance readers — sister Opção B reuse precedent),
  ADR-0030 (view_internal_analytics — action being reused)

---

## Contexto

Sequência de ADR-0030 (`view_internal_analytics`). Fecha mais 1 fn V3
documentada como Phase B'' candidate em handoff p67 next-tier discovery.

### A função afetada

**`admin_list_members(p_search text, p_tier text, p_tribe_id integer, p_status text)`** —
member directory listing com 18 colunas incluindo email + auth_id (PII).
Caller: `src/pages/admin/members.astro` (admin tier) + admin pages.

V3 gate atual:
```sql
IF NOT EXISTS (
  SELECT 1 FROM members
  WHERE auth_id = auth.uid()
    AND (
      is_superadmin = true
      OR operational_role IN ('manager', 'deputy_manager', 'sponsor', 'chapter_liaison')
    )
) THEN
  RAISE EXCEPTION 'Admin only';
END IF;
```

V3 set: **9 active members** — Vitor SA + 8 com operational_role nas roles
admin/governance.

### Por que reuso (Opção B) ao invés de nova action

Análise das 9 actions V4 existentes:

| Action | Audience match? | Privilege expansion vs V3 |
|---|---|---|
| `manage_platform` | volunteer×{co_gp,manager,deputy_manager} | NÃO — perde sponsor + chapter_liaison + chapter_board (4 vs 9) |
| `manage_member` | manage_platform + initiative leaders | NÃO — só 2 active members têm hoje |
| `manage_event` | manage_platform + initiative leaders + comms_leader | Mistura escopos — broad demais |
| `manage_partner` | sponsors-broad — drift signal #5 #6 PM-blocked | Não cabe |
| `manage_finance` (ADR-0025) | manage_platform + sponsor | Falta chapter_liaison |
| `manage_comms` (ADR-0026) | manage_platform + comms_leader | Não cabe |
| `view_pii` | manage_platform + chapter_board.board_member + initiative leaders | Broad demais — initiative leaders veriam todo o diretório |
| **`view_internal_analytics` (ADR-0030)** | volunteer×{co_gp,manager,deputy_manager} + sponsor + chapter_board×liaison | ✅ **Match excelente** — legacy 9 → V4 10 (+Roberto) |
| `write` / `write_board` | tribe-scoped | Não cabe |

**Privilege expansion check (verified pre-apply):**
```
legacy (V3) = 9: Vitor SA, Ana, Fabricio, Felipe, Francisca, Ivan,
                  Márcio, Matheus, Rogério
v4 (view_internal_analytics) = 10: legacy 9 + Roberto Macêdo
would_gain = [Roberto Macêdo] (chapter_board × liaison engagement)
would_lose = []
```

**Roberto context**: `operational_role=observer` mas designations
`[chapter_liaison, ambassador, curator]` + V4 engagement `chapter_board ×
liaison` (organization scope). V3 não incluía Roberto porque V3 usa
`operational_role IN (...)` (string match em coluna `operational_role`),
não designations. V4 inclui Roberto via engagement chapter_board×liaison
— legítimo papel institucional.

Roberto **deveria** ter acesso a member directory para seu chapter_board
liaison role. V4 conversion **corrige um gap** de V3: papel governance
sem operational_role admin não tinha acesso, mas o engagement V4 indica
que deveria.

### Custo de não fazer

- 1 fn V3 permanece. Phase B'' tally trava.
- Roberto continua sem acesso member directory que sua função exige.
- Inconsistência: ADR-0030 já dá acesso a chapter_board × liaison para
  analytics; admin_list_members é parte da mesma surface admin.

### Custo de criar nova action `view_member_directory`

- +1 V4 action no inventário (sprawl)
- Ladder seria idêntico ao view_internal_analytics
- Sem ganho de granularidade real
- Manutenção extra de seed/grants em engagement_kind_permissions

→ Opção B reuso > Opção A nova action

---

## Decisão (proposta)

### 1. Convert `admin_list_members` para V4 via `view_internal_analytics`

```sql
CREATE OR REPLACE FUNCTION public.admin_list_members(
  p_search text DEFAULT NULL,
  p_tier text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_status text DEFAULT 'active'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- V4 gate (replaces V3 operational_role check)
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- (existing body — query members with filters)
  RETURN ( ... );
END;
$$;
```

### 2. Defense-in-depth REVOKE

```sql
REVOKE EXECUTE ON FUNCTION public.admin_list_members(text, text, integer, text)
FROM PUBLIC, anon;
```

Matches ADR-0026 batch 1 + ADR-0030 precedent.

### 3. NÃO adicionar log_pii_access integration neste ADR

Rationale: admin_list_members retorna múltiplos members em batch (até
todos os 71 ativos). `log_pii_access` espera 1 target_member_id por chamada.
Logging em loop seria caro e ruidoso. Deferred para audit doc backlog
"log_pii_access enhancement carry" (já tracked desde p41).

---

## Implications

### Para a plataforma
- 1 fn V3 a menos. Phase B'' tally bumps 61 → 62 / 246.
- Reuso confirms padrão Opção B já estabelecido (ADR-0027 governance readers).
- Zero novo V4 action — economia de inventário.

### Para members
- Roberto Macêdo gain access — corrige gap V3 onde chapter_board liaison
  observer não tinha acesso.
- Zero would_lose.

### Para path A/B/C optionality
- **Path A (PMI internal)**: positivo — chapter_board liaisons têm acesso operacional aligned com role.
- **Path B (consultoria)**: positivo — multi-tenant consistency.
- **Path C (community-only)**: neutro.

---

## Open Questions (para PM input)

### Q1 — Aceito reuso `view_internal_analytics` ao invés de nova action?

Recomendação: **SIM** (Opção B reuse).

### Q2 — Roberto Macêdo gain (chapter_board × liaison) é intencional?

Roberto tem V4 engagement chapter_board × liaison (organization scope).
ADR-0030 já dá-lhe acesso a analytics. Estender member directory listing
é consistente com role institucional.

Recomendação: **SIM** (intentional gain, role-aligned).

### Q3 — Defer `log_pii_access` integration para Phase Q-D enhancement backlog?

`log_pii_access` espera per-row target_id mas admin_list_members é batch.
Alternativa: adicionar batch helper `log_pii_access_batch` (similar ao
existente para initiative members) — separate ADR.

Recomendação: **SIM** (defer).

### Q4 — Implementation timing

ADR está em `Proposed`. Implementação requer:
- 1 migration conversão de gate (CREATE OR REPLACE)
- 1 migration REVOKE FROM anon (defense-in-depth)
- 1 audit doc update

Estimativa: ~30 min (mais simples que ADR-0030 — só 1 fn, no new action).

Recomendação: **p66 mesmo**.

---

## Status / Next Action

- [x] PM ratifica ADR (Q1=SIM / Q2=SIM / Q3=SIM / Q4=p66) — 2026-04-26 p66
- [x] Migration conversão de gate — `20260427121244`
- [x] Migration REVOKE FROM anon — `20260427121249`
- [x] Audit doc update — Phase B'' tally bumps (61 → 62 / 246, ~25.2%)
- [x] Status ADR → `Accepted`

**Bloqueador**: nenhum.

### Outcome (post-apply)

- 1 fn V3 convertida (admin_list_members) reusando action existente.
- Privilege expansion: legacy 9 → V4 10 (Roberto Macêdo gain via
  chapter_board × liaison engagement — corrige gap V3).
- Zero would_lose.
- Defense-in-depth REVOKE FROM anon aplicado.
- pg_policy precondition (Q-D charter): zero RLS refs verified.
- Phase B'' tally: 61 → 62 / 246 (~25.2%).
