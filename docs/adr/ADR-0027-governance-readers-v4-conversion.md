# ADR-0027: Governance Readers V4 Conversion — Phase B'' (3 fns)

- Status: **Proposed** (PM ratify required)
- Data: 2026-04-26 (p59)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track (3 of N) — closes 3 V3-gated functions

---

## Contexto

Sequência de ADR-0025 (`manage_finance`) e ADR-0026 (`manage_comms`).
Fecha mais 3 das 11 funções V3-gated documentadas como out-of-scope V3
no audit doc Q-D track.

### As 3 funções afetadas

| Função | Operação | V3 gate (substancial) |
|---|---|---|
| `get_change_requests(p_status, p_cr_type)` | READ change_requests + filter por role | "not observer" + role-based row filter (admin tier sees all; others see só approved/implemented) |
| `get_governance_dashboard()` | READ aggregated stats + my_vote | Personaliza para sponsor (can_approve = is_sponsor OR is_superadmin) |
| `get_governance_documents(p_doc_type)` | READ governance_documents + filter signatories | Authenticated + admin tier vê signatários (campo nullado para outros) |

**Pattern comum**: cada fn é **read** com **filtragem interna**
baseada em authority do caller. Não são writes — não fazem sentido
sob action `manage_*`.

### Por que estes 3 são diferentes de manage_finance / manage_comms

- ADR-0025 e ADR-0026 são writes admin-only (DELETE/UPDATE/upsert)
  → ação `manage_*` faz sentido
- ADR-0027 são reads visíveis a quase todos os members, com
  enriquecimento condicional para admin tier → ação `manage_*` é
  semanticamente errada

Existem 3 caminhos possíveis para V4 conversion:

### Opção A — Nova ação `view_governance`

```sql
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
SELECT kind, role, 'view_governance', scope
FROM public.engagement_kind_permissions
WHERE action = 'write'  -- inherit from any existing 'write' grant
ON CONFLICT (kind, role, action) DO NOTHING;
```

Outer gate: `can_by_member('view_governance')`. Inner admin filter:
`can_by_member('manage_platform')` (existing) para signatories +
sensitive fields.

**Pro**: granularidade — auditoria pode responder "quem pode ler
governança institucional?" especificamente.
**Con**: introduz nova action que essencialmente todos os members têm
(porque governança é transparente). Action quase universal — pouco
discriminativo.

### Opção B — Reusar `rls_is_member()` (no new action)

Outer gate: `rls_is_member()` (qualquer engagement ativo authoritative).
Inner admin filter: `can_by_member('manage_platform')` para sensitive
fields.

```sql
DECLARE
  v_caller_member_id uuid;
  v_can_manage boolean;
BEGIN
  IF NOT public.rls_is_member() THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  v_can_manage := public.can_by_member(v_caller_member_id, 'manage_platform');

  -- ... (existing query, use v_can_manage in CASE expressions
  --      to filter admin-only fields like signatories)
END;
```

**Pro**: zero novas actions, máxima reuse de infraestrutura V4
existente.
**Con**: assume que ANY member tem direito a ler governance docs
(verdade hoje, mas semântica não-explícita).

### Opção C — Drop SECDEF + use SECURITY INVOKER + RLS policies

Convert as 3 fns para `SECURITY INVOKER`. Definir RLS policies
explícitas em `change_requests` + `governance_documents` que
filtram por authority do caller.

**Pro**: V4 puro — autoridade no policy layer, fns são apenas queries.
**Con**: maior refactor (mover lógica de 3 fns para policies + adjust
internal admin filtering em SQL puro). Risco de regressão.

---

## Decisão (proposta)

**Recomendação: Opção B** (reuse `rls_is_member` + existing `manage_platform`).

Justificativas:
1. Governança institucional é transparent-by-design. Não há valor
   em `view_governance` separar de `is_member`.
2. Custo zero de novas actions (reduz superfície de manutenção).
3. Admin-tier filtering preserved via `manage_platform` (já em V4).
4. Refactor mínimo — apenas substituição de gate, não re-arquitetura.

Opção A pode ser revisitada depois se vier necessidade de gate
specific para non-PM-non-superadmin "governance reader" role.

Opção C é overkill para 3 fns.

### Implementação proposta (cada uma das 3 fns)

#### `get_change_requests(p_status, p_cr_type)`

```sql
DECLARE
  v_caller_member_id uuid;
  v_can_manage boolean;
  v_result jsonb;
BEGIN
  IF NOT public.rls_is_member() THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT m.id INTO v_caller_member_id
  FROM members m WHERE m.auth_id = auth.uid();
  v_can_manage := public.can_by_member(v_caller_member_id, 'manage_platform');

  SELECT jsonb_agg(cr_row ORDER BY cr_row->>'created_at' DESC) INTO v_result FROM (
    SELECT jsonb_build_object(
      -- ... (existing fields, no change)
    ) AS cr_row FROM change_requests cr LEFT JOIN members rm ON rm.id=cr.requested_by
    WHERE (p_status IS NULL OR cr.status=p_status)
      AND (p_cr_type IS NULL OR cr.cr_type=p_cr_type)
      AND (
        v_can_manage  -- admin tier sees all
        OR cr.status IN ('approved', 'implemented')  -- public-by-design
      )
  ) sub;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
```

Outer guard: `rls_is_member()` instead of "not observer + superadmin".
Inner filter: `v_can_manage` instead of mixed role check.

#### `get_governance_dashboard()`

```sql
DECLARE
  v_member_id uuid;
  v_member_name text;
  v_can_approve boolean;
  -- ...
BEGIN
  IF NOT public.rls_is_member() THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  SELECT id, name INTO v_member_id, v_member_name
  FROM members WHERE auth_id = auth.uid();

  -- can_approve: V4 sponsor authority OR superadmin
  -- (ratification gate is sponsor-specific; mantém semantica)
  v_can_approve := EXISTS (
    SELECT 1 FROM auth_engagements ae
    WHERE ae.person_id = (SELECT person_id FROM members WHERE id = v_member_id)
      AND ae.kind = 'sponsor' AND ae.is_authoritative = true
  ) OR public.can_by_member(v_member_id, 'manage_platform');

  -- ... (existing aggregation, use can_approve in result)
END;
```

#### `get_governance_documents(p_doc_type)`

```sql
DECLARE
  v_caller_member_id uuid;
  v_can_manage boolean;
  v_result jsonb;
BEGIN
  IF NOT public.rls_is_member() THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  SELECT m.id INTO v_caller_member_id FROM members m WHERE m.auth_id = auth.uid();
  v_can_manage := public.can_by_member(v_caller_member_id, 'manage_platform');

  SELECT jsonb_agg(jsonb_build_object(
    -- ... (existing fields)
    'signatories', CASE
      WHEN v_can_manage THEN gd.signatories
      ELSE NULL
    END
  ) ORDER BY gd.status ASC, gd.signed_at DESC) INTO v_result
  FROM governance_documents gd
  WHERE (p_doc_type IS NULL OR gd.doc_type = p_doc_type)
    AND (
      gd.status = 'active'
      OR (gd.status = 'draft' AND v_can_manage)
    );

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
```

### Privilege expansion safety check

```sql
-- Para cada uma das 3 fns:
WITH legacy AS (
  SELECT id FROM members
  WHERE is_active = true
    AND (
      -- get_change_requests: not observer + (admin tier OR sees approved)
      operational_role != 'observer' OR is_superadmin = true
    )
),
v4 AS (
  SELECT id FROM members
  WHERE is_active = true
    AND public.rls_is_member()  -- needs members.auth_id context, simulate
)
SELECT
  (SELECT count(*) FROM legacy) AS legacy_count,
  (SELECT count(*) FROM v4) AS v4_count;
```

**Esperado**: `would_lose ⊆ {legacy observer accounts}` que migrarem
de "observer" para "without active engagement" ganham mesmo nível
(zero acesso). Diferença esperada: `0`.

---

## Implications

### Para a plataforma

- **3 fns V3 a menos** no backlog Phase B''.
- **Reuse pattern**: `rls_is_member` + `manage_platform` é o padrão
  recomendado para member-tier readers com admin-shape filtering.
- **Nenhuma nova action**: superfície V4 de actions permanece
  enxuta (8 actions + manage_finance + manage_comms = 10 total).

### Para members

- Observer accounts perdem acesso a `get_change_requests` que
  retornava "approved/implemented" antes — em V4, observer não
  tem engagement authoritative ⇒ rls_is_member() = false ⇒ no
  access.
  
  **Mitigation**: se PM quiser preservar acesso de observers a
  governance pública, criar action `view_governance_public` que
  qualquer non-anonymous user tenha. Mas histórico mostra que
  observers raramente acessam essa fn.

### Para path A/B/C optionality

- **Path A**: positivo — limpa V3 cleanup
- **Path B**: positivo — modelo V4 puro
- **Path C**: neutro — observers não são target audience para
  governance UI

---

## Open Questions (para PM input)

### Q1 — Opção A, B ou C?

A proposta é Opção B (reuse). PM pode preferir:
- A se vê valor em separar `view_governance` action
- C se prefere refactor profundo para SECURITY INVOKER + RLS policies

**PM decide**: A, B, ou C.

### Q2 — Observers devem manter acesso a governance pública?

V3 atual permitia que observers (member_status='observer') vissem
"approved/implemented" CRs. V4 com `rls_is_member()` exclui observers
porque não têm engagement authoritative.

Se PM quer preservar:
- Criar `view_governance_public` action (qualquer não-anônimo tem)
- Ou verificar separadamente `EXISTS member WHERE auth_id = auth.uid()`

**PM decide**: preservar OR aceitar mudança (recomendação:
aceitar — observers não usam governance).

### Q3 — Deprecate ou keep `get_governance_dashboard` separação sponsor?

Hoje a fn marca `can_approve = is_sponsor OR is_superadmin`. Em V4,
sponsor é seu próprio kind — fica explícito. O code mostra como.

Mas: alguma fn no futuro pode querer "can ratify governance" como
ação separada de "manage_platform". Vale criar `ratify_governance`
action?

**PM decide**: criar agora OU adiar.

### Q4 — Implementation timing

- 3 migrations conversão de gate (uma por fn, DROP+CREATE)
- 3 contract tests (rpc-v4-auth coverage)
- 1 audit doc update
- 1 NOTIFY pgrst

Estimativa: ~3h (mais simples que ADR-0025 porque é refactor de gate
sem grants novos se Opção B aceita).

**PM decide**: ratify + schedule p60 ou p61.

---

## Status / Next Action

- [ ] PM ratifica ADR (responde Q1-Q4)
- [ ] Decisão Q1 — drives toda a abordagem
- [ ] 3 migrations conversão de gate (DROP+CREATE per fn)
- [ ] 3 contract tests
- [ ] Audit doc update — Phase B'' tally bumps
- [ ] Status ADR → `Accepted`

**Bloqueador atual**: PM input em Q1-Q4.

**Cross-references**:
- ADR-0007 (V4 authority model)
- ADR-0011 (V4 auth pattern RPCs+MCP)
- ADR-0025 (manage_finance), ADR-0026 (manage_comms) — sister Phase B'' ADRs
- ADR-0016 (IP ratification governance model — quem ratifica governance)
- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` Phase B'' section
- `docs/council/2026-04-26-tracks-qd-r-security-hardening-decision.md`
