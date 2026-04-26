# ADR-0025: New V4 Action `manage_finance` — Phase B'' Conversion

- Status: **Proposed** (PM ratify required)
- Data: 2026-04-26 (p59)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track (1 of N) — closes 4 V3-gated functions

---

## Contexto

Phase Q-D (p55→p59) hardenizou 137 funções SECDEF via REVOKE + per-fn
classification, e Phase B' (p52→p54) converteu 13 funções V3 → V4 quando
o caso era "clean" (mesma autoridade, só refactor de gate). Mas existem
**11 funções V3-gated documentadas como out-of-scope V3 → Phase B''**
porque exigem **novas V4 actions** que ainda não existem em
`engagement_kind_permissions`.

Esta ADR propõe a **primeira nova V4 action** após Phase Q-D: `manage_finance`.

### As 4 funções afetadas

Todas as 4 usam gate idêntico V3:

```sql
IF NOT EXISTS (
  SELECT 1 FROM public.members WHERE auth_id = v_caller_id
  AND (is_superadmin = true OR operational_role = 'manager')
) THEN
  RAISE EXCEPTION 'Only managers/superadmins can ...';
END IF;
```

| Função | Operação | Tabela alvo |
|---|---|---|
| `delete_cost_entry(uuid)` | DELETE | `cost_entries` |
| `delete_revenue_entry(uuid)` | DELETE | `revenue_entries` |
| `update_kpi_target(uuid, numeric, numeric, text)` | UPDATE | `annual_kpi_targets` |
| `update_sustainability_kpi(uuid, numeric, numeric, text)` | UPDATE | `sustainability_kpi_targets` |

Todas operam sobre dados financeiros institucionais (custos, receitas,
metas KPI anuais, metas de sustentabilidade). Risco: erro ou má-fé na
edição → impacto direto em prestação de contas + relatórios para sponsors
+ auditoria PMI.

### Por que precisa de nova action (vs reutilizar `manage_platform`)

Análise das 8 actions existentes:

| Action | Semântica | Cabe para finance? |
|---|---|---|
| `manage_platform` | superadmin operations (admin_*) | NÃO — finance é operação rotineira do GP, não admin global |
| `manage_member` | member lifecycle (offboard, anonymize) | NÃO — escopo errado |
| `manage_event` | event ops | NÃO — escopo errado |
| `manage_partner` | partner CRUD | NÃO — escopo errado |
| `promote` | role transitions | NÃO — escopo errado |
| `view_pii` | PII access | NÃO — finance pode ter PII (cost.paid_to_member) mas não é o eixo |
| `write` | tribe-scoped writes | NÃO — finance é cross-tribe (institucional) |
| `write_board` | board-scoped writes | NÃO — escopo errado |

Reutilizar `manage_platform` seria semanticamente impreciso. Hoje a V3
gate explicitamente diferencia "GP que cuida de finanças" do "superadmin
que opera plataforma" — mesmo que ambos sejam autorizados, o caller
chain semântico precisa preservar a diferença para auditoria.

Auditoria PMI futura precisa poder responder: "quem está autorizado a
mexer em finanças?" sem confundir com "quem é superadmin de plataforma".

### Custo de não fazer

- 4 funções continuam V3 (operational_role check) — incompatíveis com
  V4 engagement-derived authority (ADR-0007).
- Phase B'' permanece com 11+ fns documentadas mas sem path de closure.
- Sponsor briefing pode dizer "Q-D 100% closed" mas não pode dizer
  "todas as escritas têm V4 authority gate".

---

## Decisão (proposta)

### 1. Adicionar nova V4 action `manage_finance`

> **Correção p59 pós-discovery**: kinds reais em
> `engagement_kind_permissions` são `volunteer` + `sponsor` +
> `chapter_board` + `committee_member` + `committee_coordinator` +
> `study_group_*` + `workgroup_*`. NÃO existe kind `committee`.
> A primeira versão deste ADR usou `committee` por engano; revisado
> para usar kinds reais.

```sql
-- Migration target: 20260427xxxxxx_add_v4_action_manage_finance.sql

INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  -- GP and management positions (kind=volunteer per real schema)
  ('volunteer', 'co_gp',          'manage_finance', 'organization'),
  ('volunteer', 'manager',        'manage_finance', 'organization'),
  ('volunteer', 'deputy_manager', 'manage_finance', 'organization'),
  -- Sponsors get read+manage on finance for accountability
  -- (sponsor é seu próprio kind, role único 'sponsor')
  ('sponsor',   'sponsor',        'manage_finance', 'organization')
  ON CONFLICT (kind, role, action) DO NOTHING;
```

### 2. Converter as 4 funções para usar `can_by_member('manage_finance')`

**Padrão de gate (substitui V3)**:

```sql
DECLARE
  v_caller_member_id uuid;
BEGIN
  -- Resolve caller member_id from auth.uid()
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authenticated member required';
  END IF;

  -- V4 gate
  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'Insufficient authority: manage_finance required';
  END IF;

  -- (existing operation: DELETE/UPDATE...)
END;
```

### 3. Privilege expansion safety check (per Phase B' protocol)

Antes de aplicar, validar que conversão não expande privilégios:

```sql
-- legacy_count: members atualmente autorizados via V3
WITH legacy AS (
  SELECT id FROM members
  WHERE is_active = true
    AND (is_superadmin = true OR operational_role = 'manager')
),
v4 AS (
  SELECT m.id FROM members m
  WHERE m.is_active = true
    AND public.can_by_member(m.id, 'manage_finance')
)
SELECT
  (SELECT count(*) FROM legacy) AS legacy_count,
  (SELECT count(*) FROM v4) AS v4_count,
  (SELECT count(*) FROM v4 EXCEPT SELECT count(*) FROM legacy) AS would_gain;
```

Aceito: zero diferença OU diferença explicável (e.g., +1 se um sponsor
ativo agora ganha acesso que não tinha via V3 — documentar no commit).

### 4. Treatment matrix update no audit doc

Após conversão, audit doc adiciona linha à treatment matrix Phase B':

| Pattern | Symptom | Treatment | Track |
|---|---|---|---|
| V3 gate financeiro (cost/revenue/KPI/sustainability) | `is_superadmin OR operational_role='manager'` em fn de finanças | Replace gate with `can_by_member('manage_finance')` + INSERT 4 rows em `engagement_kind_permissions` | Phase B'' (ADR-0025) |

---

## Implications

### Para a plataforma

- **Audit trail mais granular**: PMI auditoria pode responder "quem
  pode editar finanças?" sem confundir com "quem é superadmin?".
- **Engagement model purity**: 4 fns saem do bucket V3 → 4 a menos
  para Phase B'' backlog.
- **Sponsor accountability**: sponsors ganham `manage_finance` —
  permite `delete_revenue_entry` em emergência (e.g., entrada
  contabilizada erroneamente). Precisa PM confirm (next section).

### Para sponsors / PMs futuros

- `manage_finance` permission inclui sponsor — significa que sponsors
  podem editar metas KPI sem precisar pedir ao PM.
- Audit log via `pii_access_log` ou similar registra cada operação
  (já existe via gen audit triggers).

### Para path A/B/C optionality

- **Path A (PMI institutional)**: positivo — granularidade financeira
  é valor para auditor PMI Brasil.
- **Path B (commercial)**: positivo — multi-tenant SaaS pode usar
  `manage_finance` para diferenciar billing admin de tech admin.
- **Path C (community)**: neutro — ação não tem visibilidade pública.

---

## Open Questions (para PM input)

### Q1 — Sponsors devem ter `manage_finance`?

A proposta inclui sponsors. Justificativa:
- Sponsors têm responsabilidade institucional sobre prestação de contas
- Em emergência, sponsor pode precisar corrigir entrada errada sem GP

Alternativa conservadora: NÃO incluir sponsors. Apenas GP/co_gp/deputy
têm `manage_finance`. Sponsor solicita ao GP.

**PM decide**: incluir sponsors OU restringir a apenas GP-tier.

### Q2 — `chapter_liaison` deve ter `manage_finance` por chapter scope?

Cada chapter pode ter custos/receitas localizados. `chapter_liaison` poderia
ter `manage_finance` com `scope='chapter'` para gerenciar entradas do seu
chapter.

Custo: complica o gate (precisa filtrar por `chapter_id`). Tabelas
atuais (`cost_entries`, `revenue_entries`) podem não ter `chapter_id`
column ainda.

**PM decide**: incluir agora (com scope work) OU adiar para ADR posterior.

### Q3 — Gate adicional para `view_finance`?

A análise atual cobre apenas writes (delete, update). Reads (`get_cost_entries`,
`get_revenue_entries`, `get_sustainability_dashboard`) hoje têm
`REVOKE-from-anon` (Track Q-D batch 3a.7) mas SEM gate interno
adicional.

Faz sentido criar `view_finance` action separada? Ou aceita que
qualquer authenticated member com PostgREST direct call pode ler?

**PM decide**: aguardar uso real OU adicionar `view_finance` agora.

### Q4 — Implementação imediata ou próxima sessão?

ADR está em `Proposed`. Implementação requer:
- 1 migration adicionando rows em `engagement_kind_permissions`
- 4 migrations (uma por fn) refactor de gate
- 4 contract tests (rpc-v4-auth coverage)
- 1 audit doc update

**Estimativa**: ~3-4h. Pode caber em p60 ou ser pivoted para p61.

**PM decide**: ratificar agora + agendar implementação.

---

## Status / Next Action

- [ ] PM ratifica ADR (responde Q1-Q4)
- [ ] Migration `engagement_kind_permissions` rows insertion
- [ ] 4 migrations conversão de gate (DROP+CREATE per RPC signature change rule)
- [ ] Contract tests (rpc-v4-auth coverage para 4 fns)
- [ ] Audit doc update — Phase B'' tally bumps
- [ ] Status ADR → `Accepted`

**Bloqueador atual**: PM input em Q1-Q4.

**Cross-references**:
- ADR-0007 (V4 authority model)
- ADR-0011 (V4 auth pattern RPCs+MCP)
- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` Phase B'' section
- `docs/council/2026-04-26-tracks-qd-r-security-hardening-decision.md`
  (decision log que estabelece Phase B'' como follow-up)
