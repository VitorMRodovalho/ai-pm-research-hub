# Sprint 6 Backlog — Consolidation + MCP Adoption + Dependency Health

**Data:** 2026-03-30
**Contexto:** Sprint 5 entregou o conector MCP Claude.ai (23 tools funcionando). Sprint 6 foca em consolidar, adotar, e reduzir risco de dívida técnica.

---

## Priorização

| Prio | ID | Item | Tipo | Esforço | Deps |
|------|----|------|------|---------|------|
| **P0** | S6.1 | MCP write tools validation | QA | 1h | — |
| **P0** | S6.2 | Attendance cross-tribe fix (#1) | Bug | 2-4h | Análise |
| **P1** | S6.3 | MCP adoption baseline | Feature | 1h | S6.1 |
| **P1** | S6.4 | Designation filter em /teams e /attendance (#7) | Feature | 2-3h | — |
| **P1** | S6.5 | Astro 6.0.8 → 6.1.1 upgrade | Chore | 1h | — |
| **P2** | S6.6 | ChatGPT MCP connector test | QA | 1h | — |
| **P2** | S6.7 | Cursor/VS Code MCP integration test | QA | 30m | — |
| **P2** | S6.8 | Unused npm deps cleanup | Chore | 15m | — |
| **P3** | S6.9 | Zod version lock analysis | Research | 30m | — |
| **P3** | S6.10 | Major deps upgrade assessment | Research | 1h | — |
| **P3** | S6.11 | MCP new tools candidates | Research | 30m | — |
| **P3** | S6.12 | SDK 1.28.0 Deno compat tracking | Research | 15m | — |

---

## P0 — Must Do

### S6.1 — MCP Write Tools Validation
**Status:** Sprint 5 testou 5 read tools no Claude.ai. Write tools (create_board_card, update_card_status, create_meeting_notes, register_attendance, send_notification_to_tribe, create_tribe_event) ainda NÃO foram testados em produção via Claude.ai.

**Ação:**
1. Abrir Claude.ai com conector nucleo-ia
2. Testar cada write tool com dados reais (ou sandbox):
   - `create_board_card` — criar card de teste na tribo
   - `update_card_status` — mover card para done
   - `register_attendance` — registrar presença em evento recente
   - `create_tribe_event` — criar evento de teste
   - `create_meeting_notes` — criar ata para evento existente
   - `send_notification_to_tribe` — enviar notificação de teste
3. Verificar que `canWrite()` está gatilhando corretamente (testar com membro sem permissão se possível)
4. Verificar logs via `get_adoption_metrics`

**Risco:** Write tools podem ter problemas de Zod validation em parâmetros que não foram testados (e.g., `z.boolean()` para `present` no `register_attendance`).

### S6.2 — Attendance Cross-Tribe Fix (#1)
**Status:** Bug intermitente reportado. `CrossTribeIsland.tsx` (274 linhas) chama `exec_cross_tribe_comparison` RPC. Componente existe e é funcional mas o bug é intermitente — sugere problema de dados ou timing, não de código.

**Análise necessária ANTES de desenvolvimento:**
1. Verificar RPC `exec_cross_tribe_comparison` — quais joins faz, se depende de `tribe_id` não-null
2. Verificar se membros sem `tribe_id` (e.g., managers transversais como Vitor) causam NULLs nos aggregates
3. Verificar se o RPC lida com ciclos corretamente (membros ativos vs inativos)
4. Testar via MCP: `search_board_cards` com query "attendance" para ver se há cards tracking o bug

**Ação se root cause identificado:**
- Se dados: migration para corrigir + trigger guard
- Se RPC: fix no SQL + NOTIFY pgrst

---

## P1 — Should Do

### S6.3 — MCP Adoption Baseline
**Status:** `get_adoption_metrics` tool funciona. `mcp_usage_log` registra todas as chamadas. Primeira medição real de adoção agora é possível.

**Ação:**
1. Executar `get_adoption_metrics` no Claude.ai para capturar baseline
2. Registrar: total de calls, unique members, top tools, error rate
3. Compartilhar snapshot com time (pode usar MCP para gerar o relatório)
4. Definir meta: X members usando MCP até fim do Ciclo 3

### S6.4 — Designation Filter em /teams e /attendance (#7 S3.2)
**Status da análise:**
- `/teams.astro`: **SEM** filtro por designation (grep vazio)
- `/attendance.astro`: Usa `member.designations` apenas para permissão de edição, **NÃO** como filtro de listagem
- `/admin/adoption.astro`: JÁ TEM filtro por designation (dropdown funcional)
- `MemberListIsland.tsx`: JÁ TEM `designationFilter` state + dropdown

**Realidade vs Documentação:** O item diz "designation filter em /teams + /attendance". A análise mostra que `/admin/adoption` e `MemberListIsland` já implementam esse padrão. As páginas `/teams` e `/attendance` não têm.

**Ação:**
1. `/teams.astro`: Adicionar dropdown de designation (ambassador, founder, chapter_liaison, curator, etc.) que filtra a lista de membros
2. `/attendance.astro`: Adicionar mesmo dropdown para filtrar tabela de attendance por designation
3. Reutilizar padrão de `MemberListIsland.tsx` (já comprovado)
4. i18n: keys existem em admin.filter.designation* — verificar se reutilizáveis

### S6.5 — Astro 6.0.8 → 6.1.1
**Status:** `npm outdated` mostra Astro 6.1.1 disponível. É minor version (6.0→6.1), não major.

**Análise necessária:**
1. Ler changelog do Astro 6.1.0 e 6.1.1 — verificar breaking changes
2. Verificar se `@astrojs/cloudflare` 13.1.4 é compatível com Astro 6.1.1

**Ação:**
1. `npm install astro@6.1.1`
2. `npx astro build` + `npm test`
3. Se passar, deploy

---

## P2 — Nice to Have

### S6.6 — ChatGPT MCP Connector Test
**Status:** `MCP_SETUP_GUIDE.md` documenta setup para ChatGPT (beta). Nota: "Known ChatGPT-side issue. The server is compatible."

**Ação:**
1. Seguir steps da doc: Settings → Apps → Connectors → Advanced → New App
2. Testar initialize + tools/list
3. Se funcionar, atualizar doc removendo nota de "beta issue"
4. Se falhar, documentar o erro específico

### S6.7 — Cursor/VS Code MCP Integration Test
**Ação:** Testar OAuth flow via Cursor e/ou VS Code com extensão MCP. Documentar resultado.

### S6.8 — Unused npm Deps Cleanup
**Status:** `DEPENDENCY_AUDIT.md` (Mar/2026) identificou 3 pacotes sem uso: `csv-parse`, `mammoth`, `xlsx`.

**Verificação necessária:** Confirmar que ainda não são importados (podem ter sido adicionados desde a auditoria).

**Ação:**
```bash
npm uninstall csv-parse mammoth xlsx
npx astro build && npm test
```

---

## P3 — Research / Future

### S6.9 — Zod Version Lock Analysis
**Risco:** `npm:zod@3` no EF pode divergir do Zod interno do SDK 1.27.1. Se versões ficarem incompatíveis, tool schemas podem falhar silenciosamente.

**Ação:**
1. Verificar qual versão de Zod o SDK 1.27.1 usa internamente
2. Considerar pinnar versão explícita: `npm:zod@3.23.8` (ou qualquer que o SDK use)
3. Documentar em `.claude/rules/mcp.md`

### S6.10 — Major Deps Upgrade Assessment
**Estado atual vs latest:**

| Package | Current | Latest | Gap | Risco |
|---------|---------|--------|-----|-------|
| @tiptap/* | 2.27.2 | 3.21.0 | **Major** | Rich text editor rewrite. Impacta meeting notes, board descriptions. |
| lucide-react | 0.577.0 | 1.7.0 | **Major** | Icon API pode mudar. Impacta 4 componentes. |
| recharts | 2.15.4 | 3.8.1 | **Major** | Chart API muda. Impacta CommsDashboard.tsx. |
| typescript | 5.9.3 | 6.0.2 | **Major** | Pode quebrar tipos. Impacta todo o projeto. |
| eslint | 9.39.4 | 10.1.0 | **Major** | Config format muda. Impacta eslint.config.mjs. |

**Ação:** Para cada pacote, ler changelog da major version e avaliar:
- Quantos arquivos impactados?
- Há migration guide oficial?
- Vale um sprint dedicado ou pode ser incremental?

**Recomendação preliminar:**
- `lucide-react` v1: provavelmente seguro (tree-shaking, 4 arquivos). Avaliar primeiro.
- `tiptap` v3: alto impacto, precisa de sprint dedicado.
- `recharts` v3: impacta 1 arquivo mas é complexo (CommsDashboard).
- `typescript` v6: testar em branch separada, pode ser simples ou catastrófico.
- `eslint` v10: config migration, esforço médio.

### S6.11 — MCP New Tools Candidates
**Oportunidades identificadas:**
1. `verify_my_credly` — Trigger verificação de badge Credly via MCP
2. `rsvp_webinar` — Confirmar presença em webinar
3. `bulk_register_attendance` — Registrar presença em batch (meeting inteira)
4. `get_tribe_analytics` — Dashboard de métricas da tribo
5. `get_my_action_items` — Action items pendentes de meeting notes

**Ação:** Priorizar por demanda real (usar adoption metrics para guiar).

### S6.12 — SDK 1.28.0 Deno Compat Tracking
**Status:** SDK 1.28.0 falha no Deno por duas razões: mcp.tool() API mudou (requer Zod nativo) e WebStandardStreamableHTTPServerTransport crasha em runtime.

**Ação:**
1. Monitorar releases do SDK no GitHub (@modelcontextprotocol/sdk)
2. Quando sair 1.29+, testar em branch: `npm:@modelcontextprotocol/sdk@1.29.0`
3. Se Zod nativo funcionar, migrar (nossos schemas já são Zod)
4. Se WebStandard funcionar, remover manual SSE wrapping

---

## Alinhamento com Frentes Existentes

| Frente | Status | Impacto Sprint 6 |
|--------|--------|-------------------|
| MCP Connector (#5) | **DONE** Sprint 5 | S6.1, S6.3, S6.6, S6.7 são follow-ups |
| Attendance Cross-Tribe (#1) | Open P0 | S6.2 endereça diretamente |
| Designation Filter (#7 S3.2) | Pendente Sprint 4 | S6.4 endereça diretamente |
| Demo Mario 3/Abr | Prep done | MCP agora demo-ready, S6.1 valida write tools para demo |
| Dep Audit (Mar/2026) | Doc exists | S6.8 executa cleanup, S6.10 mapeia majors |
| SDK Evolution | Tracked | S6.9 + S6.12 mantêm tracking ativo |

---

## Sequência de Execução Recomendada

```
Fase 1 (QA + Bugs):  S6.1 → S6.2 → S6.3
Fase 2 (Features):   S6.4 → S6.5
Fase 3 (Expansion):  S6.6 → S6.7 → S6.8
Fase 4 (Research):   S6.9 → S6.10 → S6.11 → S6.12
```

P0/P1 (Fases 1-2) = ~8-12h de trabalho
P2/P3 (Fases 3-4) = ~4h de pesquisa/testes
