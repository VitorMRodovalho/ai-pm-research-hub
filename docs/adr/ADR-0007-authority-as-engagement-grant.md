# ADR-0007: Authority as Derived Grant from Active Engagements

- Status: Accepted
- Data: 2026-04-11
- Aprovado por: Vitor (PM) em 2026-04-11
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Modelo de Domínio V4 — Decisão 4/6

## Contexto

O modelo atual (ADR-0002) armazena autoridade em `members.operational_role` (scalar global) + `members.tribe_id` (scope) + `members.designations[]` (capabilities). Isto funciona quando:
- Uma pessoa tem um único papel estável.
- O scope é uma tribo fixa.
- Capabilities são transversais.

Mas o modelo quebra quando:

1. **Scope varia por recurso** — Herlon precisa de escrita apenas no CPMAI, não em qualquer initiative.
2. **Autoridade é temporária** — palestrante externo pode anotar feedback só durante o webinar.
3. **Autoridade depende de termo vigente** — voluntário com termo vencido não pode acessar PII.
4. **Auditoria precisa rastrear origem** — "quem concedeu esta permissão, baseado em qual artefato de governança".
5. **Revogação precisa ser atômica** — desligar alguém hoje exige caçar operational_role + designations + board_members + etc.
6. **Expiração automática** — hoje o Herlon está `observer` porque **alguém esqueceu** de rebaixar quando o termo venceu. Isto é um gap crítico de governança.

Plataforma de governança máxima exige: **toda permissão rastreável até um artefato de governança com vigência explícita**.

## Decisão

1. **Toda autoridade é função derivada de `engagements` ativos**. Não existe campo `operational_role` mutável como fonte de verdade — existe função `resolve_authority(person_id, org_id)` que computa em tempo real a partir dos engagements ativos (ADR-0006) da pessoa.
2. **Gate canônico**:
   ```sql
   can(person_id, action, resource_type, resource_id) RETURNS boolean AS
   $$
     SELECT EXISTS (
       SELECT 1 FROM engagements e
       WHERE e.person_id = person_id
         AND e.status = 'active'
         AND e.start_date <= current_date
         AND (e.end_date IS NULL OR e.end_date >= current_date)
         AND (e.agreement_certificate_id IS NOT NULL OR NOT kind_requires_agreement(e.kind))
         AND engagement_grants_action(e.kind, e.role, action, resource_type, e.initiative_id, resource_id)
     );
   $$
   ```
3. **`operational_role` continua existindo como cache denormalizado** (para performance em queries de listagem), mas é **recalculado automaticamente via trigger** sempre que engagements mudam. Nunca editado manualmente. Substitui ADR-0002 como fonte de verdade, mantém compatibilidade.
4. **`canWrite` e `canWriteBoard` no nucleo-mcp** migram para chamar `can(...)`. `WRITE_ROLES` vira lookup em `engagement_kind_permissions`, não array hardcoded.
5. **Todas RLS policies** que hoje fazem `operational_role IN (...)` migram para subquery em engagements. Gradualmente, via view `auth_engagements` para reduzir duplicação.
6. **Trigger de expiração diária** (pg_cron): encerra engagements com `end_date < today`, rebaixa operational_role, notifica para renovação via VEP. Fecha o gap de "esquecer de rebaixar Herlon".
7. **Trigger de termo vencido**: se `agreement_certificate_id` é requerido pelo kind e o certificate não está mais válido, engagement passa a `suspended` automaticamente — acesso a PII cortado até renovação.

## Consequências

**Positivas:**
- **Auditabilidade total**: cada permissão tem trace até (engagement → VEP → termo → base legal LGPD).
- **Expiração automática**: nunca mais "esquecer de rebaixar".
- **Revogação atômica**: `UPDATE engagements SET status='revoked'` e fim.
- **Permissões por recurso**: Herlon escreve no CPMAI mas não em outras initiatives.
- **Relatório LGPD trivial**: "quem acessa PII dos inscritos CPMAI hoje" é um SELECT.
- **Suporta engagements temporários**: palestrante externo, congress committee, workshops.

**Negativas / custos:**
- Refactor mais crítico do V4. Toca em TODOS os gates de autorização (RPCs, RLS, middleware, frontend).
- Performance: `can()` chamada N vezes por request pode ser cara. Mitigação: materializar em view + cache de sessão.
- Debugging: permissão negada vira "por que? qual engagement estava faltando?". Precisa ferramenta de diagnóstico.
- Risco de regressão: se o trigger de expiração tiver bug, pessoas perdem acesso indevidamente. Shadow mode antes de ativar.

**Neutras:**
- operational_role continua existindo — código legado continua funcionando durante a transição.

## Alternativas consideradas

- **(A) Adicionar `resource_grants` tabela separada além de operational_role** — rejeitado por duplicar fonte de verdade e criar drift.
- **(B) RBAC tradicional expandido** (mais valores de operational_role) — rejeitado por não modelar escopo-por-recurso e temporalidade.
- **(C) Authority derivada de engagements (escolhida)** — fonte única de verdade, governança by design.

## Relações com outros ADRs

- Depende de ADR-0006 (persons + engagements) — sem engagements, não há origem de autoridade
- **Substitui ADR-0002 parcialmente** — modelo V3 (operational_role + designations) continua existindo como cache/denormalização, mas fonte de verdade muda
- Requer ADR-0008 (lifecycle) para definir `kind_requires_agreement()` e expiração por kind

## Critérios de aceite

- [x] Função `can(person_id, action, resource_type, resource_id)` implementada e testada — `20260413420000`, 53 contract tests
- [x] View `auth_engagements` agrega engagements ativos + validade de termo — `20260413410000`
- [x] `operational_role` virou campo cache atualizado via trigger — `20260413430000` (trg_sync_role_cache)
- [x] `canWrite`/`canWriteBoard` no MCP chamam `can()` via `canV4()` → `can_by_member` RPC — **CUTOVER EXECUTADO 2026-04-13** (commit `cf76302`, 14 call sites, deploy confirmado)
- [x] Todas RLS policies migraram para subquery em `auth_engagements` — **CONCLUÍDO 2026-04-13.** 36 direct-query policies em 24 tabelas reescritas via `rls_can()`/`rls_is_superadmin()`/`rls_can_for_tribe()`. Migrations `20260415000000` + `20260415010000`.
- [x] Trigger diário de expiração em shadow mode ativo desde 2026-04-13 — `20260413440000` (cron 03:00 UTC)
- [x] Ferramenta de diagnóstico `why_denied()` implementada no banco — `20260413420000`; admin UI na Fase 5
- [ ] Relatório LGPD "quem acessa PII de <kind> agora" gerável em 1 query — **postergado Fase 7** (Fase 5 fechou sem endereçar; query trivial: `SELECT FROM auth_engagements WHERE action = 'view_pii'`)
- [x] Testes de regressão cobrindo authority contracts — 53 assertions em `authority-derivation.test.mjs`
