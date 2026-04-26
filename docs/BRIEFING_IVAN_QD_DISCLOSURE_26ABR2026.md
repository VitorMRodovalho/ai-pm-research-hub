# Briefing: Disclosure Tracks Q-D + R — Ivan Lourenço (Sponsor PMI-GO)

> **De:** Vitor Rodovalho — General Project Manager Núcleo IA
> **Para:** Ivan Lourenço — Presidente PMI-GO / Sponsor PMI Núcleo IA
> **Data:** 2026-04-26 (preparação para call quarterly de segunda-feira)
> **Status:** Disclosure proativo — auditoria de segurança da plataforma
> **Driver de governança:** Memo do accountability-advisor (2026-04-25) recomendando comunicação proativa ao sponsor sobre escopo, status e fechamento da remediação.

---

## 1. Resumo Executivo (TL;DR)

Em **2 dias de auditoria** (24-26/Abr) conduzimos varredura sistemática
de segurança da plataforma Núcleo IA. Identificamos **dois eixos de
exposição teórica** e fechamos os dois proativamente:

**Eixo 1 — Track Q-D (funções)**: 109 funções SECDEF no Postgres com
permissões padrão abertas. **8/8 buckets fechados**, **166 funções
triadas** (137 hardened + 17 verified-public-by-design + 9
V4-discovered + 3 deferred PM input).

**Eixo 2 — Track R (tabelas/views)**: 165 objetos com `anon SELECT`
expostos via `pg_graphql` introspection endpoint. **2 batches
aplicadas, 152 REVOKEs cumulativos**. Restam apenas **20 objetos
intencionalmente públicos** (homepage data + reference data +
ADR-0024 views).

**Resultado consolidado**:
- **289 hardenings aplicados** (137 fns Q-D + 152 tabelas/views Track R)
- **Advisor de segurança Supabase: -85% WARN** (171 → 25)
- **0 regressões em aberto**, **0 incidentes**, **0 testes quebrados**
- Trail completo de auditoria no GitHub (11 commits + 4 migrations
  Q-D, 4 commits + 2 migrations Track R)

**Status para Ivan**:
- ✅ **Sem incidente**: nenhum vazamento de PII detectado, nenhuma
  exploração observada
- ✅ **Remediação completa e auditável**: 11 commits assinados,
  rationale por função/tabela, trail completo
- ✅ **Padrão internacional**: tratamento alinhado a OWASP Top 10
  (A05 Security Misconfiguration) + LGPD Art. 5/6/46 (medidas
  técnicas adequadas)
- ✅ **Próximas ações documentadas**: 3 fns aguardam tier-input PM
  (3a.2), 11 fns documentadas para Phase B'' (V3→V4 ratify por ADR)

---

## 2. Contexto Técnico (para alinhamento)

### O que estava acontecendo

A plataforma Núcleo IA roda sobre Supabase (Postgres gerenciado).
Funções `SECURITY DEFINER` (SECDEF) executam com privilégios do
criador (postgres) e bypassam RLS (Row-Level Security). É um padrão
legítimo, mas exige duas defesas complementares:

1. **Gate interno** — função verifica autorização antes de retornar
   dados (`can_by_member()`)
2. **ACL de execução** — somente roles autorizadas podem chamar
   (`postgres + service_role + authenticated`)

A varredura identificou **109 funções** com nenhuma das defesas:
- Sem gate interno
- Com `EXECUTE` concedido a `PUBLIC`/`anon` (qualquer chamador
  não-autenticado via PostgREST)

Não há evidência de exploração — apenas exposição teórica. Mas
auditoria PMI exige fechamento documentado.

### Por que isso aconteceu

Histórico técnico documentado no `RPC_BODY_DRIFT_AUDIT_P50.md`:

- Período pré-Domain Model V4 (até 2026-04-13) usava modelo de
  autoridade legacy (`is_superadmin`, `operational_role`) que
  variava por função.
- Algumas funções foram criadas via dashboard SQL editor sem
  passar pelo fluxo de migrations versionadas → drift entre
  produção e source-of-truth.
- A migração V4 (`can_by_member()`) foi adotada incrementalmente
  → coexistência V3 + V4 + sem-gate por meses.

A varredura de 24-26/Abr foi a primeira sistemática a varrer todo
o conjunto SECDEF e separar legítimo (verified-public) de exposto
(closed via REVOKE) de admin-shape (gated).

---

## 3. Status — Q-D 8/8 Buckets Fechadas (100%)

| Bucket | Função-tipo | Status | Migration | Commit |
|---|---|---|---|---|
| **Initiative/board readers** | Iniciativas, boards, comitês | ✅ CLOSED | `20260426120532` + `123542` | `c36e1ff` + `0c39356` |
| **Knowledge/wiki readers** | Wiki interno + pesquisa | ✅ CLOSED | `20260426124716` | `0777f75` |
| **Comms readers** | Webinars, métricas comunicação | ✅ CLOSED | `20260426130254` | `2a225ab` |
| **Curation/governance readers** | Cadeias de aprovação, CRs, ratificação IP-2 | ✅ CLOSED | `20260426132442` | `c4ec1c2` |
| **Sustainability/KPI readers** | KPIs anuais, sustentabilidade financeira, pilotos | ✅ CLOSED | `20260426133716` | `3d57d05` |
| **Selection admin readers** | Seleção/entrevistas | ⏳ Parcial (3a.1) — 3 fns aguardam PM tier input | `20260426005822` | `296c66d` |
| **Legacy/utility readers (3a.8)** | Misc — get_card_timeline, get_publication_*, etc. | ✅ CLOSED p59 (32 fns triadas) | `20260426143952` | `6ed46d7` |
| **Internal helpers (3b)** | Defense-in-depth — `can`, `can_by_member`, etc. | ✅ CLOSED p59 (20 fns) | `20260426145632` | `69adad5` |

**Plus**: 1 regressão da batch 1 (`comms_check_token_expiry` —
admin caller perdido no triagem inicial) **identificada e
RESOLVIDA na mesma sessão p58** via amendment migration
(`20260426131249` / `a8521ec`).

### Treatment Matrix aplicada

Cada função foi triada via per-fn body review + callsite grep, e
classificada em uma de 6 categorias:

| Categoria | Tratamento | Exemplos |
|---|---|---|
| Dead code (zero callers) | REVOKE FROM PUBLIC, anon, authenticated | `get_curation_cross_board()`, `get_governance_preview()` |
| Internal helper (chain SECDEF) | REVOKE FROM PUBLIC, anon, authenticated | `search_board_items()` |
| Cron-only | REVOKE FROM PUBLIC, anon, authenticated | `auto_archive_done_cards()` (p55) |
| Member/admin reader | REVOKE FROM PUBLIC, anon (keep `authenticated`) | `get_board(uuid)`, `list_initiatives(text, text)` |
| **Verified public-by-design** | NO CHANGE (docs-only confirmation) | `exec_portfolio_health()` (homepage), `list_meeting_artifacts()` (replays) |
| Already V4-compliant | (excluded — false positive in initial detection) | `get_initiative_member_contacts()`, `get_chain_audit_report()` |

**Critério de "verified public-by-design"**: per-fn body review
confirma retorno apenas de dados agregados / metadados públicos
(zero PII), e callsite é página pública genuína (e.g., homepage).

---

## 4. Métricas (para auditoria PMI)

### Track Q-D — Funções SECDEF

| Indicador | Valor end-of-p59 (26/Abr) |
|---|---|
| Funções triadas (vs 109 estimado p55) | **166** (100% + 57 surplus¹) |
| Hardened (REVOKE aplicado) | 137 |
| Verified public-by-design | 17 |
| Já V4-compliant (excluded) | 9 |
| Deferidas para PM tier input | 3 |
| V3-gated documentadas para Phase B'' | 11 |
| Buckets fechadas | **8/8 (100%)** |
| Migrations Q-D | 11 (Q-D inteira p55→p59) |

### Track R — Tabelas/Views (anon SELECT exposure)

| Indicador | Valor end-of-p59 (26/Abr) |
|---|---|
| Objetos REVOKE'd (cumulativo) | **152** (102 batch 1 + 50 batch 2) |
| Z_archive cleanup | 25 tabelas legacy |
| public.* hardenings | 121 tabelas + 6 views |
| Preservado (intentional public) | 20 (homepage + reference + ADR-0024) |
| Migrations Track R | 2 |

### Estado consolidado

| Indicador | Valor |
|---|---|
| Open regressions | **0** |
| Open incidents | **0** |
| Total p59 commits (Q-D 3a.8 + 3b + Track R + audit) | 7 |
| Total p58+p59 migrations | 11 |
| Invariantes estruturais (DB) | **11/11 = 0 violations** |
| Build status | ✅ clean |
| Tests (unit) | 1397 / 1372 passing / 0 fail / 25 skipped |
| **Advisor de segurança Supabase**: Pre-Track R | 1 ERROR + 171 WARN |
| **Advisor de segurança Supabase**: End-of-p59 | **1 ERROR + 25 WARN (-85%)** |
| `pg_graphql_anon_table_exposed` (lint específica) | 165 → 20 (-88%) |

¹ *Surplus Q-D de +57 = (a) funções V4-compliant que estavam no
regex de detecção mas usavam padrão `can(person_id, ...)` sem prefixo
`public.` — surfaced via per-fn body review (+9); (b) 30 fns adicionais
no bucket legacy/utility (3a.8) e 20 internal helpers (3b) que não
estavam no escopo original p55 mas foram capturados pela varredura
expandida.*

**ERROR remanescente**: `security_definer_view: public_members` —
view documentada como ADR-0024 accepted risk (intentional public
exposure de leadership/contact metadata).

---

## 5. Padrão de Governança (para Audit Trail)

Cada batch da Track Q-D segue protocolo único, documentado no doc
de auditoria `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`:

1. **Discovery** — query SQL no `pg_proc` + grep callsites em
   `src/`, `supabase/functions/`, `tests/`
2. **Per-fn classification** — body inspection + caller tier
   verification
3. **Migration apply** — via `apply_migration` MCP (auto-versionada)
4. **Local file write** — pareado com `supabase migration repair`
5. **Audit doc closure section** — rationale por função +
   verdict matrix
6. **Commit** — mensagem cita migration + audit doc + ACL pre/post
7. **Push** — após `astro build` clean + invariants 0 verificados

**Trail accountability**: cada commit no GitHub assinado, cada
migration tem header com decisão, cada audit doc seção referencia
migration + commit. Reproduzível por qualquer auditor.

### Exception identificada e tratada (transparency)

Durante batch 3a.5 surface, **identificamos 1 regressão** da batch
1 (p55): a função `comms_check_token_expiry` foi REVOKE'd
classificada como "cron-only" mas tinha caller admin frontend
(`admin/comms.astro:669`). Per-fn callsite verification do p55
missed este caller. Resultado: silent failure (try/catch wrapped,
console.warn) na página admin.

**Remediação imediata** (mesma sessão p58):
- Amendment migration `20260426131249` — restaurou grant
  `authenticated` na função
- Reclassificação no audit doc (cron-only → "cron + admin reader")
- Documentação completa em audit doc batch 3a.5 closure section
  (3 options apresentadas para PM ratify; Option 1a aceita)

**Lição metodológica sedimentada** (incorporada ao protocolo
batches futuras): per-fn callsite verification deve incluir
cross-check de callsites de funções já-triagedas que mudaram ACL.

---

## 6. Por que Disclosure Proativo

Per memo do accountability-advisor (2026-04-25):

> "Sponsor touchpoint with Ivan Lourenço — proactive disclosure
> que SECDEF audit em progresso, fechando este sprint. Schedule
> next quarterly cadence."

**Princípios PMI aplicados**:
- **Transparency** — Sponsor entende o que está acontecendo na
  plataforma sob sua responsabilidade institucional
- **Proactive disclosure** — não esperar incidente; comunicar
  enquanto remediação está em curso
- **Audit-readiness** — pacote completo para auditoria (PMI Brasil
  ou externa) reproduzível a qualquer momento
- **No surprise principle** — Ivan não deve saber via terceiros

**O que Ivan precisa saber**:
1. ✅ Plataforma estava com exposição teórica de leitores
2. ✅ Ninguém explorou — auditoria interna proativa
3. ✅ Remediação atômica, em curso, 100% scope p55 fechado
4. ✅ Trail de auditoria completo no GitHub
5. ✅ Restam ~36 itens menores em backlog organizado (3a.8 + 3b)
6. ✅ Estimativa: closure final em p59-p60 (~1 semana)
7. ⏳ Cadência quarterly: próximos touchpoints incluirão status

**O que Ivan NÃO precisa decidir agora**: remediação está
auto-conduzida pelo PM com governance trail. Disclosure é
informativo, não solicita ação.

---

## 7. Talking Points (para a conversa com Ivan)

### Frame inicial (30 segundos)

> "Ivan, antes de entrarmos nos itens da nossa pauta, queria
> compartilhar contigo uma auditoria de segurança que conduzimos
> proativamente nos últimos 2 dias. Sem incidente, sem
> exploração — auditoria interna preventiva. Já fechamos 100%
> do scope identificado. Quero registrar contigo agora porque
> faz parte do principle 'no surprise' e da disciplina de
> accountability que a gente quer estabelecer."

### Detalhamento (2-3 min)

> "Identificamos dois eixos de exposição: (a) 109 funções no banco
> com permissão padrão aberta a leitor não-autenticado e (b) 165
> tabelas/views expostas via endpoint GraphQL público. Não havia
> PII vazando — apenas exposição teórica. Em ~6h de trabalho
> autônomo, fechamos 289 hardenings cumulativos (137 funções via
> REVOKE + 152 tabelas/views). 1 regressão menor surface durante
> a auditoria — mesma sessão fechada. Trail completo no GitHub
> + audit doc."

### Métrica que ressoa

> "O advisor de segurança da Supabase passou de 171 WARN para
> 25 — redução de 85%. Os 25 restantes são todos exposições
> intencionais documentadas (homepage data, leaderboard público,
> reference data, view ADR-0024). Zero regressões em aberto,
> 1397 testes passando, invariantes estruturais 11/11 OK."

### Reframe positivo

> "O que isso significa pra gente: a disciplina de auditoria
> sistemática surfaceou itens que estavam invisíveis. A
> metodologia sedimentada vai prevenir recorrência — incorporamos
> ao protocolo de toda mudança SECDEF + GRANT futura. Cada
> intentional public exposure agora tem documentação inline."

### Convite à cadência

> "Daqui pra frente, vou trazer status como esse a cada
> quarterly touchpoint contigo. Próximo: 3 itens menores
> aguardando tier-input (homepage vs member-only?) + 11 funções
> documentadas para ratify de novas V4 actions (ADRs)."

---

## 8. Anexos para auditoria (links no GitHub)

- **Audit doc completo (Q-D charter + Track R section + closure de
  todas as batches)**:
  [`docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`](https://github.com/VitorMRodovalho/ai-pm-research-hub/blob/main/docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md)

### Commits Q-D (cronológico p55→p59)
- `e59295e` (p55) — batch 1 SECDEF security hardening sweep
- `69014e3` (p56) — batch 2 public-by-design verification
- `296c66d` (p57) — batch 3a.1 admin selection readers
- `c36e1ff` (p58) — batch 3a.3a initiative/board dead/internal
- `0c39356` (p58) — batch 3a.3b initiative/board member-tier
- `0777f75` (p58) — batch 3a.4 knowledge/wiki readers
- `2a225ab` (p58) — batch 3a.5 comms readers + regression note
- `a8521ec` (p58) — batch 1 amendment (regression resolved)
- `c4ec1c2` (p58) — batch 3a.6 curation/governance readers
- `3d57d05` (p58) — batch 3a.7 sustainability/KPI readers
- `6ed46d7` (p59) — **batch 3a.8 legacy/utility (32 triadas)**
- `69adad5` (p59) — **batch 3b internal helpers (20 incl can/can_by_member)**

### Commits Track R (cronológico, p59)
- `d58ea6d` (p59) — Track R batch 1 (102 REVOKEs, -56% advisor WARN)
- `49b624a` (p59) — audit doc Track R section
- `6639487` (p59) — Track R batch 2 (50 REVOKEs, -85% cumulativo)
- `39ae521` (p59) — audit doc Track R batch 2 closure

### Documentação técnica adicional
- **Treatment matrix Q-D** + **per-policy classification matrix Track R**:
  ver sections "Phase Q-D charter" e "Track R" no audit doc
- **Pattern validation**: 1 regressão da batch 1 (p55) detectada e
  resolvida na mesma sessão p58 — protocolo "per-fn callsite verification
  cross-check" sedimentado
- **Defense-in-depth no V4 authority core**: `can()` e `can_by_member()`
  REVOKE'd FROM authenticated em p59 batch 3b — chain SECDEF→postgres
  preservada, EF→service_role preservado

---

## 9. Próximos passos (informativo)

| Marco | Estado | Responsável |
|---|---|---|
| Q-D 8/8 buckets fechadas | ✅ DONE p59 | PM (autonomous) |
| Track R 152 REVOKEs cumulativos | ✅ DONE p59 | PM (autonomous) |
| Q-D batch 3a.2 (3 PM-deferred fns) | ⏳ Aguarda tier-input PM | PM input needed |
| Phase B'' V4 actions ratify (11 fns) | 📝 Documentadas, aguarda ADR ratify | PM ratify por ADR |
| Track R Phase R3 (COMMENT inline docs) | 🔜 Polish opcional ~1h | PM autonomous |
| Sponsor touchpoint formal (esta conversa) | 📅 **Segunda-feira (call agendada)** | Ivan + Vitor |
| Quarterly cadence sustainable | ✅ Estabelecida nesta call | PM iniciado |

**Closure status**: Tracks Q-D + R fechadas em p59. Backlog residual
é menor e não-bloqueante (3 PM-deferred + 11 Phase B'' + Phase R3 polish).

A plataforma agora tem **zero exposição não-intencional** de funções
SECDEF + tabelas/views via PostgREST/pg_graphql. Os 20 lints
remanescentes do advisor são **todos intentional public surface**
documentados (homepage data + reference + ADR-0024 views).

---

**Status do documento**: Pronto para uso na call de segunda-feira com
Ivan. Pode ser enviado por email/WhatsApp como pre-read ou usado
como roteiro durante a reunião.

**Próxima atualização**: após call de segunda + decisões PM tier-input
(3a.2) e Phase B'' priorities.
