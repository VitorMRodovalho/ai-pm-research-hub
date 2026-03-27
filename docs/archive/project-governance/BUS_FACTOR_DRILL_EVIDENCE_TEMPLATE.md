# BUS_FACTOR_DRILL_EVIDENCE_TEMPLATE.md

Template oficial para registrar drill de operador secundário.

## Metadados

- Data/hora (início):  
- Data/hora (fim):  
- Ambiente:  
- Operador secundário:  
- Observador/aprovador:  
- Cenário simulado:  

## Execução (checklist)

- [ ] `npm test`
- [ ] `npm run build`
- [ ] `npm run smoke:routes`
- [ ] `supabase migration list`
- [ ] Verificação de acesso GitHub (repo/settings essenciais)
- [ ] Verificação de acesso Supabase (project + SQL/migrations)
- [ ] Verificação de acesso Cloudflare Pages (deployments/rollback)

## Evidências anexadas

- Links para logs de comando:
- Links para screenshots:
- Commit/branch usado no drill:
- Referência no `docs/RELEASE_LOG.md`:

## Resultado por etapa

| Etapa | Status (OK/Falha) | Tempo | Observações |
|------|--------------------|-------|-------------|
| Setup inicial |  |  |  |
| Build/Test/Smoke |  |  |  |
| Supabase verificação |  |  |  |
| Cloudflare verificação |  |  |  |
| Encerramento |  |  |  |

## Gaps encontrados

1.  
2.  
3.  

## Plano de ação

| Gap | Ação corretiva | Owner | Prazo |
|-----|----------------|-------|-------|
|  |  |  |  |

## Critério de aprovação do drill

- [ ] Operador secundário concluiu o fluxo sem intervenção técnica direta.
- [ ] Evidências anexadas e rastreáveis.
- [ ] Gaps mapeados com plano de ação.
