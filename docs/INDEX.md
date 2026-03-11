# Docs Index por Persona

Mapa rápido de leitura para acelerar onboarding e execução no Hub.

## 1) GP / PM (coordenação executiva)

Ordem recomendada:

1. `README.md`
2. `backlog-wave-planning-updated.md`
3. `docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md`
4. `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md`
5. `docs/RELEASE_LOG.md`
6. `docs/GOVERNANCE_CHANGELOG.md`

## 2) Líder de Tribo / Operação

Ordem recomendada:

1. `docs/PERMISSIONS_MATRIX.md`
2. `docs/MIGRATION.md`
3. `docs/QA_RELEASE_VALIDATION.md`
4. `docs/DEPLOY_CHECKLIST.md`
5. `DEBUG_HOLISTIC_PLAYBOOK.md`
6. `docs/DISASTER_RECOVERY.md`

## 3) Contributor (frontend/backend/sql)

Ordem recomendada:

1. `AGENTS.md`
2. `CONTRIBUTING.md`
3. `docs/project-governance/BRANCH_ENFORCEMENT.md`
4. `docs/adr/README.md`
5. `docs/project-governance/PROJECT_AUTOMATION_SHORT_GUIDE.md`
6. `docs/MIGRATION.md`
7. `docs/RELEASE_PROCESS.md`

## 4) Sponsor / Chapter Liaison (leitura executiva)

Ordem recomendada:

1. `README.md`
2. `docs/RELEASE_LOG.md`
3. `docs/project-governance/ANALYTICS_V2_PARTNER_VALIDATION.md`
4. `docs/project-governance/REPO_SYNC_STRATEGY.md`
5. `docs/project-governance/ROADMAP_SEQUENCIAL_AGRUPADO.md`

## 5) Rotas de referência por tema

- **Governança**: `docs/project-governance/`
- **Decisões arquiteturais (ADR)**: `docs/adr/README.md`
- **Migrations e runbooks SQL**: `docs/migrations/`
- **Sprints específicas**: `docs/sprints/`
- **Webinars**: `docs/WEBINARS_MODULE_DISCOVERY.md` e `docs/WEBINARS_CONVERGENCE_PROPOSAL.md`
- **Replicação para outros capítulos**: `docs/REPLICATION_GUIDE.md`

## 6) Regra operacional

Qualquer mudança com impacto de produção deve refletir em:

1. `docs/RELEASE_LOG.md` (o que mudou + validação)
2. Documento de governança pertinente (`docs/project-governance/*`)
3. Runbook/migration pertinente (`docs/migrations/*`) quando houver SQL

## 7) Verificação rápida do índice

Para garantir que os links/referências do índice continuam válidos:

```bash
./scripts/audit_docs_index_links.sh
```

```bash
./scripts/audit_adr_index.sh
```
