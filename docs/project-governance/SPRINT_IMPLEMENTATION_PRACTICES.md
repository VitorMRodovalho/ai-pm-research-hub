# Boas Práticas de Implementação de Sprints

**Objetivo**: O assistente (Cursor) decide a ordem e o modo de execução das sprints seguindo um critério explícito, alinhado ao `ROADMAP_SEQUENCIAL_AGRUPADO.md` e ao `PROJECT_GOVERNANCE_RUNBOOK.md`.

---

## 1. Ordem de prioridade ao escolher "o que fazer"

### 1.1. Bloqueadores primeiro (P0 Foundation)

Antes de qualquer feature nova:

1. **Regressões críticas** — Se houver bug ou falha em produção (profile, auth, tribes, gamification), priorizar correção.
2. **Pendências P0** — Items do EPIC #47 em aberto (HF5, smoke, estabilização).
3. **Dependências manuais** — Issues #56, #57, #58 e similares que exijam ação humana devem ficar documentadas; o assistente prepara runbooks e deixa explícito "aguardando execução em prod".

### 1.2. Concluir sprints parcialmente entregues

Sprints com status **Partial** têm prioridade sobre novas features planejadas. Completar uma Partial antes de abrir nova:

- `S-PA1` → consent/analytics polish
- `S11` → empty states restantes / polish
- `S-REP1` → VRMS/PMI export completo
- `S-AN1` → optional rich editor / scheduling UX
- `S-COM6` → deploy sync-comms-metrics + secrets
- `S10` → Credly Auto Sync config (secrets no GitHub)

### 1.3. Wave em ordem (P0 → P1 → P2 → P3)

Depois de P0 estável e Partials fechados:

- **P1 Comms** (#48): Comms Operating System end-to-end
- **P2 Knowledge** (#49): Knowledge Hub (S-KNW1..S-KNW5)
- **P3 Scale** (#50): Multi-tenant, API, FinOps

Nenhuma tarefa avança sem vínculo com EPIC pai e dependências explícitas.

---

## 2. Critérios para entrar em desenvolvimento

Antes de `In progress`:

| Critério | O que fazer |
|----------|-------------|
| **EPIC pai** | Item filho deve estar vinculado à issue do EPIC (#47, #48, #49 ou #50) |
| **Dependências** | Front sem backend/API/SQL pronto → ficar em `Ready` ou `Backlog` |
| **Entry/exit** | Critérios de entrada e saída definidos (no backlog ou na issue) |
| **SQL-impact** | Migrations em `supabase/migrations/` + pack docs (apply/audit/rollback) antes de Done |

---

## 3. Ao concluir uma tarefa

Seguir `docs/AGENT_BOARD_SYNC.md`:

- [ ] Código alterado e `npm run build` OK
- [ ] `docs/RELEASE_LOG.md` — entrada com escopo, entregue, validação
- [ ] Commit referenciando issue (`fix: desc (#NN)`)
- [ ] Issue/Project Board — mover para Done quando aplicável
- [ ] `backlog-wave-planning-updated.md` — atualizar status do item

---

## 4. Decisão de "próxima sprint" (fluxo prático)

```
1. Há regressão crítica em prod? → Correção imediata
2. Há item Partial prioritário (Wave 3/4)? → Completar esse item
3. P0 tem pendência (HF5, smoke, etc.)? → Resolver P0
4. P1/P2/P3 tem item Ready com dependências atendidas? → Iniciar item
5. Caso contrário → Não avançar; documentar bloqueio ou sugerir preparação (ex: runbook, specs)
```

---

## 5. Evitar

- Iniciar nova feature sem concluir Partial em andamento (exceto urgência P0)
- Avançar front sem backend/API/SQL pronto
- Marcar Done sem migration pack quando houve mudança de schema
- Esquecer RELEASE_LOG ou Board sync ao entregar produção

---

## Resumo

- **Ordem**: Regressão → P0 → Partials → P1 → P2 → P3  
- **Gate**: EPIC pai + dependências + entry/exit + SQL pack  
- **Encerramento**: Build OK + RELEASE_LOG + Board + backlog atualizado  
