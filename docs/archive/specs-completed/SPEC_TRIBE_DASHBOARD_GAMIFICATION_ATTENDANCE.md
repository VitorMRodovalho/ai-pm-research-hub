# SPEC: Tribe Dashboard — Gamificação & Presença para Líderes
## P2-2 + P2-3 | Expande /tribe/[id]
## Base: W117 (Tribe Analytics Dashboard) — spec anterior

---

## 1. CONTEXTO

A página `/tribe/[id]` existe mas falta visibilidade operacional para líderes. Dois módulos novos:

- **P2-2 Gamificação:** XP sintético por tribo + analítico por membro, trilha/certificações
- **P2-3 Presença:** Grid analítico membro × reunião (cronológico), com rank sintético

O líder precisa dessas views para:
- Cobrar presença com dados concretos
- Identificar membros inativos ou estagnados
- Acompanhar progresso de certificações (CPMAI, trilha PMI)
- Reportar resultados ao GP e stakeholders

---

## 2. PERSONAS & ACESSO

| Persona | Vê | Edita |
|---------|-----|-------|
| Tribe Leader | Própria tribo | Presença passada (P1-7 ✅) |
| GP / Deputy | Todas as tribos (dropdown) | Tudo |
| Stakeholder / Sponsor | Tribos do capítulo | Nada |
| Researcher | Própria tribo (read-only) | Nada |

---

## 3. P2-2: TAB GAMIFICAÇÃO

### 3.1 View Sintética (Tribo)

KPI cards no topo:

| KPI | Fonte | Cálculo |
|-----|-------|---------|
| XP Total da Tribo | gamification_points JOIN members | SUM(points) WHERE member.tribe_id = X |
| XP Médio por Membro | idem | AVG |
| Rank da Tribo (vs outras) | Comparar totais | RANK() OVER (ORDER BY sum DESC) |
| % Membros com Certificação | members.credly_badges | COUNT(has_cpmai OR has_pmi_cert) / total |
| Trilha PMI: % Conclusão | gamification_points WHERE category = 'trail' | membros com ≥6 trail badges / total |

Chart: BarChart horizontal — ranking de tribos por XP total (destaca tribo atual).

### 3.2 View Analítica (Membros da Tribo)

Tabela ordenável:

| Coluna | Fonte | Tipo |
|--------|-------|------|
| Membro | members.name | text |
| XP Total | gamification_leaderboard.total_points | number, sort desc default |
| XP Ciclo | gamification_leaderboard.cycle_points | number |
| Presença XP | gamification_leaderboard.attendance_points | number |
| Certificações XP | gamification_leaderboard.cert_points | number |
| Badges XP | gamification_leaderboard.badge_points | number |
| Learning XP | gamification_leaderboard.learning_points | number |
| Rank (tribo) | ROW_NUMBER | number |
| Badges Credly | members.credly_badges count | number, expandível |
| CPMAI | members.credly_badges contains cpmai | ✅/❌ |
| Trilha PMI | count of trail badges / 7 | progress bar |

Ao clicar no membro → expande detalhes inline:
- Lista de badges Credly com nome, data, categoria
- Breakdown de XP por categoria
- Link para perfil completo

### 3.3 Chart

- **BarChart vertical:** Membros da tribo ordenados por XP (top→bottom)
- **PieChart:** Distribuição de XP por categoria (attendance, cert, badge, learning)
- **Trend:** LineChart de XP acumulado da tribo por mês

---

## 4. P2-3: TAB PRESENÇA

### 4.1 View Sintética (Tribo)

KPI cards:

| KPI | Cálculo |
|-----|---------|
| % Presença Geral | presenças / (membros × reuniões aplicáveis) |
| % Presença Tribo | idem filtrado por events.type = 'tribo' |
| % Presença Liderança | idem filtrado por events.type = 'lideranca' |
| Rank da Tribo (vs outras) | RANK() OVER (ORDER BY % presença DESC) |
| Membros 100% | COUNT membros com 0 faltas |
| Membros < 50% | COUNT membros abaixo de metade |

Chart: BarChart horizontal — ranking de tribos por % presença (destaca tribo atual).

### 4.2 View Analítica: Grid Membro × Reunião

**Este é o core da feature.** Tabela matricial:

```
┌──────────────────┬───────┬───────┬───────┬───────┬───────┬───────┬─────┐
│ Membro           │ 05/03 │ 12/03 │ 12/03 │ 19/03 │ 19/03 │ 26/03 │ %   │
│                  │ Geral │ Tribo │ Geral │ Tribo │ Lider │ Tribo │     │
├──────────────────┼───────┼───────┼───────┼───────┼───────┼───────┼─────┤
│ Paulo Alves      │ ✅    │ ✅    │ ✅    │ ✅    │ N/A   │ ✅    │ 100%│
│ Wellinghton B.   │ ✅    │ ✅    │ ❌    │ ✅    │ N/A   │ ✅    │ 80% │
│ Vinicyus S.      │ ✅    │ ❌    │ ✅    │ ❌    │ N/A   │ ❌    │ 40% │
│ Maria L.         │ ❌    │ ✅    │ ❌    │ ✅    │ ✅    │ ✅    │ 67% │
└──────────────────┴───────┴───────┴───────┴───────┴───────┴───────┴─────┘

Legenda: ✅ = Presente | ❌ = Ausente | N/A = Não aplicável (não convocado)
```

**Regras do grid:**

| Regra | Lógica |
|-------|--------|
| Colunas | Todas as reuniões do ciclo em ordem cronológica |
| Header coluna | Data + Tipo (Geral/Tribo/Liderança) |
| ✅ Presente | attendance record existe para (member_id, event_id) |
| ❌ Ausente | Membro era elegível mas attendance record não existe |
| N/A | Membro não era elegível para aquela reunião |
| Elegibilidade | Geral = todos ativos. Tribo = membros daquela tribo. Liderança = tribe_leaders + GP + sponsors |
| % coluna final | presenças / reuniões elegíveis × 100 |
| Ordenação default | % presença DESC (quem falta mais aparece embaixo) |
| Cor de linha | < 50% → fundo vermelho sutil. 50-75% → amarelo. > 75% → verde |

### 4.3 Filtros do Grid

| Filtro | Opções |
|--------|--------|
| Tipo de reunião | Todas, Geral, Tribo, Liderança |
| Período | Ciclo atual (default), Último mês, Custom |
| Ordenar por | % Presença, Nome, XP |

### 4.4 Ação do Líder

- Botão "Editar Presença" em reunião passada da tribo (P1-7 já implementou o backend)
- Clicar na célula ✅/❌ de uma reunião passada da própria tribo → toggle presença
- Audit trail: alteração registrada em admin_audit_log

---

## 5. DADOS NECESSÁRIOS (RPC)

### get_tribe_gamification(p_tribe_id UUID)

```sql
RETURNS JSON:
{
  "summary": {
    "total_xp": 680,
    "avg_xp": 85,
    "tribe_rank": 3,        -- de 8
    "cert_coverage": 0.25,  -- 25% com alguma cert
    "trail_completion": 0.12 -- 12.5% completaram trilha
  },
  "members": [
    {
      "id": "uuid",
      "name": "Paulo Alves",
      "total_points": 120,
      "cycle_points": 80,
      "attendance_points": 40,
      "cert_points": 50,
      "badge_points": 20,
      "learning_points": 10,
      "credly_badge_count": 5,
      "has_cpmai": true,
      "trail_progress": 4  -- de 7
    }
  ],
  "tribe_ranking": [
    {"tribe_id": "uuid", "tribe_name": "Tribo 1", "total_xp": 900},
    {"tribe_id": "uuid", "tribe_name": "Tribo 6", "total_xp": 680},
    ...
  ],
  "monthly_trend": [
    {"month": "2026-01", "xp": 120},
    {"month": "2026-02", "xp": 200},
    {"month": "2026-03", "xp": 360}
  ]
}
```

### get_tribe_attendance_grid(p_tribe_id UUID, p_cycle_id UUID DEFAULT NULL)

```sql
RETURNS JSON:
{
  "summary": {
    "overall_rate": 0.72,
    "tribe_rate": 0.68,
    "leadership_rate": 0.85,
    "tribe_rank": 2,
    "perfect_attendance": 3,
    "below_50": 1
  },
  "events": [
    {
      "id": "uuid",
      "date": "2026-03-05",
      "title": "Reunião Geral",
      "type": "geral",
      "is_tribe_event": false,
      "is_leadership": false
    },
    {
      "id": "uuid", 
      "date": "2026-03-12",
      "title": "Tribo 6 Reunião",
      "type": "tribo",
      "is_tribe_event": true,
      "is_leadership": false
    }
  ],
  "members": [
    {
      "id": "uuid",
      "name": "Paulo Alves",
      "attendance": {
        "event_uuid_1": "present",   -- ✅
        "event_uuid_2": "present",   -- ✅
        "event_uuid_3": "absent",    -- ❌
        "event_uuid_4": "na"         -- N/A (não elegível)
      },
      "rate": 0.85,
      "eligible_count": 10,
      "present_count": 8
    }
  ],
  "tribe_ranking": [
    {"tribe_id": "uuid", "tribe_name": "Tribo 1", "rate": 0.82},
    {"tribe_id": "uuid", "tribe_name": "Tribo 6", "rate": 0.72},
    ...
  ]
}
```

**Elegibilidade:**

```sql
-- Geral: todos os membros ativos do ciclo
-- Tribo: membros com tribe_id = event.tribe_id
-- Liderança: membros com operational_role IN ('manager', 'deputy_manager', 'tribe_leader', 'stakeholder')
-- N/A: membro não era elegível → não conta no denominador
```

---

## 6. UI LAYOUT

```
/tribe/[id]
├── Header: Nome da Tribo, Líder, Quadrante, Reuniões, Links
├── KPI Cards (4): Membros | Presença % | Cards Pipeline | XP Total
├── Tabs:
│   ├── [Membros]        ← existente
│   ├── [Produção]       ← existente (board view)
│   ├── [Gamificação]    ← P2-2 NOVO
│   │   ├── KPI Sintético (cards)
│   │   ├── Chart: Ranking de tribos
│   │   ├── Tabela analítica (membros × XP breakdown)
│   │   └── Charts: XP distribution + trend
│   ├── [Presença]       ← P2-3 NOVO
│   │   ├── KPI Sintético (cards)
│   │   ├── Chart: Ranking de tribos por presença
│   │   ├── Filtros (tipo, período)
│   │   ├── Grid membro × reunião (core)
│   │   └── Ação: editar presença (líder, reunião da tribo)
│   └── [Engajamento]   ← existente (trend line)
```

---

## 7. I18N

Todas as labels, headers, tooltips, mensagens devem ter chaves nos 3 dicionários.
Padrão: `tribe_dashboard.gamification.*` e `tribe_dashboard.attendance.*`

Exemplos:
```
tribe_dashboard.gamification.title = "Gamificação" / "Gamification" / "Gamificación"
tribe_dashboard.gamification.total_xp = "XP Total da Tribo" / "Total Tribe XP" / "XP Total de la Tribu"
tribe_dashboard.attendance.grid_title = "Presença por Reunião" / "Attendance by Meeting" / "Asistencia por Reunión"
tribe_dashboard.attendance.present = "Presente" / "Present" / "Presente"
tribe_dashboard.attendance.absent = "Ausente" / "Absent" / "Ausente"
tribe_dashboard.attendance.na = "N/A" / "N/A" / "N/A"
tribe_dashboard.attendance.overdue_warning = "Abaixo de 50% de presença" / "Below 50% attendance" / "Por debajo del 50% de asistencia"
```

---

## 8. DEPENDÊNCIAS

| Depende de | Status |
|-----------|--------|
| gamification_leaderboard view | ✅ Existe |
| events + attendance tables | ✅ Existem |
| P1-7 (líder edita presença) | ✅ Implementado |
| P1-1 (Tier 3 access) | ✅ Implementado |
| tribes + members tables | ✅ Existem |
| usePageI18n hook | ✅ Implementado (GC-090) |

Zero tabelas novas. Duas RPCs novas. Um componente React novo (TribeGamificationTab + TribeAttendanceTab).

---

## 9. ESTIMATIVA

| Item | Esforço |
|------|---------|
| RPC get_tribe_gamification | 1.5h |
| RPC get_tribe_attendance_grid | 2h (lógica de elegibilidade) |
| TribeGamificationTab component | 2h |
| TribeAttendanceTab component (grid) | 3h (grid matricial é o mais complexo) |
| Charts (4-5 recharts) | 1.5h |
| i18n (3 dicionários) | 30min |
| Testes | 1h |
| **Total** | **~12h** |

---

## 10. PROMPT CLAUDE CODE

```text
SPEC EXECUTION — P2-2 + P2-3: Tribe Dashboard Gamification + Attendance tabs.

Read the full spec at docs/SPEC_TRIBE_DASHBOARD_GAMIFICATION_ATTENDANCE.md

PHASE 1: Create RPCs

1. get_tribe_gamification(p_tribe_id UUID) → returns JSON with:
   - summary (total_xp, avg_xp, tribe_rank, cert_coverage, trail_completion)
   - members array (each member's XP breakdown from gamification_leaderboard)
   - tribe_ranking (all tribes sorted by total XP)
   - monthly_trend (XP by month)
   SECURITY DEFINER, SET search_path, auth guard (tribe_leader sees own, GP sees all)

2. get_tribe_attendance_grid(p_tribe_id UUID, p_cycle_id UUID DEFAULT NULL) → returns JSON with:
   - summary (overall_rate, tribe_rate, leadership_rate, tribe_rank, perfect_attendance, below_50)
   - events array (all cycle events, chronological)
   - members array (each member with attendance map: event_id → present/absent/na)
   - tribe_ranking (all tribes by attendance rate)
   
   Eligibility logic:
   - Geral events: all active cycle members
   - Tribo events: only members of that tribe
   - Liderança events: only tribe_leader + manager + deputy_manager + stakeholder
   - N/A = not eligible, doesn't count in denominator

PHASE 2: Create React components

3. TribeGamificationTab.tsx:
   - KPI cards (total XP, avg, rank, cert coverage, trail completion)
   - Bar chart: tribe ranking
   - Table: members with XP breakdown columns (sortable)
   - Expand row: badge detail
   - Pie chart: XP by category
   - Line chart: monthly trend

4. TribeAttendanceTab.tsx:
   - KPI cards (rates, rank, perfect/below50)
   - Bar chart: tribe ranking by attendance
   - Filters: event type, period
   - GRID: member × event matrix with ✅/❌/N/A
   - Color coding: <50% red, 50-75% yellow, >75% green
   - Click to edit (tribe leader, own tribe events only)

PHASE 3: Wire into /tribe/[id]

5. Add tabs to existing TribeDashboardIsland.tsx
6. Wire usePageI18n for all strings
7. Add i18n keys to 3 dictionaries

All i18n. All trilingual. Use recharts for charts. Use existing permission patterns.
```
