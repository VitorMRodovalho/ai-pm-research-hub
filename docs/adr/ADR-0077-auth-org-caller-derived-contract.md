# ADR-0077: `auth_org()` caller-derived contract — fail-closed multi-tenant scoping

- Status: Accepted
- Data: 2026-05-10 (post p136 commit `30af579`)
- Aprovado por: Vitor (PM) em 2026-05-10
- Autor: Vitor (PM) + Claude (council Wave síntese p136)
- Escopo: Contrato comportamental do helper `auth_org()` usado por 30+ políticas RLS V4. Decorrência operacional de ADR-0004 (multi-tenancy posture) e ADR-0009 (organization_id retrofit). Não substitui — formaliza a semântica que faltava ser explícita.

## Contexto

ADR-0004 (Multi-Tenancy Posture, 2026-04-11) decidiu que toda tabela de domínio receberia `organization_id NOT NULL` e que toda RLS policy nova filtraria por `organization_id = auth_org()`. A implementação V4 Phase 1 (`20260411200000_v4_phase1_organizations_chapters.sql` + `20260411230000_v4_phase1_rls_org_scope.sql`) entregou a coluna e o helper, mas o corpo de `auth_org()` ficou como **placeholder hardcoded** — `SELECT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid` (PMI-GO).

O placeholder não foi marcado como dívida aberta em nenhum ADR ou no master doc V4 (`DOMAIN_MODEL_V4_MASTER.md`). A intenção de torná-lo caller-derived "quando o multi-tenant ligar" ficou implícita e desapareceu do radar conforme o refactor V4 fechou (2026-04-13). Como existia apenas uma org real (Núcleo IA / PMI-GO), o comportamento era **observacionalmente correto** para members reais:

- Member ativo PMI-GO → policy `organization_id = auth_org()` casa → vê seus dados ✅

Mas para callers sem member record, o placeholder produzia uma falha estrutural silenciosa:

- Ghost auth (logado em `auth.users`, sem linha em `members`) → `auth_org()` retornava `'2b4f58ab-…'` → policy casava → ghost via dados org-scoped V4 ❌
- Member inativo (11 hoje, `is_active = false`) → mesmo problema ❌
- Service role (sync-artia EF, crons) → `auth.uid()` é NULL → helper ainda retornava o UUID hardcoded → linhas de log ficavam aparentemente atribuídas a PMI-GO mas com `auth.uid()=NULL` em `created_by` etc.

Sessão p136 audit (RF-1) descobriu o vetor por outro caminho: três tabelas financeiras (`cost_entries`, `revenue_entries`, `sustainability_kpi_targets`) tinham policies `USING(true)` (P0 financial leak para qualquer authenticated). O fix — replicar o padrão V4 `organization_id = auth_org()` — só fecharia o vetor financeiro **se** `auth_org()` falhasse em ghost/inactive. Cruzar os dois bugs forçou a reescrita.

## Decisão

### 1. `auth_org()` é caller-derived, não hardcoded

Implementação canônica (migration `20260520010000`, commit `30af579`):

```sql
CREATE OR REPLACE FUNCTION public.auth_org()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT m.organization_id
  FROM public.members m
  WHERE m.auth_id = auth.uid()
    AND m.is_active = true
  ORDER BY m.created_at DESC
  LIMIT 1
$function$;
```

### 2. Semântica por classe de caller

| Caller | `auth.uid()` | `members` row | `auth_org()` retorna | Visibilidade org-scoped V4 |
|---|---|---|---|---|
| Member ativo single-org | UUID | 1 row, `is_active=true` | UUID da org | Vê dados da própria org |
| Member ativo multi-org (futuro) | UUID | N rows, todas active | UUID da row mais recente | Vê dados da org mais recente; switch via header (futuro) |
| Member inativo | UUID | row, `is_active=false` | NULL | Bloqueado (fail-closed) |
| Ghost auth (sem member) | UUID | 0 rows | NULL | Bloqueado (fail-closed) |
| Service role (EF/cron) | NULL | — | NULL | Bloqueado em policies estritas; visível a admin via `OR IS NULL` em policies permissivas |
| Anon | NULL | — | NULL | Bloqueado (combinado com `TO authenticated`) |

### 3. Consumidores classificam-se em dois grupos

**Grupo A — Strict (financeiro, dados sensíveis):**
- Policy: `(organization_id = auth_org()) [AND demais gates]`
- NULL org row = **não visível** mesmo a admin (fica como dívida que precisa de org_id explícito)
- Tabelas: `cost_entries`, `revenue_entries`, `sustainability_kpi_targets`

**Grupo B — Permissivo (logs operacionais, metadados de plataforma):**
- Policy: `(organization_id = auth_org() OR organization_id IS NULL)`
- NULL org row = "log de plataforma/sistema" visível a admin
- Tabelas: `mcp_usage_log` (Ω-E.1.c, migration `20260520020000`), padrão herdado de 30+ tabelas V4 que já usavam essa cláusula

A diferença entre A e B é **declarativa por tabela**, não emergente. Toda nova tabela V4 escolhe Grupo A ou B no design da migration. Default sugerido: A (strict). B só quando há justificativa explícita de que NULL é semanticamente "global/plataforma" para aquele dado.

### 4. Ergonomia para service-role inserts

EFs que rodam como service role (sync-artia, crons LGPD, ingestão Phase B) **devem** passar `organization_id` explícito no INSERT, em vez de depender do DEFAULT (que agora retorna NULL). Padrão (sync-artia, p138 commit `<TBD>`):

```typescript
const PMI_GO_ORG_ID = '2b4f58ab-7c45-4170-8718-b77ee69ff906'

await sb.from('mcp_usage_log').insert({
  tool_name: 'sync-artia',
  /* ... */
  organization_id: PMI_GO_ORG_ID,
})
```

Quando multi-tenant ligar, `PMI_GO_ORG_ID` vira parâmetro derivado do contexto da invocação (e.g., header da request, partition do cron, payload do worker). Não é elegível ficar como NULL "porque o admin vê de qualquer jeito" — isso amarra o design ao Grupo B e fecha optionality para mover a tabela para Grupo A no futuro.

### 5. Caller-switching multi-org (deferido)

Quando aparecer member com mais de uma org ativa (PMI-CE pilot, futuras federações), o `LIMIT 1 ORDER BY created_at DESC` retorna a org mais recente. Não é uma escolha consciente. **A solução final é UI/header de "active org" + helper recebendo overrride** (e.g., `auth_org(p_override uuid)` ou variável de sessão). Esta ADR não decide o mecanismo — declara que o `LIMIT 1` é placeholder pragmático até multi-org real existir.

## Consequências

**Positivas:**
- Fail-closed para ghost e inativo: 30+ tabelas V4 deixam de vazar dados org-scoped a callers sem member ativo (correção retroativa).
- Ergonomia multi-tenant pronta: PMI-CE pilot e futuras orgs scopam corretamente sem novo refactor.
- Auditoria LGPD defensável: a fronteira "outra org não vê nossos dados" agora é estrutural, não circumstancial (não dependia de "só temos 1 org").
- Duas posturas (strict vs permissivo) ficam declarativas e auditáveis por tabela.

**Negativas / custos:**
- 11 members inativos perdem acesso de leitura V4 (esperado — `is_active=false` significa offboardado; UX deve direcionar para reativação ou export LGPD).
- Service role sem `organization_id` explícito gera linhas com NULL — exige Grupo B na tabela, ou bug emerge (RPCs frontend não enxergam log próprio).
- Smoke tests de RLS precisam cobrir 4 classes de caller (member ativo, ghost, inativo, service role) — não basta "logado vs anon".
- Performance: lookup de `members` por `auth_id` em cada chamada. Mitigado por `STABLE` (cache per-query) + `idx_members_auth_id` (partial index). Net cost ~0 em steady state, validado empiricamente p136.

**Neutras:**
- `LIMIT 1 ORDER BY created_at DESC` é placeholder até multi-org real. Não é decidido aqui.
- ADRs anteriores que assumiam `auth_org()` retornar UUID válido para qualquer authenticated user (e.g., políticas `OR IS NULL` redundantes onde só `=` bastaria) ficaram corretas em retrospecto — a redundância vira defesa em profundidade.

## Alternativas consideradas

- **(A) Manter placeholder, aceitar exposição ghost** — rejeitado: ghost pode logar via OAuth Anthropic Connector ou registro espontâneo (`signUp` flow); LGPD não tolera defesa que depende de "ninguém faz signup ainda".
- **(B) Caller-derived com `LIMIT 1` por created_at (escolhida)** — pragmática; correta para caso real (1 org ativa por member); placeholder honesto para multi-org futuro.
- **(C) Caller-derived + erro explícito se member tem N>1 orgs** — rejeitada para não bloquear migração futura quando aparecer o primeiro caso multi-org (deveria ser não-fatal, com header de switch).
- **(D) `auth_org(p_override)` parametrizado já agora** — rejeitada: complica policies hoje (todos os callers seriam atualizados) sem benefício imediato; adiada até primeira org multi-tenant real.

## Relações com outros ADRs

- **Decorrência de ADR-0004** (multi-tenancy posture) — formaliza o contrato semântico que ADR-0004 deixou implícito.
- **Decorrência de ADR-0009** (organization_id retrofit) — completa a peça do helper que o retrofit assumia funcional.
- **Complementa ADR-0011** (autoridade V4) — `can_by_member()` opera em `member.id`; `auth_org()` opera em `auth.uid() → members.auth_id`; os dois compõem a fronteira (capacidade + escopo organizacional).
- **Não substitui ADR-0007** (Authority) — autoridade continua via `can()`/RPC; org-scoping é camada ortogonal de defesa.
- **Cita ADR-0076** (Phase B base legal) — Phase B (PMI Community ingest) usa service role + INSERT com `organization_id` explícito, conforme padrão #4 acima.

## Critérios de aceite

- [x] `auth_org()` reescrita aplicada em produção (migration `20260520010000`, commit `30af579`)
- [x] Smoke verificado p136: ghost/inativo bloqueados; member ativo vê dados; admin com `manage_member` vê NULL rows em `mcp_usage_log` via Ω-E.1.c
- [x] Financial tables (Grupo A) verificadas com ghost UUID `00000000-…` retornando 0 linhas
- [x] sync-artia EF passa `organization_id` explícito (p138 Ω-E.2-b — este commit)
- [ ] Próximas EFs/crons que escrevem em tabelas V4 seguem padrão #4 (PR review check)
- [ ] Smoke RLS expandido para 4 classes de caller (TODO suite, não bloqueante)
- [ ] Quando aparecer primeiro multi-org real: revisar `LIMIT 1` (decisão futura, fora do escopo desta ADR)

## Rollback

Reverter `auth_org()` ao placeholder hardcoded reabre o vetor de exposição ghost. **Não recomendado.** Se necessário (e.g., bug em produção que afete membros ativos):

```sql
-- Rollback (preservado no header da migration 20260520010000)
CREATE OR REPLACE FUNCTION auth_org() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$ SELECT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid $$;
```

Após rollback, RF-1 ghost exposure volta a abrir em 30+ tabelas. Tratar como incidente LGPD: registrar em `pii_access_log`, comunicar DPO (Ivan), planejar fix corrigido em <24h.

## Anti-patterns (para PR review)

1. **`auth_org()` em RPC SECURITY DEFINER sem `can_by_member()` adicional** — SECDEF bypassa RLS; precisa gate explícito de capacidade. Fix Ω-E.2-a (commit `4f5f3b9`) adicionou `can_by_member(_, 'manage_finance')` em 4 RPCs financeiros. Padrão para SECDEF read em dados sensíveis.
2. **`organization_id IS NULL OR ...` em tabela financeira** — confunde Grupo A e B. Tabela financeira é Grupo A; NULL deve ser superadmin-only.
3. **Service role insert sem `organization_id`** — produz linha NULL que só Grupo B mostra a admin. Em Grupo A, vira dado órfão. Sempre passar org explícito (ou justificar Grupo B na ADR da feature).
4. **Confiar `auth_org()` em código de aplicação** — helper é para RLS. Aplicação deve receber `organization_id` via session/header explícito. RLS é defesa em profundidade, não API.

## Ledger histórico

| Data | Evento | Commit |
|---|---|---|
| 2026-04-11 | ADR-0004 ratifica multi-tenancy posture; `auth_org()` criado como placeholder hardcoded | V4 Phase 1 |
| 2026-04-13 | V4 refactor fecha; placeholder não migra para "dívida aberta" no master doc | V4 close |
| 2026-05-10 | Audit RF-1 descobre exposição financeira; descobre placeholder; rewrite caller-derived | `30af579` |
| 2026-05-10 | `mcp_usage_log` policy ajustada para Grupo B (NULL admin-visible) | `1de9996` |
| 2026-05-10 | sync-artia EF passa `organization_id` explícito (padrão #4) | p138 (este) |
| 2026-05-10 | Esta ADR formaliza contrato comportamental | p138 (este) |
