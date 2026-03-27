# Processo de Release para Produção

Quando o projeto atingir maturidade para deploy em produção, o release deve ser feito em forma estruturada com changelog.

---

## 1. Pré-requisitos de maturidade

Antes de criar um release:

- [ ] `npm test` e `npm run build` passando
- [ ] Smoke de rotas executado: `npm run smoke:routes`
- [ ] Checklist de deploy em dia: `docs/DEPLOY_CHECKLIST.md`
- [ ] Migrações SQL documentadas (se houver) com pack apply/audit/rollback
- [ ] `docs/RELEASE_LOG.md` atualizado com todas as mudanças da release

---

## 2. Formato do Release

### 2.1 Tag e versão

```bash
# Exemplo: release v1.0.0
git tag -a v1.0.0 -m "Release v1.0.0 — [resumo curto]"
git push origin v1.0.0
```

Seguir [Semantic Versioning](https://semver.org/) quando aplicável:
- **MAJOR**: breaking changes, mudanças incompatíveis
- **MINOR**: novas features, backward compatible
- **PATCH**: bugfixes, melhorias

### 2.2 Changelog

Criar um **GitHub Release** com changelog completo:

1. Em GitHub: Repo → Releases → Draft a new release
2. Tag: selecionar a tag criada
3. Title: `v1.0.0 — [Título descritivo]`
4. Description: corpo do changelog

### 2.3 Template do Changelog (Markdown)

```markdown
## v1.0.0 — [Data] — [Título da release]

### Resumo
Breve descrição do escopo da release e do estado de maturidade.

### Novas funcionalidades
- **X**: descrição
- **Y**: descrição

### Melhorias e correções
- **Z**: descrição

### Segurança e conformidade
- Event Delegation em [rotas/páginas]
- XSS hardening (escapeHtml/escapeAttr)
- ACL e gates de acesso

### Migrações / SQL
- Se houver: referência ao runbook e evidência de aplicação

### O que ainda requer ação manual
- HF5 em produção (se pendente)
- Configuração de secrets X, Y
- etc.

### Validação
- Build: ✅
- Tests: ✅
- Smoke: ✅
```

---

## 3. Sincronização com o Project Board

Para que o trabalho apareça no [GitHub Project](https://github.com/users/VitorMRodovalho/projects/1/):

1. **Criar GitHub Issue** para cada incremento significativo (ex.: "Event Delegation: admin + attendance")
2. **Adicionar ao project**: `gh project item-add 1 --owner VitorMRodovalho --url https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/XX`
3. **Committar com referência**: `fix: Event Delegation (#XX)` — o GitHub vincula automaticamente
4. **Atualizar status** no board ao concluir: mover para Done

O workflow `project-governance-sync` faz auditoria periódica; ele não move cards automaticamente — o status no board reflete o que você ou a equipe movem manualmente (ou via `gh project item-edit`).

---

## 4. Repositório de destino

- **Canonico (este clone)**: `VitorMRodovalho/ai-pm-research-hub` via `origin/main`
- **Remote adicional de produção**: opcional. Só usar `production/main` quando o remote `production` existir localmente e estiver validado em `git remote -v`.

---

## 5. Checklist antes de cada release

1. Atualizar `docs/RELEASE_LOG.md` com entrada detalhada
2. Atualizar `package.json` version (opcional, para npm)
3. Criar tag e push
4. Criar GitHub Release com changelog
5. Executar deploy (Cloudflare Workers, etc.) conforme `docs/DEPLOY_CHECKLIST.md`
6. Pós-deploy: smoke em produção, registrar em RELEASE_LOG
