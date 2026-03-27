# Wave 5: Knowledge Hub — Plano de Ingestão e Taxonomia

> Documento gerado em 2026-03-09 | Status: **Aprovação Pendente**

---

## 1. Análise do Estado Atual (Campos Existentes)

### 1.1 Tabela `artifacts` (Ciclo 3 — Produção ativa)
| Campo | Tipo | Uso |
|-------|------|-----|
| `id` | uuid | PK |
| `title` | text | Nome do artefato |
| `url` | text | Link do documento/publicação |
| `type` | text | `article`, `framework`, `video`, `presentation`, `other` |
| `status` | text | `draft`, `submitted`, `published` |
| `member_id` | uuid | Autor (FK → members) |
| `tribe_id` | integer | Tribo de origem (FK → tribes) |
| `cycle` | text | Código do ciclo (`cycle_3`) |
| `created_at` | timestamptz | Timestamp |

### 1.2 Tabela `hub_resources` (Workspace / Knowledge Hub público)
| Campo | Tipo | Uso |
|-------|------|-----|
| `id` | uuid | PK |
| `asset_type` | text | `course`, `reference`, `webinar`, `other` |
| `title` | text | Nome do recurso |
| `description` | text | Descrição |
| `url` | text | Link externo |
| `tribe_id` | integer | Tribo vinculada |
| `author_id` | uuid | Quem cadastrou |
| `course_id` | text | ID do curso PMI |
| `is_active` | boolean | Visibilidade |

### 1.3 Tabela `member_cycle_history` (Histórico por ciclo)
| Campo | Tipo | Uso |
|-------|------|-----|
| `member_id` | uuid | FK → members |
| `cycle_code` | text | `pilot`, `cycle_1`, `cycle_2`, `cycle_3` |
| `operational_role` | text | Papel no ciclo |
| `designations` | text[] | Designações |
| `tribe_id` | integer | Tribo no ciclo |
| `is_active` | boolean | Participou ativamente |
| `notes` | text | Observações |

### 1.4 Tabela `events` (Reuniões e Webinars)
| Campo | Tipo | Uso |
|-------|------|-----|
| `id` | uuid | PK |
| `title` | text | Nome do evento |
| `date` | text | Data |
| `type` | text | `tribe_meeting`, `general_meeting`, `webinar`, `other` |
| `duration_minutes` | integer | Duração planejada |
| `tribe_id` | integer | Tribo (nullable) |
| `youtube_url` | text | Gravação |
| `is_recorded` | boolean | Se foi gravado |

---

## 2. Campos Necessários para "Artefatos de Líderes" (Ciclo 3)

Os líderes de tribo produzem entregáveis que não se encaixam na tabela `artifacts` atual (focada em pesquisa). Precisamos expandir:

### Proposta: Nova tabela `leader_artifacts`
| Campo | Tipo | Motivo |
|-------|------|--------|
| `id` | uuid | PK |
| `leader_id` | uuid | FK → members (quem entregou) |
| `tribe_id` | integer | FK → tribes |
| `cycle_code` | text | `cycle_3` |
| `artifact_type` | text | `meeting_minutes`, `tribe_report`, `onboarding_doc`, `process_doc`, `presentation`, `other` |
| `title` | text | Título do artefato |
| `description` | text | Contexto |
| `url` | text | Link do Drive/Notion/etc |
| `tags` | text[] | Tags de taxonomia (ver seção 3) |
| `kpi_category` | text | Vinculação ao KPI do PMI |
| `quality_score` | integer | 1-5, avaliado pelo GP |
| `submitted_at` | timestamptz | Data de submissão |
| `reviewed_at` | timestamptz | Data de revisão |
| `reviewed_by` | uuid | GP que revisou |
| `status` | text | `pending`, `approved`, `needs_revision`, `archived` |

---

## 3. Taxonomia & Tags — Sistema Proposto

### 3.1 Categorias de Tag (KPI-aligned)
| Tag Category | Tags | KPI Vinculado |
|-------------|------|---------------|
| `research` | `article`, `paper`, `framework`, `survey` | +10 artigos publicados |
| `education` | `webinar`, `workshop`, `course`, `certification` | +6 webinars |
| `community` | `chapter_partnership`, `onboarding`, `mentoring` | 8 capítulos |
| `innovation` | `ai_tool`, `prototype`, `pilot_project` | 3 pilotos |
| `impact` | `volunteer_hours`, `social_project`, `external_talk` | 1.800h impacto |
| `governance` | `meeting_minutes`, `report`, `process_doc` | Operacional |

### 3.2 Regra de Subgrupo por Maturidade
Se um artefato **não tiver tag**, aplicar lógica automática:

1. **Ciclo 1 (pilot)**: Tag default = `governance` (maioria é documentação fundacional)
2. **Ciclo 2 (cycle_1/cycle_2)**: Tag default = `research` (fase de produção de artigos)
3. **Ciclo 3 (cycle_3)**: Tag default = `community` (expansão e parcerias)

Fallback final: `untagged` (para revisão manual pelo GP).

### 3.3 Tabela `taxonomy_tags` (configurável pelo admin)
| Campo | Tipo |
|-------|------|
| `id` | serial |
| `category` | text |
| `tag_key` | text (unique) |
| `label_pt` | text |
| `label_en` | text |
| `label_es` | text |
| `kpi_ref` | text |
| `is_active` | boolean |

---

## 4. Plano de Importação de Dados Legados

### 4.1 Fonte: Trello (Ciclos 1 e 2)

**Dados disponíveis no Trello:**
- Cards = tarefas/entregáveis por tribo
- Listas = status (To Do, Doing, Done)
- Labels = tags informais
- Membros atribuídos = member mapping
- Datas de criação/conclusão

**Estratégia de importação:**
1. Exportar Trello boards como JSON (funcionalidade nativa)
2. Criar Edge Function `import-trello-legacy` que:
   - Recebe o JSON exportado
   - Mapeia cards → `leader_artifacts` ou `tribe_deliverables`
   - Mapeia labels → `tags[]` usando tabela de correspondência
   - Mapeia membros Trello → `members.id` via email ou nome
   - Insere com `cycle_code` = `cycle_1` ou `cycle_2`
3. Executar **uma vez** como operação administrativa

**Dados que ficarão no `member_cycle_history`:**
- Participação por ciclo (já existe parcialmente)
- Adicionar campo `artifacts_count` e `deliverables_count` ao histórico

### 4.2 Fonte: Gmail/Calendar do Vitor (Histórico de reuniões)

**Dados disponíveis:**
- Eventos do Google Calendar = reuniões semanais das tribos
- Threads de email = comunicações de coordenação

**Estratégia de importação:**
1. Google Calendar → Export ICS → Parse com Edge Function
2. Mapear eventos para tabela `events`:
   - `title` ← summary do evento
   - `date` ← dtstart
   - `type` = `tribe_meeting` ou `general_meeting`
   - `duration_minutes` ← duração do evento
   - `tribe_id` ← inferir pelo nome da reunião
3. Emails: **Não importar conteúdo** (LGPD). Apenas contagem e metadados:
   - Total de threads por mês por tribo
   - Inserir como `comms_metrics_daily` com `source = 'legacy_email'`

### 4.3 Cronograma Sugerido

| Fase | Ação | Quando |
|------|------|--------|
| 1 | Criar tabelas (`leader_artifacts`, `taxonomy_tags`) | Wave 5.1 |
| 2 | UI de gestão de tags no Admin | Wave 5.1 |
| 3 | Edge Function de importação Trello | Wave 5.2 |
| 4 | Importação Calendar → events | Wave 5.2 |
| 5 | Dashboard de Radar de Competências | Wave 5.3 |
| 6 | Leaderboard com profundidade histórica | Wave 5.3 |

---

## 5. Retorno de Valor Esperado

| Capacidade | Antes | Depois |
|-----------|-------|--------|
| Leaderboard | Apenas Ciclo 3 | 2 anos de histórico (Ciclos 1-3) |
| Radar de Competências | Baseado apenas em badges Credly | + artefatos + horas de impacto |
| Relatório para PMI | Manual (planilhas) | Automático via dashboard |
| Webinar Tracking | Não existia | Calendário integrado com chapters |
| Gestão de Entregáveis | Apenas `tribe_deliverables` | + `leader_artifacts` com tags KPI |
