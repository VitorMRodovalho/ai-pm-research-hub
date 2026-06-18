# SPEC — D4/D5: drift candidatura↔entrevista (linha de entrevista órfã na remarcação)

**Status:** ready · **Épico:** D (funil de pré-onboarding) · **Tipo:** bug de higiene de dados (DB-first, 1 migration)
**Autor:** PM (assistido) · **Data:** 2026-06-18 · **Migration:** `20260805000210`
**Council:** data-architect (GO-with-changes, 0 blockers)

## 1. Problema (aterrado ao vivo — cycle4-2026, 51 apps)

O PM aprovou "D4/D5: detectar/reconciliar drift entre `selection_applications.status` e
`selection_interviews`", esperando **candidatos perdidos** (presos num estado incoerente). O
grounding ao vivo mostrou outra coisa:

- **Zero candidato perdido.** Os 4 `app.status` divergentes estão todos **corretos**.
- A divergência (`linha_sem_status=4`) é 100% causada por **linha de entrevista anterior
  não-fechada quando o candidato remarca**: ao re-reservar, uma **nova** linha de entrevista
  é criada e a **anterior** fica presa em `scheduled`/`rescheduled` em vez de virar terminal.

Os 4 casos (todos cycle4-2026):

| Candidata | app_status | linha órfã (aberta) | linha real | leitura |
|---|---|---|---|---|
| Bruna Soares | approved | `scheduled` 08/05 (evento ainda 'scheduled') | `completed` 13/05 | progressão normal + órfã |
| Cristiano Nunes | approved | `rescheduled` 06/05 (evento já cancelled) | `completed` 12/05 | idem |
| Luíse Quintana | approved | `rescheduled` 12/05 (evento já cancelled) | `completed` 15/05 | idem |
| Bruna Lima Zomer | interview_pending | `rescheduled` 06/05 | cadeia → `noshow` 12/05 → `cancelled` 14/05 | estado real = cancelled |

Métricas globais: `apps_with_multi_open=0` (ninguém tem 2 abertas simultâneas);
`orphan_open_not_newest=4` (linha aberta que **não** é a mais recente da app).

**Dano (baixa-sev):** linhas abertas órfãs inflam qualquer contagem de "entrevistas
scheduled/rescheduled abertas" (dashboards, `get_selection_health`, widget #745, crons de
seleção). Não perdem candidato; poluem analytics.

## 2. Causa-raiz (confirmada no código)

`sync_calendar_booking_to_interview` (webhook Google Calendar, mig `20260516920000` + `..._091`):
ao receber uma nova reserva (novo `calendar_event_id`), faz `INSERT ... status='scheduled'`
**sem fechar a linha aberta anterior** da mesma application. `schedule_interview` (GP manual,
mig `20260516110000`) também INSERE `'scheduled'` sem superseder.

Os outros 2 caminhos de INSERT inserem **terminal** e não causam o bug:
`import_historical_interviews` (`completed`) e `mirror_sibling_interview` (`completed`, recusa
se já existe linha).

## 3. Solução (PM escolheu: fix causa-raiz + backfill + invariante)

Implementação como **trigger** (não edição de cada RPC) — ponto único, cobre todos os caminhos
de INSERT, torna a invariante verdadeira por construção.

### 3.1 Trigger `trg_supersede_prior_open_interviews`
`AFTER INSERT ON selection_interviews FOR EACH ROW WHEN (NEW.status IN ('scheduled','rescheduled'))`
→ cancela as outras linhas abertas (`scheduled`/`rescheduled`) da mesma application.

- **AFTER** (não BEFORE): toca **outras** linhas (não a NEW) — padrão p157/AFTER.
- **Sem recursão**: a função fecha siblings por `UPDATE status`; o trigger é só `AFTER INSERT`.
- **Não dispara** em `import_historical_interviews`/`mirror_sibling_interview` (inserem
  `completed` → `WHEN` não casa) → backfill histórico e dual-track intactos.
- **Seguro p/ app.status**: cancelar uma linha dispara `trg_sync_interview_to_app_status`, que
  nunca toca app em status terminal/locked e cujo branch de status aberto não casa `cancelled`.
- **Corrige eventos stale**: cancelar a órfã dispara `trg_sync_interview_to_event`, marcando
  o evento velho como `cancelled` (intencional — corrige o evento 'scheduled' stale da Bruna Soares).

### 3.2 Backfill (mesma migration, 1×, global a todos os ciclos)
Cancela as linhas abertas que **não** são a linha mais recente da app
(`orphan_open_not_newest=4` ao aplicar). Global (não só ciclo ativo) para a invariante AF bater
0 sem noise de ciclos antigos. Inclui **assert fail-loud**: `RAISE EXCEPTION` se sobrar > 0.

### 3.3 Invariante `AF_open_interview_is_newest_row` (severity medium)
"Uma linha `selection_interviews` em status aberto (`scheduled`/`rescheduled`) deve ser a linha
mais recente (`created_at`) da sua application. Uma linha aberta mais antiga que outra linha da
mesma app indica remarcação que não fechou a anterior (bypass do trigger ou drift legado pré-fix)."

Verdadeira por construção pós-trigger ⇒ **não precisa de cron de detecção**.

## 4. Por que NÃO um cron de detecção

A divergência é eliminada na origem pelo trigger; não há o que detectar depois. A invariante AF
em `check_schema_invariants()` é a rede de segurança (defense-in-depth), rodada no CI e no
`/admin/invariants`.

## 5. Gap direcional conhecido (defense-in-depth, aceito)

Inserir uma linha **terminal** mais nova que uma aberta existente (único caminho:
`import_historical_interviews`) não dispara o supersede e violaria AF. Em produção, `completed`
vem de `UPDATE` in-place (`mark_interview_status`/`submit_interview_scores`), não de INSERT novo
— o caminho vivo é coberto. Se ocorrer, AF pega (é o trabalho dela). Não expandir o trigger.

## 6. Validação

- Dry-run lógico: `orphan_open_not_newest=4` antes; 0 depois do backfill.
- `check_schema_invariants()` 33/0 (AF nova, 0 violações).
- Contrato `D4-D5-interview-drift.test.mjs`; suíte DB-aware completa; `npx astro build`.

## 7. Rollback

```
DROP TRIGGER IF EXISTS trg_supersede_prior_open_interviews ON public.selection_interviews;
DROP FUNCTION IF EXISTS public._trg_supersede_prior_open_interviews();
```
As linhas canceladas pelo backfill **permanecem canceladas** (reversão de dados é manual — as 4
foram investigadas e confirmadas órfãs legítimas).
