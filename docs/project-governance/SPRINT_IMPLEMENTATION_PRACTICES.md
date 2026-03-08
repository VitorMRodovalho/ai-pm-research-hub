# Práticas de Implementação de Sprint

## Definition of Done (Engenharia)
Para considerar um item de Sprint ou Hotfix tecnicamente concluído, os seguintes critérios devem ser cumpridos:

1. **Qualidade de Código:**
   - Sem uso de Vanilla JS inline em eventos (ex: `onclick="funcao()"`). Use Event Delegation.
   - UI deve seguir o design system usando Tailwind CSS.
2. **Validação Automatizada (CI Gate):**
   - O código deve passar no GitHub Actions CI (`npm test`, `npm run build`, `npm run smoke:routes`).
3. **Arquitetura de Banco de Dados:**
   - Se a feature exige mudança no banco, o SQL de migração DEVE ser documentado na pasta `docs/migrations/`.
   - Regras de leitura/escrita devem respeitar a Row Level Security (RLS) e a matriz de Tiers do Admin.
4. **Governança:**
   - Atualizar o `docs/RELEASE_LOG.md` com as evidências do que foi para produção.
