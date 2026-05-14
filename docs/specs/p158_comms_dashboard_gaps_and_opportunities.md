# Comms Dashboard — Gaps & Opportunities (p158)

**Status**: Draft for PM co-design · 2026-05-14
**Trigger**: PM live test — "YouTube vídeos não aparece, e outros dados/insights de ambos parece que ainda não é trago como poderia ser"
**Author**: Claude (Anthropic) — pending PM sign-off + scoping

---

## 1. Current state (post p158 hotfix#7)

Data pipeline (confirmed via DB):

| Channel | Daily metrics | Media items | Notes |
|---|---|---|---|
| Instagram | ✅ 30+ days | 25 items (12 carousel + 4 image + 9 video) | OK |
| YouTube | ✅ 30+ days | 29 video items | OK (last sync 13/05 06h) |
| LinkedIn | ❌ aguardando API | 0 | Pending PMI-GO LinkedIn API approval |
| Newsletter | ❌ não conectado | 0 | Out of scope (no infra) |

UI render (`/admin/comms` "Mídia Social"):

| Panel | Data source | State |
|---|---|---|
| 4 KPIs topo (Audiência/Alcance/Engagement/Posts) | `comms_metrics_latest_by_channel` | ✅ funcional pós hotfix#7 (POSTS hoje conta IG+YT corretamente) |
| Tendência por Canal (chart) | `comms_metrics_latest_by_channel` | ✅ |
| Instagram card | payload jsonb | ✅ (followers, reach, engagement, posts) pós hotfix#7 |
| YouTube card | payload jsonb | ✅ (subscribers, views, videos) pós hotfix#7 |
| LinkedIn card | — | ❌ "Aguardando API" (não acionável) |
| Top Content (últimos 30d) | `comms_top_media(p_days=30, p_limit=6)` | ✅ (mistura todos canais ordenado por reach) |

---

## 2. Gaps identificados

### Gap 2.1 — Per-channel "top content" não existe
**Hoje**: Top Content global misturado (6 itens últimos 30d, qualquer canal).
**Falta**: Painéis separados "Top 5 YouTube vídeos" + "Top 5 Instagram posts" + filter por engagement vs alcance vs views.
**Impacto**: PM tem que escanear 6 cards mistos para entender performance por canal individual. Decisões de conteúdo por canal ficam difíceis.

### Gap 2.2 — Drill-down por mídia ausente
**Hoje**: Top Content card clica em "Ver post →" abre permalink externo.
**Falta**: Modal com detalhes do item — engagement timeline (likes/comments daily), comments preview, audience demographics (se IG/YT API expõe), comparativo com média do canal.
**Impacto**: PM precisa abrir cada vídeo no YouTube Studio / IG Insights para análise — não consolida no Núcleo.

### Gap 2.3 — Engagement trend agregado, não por mídia
**Hoje**: Engagement rate é média diária do canal.
**Falta**: Trend per-mídia (este vídeo cresceu X% em 7d), top engagement growth (qual conteúdo está bombando agora).
**Impacto**: PM identifica padrão "qual tema engaja" só com inspeção visual. AI insight teria mais leverage aqui.

### Gap 2.4 — Funnel social → site → adoption ausente
**Hoje**: KPIs medem alcance externo; adoção (membros logados) está em `/admin/adoption` separado.
**Falta**: Dashboard cruzado — "X visualizações vídeo Y → Z visitas /trail-pmi-ai → W aplicações VEP". Atribuição UTM já existe em `selection_applications.referral_source`.
**Impacto**: PM não consegue justificar ROI de produção de conteúdo (custo vs aplicações). Conversa com Lorena/Comms sobre prioridade fica anedótica.

### Gap 2.5 — AI summary / sentiment por canal
**Hoje**: AI usado em `pmi-ai-triage` (selection) + `pmi-ai-analyze` (qualitative).
**Falta**: AI synthesis semanal do conteúdo published — "qual narrativa dominou esta semana", "comments sentiment trend", "temas recorrentes".
**Impacto**: PM/Comms perdem ~30min/semana lendo comments manualmente. AI digest semanal automatizaria.

### Gap 2.6 — LinkedIn API aguardando
**Hoje**: LinkedIn card "Aguardando aprovação da API". Provavelmente PMI-GO ainda não aprovou OAuth app no LinkedIn Developer.
**Falta**: Status visual mais granular (data submission, expected approval, fallback manual sync via CSV).
**Impacto**: Atrito visual mas não bloqueante. LinkedIn dados podem entrar via `publish_comms_metrics_batch` manual quando API liberar.

### Gap 2.7 — Comparação period-over-period limitada
**Hoje**: KPIs mostram delta vs período anterior (e.g. "↑2.6% vs período anterior").
**Falta**: Comparação flexível (vs mês anterior, vs trimestre, vs ano), gráfico stack de canais.
**Impacto**: PM quer answer "este mês foi melhor que o mês passado?" — hoje tem só week-vs-week.

### Gap 2.8 — Conteúdo planejado vs publicado
**Hoje**: Top Content lista posts já publicados.
**Falta**: Pipeline view "planejado para próxima semana" (vindo de `comms_pipeline` ou board comms-ops).
**Impacto**: Visão completa de inbound+outbound — saber se há buracos no calendário editorial.

---

## 3. Quick wins (≤2h cada — alta valor / baixo esforço)

### QW-1: Per-channel top content tabs (~1-2h)
Trocar o Top Content único por 3 tabs (Todos | Instagram | YouTube). Reuso de `comms_top_media` adicionando `p_channel` filter. UI: tab buttons + filtered fetch.

### QW-2: Posts/Vídeos KPI subtítulos enriquecidos (~30min)
Hoje o KPI "POSTS TOTAIS: 62" mostra "IG: 25 · YT: 37". Adicionar variação: "(↑2 últimos 7d)" e link clicável que rola para per-channel section. Subtitle atual é informativo, precisa actionable.

### QW-3: Manual LinkedIn metrics input form (~1h)
Enquanto API não aprova, formulário admin para input manual semanal (followers, post count, engagement). Salva em `comms_metrics_daily` com `source='manual'`. Card LinkedIn passa a mostrar dados.

### QW-4: Engagement rate per-post overlay (~1h)
Top Content cards mostram likes/comments mas não o **engagement rate** (likes+comments / reach). Adicionar badge "ER: 4.5%" colorido por threshold (<2% gray, 2-5% green, >5% gold).

---

## 4. Médio prazo (3-8h — moderate effort)

### MP-1: Funnel social → adoption (~4-6h)
- RPC nova `get_comms_to_adoption_funnel(p_period)` que cruza:
  - `selection_applications.referral_source` (com UTM social)
  - `comms_metrics_daily.audience` per period
  - `member_activity_sessions.first_page` (landing trail pages)
- UI: Sankey-style funnel chart no /admin/comms.
- Permite resposta: "Vídeo X gerou Y aplicações no ciclo Z?"

### MP-2: Per-video drill-down modal (~3-4h)
- Click em vídeo do Top Content abre modal:
  - Timeline likes/comments/views (se historic data — pode requerer scheduled snapshot table `comms_media_items_history`)
  - Comments preview (top 10 por timestamp)
  - Compare vs canal average
  - CTA "Boost este post" (manual flag to surface no próximo digest)

### MP-3: Period-over-period flex comparison (~2-3h)
- Frontend toggle: Esta semana / Este mês / Últimos 30d / Últimos 90d / This year vs Last year
- RPC já é p_days-parametrizada — extensible. UI necessita o seletor + delta computation per channel.

### MP-4: AI weekly digest comms (~4-6h)
- EF nova `pmi-ai-comms-digest` (Sonnet) ingere:
  - Última semana de posts (caption + engagement + permalink)
  - Comments amostra
- Output JSON: themes, sentiment overall, top performing format, suggested next post topic
- Schedule weekly cron Mon 8h → email Lorena + PM. Dashboard "AI Insights" tab no /admin/comms.

---

## 5. Strategic / longer (8h+)

### ST-1: Editorial calendar 360 (~6-10h)
Unifica `comms_pipeline` (planejado) + `comms_media_items` (publicado) + `webinar_proposals` (live events) em calendar view. Filter por canal, type, status. Drag-drop reschedule. Substitui dependência atual de Google Calendar / Trello externo.

### ST-2: Comments AI moderation (~10h+)
- EF que classifica comments (spam / question / praise / complaint) via Sonnet.
- Surface "perguntas não respondidas" para o Comms team agir.
- Auto-tag comments com `member_id` quando reconhece nome.
- Métricas resposta SLA Comms.

### ST-3: Cross-channel content recommendation (~8h)
- AI análise de qual conteúdo viralizou em IG → sugere remix YouTube short / LinkedIn carousel.
- Treina modelo no histórico próprio (vs hot themes externos via PostHog?).
- Output: priority list semanal de "remix candidates".

---

## 6. Bug corrections já feitos (p158 hotfix#7)

- ✅ `comms_metrics_latest_by_channel` agora retorna payload jsonb. YouTube vídeos passa a mostrar count real (era "--").
- ✅ Mesmo fix beneficia IG media_count, e KPI "POSTS TOTAIS" que somava 0+0=0.

Pendente verificação prod (após PM F5):
- [ ] YouTube card mostra "Vídeos: 37" (era "--")
- [ ] Instagram card mostra "Posts: 25" (era "--" se assim estava antes)
- [ ] KPI "POSTS TOTAIS: 62" no topo do dashboard

---

## 7. Recomendação de priorização

| Tier | Items | Sessão proposta |
|---|---|---|
| **Imediato** | hotfix#7 (já shipped) | done p158 |
| **Próxima sessão (~2-3h)** | QW-1 + QW-2 + QW-4 (per-channel tabs + KPI subtítulos + ER overlay) | ~3h fecha hygiene visual |
| **Sessão dedicada (~6h)** | MP-1 funnel social→adoption | maior valor estratégico — justifica ROI Comms |
| **Sprint dedicado (~10h)** | MP-4 AI weekly digest comms | alta alavanca tempo Lorena/Comms |
| **Quarterly** | ST-1 editorial calendar OR ST-2 AI moderation | sobre qual stack escolher — separar discussão |

---

## 8. Perguntas abertas para PM

1. **LinkedIn API**: status real do approval com PMI-GO LinkedIn dev? Se >30d, vale acelerar QW-3 (manual input).
2. **Prioridade Q3**: você quer MP-1 (funnel) ou MP-4 (AI digest) primeiro? MP-1 justifica gasto Comms; MP-4 acelera produção.
3. **Comments moderation**: tem volume hoje que justifica ST-2? Quantos comments/semana median? Se <30, manual fine; se >100, IA vale.
4. **Editorial calendar** (ST-1): você usa Google Calendar/Sheets/Trello externo hoje? Migrar é prioridade ou está OK?

---

**Próxima ação proposta**: PM revisa este doc + marca priorização + abre sessão dedicada para o item escolhido. Ou alternativamente abre milestone "comms-uplift-q3" + agenda 1-2h/semana para iterar quick wins.
