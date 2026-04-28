# Council Tier 3 Synthesis — Issues #87 / #88 / #97

**Data:** 2026-04-28
**Convocação:** PM (Vitor Rodovalho) durante sessão p74 marathon
**Agents convocados (11 paralelos):** product-leader (×3) + ux-leader (×2) + accountability-advisor (×2) + legal-counsel (×2) + ai-engineer (×1) + c-level-advisor (×1) + startup-advisor (×1)
**Output:** synthesis para PM-decision

---

## Issue #87 — Selection bias-prevention

### Consenso forte (4 agents)

**Ship W2 (anti-bias RPC patch) esta semana**, antes de qualquer outra wave.

- product-leader: dano ativo no ciclo B2; W2 single item irreversível-se-não-fizer
- accountability-advisor: CBGPL audit 28/Abr; cada hora de delay = avaliação influenciada permanente
- ux-leader: anti-pattern Greenhouse/Linear; `hidden_fields` explicit > null silent
- legal-counsel: blind review é execução operacional do Art. 20 LGPD (revisão humana de decisão automatizada)

### Divergência

- **ux-leader exige confirm gate em `submit_evaluation`** (padrão ADR-0018 W1) com `application_summary` no preview
- **legal-counsel BLOQUEIA W4 (LLM analyze) sem 4 ajustes não-negociáveis**:
  1. Consent granular destacado (não bundled)
  2. Retenção por coluna (`cv_extracted_text` 90d, `ai_analysis` 90d, `linkedin_relevant_posts` purge imediato)
  3. Identificar LLM provider no consent
  4. Verificar contrato LLM provider tem LGPD (não só GDPR) — Red Flag: transferência internacional Art. 33

### PM decisions needed

1. Process owner para B2 nomeado HOJE
2. ADR retroativo documentando o gap + decisão de remediar
3. Comunicação aos 6 avaliadores ativos antes do deploy
4. Tratamento das 186 evaluations já submitted "com bias visibility": manter com nota
5. W4 (LLM analyze): adiar para Q3 2026
6. W3 priorização: avaliador-first (Pareto: pending_evaluations + application_detail + submit_evaluation)

### Sequência recomendada

| Wave | Quando | Esforço |
|---|---|---|
| W2 anti-bias RPC | Esta semana | 1 dia |
| W5 manage_event sweep | Esta semana paralelo | 2h |
| W1 schema hardening (cycle phase + LinkedIn fields aditivos) | Esta semana paralelo | 2h |
| ADR retroativo + process owner | Antes do deploy W2 | 30min |
| W3 avaliador-first (3 tools Pareto) | Pós-W1 | 2 dias |
| W6 self-discovery enrichment | Junto com W3 | 1 dia |
| W4 LLM analyze | Q3 2026 (decisão budget separada) | 2-3 dias |

---

## Issue #88 — Convocação iniciativas

### Consenso forte

**W1 fix `manage_initiative_engagement` enforcement = prerequisite ZERO**. Bug schema-vs-RPC bloqueia tudo.

### Divergência sequência pós-W1

**product-leader**: Comms (W4+W5) antes de tudo. Comms operacional > CPMAI ad-hoc.
**ux-leader**: Antes de adicionar tools, criar action `manage_initiative` no V4 catalog. Sem authority gate, tools = cosmético.
**accountability-advisor**: 4 mitigations BLOCKING antes de QUALQUER tool nova.

### Sequência correta sintetizada

```
0. ADR + invitations table + pii_access_log              [accountability BLOCKING]
1. Action manage_initiative no engagement_kind_permissions [ux + governance]
2. W1 patch RPC manage_initiative_engagement              [product-leader]
3. invite_to_initiative com message obrigatório + batch    [ux]
4. accept/decline + list_my_invitations                   [ux]
5. Comms 8 write tools com manage_initiative funcionando   [product-leader]
6. Skill launch-webinar (granular, não polivalente)        [ai-engineer]
```

### PM decisions needed

1. `join_policy` field em initiatives: `invite_only` | `request_to_join` | `open`
2. Batch invite max size: 30 (Cycle 3 volume)
3. Self-service join (W7): **NÃO ainda** — todos 4 agents flagam mudança organizacional
4. Canva MCP $100/mo: validar uso real do comms team antes
5. Skill design: 3 granulares (launch-webinar, launch-publication, launch-newsletter) > 1 polivalente
6. `manage_event` action: ADR ou remover do catalog (não deixar vazio)
7. Content Governance Policy 1 página antes de comms write tools (revisor + prazo + critérios)
8. Declaração escrita autonomia operacional dos presidentes capítulos antes de delegar

### Worst-case de governance (accountability-advisor)

PMI Latam audita capítulo parceiro. Pergunta: "mostrem registros de quem aprovou entrada do membro X em CPMAI". Resposta hoje: não existe log. Consequência: capítulo parceiro perde credenciamento PMI; presidente exposto; Núcleo IA perde contratos multi-capítulo (Path A bloqueado).

Mitigação: invitations table + pii_access_log + ADR formal — sem isso, **delegar permissão é distribuir exposição**, não responsabilidade.

---

## Issue #97 — LATAM LIM 2026

### Divergência estratégica

| Agent | Posição | Razão |
|---|---|---|
| c-level-advisor | W2+G7 NOW; W3 trigger=2º congresso | LIM é caso 1 de série; whitepaper precisa 3 casos comparáveis |
| startup-advisor | Apenas G7 + 3 micro-experimentos | YC pattern: build manual até dor; invest só após 2-3 repetições |
| product-leader | G7 isolado; G1+G4 batch com #88; G6+W2 defer pós-LIM | Triggers explícitos por gap |
| legal-counsel | Independente: 4 red flags pré-deploy contratuais | Termo de Speaker SEPARADO do welcome é não-negociável |

### Consenso (3 de 4 agents)

**Ship G7 (welcome email) esta semana, isolado**. Substrate pronto, esforço baixo (~30 linhas trigger + 1 EF stub + templates por kind), padrão escalável.

### PM decision crítica

Você tem sinal CONCRETO de 2º congresso institucional em 6 meses (LIM 2027, Detroit, Tasc/IISE)?

- **SIM** → c-level-advisor wins: W2 + G7 NOW
- **NÃO** → startup-advisor wins: G7 only + micro-experimentos (doc manual + debrief 30min + ProjectManagement.com article até setembro)
- **TALVEZ** → product-leader wins: G7 isolado + G1+G4 batch quando #88 W4 começar

### Legal não-negociáveis — RETRATADO PM 2026-04-28

PM identificou que itens 1, 3, 4, 6 abaixo foram baseados em premissa
INCORRETA do agent legal-counsel: assumiu cenário "commercial speaker
contract com assignment clauses" típico de keynote pago em conferência
industrial. **Realidade**: Núcleo aceito para apresentar proposta
peer-reviewed em LATAM LIM 2026 — sem contrato comercial, sem assignment
de direitos, sem benefício patrimonial requerendo disclosure (comp/discount
a speakers é prática institucional padrão de conferências PMI).

**Itens válidos (mantidos):**
- Item 2: Termo de Speaker específico SEPARADO do welcome email — válido
  como guideline para outros engagement_kinds com `requires_agreement=true`,
  não específico ao LATAM LIM
- Item 5: Welcome email NUNCA bundled com cessão autoral — válido como
  constraint geral em ADR-0060 G7 (incorporado)

**Itens retratados (não aplicam):**
- Item 1: ~~contrato PMI Lima com assignment clause~~ — não há contrato
  comercial; aceite peer-reviewed apenas
- Item 3: ~~LGPD Art. 33 transferência internacional~~ — só relevante se
  PMI Global processar dados pessoais via gravação oficial pós-evento;
  validar quando aplicável
- Item 4: ~~disclosure formal complimentary/discounted~~ — comp/discount
  a speakers em conferência PMI é institutional norm, não conflito de
  interesse requerendo formal disclosure
- Item 6: ~~co_speaker engagement_kind com contribution_type~~ — válido
  como melhoria semântica futura; não bloqueante para LIM 2026

**Lição aprendida**: ao invocar legal-counsel agent, validar premissa de
cenário comercial vs acadêmico antes de aceitar parecer. Council Tier 3
é consultivo — PM filtra premissas antes de PM-action items.

### Whitepaper framing (startup-advisor)

❌ "AI-augmented PMI chapter ops" — narrow demais
✅ **"How community-led organizations run institutional operations at scale without full-time staff"**

Audience: PMI publications, HBR LatAm, SSIR. Caso 1 = LIM 2026. Próxima ação: gravar debrief 30min com Roberto+Ivan na semana seguinte ao evento (audio = whitepaper draft).

---

## TL;DR PM-only decisions

1. **#87**: Você nomeia process owner para B2 + autoriza ADR retroativo + comunica os 6 avaliadores? (Se sim → ship W2 + W5 + LinkedIn fields ~6h)
2. **#88**: Comms-first OU Authority-first? (Comms-first = ship ~1 semana mas tools podem fail Unauthorized; Authority-first = ship ~2 semanas com base sólida)
3. **#97**: Sinal concreto de 2º congresso em 6 meses?

---

## Trace

- Sessão p74 marathon (12º push: Council Tier 3)
- 11 agents paralelos
- Total tokens consumidos: ~382k
- Outputs preservados em transcripts da sessão
- Cross-ref: ADR-0007 (V4 authority), ADR-0011 (cutover canV4), ADR-0022 (communication batching), ADR-0018 (confirm gate pattern)

Assisted-By: Claude (Anthropic) + 11-agent council
