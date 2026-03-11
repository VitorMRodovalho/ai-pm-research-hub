# COMMS_PHASE1_BASELINE.md

Baseline operacional da Fase 1 para integração do time de comunicação no Hub.

## Objetivo

Estabelecer uma linha de base única (inventário + status) para transição gradual de operação comms para o Hub.

## Escopo da baseline

- canais de publicação;
- tipos de ativos;
- pontos de entrada operacionais;
- gaps para corte do Trello.

## Matriz de baseline (estado atual)

| Domínio | Fonte atual | Fonte-alvo | Status |
|---|---|---|---|
| Calendário de eventos | Hub (`events`) | Hub | em operação |
| Presença e lista | Hub (`attendance`) | Hub | em operação |
| Broadcast/Comms | Hub (`admin/comms`) + apoio externo | Hub (primário) | híbrido |
| Assets webinar/replay | Hub (`hub_resources`) | Hub | em operação |
| Gestão tática diária | Trello + Hub | Hub | transição |

## Critérios de avanço para fase 2

- `admin/comms` usado como painel primário semanal;
- pelo menos 1 ciclo completo com handoff attendance → comms sem retrabalho;
- evidência de uso (captura de templates, links e publicação).

## Cadência recomendada

- checkpoint semanal de 20 min;
- revisão quinzenal de gaps de processo;
- atualização mensal no `docs/RELEASE_LOG.md`.
