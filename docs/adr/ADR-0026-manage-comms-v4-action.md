# ADR-0026: New V4 Action `manage_comms` — Phase B'' Conversion

- Status: **Accepted** (2026-04-26 p59 — PM rubber-stamp ratify of all Q1-Q4)
  + **Extended** (2026-04-26 p66 — campaign stats/preview added to scope)
- Data: 2026-04-26 (p59); extension 2026-04-26 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track — closes 3 V3-gated functions total
  (1 batch 1 + 2 extension)
- Ratify decisions:
  - Q1 sponsors com manage_comms: **NÃO**
  - Q2 chapter_board × liaison scope: **NÃO agora**
  - Q3 migrar admin_send_campaign + comms_check_token_expiry: **NÃO**
  - Q4 timing: **p59** (executado 2026-04-26)
  - Q5 (p66) — extender para `admin_get_campaign_stats` + `admin_preview_campaign`: **SIM**
- Implementation:
  - Batch 1: migration `20260426170038_adr_0026_manage_comms_v4_conversion`
  - Extension: migrations `20260427011141_adr_0026_extension_campaign_fns_v4_manage_comms` +
    `20260427011239_adr_0026_extension_campaign_fns_revoke_anon`
- Drift surfaced: Mayanna Duarte perdeu access (V3 designation comms_leader sem
  V4 engagement). Documentado para PM decidir se cria engagement post-fact.

---

## Contexto

Sequência de ADR-0025 (`manage_finance`). Fecha mais 1 das 11 funções
V3-gated documentadas como out-of-scope V3 → Phase B'' no audit doc.

### A função afetada

`admin_manage_comms_channel(p_action, p_channel, p_api_key, p_oauth_token, p_oauth_refresh_token, p_token_expires_at, p_config)`

Operações: `upsert` ou `delete` em `comms_channel_config` (tabela de
credenciais de canais de comunicação — Mailchimp, Resend, OAuth tokens
para WhatsApp Business API, etc.).

V3 gate atual:

```sql
SELECT operational_role, is_superadmin, designations
INTO v_role, v_is_admin, v_designations
FROM public.members WHERE auth_id = auth.uid();

IF NOT (
  v_is_admin
  OR v_role IN ('manager', 'deputy_manager')
  OR v_designations && ARRAY['comms_leader']
) THEN
  RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
END IF;
```

Caller único: `src/pages/admin/comms.astro` (admin tier).

### Por que precisa de nova action

Análise das 8 actions existentes (idêntica a ADR-0025):

| Action | Cabe para comms_channel_config? |
|---|---|
| `manage_platform` | Próximo, mas comms_leader hoje opera comms sem ser superadmin/manager |
| `manage_event` | Não — escopo evento, não credenciais de canal |
| `manage_member` | Não |
| `manage_partner` | Não |
| `manage_finance` (ADR-0025 Proposed) | Não |
| `view_pii` | Não — operação de write |
| `write` | Próximo, mas escopo tribe-level, não org-level |
| `write_board` | Não — board-scoped |

Reutilizar `manage_platform` significaria que `comms_leader` perde
acesso (não tem manage_platform). Quebraria fluxo atual onde
comms_leader opera o canal.

Manter granularidade `manage_comms` permite:
- Controle dedicado de quem mexe em credenciais de canais
- Audit trail mais limpo ("quem editou OAuth Mailchimp?")
- Compatibilidade futura com outras fns comms (e.g., admin_send_campaign
  já em V4 via manage_platform; talvez migre para manage_comms se
  granularidade for útil)

### Custo de não fazer

- 1 fn V3 permanece. Phase B'' dependency persiste para fechar
  totalmente a Q-D track.
- Auditoria PMI vê V3 mix em código que advertise V4 compliance.

---

## Decisão (proposta)

### 1. Adicionar nova V4 action `manage_comms`

```sql
-- Migration target: 20260427xxxxxx_add_v4_action_manage_comms.sql

INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  -- GP-tier and management roles (already have most other actions)
  ('volunteer', 'co_gp',          'manage_comms', 'organization'),
  ('volunteer', 'manager',        'manage_comms', 'organization'),
  ('volunteer', 'deputy_manager', 'manage_comms', 'organization'),
  -- comms_leader is the dedicated role for comms ops
  ('volunteer', 'comms_leader',   'manage_comms', 'organization')
  ON CONFLICT (kind, role, action) DO NOTHING;
```

Note kinds reais (descobertos via discovery em p59):
- `volunteer` é o kind para todos os papéis institucionais (manager,
  deputy_manager, co_gp, comms_leader, leader, etc.)
- `sponsor` é seu próprio kind com role único `sponsor`
- `chapter_board` tem role `liaison` para chapter ops

`is_superadmin` continua reconhecido via `can_by_member()` body
(superadmin path independente de kind/role).

### 2. Converter `admin_manage_comms_channel` para V4

```sql
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'authentication_required');
  END IF;

  -- V4 gate (replaces V3 mix of role + designation check)
  IF NOT public.can_by_member(v_caller_member_id, 'manage_comms') THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  -- (existing channel input validation + CASE upsert/delete)
END;
```

### 3. Privilege expansion safety check

```sql
WITH legacy AS (
  SELECT id FROM members
  WHERE is_active = true
    AND (
      is_superadmin = true
      OR operational_role IN ('manager', 'deputy_manager')
      OR designations && ARRAY['comms_leader']
    )
),
v4 AS (
  SELECT m.id FROM members m
  WHERE m.is_active = true
    AND public.can_by_member(m.id, 'manage_comms')
)
SELECT
  (SELECT count(*) FROM legacy) AS legacy_count,
  (SELECT count(*) FROM v4) AS v4_count,
  ARRAY(SELECT id FROM v4 EXCEPT SELECT id FROM legacy) AS would_gain,
  ARRAY(SELECT id FROM legacy EXCEPT SELECT id FROM v4) AS would_lose;
```

Aceito: `would_gain = []` AND `would_lose = []` OR diferença explicada
(documentar no commit).

Cuidado especial: `comms_leader` em V3 era uma `designation`
(text[] em members), mas em V4 é `engagement.role` em kind `volunteer`.
A migração de designations → engagements aconteceu em ADR-0006.
Se um member tem `designations && {comms_leader}` mas NÃO tem
engagement ativo `volunteer × comms_leader`, V4 conversion REMOVE
acesso desse member. Isso é correção de drift (V3 cache desatualizado),
não regressão — mas precisa ser documentado.

---

## Implications

### Para a plataforma

- **1 fn V3 a menos** no backlog Phase B''.
- **Granularidade comms preserved**: comms_leader continua
  operando o canal sem precisar ser manager/superadmin.
- **Audit cleaner**: edits em credenciais OAuth/API key agora têm
  origem clara via `pii_access_log` ou audit trigger.

### Para members

- Nenhum member ativo deve perder acesso (legacy V3 ⊆ V4 esperado).
- Drift de designations sem engagement será surfaced — caso aparece,
  PM decide criar engagement ou aceitar perda.

### Para path A/B/C optionality

- **Path A**: positivo — granularidade institucional (PMI auditor pode
  responder "quem é responsável por canal de comunicação?")
- **Path B**: positivo — multi-tenant SaaS pode ter dedicated comms
  admin role
- **Path C**: neutro

---

## Open Questions (para PM input)

### Q1 — Sponsors devem ter `manage_comms`?

A proposta NÃO inclui sponsors (diferente de ADR-0025 onde a proposta
inclui). Justificativa: sponsors têm responsabilidade institucional
financeira, mas não operacional comms. A operação de canal é função
do GP+comms_leader.

Alternativa: incluir sponsors para emergência (e.g., desativar canal
após incidente).

**PM decide**: incluir OU não incluir sponsors.

### Q2 — `chapter_board × liaison` deve ter `manage_comms`?

Cada chapter pode ter canais locais (e.g., grupo WhatsApp por chapter).
Liaison pode ter `manage_comms` com `scope='chapter'` (precisaria
column `chapter_id` em `comms_channel_config`).

**PM decide**: incluir agora (com scope work) OU adiar.

### Q3 — Migrar outras fns comms para `manage_comms`?

Hoje:
- `admin_send_campaign` já é V4 via `manage_platform` (p54 batch 4)
- `comms_check_token_expiry` é cron + admin reader (p55 batch 1
  amendment)

Se fizer sentido convergir essas fns também para `manage_comms`,
o action vira mais consistente. Trade-off: migration adicional
+ risco de regressão.

**PM decide**: manter scope de 1 fn ou expandir para 3.

### Q4 — Implementation timing

ADR está em `Proposed`. Implementação requer:
- 1 migration adicionando 4 rows em `engagement_kind_permissions`
- 1 migration conversão de gate (DROP+CREATE per signature)
- 1 contract test (rpc-v4-auth coverage)
- 1 audit doc update

Estimativa: ~1.5h (mais simples que ADR-0025 porque é apenas 1 fn).

**PM decide**: ratify + schedule p60 ou p61.

---

## Status / Next Action

- [ ] PM ratifica ADR (responde Q1-Q4)
- [ ] Decisão Q3 — drives if 1 ou 3 fns convertem
- [ ] Migration `engagement_kind_permissions` rows
- [ ] Migration conversão de gate (DROP+CREATE)
- [ ] Contract test
- [ ] Audit doc update — Phase B'' tally bumps
- [ ] Status ADR → `Accepted`

**Bloqueador atual**: PM input em Q1-Q4.

**Cross-references**:
- ADR-0007 (V4 authority model)
- ADR-0011 (V4 auth pattern RPCs+MCP)
- ADR-0025 (manage_finance — sister proposal, mesmo padrão)
- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` Phase B'' section
- `docs/council/2026-04-26-tracks-qd-r-security-hardening-decision.md`

---

## Extension (p66, 2026-04-26)

PM directive p66: "primeiro 1 depois 2" → item #1 = ADR-0026 scope extension.

### Scope addition

2 fns V3 added to scope (originally documented in p57/p58 audit as Phase B''
candidates):

1. `admin_get_campaign_stats(p_send_id uuid)` — campaign send statistics reader
   (delivered/opened/unsubscribed counts).
2. `admin_preview_campaign(p_template_id uuid, p_preview_member_id uuid)` —
   render template preview with variable substitution. Calls `log_pii_access`.

### V3 gate (both fns, identical)

```sql
SELECT id INTO v_caller_id FROM public.members
WHERE auth_id = auth.uid()
  AND (
    is_superadmin
    OR operational_role IN ('manager','deputy_manager')
    OR 'comms_team' = ANY(designations)
  );
```

### Discovery: `comms_team` designation = 0 active members

Pre-apply audit revealed `'comms_team' = ANY(designations)` was effectively
dead code — zero active members carry that designation. The legacy gate was
behaving as `is_superadmin OR manager/deputy_manager` only.

This is consistent with the V3 → V4 designation modernization track: ADR-0006
moved roles to `engagements`, leaving some V3 designation references as dead
references in code that was never updated.

### Privilege expansion (zero change)

```
legacy_count = 2  (Vitor SA, Fabricio manager-equiv)
v4_count    = 2  (same)
would_gain   = []
would_lose   = []
```

Mayanna (designation comms_leader, no V4 engagement volunteer×comms_leader) —
same drift case as ADR-0026 batch 1; no incremental impact.

### pg_policy precondition (Q-D charter, p65)

Verified zero RLS policy refs to either fn (word-boundary regex `\m`).
REVOKE FROM anon is safe — applied as defense-in-depth.

### Migrations

- `20260427011141_adr_0026_extension_campaign_fns_v4_manage_comms.sql` —
  CREATE OR REPLACE for both fns with `can_by_member(_, 'manage_comms')` gate.
  search_path tightened to `''` (matches ADR-0026 batch 1 pattern).
- `20260427011239_adr_0026_extension_campaign_fns_revoke_anon.sql` —
  REVOKE EXECUTE FROM PUBLIC, anon (defense-in-depth, matches batch 1).

### Phase B'' tally update

Pre-extension: 65/213 (~30.5%) per p64 handoff.
Post-extension: **67/213 (~31.5%)**.
