# Contributing — AI & PM Research Hub

Obrigado pelo interesse em contribuir! Este guia explica como participar do desenvolvimento da plataforma.

---

## Antes de começar

1. Leia o [ARCHITECTURE.md](ARCHITECTURE.md) para entender a stack e os padrões
2. Tenha Node.js 22+ instalado (use `nvm use` na raiz do projeto)
3. Solicite acesso ao projeto Supabase (apenas para contribuidores ativos)

---

## Fluxo de trabalho

### 1. Branch

```bash
# Sempre partir de main atualizada
git checkout main
git pull origin main

# Criar branch descritiva
git checkout -b feat/nome-da-feature
# ou: fix/descricao-do-bug
# ou: chore/tarefa-de-manutencao
```

### 2. Desenvolvimento

```bash
npm run dev    # Dev server em localhost:4321
npm test       # Rodar testes antes de commitar
```

### 3. Commit convention

```
feat(scope): descrição curta      # Nova funcionalidade
fix(scope): descrição curta       # Correção de bug
chore(scope): descrição curta     # Manutenção, refactor, docs
```

Scopes comuns: `auth`, `attendance`, `board`, `blog`, `certs`, `gamification`, `i18n`, `admin`, `sentry`, `cron`

### 4. Pull Request

- Descrição clara do que mudou e por quê
- Screenshots se houver mudança visual
- Testes passando (`npm test` + `npx playwright test`)

---

## Regras obrigatórias

### SQL / RPCs

- [ ] Verificar FK targets: `auth.users(id)` vs `members(id)` — são UUIDs diferentes
- [ ] Verificar nomes de coluna contra `information_schema.columns` (ver cheat sheet no ARCHITECTURE.md)
- [ ] Usar `DROP + CREATE`, nunca `CREATE OR REPLACE` via DO blocks
- [ ] Executar `NOTIFY pgrst, 'reload schema'` após criar/alterar RPCs
- [ ] Testar que o RPC retorna dados (não apenas que compila)
- [ ] Para tabelas deny-all: usar `.rpc()`, nunca `.from()`

### Frontend

- [ ] Chart.js: sempre `maintainAspectRatio: false` + container com height fixo
- [ ] Dark mode: textos usam CSS variables ou check `isDark`
- [ ] Sem props undefined no render
- [ ] Event delegation: sempre `if (!(e.target instanceof HTMLElement)) return;`

### i18n (OBRIGATÓRIO)

- [ ] **Toda** string user-facing existe em PT-BR, EN-US E ES-LATAM
- [ ] Nenhuma raw key visível na UI (patterns como `word.word.word`)
- [ ] Testar nas 3 rotas: `/`, `/en/`, `/es/`

### Rotas

- [ ] Toda página nova existe em 3 locale paths (`/`, `/en/`, `/es/`)

### Build

- [ ] `npm run build` → 0 erros
- [ ] Abrir a página no browser e confirmar que dados carregam
- [ ] Testar em dark mode
- [ ] Se role-gated: testar como GP, Leader e Researcher

---

## Terminologia

| ❌ Não usar | ✅ Usar |
|------------|---------|
| CoP, Community of Practice | Tribo (PT) / Research Stream (EN) / Línea de Investigación (ES) |
| Ata | Registro de reunião |
| Votos | Deliberações |
| Membros (em contexto associativo) | Pesquisadores, voluntários |
| Associação | Projeto, iniciativa |

---

## Estrutura de testes

```bash
tests/
├── unit/          # Vitest — lógica, utils, formatação
├── e2e/           # Playwright — 8 jornadas críticas
└── fixtures/      # Dados de teste
```

Para adicionar um teste e2e:
```bash
npx playwright codegen http://localhost:4321
# Gera o teste interativamente
```

---

## Migrations

As migrations ficam em `supabase/migrations/`. Se você aplicar SQL diretamente no Supabase Dashboard:

```bash
# 1. Criar arquivo de migration com o SQL aplicado
touch supabase/migrations/YYYYMMDDHHMMSS_descricao.sql

# 2. Marcar como já aplicada
npx supabase migration repair YYYYMMDDHHMMSS --status applied

# 3. Verificar alinhamento
npx supabase migration list
```

**Nunca** rodar `db push` sem verificar `migration list` antes.

---

## Dúvidas

Contato: Vitor Maia Rodovalho (GP) — via plataforma ou WhatsApp do Núcleo.
