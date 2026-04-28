# ADR-0059: Selection cycle phase state machine + blind review enforcement

| Field | Value |
|---|---|
| Status | Accepted (retroactive — gap identificado em ciclo ativo) |
| Date | 2026-04-28 (sessão p74, council Tier 3) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude + 4-agent council) |
| Migration | `20260514290000_adr_0059_selection_phase_blind_review_anti_bias.sql` |
| Issue | #87 (selection bias-prevention) |
| Cross-ref | ADR-0007 (V4 authority), ADR-0011 (canV4), council synthesis 2026-04-28 |

## Context

Council Tier 3 review (4 agents — product-leader, accountability-advisor,
ux-leader, legal-counsel) convergiu unanimemente: `get_application_score_breakdown`
durante phase de avaliação ATIVA expõe `evaluator_name` + `scores` brutos a
qualquer member com gate manager/curator. Resultado: avaliador A vê tudo do
avaliador B antes de submeter próprio score → enviesa peer-review em direção
a "alinhar" com B.

Estado quando issue foi aberta:
- `selection_cycles.status` enum binário (open/closed) — sem fase fina
- `cycle3-2026-b2` aberto recebendo 186 evaluations
- 6 selection_committee members com gate curator
- CBGPL audit window: 28/Abr (mesmo dia desta decisão)

Esta é uma **gap retroativa**: o código vivia em produção. A descoberta
não invalida as 186 evaluations já submetidas, mas exige documentação
explícita do gap + remediação para avaliações futuras + ADR formal antes
do CBGPL.

## Decision

Implementar state machine de fases no ciclo seletivo + blind enforcement
em `get_application_score_breakdown` durante phases sensíveis.

### State machine (11 phases)

```
planning → applications_open → screening → evaluating[BLIND]
  → evaluations_closed → interviews_scheduling → interviews[BLIND]
  → interviews_closed → ranking → announcement → onboarding
```

Phases marcadas `[BLIND]` ativam:
- `get_application_score_breakdown` retorna apenas evaluation do próprio caller
- Campo `blind_review_active: true` + `hidden_fields: [...]` no payload de retorno
- Superadmin override (governance backstop) — sempre vê tudo

### RPC patch

```sql
v_blind := COALESCE(v_cycle.phase, 'planning') IN ('evaluating', 'interviews')
           AND v_caller.is_superadmin IS NOT TRUE;

-- Blind path: WHERE e.evaluator_id = v_caller.id
-- Reveal path: sem filtro + is_own flag por row
```

### Anomaly table + trigger

`selection_evaluation_anomalies` rastreia 4 alert_types:
- `high_variance` — stddev > 1.5 entre avaliadores
- `outlier_score` — score > 2 stddev do mean
- `late_submission` — submitted após phase fechada
- `blind_violation_attempt` — tentativa de read durante 'evaluating'

Trigger `trg_compute_evaluation_anomalies_on_phase_change` dispara em
`UPDATE phase = 'evaluations_closed' WHERE OLD.phase = 'evaluating'`,
calcula stddev por application e flagga anomalies.

### Backfill

- `cycle3-2026` (status=closed) → `phase='announcement'` (ciclo já anunciado)
- `cycle3-2026-b2` (status=open) → `phase='evaluating'` (mid-evaluation, 186 evals submetidas)

## Consequences

**Positive:**
- Cycle B2 imediatamente protegido — novas avaliações em phase 'evaluating'
  não veem scores alheios
- State machine substitui binário status, permite UX/RPC granulares por fase
- Anomaly trail audit-ready para CBGPL (28/Abr) + futuros cycles
- Superadmin override preservado (PM pode investigar incidentes)
- `is_own` flag em reveal phase distingue self vs peer

**Neutral:**
- 186 evaluations já submetidas "com bias visibility" mantidas (não
  invalidadas) — registrado em ADR como decisão consciente
- Existing callsites continuam funcionando (DROP+CREATE preserva signature)

**Negative:**
- Avaliador acostumado a ver scores alheios pode estranhar — UX requer
  comunicação prévia (operacional, não código)
- Phase transitions exigem disciplina operacional (PM ou GP avança fases
  manualmente até automation chegar)

## Process owner para B2 (accountability gap)

**PM (Vitor Rodovalho)** assume process ownership formal de B2 a partir
desta data. Responsabilidades:
- Comunicar 6 avaliadores ativos sobre mudança pós-deploy
- Avançar phase do cycle B2 para 'evaluations_closed' quando completas
- Investigar anomalies geradas pelo trigger
- Escalar para council Tier 3 se SLA de avaliações for violado

## Tratamento das 186 evaluations já submitted

Mantidas (não invalidadas). Razão: invalidar criaria disruption
desproporcionalmente maior do que o risco de bias parcial — não há como
provar que cada score foi efetivamente influenciado. Para audit:

> "Avaliações submetidas até 2026-04-28 (data deste ADR) foram realizadas
> sob arquitetura sem blind enforcement. Gap identificado, remediado em
> migration 20260514290000. Avaliações posteriores operam sob blind mode
> em phases evaluating/interviews."

Essa nota ficará no registro do ciclo (selection_cycles ou doc
equivalente).

## Comunicação aos avaliadores ativos (post-deploy)

Email curto aos 4 avaliadores ativos confirmados via `selection_committee`
(query 2026-04-28): **Vitor Maia Rodovalho** (PM, 226 evaluations submitted),
**Fabricio Costa** (deputy_manager, 142), **Sarah Faria Alcantara Macedo
Rodovalho** (curator, 2), **Roberto Macêdo** (curator/chapter_liaison,
0 — committee member sem submitted ainda):

> Implementamos blind review enforcement em fase de avaliação ativa.
> A partir de hoje, ao consultar uma application durante phase 'evaluating',
> você verá apenas sua própria avaliação. Scores e nomes de outros
> avaliadores ficam ocultos até o GP avançar a fase para 'evaluations_closed'.
> Esta mudança alinha o processo às boas práticas de peer-review e padrões
> PMI Code of Ethics. Nenhuma avaliação já submetida foi invalidada.

(Owner: PM enviar via canal preferido — email ou WhatsApp Núcleo IA Hub.
Como PM é também avaliador, comunicar aos outros 3: Fabricio, Sarah, Roberto.)

## Verification

- [x] Migration applied (`20260514290000`)
- [x] cycle3-2026-b2 phase = 'evaluating'
- [x] cycle3-2026 phase = 'announcement'
- [x] Schema invariants 11/11 = 0
- [x] Tests preserved (will run pré-commit)
- [x] Council Tier 3 sign-off (4 agents convergent)
- [ ] Post-deploy: comunicação aos 6 avaliadores (PM owner)
- [ ] Pré-CBGPL audit (28/Abr): este ADR + migration arquivados
- [ ] First phase transition test: PM avança B2 → 'evaluations_closed' quando
      avaliações completas; verificar trigger fire em
      selection_evaluation_anomalies

## References

- Issue #87 (full body)
- Council synthesis: `docs/council/decisions/2026-04-28-tier-3-issues-87-88-97-synthesis.md`
- ADR-0007 (authority-as-engagement-grant)
- ADR-0011 (canV4 cutover)
- PMI Code of Ethics Sec. 2 (Fairness) + Sec. 4 (Accountability)
- LGPD Art. 20 (revisão humana de decisão automatizada)

## Pattern sedimented

32. **Phase state machine for governance-sensitive workflows**: when a
    binary status (open/closed) doesn't capture transition semantics
    (e.g., evaluation flow has BLIND vs REVEAL sub-phases), introduce
    fine-grained enum + RPC predicates that check phase membership.
    Trigger anomaly computation on transitions. Always preserve a
    superadmin override for governance backstop.

Assisted-By: Claude (Anthropic) + council 4-agent Tier 3
