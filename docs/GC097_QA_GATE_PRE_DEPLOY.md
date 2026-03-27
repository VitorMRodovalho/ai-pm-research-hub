# DECISÃO DE GOVERNANÇA: QA Gate Pré-Deploy
## GC-097 — Pre-Deploy Validation Gate

> **Date:** 20/Mar/2026
> **Trigger:** Ciclo repetido de deploy→falha→hotfix→deploy em 3+ entregas consecutivas
> **Decisão por:** GP (Vitor)
> **Status:** PROPOSTA — aguardando aprovação

---

## 1. DIAGNÓSTICO DO PROBLEMA

### Padrão observado (últimas 2 sessões):

| Entrega | O que falhou em prod | Como foi encontrado | Deveria ter sido pego por |
|---------|---------------------|--------------------|-----------------------|
| RPCs P0 (GC-091) | 8 colunas inexistentes | HAR em campo (Jefferson, Fabricio, Vitor) | Smoke test de cada RPC |
| Dark mode (GC-090) | 45 bugs visuais | Inspeção manual | Checklist visual por tema |
| GC-095 create_event | FK violation (auth.uid vs member.id) | Jefferson em prod | Teste funcional: criar evento como líder |
| GC-095 i18n | `attendance.modal.advanced` raw | Screenshot em prod | Grep por keys não traduzidas |
| Blog EN/ES | 404 em /en/blog, /es/blog | Crawl sistemático (esta sessão) | Checklist de rotas por locale |
| Privacy EN/ES | 404 em /en/privacy, /es/privacy | Crawl sistemático | Mesmo checklist |
| Hero section | Horário raw, stats, email errado | Jefferson em prod | Smoke test autenticado |

### Root cause:
- **CI testa build e tipos, não comportamento.** 590 testes passam, mas nenhum teste simula "líder cria evento" ou "visitante EN acessa blog".
- **Claude Code não tem contexto de banco.** Ele escreve SQL sintaticamente correto mas semanticamente errado (ex: `auth.uid()` vs `members.id`) porque não consulta o schema real.
- **Não existe smoke test pós-deploy.** O merge vai direto para produção via Cloudflare Workers auto-deploy.
- **O GP é o QA.** Vitor e Jefferson estão encontrando bugs que um checklist de 5 minutos pegaria.

---

## 2. PROPOSTA: PRE-DEPLOY VALIDATION GATE

### Princípios:
- **Leve, não burocrático** — 5-10 minutos, não 2 horas
- **Automatizável incrementalmente** — começa manual, evolui para script
- **Bloqueia deploy, não desenvolvimento** — Code pode commitar, mas merge/deploy só após gate
- **Focado em jornadas, não em cobertura** — 8 personas × ação principal

### Gate consiste em 3 camadas:

#### Camada 1: Pre-Commit (Claude Code deve fazer ANTES de commitar)
```
□ SQL: Verificar FK constraints das tabelas tocadas
  → SELECT constraint_name, column_name FROM information_schema... WHERE table_name = 'X'
□ SQL: Testar RPC nova/modificada com dados reais
  → SELECT create_event(...) com parâmetros de teste, verificar retorno
□ i18n: Grep por keys sem tradução
  → grep -r "'\w+\.\w+\.\w+'" src/ | grep -v "import\|const\|//"  (patterns suspeitos)
□ Rotas: Para cada locale (PT/EN/ES), verificar se a página existe
  → ls src/pages/en/X src/pages/es/X (se X foi criado/modificado)
```

#### Camada 2: Pre-Deploy Smoke Test (GP ou deputy, 5 min)
```
PERSONA: Visitante anônimo
□ Homepage carrega (PT-BR, EN, ES)
□ Nav links não dão 404
□ Stats carregam (ou "--" aceitável)

PERSONA: Pesquisador (tier normal)
□ Login funciona
□ Workspace carrega
□ Funcionalidade tocada neste deploy funciona

PERSONA: Líder de tribo
□ Login funciona
□ Funcionalidade tocada neste deploy funciona
□ Pode criar evento (se eventos foram tocados)
□ Pode registrar presença (se attendance foi tocada)

PERSONA: GP/Superadmin
□ Admin carrega
□ Funcionalidade tocada neste deploy funciona
□ Dashboard KPIs carregam
```

**Regra:** Só testar as personas afetadas pela mudança. Se só mexeu em i18n, testa visitante anônimo nos 3 locales. Se mexeu em RPC de evento, testa líder criando evento.

#### Camada 3: Post-Deploy Verification (1 min, automação futura)
```
□ Homepage retorna 200 (curl)
□ /en/ retorna 200
□ /es/ retorna 200
□ No new Sentry errors in last 5 min
□ PostHog session replay mostra página carregando
```

---

## 3. COMO IMPLEMENTAR NO WORKFLOW ATUAL

### Fase 1: Imediata (esta sessão)
- **Spec inclui "Definition of Done" com smoke tests específicos** ✅ (já fazemos)
- **Prompt para Claude Code inclui:** "Antes de commitar, rode estas verificações: [lista]"
- **GP faz smoke test de 5 min antes de aprovar merge** (manual)

### Fase 2: Próximo sprint
- **Script `scripts/smoke-test.sh`** que:
  - Faz curl nas rotas principais (3 locales)
  - Verifica status codes
  - Grep por i18n keys não traduzidas no build output
  - Roda no CI como step pós-build, pré-deploy

### Fase 3: Ciclo 4
- **Playwright e2e tests** para as 4 personas:
  - Visitante anônimo → homepage → nav → blog → library
  - Pesquisador → login → workspace → tribe
  - Líder → login → criar evento → check-in
  - GP → login → admin → dashboard → criar evento global
- **Roda no CI** como gate antes do deploy

---

## 4. REGRA PARA CLAUDE CODE (adicionar ao prompt base)

```
ANTES DE COMMITAR qualquer mudança:

1. Se tocou em SQL/RPC:
   - Verificar FK constraints: SELECT constraint_name FROM information_schema.table_constraints WHERE table_name = 'X'
   - Testar a RPC com um SELECT/CALL real contra o banco
   - Verificar que auth.uid() vs members.id está correto para cada FK

2. Se tocou em i18n:
   - Verificar que TODA key nova existe nos 3 locales (PT, EN, ES)
   - Grep por strings que parecem keys não traduzidas no output

3. Se criou/modificou rotas:
   - Verificar que a rota existe para os 3 locales
   - Se só PT-BR existe, criar redirect pages para EN/ES

4. Se tocou em componente React:
   - Verificar que não há props undefined no render
   - Verificar que dark mode classes existem

5. SEMPRE: Rodar build local (npm run build) e verificar 0 errors
```

---

## 5. IMPACTO ESPERADO

| Métrica | Antes | Depois (esperado) |
|---------|-------|-------------------|
| Hotfixes pós-deploy por sessão | 2-4 | 0-1 |
| Bugs encontrados por usuários | 5+ | 1-2 (edge cases) |
| Tempo de validação por deploy | 0 min (skip) | 5-10 min |
| Confiança do GP no deploy | Baixa | Alta |
| Confiança dos líderes na plataforma | Erodida | Restaurada |

---

## 6. DECISÃO

**O QA gate pré-deploy é obrigatório a partir de agora.**

- Fase 1 (manual) entra em vigor imediatamente
- Claude Code recebe as regras de pre-commit no prompt
- GP faz smoke test de 5 min antes de aprovar cada merge
- Specs futuras incluem smoke tests específicos na "Definition of Done"
- Script automatizado (`smoke-test.sh`) é item do próximo sprint

**GC-097 registrado.**
