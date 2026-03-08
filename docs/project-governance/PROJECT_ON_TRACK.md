# Projeto em Trilha — Análise de Integridade e Roadmap Corrigido

**Data:** 2026-03-08  
**Objetivo:** Colocar o projeto on track, eliminar camadas frágeis, conectar DB ↔ Frontend ↔ API e parar features falhando ou incompletas.

---

## 1. Discussão de Time Sênior (Simulada)

### Visão do Sponsor / Produto
- **Problema:** Features entregues parcialmente; pesquisadores encontram "Seleção encerrada" incorreto, trilha vs gamificação dessincronizados, abas em loading infinito.
- **Expectativa:** Um Hub que funciona de ponta a ponta — dados reais, sem mock, sem deadlocks, sem drift entre telas.
- **Regra de ouro:** *Feature de frontend sem backend/API/SQL pronto não avança para desenvolvimento.*

### Visão do Engenheiro de Dados (Backend/DB)
- **Tabelas órfãs:** `change_requests`, `knowledge_assets`, `knowledge_chunks`, `knowledge_insights`, `presentations`, `member_chapter_affiliations`, `global_links`, `comms_metrics_publish_log` — sem consumo no frontend.
- **Views/RPCs não utilizados:** `impact_hours_summary`, `recurring_event_groups`, `knowledge_search`, `knowledge_insights_overview`, `publish_comms_metrics_batch`.
- **Riscos:** `hub_resources` vs `knowledge_assets` — dois modelos paralelos (admin CRUD vs sync); inconsistência `author_id` vs `member_id` em artifacts.
- **Ação:** Definir fonte única; conectar ou descontinuar objetos órfãos; migrar para tabela de ciclos/configuração em vez de hardcode.

### Visão do Frontend Sênior
- **Dados estáticos demais:** `data/tribes.ts`, `data/kpis.ts`, `data/trail.ts`, `ResourcesSection.astro` inline — quebram ao mudar ciclo.
- **Edge functions ausentes no repo:** `sync-credly-all` e `sync-attendance-points` são invocados mas não existem em `supabase/functions/` — risco de deploy irreproduzível.
- **Fallbacks perigosos:** `2030-12-31` como deadline quando `home_schedule` vazio.
- **Ação:** Tudo que muda com ciclo/deadline vem de DB ou config injetável; edge functions versionadas no repo.

### Visão do Backend / DevOps
- **Integração incompleta:** Knowledge Hub (tabelas + sync) sem UI; Comms dashboard parcial.
- **Workflows órfãos:** `sync-credly-all` chamado por GitHub Action e gamification.astro mas código não está no repositório.
- **Ação:** Trazer `sync-credly-all` e `sync-attendance-points` para o repo; garantir deploy via CI.

---

## 2. Mapa de Integração (DB ↔ Frontend ↔ API)

### ✅ Integrado e funcionando

| Área | Tabelas/RPCs | Frontend | Edge / API |
|------|--------------|----------|------------|
| Members | members, get_member_by_auth, admin_list_members | profile, admin, TribesSection, TeamSection | — |
| Gamification | gamification_points, gamification_leaderboard, course_progress, tribe_selections | gamification.astro | verify-credly |
| Attendance | events, attendance, impact_hours_total, member_attendance_summary | attendance.astro | — |
| Tribes | tribes, tribe_selections, tribe_meeting_slots | TribesSection, admin | — |
| Artifacts | artifacts | artifacts.astro, profile, admin | — |
| Home/Deadline | home_schedule | HeroSection, TribesSection, index | — |
| Admin Comms | comms_metrics_latest_by_channel | admin/comms | sync-comms-metrics |
| Exec Analytics | exec_funnel_summary, exec_cert_timeline, exec_skills_radar | admin/index | — |

### ❌ DB sem frontend (órfãos)

| Objeto | Tipo | Ação sugerida |
|--------|------|---------------|
| change_requests | Tabela | Definir use case ou descontinuar |
| knowledge_assets, knowledge_chunks, knowledge_insights | Tabelas | Wave 5 Knowledge Hub — planejar UI |
| presentations | Tabela | Conectar a ciclo ou descontinuar |
| member_chapter_affiliations | Tabela | Migrar de members.chapter ou documentar |
| global_links | Tabela | Conectar ResourcesSection ou remover |
| impact_hours_summary | View | Usar em relatório ou remover |
| recurring_event_groups | View | Usar em attendance ou remover |
| publish_comms_metrics_batch | RPC | Usar em admin/comms ou documentar |

### ❌ Frontend sem API finalizada / mock

| Local | Problema |
|-------|----------|
| gamification.astro | Invoca `sync-attendance-points` e `sync-credly-all` — funções **não existem no repo** |
| ResourcesSection.astro | Array hardcoded; deveria usar `hub_resources` ou `global_links` |
| data/tribes.ts, data/kpis.ts, data/trail.ts | Fonte estática; ciclos/datas em `admin/constants.ts` |
| admin/index.astro | Filtros `'2026-01-01'` e mapa de ciclos hardcoded |

---

## 3. Edge Functions — Lacuna crítica

| Função | Chamada de | Existe no repo? |
|--------|------------|-----------------|
| verify-credly | profile.astro | ✅ |
| sync-comms-metrics | GitHub Action, external | ✅ |
| sync-knowledge-insights | GitHub Action | ✅ |
| **sync-credly-all** | gamification.astro, credly-auto-sync.yml | ❌ **ausente** |
| **sync-attendance-points** | gamification.astro | ❌ **ausente** |

**Impacto:** Botões em /gamification disparam funções que podem estar deployadas em produção mas não versionadas. Regressão e auditoria impossíveis.

---

## 4. Roadmap Reorganizado por Batch

### Batch 1 — Foundation Gate (P0) — **Bloqueador**
**Objetivo:** Eliminar camadas frágeis e lacunas de código.

| Item | Descrição | Owner sugerido |
|------|-----------|----------------|
| F1 | Trazer `sync-credly-all` e `sync-attendance-points` para `supabase/functions/` (ou documentar deploy externo) | Backend |
| F2 | Tabela `config_cycles` ou `group_cycles`: `code`, `label`, `start`, `end`; migrar hardcode de admin/constants | Dados |
| F3 | `home_schedule` como fonte única para deadline; validar `select_tribe` no RPC com `selection_deadline_at` | Backend |
| F4 | Revisar `author_id` vs `member_id` em artifacts; unificar schema | Dados |

### Batch 2 — Comms Operating System (P1)
**Objetivo:** Cadeia fim-a-fim de comunicação.

| Item | Descrição |
|------|-----------|
| C1 | Conectar `comms_metrics_publish_log` e RPC `publish_comms_metrics_batch` ao admin/comms |
| C2 | Deploy sync-comms-metrics em produção (se ainda pendente) |

### Batch 3 — Knowledge Hub (P2)
**Objetivo:** Dados → Produto → Assistente.

| Item | Descrição |
|------|-----------|
| K1 | Decisão: `hub_resources` (admin CRUD) ou `knowledge_assets` (sync) como fonte principal |
| K2 | Rota `/workspace` ou `/knowledge` consumindo `knowledge_assets_latest` / `knowledge_search` |
| K3 | Conectar `ResourcesSection` a `hub_resources` ou `global_links` |

### Batch 4 — Dados Órfãos e Limpeza (P2.5)
**Objetivo:** Conectar ou descontinuar.

| Item | Objeto | Ação |
|------|--------|------|
| O1 | change_requests | Definir backlog ou marcar deprecated |
| O2 | presentations | Conectar a ciclo ou remover |
| O3 | member_chapter_affiliations | Documentar relação com members.chapter |
| O4 | global_links | Conectar ResourcesSection ou remover |

---

## 5. Pontos Frágeis por Batch

### Batch 1 (Foundation)
- **sync-credly-all / sync-attendance-points fora do repo:** risco de perda, rollback impossível.
- **Hardcode de ciclo:** admin, TribesSection, HeroSection, profile — mudança de ciclo exige toque em 5+ arquivos.
- **Fallback 2030-12-31:** mascara ausência de `home_schedule`; usuário vê "disponível" quando deveria ver erro.

### Batch 2 (Comms)
- **comms_metrics:** ingestão e publicação separadas; se batch falhar, UI pode mostrar dados antigos sem aviso.

### Batch 3 (Knowledge)
- **Dois modelos:** `hub_resources` e `knowledge_assets` — risco de duplicação e drift.
- **Sem UI:** conhecimento ingerido mas invisível ao usuário.

### Batch 4 (Órfãos)
- **Objetos sem dono:** acumulam schema e custo sem valor mensurável.

---

## 6. Regras de Governança (Obrigatórias)

1. **Nenhum frontend sem backend pronto:** Item não entra em `In progress` sem RPC/tabela/edge function disponível.
2. **Edge functions versionadas:** Todas as funções invocadas devem existir em `supabase/functions/`.
3. **Ciclo/config em DB:** Nenhum `'2026-01-01'`, `MAX_SLOTS` ou label de ciclo hardcoded; tabela de configuração.
4. **Fonte única:** Um conceito (ex.: tribo, ciclo) = uma tabela ou um config injetável.
5. **SQL em sprint:** Migrations + pack apply/audit/rollback antes de marcar Done.

---

## 7. Checklist de Entrada para Novo Item

- [ ] Vinculado a EPIC pai (P0..P3)
- [ ] Dependências DB/API/Front explícitas
- [ ] Backend/API/SQL pronto ou em paralelo com gate
- [ ] Critérios de aceite e evidência (RELEASE_LOG)

---

## 8. Próximos Passos Imediatos

1. **Alta prioridade:** Recuperar ou recriar `sync-credly-all` e `sync-attendance-points` no repo; validar deploy.
2. **Média:** Criar `config_cycles` (migration) e migrar constantes de ciclo.
3. **Baixa:** Documentar decisão sobre `change_requests`, `presentations`, `global_links` e executar em batch 4.

---

*Documento gerado a partir de auditoria técnica (DB schema, frontend, edge functions) e backlog existente. Atualizar conforme decisões de time.*
