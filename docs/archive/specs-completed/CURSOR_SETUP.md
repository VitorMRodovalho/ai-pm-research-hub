# Cursor — Primeiro uso no AI & PM Hub

Checklist para configurar o Cursor e começar a trabalhar no projeto.

## Fluxo rápido (clone → run)

```bash
cd /caminho/para/ai-pm-research-hub
cp .env.example .env
# Edite .env: PUBLIC_SUPABASE_URL e PUBLIC_SUPABASE_ANON_KEY
npm install
npm run build
npm run dev -- --host 0.0.0.0 --port 4321
```

Acesse `http://localhost:4321`. Tempo estimado: < 15 min (com Supabase já criado).

## 1. Abrir o projeto

```bash
cd /caminho/para/ai-pm-research-hub
cursor .
```

Ou: **File → Open Folder** e escolher a pasta do repositório.

## 2. Verificar regras ativas

- **Cursor Settings → Rules**: As regras em `.cursor/rules/` devem aparecer automaticamente.
- Se não aparecerem, confira se a pasta `.cursor/rules/` existe e contém os arquivos `.mdc`.

Regras esperadas:

| Regra | Quando aplica |
|-------|----------------|
| project-context | Sempre |
| astro-frontend | Ao editar `.astro`, `.ts`, `.tsx` |
| sql-migrations | Ao editar `.sql` |
| edge-functions | Ao editar `supabase/functions/**/*.ts` |

## 3. Variáveis de ambiente

```bash
cp .env.example .env
```

Preencha em `.env`:

| Variável | Obrigatório | Onde obter |
|----------|-------------|------------|
| `PUBLIC_SUPABASE_URL` | Sim | Supabase Dashboard → Project Settings → API |
| `PUBLIC_SUPABASE_ANON_KEY` | Sim | Idem (anon public) |

Opcional (admin/analytics, dashboards): veja `.env.example` — cada variável está documentada.

**Replicando para outro projeto?** Consulte `docs/REPLICATION_GUIDE.md`.

## 4. Instalar e validar

```bash
npm install
npm run build
npm test
npm run smoke:routes
```

## 5. Rodar localmente

```bash
npm run dev -- --host 0.0.0.0 --port 4321
```

Acesse `http://localhost:4321`.

## 6. Onde está o board de sprints

- **GitHub Project**: [https://github.com/users/VitorMRodovalho/projects/1/](https://github.com/users/VitorMRodovalho/projects/1/)
- Use o board para ver itens em `Backlog`, `Ready`, `In progress`.
- Leia **docs/project-governance/PROJECT_GOVERNANCE_RUNBOOK.md** para como pegar trabalho e referenciar issues.

## 7. Ao usar o Chat/Agent

- O Cursor usa **AGENTS.md** e as regras de `.cursor/rules/` como contexto.
- Para decisões de produto, schema ou governança, mencione explicitamente: "conforme docs/GOVERNANCE_CHANGELOG.md" ou "ver docs/MIGRATION.md".
- Após mudanças que afetem produção, atualize `docs/RELEASE_LOG.md`.

## 8. Dicas

- **@AGENTS.md** — Incluir contexto do projeto no prompt.
- **@docs/arquivo.md** — Incluir um doc específico na conversa.
- **Cursor Settings → General → Rules for AI** — Ver regras globais vs. regras do projeto.
