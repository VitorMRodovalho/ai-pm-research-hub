# Deployment Spec — W98 + W104 + W105

**Data:** 2026-03-12
**Autor:** Vitor (GP) + Claude (CXO)
**Decisões:** Todas aprovadas pelo GP

---

## W98 — Data Sanity Remediation Runbook (Automático)

### Contexto
O saneamento manual da sessão anterior (12 fixes, 67 membros auditados) não escala.
Com ciclos semestrais, membros entrando/saindo, e trocas de tribo, inconsistências 
são inevitáveis. Precisa de detecção automática + auto-fix para anomalias seguras.

### Schema

**Tabela de anomalias detectadas (audit trail):**

```sql
CREATE TABLE IF NOT EXISTS data_anomaly_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  anomaly_type text NOT NULL,
  severity text NOT NULL DEFAULT 'warning',  -- 'critical' | 'warning' | 'info'
  member_id uuid REFERENCES members(id),
  description text NOT NULL,
  auto_fixable boolean DEFAULT false,
  auto_fixed boolean DEFAULT false,
  fixed_at timestamptz,
  fixed_by text,  -- 'auto' | member name/id
  context jsonb DEFAULT '{}',
  detected_at timestamptz DEFAULT now()
);

CREATE INDEX idx_anomaly_type ON data_anomaly_log(anomaly_type);
CREATE INDEX idx_anomaly_severity ON data_anomaly_log(severity);
CREATE INDEX idx_anomaly_pending ON data_anomaly_log(auto_fixed) WHERE auto_fixed = false;
```

### RPC: `admin_detect_data_anomalies(p_auto_fix boolean DEFAULT false)`

Detecta E opcionalmente corrige anomalias seguras. Retorna relatório completo.

**Anomalias a detectar:**

| # | Tipo | Severidade | Auto-fixável? | Lógica |
|---|---|---|---|---|
| 1 | `tribe_selection_drift` | warning | SIM | tribe_selections.tribe_id != members.tribe_id |
| 2 | `active_flag_inconsistency` | warning | SIM (para is_active=false + cycle_active=true + sem papel) | is_active contradiz current_cycle_active |
| 3 | `role_designation_mismatch` | info | NÃO | operational_role='none' mas tem designations não-vazias |
| 4 | `orphan_active_no_tribe` | warning | NÃO | current_cycle_active=true, tribe_id IS NULL, >30 dias do início do ciclo |
| 5 | `cycle_array_stale` | info | SIM | current_cycle_active=true mas cycles não inclui ciclo atual |
| 6 | `duplicate_email` | critical | NÃO | Mesmo email em mais de um member |
| 7 | `never_logged_in` | info | NÃO | auth_id IS NULL e created_at > 60 dias atrás |
| 8 | `assignment_orphan` | warning | SIM | board_item_assignments referencia member que não é mais is_active |
| 9 | `sla_config_missing` | warning | SIM (cria com defaults) | Board ativo sem board_sla_config |

**Comportamento com p_auto_fix=true:**
- Anomalias marcadas auto-fixable são corrigidas e logadas
- Anomalias não auto-fixable são apenas logadas para resolução manual
- Retorna: {fixed: [...], pending: [...], summary: {total, fixed, pending, by_severity}}

### RPC: `admin_get_anomaly_report()`
- Retorna anomalias pendentes (auto_fixed=false) agrupadas por tipo e severidade
- Para o admin panel consumir

### UI

**Admin Panel — Nova tab "Saúde dos Dados":**
- Cards por tipo de anomalia com contagem e badge de severidade
- Botão "Corrigir Automáticas" que chama admin_detect_data_anomalies(true)
- Lista de anomalias pendentes (não auto-fixáveis) com botão "Resolver" que abre modal
- Modal de resolução: mostra contexto, sugere fix, permite editar e confirmar
- Histórico de fixes aplicados (auto + manual)

**Scheduler (recomendação futura):**
- Idealmente, admin_detect_data_anomalies(true) roda automaticamente via cron
- Cloudflare Workers Cron Triggers pode fazer isso — agendar para backlog
- Por agora: botão manual no admin é suficiente

---

## W104 — Portfolio KPI Calibration & Monitoring

### Contexto
As metas anuais do Núcleo (Seção 1.5 do Manual de Governança) precisam ser 
monitoradas continuamente. A seção /#kpis mostra targets estáticos. O kpi_summary 
RPC foi wired mas não cruza meta vs realidade de forma granular.

### Metas anuais a monitorar (da home + Manual):

| Métrica | Meta 2026 | Fonte de dados | Status tracking |
|---|---|---|---|
| Artigos técnicos | +10 | board_items WHERE domain_key LIKE '%publication%' AND status='published' | NÃO rastreado live |
| Webinars | +6 | events WHERE type='webinar' AND status='completed' | NÃO rastreado live |
| Pilotos IA | 3 | NOVO — precisa de registro (o Hub é Piloto #1) | NÃO existe |
| Horas de impacto | 1.800h | attendance (duration × presentes) | PARCIAL (attendance existe, cálculo não) |
| Certificação IA (trilha) | 70% | course_progress WHERE status='completed' | CORRETO no /#trail, INCORRETO no /#kpis |
| Capítulos PMI | 8 (meta futura, atual 5) | members → distinct chapters | Estático |

### Schema

**Tabela de KPI targets configuráveis:**

```sql
CREATE TABLE IF NOT EXISTS portfolio_kpi_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_code text NOT NULL DEFAULT 'cycle3-2026',
  metric_key text NOT NULL,
  metric_label jsonb NOT NULL,  -- {"pt": "Artigos Técnicos", "en": "Technical Articles"}
  target_value numeric NOT NULL,
  warning_threshold numeric NOT NULL,  -- abaixo disso = amarelo
  critical_threshold numeric NOT NULL, -- abaixo disso = vermelho
  unit text DEFAULT 'count',  -- 'count' | 'hours' | 'percent' | 'chapters'
  source_query text,  -- descrição de como calcular o valor atual
  display_order int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  UNIQUE(cycle_code, metric_key)
);

-- Seed com metas 2026
INSERT INTO portfolio_kpi_targets (cycle_code, metric_key, metric_label, target_value, warning_threshold, critical_threshold, unit, source_query, display_order) VALUES
('cycle3-2026', 'articles_published', '{"pt":"Artigos Técnicos","en":"Technical Articles","es":"Artículos Técnicos"}', 10, 6, 3, 'count', 'board_items com status published em boards de publicação', 1),
('cycle3-2026', 'webinars_completed', '{"pt":"Webinars","en":"Webinars","es":"Webinars"}', 6, 4, 2, 'count', 'events com type=webinar e status=completed', 2),
('cycle3-2026', 'ia_pilots', '{"pt":"Pilotos IA","en":"AI Pilots","es":"Pilotos IA"}', 3, 2, 1, 'count', 'projetos registrados como piloto IA (inclui o Hub)', 3),
('cycle3-2026', 'impact_hours', '{"pt":"Horas de Impacto","en":"Impact Hours","es":"Horas de Impacto"}', 1800, 1200, 600, 'hours', 'attendance.duration_actual × contagem de presentes por evento', 4),
('cycle3-2026', 'certification_rate', '{"pt":"Certificação IA","en":"AI Certification","es":"Certificación IA"}', 70, 50, 30, 'percent', 'course_progress completed / total active members × 100', 5),
('cycle3-2026', 'chapters_participating', '{"pt":"Capítulos PMI","en":"PMI Chapters","es":"Capítulos PMI"}', 8, 6, 5, 'chapters', 'distinct chapters em members ativos', 6)
ON CONFLICT (cycle_code, metric_key) DO NOTHING;
```

### RPC: `exec_portfolio_health(p_cycle_code text DEFAULT 'cycle3-2026')`

Cruza targets com dados reais e retorna health score:

```
Returns: [
  {
    metric_key: 'articles_published',
    label: {"pt": "Artigos Técnicos", ...},
    target: 10,
    current: 0,
    progress_pct: 0,
    status: 'critical',  -- green/yellow/red
    unit: 'count',
    trend: null  -- futuro: comparar com período anterior
  },
  ...
]
```

**Cálculo do current por métrica:**
- articles_published: COUNT de board_items em boards com domain_key contendo 'publication' E status IN ('published', 'approved')
- webinars_completed: COUNT de events com category='webinar' e happened=true
- ia_pilots: COUNT de projetos registrados como piloto (NOVO — seed com 1 = o Hub)
- impact_hours: SUM(duration_actual * presentes) de attendance no ciclo
- certification_rate: (COUNT members com 8/8 completed) / (COUNT active members) × 100
- chapters_participating: COUNT DISTINCT(chapter) de members WHERE current_cycle_active=true

### UI

**Seção /#kpis — Upgrade:**
- Abaixo de cada card estático de meta, mostrar barra de progresso com valor atual
- Cor do progresso: verde (>= target), amarelo (>= warning), vermelho (< critical)
- Tooltip com detalhes: "0 de 10 artigos publicados — ciclo iniciou em mar/2026"
- Dados vêm de exec_portfolio_health() chamado client-side após load

**Admin /admin/portfolio — Seção "Saúde do Portfólio":**
- Cards semáforo com progresso de cada KPI
- Clicável: abre drill-down com lista dos items que compõem o número
- Botão "Configurar Metas" (superadmin) → modal para editar targets

**Workspace — Resumo do membro:**
- Mostrar só as métricas relevantes para o membro (progresso pessoal na trilha, horas registradas)

---

## W105 — Cycle Report (Executive Dashboard)

### Contexto
O GP precisa apresentar resultados aos sponsors (5 presidentes de capítulo) em reuniões.
Precisa de uma página web que consolida tudo, com opção de imprimir como PDF.

### RPC: `exec_cycle_report(p_cycle_code text DEFAULT 'cycle3-2026')`

Agrega todos os dados do ciclo em um único objeto:

```typescript
interface CycleReport {
  // Header
  cycle: { code: string, name: string, start_date: string, end_date: string }
  
  // KPIs (de exec_portfolio_health)
  kpis: PortfolioHealthItem[]
  
  // Membros
  members: {
    total: number
    active: number
    by_chapter: { chapter: string, count: number }[]
    by_role: { role: string, count: number }[]
    retention_rate: number  // % que continuaram do ciclo anterior
    new_this_cycle: number
  }
  
  // Tribos
  tribes: {
    id: number
    name: string
    leader: string
    member_count: number
    board_items_total: number
    board_items_completed: number
    completion_pct: number
    articles_produced: number
  }[]
  
  // Produção
  production: {
    articles_submitted: number
    articles_published: number
    articles_in_review: number
    webinars_completed: number
    webinars_planned: number
  }
  
  // Engajamento
  engagement: {
    total_events: number
    total_attendance_hours: number
    avg_attendance_per_event: number
    certification_completion_rate: number
    course_progress_avg: number
  }
  
  // Curadoria (de W90)
  curation: {
    items_submitted: number
    items_approved: number
    items_in_review: number
    avg_review_days: number
    sla_compliance_rate: number
  }
}
```

### UI: `/admin/cycle-report`

**Layout: página única, otimizada para impressão**

Seções na ordem:
1. **Header:** Logo Núcleo + "Relatório do Ciclo 3 — 2026/1" + data de geração
2. **KPIs Semáforo:** 6 cards com progresso (reusa exec_portfolio_health)
3. **Membros por Capítulo:** Bar chart horizontal (por capítulo) + donut (por role)
4. **Tribos:** Grid com card por tribo mostrando progresso e produção
5. **Produção:** Pipeline de artigos (funnel: ideias → redação → revisão → curadoria → publicado)
6. **Engajamento:** Horas de impacto acumuladas + presença média + certificação
7. **Curadoria:** Throughput + SLA compliance
8. **Footer:** "Gerado em [data] · Núcleo IA & GP · ai-pm-research-hub.pages.dev"

**Print-to-PDF:**
- Botão "📄 Exportar PDF" no topo
- Usa `window.print()` com CSS `@media print` dedicado
- Esconde nav, footer do site, botões interativos
- Força background colors com `-webkit-print-color-adjust: exact`
- Page breaks entre seções
- Zero dependência nova — 100% CSS

**Charts:**
- Usar chart.js (já instalado) para bar charts e donuts
- Estilo: fundo transparente, cores dos design tokens (--color-navy, --color-teal, etc.)
- Print-friendly: sem gradients, cores sólidas

### Permissão
- Rota: minTier='admin' + allowedDesignations=['sponsor', 'chapter_liaison']
- Sponsors podem ver o relatório do seu capítulo + agregado
- GP/Deputy vêem tudo

---

## Novas Waves para Backlog (identificadas pelo GP)

Documentar no backlog-wave-planning:

### W106 — Attendance Journey Friction Analysis (CXO Sprint)
**Prioridade:** Alta
**Contexto:** O KPI de 1.800h de impacto depende da qualidade do tracking de attendance.
A jornada já está gamificada mas pode ter fricção não identificada.
**Escopo:**
- Auditar a jornada completa: como um membro registra presença? Quantos cliques?
- Verificar se attendance.duration_actual está sendo calculado corretamente
- Verificar se a multiplicação (duração × presentes) está alimentando o KPI
- Identificar pontos de abandono (PostHog funnel: página → clique → confirmação)
- Propor melhorias de UX se houver fricção
**Critério:** Funnel de attendance documentado, gaps identificados, fixes implementados

### W107 — Hub como Piloto IA #1 (Registro e Documentação)
**Prioridade:** Média
**Contexto:** O Hub/SaaS é o primeiro dos 3 Pilotos IA da meta anual. 
Precisa ser formalmente registrado como projeto-piloto no portal, com:
- Descrição do projeto e tecnologias utilizadas
- Resultados e impactos alcançados
- Métricas de uso (PostHog)
- Lições aprendidas
**Escopo:** Criar página /projects/hub-ia ou seção no /admin com registro formal do piloto.
Alinhar com o formato que os outros 2 pilotos vão usar.

### W108 — Financial Sustainability Framework (Design Phase)
**Prioridade:** Baixa (design only, sem implementação)
**Contexto:** Deputy PM Fabricio cobra início de pensamento sobre sustentabilidade.
PMI é sem fins lucrativos mas recursos são necessários para manutenção.
**Escopo (apenas documentação):**
- Mapear possibilidades: parcerias acadêmicas, licenças de ferramentas IA, 
  sponsorships de empresas de tecnologia, grants de pesquisa
- Documentar em docs/SUSTAINABILITY_FRAMEWORK.md
- Criar placeholder no portal para quando houver escopo claro
**Nota:** Não implementar features financeiras agora — apenas registrar a oportunidade
e ter a infraestrutura de tracking pronta quando o escopo for definido.

---

## Ordem de Execução

```
Sprint A (W98):  Schema + RPC anomalias → Auto-fix → UI admin tab
Sprint B (W104): Schema KPI targets + seed → RPC health → UI /#kpis upgrade + admin portfolio
Sprint C (W105): RPC cycle report → Página /admin/cycle-report → Print CSS
```

W98 vai primeiro porque o auto-fix resolve inconsistências que afetariam os KPIs do W104.
W104 vai antes do W105 porque o cycle report consome os KPIs.

Cada sprint: build + tests + smoke + push.
Aplicar migrations via Supabase CLI após cada sprint.

---

## Critérios de Aceite

### W98
- [ ] admin_detect_data_anomalies() detecta os 9 tipos de anomalia
- [ ] Com p_auto_fix=true, corrige automaticamente tribe_id drift, cycle array stale, SLA config missing
- [ ] Admin panel mostra tab "Saúde dos Dados" com cards por severidade
- [ ] Anomalias não auto-fixáveis têm modal de resolução manual
- [ ] Audit trail completo em data_anomaly_log

### W104
- [ ] portfolio_kpi_targets preenchida com 6 metas do ciclo 3
- [ ] exec_portfolio_health() retorna progresso real vs meta para cada KPI
- [ ] Seção /#kpis mostra barras de progresso com cores semáforo
- [ ] /admin/portfolio mostra dashboard de saúde
- [ ] Certificação rate puxada de course_progress (não hardcoded)

### W105
- [ ] /admin/cycle-report renderiza relatório completo com dados reais
- [ ] Botão "Exportar PDF" gera PDF legível via window.print()
- [ ] Charts usam chart.js com cores dos design tokens
- [ ] Sponsors podem acessar (minTier + allowedDesignations)
- [ ] Relatório inclui: KPIs, membros, tribos, produção, engajamento, curadoria
