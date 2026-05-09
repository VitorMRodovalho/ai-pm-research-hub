# p125 Spec Consolidado — Step 0.5 Pre-Mortem

**Data:** 2026-05-09
**Sessão:** p125
**Pergunta-quadro:** "Se este spec falhar em produção 3 meses depois (≈Agosto/2026), por quais 5 razões mais prováveis?"
**Predecessor:** `docs/council/p125_spec_strategic_review.md` (Step 0)
**Sucessor:** Wave 1 de Entregável 1 (após Vitor lock 7 decisões PM)

---

## Metodologia

Aplicação técnica de pre-mortem (Klein 2007): assumir o spec já falhou, listar causas mais prováveis ranqueadas por (probabilidade × impacto), associar mitigação por entregável + owner. Cada risco verificado contra dados live (DB) onde aplicável.

---

## TOP 5 risks ranqueados

### Risk 1 — gender/age dimension de E4 ships com base legal inadequada

**Failure mode (Agosto/2026):** /admin/diversity dashboard ou CSV export gera relatório agregando `gender` e `age_band`. Auditor LGPD interno (Ivan DPO) ou ANPD pergunta: "Qual a base legal específica para tratamento desses campos para finalidade de analytics agregada?" Núcleo não tem resposta documentada — campos foram capturados sob consentimento genérico do Termo Voluntariado v2 (que não menciona analytics). E4 vira evidência de processamento sem base.

**Probabilidade:** ALTA — confirmado live:
- gender populated: 70/103 cycle 3 apps (68%)
- **age_band populated: 0/103 (0%)** — column unused
- **consent_record_id linked: 0/103 (0%)** — base legal não rastreável per-row

**Impacto:** ALTO — exposição regulatória + audit failure + Ivan DPO at risk. Reverter dashboard pós-launch é fácil; reverter o conhecimento de que dados foram processados sem base é impossível.

**Mitigation per entregável:**
- **PRECONDIÇÃO E4a (gate):** mini-audit antes de qualquer Wave de E4 — query `SELECT COUNT(*) WHERE gender IS NOT NULL` cross-checked com `consent_record_id` linkage + cobertura do consent text (Termo voluntário v2) sobre analytics. Se inadequado → defer E4 inteiro para Cycle 4 com novo consent.
- **E1:** ADR único declara base legal por field. gender/age explicitamente flagged como "pendente audit pré-build E4".
- **E4 (se prosseguir):** começar com dimensions seguras (geo, certifications, multi-chapter) e tratar gender/age como adições posteriores condicionais à base legal validada.

**Owner:** Vitor (PM) + Ivan (DPO) sign-off antes de E4 começar.

**Reversibility se acontecer:** baixa — uma vez RPC SECDEF processou gender em produção sem base, log existe forever no `pii_access_log`.

---

### Risk 2 — `anonymize_cron_5y` não CASCADE para novas tabelas → LGPD Art. 18 violado

**Failure mode (Agosto/2026):** Candidato exerce direito de eliminação (Art. 18 §VI). Cron anonymization processa `members.email = 'anon_xxx'` mas NÃO toca `pmi_chapter_memberships` nem `selection_application_service_history`. Dados PMI históricos do indivíduo persistem indefinidamente vinculados a `person_id` que ainda existe. Right-to-erasure não foi exercido na prática.

**Probabilidade:** ALTA se não endereçado — depende da implementação atual do cron:
- Se cron faz `UPDATE persons SET email='anon...'`, FK CASCADE não dispara
- Se cron faz `DELETE FROM persons`, CASCADE seria correto
- **A se determinar pré-Wave 1:** que padrão o cron atual usa?

**Impacto:** ALTO — Art. 18 §VI violation = ANPD complaint risk; cumulativo (cada eliminação não-completa = nova violação).

**Mitigation per entregável:**
- **E1 Wave 2 Watch-out #4 (data-architect):** verificar `anonymize_cron_5y` body antes de E1 migration ship. Se UPDATE-based, novo cron-extension obrigatório.
- **E1:** invariante adicionada `I_lgpd_erasure_completeness` em `check_schema_invariants()`: query que detecta órfãos `pmi_chapter_memberships.person_id` referenciando persons com `email LIKE 'anon%'`.
- **E1:** FK `ON DELETE CASCADE` em ambas tabelas novas — se cron eventualmente migra para DELETE-pattern, CASCADE captura.
- **Test em CI:** integration test que cria person → multi-chapter rows → trigger anonymize → assert rows tocadas.

**Owner:** data-architect Wave 2 review (E1) + security-engineer.

**Reversibility se acontecer:** baixa — dados deixados são impossíveis de unifier post-hoc com confidence.

---

### Risk 3 — `import_vep_applications` drift na 4ª iteração → silent NULL injection nos novos campos

**Failure mode (Agosto/2026):** Migration E1 adiciona `applicant_city` + `pmi_memberships`. Mapper E2 atualizado. Mas terceira-party rota (admin manual import? Bulk SQL? Dashboard form?) chama `import_vep_applications` RPC que ainda tem INSERT statement antigo. Novas apps importadas via essa rota silenciosamente NULL nos campos novos. E3 cron compliance (que depende de `pmi_memberships.expiryDate`) rejeita silenciosamente para essas apps. Issue manifesta 60-90 dias após launch quando primeira renewal cycle dispara mas algumas apps "invisíveis" perdem alerta.

**Probabilidade:** MÉDIA-ALTA — RPC body `import_vep_applications` já driftou 2x (documented em migrations 20260514020000). 3ª iteração tem ~50% chance histórica de drift.

**Impacto:** ALTO — silent data loss no field exatamente projetado para compliance reminding. Detection lag 60-90 dias.

**Mitigation per entregável:**
- **E1:** migration usa `apply_migration` MCP (NÃO `execute_sql`) per CLAUDE.md regra explícita. Local file + `supabase migration repair --status applied TIMESTAMP` + `NOTIFY pgrst, 'reload schema'`.
- **E1:** invariante `I_vep_import_columns_complete` em `check_schema_invariants()` — count rows in `selection_applications` where `imported_at IS NOT NULL AND applicant_city IS NULL` flagged se >0 após imports recent.
- **E1↔E2 atomicity:** migration E1 pode incluir empty column adds (NULL-allowed), mas RPC body update SAME migration. E2 worker deploy ANTES de migration aplicada.
- **CI test:** existing `tests/contracts/rpc-migration-coverage.test.mjs` já catches functions in pg_proc without CREATE FUNCTION block. Verify it covers `import_vep_applications`.

**Owner:** spec-executor (DDL) + senior-software-engineer Wave 2 E2 review.

**Reversibility:** medium — quando detectado, NULL → fill via re-sync via worker mapper. Cron alertas perdidos durante gap são unrecoverable.

---

### Risk 4 — Cron compliance D-60/D-30/D-7 misfires → candidate UX disaster + opt-outs cascade

**Failure mode (Agosto/2026):** Cron dispara dois templates distintos baseados em DOIS prazos (engagements.end_date vs pmi_chapter_memberships.expiry_date) na mesma janela. Candidato João recebe **2026-08-01**: "Seu termo Núcleo expira em 60 dias (30/Set/2026)" + "Sua membership PMI Goiás expira em 30 dias (31/Aug/2026)". Mensagens distintas mas chegam na mesma semana, plataforma idêntica, parecendo conflito ou redundância. João liga PMI-GO confuso. Chapter VP secretarial não foi briefed. Brand damage cascata. Re-engagement futura prejudicada.

**Probabilidade:** MÉDIA — TWO timelines coordinating é receita conhecida para confusion. Sem chapter VP coordination, alta chance de overlap message indesejado.

**Impacto:** ALTO — brand + opt-outs cascade. 1 candidato confuso vira social proof negativo na rede de voluntários.

**Mitigation per entregável:**
- **E3 Wave 2 Watch-out (accountability-advisor):** cron design review com chapter VP secretarial briefing antes de deploy. Não é design-review opcional — é gate.
- **E3:** templates distintos com NOMENCLATURA explícita ("Seu termo de voluntariado Núcleo — vence em X dias" vs "Sua filiação PMI Goiás — renovação em X dias"). Templates testados com 3 candidatos pilot ANTES de cron go-live.
- **E3:** dry-run mode em staging — cron executa mas envia para email de Vitor only durante 2 weeks, validar mensagens reais.
- **E3:** opt-out path nas mensagens (link "não quero esses lembretes" → flag em selection_applications).
- **E3:** quiet window — mensagens não disparam entre 18h sextas e 8h segundas.

**Owner:** product-leader Wave 2 E3 + ux-leader Wave 2 E3.

**Reversibility:** medium — pode-se kill switch cron, mas mensagens enviadas são unrecoverable. Brand recovery 3-6 meses.

---

### Risk 5 — Issue D fix não fixou nada porque 58/94 active engagements não têm `agreement_certificate_id` para sourcing end_date

**Failure mode (Agosto/2026):** E2 worker tenta backfill `engagements.end_date` from `agreement_certificate_id`-derived data (per Decision 2 of Step 0). Para 36/94 (38%) active engagements: funciona. Para **58/94 (62%) active sem agreement_certificate**: end_date permanece NULL. Cron compliance (E3) skip esses 58 — exatamente os volunteers historic-mais-vulneráveis (legacy Cycle 1/Cycle 2 sem termo formal). Termo vencendo Junho/2026 invisível para João Coelho cuja engagement não tem agreement_certificate. Issue D, allegedly resolvida em E1, é parcialmente aberta.

**Probabilidade:** ALTA — dados verificados live: 36/94 active têm agreement_certificate, **58/94 não têm**.

**Impacto:** MÉDIO-ALTO — maioria dos engagements legacy permanece com end_date null. Compliance reminding falha exatamente para o público legacy mais expostos a renewal-not-noticed.

**Mitigation per entregável:**
- **Hotfix Wave 0 / E1:** SQL audit pré-Wave 1 documentando 58/94 gap. ADR explicitamente registra "fallback strategy" para engagements sem agreement_certificate:
  - **Opção 1**: Backfill de PMI VEP serviceEndDateUTC (fonte secundária, opportunity-window-based, possivelmente impreciso vs term)
  - **Opção 2**: Backfill com data conservadora (e.g., current_date + 6 meses) + flag `end_date_source='estimated_legacy'`
  - **Opção 3**: Manual data entry por chapter VP secretarial — labor-intensive
- **E2 worker:** popular `metadata->>'end_date_source'` indicando fonte ('agreement', 'pmi_vep', 'estimated', 'manual') para audit trail.
- **E3 cron:** filtros explícitos para `end_date_source` — alertas D-60 só para 'agreement' (most accurate); 'pmi_vep' alertas D-90 (mais cedo, menos confidence); 'estimated' alertas como "pendente confirmação" não data fechada.
- **Decision 2 retreat option:** se fallback policy não aceitável, defer Issue D fix para Cycle 4 com agreement_certificate backfill manual; documentar Issue D como "P1 não resolvido" no ADR.

**Owner:** data-architect Wave 2 E1 + Vitor PM (decisão fallback policy).

**Reversibility:** alta — fallback strategy pode evoluir; nenhum dado destruído; apenas cron alertas perdidos durante gap recoverable se fix shipa em N+1.

---

## Risks DEPRIORIZADOS (registered, not top-5)

### R6 — profileAboutMe leak via outro vetor (não LLM)
Se Vitor ou curator copiar bio do admin UI para shared doc enviado externamente. Mitigação: RLS + view_pii action gate + admin UI redaction. Probabilidade BAIXA dado access-tier policy + user awareness; impacto MÉDIO se acontecer. Watch-out E2 Wave 2.

### R7 — Multi-chapter data leak inter-chapter
Fabricio Costa's DC affiliation visível para Goiás president via dashboard. Mitigado por Decision 6 access tier (PM+DPO only durante active cycle). Probabilidade BAIXA com lock; impacto ALTO se vazar. Watch-out E4 Wave 2.

### R8 — Re-engagement email storm via isOpenToVolunteer ternary
19 Unknown receberem mensagem inadequada "noticed you're not open" / 78 True spam. Mitigação: Decision implícita (tratar isOpenToVolunteer como ternário, não booleano). Probabilidade MÉDIA, impacto MÉDIO. Watch-out E3 Wave 2.

### R9 — Cycle 3 freeze creates Cycle 4 lock-in (V2 enriched model never deploys)
Se Cycle 4 atrasar 6+ meses, V2 enriched fica pronto-mas-engaveted. Esforço waste. Probabilidade MÉDIA. Mitigation: Cycle 4 enrichment como milestone dated separado pós-Cycle 3 close.

### R10 — Prompt injection via cover_letter / non_pmi_experience (existing fields, not new)
Security-engineer flagged ZERO sanitization atual. Compounded by E3 mas vetor pré-existente. Mitigation: prompt injection hardening (escape/strip patterns) ANTES de qualquer expansion. Probabilidade MÉDIA, impacto ALTO. Watch-out E3 Wave 2.

---

## Síntese executiva pre-mortem

**3 dos 5 top-risks são ANTECIPÁVEIS via decisões PM Step 0** (R1 via Decision 6 + R2 via E1 Wave 2 invariant + R3 via E1 atomicity protocol). **2 dos 5 requerem decisões adicionais não cobertas** pelas 7 decisions Step 0:

- **R4 (cron misfires):** decisão UX adicional necessária — chapter VP secretarial coordination policy + dry-run staging requirement.
- **R5 (Issue D fallback):** decisão de fallback strategy — Vitor escolhe entre Opção 1/2/3 ou defer Issue D.

**Recomendação adicional ao Step 0:** adicionar **Decision 8 e Decision 9** ao set já recomendado:

### Decision 8 — Issue D fallback strategy para 58/94 engagements sem agreement_certificate
**Options:**
- A) Backfill PMI VEP serviceEndDateUTC (fonte secundária imprecisa)
- B) Backfill estimated current_date + 6m + flag origem
- C) Manual data entry chapter VP
- D) Defer Issue D — reconhecer como P1 não resolvido em p125

**Recommend: A com fallback B.** Multi-source com `metadata->>'end_date_source'` audit trail. Hotfix Wave 0 implementa. E3 cron filtra por source quality.

### Decision 9 — Cron deploy gate (E3)
**Options:**
- A) Dry-run staging 2 weeks → 3 pilot candidates → go-live
- B) Direct deploy com kill switch + monitoring 48h
- C) Phased rollout por chapter (Goiás first, expand)

**Recommend: A** — chapter VP secretarial briefed durante 2 weeks. Test pilots = Vitor + 2 chapter leads (consenting).

---

## Próximos passos

1. Vitor revisa pre-mortem + Step 0 strategic review
2. Vitor decide A/B/C/D nas **9 decisions** (7 Step 0 + 2 pre-mortem)
3. Cada decisão = 1 markdown em `docs/council/decisions/2026-05-09-p125-decision-N-slug.md`
4. **Wave 1 de E1** (ADR + DDL drafting) começa apenas após decisões 1-9 lock
5. Hotfix Wave 0 paralelo conforme Decision 1
