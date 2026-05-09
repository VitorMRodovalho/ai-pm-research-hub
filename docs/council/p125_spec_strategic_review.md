# p125 Spec Consolidado — Step 0 Strategic Council Review

**Data:** 2026-05-09
**Sessão:** p125
**Convocação:** PM (Vitor Rodovalho) — workflow ratificado: Step 0 (este doc) → Step 0.5 (pre-mortem) → 4 entregáveis sequenciais (Wave 1 PM draft → Wave 2 council parallel → Wave 3 PM synth → Wave 4 Vitor A/B/C).
**Agents convocados (6 paralelos):** product-leader, data-architect, security-engineer, legal-counsel, accountability-advisor, platform-guardian.
**Output:** synthesis para PM-decision (este doc) + 7 decisões A/B/C abaixo, cada uma virando markdown próprio em `docs/council/decisions/` quando Vitor decidir.

---

## TL;DR

**Drafting é seguro com 1 hotfix paralelo + 7 decisões PM travadas no Step 0.** Council convergiu em **3 áreas de risco material** (cross-chapter data ingestion sem authorization, profileAboutMe→LLM sem base Art. 11/33, mid-cycle enrichment criando unequal treatment) e **3 facts-on-the-ground** que invalidam premissas do handoff:

1. **`pii_access_log` EXISTE** (platform-guardian falso-negativo no grep — tabela está no DB, shape per-member-access)
2. **`selection_applications.state/country` JÁ existem** (handoff dizia que adicionaríamos — só `applicant_city` é novo)
3. **`persons` NÃO tem coluna `chapter`** (memória ambígua — apenas `members.chapter` existe; multi-chapter requer nova tabela em persons)

Achado adicional cycle 3 b2 ao vivo: **0/40 apps com `age_band`, 0/103 com `consent_record_id` linkado, gender pop=70/103** — base legal de E4 (diversity) precisa auditoria pré-build, não pós.

---

## Convergências fortes (≥3 agents alinharam)

### C1 — Hotfix Wave 0 paralelo (não bloqueia drafting de E1)
**Agents:** product-leader + data-architect + platform-guardian (implícito)
- Issue A (Calendar webhook 30 dias zero sync): schema-independente, ~2-4h, ops-crítico
- Issue D (94/94 active engagements end_date NULL): semantic decision precede E1 DDL — backfill strategy não é current_date+1y nem PMI VEP serviceEndDateUTC; é `agreement_certificate_id`-derived
- `pii_access_log` shape extension: existe mas precisa entrada `target_type='aggregate'` ou nova log table para diversity (E4) — pré-Wave 1 de E4

### C2 — profilePrivate (19/97) → VEP-only documentado
**Agents:** legal-counsel + security-engineer + accountability-advisor (3 lentes convergentes)
- LGPD Art. 7 VI ("dados manifestamente públicos") **não se aplica** quando user disabled public profile
- Política pré-comprometida em `docs/council/decisions/`: "candidatos profilePrivate são scored apenas com VEP data; isto NÃO é penalidade — critérios de seleção priorizam PMI volunteer experience, não richness de perfil público"
- Implementação: nova coluna `community_profile_private boolean` em selection_applications; mapper E2 popula true para os 19 e omite todos `profile_*` fields

### C3 — profileAboutMe → LLM excluído de Cycle 3
**Agents:** legal-counsel + security-engineer (2 lentes técnicas)
- Art. 11 LGPD (dados sensíveis) — texto livre pode revelar saúde/religião/orientação política/sexual
- Art. 33 LGPD (transferência internacional) — Anthropic = US, sem cláusula contratual padrão hoje
- Art. 20 LGPD (revisão automatizada) — bias risk via prompt injection
- Apenas 21/97 candidatos têm bio preenchida — sinal incremental BAIXO vs. risco DESPROPORCIONALMENTE alto
- **Cycle 3 imediato: excluir do prompt;** Cycle 4: avaliar Option B (detection layer + consent específico + DPA Anthropic)

### C4 — Cycle 3 enrichment freeze (não retroativo)
**Agents:** accountability-advisor + product-leader (lente fairness + lente sequencing)
- 6 evaluators ativos em batch 2 já scoraram subset — enriquecer triage prompt mid-cycle = unequal treatment audível
- Decisão dated por PM: "AI triage parameters are locked for Cycle 3 batch 2 as of 2026-05-09. Enriched model deploys from Cycle 4."
- Custos: nenhum — apps já submetidas serão re-rankeadas em outro ciclo se candidatarem

### C5 — Single ADR multi-entregável (em vez de ADR-per-entregável)
**Agents:** legal-counsel + accountability-advisor
- ADR único cobrindo: finalidade declarada Phase B, base legal por field, papéis PMI Global vs Núcleo (operador-controlador), retenção bifurcada, k-anonymity rules, multi-chapter data theory
- Sem ADR único, cada wave futura reabre as mesmas perguntas
- Ivan (DPO) assina UMA vez

### C6 — service_history 1:N table sem summary cache
**Agents:** data-architect (anti-overengineering) + security-engineer (anti-perpetual-retention)
- Avg 1.76 / app, max 20 (LEONARDO CHAVES) — JSONB GIN index não resolve nada em 200 rows
- Summary column = trigger sync mandatório (ADR-0012) = complexidade desproporcional
- **Decisão híbrida**: tabela 1:N durante ciclo + post-cycle anonymize cron movendo para summary anonimizado

### C7 — E4 reduzido para "E4a CSV-only" no p125, dashboard E4b deferido
**Agents:** product-leader + accountability-advisor + security-engineer (3 lentes diferentes)
- product-leader: dashboard ROI baixo durante Cycle 3 (ninguém esperando hoje); CSV em 2h vs dashboard 6-8h
- accountability-advisor: dashboard em ciclo ATIVO = munição para appeal/political risk; super-restricted access (PM+DPO only)
- security-engineer: cross-tab limits explícitos no SQL antes de UI; k≥5 não sobrevive 3+ dimensões em 97 apps
- **Síntese**: E4a = single SECDEF RPC + CSV export, admin-only. E4b (dashboard + k-anonymity SECDEF) → backlog Cycle 4

---

## Divergências resolvidas

### D1 — pmi_memberships storage: snapshot vs canonical vs híbrido
- **product-leader**: implícito JSONB on selection_applications (snapshot)
- **data-architect**: HÍBRIDO — JSONB selection_applications (snapshot imutável p/ committee) + nova tabela `pmi_chapter_memberships(person_id, chapter_name, expiry_date, source, captured_at)` (canonical, queryable)
- **legal-counsel**: minimização Art. 6 §III — questiona se persistência de `profileLinkedinUrl` + `profileDesignation` é necessária

**Síntese PM**: data-architect HÍBRIDO está correto. ADR-0006 invariante: identity facts vão para `persons` (via tabela 1:N pmi_chapter_memberships). selection_applications.pmi_memberships JSONB é snapshot point-in-time (committee evaluates state at submission, ADR-0067 D5 audit principle). Cron compliance E3 query `pmi_chapter_memberships` (B-tree on `(person_id, expiry_date)`) — JSONB GIN não escala. profileLinkedinUrl + profileDesignation: persistir em `selection_applications` apenas com `fetched_at` timestamp (snapshot, não identity canonical) — não vão para `persons`.

### D2 — engagements.end_date backfill: from PMI VEP vs agreement_certificate
- **product-leader**: opção C ("Block on PMI API: only set end_date if serviceEndDateUTC non-null")
- **data-architect**: agreement_certificate_id é canonical para term agreement; PMI serviceEndDateUTC reflete opportunity window (calendário diferente)

**Síntese PM**: data-architect mais correto. PMI returns `serviceEndDateUTC` baseado no posting opportunity (e.g., 31/Jul/2026 do VEP), não no termo Núcleo (31/Dez/2026). João Coelho tem termo expirando ~Junho/2026 que vem do termo assinado, não do VEP. Pipeline: E2 worker tenta agreement_certificate primeiro; só usa PMI dates se `agreement_certificate_id IS NULL`. ADR-0007 invariante: NULL end_date = "currently active" semantic preserved.

### D3 — PMI Global papel: controlador conjunto vs operador-controlador
- **legal-counsel**: instrumento formal Núcleo↔PMI Global (DPA) ideal, B-side documentação interna como operador
- **accountability-advisor**: theory narrower — "candidato submeteu seus próprios dados como parte do ato de candidatura"

**Síntese PM**: combinar — operar como **operador dos dados VEP** (candidatura é o ato, candidato é parte) E **controlador dos dados coletados em plataforma própria nucleoia.vitormr.dev**. Documentar explicitamente no ADR (Decisão 7 abaixo). Não bloquear E1 esperando DPA com PMI Global; documentar internamente + Ivan DPO assina.

---

## Riscos não-detectados pelo council (síntese PM)

### R1 — Atomicidade E1↔E2 (data-architect Watchout #1)
Migration E1 que adiciona `applicant_city` + `pmi_memberships` E mapper E2 que popula esses campos DEVEM ser atômicos. Período intermediário = nova INSERT silenciosamente NULL injection no novo column. Se E1 ship antes de E2: cada nova app importada via `import_vep_applications` perde os campos novos.

**Mitigação**: 
- E1 migration cria column NULL-allowed (sem default fabricado)
- E1 migration ATUALIZA `import_vep_applications` RPC para incluir novos columns no INSERT (mesmo que NULL no início)
- E2 worker deploy ANTES de E1 ser aplicada em prod

### R2 — gender/age base legal pré-existente (legal-counsel Watchout)
**Confirmado live**: 70/103 cycle 3 apps com gender, **0/103 com age_band**, **0/103 com consent_record_id**. Antes de E4 build:
1. Auditar SQL: query `selection_applications WHERE gender IS NOT NULL` para verificar se foram capturadas com consentimento específico para diversity analytics OU apenas para campos do formulário
2. Se base = consentimento genérico do Termo Voluntariado v2, avaliar se escopo cobria analytics (provavelmente NÃO)
3. age_band column existe mas vazia — building dimension nesse field é cosmético até pipeline de captura existir

**Mitigação**: pre-build mini-audit step antes de E4a (CSV) ser draftado. Se base inadequada, E4 inteiro defer para Cycle 4 com novo consent.

### R3 — `import_vep_applications` drift histórico (data-architect)
RPC body já driftou antes (migration `20260514020000` documentou). E1 schema adições serão a 4ª oportunidade de drift. Mitigação: E1 migration usa CREATE OR REPLACE FUNCTION via `apply_migration` MCP (NÃO `execute_sql`) + adiciona invariante em `check_schema_invariants()` (`I_vep_import_columns_complete`).

### R4 — pii_access_log shape inadequado para aggregate diversity (security-engineer)
Tabela atual: `(accessor_id, target_member_id, fields_accessed[], context, reason, accessed_at)` — modela per-member access. E4 RPC agrega 97 candidates → 1 chamada. Opções:
- A) target_member_id NULL + context='diversity_aggregate' + reason=cycle_id (preserva tabela atual)
- B) Nova tabela `analytics_access_log(accessor_id, rpc_name, dimensions[], result_row_count, suppressed_cells, accessed_at)`

**Recomendação**: A para v0.1 (E4a CSV only); B se E4b dashboard for retomado em Cycle 4.

### R5 — Trentim Path B firewall (accountability-advisor)
Persistir 171 historical PMI roles + diversity aggregates posiciona dataset como "asset comercial" — se Path B (consulting) materializar, aparece como talent intelligence database. 5 chapter presidents que ratificaram IP Policy NÃO ratificaram esse uso. **ADR clause obrigatória**: "data persisted under este modelo é para selection + operational governance only; commercial use requires new CR approved by all 5 ratifying chapters."

---

## Decisões PM (lock antes de Wave 1 de E1) — 7 decisions

### Decision 1 — Hotfix Wave 0 escopo
**Options:**
- A) Hotfix Wave 0 paralelo a E1 drafting: (a1) Calendar webhook deploy + (a2) NULL end_date semantic doc'd + (a3) `import_vep_applications` invariant adicionado
- B) Block E1 only on Issue D semantic; defer Issue A e pii_access_log
- C) Treat all P0s as E1 prereqs, sequential

**Recommend: A.** Calendar webhook = 2-4h schema-independent, ops-crítico (30d zero sync). Issue D = doc no ADR ("NULL = currently active" semantic preserved per ADR-0007). Custo ~6h, risk savings huge. Atomicity preservada porque Wave 0 não toca schema novo.

**Reversibility:** medium (calendar deploy reversible, ADR doc additive).

### Decision 2 — pmi_memberships storage model
**Options:**
- A) JSONB only on selection_applications (snapshot only)
- B) JSONB only on persons (canonical, no snapshot)
- C) HÍBRIDO: JSONB selection_applications snapshot + new 1:N `pmi_chapter_memberships(person_id, chapter_name, expiry_date, source, captured_at)` canonical
- D) JSONB on persons + new tabela `pmi_chapter_memberships` (variante de C sem snapshot)

**Recommend: C.** Resolve audit trail (snapshot evaluators viam) + queryability (cron compliance B-tree index). ADR-0006 invariante: identity facts em persons via tabela 1:N. JSONB GIN índice em ~150 rows resolve nada vs B-tree em (person_id, expiry_date).

**Reversibility:** low (1:N table com FK CASCADE = breaking change rollback). Lock decision; mudança futura via migration v0.2.

### Decision 3 — profileAboutMe destino no AI triage prompt
**Options:**
- A) Include com sanitization + consent gate
- B) Exclude do Cycle 3 prompt; store DB para human review only; Cycle 4 avalia detection layer
- C) Include com re-consent retroativo

**Recommend: B.** Convergência legal-counsel + security-engineer. Loss baixa (21/97 com bio = 22% population). Risco Art. 11 + Art. 33 + Art. 20 desproporcional. C juridicamente frágil (consentimento retroativo para transferência internacional não é reconhecido como válido — Art. 8 §5).

**Reversibility:** low (decision dated archived; Cycle 4 pode reverter com diferente consent).

### Decision 4 — Cycle 3 AI triage freeze
**Options:**
- A) Freeze AI triage parameters para Cycle 3 batch 2; deploy enriched model do Cycle 4 onward
- B) Re-run AI triage retroativo para todos batch 2 antes de qualquer offer (equalizar pool)
- C) Document gap, proceed enriching for un-evaluated remaining; disclose post-mortem

**Recommend: A.** Process consistency = audit defensibility. Re-run retroativo (B) cria audibility própria ("model V1 vs V2 comparison?"). C cria appeal vector aberto. Decision dated by PM hoje.

**Reversibility:** high (governance memo dated; cycle 4 reverte naturalmente).

### Decision 5 — profilePrivate (19/97) treatment
**Options:**
- A) VEP-only para os 19; flag `community_profile_private=true`; pré-comprometer policy "scored on VEP data only, not penalty"
- B) Re-consent específico via email
- C) Excluir os 19 do triage entirely

**Recommend: A.** Convergência 3 agents. Custo zero — mapper E2 não popula campos profile_*. Policy markdown em `docs/council/decisions/` ANTES de qualquer Wave de E3.

**Reversibility:** high (mapper logic reversível).

### Decision 6 — E4 escopo no p125
**Options:**
- A) Full E4: SECDEF RPCs + k-anonymity + /admin/diversity UI + 6 dimensões + cross-tab
- B) E4a only: single SECDEF RPC retornando aggregate CSV-friendly, admin-only, no UI. Defer E4b post-cycle 3
- C) Drop E4 entirely from p125; backlog Cycle 4

**Recommend: B.** 3 lentes convergem. CSV serve 80% use case at 10% engineering cost. NO ONE waiting for dashboard hoje. Preserve 6-8h engineering para E3 fixes que afetam quality direto. **PRECONDICIONAL**: passar mini-audit gender/age base legal (R2) — se inadequado, drop para C.

**Reversibility:** high (E4a CSV é additive RPC + admin-only; E4b dashboard é separate work).

### Decision 7 — Retenção bifurcada + Trentim Path B firewall
**Options:**
- A) Anonymize cron 5y para todos (status quo)
- B) Bifurcado: 5y para active members; 12 months para non-selected applicants; 90 days para profileAboutMe + bio fields independent of selection
- C) 5y for all, com profileAboutMe explicit short retention (90d)

**Recommend: B + ADR clause Trentim firewall.** Convergência legal-counsel + security-engineer. Implementação: cron bifurca lógica entre active member (5y) vs applicant-rejected (12m) vs free-text bio (90d). ADR clause obrigatória: "data persisted under este modelo = selection + operational governance only; commercial use requires new CR all 5 ratifying chapters."

**Reversibility:** medium (cron logic reversível; mas dados anonimizados antes de 5y são unrecoverable).

---

## Watch-outs para Wave 2 de cada entregável

### E1 Wave 2 (data-architect + security-engineer + legal-counsel)
1. ADR único explicitamente declara fonte canônica para return-status detection (pmi_chapter_memberships vs engagements vs offboarding records)
2. Verificar `check_schema_invariants()` adiciona ≥1 invariante selection-domain (recomendado: `I_pmi_memberships_snapshot_exists` em status='approved' ou `I_service_history_orphans` cascade race)
3. RLS habilitado at-creation em `pmi_chapter_memberships` + `selection_application_service_history` (default-deny via Supabase exposes anon read all)
4. CASCADE on `persons` delete: anonymize_cron_5y faz UPDATE ou DELETE? Se UPDATE, novo cron-extension obrigatório
5. NÃO normalizar `chapter_name` para FK contra `chapter_registry` — Fernando Maquiaveli's "Silicon Valley" não existe registry

### E2 Wave 2 (senior-software-engineer + ai-engineer + code-reviewer)
1. Phase A / Phase B split explícito no mapper — duas paths separadas de persistência
2. Boolean `phase_b_consented` no types.ts — derivado de `community_profile_private` flag (NOT inferred from data presence/absence)
3. Worker deploys ANTES de E1 migration aplicada em prod (atomicity)
4. Validate 97/97 (or current count) candidates produzem non-null applicant_city OR are flagged community_profile_private=true (no silent NULLs)

### E3 Wave 2 (product-leader + ux-leader + stakeholder-persona + security-engineer)
1. "Enrich AI triage" tem bounded change list (specific fields: profile_state, profile_chapter_list, profile_service_history_count, profile_industry, profile_designation; explicitly EXCLUDE profileAboutMe per Decision 3 + isOpenToVolunteer per security-engineer R7)
2. is_returning_member fix tem regression test (João Coelho case flips false→true)
3. Booking gate alignment não introduz nova feature — só fecha bypass
4. Cron compliance D-60/D-30/D-7 sobre engagements.end_date + pmi_chapter_memberships.expiry_date — DOIS templates distintos (não messaging conflict candidate)
5. Apps Script Calendar webhook auth chain documented end-to-end (já hotfix Wave 0)
6. consent_version column adicionado a selection_applications (audit trail "qual prompt schema fui consented?")

### E4a Wave 2 (legal-counsel + data-architect + ux-leader + accountability-advisor)
1. **PRECONDIÇÃO**: gender/age base legal mini-audit completed (R2) — go/no-go gate
2. k-anonymity ≥5 enforced server-side (RAISE EXCEPTION if cell <5), não frontend
3. Cross-tab restrito a 2 dimensões simultâneas em v0.1 (97 apps + 6 dims = re-id risk em 3D+)
4. Generalization hierarchies declarados no ADR (state→region; cert→has_pmp/has_advanced/has_none; senioridade→junior/mid/senior; multi-chapter→bool)
5. Access tier policy markdown ANTES de RPC build (PM + DPO only durante active cycle; B-tier post-cycle retrospective)
6. pii_access_log entry format: opção A (target_member_id=NULL, context='diversity_aggregate', reason=cycle_id, fields_accessed=dimensions[]) — preserve schema atual

---

## Ready-to-go gate

| Gate | Status | Owner |
|---|---|---|
| C1 Hotfix Wave 0 paralelo | Pendente PM decision | Vitor |
| C2 profilePrivate VEP-only | Pendente PM decision | Vitor + Ivan DPO |
| C3 profileAboutMe excluded Cycle 3 | Pendente PM decision | Vitor |
| C4 Cycle 3 freeze | Pendente PM decision dated | Vitor |
| C5 Single ADR multi-entregável | Pendente PM decision | Vitor + Ivan DPO sign |
| C6 service_history table only | Pendente PM decision | Vitor |
| C7 E4a only + R2 audit precondition | Pendente PM decision | Vitor |
| Wave 1 of E1 ready | **NO** until decisions 1-7 lock | Vitor |

**Estimate post-decisions:** Wave 1 of E1 ADR + DDL drafting ~3-4h.

---

## Apêndice A — Achados live DB que invalidam premissas do handoff

| Premissa handoff p125 | Realidade live | Impacto |
|---|---|---|
| "selection_applications ganha applicant_city/state/country" | state + country JÁ existem; só applicant_city é novo | Migration menor que esperado |
| "rename selection_applications.chapter → entry_chapter" | `chapter` (normalized) + `chapter_affiliation` (raw form) JÁ existem como par; entry_chapter conceito já presente | NÃO renomear — keep semantics atual; documentar no ADR |
| "persons.chapter para multi-chapter" | persons NÃO tem column `chapter` — apenas `members.chapter` | Multi-chapter requer NOVA tabela 1:N (Decision 2) |
| "pii_access_log existente, retention policy" | EXISTE mas shape per-member-access, NÃO aggregate-friendly | E4 precisa adapter (R4 mitigação A) |
| "94 active engagements null end_date" | Confirmado: 94/94 NULL — 100% dos active | NULL=active semantic correto preservar (Decision 1) |
| "97 applications cycle 3" | Live: 40 b2 + 63 b1 = 103 (close enough) | OK |
| "gender/age 6 dimensions diversity" | gender 70/103 (68%); age_band **0/103** (0%); consent_record_id **0/103** | E4 base legal pre-build audit obrigatório (R2) |

---

## Apêndice B — Agents consulted

| Agent | Verdict | Key contribution |
|---|---|---|
| product-leader | safe with Hotfix Wave 0 | Sequencing + scope discipline + kill criteria; CSV v0.1 idea |
| data-architect | 4 cross-deliverable contradictions, 5 schema decisions | Hybrid storage; agreement_certificate_id source; check_schema_invariants coverage; persons.chapter clarification |
| security-engineer | 3 mandatory locks before E1 ship | profileAboutMe risk; k-anonymity cross-tab inhibition; isOpenToVolunteer ternary blacklist-by-silence; resumeUrl false permanence |
| legal-counsel | 2 hard blockers + 5 PM decisions | Phase B base legal Art. 7 IX; controlador conjunto theory; retention bifurcated; Art. 33 transferência internacional Anthropic |
| accountability-advisor | 3 institutional thresholds crossed | Cross-chapter authorization narrower theory; mid-cycle freeze owner naming; Trentim Path B firewall ADR clause; access tier policy |
| platform-guardian | YELLOW (1 ADR-0011 read-function pattern; 1 false-negative on pii_access_log) | Schema ready for greenfield E1; backlog candidate `get_tribe_attendance_grid` |

---

## Próximos passos

1. **Vitor decide A/B/C nas 7 decisions acima** (este turno ou próximo)
2. **Cada decisão escolhida vira `docs/council/decisions/2026-05-09-p125-decision-N-slug.md`**
3. **Step 0.5 pre-mortem (5 risks ranqueados)** em `docs/council/p125_premortem.md`
4. **Wave 1 de E1 (ADR + DDL drafting)** começa apenas após Decisions 1-7 lock + Hotfix Wave 0 escopo definido
