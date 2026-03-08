# Auditoria — Dados Hardcoded e Riscos de Manutenção

**Data:** 2026-03-08  
**Contexto:** Pesquisador recebeu "Seleção encerrada!" ao tentar escolher tribo — deadline estava hardcoded (`2026-03-08T15:00:00Z`), ignorando `home_schedule.selection_deadline_at`.

---

## Correção aplicada (tribo selection deadline)

- **Causa:** `TribesSection.astro` e `index.astro`/`HeroSection` usavam data fixa em vez de DB.
- **Solução:** `src/lib/schedule.ts` lê `home_schedule.selection_deadline_at`; index pages passam para HeroSection e TribesSection.
- **Fallback:** Se tabela vazia ou erro → `2030-12-31T23:59:59Z` (evita bloquear incorretamente).
- **Admin:** Atualize `home_schedule.selection_deadline_at` via SQL ou futura UI.

```sql
-- Exemplo: garantir linha em home_schedule
insert into public.home_schedule (kickoff_at, recurring_start_brt, recurring_end_brt, recurring_weekday, selection_deadline_at)
values ('2026-01-15T19:00:00Z', '19:30', '20:30', 4, '2026-04-30T23:59:59Z')
on conflict do nothing;  -- ou update onde aplicável
```

---

## Outros pontos de risco (backlog de melhoria)

### Alta prioridade — mudança de ciclo difícil

| Arquivo | Linhas | Problema |
|---------|--------|----------|
| `admin/index.astro` | 1629, 1633 | Default de filtros: `'2026-01-01'` |
| `admin/index.astro` | 2094–2100 | Mapa de ciclos (pilot, cycle_1–3) com datas fixas |
| `data/tribes.ts` | 36 | `MAX_SLOTS = 6` — deveria vir de `tribes` ou config |
| `admin/constants.ts` | 83 | `MAX_SLOTS` duplicado |
| `TribesSection.astro` | 184–185 | `MAX_SLOTS`/`MIN_SLOTS` no script inline |
| `admin/index.astro` | 325–340, 465+ | Labels PT em selects (Tribo 01–08, capítulos) |
| `lib/admin/constants.ts` | 4–96 | `TRIBE_NAMES`, `CYCLE_META`, `OPROLE_LABELS` em PT |

### Média prioridade — configurabilidade

| Arquivo | Linhas | Problema |
|---------|--------|----------|
| `cycle-history.js` / `constants.ts` | 75 | `'Piloto 2024'`, datas de ciclo |
| `profile.astro` | 370 | `"Ciclo 3 (2026/1)"` fixo |
| `admin/index.astro` | 900, 1082… | `for (t = 1; t <= 8)`, `.limit(200/400/500)` |
| `TrailSection.astro` | 139, 154–155 | Thresholds `avg >= 70`, `pct >= 100` |
| `attendance.astro` | 216, 403 | `pct >= 70`, `duration_minutes || 90` |

### Baixa prioridade

| Arquivo | Problema |
|---------|----------|
| `TribesSection`, `HeroSection` | Fallbacks de deadline (ok) |
| i18n | Conteúdo por ciclo — atualizável via i18n |

---

## Recomendações

1. **Ciclos e datas:** Tabela `group_cycles` ou `config_cycles` com `code`, `label`, `start`, `end`; admin UI para editar.
2. **MAX_SLOTS / MIN_SLOTS:** Coluna em `tribes` ou tabela `group_config`.
3. **Labels admin:** Migrar para i18n ou DB (ex.: `admin.labels.tribe01`).
4. **Thresholds:** Constantes em `data/config.ts` ou DB para KPIs.
5. **Regra:** Nenhum ponto de mudança de ciclo/deadline/config deve ser hardcoded; sempre fonte única (DB ou config injetável).
6. **RPC `select_tribe`:** Verificar se valida `home_schedule.selection_deadline_at` no backend; se não, adicionar validação para evitar bypass via API.
