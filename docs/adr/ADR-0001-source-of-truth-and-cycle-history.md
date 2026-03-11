# ADR-0001: Source of Truth and Cycle History

- Status: Accepted
- Data: 2026-03-11

## Contexto

O Hub integra dados de membros, ciclos, gamificação e operação. Sem regra clara de origem da verdade, surgem divergências entre tabelas de estado atual e relatórios históricos.

## Decisão

1. O Hub é a fonte única de verdade operacional.
2. `members` representa snapshot atual.
3. Histórico de participação/atribuição por ciclo deve viver em `member_cycle_history` (e fatos relacionados), não em colunas legadas de snapshot.

## Consequências

- Relatórios e timelines devem ser cycle-aware.
- Features novas não podem misturar estado atual e histórico na mesma leitura sem modelagem explícita.
- Reduz drift entre superfície de produto e governança de dados.
