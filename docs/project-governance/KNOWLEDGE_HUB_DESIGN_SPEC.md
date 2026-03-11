# KNOWLEDGE_HUB_DESIGN_SPEC.md

Especificação funcional/técnica do Knowledge Hub para execução incremental segura.

Status: **Aprovado para implementação em fases**  
Fonte complementar: `docs/WAVE5_KNOWLEDGE_HUB_PLAN.md`

## 1. Objetivo

Transformar o Hub em uma camada relacional de conhecimento entre ciclos, tribos e entregáveis, evitando múltiplas fontes de verdade e preservando governança/LGPD.

## 2. Princípios de desenho

1. **Fonte única operacional**: reutilizar entidades existentes (`events`, `artifacts`, `hub_resources`, `knowledge_assets`) antes de criar novas tabelas.
2. **Segurança no banco**: RLS e contratos RPC como fronteira de acesso.
3. **Sem agregação pesada no cliente**: painéis e filtros críticos via SQL/RPC.
4. **Compatibilidade progressiva**: manter rotas e fluxos legados enquanto o novo módulo amadurece.

## 3. Escopo funcional (MVP incremental)

- Curadoria com estados (`draft/review/approved/rejected`) e taxonomia de tags.
- Descoberta de conhecimento por:
  - tribo
  - tipo de ativo
  - ciclo
  - palavras-chave
- Superfícies conectadas:
  - `workspace`
  - `presentations`
  - `admin/curatorship`
  - `admin/analytics` (somente indicadores agregados)

## 4. Modelo de dados (direção)

### Reuso imediato

- `artifacts` para produção de pesquisa e outputs.
- `hub_resources` para biblioteca de consumo.
- `events` (`type='webinar'`) para trilha de agenda/attendance/replay.
- `knowledge_assets` para curadoria de conhecimento ativável/publicável.
- `taxonomy_tags` para classificação padronizada.

### Expansões condicionais (somente se necessidade real)

- Entidades especializadas de speaker/registration para webinars externos.
- Estruturas adicionais de lineage apenas com validação de uso operacional.

## 5. ACL e governança

- Leitura ampla no público somente para conteúdo explicitamente ativo/publicado.
- Operação de curadoria restrita a perfis administrativos/liderança definidos em matriz de permissões.
- Dados analíticos sensíveis: apenas agregados, sem PII.

## 6. Fluxos principais

1. **Ingestão**: ativo entra como draft com metadados mínimos.
2. **Curadoria**: operador classifica tags, visibilidade e público.
3. **Publicação**: item aprovado passa a superfícies públicas/internas conforme ACL.
4. **Observabilidade**: indicadores de qualidade e cobertura por ciclo/tribo.

## 7. Fases de implementação

### Fase A — Consolidação de contratos

- Revisar e fixar contratos RPC usados por curadoria e busca.
- Garantir testes de regressão para ACL e filtros.

### Fase B — UX integrada

- Melhorar jornada de busca cruzada em `workspace` e `presentations`.
- Reforçar feedback de status de curadoria no admin.

### Fase C — Métricas de conhecimento

- Indicadores agregados de volume, cobertura por tribo e tempo de curadoria.
- Sem introduzir BI paralelo fora do stack atual.

## 8. Dependências e riscos

### Dependências

- Consistência de tags/taxonomia.
- Integridade de `tribe_id` e `cycle_code`.
- Pipeline de CI cobrindo smoke + browser guards.

### Riscos

- Drift entre copy i18n e dados runtime.
- Crescimento de acoplamento em páginas admin monolíticas.
- Expansão prematura de schema sem prova de necessidade.

## 9. Critérios de aceite (DoD)

- Contratos SQL e frontend alinhados para curadoria e descoberta.
- Cobertura mínima de regressão para ACL, busca e publicação.
- Documentação atualizada em `docs/RELEASE_LOG.md` e governança associada.
- Sem bypass de RLS e sem hardcode operacional de agenda/prazos.
