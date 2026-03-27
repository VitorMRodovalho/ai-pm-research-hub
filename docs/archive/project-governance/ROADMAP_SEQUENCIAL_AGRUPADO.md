# Roadmap Sequencial Agrupado (Pai -> Filho)

**Board**: [GitHub Project](https://github.com/users/VitorMRodovalho/projects/1/) · **Runbook**: `PROJECT_GOVERNANCE_RUNBOOK.md`

## Por que havia itens em Wave 2/3 abertos enquanto Wave 4 avançou
A execução recente foi orientada por incidentes de produção e dependências urgentes (hotfix/ACL/credly/comms), mas sem um gate formal de pacote pai. Isso permitiu avanço de trilhas paralelas e deixou percepção de "onda fora de ordem".

## Regra nova (obrigatória)
Nenhum item entra em desenvolvimento sem:
1. issue filha vinculada a um EPIC pai;
2. dependências front/back/SQL/integração explícitas;
3. critérios de entrada e saída definidos.

## Estrutura de pacotes (estado 2026-03-08)

### P0 — Foundation Reliability Gate
- EPIC: #47
- Objetivo: estabilizar base operacional e eliminar regressão recorrente
- Filhos principais: #1, #3, #4, #5, #6 e histórico #8..#33
- Status alvo: `In progress` até fechar pendências de foundation

### P1 — Comms Operating System
- EPIC: #48
- Objetivo: cadeia fim-a-fim de comunicação sem front órfão
- Filhos: #2, #34, #35, #36, #37
- Dependência: P0 saudável

### P2 — Knowledge Hub Sequential Delivery
- EPIC: #49
- Objetivo: entregar knowledge por sequência de dados -> produto -> assistente
- Filhos: #7, #18, #19, #20, #21, #22, #38, #39
- Dependência: P0 e P1

### P3 — Scale, Data Platform & FinOps
- EPIC: #50
- Objetivo: escalabilidade multi-tenant + governança de custo/dados
- Filhos: #23, #24, #25, #26, #40, #41, #42, #43, #44, #45, #46
- Dependência: P2 em produção estável

## Sequência de execução (controle visual)
1. P0 Foundation
2. P1 Comms
3. P2 Knowledge
4. P3 Scale/Data/FinOps

## Gate de avanço entre pacotes
- `P0 -> P1`: zero regressão crítica aberta de profile/auth/tribes/gamification
- `P1 -> P2`: cadeia comms com evidência de publicação/auditoria
- `P2 -> P3`: RAG e ingestão estáveis com custo monitorado

## Política de priorização
- Prioridade máxima é sempre fundação/arquitetura quando há risco de regressão.
- Feature sem backend/API/SQL pronto não entra em `In progress`; fica em `Ready` ou `Backlog`.
