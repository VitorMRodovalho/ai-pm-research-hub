# ADR-0076: PMI 3-dimensional volunteer model + Phase B base legal + retention bifurcated + Trentim firewall

- Status: Proposed (Wave 1 draft p125)
- Data: 2026-05-09
- Aprovado por: Vitor (PM) + Ivan (DPO PMI-GO) — pendente sign-off Wave 4
- Autor: Vitor (PM) + Claude (council Wave 1 + Wave 3 synthesis)
- Escopo: Modelo de dados e base jurídica para ingestão multi-fonte de dados de voluntários PMI (VEP + Community), retenção bifurcada, e firewall contra uso comercial (Path B Trentim). Complementa ADRs V4 (0006-0009), ADR-0011 (autoridade), ADR-0012 (schema consolidation), ADR-0067 (AI-augmented selection Art. 20).

## Contexto

Sessão p125 (2026-05-09) consolidou extração de dados PMI de duas fontes para fundamentar pipeline robusto de gestão de voluntário + processo seletivo + AI triage + diversity analytics:

**Fonte A — PMI VEP (volunteer.pmi.org):** partnership formal Núcleo↔PMI Global. Dados submetidos pelo candidato como parte do ato de candidatura.

**Fonte B — PMI Community (community.pmi.org):** profile pages public-by-default. Dados sobre filiação multi-capítulo ATUAL, service history HISTÓRICA, certifications, industry, designation, bio. **49/97 candidatos cycle 3 com perfil público acessível; 19/97 profilePrivate (HTTP 400 — usuário desabilitou)**.

Audit live durante Step 0 confirmou:
- 94/94 active engagements têm `end_date=NULL` (Issue D)
- 36/94 active engagements têm `agreement_certificate_id` (sourceable); 58/94 não
- gender 70/103 cycle 3 apps; **age_band 0/103; consent_record_id 0/103**
- `selection_applications.state/country` JÁ existem; só `applicant_city` é novo
- `chapter_affiliation` (raw form) + `chapter` (normalized) JÁ coexistem como par (não renomear)
- `persons.chapter` NÃO existe; multi-chapter requer nova tabela 1:N
- `pii_access_log` existe com shape `(accessor_id, target_member_id, fields_accessed[], context, reason, accessed_at)`

Council Step 0 (6 agents paralelos) + Step 0.5 pre-mortem (5 risks ranqueados) identificou 9 PM decisions críticas, todas accepted by Vitor (decisions documentadas em `docs/council/decisions/2026-05-09-p125-decision-N-*.md`).

Esta ADR codifica decisões + invariantes + base legal para ingest+armazenamento+retenção+uso dos dados PMI.

## Decisão

### Princípio 1 — Modelo 3-dimensional de filiação PMI

Filiação PMI tem **três dimensões temporais distintas** que não são intercambiáveis:

| Dimensão | Onde vive | Update cadence | Imutabilidade |
|---|---|---|---|
| **Filiação ATUAL multi-chapter** | `pmi_chapter_memberships(person_id, chapter_name, expiry_date, source, captured_at)` | Re-sync via worker | Mutable — evolve com renewals |
| **Filiação HISTÓRICA / service history** | `selection_application_service_history(application_id, chapter, role, start_date, end_date, source)` | Append-only at submission | Imutável após import |
| **Chapter de ENTRADA (admissão Núcleo)** | `selection_applications.chapter` (existing) | Set once at submission | Imutável após decision |

**`selection_applications.pmi_memberships JSONB`** = snapshot point-in-time das filiações ATUAIS do candidato no momento da submission (committee evaluates state at submission, ADR-0067 D5 audit principle). Imutável após import. **NÃO é canonical** — para consultas live (cron compliance E3), use `pmi_chapter_memberships`.

`chapter_affiliation` (raw form answer) preserva-se por audit; não renomear.

### Princípio 2 — Base legal por field e por finalidade

| Campo | Fonte | Finalidade declarada | Base legal LGPD |
|---|---|---|---|
| applicantName/Email/Resume/CoverLetter/nonPMIExperience | VEP | Seleção (procedimento preparatório a contrato) | Art. 7 II + Art. 7 V (execução de contrato/preparatório) |
| applicantId/applicationId/opportunityId | VEP | Identificação técnica + audit | Art. 7 II |
| serviceStartDate/EndDate (VEP) | VEP | Compliance reminders + return-status | Art. 7 V + Art. 7 VI |
| applicant_city | VEP profile | Selection geographic context | Art. 7 IX (legítimo interesse) — LIA documentada (link abaixo) |
| pmi_memberships (snapshot) | Community | Selection + return-status detection | Art. 7 IX — LIA documentada |
| pmi_chapter_memberships (canonical) | Community | Compliance reminders D-60/D-30/D-7 | Art. 7 IX — LIA documentada |
| profileLocation/State/City/Country | Community | Selection geographic context | Art. 7 IX — LIA documentada |
| profileCertifications | Community | Selection signal | Art. 7 IX — LIA documentada |
| profileIndustry/Company/Designation | Community | Selection signal | Art. 7 IX — LIA documentada |
| profileLinkedinUrl | Community | Display only (admin UI) | Art. 7 IX — LIA documentada (snapshot, fetched_at) |
| serviceHistoryCount/Chapters/Dates | Community | AI triage signal | Art. 7 IX — LIA documentada |
| isOpenToVolunteer (ternary) | Community | Display + human context only — **NOT in LLM prompt** | Art. 7 IX — LIA documentada |
| **profileAboutMe** | Community | **Human review only — Cycle 3 EXCLUDED do LLM** | Cycle 3: Art. 7 IX storage only. Cycle 4: avaliação Option B (detection + DPA + consent específico). |
| gender | Form direto | TBD audit (E4 precondicional) | **PRE-AUDIT REQUIRED** — base legal atual incerta |
| age_band | Form direto | TBD audit (E4 precondicional) | **PRE-AUDIT REQUIRED** — 0/103 populated; campo unused |

**LIA (Legitimate Interest Assessment) Art. 7 IX:**
- Finalidade legítima: seleção de voluntários para Núcleo IA + compliance de filiação PMI
- Necessidade: dados Phase B são complementares ao formulário VEP; permitem qualificação multi-capítulo + compliance reminders sem requerer formulário longo
- Balanceamento: dados são públicos por default no PMI Community (exceto os 19 profilePrivate); titular tem expectativa razoável de processamento por chapter parceiro PMI; titular pode opt-out (Art. 18) se discordar
- Compensação: 19 profilePrivate respeitados (Decision 5 — VEP-only). profileAboutMe excluído de LLM (Decision 3 — Cycle 3).

### Princípio 3 — profilePrivate posture (19/97)

Candidatos com `profilePrivate=true` no PMI Community (HTTP 400 ao acessar profile API) exerceram **opt-out explícito** equiparável ao Art. 18 §I LGPD. Posture (Decision 5):

- Boolean column `selection_applications.community_profile_private` (default false)
- Mapper E2 detecta HTTP 400 → set true + omite todos `profile_*` fields (NULL)
- Policy pré-comprometida (declaration neste ADR): "candidates with profilePrivate scored on VEP data only; this is not a disadvantage relative to stated selection criteria, which are based on PMI volunteer experience, not public profile richness"
- AI triage prompt verifica flag e documenta explicit que sinal "VEP-data-only" não é penalidade

### Princípio 4 — AI triage scope (Decision 3 + Decision 4)

**Cycle 3 batch 2 (current, in progress):** AI triage parameters FROZEN at V1. Enriched model (V2) deploys from Cycle 4 onward.

**Cycle 3 V1 prompt fields (persist atual scope):** já existem fields que podem ser enriquecidos para V2.

**Cycle 4+ V2 prompt fields (enriched):**
- INCLUDE: profile_state, profile_chapter_list (current), profile_service_history_count, profile_industry, profile_designation, profile_certifications
- **EXCLUDE Cycle 3 + Cycle 4 V2 initial:** `profile_about_me` (Decision 3 — Art. 11 + Art. 33 + Art. 20 risks)
- **EXCLUDE always:** `isOpenToVolunteer` (security-engineer R7 — ternary 78T/0F/19U cria blacklist-by-silence vector; store mas keep out of prompt)

**Cycle 4 V2 deploy schedule (locked 2026-05-09 per B4):**
- Target deploy: **2026-09-01 OR 30 dias pós Cycle 3 closure (whichever later)**
- Hard deadline: 2026-12-15 (independente de Cycle 4 timing) — para evitar Risk 9 pre-mortem (V2 model engaveted indefinitely)
- Se Cycle 4 ainda não aberto em 2026-12-15: deploy em STAGING + manual integration test, freeze para Cycle 4 effective date
- pmi-ai-triage EF logic: cycle-based prompt template selection
- Logs em `ai_processing_log` registram `prompt_version` usado
- Cycle 4 launch memo pelo PM = governance gate

**`profile_about_me` Cycle 4 evaluation (Decision 3 path Option B):**
- Detection layer Art. 11 (regex + classifier para health/religion/política/orientation)
- DPA com Anthropic estabelecida
- Consent específico capturado at-submission (não retroativo — Art. 8 §5)
- Apenas com 3 conditions met, profile_about_me pode entrar em prompt V3 Cycle 5+

### Princípio 5 — Issue D fallback strategy (Decision 8)

`engagements.end_date` populated por **multi-source** com origem flagged em `metadata->>'end_date_source'`:

| Source | Trigger | Confidence | Cron alert pattern |
|---|---|---|---|
| `agreement` | `agreement_certificate_id` IS NOT NULL → derive from agreement | High | D-60/D-30/D-7 (high confidence) |
| `pmi_vep` | Fallback if no agreement; use `serviceEndDateUTC` from PMI VEP | Medium | D-90/D-60/D-30 (earlier; mensagem "estimativa baseada em PMI VEP, confirmar com chapter VP") |
| `estimated` | Last resort: `current_date + 6 months` | Low | Admin dashboard only ("pendente confirmação") — NOT to candidate |
| `manual` | Future: chapter VP secretarial entry | High | D-60/D-30/D-7 (high confidence) |

Pre-existing data: 36/94 active engagements eligible for `agreement`; 58/94 fallback to `pmi_vep` or `estimated`. E2 worker mapper popula durante backfill.

`NULL end_date` continues to mean "active no defined expiry" per ADR-0007 — preserve invariant. `metadata->>'end_date_source'` is additive metadata, not replacement.

### Princípio 6 — Retenção bifurcada (Decision 7)

| Concept | Retention | Anonymization scope |
|---|---|---|
| Active members (`status='active'`) | 5y from inactivity | Full PII anonymization (existing `anonymize_inactive_members`) |
| Applicants rejected (`selection_applications.status IN ('declined','withdrawn','removed','expired')`) | 12 months from cycle decision | All PII fields cleared; `pmi_memberships` snapshot kept para audit; `service_history` rows deleted |
| Free-text bio fields (`profile_about_me`, `non_pmi_experience`, `motivation_letter`) | 90 days from any state | Cleared regardless of selection status (Art. 11 priority) |
| `pmi_chapter_memberships` (canonical) | Linked to `persons` retention | Cleared via cron extension (NEW) when person_id anonymized |
| `selection_application_service_history` | Linked to `selection_applications` retention | Cleared via cron extension (NEW) when applicant rejected 12+ months |

**CRITICAL — Risk 2 do pre-mortem:** `anonymize_inactive_members()` atualmente usa `UPDATE public.members SET ...` que NÃO dispara FK CASCADE em `persons`. Migration E1 estende função para incluir explicit DELETE de novas tabelas (E1 migration 5 abaixo).

### Princípio 7 — Trentim Path B firewall + Decision S2 (Wave 3 synth — IP Policy v3 commitment)

**Cláusula obrigatória:** "Data persisted under este modelo é para selection + operational governance only. Commercial use (Path B consulting, white-label, sale, sharing with third parties beyond PMI partnership scope) requires new CR approved by all 5 ratifying chapters via existing approval_chains workflow."

**Decision S2 (Wave 3 synth 2026-05-09 — locked by PM):**

Para a cláusula virar **legalmente vinculante** entre os 5 capítulos (não apenas cultural/process control), ela deve estar incorporada em **IP Policy v3** (revisão da v2) com:

- **Owners**: Vitor (PM Núcleo) + Ivan (DPO PMI-GO) co-drivers
- **Deadline**: **Q3 2026 — até 30/Set/2026** (governance review com 5 chapter presidents agendado antes desta data)
- **Cláusula penal mínima**: 3 meses budget do programa Núcleo IA pagos pelo capítulo violador para os 4 capítulos não-violadores (deterrence proporcional + remedy mensurável)
- **Definição precisa de "commercial use"**: explicit list (consulting engagement com terceiro pago / white-label da methodology / sale of dataset access / sharing com 3rd party não-PMI / monetização direta ou indireta de aggregate insights)
- **Veículo**: approval_chains workflow existente (5 presidents ratificam via assinatura digital eletrônica governamental, mesmo padrão do IP Policy v2)
- **Trigger pré-CR**: any external mention by Núcleo team em pitch/keynote/whitepaper de dataset como "talent intelligence", "diversity benchmark", ou "consulting asset" — OBRIGA pause + CR antes de prosseguir

**Visible artifacts (post-Decision S2)**:
- This ADR section (Princípio 7) — referenciado em IP Policy v3 appendix
- COMMENT ON SCHEMA / COMMENT ON TABLE em `pmi_chapter_memberships` + `selection_application_service_history` cita IP Policy v3 (uma vez ratificado)
- **IP Policy v3 (post-Q3 2026)** — instrumento legalmente vinculante entre 5 capítulos
- GitHub issue T-2 tracking IP Policy v3 progress

**Status atual (2026-05-09 → Q3 2026)**: cultural/process control via ADR + COMMENT. Vitor + Ivan committed to converter para legal binding via IP Policy v3 até 30/Set/2026.

**Important:** Esta cláusula é technical control = NULL. Enforcement real é (a) absence of bulk-export RPCs em E1/E2/E3/E4 implementation, (b) PII RLS gates, (c) cultural commitment até IP Policy v3 ratificada, (d) cláusula penal post-IP Policy v3.

### Princípio 8 — Diversity analytics scope (Decision 6 — E4a only) + Decision S1 (Wave 3 synth)

**E4a scope no p125:** single SECDEF RPC `get_diversity_aggregate_csv(p_cycle_id, p_dimensions text[])` retornando aggregate CSV-friendly.

**Decision S1 (Wave 3 synth 2026-05-09 — locked by PM):**

**`gender` is OUT OF E4 SCOPE PERMANENTEMENTE.** Rationale:
- Nome em PT-BR já implicitamente revela gender; coletar campo separado adiciona LGPD risk sem ganho analítico real
- ANPD interpreta gender em analytics agregada como categoria sensível (Art. 11)
- Não-coletar = elimina vector de challenge "fui rejeitado por ser X gender"
- Diversity reporting via name-inference também é processamento — fica out-of-scope explicitly
- 70/103 Cycle 3 legacy values: mantidos no DB para human review individual; **não entram em pipeline analytics** E4 nem qualquer RPC SECDEF agregado
- Cycle 4+ termo voluntariado v3: NÃO pede gender no formulário
- Diversity por gender (se desejado no futuro): survey voluntário separado pós-decisão de seleção, não vinculado a application — fora escopo p125

**`age_band` PERMITIDO em E4 com escopo reduzido:**
- Schema: `age_band text` column existing — add CHECK constraint enum: `('18-25','26-35','36-50','50+','prefer_not_to_say')`
- Capture: voluntário no termo voluntariado v3 + opcional Cycle 3 (post-submit survey, não obrigatório)
- Base legal: Art. 7 IX (LIA) — categoria não sensível, defensibility maior que gender
- Status hoje: 0/103 populated → não há legacy gap
- Mini-audit Ivan DPO: escopo agora é **só age_band** (não gender). Deadline mantido **30/Jun/2026**.
- birth_date / exact age: NUNCA coletar. Apenas band.

**Generalization hierarchies (k-anonymity ≥5 enforced server-side):**
- `state` → `region` (Sul / Sudeste / Nordeste / Norte / Centro-Oeste / Outside Brazil)
- `cert` → `has_pmp / has_advanced / has_none`
- `senioridade` → `junior (<5y) / mid (5-15y) / senior (>15y)`
- `multi_chapter` → boolean
- `industry` → 5 buckets via mapping (TBD em Wave 2 E4a)
- `age_band` → enum direto (gated by Ivan DPO mini-audit 30/Jun)
- ~~`gender`~~ → **REMOVED — out of scope per Decision S1**

**E4a access tier:** PM + DPO only durante active cycle. Post-cycle retrospective: 5 chapter presidents acessam aggregate report.

**Cross-tab limit:** 2 dimensions simultâneas max em v0.1. RPC RAISE EXCEPTION se p_dimensions length >2.

**E4a CSV ships com 5 dimensões IMEDIATAMENTE pós-Wave 4 sign-off** (geo, industry, certs, senioridade, multi-chapter — todos sem audit dependency). age_band entra como 6ª dimensão pós Ivan sign-off (até 30/Jun/2026).

**E4b dashboard:** NOT in p125 scope. Backlog Cycle 4 com prerequisitos: (a) age_band audit OK, (b) p125 cycle of operation completed, (c) explicit consent updated for Cycle 4.

### Princípio 9 — Cron deploy gate (Decision 9 — E3)

Compliance cron D-60/D-30/D-7 (E3) tem **mandatory dry-run protocol**:

1. **Staging dry-run 2 weeks** — cron executa em staging Supabase branch, sem real email send
2. **Pilot consenting** — semana 1 do dry-run: 3 candidates (Vitor + 2 chapter leads) recebem real emails + give feedback
3. **Chapter VP secretarial briefing** — 1 week pre go-live: meeting com 5 chapter VPs, present templates + timing logic
4. **Quiet window** — mensagens NÃO disparam entre 18h sextas e 8h segundas
5. **Templates distintos** — nomenclatura explícita: "Seu termo de voluntariado Núcleo — vence em X dias" vs "Sua filiação PMI [Chapter] — renovação em X dias"
6. **Opt-out path** — link "não quero esses lembretes" → flag em selection_applications

**Go/no-go gate pós-dry-run:** se >5% false positives ou ANY collision com PMI renewal cycle, **defer + redesign**.

### Princípio 10 — PMI Code of Ethics §3.3.4 cross-reference (Wave 3 synth — S4)

PMI Code of Ethics §3.3.4 (Honesty — proprietary information) e §2.2.6 (Responsibility — confidential information) são cláusulas que membros PMI devem respeitar quanto a informação proprietária de terceiros. Ingestão de dados PMI Community por chapter parceiro precisa ser assessed contra essas cláusulas.

**Assessment Núcleo IA**:
- PMI Community profiles são **public-by-default** as a platform convention; user must explicitly disable to set as private (= os 19 profilePrivate em Cycle 3)
- Public-by-default ≠ proprietary no sentido do Code §3.3.4 — informação publicamente acessível por qualquer PMI member não é "obtained in PMI capacity for unauthorized purposes"
- Núcleo opera **dentro de** sua capacidade PMI (chapter parceiro PMI-GO) processando dados de PMI volunteers candidatos a uma PMI volunteer initiative
- Os 19 profilePrivate são respeitados (Decision 5) — opt-out explícito reconhecido como exercise de privacy right equivalente a Code Honesty principle

**Conclusão**: assessment Code §3.3.4 é compatível. ADR explicit cross-reference desta seção evita audit gap "did you check against PMI Code of Ethics?" em PMI Latam ou PMI Global review.

**Documentation trail**: este ADR + decision logs constituem o "documented assessment" referenciado em Code §3.3.4 honesty requirement.

### Princípio 11 — Atomicidade E1 ↔ E2

Migration E1 e Worker E2 deployment **devem ser atômicos** (Risk 3 do pre-mortem):
- E1 migration adiciona columns NULL-allowed (sem default fabricado)
- E1 migration ATUALIZA `import_vep_applications` RPC body para incluir new columns no INSERT
- E2 worker deploy ANTES de E1 migration aplicada em prod (worker tolera columns ausentes mas migration cobre)
- Invariante adicionada `I_vep_import_columns_complete` em `check_schema_invariants()`

## Consequências

### Positivas
- **Single source of truth restored:** filiação ATUAL em `pmi_chapter_memberships`, HISTÓRICA em `selection_application_service_history`, ENTRADA em `selection_applications.chapter`. Zero ambiguidade conceitual.
- **LGPD defensibility:** base legal explícita por field; LIA Art. 7 IX documentada; profilePrivate respeitados; profileAboutMe excluído LLM Cycle 3.
- **Audit trail robusto:** snapshot evaluators viam preservado; canonical evolve via worker re-sync; cron alertas com source confidence.
- **Trentim Path B firewall codified:** chapter presidents protegidos contra commercial use unauthorized.
- **Pre-mortem risks mitigated:** Risk 2 (cron CASCADE) addressed via cron extension; Risk 3 (RPC drift) via invariant + atomicity protocol; Risk 5 (Issue D fallback) via multi-source.

### Negativas / risks
- **Complexity:** 2 novas tabelas + JSONB snapshot + cron bifurcation = 5 migrations. Maintenance surface aumenta.
- **R2 audit dependency:** E4a blocked até gender/age base legal audit completed. Sliding deadline.
- **Cycle 4 deferred items:** profileAboutMe LLM evaluation, E4b dashboard, V2 enriched prompt deploy. Multiple parallel tracks pra não esquecer.
- **Manual ops:** chapter VP secretarial briefing (E3 deploy gate) requires human coordination — não automatable.
- **Storage:** ~150 service_history rows + ~90 multi-chapter membership rows = small. JSONB snapshots adicionais ~2KB per app × 100 apps = 200KB. Negligible vs benefit.

### Reversibility
- Decisions 1, 4, 5, 6, 8, 9: HIGH (governance memos / mapper logic / cron config — all reversible)
- Decision 2 (storage hybrid): LOW (1:N table com FK = breaking; rollback via migration v0.2 not trivial)
- Decision 3 (profileAboutMe): HIGH (Cycle 4 path Option B clearly defined)
- Decision 7 (retention bifurcated): MEDIUM (cron logic reversível; data anonimizado pré-5y unrecoverable)

## Implementação

E1 migrations (7 files, sequential timestamps):

| # | Migration | Timestamp | Contents |
|---|---|---|---|
| 0 (Hotfix) | `_p125_hotfix_wave0_engagements_end_date_source.sql` | 20260517235500 | Hotfix Wave 0 — Issue D fallback metadata flag (R1) |
| 1 | `_p125_e1_selection_applications_pmi_3d_columns.sql` | 20260518000000 | selection_applications 22 new columns + COMMENTs + import_vep_applications RPC update (atomic per Decision B1) |
| 2 | `_p125_e1_pmi_chapter_memberships.sql` | 20260518010000 | pmi_chapter_memberships table (canonical multi-chapter) + RLS + indexes + updated_at trigger |
| 3 | `_p125_e1_service_history_table.sql` | 20260518020000 | selection_application_service_history (1:N HISTÓRICA) + RLS + indexes |
| 4 | `_p125_e1_invariants_extension.sql` | 20260518030000 | check_schema_invariants_p125() — 5 new invariants (standalone for Wave 1; integrated into base post-Wave 4) |
| 5 | `_p125_e1_anonymize_bifurcated_cron.sql` | 20260518040000 | anonymize_pmi_cascade helper + anonymize_rejected_applicants 12m + anonymize_free_text_bios 90d + pg_cron schedules |
| 5b | `_p125_e1_anonymize_inactive_members_cascade.sql` | 20260518050000 | anonymize_inactive_members CREATE OR REPLACE com CASCADE call (Decision B3 separate migration; Risk 2 mitigation) |
| 6 | `_p125_e1_age_band_constraint_gender_freeze.sql` | 20260518060000 | age_band CHECK constraint enum + gender out-of-scope COMMENT (Wave 3 synth Decision S1) |

E2 worker deploys ANTES de E1 migrations 1-6 applied to production. Hotfix Wave 0 (file 0) é independent.

E3 + E4a são entregáveis subsequentes; E4b deferred.

## Referências obrigatórias

- ADR-0006 (Person + engagement identity model V4)
- ADR-0007 (Authority as engagement grant — `can()` canonical)
- ADR-0011 (V4 auth pattern — RPCs + MCP)
- ADR-0012 (Schema consolidation principles)
- ADR-0067 (AI-augmented selection — Art. 20 LGPD safeguards)
- LGPD Art. 6 III, Art. 7 II/V/VI/IX, Art. 8 §5/§6, Art. 9, Art. 11, Art. 18, Art. 20, Art. 33
- IP Policy v2 + 4 adendos (5 chapter presidents ratified Apr 2026)
- Termo de Voluntariado v2 Cycle 3
- `docs/council/p125_spec_strategic_review.md` (Step 0 council synthesis)
- `docs/council/p125_premortem.md` (Step 0.5 pre-mortem)
- `docs/council/decisions/2026-05-09-p125-decision-{1..9}-*.md` (9 PM decisions)

## Aprovação requerida (Wave 4)

- **PM (Vitor)**: aprova este ADR como master decision para p125 spec
- **DPO (Ivan)**: signs base legal section (Princípio 2) + retention bifurcation (Princípio 6) + Trentim firewall (Princípio 7)
- **Council Wave 2 review** (5 agents paralelos): data-architect + security-engineer + legal-counsel + platform-guardian + accountability-advisor — antes do sign-off final

Após sign-off: status `Accepted`. Antes: `Proposed`.
