# Track B — Champion ata-capture flow: design call (p162)

**Date:** 2026-05-15 (sessão p162)
**Convened by:** PM Vitor
**Lenses:** 3 personas (gp-leader, active-volunteer, sponsor-liaison) + 3 disciplinares (product-leader, ux-leader, data-architect)
**Output:** consolidated recommendation + invariantes + risks

## 3 Design questions

- **Q1** — Onde dispara o prompt? (a) modal pré-publish / (b) sidebar opt-in / (c) card pós-publish
- **Q2** — Mandatório ou opt-in? (a) mandatório + checkbox "Nenhum"+justificativa / (b) opt-in silencioso
- **Q3** — Estrutura DB? (a) `champion_grant_ids uuid[]` em meeting_artifacts / (b) só via `champions_awarded.context_id`

Recomendação inicial PM: 1a + 2a + 3b.

## Voto consolidado

| Lente | Q1 | Q2 | Q3 | Caveat principal |
|---|---|---|---|---|
| **gp-leader** | 1a | 2a (com justificativa curta) | 3b | "Reuniões de 20min com 3 pessoas — cerimônia desproporcional. 1 clique pra Nenhum em reuniões pequenas." |
| **active-volunteer** | 1a (com ressalva) | 2a (justificativa **opcional** no negativo) | 3b | "Champion sem contexto vira robô. Texto livre 140 chars opcional preserva o calor." |
| **sponsor-liaison** | 1a (única opção real) | 2a | 3b | "Sem justificativa, 'Nenhum' e 'esqueceu' são indistinguíveis no relatório board." |
| **product-leader** | 1a | **2a com warm-up 30d** | 3b | "Mandatório dia 1 sem buy-in gera gaming. Fase 0 opt-in → Fase 1 gate." |
| **ux-leader** | 1a **inline NÃO modal sobreposto** | 2a com **friction symmetry** ("Nenhum" deve ser tão fácil quanto "Sim") | 3b | "Modal overlay em 375px com UUID paste = anti-mobile. Inline accordion na mesma tela de publish." |
| **data-architect** | (escopo UX) | (precisa coluna c para enforce) | **3b + adicionar `champion_decision jsonb` (variant c)** | "Sem coluna decision: impossível distinguir pending vs deliberadamente-nenhum. Coluna c é load-bearing para Q2a." |

## Decisões consolidadas

### Q1 — Inline gate na tela de publish (refined 1a)

**Não é modal sobreposto.** É uma seção inline expandida na mesma página de edição de ata quando líder clica "Publicar". Funciona em mobile (375px) sem overlay risks + permite scroll natural + sem UUID paste.

Padrão (ux-leader):
```
GP clica "Publicar ata"
  → seção inline expande abaixo do botão:
    Pergunta binária "Houve Champion?" toggle Sim/Não
      Se Sim: typeahead por nome (pre-pop attendees) → criteria checklist → justificativa
      Se Não: textarea opcional ("ex: reunião técnica sem apresentação formal") — sem mínimo de chars
  → botão final "Confirmar e Publicar"
```

### Q2 — Mandatório com friction symmetry + phased rollout

**Fase 0 (Dia 1-30) — opt-in suave:** seção inline visível mas não bloqueante. Mede behavior real + permite onboarding orgânico.

**Fase 1 (Dia 31+) — gate ativo:** Champion ou "Nenhum" obrigatório. **Caminho negativo NÃO deve custar mais que positivo:**
- Caminho positivo: typeahead + 1-4 criteria + 50-char justificativa
- Caminho negativo: 1 toggle "Não houve destaque" + textarea **opcional** (sem mínimo de chars)

**Sentinela anti-gaming (Fase 1+):** monitorar Nenhum-rate por GP. Alerta admin se um GP específico tem >60% Nenhum em 4 reuniões consecutivas. Não bloqueia — apenas alerta.

### Q3 — Hybrid b + c (architectural shift)

**Manter (b):** `champions_awarded.context_id = meeting_artifact_id` para ledger. **Sem array em meeting_artifacts.**

**Adicionar (c):** nova coluna `meeting_artifacts.champion_decision jsonb` com shape:
```jsonb
{ "status": "pending|awarded|none",
  "reviewed_at": "2026-05-15T...",
  "reviewed_by": "<member_id>",
  "no_champion_reason": "<text, optional>" }
```

**Por que (c) é load-bearing:**
- (b) sozinha: ata sem Champion = COUNT(champions_awarded WHERE context_id=?) = 0. **Indistinguível** entre "líder esqueceu/nunca abriu modal" e "decidiu deliberadamente Nenhum".
- (c) adiciona: `pending` (não processou) ≠ `none` (decidiu Nenhum) ≠ `awarded` (decidiu Sim, ledger em champions_awarded).

**Invariantes novos** (data-architect proposal):
```sql
-- I_champion_decision_awarded_consistency
-- Se champion_decision.status='awarded', deve haver ≥1 champion ativo
SELECT count(*) FROM meeting_artifacts ma
WHERE (ma.champion_decision->>'status') = 'awarded'
  AND NOT EXISTS (
    SELECT 1 FROM champions_awarded ca
    WHERE ca.context_kind='artifact' AND ca.context_id=ma.id AND ca.status='active'
  );
-- Expected: 0

-- I_champion_decision_none_no_active
-- Se champion_decision.status='none', não pode haver champion ativo
SELECT count(*) FROM meeting_artifacts ma
WHERE (ma.champion_decision->>'status') = 'none'
  AND EXISTS (
    SELECT 1 FROM champions_awarded ca
    WHERE ca.context_kind='artifact' AND ca.context_id=ma.id AND ca.status='active'
  );
-- Expected: 0
```

## KPIs pós-launch (product-leader)

| KPI | Baseline | Target 60d |
|---|---|---|
| Champion adoption rate | 0% (histórico) | >50% Fase 0, >80% Fase 1 |
| Time-to-publish (ata) | medir Fase 0 | sem aumento >+90s vs pre-feature |
| "Nenhum" rate | — | <20% sustentado pós-Fase 1 |
| Criteria utilization (% grants c/ critério marcado) | 0% | >70% — sinal de intenção genuína vs compliance theater |

## Risks priorizados

| Rank | Risk | Mitigação |
|---|---|---|
| 1 | Modal overlay quebra em mobile (375px iOS auto-zoom) | **Inline accordion, não overlay.** font-size ≥16px nos inputs. Touch targets ≥44px. |
| 2 | Líder publica "Nenhum + texto vazio" pra burlar gate | Friction symmetry + sentinela Nenhum-rate >60% (alert admin). |
| 3 | Champion sem context_id auditável após revoke | Manter (b) `champions_awarded.context_id` como source of truth. (c) `champion_decision` não muda ao revogar — revogação é evento pós-decisão. |
| 4 | Reuniões muito curtas (1on1, partial leaderança) | Bypass: só atas `meeting_artifacts` (= reuniões deliberativas) — não 1on1/parceria/entrevista. Já alinhado com Track C event.type filter. |
| 5 | UX requer reescrita do `/admin/gamification` modal antes de Track B | Confirmado pela ux-leader: o modal atual usa UUID paste + falha em mobile. Track B precisa typeahead + attendee suggestion antes de prod. |

## Path-impact (Trentim)

- **Path A (PMI internal):** Champion ranking + criteria audit trail = artefato pronto para PMI Global "impact evidence" reports (CBGPL Detroit, chapter relatórios).
- **Path C (community):** transparência de Champion + ranking = retention/engagement orgânico. Sponsor-liaison validou que esse é o sinal que ele leva ao chapter board.
- **Path B (consulting):** capacidade de plataforma demonstrável em demos (whitelabel para outros PMI chapters).

## Implementation phasing

| Fase | Escopo | Effort | Output |
|---|---|---|---|
| **B1 (~1h)** | Migration: ALTER TABLE meeting_artifacts ADD COLUMN champion_decision jsonb NULL + 2 invariantes em check_schema_invariants | M | Schema ready, invariantes guarded |
| **B2 (~3h)** | RPC update_meeting_artifact_champion_decision(artifact_id, decision_status, reason?) + RPC publish_meeting_artifact_v2 com optional p_champion_decision | M | DB layer ready |
| **B3 (~3-4h)** | Inline section em pagina de edição de ata (não modal): toggle Sim/Não + typeahead attendees + criteria checklist + justificativa | L | Frontend B Fase 0 (opt-in) |
| **B4 (~1h)** | Toggle de Fase: feature flag `champion_capture_gate_mandatory` env var + gate enforcement em RPC publish | S | Phasing-ready |
| **B5 (~30min)** | Sentinela query + admin alert ("GP X teve N Nenhum consecutivos") | S | Operational visibility |

Total estimated: **~8-9h** (vs original ~2-3h da minha proposta) — escala porque arquitetura UX foi corrigida (inline em vez de modal) e column (c) adicionada para enforce.

## Cross-references

- ADR-0081 (gamification config-driven + Champions ledger)
- ADR-0012 (schema consolidation principles — coluna c respeita Princípio 2 fact column ≠ cache)
- ADR-0009 (config-not-code — invariantes adicionados em check_schema_invariants)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` — item #9 OPP Champion capture flow

## Decisão pendente PM

- [ ] Confirma synthesized recommendation: **inline (não modal) + phased mandatório (warm-up 30d → gate) + b+c hybrid (context_id + champion_decision jsonb)?**
- [ ] Ship B1+B2 nesta sessão (foundation DB) + B3-B5 em p163?
- [ ] OU descer para algo menor para acomodar tempo restante (e.g., só B1+B2 agora, ship inline UI próxima sessão)?
