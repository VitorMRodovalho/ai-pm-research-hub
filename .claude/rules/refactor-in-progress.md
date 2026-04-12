# Refactor In Progress — Domain Model V4

**STATUS:** Active (desde 2026-04-11)
**Master doc:** `docs/refactor/DOMAIN_MODEL_V4_MASTER.md`

## Quando este arquivo se aplica

Sempre que houver refactor arquitetural ativo na plataforma. Ao terminar, este arquivo deve ser removido ou marcado como `STATUS: Complete`.

## Regras mandatórias durante o refactor V4

### 1. Leia antes de tocar
Antes de qualquer edição em código de domínio (migrations, RPCs, middleware, frontend auth), leia:
1. `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` (status e fase atual)
2. O ADR relevante (0004-0009) da decisão que está implementando

### 2. Invoque o guardian no começo E no fim da sessão
Use o agente `.claude/agents/refactor-guardian.md` para:
- **No início:** status check + invariantes antes de começar
- **No fim:** auditoria de impacto e atualização do master doc

### 3. Não crie decisões fora dos ADRs
Se o trabalho exigir uma decisão que não está em nenhum ADR 0004-0009, **pare e crie um ADR novo**. Não comite até o ADR estar escrito.

### 4. Migrations novas seguem regras adicionais
- Toda tabela de domínio nova tem `organization_id` (depois de Fase 1)
- Toda entidade de pessoa nova usa `persons` (depois de Fase 3)
- Toda gate de autoridade nova chama `can()` (depois de Fase 4)
- RLS policy é mandatória (GC-162)
- Rollback documentado no header da migration

### 5. Nenhuma feature estável pode regredir
Antes de commit, rodar smoke (ver `DOMAIN_MODEL_V4_MASTER.md` seção "Features estáveis que não podem regredir"). Se algum quebra, reverter e investigar antes de prosseguir.

### 6. Commits atômicos por sub-fase
Um commit = uma sub-fase entregável. Não misturar sub-fases diferentes. Cada commit deve ser revertível individualmente.

### 7. Nada de "fix depois"
Se um TODO crítico surgir, ou ele entra nesta sessão, ou vira ticket no master doc. Nunca fica como comentário no código.

### 8. Shadow mode antes de cutover
Estruturas novas rodam em paralelo com as antigas por pelo menos 48h (72h para fases críticas) antes de virar default. Ver plano em fases no master doc.

### 9. Branch isolada
Trabalho de refactor acontece em `refactor/domain-v4` ou branches derivadas. `main` só recebe merge depois de quiet window.

### 10. Parallel tracks respeitam invariantes
Trabalho paralelo (ex: Herlon onboarding via VEP formal) não pode criar dívida que o refactor vai pagar depois. Ver `docs/refactor/HERLON_VEP_PARALLEL_TRACK.md` para o padrão de parallel track correto.

## Features bloqueadas durante o refactor

A menos que explicitamente autorizadas pelo PM:

- Novas tabelas `*_courses`, `*_events`, ou "tabelas dedicadas por caso" — vão contra ADR-0005 e ADR-0009
- Novos valores de `operational_role` — vão contra ADR-0007
- Novas colunas em `members` para casos especiais — vão contra ADR-0006
- Edições em `sign_volunteer_agreement()` que não sejam para Fase 3 do V4
- Mudanças em `canWrite`/`canWriteBoard` fora da Fase 4

## Quem pode ignorar estas regras

Ninguém durante a vigência do refactor. Se algo urgente exige exceção, documentar em `DOMAIN_MODEL_V4_MASTER.md` como exceção aprovada pelo PM com justificativa e plano de reconciliação.

## Referências obrigatórias

- `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` — master tracking
- `docs/adr/ADR-0004` a `ADR-0009` — decisões arquiteturais
- `.claude/agents/refactor-guardian.md` — agente de auditoria
- `docs/refactor/HERLON_VEP_PARALLEL_TRACK.md` — exemplo de parallel track
