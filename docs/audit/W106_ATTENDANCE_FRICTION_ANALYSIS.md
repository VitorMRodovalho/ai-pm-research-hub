# W106 — Attendance Journey Friction Analysis

**Date:** 2026-03-16
**Analyst:** Claude Code (Opus 4.6)
**Data Range:** Cycle 3 (2025-12-01 → present) + historical (2025-06-01+)

---

## Data Collection (Raw)

### Query 1 — Overall Attendance Stats (Cycle 3)

```sql
SELECT count(DISTINCT e.id) as total_events, ...
FROM events e LEFT JOIN attendance a ON a.event_id = e.id
WHERE e.date >= '2025-12-01';
```

| total_events | general_meetings | tribe_meetings | total_attendance_records | unique_attendees |
|---|---|---|---|---|
| 39 | 6 | 3 | 126 | 45 |

**Insight:** 45 of 52 active members (86.5%) attended at least one event. 126 records across 39 events = **3.2 avg per event** (low, but 27 events are interviews with 0 attendance expected).

---

### Query 2 — Attendance by Event Type

```sql
SELECT t.name as event_type, count(DISTINCT e.id) as event_count, ...
FROM events e JOIN event_tag_assignments eta ON eta.event_id = e.id ...
GROUP BY t.name ORDER BY event_count DESC;
```

| event_type | event_count | attendance_records | avg_per_event |
|---|---|---|---|
| interview | 27 | 0 | 0.0 |
| general_meeting | 6 | 102 | **17.0** |
| tribe_meeting | 3 | 11 | **3.7** |
| external_event | 1 | 0 | 0.0 |
| alignment | 1 | 0 | 0.0 |
| kickoff | 1 | 42 | **42.0** |
| leadership_meeting | 1 | 13 | **13.0** |

**Insight:** Interviews (27/39 = 69% of events) have 0 attendance records by design. Excluding interviews: **12 real events, 126 attendances, 10.5 avg/event**. General meetings average 17 attendees (32.7% of active members). Kick-off had 42 (80.8%).

---

### Query 3 — Attendance Trend by Month

```sql
SELECT to_char(e.date, 'YYYY-MM') as month, ...
FROM events e LEFT JOIN attendance a ON a.event_id = e.id
WHERE e.date >= '2025-06-01' GROUP BY month ORDER BY month;
```

| month | events | attendances | unique_members | avg_per_event |
|---|---|---|---|---|
| 2025-06 | 10 | 57 | 15 | 5.7 |
| 2025-07 | 8 | 42 | 15 | 5.3 |
| 2025-08 | 18 | 60 | 20 | 3.3 |
| 2025-09 | 16 | 114 | 30 | 7.1 |
| 2025-10 | 12 | 90 | 25 | 7.5 |
| 2025-11 | 7 | 35 | 18 | 5.0 |
| 2025-12 | 7 | 48 | 23 | 6.9 |
| 2026-01 | 22 | 0 | 0 | 0.0 |
| 2026-02 | 7 | 13 | 13 | 1.9 |
| 2026-03 | 3 | 65 | 42 | **21.7** |

**Insight:** January 2026 had 22 events (all interviews) with 0 recorded attendance. March 2026 spike (21.7 avg) due to kick-off. Feb 2026 dip (1.9) suggests attendance recording gap during cycle transition. Cycle 2 trend (Jun-Nov 2025) was relatively stable at 5-7.5 avg.

---

### Query 4 — Member Attendance Distribution (Cycle 3)

```sql
SELECT CASE WHEN attend_count = 0 THEN '0 events (ghost)' ... END as engagement_tier,
  count(*) as member_count, ...
FROM (...) sub GROUP BY ... ORDER BY min(attend_count);
```

| engagement_tier | member_count | pct |
|---|---|---|
| 0 events (ghost) | 10 | 19.2% |
| 1-3 events (low) | 32 | 61.5% |
| 4-10 events (moderate) | 10 | 19.2% |
| 11-20 events (active) | 0 | 0.0% |
| 21+ events (champion) | 0 | 0.0% |

**Insight:** No members in "active" or "champion" tiers. 80.8% attend ≤3 events. The distribution is heavily left-skewed — most members show minimal engagement. The "moderate" tier (19.2%) is the core engaged group.

---

### Query 5 — Top 10 Most Attended Events

```sql
SELECT e.title, e.date, count(a.id) as attendees, ... ORDER BY attendees DESC LIMIT 10;
```

| title | date | attendees | tags |
|---|---|---|---|
| Evento de Abertura (Kick-off) + Reunião Geral – Ciclo 3 | 2026-03-05 | **42** | kickoff, general_meeting |
| Reunião Geral Recorrente – Ciclo 3 | 2026-03-12 | **23** | general_meeting |
| Reunião Geral C2 (12/Dec) | 2025-12-12 | **20** | general_meeting |
| Reunião Geral C2 (03/Dec) | 2025-12-03 | **17** | general_meeting |
| Alinhamento Estratégico: Liderança | 2026-02-17 | **13** | leadership_meeting |
| Tribo 6 (C2) (11/Dec) | 2025-12-11 | 4 | tribe_meeting |
| Tribo 6 (C2) (15/Dec) | 2025-12-15 | 4 | tribe_meeting |
| Tribo 6 (C2) (17/Dec) | 2025-12-17 | 3 | tribe_meeting |

**Insight:** General meetings dominate top attendance. Tribe meetings average only 3.7 attendees. Only Tribo 6 has recorded tribe meeting attendance — other tribes may not be recording.

---

### Query 6 — Bottom 10 Least Attended Events

```sql
SELECT e.title, e.date, count(a.id) as attendees, ... ORDER BY attendees ASC LIMIT 10;
```

All 10 bottom events are **interview** events with 0 attendees — expected behavior (interviews are 1:1 sessions, attendance not tracked the same way).

---

### Query 7 — Ghost Members (Active, 0 Attendance in Cycle 3)

```sql
SELECT m.name, m.operational_role, t.name as tribe, m.designations
FROM members m ... WHERE m.is_active = true AND NOT EXISTS (...) ORDER BY m.name;
```

| name | role | tribe | designations |
|---|---|---|---|
| Ana Cristina Fernandes Lima | chapter_liaison | — | [chapter_liaison] |
| Felipe Moraes Borges | sponsor | — | [sponsor] |
| Francisca Jessica de Sousa de Alcântara | sponsor | — | [sponsor] |
| Leonardo Chaves | researcher | Radar Tecnológico | [] |
| Lorena Almeida | researcher | Radar Tecnológico | [] |
| Matheus Frederico Rosa Rocha | sponsor | — | [sponsor] |
| Ricardo Santos | researcher | Agentes Autônomos | [] |
| Roberto Macêdo | chapter_liaison | — | [chapter_liaison, ambassador, curator] |
| Rogério Peixoto | chapter_liaison | — | [chapter_liaison] |
| Wellinghton Pereira Barboza | researcher | Talentos & Upskilling | [] |

**10 ghost members (19.2%).**
- 3 sponsors (expected — advisory role, not required at events)
- 3 chapter_liaisons (expected — cross-chapter coordination, may attend informally)
- 4 researchers (unexpected — should be attending)

---

### Query 8 — Champions (Highest Attendance in Cycle 3)

```sql
SELECT m.name, t.name as tribe, count(a.id) as events_attended, ...
ORDER BY events_attended DESC LIMIT 10;
```

| name | tribe | events_attended | months_active |
|---|---|---|---|
| **Joao Coelho Junior** | Inclusao & Colaboracao & Comunicacao | **7** | 2 |
| **Debora Moura** | Agentes Autonomos | **7** | 3 |
| **Leticia Clemente** | Inclusao & Colaboracao & Comunicacao | **7** | 2 |
| Vitor Maia Rodovalho | — | 5 | 3 |
| Francisco Jose Nascimento | Inclusao & Colaboracao & Comunicacao | 5 | 2 |
| Fabricio Costa | ROI & Portfolio | 4 | 3 |
| Mayanna Duarte | Inclusao & Colaboracao & Comunicacao | 4 | 2 |
| Luciana Dutra Martins | ROI & Portfolio | 4 | 2 |
| Gustavo Batista Ferreira | Agentes Autonomos | 4 | 3 |
| Antonio Marcos Costa | Governanca & Trustworthy AI | 4 | 2 |

**Insight:** Top champion has only 7 events (out of 12 non-interview events). Tribo 8 (Inclusao & Colaboracao & Comunicacao) dominates — 4 of top 10 are from this tribe.

---

### Query 9 — Day-of-Week Attendance Pattern

```sql
SELECT to_char(e.date, 'Day') as day_of_week, ...
GROUP BY ... ORDER BY dow_num;
```

| day | events | attendances | avg_per_event |
|---|---|---|---|
| Monday | 2 | 4 | 2.0 |
| Tuesday | 5 | 13 | 2.6 |
| Wednesday | 9 | 20 | **2.2** |
| Thursday | 13 | 69 | **5.3** |
| Friday | 6 | 20 | 3.3 |
| Saturday | 4 | 0 | 0.0 |

**Insight:** Thursday is the strongest day (5.3 avg, 53% of all attendance). Saturday events get zero attendance. Wednesday has many events (9) but poor turnout (2.2 avg) — most are interviews.

---

### Query 10 — Mandatory vs Optional Attendance

```sql
SELECT ear.attendance_type, count(DISTINCT e.id) as events, ...
FROM event_audience_rules ear JOIN events e ON e.id = ear.event_id ...
GROUP BY ear.attendance_type;
```

| attendance_type | events | unique_attendees |
|---|---|---|
| mandatory | 38 | 45 |
| optional | 1 | 0 |

**Insight:** 38/39 events are marked mandatory, but actual compliance is low (~31.1% avg). The mandatory label has no enforcement mechanism and appears to be ignored. The single optional event had 0 attendees.

---

## Key Findings

### 1. Ghost Rate: 19.2% (10 of 52 active members)
- 6 are sponsors/chapter_liaisons (advisory, expected)
- **4 researchers with zero attendance is a retention risk** (Leonardo, Lorena, Ricardo, Wellinghton)

### 2. Event Type Attendance
- **Kick-off: 80.8%** attendance (42/52) — best performing
- **General meetings: 32.7%** average (17/52) — declining from kick-off
- **Tribe meetings: 7.1%** average (3.7/52) — critically low, only Tribo 6 records
- **Interviews: 0%** — expected (1:1 sessions, attendance not tracked)

### 3. Trend: Volatile, Not Declining
- Cycle 2 (Jun-Nov 2025): stable at 5-7.5 avg/event
- Cycle 3 transition (Jan 2026): 0 attendance recorded (all interviews)
- Cycle 3 active (Mar 2026): kick-off spike (42), then drop (23) — **50% retention loss between meeting 1 and meeting 2**

### 4. Best Day: Thursday (5.3 avg)
- Thursday events get 2.4x the attendance of other days
- Saturday events get 0 attendance — should be eliminated or moved
- Wednesday is popular for scheduling (9 events) but poor for attendance (2.2 avg)

### 5. Champions vs Ghosts: 10 vs 10 (1:1 ratio)
- Top champion: 7 events (58% of 12 non-interview events)
- 61.5% of members attend only 1-3 events — the "passive majority"
- Tribo 8 (Comunicacao) produces the most champions

### 6. Mandatory Label Is Meaningless
- 97% of events are "mandatory" but avg compliance is 31.1%
- No enforcement, no differentiation from optional
- The attendance_type field provides no actionable signal

---

## Friction Hypotheses

Based on the data, the following friction points are likely:

### H1: Tribe meetings are not being recorded, not that they're empty
Only Tribo 6 has recorded tribe meeting attendance (3 events, 3.7 avg). The other 7 tribes likely meet but don't record attendance. This is a **data gap**, not an engagement gap.

### H2: The 50% drop from kick-off to meeting #2 is a classic onboarding cliff
42 people attended the kick-off → 23 at the next general meeting. The novelty/excitement fades, and members who joined out of curiosity don't convert to regulars. **No onboarding nudge exists between meetings.**

### H3: Wednesday scheduling conflicts create phantom events
9 events on Wednesday but only 2.2 avg attendance. These are mostly interviews, but any real meetings on Wednesday compete with workday schedules and get poor turnout.

### H4: The "passive majority" (61.5%) is not engaged enough to form habits
Members who attend 1-3 events haven't built attendance into their routine. They need **fewer, higher-quality touchpoints** rather than more events with low turnout.

### H5: Sponsors and chapter_liaisons are excluded from attendance tracking
6 of 10 ghosts are advisory roles. Their engagement model is different — they might attend some events but their value comes from strategic input, not presence. **Attendance KPI should exclude these roles** from the denominator.

### H6: Saturday events are dead
4 events scheduled on Saturday with 0 attendance. Volunteer/research groups don't engage on weekends.

---

## Recommended Actions

### Priority 1 — Data Quality (fix before measuring)

| Action | Impact | Effort |
|---|---|---|
| **A1:** Mandate tribe leaders record attendance for every tribe meeting | Fixes H1, improves data coverage from 3 tribes to 8 | Low (process) |
| **A2:** Exclude interviews from attendance metrics (filter by tag) | Removes 27 phantom events from dashboards | Low (SQL filter) |
| **A3:** Exclude sponsors/chapter_liaisons from attendance KPI denominator | Fixes H5, raises avg from 31.1% to ~37% | Low (SQL filter) |

### Priority 2 — Engagement Interventions

| Action | Impact | Effort |
|---|---|---|
| **A4:** Send automated reminder 24h before general meetings | Addresses H2/H4, nudges passive majority | Medium (notification system) |
| **A5:** Implement "streak" gamification for consecutive meeting attendance | Addresses H4, builds habits | Medium (gamification points rule) |
| **A6:** Consolidate to Thursday-only scheduling for general/tribe meetings | Leverages best day (5.3x avg), avoids Saturday (0 attendance) | Low (scheduling policy) |

### Priority 3 — Structural Changes

| Action | Impact | Effort |
|---|---|---|
| **A7:** Create post-kickoff "week 2 onboarding" touchpoint for new members | Addresses H2, reduces 50% cliff | Medium (content + automation) |
| **A8:** Replace mandatory/optional binary with tiered attendance expectations by role | Addresses H6, sets realistic expectations | Medium (schema + UI) |
| **A9:** Contact 4 ghost researchers individually (Leonardo, Lorena, Ricardo, Wellinghton) | Direct intervention for at-risk retention | Low (manual outreach) |
