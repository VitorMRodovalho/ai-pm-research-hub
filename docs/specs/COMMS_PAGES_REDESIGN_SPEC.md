# SPEC: Redesign das Paginas de Comunicacao

**Status:** Draft
**Data:** 2026-04-15
**Autor:** Vitor + Claude (spec collaborativa)
**Paginas:** `/admin/comms-ops` (Comunicacao) + `/admin/comms` (Midia Social)

---

## 1. Diagnostico — Estado Atual

### `/admin/comms` (hoje: "Dashboard Central de Midia")

| Secao | Problema |
|---|---|
| Channel Config cards | "Ultimo sync: Nunca" para todos. Instagram e YouTube tem token mas nunca rodou sync automatico. Status "Sem expiracao" correto para IG (permanent token) mas confuso para o usuario. |
| Tribe Impact Ranking | **Nao tem relacao com midia social.** Mostra ranking de eventos por tribo. |
| Channel Metrics Chart | Bar chart basico (reach vs audience). Sem serie temporal. Sem tendencia. |
| Channel Metrics Table | 7 rows total no DB. Mostra agregado diario sem granularidade por post. |
| Broadcast History | Historico de notificacoes internas (email/push). Nao tem relacao com social media. |
| Webinars Pendentes | Webinars que precisam de divulgacao. Pertence a operacional, nao analytics. |
| Playbook/Context | Copy templates para webinars. Pertence a operacional. |
| Manual Metrics Form | Fallback para entrada manual. Niche, deveria ser secundario. |

**Veredicto:** Mistura analytics com operacional, social media com eventos internos. Nao tem per-post metrics, nao tem tendencias, nao tem demographics.

### `/admin/comms-ops` (hoje: "Comms Ops Dashboard")

| Secao | Estado |
|---|---|
| CommsDashboard | Cards (backlog, overdue, total) + bar chart por status + pie chart por formato. Tudo baseado em board_items do domain `communication`. |
| BoardEngine | Kanban board funcional. |

**Veredicto:** Escopo correto para operacional, mas faltam elementos que estao no `/admin/comms` (webinars pendentes, playbook, broadcast history).

---

## 2. Dados Disponiveis Hoje

### Banco de dados
- `comms_metrics_daily`: 7 rows (2 datas), campos: date, channel, audience, reach, engagement_rate, leads, source, payload
- `comms_channel_config`: 3 canais (youtube, instagram, linkedin), tokens + config
- `notifications`: log de notificacoes internas
- `board_items` (domain=communication): tarefas do kanban
- `webinars`: webinars com status de comms

### APIs configuradas
| Canal | API | Metricas disponíveis hoje | Metricas possiveis |
|---|---|---|---|
| **Instagram** | Graph API v19.0 | followers, reach (daily), accounts_engaged, total_interactions, media_count | Per-media: likes, comments, saves, reach. Demographics: age, gender, city, country. Stories insights. Reels insights. |
| **YouTube** | Data API v3 | subscribers, total views, video count | Per-video: views, likes, comments, duration, publish date, thumbnail. Search trends. Playlist data. |
| **LinkedIn** | Community Mgmt API | (pending approval) | Followers, impressions, clicks, engagement rate, share stats |

---

## 3. Personas e Necessidades

### P1: Comms Member (Mayanna, Leticia, Maria Luiza)
**Precisa de:**
- Ver quais posts performaram melhor (para replicar)
- Saber o que publicar esta semana (backlog + calendario)
- Templates de copy para webinars
- Status das tarefas do board

**Nao precisa de:** Tokens, config de API, metrics manuais

### P2: Comms Leader (futuro: alguem promovido)
**Precisa de:**
- Tudo do P1
- KPIs de crescimento (followers WoW, reach trend)
- Visao cross-channel (comparativo YouTube vs Instagram vs LinkedIn)
- Gerenciar tokens e config de integracao
- Alertas de token expirando

### P3: Gestor / Sponsor / Consultor (Vitor, capitulo, stakeholders)
**Precisa de:**
- Executive summary: numeros-chave em 5 segundos
- Tendencia de crescimento (esta crescendo ou estagnando?)
- ROI: investimento de horas da equipe vs alcance
- Benchmarks: como estamos vs periodo anterior

### P4: Admin / Infra
**Precisa de:**
- Status de tokens e sync
- Logs de erro de integracao
- Config de canais

---

## 4. Proposta de Redesign

### 4.1 `/admin/comms-ops` → "Comunicacao" (Operacional)

**Foco:** O que fazer hoje. Tarefas, calendario, templates.

```
Sections:
1. [MANTER] KPI Cards — backlog, overdue, total publicacoes
2. [MANTER] Board Kanban — tarefas de comunicacao
3. [MOVER DE /admin/comms] Webinars Pendentes — acoes de divulgacao
4. [MOVER DE /admin/comms] Playbook/Context — templates de copy
5. [MOVER DE /admin/comms] Broadcast History — historico de notificacoes
6. [NOVO] Calendario de Publicacoes — timeline visual do que esta agendado
```

**Racional:** Tudo que e "o que preciso fazer" fica aqui. Board + webinars + templates + historico = workflow completo do comms member.

### 4.2 `/admin/comms` → "Midia Social" (Analytics)

**Foco:** Como estamos performando. Numeros, tendencias, insights.

#### S1: Executive Summary (todos veem)
4 KPI cards no topo:

| Card | Fonte | Calculo |
|---|---|---|
| Audiencia Total | SUM(latest audience per channel) | YouTube subs + IG followers + LI followers |
| Alcance Semanal | SUM(reach) ultimos 7 dias | IG reach + YT views + LI impressions |
| Engagement Rate Medio | AVG(engagement_rate) ponderado | Calculado por channel, media ponderada por audience |
| Crescimento (WoW) | (this_week - last_week) / last_week | Percentual de crescimento da audiencia |

Cada card com sparkline (minigrafico de tendencia dos ultimos 14 dias).

#### S2: Tendencia por Canal (todos veem)
**Line chart** com serie temporal: audience (followers/subs) ao longo do tempo, uma linha por canal.
- Periodo: ultimo mes (default), 3 meses, 6 meses
- Toggle: audiencia vs alcance vs engagement

#### S3: Performance por Canal (todos veem)
3 colunas (Instagram / YouTube / LinkedIn), cada uma com:

**Instagram:**
- Followers: 212 (+X% WoW)
- Reach (7d): 472
- Engagement: 15.6%
- Top 3 posts (thumbnail + likes + comments + reach)

**YouTube:**
- Subscribers: 64 (+X% WoW)
- Total views: 1,282
- Videos: 43
- Top 3 videos (thumbnail + title + views + likes)

**LinkedIn:**
- Followers: --
- Status: Aguardando aprovacao da API
- (placeholder com dados manuais se existirem)

#### S4: Top Content (todos veem)
**Feed visual** dos posts com melhor performance across all channels.
- Thumbnail + caption (truncado) + canal + data
- Metricas: reach, likes, comments, saves
- Ordenado por engagement ou reach (toggle)
- Limite: top 10

#### S5: Audience Demographics (comms_leader+ apenas)
- **Disponivel via IG API:** `follower_demographics` (age, gender, city, country)
- Pie charts: Genero, Faixa etaria
- Bar chart: Top 5 cidades
- Util para direcionar conteudo

#### S6: Channel Admin (comms_leader+ apenas — ja implementado)
- [MANTER] Channel config cards com status de token
- [MANTER] Modal de edicao de config
- [MANTER] Token alerts
- [MANTER] Staleness banner
- [REMOVER] Tribe Impact Ranking (nao pertence aqui)
- [REMOVER] Manual Metrics Form (substituido por sync automatico; se necessario, mover para drawer)

---

## 5. Mudancas no Backend

### 5.1 Nova tabela: `comms_media_items`
Para armazenar per-post metrics (Instagram media, YouTube videos):

```sql
CREATE TABLE comms_media_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel text NOT NULL,                    -- 'instagram', 'youtube'
  external_id text NOT NULL,                -- IG media_id ou YT video_id
  media_type text,                          -- 'IMAGE', 'VIDEO', 'CAROUSEL', 'REEL'
  caption text,
  permalink text,
  thumbnail_url text,
  published_at timestamptz,
  -- metrics snapshot (updated each sync)
  likes int DEFAULT 0,
  comments int DEFAULT 0,
  shares int DEFAULT 0,
  saves int DEFAULT 0,
  reach int,
  impressions int,
  views int,                                -- YouTube specific
  -- metadata
  payload jsonb DEFAULT '{}',
  synced_at timestamptz DEFAULT now(),
  UNIQUE(channel, external_id)
);
```

### 5.2 Atualizar EF `sync-comms-metrics`

Alem das metricas agregadas diarias, buscar:

**Instagram:**
```
GET /{ig_user_id}/media?fields=id,caption,media_type,timestamp,like_count,comments_count,permalink,thumbnail_url&limit=25
GET /{media_id}/insights?metric=reach,saved,shares
```

**YouTube:**
```
GET /youtube/v3/search?channelId={id}&type=video&order=date&maxResults=10
GET /youtube/v3/videos?id={ids}&part=statistics,snippet
```

Upsert em `comms_media_items` a cada sync.

### 5.3 Novos RPCs

```sql
-- Top content across channels
comms_top_media(p_channel text DEFAULT NULL, p_days int DEFAULT 30, p_limit int DEFAULT 10)
  → {channel, external_id, media_type, caption, permalink, thumbnail_url, published_at, likes, comments, shares, saves, reach, views}

-- Time series for trend charts
comms_audience_trend(p_days int DEFAULT 30)
  → {metric_date, channel, audience, reach, engagement_rate}

-- Executive KPIs (calculated)
comms_executive_kpis()
  → {total_audience, weekly_reach, avg_engagement, audience_growth_pct, channel_breakdown: [{channel, audience, reach, engagement}]}

-- Audience demographics (IG only)
comms_audience_demographics()
  → {age_ranges: {...}, genders: {...}, top_cities: [...], top_countries: [...]}
```

### 5.4 Sync automatico (pg_cron ou Supabase cron)

Disparar `sync-comms-metrics` diariamente (ex: 06:00 UTC):
- Fetch daily aggregates (ja existe)
- Fetch media items (novo)
- Fetch demographics (novo, IG only, weekly)

---

## 6. O que NAO muda

- `/admin/comms-ops` continua com CommsDashboard + BoardEngine (layout OK)
- RLS e permissoes de acesso (ja implementadas)
- `comms_metrics_daily` continua como fonte de metricas diarias agregadas
- Token management (ja funcional)

---

## 7. Prioridade de Implementacao

### Fase 1: Separacao de Conteudo (rapido, sem backend)
1. Mover Webinars Pendentes, Playbook, Broadcast History para `/admin/comms-ops`
2. Remover Tribe Impact Ranking de `/admin/comms`
3. Reorganizar `/admin/comms` com layout de KPIs no topo

### Fase 2: Trend Charts + Executive KPIs (backend leve)
1. Criar RPC `comms_audience_trend` (query em comms_metrics_daily existente)
2. Criar RPC `comms_executive_kpis` (calculo sobre dados existentes)
3. Implementar line chart de tendencia e KPI cards com sparklines
4. Configurar sync automatico (pg_cron)

### Fase 3: Per-Post Analytics (backend + EF)
1. Criar tabela `comms_media_items`
2. Atualizar EF para buscar media list + per-media insights
3. Criar RPC `comms_top_media`
4. Implementar S4 (Top Content feed visual)

### Fase 4: Demographics + Polish
1. Fetch `follower_demographics` da IG API (weekly)
2. Implementar S5 (demographics charts)
3. Sparklines nos KPI cards
4. Periodo selecionavel (7d / 30d / 90d)

---

### Fase 5: Additions from market analysis (16/Abr)
1. [x] CSV Export — botao na tabela de metricas
2. [x] PDF Export — html2canvas + jsPDF, captura KPIs + charts
3. [x] Comparativo por periodo — delta (arrow + %) nos KPI cards vs periodo anterior
4. [x] Melhor horario para postar — IG online_followers heatmap (bar chart por hora)
5. [x] Calendario de publicacoes — board_items agrupados por semana no comms-ops
6. [x] Top Content feed visual — grid com thumbnail, metricas, link direto

### Fase 6: Blocked / Future
1. **Hashtag analytics** — Requer `ig_hashtag_search` permission que exige Meta App Review para producao. Em dev mode funciona apenas para o proprio perfil. Preparar quando LI app review concluir (same process).
2. **Video retention (YT)** — YouTube Analytics API requer OAuth do canal (diferente da Data API com API key). Necessita novo auth flow. ROI baixo para 43 videos / 64 subs. Reavaliar quando canal crescer.

---

## 8. Metricas de Sucesso

- Comms member consegue identificar top 3 posts sem sair da plataforma
- Gestor ve tendencia de crescimento em <5 segundos
- Sync automatico roda diariamente sem intervencao manual
- Zero exposure de tokens para comms_member (ja implementado)
- CSV/PDF export disponivel para relatorios de capitulo
- Comparativo por periodo mostra direcao do crescimento
