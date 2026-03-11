# COMMS_INTEGRATION_ROADMAP.md

Roadmap para integração operacional do time de comunicação no Hub e redução progressiva de dependência de Trello.

## Objetivo

Unificar planejamento, execução e evidências de comunicação no Hub sem ruptura operacional abrupta.

## Escopo

- Fluxos de pauta e publicação ligados a webinars/eventos.
- Acompanhamento de status (rascunho, revisão, publicado).
- Métricas operacionais mínimas para acompanhamento interno.
- Hand-off entre `/admin/webinars`, `/admin/comms`, `presentations` e `workspace`.

## Fora de escopo (nesta trilha)

- Reescrever stack de mídia social.
- Integrações diretas com APIs externas em tempo real.
- Automação completa de conteúdo com IA sem governança de revisão.

## Fases e milestones

### Fase 1 — Mapeamento e baseline (1 sprint)

- Inventariar quadro Trello atual (listas, labels, responsáveis, SLAs).
- Definir dicionário de status equivalente no Hub.
- Publicar checklist de migração piloto por campanha.

**Milestone M1:** baseline aprovado e checklist publicado.

### Fase 2 — Operação híbrida controlada (1-2 sprints)

- Operar planejamento principal no Hub e manter Trello apenas como fallback.
- Garantir que todo item publicado tenha referência de origem no Hub.
- Rodar acompanhamento semanal de gaps de adoção.

**Milestone M2:** >80% das pautas novas originadas no Hub.

### Fase 3 — Cutover assistido (1 sprint)

- Congelar criação de novos cards no Trello.
- Consolidar histórico essencial no Hub (metadados, não conteúdo sensível).
- Treinar operadores de comms no fluxo final.

**Milestone M3:** cutover concluído sem bloqueio operacional.

### Fase 4 — Estabilização e auditoria (contínuo)

- Monitorar tempos de ciclo de comunicação.
- Revisar qualidade de hand-off webinar -> comms -> publicação.
- Revisar governança mensal com evidências no release log.

**Milestone M4:** 2 ciclos seguidos sem rollback para Trello.

## Dependências

- ACL e permissões em `docs/PERMISSIONS_MATRIX.md`.
- Contratos de dados de eventos e curadoria já estáveis.
- Gate de CI/issue reference ativo para mudanças críticas.

## Riscos e mitigação

| Risco | Impacto | Mitigação |
|------|---------|-----------|
| Adoção parcial do time | Médio | operação híbrida com KPI de adoção e suporte semanal |
| Divergência de status Trello vs Hub | Alto | dicionário único de status + freeze na Fase 3 |
| Sobrecarga manual no início | Médio | priorizar templates e hand-offs contextualizados |
| Regressão de ACL | Alto | browser guards + revisão de matriz de permissões |

## Critérios de aceite

- Roadmap aprovado e comunicado para operação.
- Milestones e responsáveis definidos por fase.
- Evidências de adoção registradas em `docs/RELEASE_LOG.md`.
