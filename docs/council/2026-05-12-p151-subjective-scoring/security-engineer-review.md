# Council review p151 — security-engineer lens — ADR-0079

## TL;DR

O consent reuse `consent_ai_analysis_at` para subjective scoring é juridicamente questionável sob LGPD Art. 8 §5 (especificidade do consentimento) e precisa de decisão formal com razão documentada ou coluna `consent_subjective_scoring_at` dedicada. O revoke trigger existente (`handle_consent_revocation`) NO SEU ESTADO ATUAL não cobre `video_screening_analysis` — o scope está hard-coded para `selection_evaluation_ai_suggestions` apenas, criando uma lacuna LGPD concreta. O resto da postura RLS e audit trail é defensável com os ajustes listados abaixo.

---

## Veredicto sobre consent reuse (D-CONSENT)

**Severity: HIGH**

O argumento "consent abrangente sobre análise IA do candidato" tem base razoável em ADR-0074, mas enfrenta dois problemas:

**Problema 1 — Escopo material diferente.** `consent_ai_analysis_at` foi coletado num contexto onde o candidato sabia que seu formulário e CV seriam processados por IA. Video transcription é tratamento adicional materialmente distinto: a IA agora avalia performance comunicativa/comportamental via voz transcrita. Art. 8 §5 LGPD exige consentimento "para finalidades determinadas"; ANPD interpreta "determinadas" como "identificáveis pelo titular ao consentir". Se o termo de voluntariado/tela de consent (ADR-0076) não menciona explicitamente avaliação de vídeo por IA, o reuso não tem cobertura formal.

**Problema 2 — A EF não verifica revogação ativa.** Step 1 (spec §3) checa `consent_ai_analysis_at IS NOT NULL`, mas NÃO checa `consent_ai_analysis_revoked_at IS NULL`. Candidata que revogou consent ainda teria scoring disparado pelo cron. Bug de gate independente da questão de especificidade.

**Recomendações:**

(a) Verificar texto exato do termo de voluntariado v2 / tela de consent. Se já menciona "análise de vídeos enviados", reuso defensável como editorial change. Se não: (i) nova coluna `consent_subjective_scoring_at` ou (ii) amendment Material Change ao termo com re-consentimento ativo (não retroativo per ADR-0076 Princípio 4, Decision 3 path Option B — mesma lógica de `profile_about_me`).

(b) Step 1 da EF DEVE checar: `consent_ai_analysis_at IS NOT NULL AND consent_ai_analysis_revoked_at IS NULL`. Combinação já usada em `check_ai_consent_at_suggestion_insert()` (linha 353 migration `20260516200000`).

---

## Salvaguardas Art. 20 §1 recomendadas (além de non-binding)

**Severity: MEDIUM**

Design D-NON-BIND=A é salvaguarda principal e abordagem correta. Camadas adicionais em ordem decrescente:

**Necessária (bloqueante para ACCEPTED):** Invariante CI via `pg_get_functiondef` auditando que `final_score` não referencia `ai_subjective_score_avg`. Spec R4 já propõe — não opcional, deve ser na migration e CI antes de ship.

**Recomendada (defensável em fiscalização):** Banner no modal Vídeos quando PM visualiza score: "Score gerado por IA — sinal auxiliar apenas. Decisão de seleção é exclusivamente humana." Cria evidência documental de que PM foi informado. Implementação: `<aside>` fixo no topo do modal, não dismissable.

**Opcional (over-engineering):** Checkbox PM ao usar score em decisão — fricção desnecessária num ciclo com 1 candidato. Reservar para volume. Audit log de "score visualizado" também over-engineering.

**Sobre "decisão humana forçada":** design atual não tem enforcement técnico de que PM avaliou vídeo independentemente antes de ver score IA. Em ciclos com volume, ordering importa (anchoring). Considerar como Cycle 5+ feature: mostrar score IA somente depois de avaliação humana submetida para o pillar correspondente.

---

## Gaps no audit trail proposto

**Severity: MEDIUM**

**Gap 1 — Rubric version não capturada suficientemente.** Se D-RUBRIC=B (tabela versionada), `prompt_hash` muda quando rubric muda — bom. Mas audit trail deve incluir `rubric_version_id` (FK para row da tabela) além do hash, para queries tipo "quantas análises usaram rubric v3?". Hash sozinho não queryable.

**Gap 2 — `ai_processing_log` não definida na spec.** Spec referencia como "ADR-0074 sediment" mas migration não foi lida. Se existe em produção (ADR-0074 Onda 3 p108), shape — especificamente se captura `application_id`, `screening_id`, `purpose`, `model_version` (full semver `claude-sonnet-4-6-20260415`, não só `claude-sonnet-4-6`), `input_hash`, `output_hash` — precisa ser validada. Se shape não inclui `screening_id` referenciando `pmi_video_screenings`, cadeia ficará parcial.

**Gap 3 — `failure_reason` pode registrar PII acidentalmente.** Ver "Riscos PII em logs" abaixo.

**O que basta para Art. 18 (titular pede explicação)?** Com `prompt_hash` + `transcription_hash` + `model_version` + `reasoning`, possível responder "seu vídeo foi avaliado com modelo X, rubric hash Y, score X.X dado porque Z (reasoning)". Cobre mínimo do Art. 20 §3. Adição de `rubric_version_id` torna explicação mais legível ao titular e DPO.

---

## Ajustes ao revoke trigger (prazo + escopo)

**Severity: CRITICAL**

**Escopo — bug concreto identificado:**

Trigger atual `trg_supersede_ai_suggestions_on_consent_revoke` chama `handle_consent_revocation()`, hard-coded para afetar `selection_evaluation_ai_suggestions` apenas (migration `20260516200000`, linha 375-379). Nova tabela `video_screening_analysis` NÃO está no escopo. Se candidato revogar consent após scores gerados, rows persistirão indefinidamente.

Migration `b_full_video_screening_analysis_table.sql` deve incluir extensão do trigger: `UPDATE video_screening_analysis SET status='superseded' WHERE application_id = NEW.id AND status NOT IN ('superseded', 'failed')`. Alternativamente, segundo trigger ou estender `handle_consent_revocation()`. Spec menciona "revoke trigger 72h purga `video_screening_analysis` rows" como requisito mas não mapeia para trigger existente — lacuna a fechar na migration.

**Prazo — 72h vs prazo legal:**

ANPD Resolução CD/ANPD nº 2/2022 não fixa prazo para eliminação pós-revogação no texto normativo. Art. 18, III LGPD estabelece direito à eliminação sem prazo específico para controlador agir. Não há regulamentação específica de prazo até agosto/2025. **"72h" é escolha técnica do controlador**; escolhas menores (24h, imediato) mais defensáveis em fiscalização.

**Recomendação:** trocar 72h por execução **imediata** no trigger (deleção/`superseded` na mesma transaction do UPDATE em `selection_applications`), com fallback cron para edge cases. Elimina janela de exposição. Se razão operacional exigir janela ("candidato pode reconsiderar"), documentar explicitamente em ADR-0079 como decisão consciente com justificativa.

**Adicionalmente:** cron purge `cycle_decision_date` (90d/180d) deve incluir `video_screening_analysis` explicitamente. Spec diz "piggybacks no purge cron existente" mas se cron existente operates por `selection_applications` cascade e `video_screening_analysis` tem `ON DELETE CASCADE` em `application_id`, a deleção de `selection_applications` propaga. Verificar se purge cron faz DELETE em `selection_applications` ou apenas anonimiza colunas — se anonimiza (UPDATE, não DELETE), CASCADE não dispara e `video_screening_analysis` persiste. **Bug documentado em ADR-0076 Princípio 6 (Risk 2 do pre-mortem).**

---

## RLS + organization_id retrofit window

**Severity: MEDIUM**

**Postura RLS proposta (rpc-only deny-all + org-scope restrictive) é padrão correto.** Segue exatamente padrão de `pmi_video_screenings` e `selection_evaluation_ai_suggestions`. Mental test:

- Anon: `rpc_only_deny_all USING(false)` bloqueia. Correto.
- Ghost auth (sem member): `auth_org()` retorna NULL (ADR-0077 caller-derived). `organization_id = NULL` falha. Correto.
- Member sem committee: RPC gate verifica `selection_committee` membership. Pattern de `get_ai_suggestion()` (linha 473-484) é modelo correto.
- Committee member: RPC gate abre. Correto.
- Service role (EF `pmi-ai-subjective`): contorna RLS. EF DEVE passar `organization_id` explícito em todos INSERTs conforme ADR-0077 Princípio 4.

**organization_id NOT NULL — Ω-E.2-c defer:**

Para tabela NOVA `video_screening_analysis`, NOT NULL deve ser aplicado na migration de criação **sem deferir** — não há legado para migrar. EF service role popula campo explicitamente conforme ADR-0077. Aplica retrofit em tabelas existentes pode ficar deferido, mas não esta.

**`auth_org()` em `video_screening_analysis`:** tabela não tem RLS baseada em `auth_org()` para leitura direta (rpc-only deny-all). RPCs SECURITY DEFINER fazem gate de capacidade. Consistente com padrão e correto.

---

## Riscos PII em logs

**Severity: MEDIUM**

**`failure_reason` text — risco concreto:**

Spec (§2) define `failure_reason text` sem restrição. Risco: código EF popule com mensagens que incluem conteúdo da transcrição: `"Transcription too short: 'Olá meu nome é Eduardo'" (15 chars, minimum 20)`. Vaza PII (nome, fragmento de fala) em coluna não coberta por retenção diferenciada.

**Mitigação necessária:** sanitizar `failure_reason` na EF para nunca incluir dados do candidato. Enum de failure reasons preferível: `CHECK (failure_reason IN ('low_transcription_confidence','transcription_too_short','model_timeout','invalid_json_output','consent_revoked'))`. Texto livre reservado a failure codes, não content snippets.

**`ai_processing_log.prompt_text` — risco teórico:**

Se tabela armazena prompt completo (além de hash), inclui transcrição do vídeo. Transcrição é PII. Verificar: (a) se armazena `prompt_text` ou só `prompt_hash`; (b) policies de acesso. Se `view_internal_analytics` puxa em admin UI, fragmentos de transcrição aparecem na UI para quem tem esse role — potencial over-exposure. **Recomendação: `ai_processing_log` armazenar SOMENTE hashes, não conteúdo.**

**`reasoning` no export Art. 18:**

D-EXPORT=A (incluir reasoning) correto. `reasoning` gerada pela IA sobre conteúdo do candidato → dado pessoal derivado do titular. Deve estar no export. Sem risk aqui.

---

## ADR readiness — verdict

**BLOCK — condicional com 3 itens antes de ACCEPTED**

ADR pode avançar para ACCEPTED apenas após:

**Item 1 (CRITICAL — bloqueante):** Confirmar que revoke trigger `handle_consent_revocation()` será estendido na migration `b_full_video_screening_analysis_table.sql` para incluir `video_screening_analysis`. Documentar no ADR-0079 a mudança de 72h para imediato (ou justificativa formal para manter 72h).

**Item 2 (HIGH — bloqueante):** Documentar no ADR-0079 a decisão D-CONSENT com uma das duas saídas: (a) evidência de que texto do termo voluntariado v2 / consent gate cobre explicitamente avaliação de vídeo por IA, ou (b) declaração de que isso constitui uso adicional e requer `consent_subjective_scoring_at` separada ou amendment Material Change. Decisão não pode ficar implícita como "mesmo padrão ADR-0074".

**Item 3 (HIGH — bloqueante):** Corrigir step 1 da EF `pmi-ai-subjective` para verificar `consent_ai_analysis_revoked_at IS NULL` além de `consent_ai_analysis_at IS NOT NULL`. Sem isso, candidatos que revogaram consent receberão scoring.

**Itens condicionais (não bloqueantes para ACCEPTED, bloqueantes para p152):**
- (a) `failure_reason` sanitização via enum ou instrução explícita na EF spec
- (b) `rubric_version_id` adicionado ao schema para queryability do audit trail
- (c) verificação do shape de `ai_processing_log` e se inclui `screening_id`
- (d) verificação de que purge cron faz DELETE (não apenas UPDATE/anonymize) em `selection_applications` para CASCADE propagar

---

**Arquivos lidos:**
- `docs/specs/p150-b-full-subjective-scoring-spec.md`
- `docs/adr/ADR-0079-subjective-scoring-via-video-transcription.md`
- `docs/adr/ADR-0076-pmi-3d-volunteer-model-and-phase-b-base-legal.md`
- `docs/adr/ADR-0077-auth-org-caller-derived-contract.md`
- `supabase/migrations/20260516200000_phase_b_pmi_journey_v4.sql` (linhas 96-398)
- `supabase/migrations/20260516350000_p86_wave5b1b_ai_analysis_runs.sql`
