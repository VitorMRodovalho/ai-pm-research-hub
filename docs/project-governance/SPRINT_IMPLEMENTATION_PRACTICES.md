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
5. **Gate de Integração:**
   - Feature de frontend sem backend/API/SQL pronto não avança para desenvolvimento. Ver `docs/project-governance/PROJECT_ON_TRACK.md`.

---

## Rotina de Encerramento de Sprint (5 Fases)

Toda sprint DEVE completar esta sequência antes de iniciar a próxima. Este processo foi formalizado a partir da Wave 7 e é obrigatório.

### Fase 1: Execute
- Todas as alterações de código da sprint estão completas.
- Nenhum item do sprint permanece em `in_progress`.

### Fase 2: Audit
- `supabase db push` — aplicar migrações pendentes em produção.
- `npm run build` — confirmar build limpo sem erros.
- `npm test` — todos os testes passam (13+ testes unitários).
- Lint check nos arquivos editados (0 erros introduzidos).
- Smoke test de rotas — verificar que todas as rotas retornam HTTP 200.
- Verificação de RPCs — confirmar que novas RPCs retornam dados corretos.

### Fase 3: Fix
- Corrigir qualquer problema encontrado na Fase 2.
- Se a correção for substancial, repetir a Fase 2 para o escopo afetado.

### Fase 4: Docs
- `backlog-wave-planning-updated.md` — marcar wave como CONCLUÍDA, registrar resultados da auditoria.
- `docs/RELEASE_LOG.md` — nova entrada com versão (vX.Y.Z), escopo, arquivos alterados, resultados.
- `docs/GOVERNANCE_CHANGELOG.md` — decisões arquiteturais e lições aprendidas da sprint.
- Atualizar PRODUCTION STATE SUMMARY no backlog com contagens atualizadas.

### Fase 5: Deploy
- `git add -A && git commit` — mensagem seguindo conventional commits.
- `git push origin main` — deploy automático via Cloudflare Pages.
- `git tag -a vX.Y.Z -m "descricao"` + `git push origin vX.Y.Z` — tag de release.
- Verificação final em produção (navegação manual nas funcionalidades entregues).
