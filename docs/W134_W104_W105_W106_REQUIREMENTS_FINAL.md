# W134/W104/W105/W106 — Requisitos Consolidados (Validado pelo GP)
**Data: 2026-03-15 | Status: APROVADO para Code | Decisões D1-D5 resolvidas**

---

## Decisões do GP (registradas)

| ID | Decisão | Impacto |
|----|---------|---------|
| D1 | **3 reuniões sequenciais por data** (qualquer tipo: geral, tribo, misto — o que importa é a sequência cronológica de eventos com presença esperada) | R1.3 alertas |
| D2 | **Lovable apps NÃO contam como pilotos** (foram experimentais C2, não implementados em gestão real de capítulo/projeto). Hub SaaS = Pilot #1, os outros 2 precisam ser implementações reais em gestão. | R2.3 KPI pilotos |
| D3 | **Não é relatório mensal fixo.** GP precisa levar informações gerenciais "na mão" para sponsors com mais frequência. Relatório sob demanda com dados atualizados, não ciclo fixo. | R3.1 executive report |
| D4 | **Líderes de tribo PODEM lançar presença** da própria tribo. | R1.4 permissões |
| D5 | **Pesquisador VÊ sua própria assiduidade** + agrupamento comparativo com a tribo. O membro deve saber se é detrator da nota da tribo, e se a tribo é detratora da geral. Transparência total. | R1.1 visibilidade |

---

## Dados de Base (produção atual)

- 164 eventos (Fev/2025 → Mar/2026)
- 783 registros de presença, 56 membros distintos, 96 eventos cobertos
- 58 membros ativos, 8 tribos
- Geral: avg 14.2 presentes/reunião (peak 30)
- Tribo: avg 4.2 presentes/reunião (peak 7)
- KPI targets C3: cert 70%, impact 1.800h, pilots 3, articles +10, webinars +6, chapters 8
- Horas de impacto estimadas até hoje: ~982h (55% da meta em 25% do ano = on track)

---

## WAVE W134a — Lançamento de Presença
**Prioridade: P0 (desbloqueia tudo) | Personas: GP, tribe_leader**

### Escopo
Form para registrar presença de um evento, substituindo a planilha.

### Requisitos funcionais

**R1.4.1 — Seleção de evento**
- Dropdown dos eventos do ciclo atual (filtrado: últimos 30 dias + próximos 7 dias)
- Ao selecionar, mostra: data, tipo, tribo (se tribe_meeting)
- Se tribe_meeting, pré-filtra lista de membros pela tribo do evento
- Se general_meeting, mostra todos os ativos

**R1.4.2 — Lista de membros com checkbox**
- Todos os membros ativos da tribo (ou todos, se geral) com checkbox
- Busca por nome para encontrar rápido
- Indicador visual se já tem presença registrada nesse evento (para não duplicar)

**R1.4.3 — Salvar batch**
- RPC `register_attendance_batch(event_id, member_ids[], registered_by)`
- Insere todos de uma vez com `ON CONFLICT DO NOTHING`
- Toast de confirmação: "X presenças registradas"

**R1.4.4 — Permissões**
- `manager` e `deputy_manager`: qualquer evento
- `tribe_leader`: apenas eventos da própria tribo + eventos gerais (para registrar quem da tribo estava lá)

### Backend
```sql
CREATE OR REPLACE FUNCTION register_attendance_batch(
  p_event_id uuid,
  p_member_ids uuid[],
  p_registered_by uuid
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  inserted integer;
BEGIN
  INSERT INTO attendance (event_id, member_id, present, registered_by)
  SELECT p_event_id, unnest(p_member_ids), true, p_registered_by
  ON CONFLICT (event_id, member_id) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;
```

### Frontend
- Localização: `/workspace` → seção "Lançar Presença" (visível para manager + tribe_leader)
- Componente React: `AttendanceForm.tsx`
- Estimativa: 1 RPC + 1 componente React = **Pequena**

---

## WAVE W134b — Dashboard de Assiduidade
**Prioridade: P1 | Personas: GP (visão completa), tribe_leader (filtrado), pesquisador (próprio)**

### Escopo
Visão consolidada de presença por membro, substituindo a planilha de controle.

### Requisitos funcionais

**R1.1.1 — Visão GP (manager/deputy_manager)**
Tabela com TODOS os membros ativos:

| Coluna | Descrição |
|--------|-----------|
| Nome | Nome do membro |
| Tribo | Tribo atual |
| Role | operational_role |
| Geral (%) | Presenças em general_meeting / total de general_meetings do ciclo |
| Tribo (%) | Presenças em tribe_meeting da tribo / total de tribe_meetings da tribo no ciclo |
| Combinado (%) | Média ponderada: (geral × 0.4 + tribo × 0.6) — tribo pesa mais porque é onde a pesquisa acontece |
| Indicador | 🟢 ≥75% | 🟡 50-74% | 🔴 <50% | ⚫ 0% |
| Trend | ↑↓→ comparando últimas 4 reuniões vs 4 anteriores |
| Última presença | Data da última presença registrada |

Filtros: por tribo, por ciclo, por range de datas
Ordenação: default = menor % combinado primeiro (alerta)

**Recomendação aplicada:** NÃO usar sparkline por reunião (escala ruim com 30+ reuniões). Usar % + trend.

**R1.2.1 — Visão Tribe Leader**
Mesma tabela, automaticamente filtrada para a tribo do líder logado.
Colunas extras:
- Dias desde última presença
- Streak de reuniões consecutivas da tribo

**R1.5.1 — Visão Pesquisador (D5 aplicada)**
O pesquisador vê no `/workspace`:
- **Sua linha individual** com todos os % (geral, tribo, combinado, indicador)
- **Ao lado:** os agregados da tribo (média da tribo nos mesmos %)
- **E ao lado:** os agregados gerais (média de todos os membros)
- Visual: "Você: 65% | Sua tribo: 72% | Geral: 68%"
- Se o pesquisador está abaixo da tribo = ele é detrator da tribo
- Se a tribo está abaixo da geral = a tribo é detratora da geral
- Indicação textual sutil: "Sua participação está abaixo da média da tribo" ou "Sua tribo está acima da média geral"

**Recomendação:** Não usar linguagem punitiva ("detrator"). Usar framing positivo: "Sua tribo está 4% acima da média geral — parabéns!" ou "Você pode fortalecer a nota da tribo participando das próximas reuniões".

### R1.3.1 — Alertas de Risco (D1 aplicada)
- Cálculo: para cada membro ativo, verificar os últimos 3 eventos (por data, qualquer tipo que a tribo/membro deveria participar) e ver se faltou a todos
- Definição de "deveria participar": general_meetings (todos) + tribe_meetings da tribo do membro
- Badge no `/workspace` do GP e tribe_leader: "X membros em risco de dropout"
- Clicável → modal com nome, tribo, última presença, dias sem comparecer
- Threshold: `site_config.attendance_risk_threshold = 3` (configurável)

### Backend
```sql
CREATE OR REPLACE FUNCTION get_attendance_summary(
  p_cycle_start date DEFAULT '2026-03-01',
  p_cycle_end date DEFAULT '2026-08-31',
  p_tribe_id integer DEFAULT NULL
) RETURNS TABLE(
  member_id uuid,
  member_name text,
  tribe_id integer,
  tribe_name text,
  operational_role text,
  geral_present bigint,
  geral_total bigint,
  geral_pct numeric,
  tribe_present bigint,
  tribe_total bigint,
  tribe_pct numeric,
  combined_pct numeric,
  last_attendance date,
  consecutive_misses integer
) LANGUAGE plpgsql SECURITY DEFINER AS $$
-- Implementation: 
-- 1. Count general meetings in cycle range
-- 2. Count tribe meetings per tribe in cycle range
-- 3. For each active member, count their present records in each category
-- 4. Calculate % and combined score (0.4 geral + 0.6 tribo)
-- 5. Find last attendance date
-- 6. Calculate consecutive misses from latest events backward
$$;
```

### Frontend
- Componente: `AttendanceDashboard.tsx`
- Visão dinâmica baseada na role do usuário logado (via middleware existente)
- Estimativa: 1 RPC + 1 componente com 3 views condicionais = **Média**

---

## WAVE W104 — Portfolio KPI Dashboard
**Prioridade: P1 | Personas: GP, sponsors (via report)**

### Escopo
Painel de progresso contra as 6 metas anuais.

### Requisitos funcionais

**R2.1.1 — KPI Cards**
6 cards mostrando cada KPI com progress bar:

| KPI | Fonte de dados | Cálculo |
|-----|---------------|---------|
| Certificações CPMAI (70%) | `courses` table (completions de CPMAI) / `members` ativos | % membros com CPMAI concluído |
| Horas de impacto (1.800h) | `SUM(COALESCE(duration_actual, duration_minutes, 60) * headcount) / 60` | Join events × attendance count |
| Pilotos de IA (3) | board_items com tag 'pilot' no board de gestão | Hub SaaS = 1 hardcoded. Demais: contagem de items com tag. **Lovable apps NÃO contam.** |
| Artigos publicados (+10) | board_items no board "Publicações" com status 'done' no stage "Published" | Count |
| Webinars realizados (+6) | `events` com type = 'webinar' no ciclo | Count |
| Capítulos integrados (8) | Distinct chapters em `members` ativos (via field chapter ou derivado) | Count distinct. Hoje: 5 (GO, CE, DF, MG, RS) |

**R2.1.2 — Projeção linear**
- Progresso esperado = (dias passados do ciclo / dias totais do ciclo) × meta
- Cor: verde (atual ≥ esperado), amarelo (atual ≥ 75% do esperado), vermelho (atual < 75% do esperado)

**R2.2.1 — Campo duration_actual**
- Quando o GP/leader lança presença (W134a), incluir campo opcional "Duração real (min)" que popula `events.duration_actual`
- Default: usa `duration_minutes` (60 min)

### Backend
```sql
CREATE OR REPLACE FUNCTION get_kpi_dashboard(
  p_cycle_start date DEFAULT '2026-03-01',
  p_cycle_end date DEFAULT '2026-08-31'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
-- Returns: { kpis: [{name, current, target, pct, status}] }
-- 6 subqueries, one per KPI
$$;
```

### Frontend
- Componente: `KpiDashboard.tsx`
- 6 cards com progress bar + cores + tooltip com detalhes
- Localização: `/workspace` acima do attendance dashboard
- Estimativa: 1 RPC + 1 componente = **Média**

---

## WAVE W105 — Executive Report (Informações Gerenciais para Sponsors)
**Prioridade: P2 | Personas: GP (gera), sponsors (consomem)**

### Escopo
Página com visão consolidada que o GP pode imprimir/PDF e levar para sponsors.

### Requisitos funcionais (D3 aplicada — sob demanda, não periódico)

**R3.1.1 — Página `/report` ou `/workspace/report`**
Layout de relatório com:
1. **Header:** Núcleo IA & GP — Relatório Gerencial [data da geração]
2. **Resumo:** Ciclo atual, período, membros ativos, tribos ativas, capítulos
3. **KPIs:** 6 indicadores com progresso (reusa W104)
4. **Assiduidade:** Média geral, por tribo (tabela pequena), membros em risco
5. **Entregas:** Artigos (submetidos/publicados), protótipos, webinars realizados
6. **Eventos recentes:** Últimos 5 eventos com headcount
7. **Próximos passos:** Eventos agendados, deadlines

**R3.2.1 — Print-to-PDF**
- Botão "Imprimir / Gerar PDF" → `window.print()` com `@media print` CSS limpo
- Sem dependência de biblioteca PDF server-side (zero-cost constraint)
- Logo do Núcleo no header, cores institucionais
- Página A4 com margens corretas

**R3.3.1 — Acesso**
- Fase 1: apenas GP gera e compartilha como PDF
- Sem multi-view por capítulo (desnecessário agora com 5 capítulos)
- GP pode filtrar por capítulo antes de imprimir se quiser levar dados específicos

### Frontend
- Página Astro: `report.astro` com layout de impressão
- Reusa RPCs de W134b e W104
- Estimativa: 0 RPCs novos + 1 página Astro com print CSS = **Média-Baixa**

---

## WAVE W106 — Attendance Journey Friction Analysis
**Prioridade: P3 (analítica) | Personas: GP**

### Escopo
Análise de retenção e dropout com dados históricos. Fase 1 = documento com insights. Fase 2 = visualização no dashboard.

### Requisitos funcionais

**R4.1.1 — Análise de Retenção (documento, não código)**
Com os 783 registros existentes, gerar:
- Curva de retenção kickoff → mês 1 → mês 2...
- Retenção por tribo (T3/Fabricio tinha 100% em 29 reuniões)
- Dropout timeline médio
- Comparativo C1 vs C2

**R4.3.1 — Quick Win já calculado**
Kickoff C3 (41) → Geral 12/mar (23) = 44% dropout na 1ª semana:
- 4 sponsors/fundadores (esperado, roles não-operacionais)
- 2 líderes de tribo (Fabricio + Marcel — provavelmente pontual)
- 5 veteranos C2 (Débora, Denis, Cíntia, Francisco, Maria Luiza — sinal de alerta)
- 7 novatos C3 (Leandro, Gustavo, Vinicyus, Ana Carla, Rodrigo, Stephania, Letícia V — risco real)

**R4.2.1 — Fase 2: Visualização (futuro)**
- Heatmap de presença (membro × reunião)
- Gráfico de retenção por coorte
- Correlação engajamento × produção

### Entrega
- Fase 1: documento SQL + insights (posso gerar agora)
- Fase 2: componente React no `/workspace` (sprint futuro)
- Estimativa Fase 1: **Zero código** (análise sobre dados existentes)

---

## Ordem de Execução para Code

| # | Wave | Entrega | RPCs | Components | Est. |
|---|------|---------|------|-----------|------|
| 1 | W134a | Lançamento de presença | 1 | 1 form | P |
| 2 | W134b | Dashboard assiduidade (3 views) | 1 | 1 table | M |
| 3 | W104 | KPI progress cards | 1 | 1 grid | M |
| 4 | W134c | Alertas de risco | extensão | 1 badge | P |
| 5 | W105 | Executive report page | 0 (reusa) | 1 page | M-B |
| 6 | W106 | Friction analysis doc | 0 | 0 | Zero |

**Total: 3 RPCs novos, ~5 componentes/páginas.**

---

## site_config entries a adicionar

```sql
INSERT INTO site_config (key, value) VALUES
  ('attendance_risk_threshold', '3'),
  ('attendance_weight_geral', '0.4'),
  ('attendance_weight_tribo', '0.6'),
  ('kpi_pilot_count_override', '1') -- Hub SaaS hardcoded as Pilot #1
ON CONFLICT (key) DO NOTHING;
```
