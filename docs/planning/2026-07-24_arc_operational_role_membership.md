# Arco — `operational_role` como proxy de pertencimento (#1476 + #1477)

> **Aberto 2026-07-24** após re-triagem do backlog (owner escolheu esta frente). Continuação natural do arco de
> auditoria pontuação/mérito (umbrella #1465, fechado 2026-07-23): mesmo domínio de autoridade/pertencimento.
> Todos os números abaixo vieram de query ao vivo desta sessão (não recitar; re-aterrar por PR).

## Problema (SSOT)

`members.operational_role` é um **cache de exibição de valor único** (derivado por escada de prioridade em
`sync_operational_role_cache`, "governança vence": `sponsor` > `chapter_liaison` > `researcher`). O bug: ~16 funções
vivas usam esse rótulo como **proxy de pertencimento operacional** (`operational_role NOT IN ('sponsor',
'chapter_liaison', ...)`). Quem acumula dois papéis (ponto focal de capítulo **e** pesquisador de tribo) tem a
militância operacional apagada em toda superfície derivada. A fonte de verdade de pertencimento é o **engagement
volunteer ativo na iniciativa**, não o cache.

- **Afetados ao vivo (2026-07-24):** `2` membros ativos do ciclo (ponto focal + pesquisador, 2 tribos distintas).
  Tende a crescer com a política de entrada multi-capítulo.
- **Superfícies com o predicado (ao vivo):** `16` funções na forma `NOT IN (...)` MAIS `~10` na forma de
  **inclusão positiva** `operational_role IN/ANY(... 'researcher' ...)` que a 1ª varredura (só NOT IN) perdeu —
  MESMA classe de bug (o multi-papel cujo cache resolveu `chapter_liaison` cai fora da lista de inclusão). Escopo
  real ≈ `26` superfícies + a view `v_operational_members`. Nem toda inclusão é bug (ver Classe E).
- **Sintoma reportado:** um pesquisador ativo não aparece no `get_tribe_attendance_grid` (5 vs 6 no roster real);
  presença gravada em `attendance` é silenciosamente engolida pelo grid.

## Padrão do fix (descoberto ao comparar corpos vivos)

- **Padrão CERTO** (`get_tribe_event_roster`): pertencimento = engagement volunteer ativo na iniciativa; sem filtro
  de rótulo (só exclui `guest`).
- **Padrão ERRADO redundante** (`get_tribe_attendance_grid` leg1, `get_tribe_events_timeline`): a perna JÁ gateia
  por `EXISTS engagement volunteer active AND initiative_id`, e o `AND operational_role NOT IN (...)` é um filtro
  ADICIONAL que retira quem já foi legitimamente incluído. Fix = **remover o filtro de rótulo**.
- **Padrão ERRADO por-derivação** (`count_tribe_slots`, gates de capacidade em `request_tribe_assignment` e
  `review_tribe_request`, `exec_cycle_report.members_count`): contam por `members.tribe_id` + filtro de rótulo, sem
  engagement. Fix = **rebasear em engagement volunteer ativo na iniciativa** (SSOT), que naturalmente exclui
  sponsor-puro/guest e inclui o multi-papel. Semântica de capacidade: o multi-papel OCUPA uma vaga de pesquisador —
  contá-lo é o comportamento correto.

## Classificação das 16 superfícies (varredura viva 2026-07-24)

### Classe A — undercount de pertencimento/contagem (FIX)
| função | uso atual | fix |
|---|---|---|
| `get_tribe_attendance_grid` | leg1 já gateia engagement; rótulo redundante+nocivo (o sintoma) | remove filtro de rótulo do leg1 |
| `get_tribe_events_timeline` | `v_tribe_member_count`: engagement EXISTS + `NOT IN(sponsor,liaison)` | remove filtro de rótulo |
| `count_tribe_slots` | `tribe_id` + rótulo, sem engagement | rebase em engagement (capacidade) |
| `request_tribe_assignment` (gate de vaga) | `tribe_id` + rótulo | idem `count_tribe_slots` |
| `review_tribe_request` (gate de vaga) | `tribe_id` + rótulo | idem `count_tribe_slots` |
| `exec_cycle_report` (`members_count`) | `tribe_id` + rótulo | rebase em engagement |
| `detect_and_notify_detractors` (+`_cron`) | `NOT IN(sponsor,liaison)` | remove filtro (multi-papel recebe alerta de detrator) |
| `detect_operational_alerts` | `NOT IN(sponsor,liaison,guest,none)` | remove filtro |
| `get_admin_dashboard` | `NOT IN(sponsor,liaison,manager,deputy_manager,observer)` | ATENÇÃO: também exclui liderança — confirmar se é contagem "pesquisadores de linha" intencional antes de mexer |

### Classe B — identificação legítima de papel de governança (LEAVE, verificar)
| função | uso | veredicto |
|---|---|---|
| `get_org_chart` | `IN(sponsor,chapter_liaison)` — constrói o organograma de governança | uso correto do rótulo |
| `get_portfolio_planned_vs_actual` | caller `IN(...)` → view-scoping | gate de autoridade, provável intencional |
| `review_change_request` | caller `IN(...)` → NULL (nega review de CR) | gate de autoridade |

### Classe C — semântica de trilha/aprendiz (DECISÃO do owner)
| função | uso | pergunta |
|---|---|---|
| `calc_trail_completion_pct` | exclui governança da conclusão de trilha | papéis de governança têm trilha? |
| `get_public_trail_ranking` | exclui governança do ranking público | governança entra no ranking de aprendiz? |

### Classe D — elegibilidade ao TCV (#1477)
| `check_my_tcv_readiness` | `role IN(...)` → `role_exempt` | isenta pesquisador voluntário ativo pelo rótulo; corrigir per #1477 |

### Classe E — forma de INCLUSÃO positiva (`operational_role IN/ANY('...researcher...')`) — re-varredura 2026-07-24
Mesma classe de bug quando a lista deriva PERTENCIMENTO; legítima quando só faz BUCKETING de papel para exibição/analytics.
Classificar cada uma (candidatas a bug em **negrito**, alta materialidade primeiro):
- **`get_attendance_engagement_summary`**, **`get_attendance_reliability_summary`** — usadas DENTRO de `exec_cycle_report`
  para % por tribo; se excluem `chapter_liaison`, o multi-papel some dos denominadores. ALTA.
- **`seal_event_attendance`** — se sela presença só para a lista de inclusão, a presença do multi-papel pode não ser selada. ALTA.
- **`get_dropout_risk_members`**, **`get_gp_cohort_health`**, **`get_cycle_attendance_overview`** — cohort/risco por lista. MÉDIA.
- **`v_operational_members`** (view) — "canonical operational members metric" (#1437, com contract test
  `1437-operational-members-canonical-metric.test.mjs`). Mexer aqui exige entender o que #1437 ratificou. ALTA/sensível.
- `analytics_role_bucket` — provável bucketing de papel para analytics (não pertencimento) → LEAVE (verificar).
- `_credly_health_rows`, `admin_get_anomaly_report` — verificar se é derivação de pertencimento ou diagnóstico. A confirmar.

> **Onda 1b (inclusão):** `get_attendance_engagement_summary`/`reliability` + `seal_event_attendance` casam com o
> sintoma de presença da Onda 1 — dobrar junto se o consult confirmar. `v_operational_members` fica em onda própria
> (canonical-metric #1437). `analytics_role_bucket` provável LEAVE.

## Ondas propostas (apply→merge serial; DB compartilhado serializa DDL)

- **Onda 1 — família tribo/presença (o sintoma) — ✅ FEITA (mig 484, 2026-07-24):** view canonical
  `v_tribe_active_members` (security_invoker=on + REVOKE anon/authenticated) + 6 funções rebaseadas
  (`get_tribe_attendance_grid`, `get_tribe_events_timeline`, `count_tribe_slots`,
  `request_tribe_assignment`/`review_tribe_request` gates de vaga, `exec_cycle_report` AMBOS member_count —
  o consult achou o overcount extra em `v_tribes[].member_count`). QA por impersonação: grid da tribo 7
  passou 5→6; deltas de contagem SÓ nas tribos 1 (7→8) e 7 (5→6), toda outra tribo intacta. Contract tests
  `1476-tribe-membership-canonical` (novo) + `1350` repontado. Phantom row `20260723130448` limpo (GC-097).
- **Onda 2 — alertas/detrator:** `detect_and_notify_detractors`(+`_cron`), `detect_operational_alerts`,
  `get_admin_dashboard` (após confirmar semântica).
- **Onda 3 — #1477 TCV:** `check_my_tcv_readiness` (elegibilidade por engagement, não rótulo).
- **Classe B/C:** só documentar/ratificar (não mexer sem decisão). Fechar #1476 quando A+B/C resolvidas; #1477 na Onda 3.

## Regras da casa (herdadas)
- DDL só via `apply_migration` byte-fiel; `Write` arquivo local `supabase/migrations/`; `migration repair`; `NOTIFY pgrst`.
- `CREATE OR REPLACE` de função compartilhada: basear no corpo VIVO (`pg_get_functiondef`), não em grep da 1ª migration.
- Teste novo nas 2 whitelists do `package.json`. `npx astro build` + `npm test` (com secrets). Merge = sessão main.
- Sem em-dash. Trailer `Assisted-By: Claude (Anthropic)`.
