# ADR-0037: Chapter needs + Org chart V4 conversion — `view_internal_analytics` reuse + Path Y chapter_board preservation

- Status: **Proposed** (2026-04-27 p67 — aguarda PM rubber-stamp Q1=? / Q2=? / Q3=? / Q4=?)
- Data: 2026-04-27 (p67)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion (2 fns) — `get_chapter_needs` (Path Y) +
  `get_org_chart` (pure Opção B)
- Implementation:
  - Migration `20260427143000_adr_0037_chapter_needs_and_org_chart_v4.sql`
  - Migration `20260427143005_adr_0037_revoke_anon.sql`
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (V4 auth pattern),
  ADR-0030 (`view_internal_analytics` action — being reused),
  ADR-0031/0036 (Opção B reuse precedents — admin readers via
  view_internal_analytics), ADR-0034/0035 (drift correction precedent —
  designation-without-engagement loss accepted)

---

## Contexto

Sequência de ADR-0030/0036 fechando mais 2 fns V3-gated do tipo "admin reader"
identificadas em discovery p67 next-tier. Ambas reusam
`view_internal_analytics` (zero novo V4 action no inventário) com diferença
de Path Y para `get_chapter_needs`.

### As funções afetadas

#### `get_chapter_needs(p_chapter text)` — chapter need backlog reader

Lista até 50 needs submetidos via `submit_chapter_need`, scoped por chapter.

V3 ladder atual:
```sql
IF v_member.is_superadmin OR v_member.operational_role IN ('manager', 'deputy_manager') THEN
  -- broad: free p_chapter
ELSIF v_member.designations && ARRAY['chapter_board', 'sponsor', 'chapter_liaison']::text[] THEN
  v_chapter := v_member.chapter;  -- own chapter only
ELSE
  RETURN;  -- no access
END IF;
```

Caller: `nucleo-mcp` MCP tool `get_chapter_needs`.

**V3 set**: 14 active members (SA + manager/deputy_manager + chapter_board /
sponsor / chapter_liaison designations).

#### `get_org_chart()` — platform structure reader

Retorna jsonb com superadmins, tiers (1/2/3/5/7/8), designations buckets,
`stakeholder_auth_gap` count, total_active count.

V3 ladder:
```sql
IF v_caller.is_superadmin IS NOT TRUE
   AND v_caller.operational_role NOT IN ('manager','sponsor','chapter_liaison','tribe_leader')
   AND NOT (v_caller.designations && ARRAY['deputy_manager','curator'])
THEN
  RETURN jsonb_build_object('error', 'Unauthorized');
END IF;
```

Caller: `src/pages/admin/governance-v2.astro`.

**V3 set**: 17 active members (SA + manager/sponsor/chapter_liaison/tribe_leader
operational_roles + deputy_manager/curator designations).

### Por que reuso (Opção B) ao invés de novas actions

Análise das 9 actions V4 + ADR-0030 view_internal_analytics:

Para `get_chapter_needs`:
- Audience: SA + manager + deputy_manager (broad) + chapter_board + sponsor + chapter_liaison (chapter-bound)
- Best match: split-path com `manage_platform` (broad) + `view_internal_analytics` (chapter-bound)
- Catalog gap: `chapter_board × board_member` tem `view_pii` mas NÃO `view_internal_analytics`
  (apenas `chapter_board × liaison` tem). Sem Path Y, 3 active board_member (Emanuele,
  Emanoela, Lorena) perderiam acesso a chapter needs do próprio chapter — **regressão
  operacional não-intencional** (board_members são quem fulfilm needs no chapter).

Para `get_org_chart`:
- Audience: SA + manager + sponsor + chapter_liaison + tribe_leader + deputy_manager + curator
- Best match: `view_internal_analytics` (catalog: SA + manager + co_gp + deputy_manager + sponsor + chapter_liaison + chapter_board×liaison)
- 7 drift losses: 6 tribe_leaders (volunteer × leader, initiative-scope) + Sarah curator
  (designation deprecated, no V4 engagement role for curator)
- Drift losses são **exatamente o padrão precedente 8×** (ADR-0030/0034: tribe_leaders +
  Sarah curator). PM rubber-stamp esperado.

### Privilege expansion (verified pre-apply)

#### `get_chapter_needs` (com Path Y chapter_board engagement preservation):

```
legacy (V3)  = 14 members
v4 + Path Y  = 13 members
would_gain   = (none)
would_lose   = [João Uzejka Dos Santos]
```

João context: `operational_role=researcher`, `designations=[chapter_liaison]`,
engagements `volunteer × researcher` only. V3 grants via `chapter_liaison`
designation; V4 catalog requires `chapter_board × liaison` engagement (which
João doesn't have). **Same drift as ADR-0030/0034 João loss** — PM-precedented.

Path Y (chapter_board × any role engagement) preserves 3 board_member members
(Emanuele Melo, Emanoela Kerkhoff, Lorena Souza — chapter_board × board_member
engagements) for own-chapter access only. Zero would_gain for Path Y.

#### `get_org_chart`:

```
legacy (V3)  = 17 members
v4 (pure)    = 10 members
would_gain   = (none)
would_lose   = [Débora Moura, Ana Carla Cavalcante, Hayala Curto, Jefferson Pinto,
                Fernando Maquiaveli, Marcos Antunes Klemz, Sarah Faria]
```

Drift composition:
- 6 tribe_leaders (Ana Carla, Débora, Hayala, Jefferson, Fernando, Marcos) —
  `operational_role=tribe_leader`, engagement `volunteer × leader` (initiative
  scope). V4 `view_internal_analytics` is organization-scope; tribe_leaders
  don't qualify. **Same drift as ADR-0034 (6 tribe_leaders for partner
  attachments)** — PM-precedented.
- Sarah Faria — `designations=[ambassador, founder, curator]`. No V4 engagement
  for curator role; her `committee_*`/`workgroup_*`/`ambassador` engagements
  don't grant `view_internal_analytics`. **Same drift as ADR-0034** —
  PM-precedented.

### pg_policy precondition (Q-D charter mandatory)

Word-boundary regex `\m` scan on `pg_policy.polqual` + `polwithcheck` for both
fns: **zero references**. Safe to proceed without RLS hotpath risk.

---

## Decisão (proposta)

### 1. `get_chapter_needs` — 3-path V4 ladder com Path Y

```sql
CREATE OR REPLACE FUNCTION public.get_chapter_needs(p_chapter text DEFAULT NULL)
RETURNS TABLE(...)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_chapter text;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid() LIMIT 1;

  IF v_caller_id IS NULL THEN RETURN; END IF;

  -- Path A (broad): manager + co_gp + deputy_manager
  IF public.can_by_member(v_caller_id, 'manage_platform') THEN
    v_chapter := COALESCE(p_chapter, v_caller_chapter);
  -- Path B (chapter-bound): sponsor + chapter_liaison + chapter_board×liaison
  ELSIF public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    v_chapter := v_caller_chapter;
  -- Path Y (chapter_board preservation): any chapter_board engagement, own chapter
  ELSIF EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  ) THEN
    v_chapter := v_caller_chapter;
  ELSE
    RETURN;
  END IF;

  RETURN QUERY ... -- existing body
END;
$$;
```

### 2. `get_org_chart` — pure V4 reuse view_internal_analytics

```sql
CREATE OR REPLACE FUNCTION public.get_org_chart()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  SELECT jsonb_build_object(...) INTO v_result;  -- existing body
  RETURN v_result;
END;
$$;
```

### 3. Defense-in-depth REVOKE FROM PUBLIC, anon

```sql
REVOKE EXECUTE ON FUNCTION public.get_chapter_needs(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_org_chart() FROM PUBLIC, anon;
```

Matches ADR-0030/0031/0034/0035/0036 precedent — defense-in-depth para SECDEF
external-callable.

---

## Implications

### Para a plataforma
- 2 fns adicionais V4. Phase B'' tally bumps 79 → 81 / 246 (~32.9%).
- Zero novo V4 action — full reuse view_internal_analytics + manage_platform.
- Path Y pattern formalized (auth_engagements direct check para
  resource-class preservation quando catalog não cobre sub-role).
- pg_policy precondition verificado (zero refs) — sem regressão RLS.

### Para members (drift consolidado)
- **João Uzejka** (chapter_liaison designation drift) — perde get_chapter_needs.
  Mesmo drift de ADR-0030/0034 (PM-precedented).
- **6 tribe_leaders + Sarah curator** — perdem get_org_chart. Mesmo drift de
  ADR-0034 (PM-precedented).
- **3 chapter_board × board_member members** (Emanuele, Emanoela, Lorena) —
  PRESERVAM acesso a get_chapter_needs via Path Y. Operacionalmente correto
  (board_members fulfilm chapter needs).
- **Roberto Macêdo** (chapter_board × liaison) — gain implícito via ADR-0030 já
  ratificado. Aplicado a get_chapter_needs (analytics-tier reader sister fn).

### Para path A/B/C optionality
- Path A (PMI internal): positivo — drift correction continua aligned com
  V4 catalog design (chapter_board × liaison institutional, board_member
  operational).
- Path B (consultoria): positivo — multi-tenant consistency preservada.
- Path C (community-only): neutro.

---

## Open Questions (para PM input)

### Q1 — Aceito Opção B reuse `view_internal_analytics` para ambas fns?

Recomendação: **SIM** (ADR-0030/0031/0036 precedent extension).

### Q2 — Path Y para `get_chapter_needs` é warranted?

Path Y preserva 3 chapter_board × board_member members para acesso ao próprio
chapter — operacionalmente legítimo (board members são quem opera chapter needs
locally). Sem Path Y, board_members perderiam acesso a chapter needs do próprio
chapter — regressão real. Com Path Y, drift = 1 (João) ao invés de 4.

Recomendação: **SIM** (Path Y aceito; padrão para futuras conversões com
chapter_board sub-role mismatch).

### Q3 — `get_org_chart` 7 drift losses (6 tribe_leaders + Sarah curator) aceitos?

Mesmo padrão precedent 8× (ADR-0030/0034). tribe_leaders são
volunteer×leader (initiative scope), não org-scope analytics audience. Sarah
curator designation já não tem V4 engagement role.

Recomendação: **SIM** (PM-precedented drift correction).

### Q4 — Implementation timing

ADR está em `Proposed`. Implementação requer:
- 1 migration conversão (2 fns)
- 1 migration REVOKE FROM anon
- 1 audit doc update

Estimativa: ~30 min.

Recomendação: **p67 mesmo**.

---

## Status / Next Action

- [ ] PM ratifica ADR (Q1 / Q2 / Q3 / Q4)
- [ ] Migration conversão — `20260427143000`
- [ ] Migration REVOKE FROM anon — `20260427143005`
- [ ] Audit doc update — Phase B'' tally bumps (79 → 81 / 246, ~32.9%)
- [ ] Status ADR → `Accepted`

**Bloqueador**: nenhum (PM rubber-stamp expected).

### Outcome (post-apply esperado)

- 2 fns V3 convertidas (get_chapter_needs + get_org_chart) reusando action existente.
- Privilege expansion totals:
  - get_chapter_needs: legacy 14 → V4+Path Y 13 (drift 1: João, precedented).
  - get_org_chart: legacy 17 → V4 10 (drift 7: 6 tribe_leaders + Sarah, precedented).
- Zero would_gain (Roberto já aplicado em ADR-0030).
- Zero novo V4 action — full reuse `view_internal_analytics` + `manage_platform`.
- Defense-in-depth REVOKE FROM anon aplicado.
- pg_policy precondition (Q-D charter): zero RLS refs verificados.
- Path Y pattern formalized para chapter_board sub-role preservation.
- Phase B'' tally: 79 → 81 / 246 (~32.9%).
