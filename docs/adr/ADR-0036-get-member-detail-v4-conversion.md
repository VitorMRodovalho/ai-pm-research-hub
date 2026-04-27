# ADR-0036: `get_member_detail` V4 conversion — Opção B reuse `view_internal_analytics`

- Status: **Accepted** (2026-04-27 p66 — PM rubber-stamp Q1=SIM / Q2=SIM / Q3=SIM / Q4=p66)
- Data: 2026-04-27 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track — fecha 1 fn V3 (`get_member_detail`)
  via reuso de action V4 existente
- Implementation:
  - Migration `20260427135518_adr_0036_get_member_detail_v4_view_internal_analytics.sql`
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (V4 auth pattern),
  ADR-0030 (`view_internal_analytics` action — being reused),
  ADR-0031 (admin_list_members — sister Opção B reuse, same ladder),
  ADR-0034 (drift correction precedent — designation-without-engagement loss accepted)
- **Retroactive ADR file** (created p67 2026-04-27) — preenche gap detectado pelo
  Platform Guardian no end-of-session p67. Migration foi shipped em p66 com
  COMMENT preservando intent + commit message `689469b feat(p66): ADR-0036
  get_member_detail V4 — view_internal_analytics reuse`, mas o arquivo ADR
  não havia sido criado.

---

## Contexto

Sequência de ADR-0030 (`view_internal_analytics`) e ADR-0031
(`admin_list_members` Opção B reuse). Próxima fn V3 do tipo "admin reader
sobre member" identificada no p66 final round. Mesmo ladder e audiência
de ADR-0031.

### A função afetada

**`get_member_detail(p_member_id uuid)`** — member detail page reader.
Retorna jsonb com perfil completo: nome + email + photo + operational_role
+ designations + flags + chapter + tribe + auth fields + cycle status.

Caller: `src/pages/admin/members/[id].astro` (member detail page,
admin tier).

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

V3 set: **9 active members** (idêntico ao admin_list_members) — Vitor SA + 8
com operational_role nas roles admin/governance.

### Por que reuso (Opção B) ao invés de nova action

Idêntica análise de ADR-0031 — `view_internal_analytics` (ADR-0030) é
match excelente para audiência admin readers + chapter governance.

| Action | Audience match? | Privilege expansion vs V3 |
|---|---|---|
| `manage_platform` | volunteer×{co_gp,manager,deputy_manager} | NÃO — perde sponsor + chapter_liaison + chapter_board (4 vs 9) |
| `manage_member` | manage_platform + initiative leaders | NÃO — só 2 active members têm hoje |
| **`view_internal_analytics`** | volunteer×{co_gp,manager,deputy_manager} + sponsor + chapter_board×liaison | ✅ **Match excelente** — legacy 9 → V4 10 (+Roberto, igual ADR-0031) |
| `view_pii` | broader — initiative leaders | Broad demais para member directory detail |

### Privilege expansion (verified pre-apply)

```
legacy (V3) = 9: Vitor SA, Ana, Fabricio, Felipe, Francisca, Ivan,
                  Márcio, Matheus, Rogério
v4 (view_internal_analytics) = 10: legacy 9 + Roberto Macêdo
would_gain = [Roberto Macêdo] (chapter_board × liaison engagement)
would_lose = []
```

**Roberto context**: idêntico ao ADR-0031 — chapter_board × liaison
engagement legítimo, V3 não cobria por usar operational_role string match.
Member detail é parte da mesma surface admin que admin_list_members; é
consistente que Roberto tenha acesso a ambos.

### Custo de não fazer

- 1 fn V3 permanece. Phase B'' tally trava.
- Inconsistência: ADR-0031 admin_list_members já dá acesso a Roberto;
  get_member_detail (clicar em row da lista) bloqueia. UX broken.

---

## Decisão

### 1. Convert `get_member_detail` para V4 via `view_internal_analytics`

```sql
CREATE OR REPLACE FUNCTION public.get_member_detail(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- V4 gate (Opção B reuse view_internal_analytics — ADR-0031 precedent)
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  -- (existing body — query members + engagements + cert summary)
  RETURN ( ... );
END;
$$;
```

### 2. Defense-in-depth REVOKE (já existia anteriormente; preservado)

ACL pré-existente já era `postgres,authenticated,service_role` (anon
REVOKED em migration anterior). Sem REVOKE adicional necessário neste ADR.

### 3. NÃO adicionar log_pii_access integration neste ADR

Mesma rationale de ADR-0031 — get_member_detail retorna 1 member
(target_member_id direto), portanto poderia logar trivialmente. Mas
foi deferido para audit doc backlog "log_pii_access enhancement carry"
(tracked desde p41) para consistência com admin_list_members.

---

## Implications

### Para a plataforma
- 1 fn V3 a menos. Phase B'' tally bumps 78 → 79 / 246.
- Sister fn de admin_list_members (ADR-0031). Subsystem admin member
  detail consistency restaurado.
- Zero novo V4 action.

### Para members
- Roberto Macêdo gain access — idêntico ao ADR-0031, corrige inconsistência.
- Zero would_lose.

### Para path A/B/C optionality
- **Path A (PMI internal)**: positivo — chapter_board liaisons têm acesso
  consistente entre lista e detalhe.
- **Path B (consultoria)**: positivo — multi-tenant consistency.
- **Path C (community-only)**: neutro.

---

## Open Questions (decididas pelo PM em p66)

### Q1 — Aceito reuso `view_internal_analytics` ao invés de nova action?

PM **SIM** — Opção B reuse, mesma ladder de ADR-0031.

### Q2 — Roberto Macêdo gain (chapter_board × liaison) é intencional?

PM **SIM** — consistente com ADR-0031, role-aligned.

### Q3 — Defer `log_pii_access` integration para enhancement backlog?

PM **SIM** — consistente com ADR-0031 deferral.

### Q4 — Implementation timing

PM **p66** — junto com restante do final round.

---

## Status / Next Action

- [x] PM ratifica ADR (Q1=SIM / Q2=SIM / Q3=SIM / Q4=p66) — 2026-04-27 p66
- [x] Migration conversão de gate — `20260427135518`
- [x] ACL já estava com anon REVOKED (carry de migration anterior)
- [x] Audit doc update — Phase B'' tally bumps (78 → 79 / 246, ~32.1%)
- [x] Status ADR → `Accepted`
- [x] **ADR file criado retroativamente em p67** (2026-04-27) preenchendo
  gap detectado pelo Platform Guardian.

**Bloqueador**: nenhum.

### Outcome (post-apply)

- 1 fn V3 convertida (get_member_detail) reusando action existente.
- Privilege expansion: legacy 9 → V4 10 (Roberto Macêdo gain via
  chapter_board × liaison engagement — corrige inconsistência com ADR-0031).
- Zero would_lose.
- pg_policy precondition (Q-D charter): zero RLS refs verified.
- Phase B'' tally: 78 → 79 / 246 (~32.1%).
- Member detail page consistent with admin_list_members (Roberto gains access in both).
