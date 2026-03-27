# Workflow: Sincronização Board ↔ Documentação

Este documento define como o assistente (Cursor) mantém o [GitHub Project](https://github.com/users/VitorMRodovalho/projects/1/) e a documentação sempre alinhados, para gestão à vista.

---

## Ferramentas disponíveis ao assistente

| Ferramenta | Acesso | Uso |
|------------|--------|-----|
| **Git** | ✅ | `git add`, `commit`, `push`, `branch` — atualiza o pipeline (commits acionam CI) |
| **GitHub CLI (gh)** | ✅ | Criar issues, adicionar ao project, mover status (Backlog → Done) |
| **Supabase** | ✅ | Schema via `npm run db:types`; consultas REST com `source .env` + curl |
| **Terminal** | ✅ | Scripts, build, smoke, migrações |

---

## Regra: Todo trabalho com impacto → Board + Docs atualizados

Ao concluir uma tarefa com impacto (feature, fix, migração):

1. **docs/RELEASE_LOG.md** — entrada com escopo, entregue, validação
2. **GitHub Issue** — criar se não existir; referenciar no commit (`fix: X (#NN)`)
3. **Project Board** — adicionar issue ao project (se nova); mover status para Done
4. **backlog-wave-planning-updated.md** — atualizar status do sprint/item quando relevante

---

## Comandos para o assistente

### Criar issue e adicionar ao project

```bash
gh issue create --repo VitorMRodovalho/ai-pm-research-hub --title "Título" --body "Descrição"
gh project item-add 1 --owner VitorMRodovalho --url https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/NN
```

### Mover card para Done (após obter item-id)

```bash
# Obter item-id: gh project item-list 1 --owner VitorMRodovalho | grep "issue-number"
gh project item-edit --id <ITEM_ID> --project-id PVT_kwHOC2hXyM4BRGtH \
  --field-id PVTSSF_lAHOC2hXyM4BRGtHzg_B9EY --single-select-option-id 98236657
```

**IDs de referência (Project 1, owner VitorMRodovalho):**
- Project ID: `PVT_kwHOC2hXyM4BRGtH`
- Status field: `PVTSSF_lAHOC2hXyM4BRGtHzg_B9EY`
- Done: `98236657` | In progress: `47fc9ee4` | Backlog: `f75ad846` | Ready: `61e4505c`

### Commit com referência à issue

```bash
git add -A && git commit -m "feat: descrição (#NN)" && git push
```

---

## Checklist de conclusão de tarefa (para o assistente)

- [ ] Código/arquivos alterados e testados (`npm run build`)
- [ ] `docs/RELEASE_LOG.md` atualizado
- [ ] Issue existente referenciada no commit OU nova issue criada + adicionada ao project
- [ ] Card no board movido para Done (se aplicável)
- [ ] `backlog-wave-planning-updated.md` ajustado quando o item estiver listado lá

---

## Onde acompanhar

- **Board**: https://github.com/users/VitorMRodovalho/projects/1/
- ** docs**: `backlog-wave-planning-updated.md`, `docs/RELEASE_LOG.md`, `docs/project-governance/`
- **CI**: GitHub Actions (push aciona build, CodeQL, etc.)
