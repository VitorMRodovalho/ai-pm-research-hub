# TRIAGE DE CAMPO — Achados de Uso Real
## 19/Mar/2026 — Feedback de Vitor, Jefferson (T5), Fabricio (Deputy)
## GC-091+

---

## CLASSIFICAÇÃO DE URGÊNCIA

### 🔴 P0 — Quebrado em Produção (bloqueia uso)

| # | Issue | Quem reportou | Erro | Root Cause Provável |
|---|-------|--------------|------|-------------------|
| P0-1 | **Criar Evento falha** | Jefferson (T5) | `Could not choose the best candidate function between public.create_event(...)` — duas assinaturas sobrepostas | Duas versões da RPC `create_event` com tipos de param diferentes (uma com `p_tribe_id => uuid`, outra com `p_tribe_id => integer`). PostgreSQL não resolve ambiguidade. |
| P0-2 | **Criar Série Recorrente falha** | Fabricio | `Could not find the function public.create_recurring_weekly_events(...)` in the schema cache | RPC não existe no banco. Frontend chama função que nunca foi criada ou foi dropada numa migration. |
| P0-3 | **Admin/members não carrega** | Vitor | Tudo zerado, sem dados | Provavelmente relacionado ao fix da RPC `get_member_detail` (B1) — verificar se a migration foi aplicada corretamente e se o frontend consome a resposta no formato esperado. |
| P0-4 | **Relatório do Ciclo falha** | Vitor | "Falha ao gerar relatório do ciclo" | RPC de geração de relatório quebrada — pode ser mesma família de colunas renomeadas (padrão do B1). |
| P0-5 | **Links 404 em vários lugares** | Vitor (apresentação PMI-RS) | 404 em múltiplas páginas | Necessita varredura sistemática de todas as rotas. Pode ser middleware novo (B4) bloqueando rotas que não deveria, ou rotas que nunca existiram. |

### 🟡 P1 — Funcionalidade Incompleta (impacta operação)

| # | Issue | Detalhe |
|---|-------|---------|
| P1-1 | **Permissões Tier ≤3 restritas demais** | Líderes, Patrocinadores e GP não acessam: Portfolio Executivo, gestão de Tribos, e outros painéis que deveriam ser read-only para eles. Reavaliação de `permissions.ts` necessária. |
| P1-2 | **Portfolio Executivo: filtros não propagam** | Filtrar por tribo não atualiza KPI cards superiores. Filtro é cosmético, não funcional. |
| P1-3 | **Portfolio/Boards: sem alerta de atraso** | Artefatos com baseline ou forecast anterior a hoje não mostram indicador de atraso. Sem visibilidade de overdue. |
| P1-4 | **Parcerias: CRUD incompleto** | Não é possível criar nova parceria nem editar existentes via frontend. Dados foram inseridos direto no banco. Frontend não tem formulário de criação/edição. |
| P1-5 | **Pilotos: CRUD incompleto** | Não é possível criar novo piloto nem editar via frontend. Dados parciais (nem tudo que está no banco aparece na UI). Verificar: quem vê? Quem edita? Tiers de acesso. |
| P1-6 | **Processo Seletivo: múltiplos problemas** | (a) Nada é editável. (b) Snapshot tem duplicações. (c) Falta agrupamento por nome (mostrar último status). (d) Faltam colunas de indicadores de impacto (CPMAI pós-núcleo, membrezia PMI por conta do núcleo, filiação a capítulo). (e) Falta seção de requisitos/jornada do candidato. (f) Não filtra por capítulo. (g) João está como pesquisador mas sem contrato — feature de jornada pendente. |
| P1-7 | **Líder de tribo sem permissão de ajustar presenças passadas** | Líder não consegue corrigir presenças de reuniões passadas da sua tribo. Necessário para accountability. |

### 🟢 P2 — Melhoria / Polishing

| # | Issue | Detalhe |
|---|-------|---------|
| P2-1 | **Termo "CoP" aparecendo no site** | Vários lugares usam "CoP" em vez de "Tribos"/"Research Streams". Varredura e substituição necessária. |
| P2-2 | **Tribe Dashboard (/tribe/[id]): visão de gamificação** | Líderes precisam ver: (a) XP sintético por tribo, (b) XP analítico por membro da tribo, (c) Trilha/certificações por membro. |
| P2-3 | **Tribe Dashboard: visão de presença** | Líderes precisam ver: (a) Rank sintético por tribo, (b) Grid analítico por membro × reunião (cronológico). Colunas: Geral, Tribo, Liderança. Membros não listados para uma reunião = "N/A" ou "-". |
| P2-4 | **Admin/members: filtros não propagam nos resumos** | Se filtrar por dimensão (tribo, capítulo, etc.), os KPI cards superiores devem refletir o filtro. |

---

## INVESTIGAÇÃO NECESSÁRIA

### P0-1: create_event — Resolução de Ambiguidade

```text
Claude Code prompt:

DIAGNOSTIC — Fix create_event RPC ambiguity.

Error: "Could not choose the best candidate function between:
  public.create_event(p_type => text, p_title => text, p_date => date, p_duration_minutes => integer, p_tribe_id => uuid, p_audience_level => text),
  public.create_event(p_type => text, p_title => text, p_date => date, p_duration_minutes => integer, p_tribe_id => integer, p_audience_level => text)"

1. Find all versions of create_event in migrations:
   grep -rn "CREATE.*FUNCTION.*create_event" supabase/migrations/ --include="*.sql"

2. Check current state in DB:
   SELECT proname, proargtypes, pronargs 
   FROM pg_proc WHERE proname = 'create_event';

3. The fix: DROP the version with p_tribe_id => integer (legacy), keep only uuid version.
   Create migration: DROP FUNCTION IF EXISTS create_event(text, text, date, integer, integer, text);

4. Verify frontend sends UUID for tribe_id:
   grep -rn "create_event" src/ --include="*.tsx" --include="*.ts" --include="*.astro"

Commit: "fix: drop legacy create_event overload (integer tribe_id)"
```

### P0-2: create_recurring_weekly_events — Função Ausente

```text
Claude Code prompt:

DIAGNOSTIC — Fix missing create_recurring_weekly_events RPC.

Error: "Could not find the function public.create_recurring_weekly_events(...) in the schema cache"

1. Check if function exists in any migration:
   grep -rn "create_recurring_weekly_events" supabase/migrations/ --include="*.sql"

2. Check if function exists in DB:
   SELECT proname FROM pg_proc WHERE proname = 'create_recurring_weekly_events';

3. Check frontend call to understand expected signature:
   grep -rn "create_recurring_weekly_events" src/ --include="*.tsx" --include="*.ts" --include="*.astro"

4. If function was never created: create migration with the RPC.
   If function was dropped: recreate it.

   Expected logic (from UI):
   - Takes: p_title_template, p_type, p_audience_level, p_tribe_id, 
     p_duration_minutes, p_start_date, p_n_weeks, p_meeting_link, p_is_recorded
   - Creates N events (one per week) using title template with {n} for week number and {date} for date
   - Returns array of created event IDs

Commit: "fix: create missing create_recurring_weekly_events RPC"
```

### P0-5: Links 404 — Varredura Sistemática

```text
Claude Code prompt:

DIAGNOSTIC — Find all broken internal links.

1. Extract all internal hrefs from the codebase:
   grep -rn 'href="/' src/ --include="*.tsx" --include="*.ts" --include="*.astro" | 
   grep -oP 'href="(/[^"]*)"' | sort -u

2. Extract all defined routes:
   ls src/pages/**/*.astro | sed 's|src/pages||;s|\.astro||;s|/index||'

3. Cross-reference: which hrefs don't have matching routes?

4. Also check: does the new SSR middleware (B4) accidentally block any routes?
   grep -n "redirect" src/middleware/index.ts

5. Report all mismatches.

DO NOT fix yet — just report the list.
```

### P0-3: Admin/Members Zerado

```text
Claude Code prompt:

DIAGNOSTIC — Admin/members page loading empty.

1. Check what RPC the members list calls:
   grep -rn "admin.*member\|list.*member\|get.*member" src/components/admin/members/ --include="*.tsx"

2. Check if the RPC works directly:
   Run via Supabase SQL editor: SELECT * FROM admin_list_members() LIMIT 5;

3. Check if the new middleware (B4) is interfering with the API calls.

4. Check browser console for specific error messages.

Report findings — may be related to search_path hardening (B3) changing function behavior.
```

---

## ANÁLISE DE PERMISSÕES (P1-1)

### Estado Atual vs. Desejado

| Painel | Tier 1 (GP) | Tier 2 (Deputy/Curator) | Tier 3 (Leaders/Sponsors) | Tier 4+ (Researchers) |
|--------|------------|----------------------|--------------------------|---------------------|
| Portfolio Executivo | ✅ Edit | ✅ Edit | ❌ **Deveria: 👁️ View** | ❌ Correto |
| Tribos (gestão) | ✅ Edit | ✅ Edit | ❌ **Deveria: 👁️ Own tribe** | ❌ Correto |
| Pilotos | ✅ Edit | ✅ Edit | ❌ **Deveria: 👁️ View** | ❌ Correto |
| Parcerias | ✅ Edit | ✅ Edit | ❌ **Deveria: 👁️ View** | ❌ Correto |
| Processo Seletivo | ✅ Edit | ✅ Edit | ❌ **Deveria: 👁️ View** | ❌ Correto |
| Cycle Report | ✅ View | ✅ View | ❌ **Deveria: 👁️ View** | ❌ Correto |

**Ação:** Rever `permissions.ts` — Tier 3 (tribe_leader + stakeholder) deve ter acesso read-only a painéis executivos. Atualmente provavelmente está como `['manager', 'deputy_manager']` e precisa incluir os tiers corretos.

---

## PRIORIZAÇÃO DE EXECUÇÃO

### Sprint Imediata (Bloqueante)

| Ordem | Item | Esforço | Impacto |
|-------|------|---------|---------|
| 1 | P0-1 + P0-2: Fix RPCs de eventos | 1-2h | Desbloqueia Jefferson, Fabricio, e todos os líderes |
| 2 | P0-5: Varredura 404 + fix middleware | 2h | Credibilidade em apresentações |
| 3 | P0-3: Admin/members zerado | 1h | Desbloqueia painel admin |
| 4 | P0-4: Relatório do ciclo | 1h | Desbloqueia reporting |

### Sprint Seguinte

| Ordem | Item | Esforço |
|-------|------|---------|
| 5 | P1-1: Permissões Tier 3 read-only | 3h |
| 6 | P1-2 + P2-4: Filtros propagam em KPIs | 2h |
| 7 | P1-3: Alertas de atraso (overdue) | 2h |
| 8 | P1-4 + P1-5: CRUD Parcerias + Pilotos | 4h cada |
| 9 | P1-6: Processo Seletivo overhaul | 6-8h (spec separada) |
| 10 | P1-7: Líder ajusta presenças passadas | 2h |

### Backlog

| Item | Esforço |
|------|---------|
| P2-1: Substituir "CoP" em todo o site | 1h |
| P2-2: Tribe dashboard gamificação | 4h |
| P2-3: Tribe dashboard presença grid | 4h |

---

## REUNIÃO PMI-RS

Vitor mencionou que a reunião com o ponto focal do PMI-RS está no Google Calendar. Para registrar:

- **Contexto:** Apresentação da plataforma para PMI-RS durante a qual 404s foram encontrados
- **Ação:** Verificar no Google Calendar detalhes da reunião para registro no portal

---

## LIÇÕES APRENDIDAS (desta triage)

1. **Ambiguidade de RPC é silenciosa até o uso real.** Duas versões da mesma função com tipos diferentes coexistem sem erro até alguém chamar. Checklist: após refatorar uma RPC, verificar se existe versão anterior e DROPar.

2. **Frontend chama RPCs que não existem.** O frontend de eventos recorrentes foi construído assumindo que a RPC existiria. Se a RPC não foi criada ou foi dropada, o erro só aparece em uso. Checklist: todo formulário frontend deve ter smoke test que verifica existência da RPC.

3. **Middleware novo pode causar 404 colateral.** O SSR middleware (B4) pode estar interferindo em rotas que antes funcionavam. Precisa de varredura pós-deploy.

4. **Permissões restritivas demais são tão ruins quanto permissivas demais.** Líderes sem visibilidade = líderes sem accountability = líderes desengajados.

5. **Apresentação ao vivo é o melhor QA.** Três pessoas usando o site em contextos diferentes encontraram mais bugs em 1 hora do que specs e testes em 1 semana.

---

*Triage gerada em 19/Mar/2026. Prioridade: P0-1 e P0-2 são bloqueantes para líderes de tribo.*
