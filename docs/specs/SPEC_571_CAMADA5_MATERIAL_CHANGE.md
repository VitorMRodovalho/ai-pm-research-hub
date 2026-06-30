# SPEC — #571 Camada 5: Backbone de Material change (re-aceite + version pin + cadeia de ratificação)

> **Status:** Draft para aprovação do PM. Decomposição em 5 PR-slices. Decisão de modelagem (adendo-vs-4-docs) **RESOLVIDA = Opção A (consolidar)** — PM, 2026-06-29.
>
> **Data:** 2026-06-29
>
> **Origem:** Issue #571 (`[legal-ops] Backbone de Material change … Camada 5`). Análise de entendimento via workflow `wf_6cbc5c94-631` (7 agentes, leituras ao vivo). PARECER §C (pipeline operacional Camada 5).
>
> **Relacionadas:** #459 (governance docs via MCP, CLOSED) · #573 (cláusulas EEE/UK) · #574 (fiscalização DPO, blocked) · #334 (C4 chain legal-ops, **gate G12 do dispatch outward**) · #335 (ADR-0094). Coorte legal-ops #568/#569/#570/#572 CLOSED.
>
> **ADRs tocados:** amenda **ADR-0016** (gates-as-data, Gate Matrix v3) · novos ADRs para version-pin, re-aceite state machine, per-work governing version.

---

## 0. Correção de grounding (LEIA ANTES) — drift de cláusulas e fonte canônica

A análise ao vivo provou que **o texto operativo do #571 NÃO está onde o issue aponta**. Três camadas de drift, todas confirmadas por leitura do DB:

1. **Issue × disco:** as cláusulas que o #571 cita (Política 12.2.1/12.2.2/12.6; Termo 15.3/15.4) **não existem** no HTML v2.2 em `tmp/ip-v2.2-html/` (gitignored). Em v2.2, Política §12 é um parágrafo único "Revisão" e o Termo tem cláusulas 1–14 (sem §15). Os arquivos em disco são um snapshot **anterior** ao backbone.
2. **Fonte canônica = corpos vivos do DB.** `governance_documents.current_version_id` aponta para:
   - Política → `document_versions.version_label = 'v2.7-p128-roberto-comment-redaction'` (id `8f4337e6`) — contém §12 completo (regime dual Material/Editorial).
   - Termo → `'R3-C3-IP v2.7-p150-15-4-opcao-c'` (id `29a2d175`) — contém §15.3/§15.4 completo.
   - Adendo Retificativo → `'v2.6-p90c-material-fixes'`.
   - Anexo Técnico → `'v1.0-p90c-anexo-tecnico-creation'`.
3. **`gd.version` (coluna TEXT) está defasada:** ainda lê `v2.3-adr0068-draft` para Política/Termo/Adendos. **Nunca confiar em `gd.version`** — resolver sempre via `current_version_id → document_versions.version_label`.

**Mapa de renumeração issue → texto real (v2.7):**

| Issue cita | Realidade v2.7 | Conteúdo |
|---|---|---|
| Política **12.6** (version pin) | **NÃO EXISTE** (§12 termina em 12.5) | Version-pin / governing-version-por-obra vive no **Termo 15.4.1** (+15.4.6 tie-break, +15.4.7 ledger) |
| Termo **15.3(f)** recusa expressa | 15.3 só tem (a)–(e) | Objeção fundamentada = **15.4.3**; recusa/rescisão = 15.3(e)→Cláusula 6 + direitos preservados 15.4.5 |
| Termo **15.4.7** governing version | 15.4.7 é o **ledger** (audit-trail por obra) | A **regra** está em **15.4.1**; ambos necessários |
| Material vs Editorial | — | Definição existe em **Política 12.2 (teste 5-prong a–e) / 12.3** |

**Recomendação operativa:** toda a spec é construída contra os corpos vivos `current_version_id` (v2.7/v2.6). O HTML v2.2 e `gd.version` são **stale**. Reconciliar `gd.version` é higiene de dados — incluído como sub-tarefa de PR-1 (baixo custo, alto valor anti-confusão).

---

## 1. Objetivo

Operar a **Camada 5 (ratificação)** sem ações manuais: quando um instrumento de governança binding sofre uma **Material change**, o sistema deve dirigir, de ponta a ponta e com prazos rastreáveis, o ciclo **classificação → ratificação → notificação → re-aceite → desfecho**, e fixar, por **obra**, a versão regente sob a qual ela foi constituída.

Quatro frentes (work areas), mapeadas às cláusulas vivas:

- **WA1 — Máquina de estados de Material change + re-aceite** (Política 12.2.1; Termo 15.3, 15.4.3, 15.4.4, 15.4.5).
- **WA2 — Cadeia de ratificação** (Política 12.2.2).
- **WA3 — Version pin + re-ancoragem** (Termo 15.4.1; vedação de remissão dinâmica; Anexo item 8.4 referenciado dinamicamente).
- **WA4 — Audit-trail por obra + versão regente** (Termo 15.4.1 regra + 15.4.7 ledger + 15.4.6 tie-break).

## 1.1 Escopo / Fora de escopo

**No escopo (self-contained, texto legal já ratificado/em ratificação):** schema + RPCs + crons + UI da máquina de estados, do version-pin, da cadeia de ratificação material e do stamp por-obra. Calendário de dias úteis BR. Classificação material/editorial. Consolidação do Adendo (Opção A) no plano de modelagem.

**Fora de escopo / gated:**
- **Dispatch OUTWARD** (notificação de 30 dias aos capítulos, disparo da campanha de re-aceite a voluntários, ratificação PMI-GO ao vivo) — **gated em PM-OK + #334 (G12 DPO/ANPD)**. A máquina é construída **dormente**; o disparo é uma ação humana posterior (PARECER §C passos 5–7 são `[OUTWARD]`).
- Mérito jurídico dos instrumentos / redação da cláusula de superação do Termo v2.3 (Opção A) — é **ação do jurídico do Ivan**, pré-requisito da ratificação, fora do código.
- Reescrever o subsistema de approval chains (reusar ADR-0016).

## 1.2 Decisão de modelagem — RESOLVIDA: Opção A (consolidar)

**PM decidiu (2026-06-29): consolidar o Adendo Retificativo no Termo base.** Fundamentos factuais (verificados ao vivo este turno):

- **Janela irrepetível:** `member_document_signatures` = **0 linhas** (nenhuma assinatura de produção de qualquer instrumento; o Adendo nunca foi disparado — Etapa 4 do CR-050 não deflagrada). Consolidar agora = **custo de migração zero**.
- **Conteúdo idêntico:** Termo v2.7 Cláusula 2 ≡ Adendo Art. 3 (substantivamente palavra-por-palavra); Art. 4 ≡ Cláusula 13; Art. 5 ≡ Cláusula 4 §único; Art. 8 ≡ Cláusula 14. Dois instrumentos com conteúdo idêntico = risco de **drift jurídico** (análogo ao body-drift de RPC, com consequência em litígio).
- **Ambiguidade NULL fatal para WA4:** em Opção B, o stamp por-obra precisaria de `governing_adendo_version_id = NULL` com **dois sentidos opostos** ("Termo antigo sem Adendo → Cláusula 2 defeituosa vigora" vs "Termo novo sem necessidade de Adendo"). Opção A elimina a classe inteira.

**Consequências para o backbone:**
- `governance_documents` do Adendo Retificativo (`doc_type='volunteer_addendum'`) → `status='superseded'` (NUNCA deletar; preservar as 7 `document_versions` como registro histórico do CR-050 e das 5 fragilidades jurídicas).
- WA4 stamp por-obra referencia **um** `governing_termo_version_id` (sem FK composto, sem condicional).
- Lista de instrumentos binding cai de 4 → **3** (Política, Termo, Anexo).
- **Pré-requisito legal (fora deste backbone):** o **Termo v2.7** — instrumento **ora em vias de ratificação** (`document_versions` id `29a2d175`, label `R3-C3-IP v2.7-p150-15-4-opcao-c`), que **já absorve** o conteúdo do Adendo (Cláusula 2 ≡ Adendo Art. 3) — deve conter **cláusula expressa de superação**: *"O presente Termo revoga e substitui integralmente o Termo R3-C3 anteriormente vigente e o Adendo Retificativo CR-050, cuja regulação de Propriedade Intelectual fica absorvida pela Cláusula 2 deste instrumento"*, confirmada por advogado licenciado **antes** de ratificar. ⚠️ A cláusula vai no instrumento **NOVO** (v2.7), nunca no v2.3 (que é o que está sendo supersedido) — arts. 472–473 CC. **A spec do backbone não bloqueia nisso**; o schema de version-pin trata o Adendo Retificativo como `governance_documents.status='superseded'` (preservar as 7 `document_versions`).

---

## 2. Estado atual vs. gaps (grounded)

Reuso máximo: a fundação IP-1..IP-4 (ADR-0016) já entrega o esqueleto. Os gaps são cirúrgicos.

### WA1 — re-aceite (máquina de estados)
**Reusar:** `member_document_signatures` (ledger por-membro + auto-supersede via `trg_member_doc_sig_supersede_previous`) · `sign_volunteer_agreement` (template do RPC de re-aceite expresso) · `notifications` + `create_notification()` + cron `send-notification-emails` (jobid 9) · `notify_privacy_policy_change` + `privacy_policy_versions.summary_pt/en/es` (template do aviso-30d-com-sumário) · `recirculate_governance_doc` (caminho 15.4.3(a)) · `offboard_member`/`admin_offboard_member` (terminal **não-destrutivo** ⇒ licenças preservadas) · `affiliation_access_attestations` + `_enforce_affiliation_attestation` (**análogo já shipado de "bloqueia acesso até re-aceitar a versão vigente"**) · cron `v4_engagement_expiry_notify` (jobid 19, precedente de sweep por deadline).

**Gaps (todos confirmados ausentes):**
- 🔴 **Máquina de estados por-membro** (obrigação + janela + deadline + enum de estado). Não há onde um status de re-aceite viver. *(`member_document_signatures` só registra aceite concluído.)*
- 🔴 **Helper de dias úteis** (15/10/5 úteis + auto-extensão) — `add_business_days` = 0 funções; sem tabela de feriados.
- 🔴 **Classificação Material/Editorial estruturada** — `document_versions.change_class` = 0; `change_requests.cr_type` ∈ (editorial/operational/structural/emergency), sem `material`.
- 🔴 **Estado 'suspenso (+30d)' reversível** — `engagements.status='suspended'` é CHECK-válido **e JÁ é setado** pelo cron de expiração (`v4_phase5_real_expiration`, `auto_expire_behavior=suspend`); reusar o MESMO valor p/ re-aceite cria ambiguidade de discriminação ⇒ **SSOT = tabela de obrigação** (`member_reacceptance_obligations.state`), **sem espelhar** em `engagements.status` (ver §9.5). `admin_offboard_member` só faz `offboarded` (one-way).
- 🟠 Fluxo **objeção fundamentada** (15.4.3): registro + SLA Comitê 10 úteis + cascata-suspensa + extensão por atraso + acomodação 5 úteis.
- 🟠 Caminho **recusa expressa**: desvinculação imediata **independente da cascata**, preservando licenças (15.4.5).
- 🟠 **Cron** do ciclo de vida (abrir aviso-30d → suspenso em +15 úteis → desligar em +30d).
- 🟠 **Aviso-30d com sumário** ancorado em `effective_from`: instrumentos não têm `summary_pt/en/es`.

### WA2 — cadeia de ratificação
**Reusar:** `approval_chains.gates jsonb` (sequência **já resolvida** por `_prior_gates_satisfied` + guard de escrita #654) · gate **`president_go`** (threshold 1) = **ratificação obrigatória PMI-GO já existe** · `approval_signoffs` (ledger sha256 + content_snapshot; `signoff_type` já aceita abstain/rejection) · `resolve_default_gates(p_doc_type)` (registry de templates) · `get_chain_audit_report`/`get_pending_ratifications`/`_enqueue_gate_notifications`.

**Gaps:**
- 🔴 **Parceiros consultivo 15 úteis sem veto** está **INVERTIDO**: o único gate de parceiro (`president_others`, threshold 4) é **bloqueante** — capítulos parceiros hoje têm veto de fato (chain não aprova sem os 4). Precisa de gate `partner_consultation` **não-bloqueante + janelado**.
- 🔴 **Conceito de janela temporal** inexiste — `approval_chains` não tem coluna de deadline; nada avança chain por tempo decorrido.
- 🟠 **Threshold `maioria`** — `_validate_gates_shape` só permite `int>=0` ou `'all'`; `_gate_threshold_met` só implementa all/N/0. "Comitê maioria simples" não é expressável.
- 🟠 **Âncora de elegibilidade por-gate** — só existe `chain.opened_at`; a janela de 15 úteis precisa ancorar em quando o gate consultivo ficou elegível (após `president_go`).

### WA3 — version pin + re-ancoragem
**Reusar:** `get_version_diff(a,b,include_content)` (diff intra-documento) · `document_versions` imutável (`locked_at`, `trg_document_version_immutable`) · `confirm_manual_version`/`lock_document_version` (estender no confirm para setar `change_class`) · `change_requests.cr_type` (alimenta `change_class` via mapeamento explícito).

**Gaps:**
- 🔴 **Tabela de binding instrumento→versão-pinada** inexiste. A única coluna cross-ref (`related_manual_sections`) é NULL em toda linha e não é um pin.
- 🔴 **Remissão dinâmica é o estado VIVO e nada a veda:** seeds dizem "Política … vigente" / "enquanto durar o Acordo … ao qual está vinculado". Req (a) (vedar) não tem ponto de enforcement.
- 🟠 **`change_class` na versão** (material|editorial) — ausente; drift codificado só em `version_label` free-text.
- 🟠 **Propagação**: editorial não auto-avança o pin dos instrumentos vinculados; material não marca `re_anchor_required`.
- ⚪ `approval_signoffs.referenced_policy_version_id` (66/73 populados) é **snapshot de auditoria** "versão corrente no momento da assinatura" — **NÃO** é o binding SSOT; manter separado para não reintroduzir remissão dinâmica.

### WA4 — versão regente por obra
**Reusar:** `content_products` (37 linhas, **âncora canônica de obra**; 1:1 com 37 `publication_submissions`) · `document_versions` (FK alvo dos `governing_*_version_id`) · `governance_documents.current_ratified_version_id` (fonte da Política regente) · `member_document_signatures.signed_version_id` (Termo regente por-autor) · `pi_exclusion_assets` (#569: write-once + sha256 + OpenTimestamps — template de imutabilidade) · `get_chain_audit_report` (shape do relatório por-obra) · `rls_can_see_initiative()` (ADR-0105, obrigatório se a obra liga a initiative confidencial).

**Gaps:**
- 🔴 **Stamp por-obra inexiste** em qualquer tabela (`governing_termo_version_id`/`governing_politica_version_id`/`attribution`/`enquadramento` ausentes). `first_ratified_version_id` existe só no grão **documento**.
- 🟠 **Detector de "primeira contribuição material"** por obra — só há `created_at`/`submitted_at`, sem semântica de materialidade.
- 🟠 **Imutabilidade write-once** generalizada só existe em `pi_exclusion_assets` (dormante).
- 🟠 **Polimorfismo de obra:** "obra" abrange ≥5 tabelas (content_products 37, tribe_deliverables 71, event_showcases 25, public_publications 7, knowledge_assets) sem entidade canônica unificadora.
- 🟠 **Fonte runtime ainda vazia:** `current_ratified_version_id` é NULL para Política/Termo; `member_document_signatures` = 0. Stamp hoje congelaria NULLs ⇒ **WA4 depende de WA2+WA3 populando** + ratificação do v2.7.

---

## 3. Timelines (v2.7, confirmados ao vivo) — unidades importam

| Evento | Valor | Unidade | Fonte |
|---|---|---|---|
| Pré-aviso antes da vigência | 30 | **corridos** | Política 12.2.1 / Termo 15.3(a) |
| Janela de re-aceite | **15** | **úteis** | Termo 15.3(b) |
| Suspenso (re-aceite tardio permitido) | +30 | **corridos** | Termo 15.3(c) |
| Comitê responde objeção | **10** | **úteis** | Termo 15.4.3 |
| Acomodação mediada (mini-janela) | **5** | **úteis** | Termo 15.4.3(c) |
| Parceiros — manifestação consultiva sem veto | **15** | **úteis** | Política 12.2.2 |
| Editorial — ciência (sem re-aceite) | 15 | corridos | Política 12.3 / Termo 15.2 |
| Reorg estrutural — janela ampliada | +60 | corridos | Termo §16 continuidade (corpo v2.7 menciona "60 (sessenta) dias"; nº de subcláusula a confirmar ao vivo) |

⚠️ **Regra dura:** misturar dias úteis e corridos. **Não existe calendário de dias úteis BR no sistema** (`add_business_days`=0, tabela de feriados=0). PR-1 deve construir `add_business_days` + `br_holidays` (nacionais + Goiás/GO). O modelo de prazo deve armazenar `{valor, unidade}` por timeline.

**Teste material vs editorial (Política 12.2, 5-prong):** MATERIAL se (a) cria/modifica/extingue obrigação ou direito de signatário; (b) altera escopo/regime/destinação de PI; (c) modifica quórum/processo decisório/competências do Comitê; (d) cria nova sanção; (e) altera regra de opt-out/retirada de consentimento/janela de re-aceite. EDITORIAL = redacional que não toca nenhum desses. **Aceite tácito (art. 111 CC) só para Editorial — NUNCA Material (15.4.4).** Tie-break (15.4.6): ambiguidade → interpretação pró-voluntário; versão regente em dúvida → data da 1ª contribuição material.

---

## 4. Invariantes a honrar (NÃO quebrar)

1. **Append-only:** re-aceite/recusa/objeção/re-ancoragem = **NOVAS linhas**, nunca mutação de linha lacrada (`trg_document_version_immutable`, `trg_approval_signoff_immutable`). O re-aceite passa **pelo INSERT** em `member_document_signatures` (dispara auto-supersede), não por flip manual de `is_current`.
2. **V_status_chain_coherence:** virar `governance_documents` para approved/active exige `current_ratified_chain_id` populado — dirigir via `sign_ip_ratification`/chain-close (`trg_sync_ratification_cache` preenche o cache).
3. **J_current_version_published (chain-aware):** manter o carve-out de "chain aberta em voo"; lacrar a versão no fechamento da chain.
4. **`_validate_gates_shape` — DOIS branches** devem ser estendidos **atomicamente** na mesma migration: (a) o **allowlist de `kind`** (hoje 11 kinds) E (b) o **allowlist de `threshold` string** (hoje só `'all'`; adicionar `'majority'`/`'window_optional'`). Esquecer (b) faz o INSERT da chain estourar o CHECK `approval_chains_gates_shape` (ver §9.4).
5. **`_can_sign_gate` PURO (#654):** é o denominador do threshold `'all'`. Toda lógica nova de maioria/janela/quórum vive em `_gate_threshold_met` + guards, **nunca** em `_can_sign_gate` (tornaria-o time/order-aware ⇒ denominador colapsa a 0 ⇒ gates falsamente "met").
6. **ADR-0102 GR-1 (comment ≠ sign; visibility ≠ actionability):** nenhum reader/notificação da Camada 5 pode expor sign-CTA / `approval_chain_id` / `eligible_gates` a não-signatário. **O dispatch de re-aceite em massa (passo 7) é exatamente a superfície do leak #648/#653** (card de assinatura empurrado a ~55 pessoas incl. 25 guests pré-onboarding) — por isso é `[OUTWARD]` + gated.
7. **DDL via `apply_migration`** apenas (depois escrever arquivo local + `migration repair --status applied` + `NOTIFY pgrst`); `rpc-migration-coverage` + body-drift quebram senão.
8. **Sem remissão dinâmica:** pin = referência dura a `document_versions.id`, nunca texto "vigente". `consent_records.policy_version` é TEXT free-form — **não copiar** esse modelo para pin instrumento-a-instrumento.
9. **Sem seed-expand de `engagement_kind_permissions`** como atalho de autoridade (privilege-escalation; lifecycle = GP-only, LGPD Art.18). Rodar o procedimento 4-etapas `V4_AUTHORITY_MODEL` antes.
10. **ADR-0105 confidencial:** qualquer novo reader SECDEF sobre linhas ligadas a initiative aplica `rls_can_see_initiative()`; nova tabela ligada a initiative carrega a policy RESTRICTIVE AJ.
11. **Licença preservada (15.4.5):** desligamento por recusa/lapso **NÃO** deleta `member_document_signatures` nem revoga licenças; crons de anonimização LGPD (jobid 15/17/71) devem excluir/preservar. Guard por contract test.
12. **Não citar números de MEMORY** ([RE-VERIFICAR]: "52 voluntários", "5 capítulos") como fato na SPEC/PR — re-query ao vivo antes de qualquer prompt de decisão.
13. **Build/test verdes:** `astro build` 0 novos erros, `npm test` 0 fail, `check_schema_invariants()` = 0 violações (baseline vivo).

---

## 5. Decomposição em PR-slices

O issue estimou ~4 PRs. A análise mostra **2 primitivos cross-cutting** (`change_class` + dias-úteis) compartilhados por WA1/WA2/WA3 — mais limpo como **PR-1 (fundação)**. Resultado: **5 slices** com spine de dependências. Todos **self-contained / behavior-neutral** exceto onde marcado `[OUTWARD/gated #334]`.

```
PR-1 Fundações ──┬─→ PR-2 Version-pin (WA3) ──┐
 (change_class,  │                            ├─→ PR-5 Versão-regente-por-obra (WA4)
  dias úteis)    └─→ PR-3 Cadeia material ────┘        (depende de WA2+WA3 populando)
                        (WA2) ──→ PR-4 Re-aceite state machine (WA1)
                                       [dispatch OUTWARD gated #334]
```

### PR-1 — Fundações: classificação + calendário de dias úteis
**Objetivo:** os dois primitivos dos quais todo o resto depende. Behavior-neutral.
- **DDL:** `document_versions.change_class text CHECK in ('editorial','material')` (nullable; resolvido no confirm, nunca default silencioso). `br_holidays(date pk, label, scope text CHECK in ('national','GO'))` + seed. Função `add_business_days(timestamptz,int) returns timestamptz` + `business_days_between`.
- **Wire:** `confirm_manual_version` seta `change_class` (mapeamento explícito de `change_requests.cr_type`: editorial→editorial; operational/structural/emergency→material; NULL **deve ser resolvido**, não defaultado). Higiene: reconciliar `gd.version` ← `current_version_id` label.
- **ADR:** "Material/Editorial como campo de 1ª classe + calendário BR".
- **Testes:** `add_business_days` honra feriados; mapeamento cr_type→change_class; reconciliação gd.version.
- **Critérios de aceite:** toda nova versão lacrada carrega `change_class`; `add_business_days('2026-04-21'(Tiradentes),1)` pula o feriado; `check_schema_invariants()`=0.

### PR-2 — Version pin + re-ancoragem (WA3)
**Objetivo:** SSOT do pin instrumento→versão; vedar remissão dinâmica; editorial auto-aplica / material exige re-âncora expressa.
- **DDL:** `instrument_version_bindings(id, organization_id, bound_document_id FK, referenced_document_id FK, pinned_version_id FK document_versions NOT NULL, pin_clause_ref, re_anchor_required bool default false, last_material_version_id, status CHECK('active','superseded'), bound_at/by; UNIQUE(bound_document_id,referenced_document_id) WHERE active; CHECK referenced<>bound)`. NOT NULL no `pinned_version_id` **veda remissão dinâmica por construção**.
- **RPCs:** `pin_instrument_version(bound, referenced, pinned_version, clause_ref)` (SECDEF, manage_platform; valida que a versão pertence ao referenced e está locked) · `reanchor_instrument_binding(binding, new_version, justification)` (único caminho que limpa `re_anchor_required`; escreve audit) · `list_stale_instrument_bindings()` (read p/ dashboard; par com `get_version_diff(pinned, current)`).
- **Trigger:** `trg_propagate_version_change_class` — ao confirmar nova versão: se `editorial` → auto-avança `pinned_version_id` dos bindings ativos do referenced (auditado); se `material` → seta `re_anchor_required=true` + `last_material_version_id`.
- **Invariante:** `no_dynamic_remission` (toda linha que referencia outro instrumento binding tem binding ativo com pin não-nulo). **Backfill ANTES de enforçar:** os **4** `cooperation_agreement` ativos (PMI-GO↔CE/DF/MG/RS) pinam a versão da Política **vigente na data de assinatura** (preserva o que as partes vincularam).
- **ADR:** amenda ADR-0016 (pin = `document_version_id` imutável, não label; por-instância; `referenced_policy_version_id` permanece snapshot de auditoria, não SSOT).
- **Critérios:** os 4 acordos têm binding ativo pós-backfill; um editorial avança o pin sem `re_anchor_required`; um material seta `re_anchor_required`; INSERT com remissão genérica é rejeitado pelo invariante.

### PR-3 — Cadeia de ratificação para Material change (WA2)
**Objetivo:** Comitê maioria simples + ratificação obrigatória PMI-GO (já existe) + parceiros 15 úteis consultivo **sem veto**.
- **Schema de gate:** estender o elemento de `{kind,order,threshold}` para `{kind,order,threshold, blocking?:bool, window_business_days?:int}`. Novo threshold `'majority'`. **Estender `_validate_gates_shape` allowlist na mesma migration.**
- **Novos gate kinds:** `committee_majority` (threshold `'majority'`; **snapshot do roster do Comitê na abertura da chain** p/ matemática determinística) · `partner_consultation` (`blocking=false, window_business_days=15`; registra approval/abstain/objection mas **nunca bloqueia**; auto-satisfaz quando janela expira OU todos respondem). **NÃO** repropositar `president_others` (cooperation_agreement/_addendum legitimamente precisam dele bloqueante).
- **RPC:** estender `_gate_threshold_met` com branch `majority` (`count(approvals) > floor(eligible/2)` + guarda de quórum) e branch janelado (TRUE quando janela expira OU todos elegíveis responderam). `_can_sign_gate` permanece PURO (#654).
- **Âncora + cron:** persistir quando cada gate ficou elegível (`approval_chains.gate_state jsonb` ou child `gate_activations`); cron diário `ratification-window-close` detecta janelas expiradas → marca gate fechado → re-avalia conclusão da chain → `_enqueue_gate_notifications` (on-read nunca vira status sozinho).
- **Template:** atualizar `resolve_default_gates('policy')` para o novo template (Comitê maioria → president_go obrigatório → partner_consultation 15 úteis). ADR: amenda ADR-0016 "Gate Matrix v3".
- **Testes:** maioria contra roster pinado; **não-resposta de parceiro NÃO bloqueia após 15 úteis**; rejeição de parceiro registrada mas não-vetante; sequência ainda enforçada; shape aceita novos campos e rejeita malformados.
- **Critérios:** chain de policy aprova com Comitê-maioria + president_go mesmo sem todos os parceiros; `check_schema_invariants()`=0.
- ⚠️ **Aberto p/ legal/PM:** composição do "Comitê" (designação `ip_committee` vs roster explícito) e quórum mínimo — ver §7.

### PR-4 — Máquina de estados de re-aceite (WA1) — **dispatch OUTWARD gated #334**
**Objetivo:** o ciclo notif-30d → re-aceite-15-úteis → suspenso-+30d → desligamento, com objeção e recusa. Máquina **construída dormente**; disparo de massa é ação humana gated.
- **DDL:** `member_reacceptance_obligations(id, member_id, document_id, from_version_id, to_version_id, change_class, effective_from, notified_at, window_opens_at, window_closes_at = add_business_days(notified_at,15), suspended_until = window_closes_at + 30d corridos, state enum(pending_notification,notified,in_window,objection_pending,accommodation_window,suspended,re_accepted,refused,lapsed_disengaged), objection_id, signature_id FK member_document_signatures, license_preservation_noted bool, resolved_at, resolution)` RLS member-scoped. `reacceptance_objections(id, obligation_id, member_id, body, contested_points, suggested_text, registered_at, committee_due_at = add_business_days(registered_at,10), committee_decision enum(accepted,rejected,accommodation), committee_responded_at, minutes_ref, accommodation_window_closes_at = add_business_days(responded_at,5), recirculated_chain_id)`. Adicionar `summary_pt/en/es` à versão (ou tabela lateral) p/ o aviso-30d.
- **RPCs:** `open_reacceptance_obligations(document, to_version)` (manage_platform; só p/ `change_class='material'`, fan-out 1 obrigação por signatário ativo + rascunha aviso-30d reusando padrão `notify_privacy_policy_change`; editorial ⇒ nenhuma obrigação) · `express_reacceptance(obligation)` (membro; INSERT em `member_document_signatures` reusando `sign_volunteer_agreement`; permitido em `in_window` E `suspended` — re-aceite tardio 15.3(c)) · `register_reacceptance_objection(...)` (suspende timer da cascata) · `respond_reacceptance_objection(objection, decision, minutes)` (gate Comitê: accept→`recirculate_governance_doc`+reinicia 15.3 / reject→ata+retoma cascata / accommodation→janela 5 úteis; resposta tardia auto-estende janela do membro pelo atraso) · `refuse_reacceptance(obligation)` (15.3(e)/recusa; desligamento imediato via `offboard_member` com `reason_category='reacceptance_refusal'`, `license_preservation_noted=true`, **independente da cascata**).
- **Cron:** `reacceptance-lifecycle-sweep-daily` (ao lado do jobid 18): `pending_notification→notified` (envia aviso-30d), `in_window→suspended` em `window_closes_at` (espelha `engagements.status='suspended'`), `suspended→lapsed_disengaged` em `suspended_until` via `offboard_member`, expiração de acomodação, lembretes de objeção, auto-extensão por Comitê tardio. **Idempotente** sob re-run diário.
- **Estado do 'suspenso':** SSOT = tabela de obrigação; espelhar p/ `engagements.status='suspended'` (já CHECK-válido) p/ enforcement de gate. **NÃO** adicionar valor a `members.member_status` (evita reabrir edges do `validate_status_transition`/ARM-9). — *decisão ADR, ver §7.*
- **Invariante + UI + i18n:** `license-preservation-on-reacceptance-disengagement` (contract test; excluir lapsed dos crons de anonimização) · banner/countdown/formulário-de-objeção em `src/pages/governance/*` + `volunteer-agreement.astro` (respeitando GR-1 — só a signatários) · chaves `reacceptance_required/_suspended_warning/_objection_response/_disengaged` nas 3 línguas.
- **Gate OUTWARD:** os RPCs existem e a máquina roda dormente, mas **`open_reacceptance_obligations` em produção (fan-out real + aviso-30d aos capítulos)** só dispara com **PM-OK + #334 (G12)**. Documentar no runbook.
- **Critérios:** obrigação material abre→notifica→suspende→desliga com prazos corretos em úteis/corridos; editorial não abre obrigação (aceite tácito); recusa preserva `member_document_signatures`; objeção congela cascata; cron idempotente.

### PR-5 — Audit-trail por obra + versão regente (WA4)
**Objetivo:** stamp imutável da versão regente (Termo/Política) por obra na 1ª contribuição material. **Opção A** ⇒ um `governing_termo_version_id` (sem composto).
- **DDL:** `work_governing_version(id, organization_id, work_type CHECK(content_product,publication_submission,tribe_deliverable,event_showcase,public_publication,knowledge_asset), work_id, first_material_contribution_at NOT NULL, governing_termo_version_id FK document_versions, governing_politica_version_id FK document_versions, attribution_text (snapshot denormalizado), enquadramento jsonb (9.610/9.609/9.279), stamped_at/by, superseded_by_id; UNIQUE(work_type,work_id))`. Polimórfico (sem FK em `work_id`) — integridade via trigger + contract test.
- **RPC/trigger:** `stamp_work_governing_version` (SECDEF; Política regente = `current_ratified_version_id`; Termo regente = `member_document_signatures.signed_version_id is_current` do autor à data; enquadramento auto-derivado da natureza; idempotente por (type,id); REVOKE PUBLIC/anon como `register_exclusion_asset`). `trg_work_governing_version_immutable` (write-once; correção só via `superseded_by` chain — legal "retificação"). `get_work_governing_version` (read; aplica `rls_can_see_initiative()` p/ obras de initiative confidencial).
- **Snapshot vs FK:** armazenar **FK + snapshot denormalizado** de `attribution_text`/`enquadramento` (durabilidade "preservada independentemente de mudanças posteriores").
- **Dependência:** roda **dormente** até WA2/WA3 popularem `current_ratified_version_id` + existirem signatures; senão congela NULLs. Sequenciar após v2.7 ratificar (ou guardar com check de não-NULL).
- **ADR + teste:** grão por-obra vs por-documento; âncora "1ª contribuição material"; contract test "toda obra `published` tem exatamente 1 `work_governing_version` imutável".
- **Critérios:** obra publicada carrega stamp imutável; mutação pós-stamp é rejeitada (só superseded chain); reader confidencial respeita ADR-0105.
- ⚠️ **Aberto p/ legal/PM:** o que conta como "1ª contribuição material" (created_at do content_product vs first-drafted vs first-author); governing Termo por-autor vs por-obra em obras multi-autor — ver §7.

---

## 6. Pipeline operacional (PARECER §C) — onde cada passo aterrissa

| Passo | Ação | Cobertura |
|---|---|---|
| 1 [PM] | conferir .docx v2.7 + sha256 | manual (Tópico B blockchain) |
| 2 | re-importar como DRAFT + diff | **reusa** version subsystem (propose/edit/confirm + get_version_diff) |
| 3 [PM] | classificar Material vs Editorial | **PR-1** (`change_class`) |
| 4 | rotear via CR (submit→review→approve); editorial→lock+DONE (tácito) | **reusa** change_requests + **PR-1** fork |
| 5 `[OUTWARD]` | ratificação PMI-GO antes de circular | **PR-3** (president_go existe; +committee_majority+partner_consultation) · gated #334 |
| 6 `[OUTWARD]` | notificação 30d aos capítulos (após gate) | **PR-4** (open_reacceptance_obligations) · gated #334 |
| 7 `[OUTWARD]` | janela 15 úteis de re-aceite | **PR-4** (express/objection/refuse + cron) · gated #334 |
| 8 | lock + register_decision + espelhar wiki | **reusa** lock_document_version + register_decision |

---

## 7. Questões abertas (PM/legal — não-bloqueantes do backbone; resolver até o PR respectivo)

1. **Composição do "Comitê de Curadoria"** p/ maioria simples (12.2.2): designação `ip_committee` vs roster explícito snapshot-ável; quórum mínimo. *(bloqueia PR-3 go-live, não o schema.)*
2. **Sponsor PMI-GO = president_go?** O predicado vivo chaveia em `chapter_board`+`legal_signer`; "Chapter Sponsor" (Ivan) é o presidente. Confirmar semântica.
3. **Âncora da janela consultiva de 15 úteis** (chain-open vs após president_go vs após committee_majority). Recomendação: após `president_go` (passo 5 precede passo 6).
4. **"1ª contribuição material" por obra** (WA4): `content_products.created_at` (default recomendado, âncora canônica) vs first-drafted vs first-author. Fixa a versão regente irreversivelmente — ruling legal.
5. **Governing Termo por-autor vs por-obra** em obras multi-autor (co-autores podem ter assinado versões diferentes). Recomendação: snapshot por-autor.
6. **Terminal 15.3(d)** "desligamento OU suspensão": alvo do `offboard_member` (alumni vs inactive vs suspenso-longo). Recomendação: `inactive` reversível.
7. **Estado-de-registro do 'suspenso':** tabela de obrigação (SSOT) + espelho `engagements.status='suspended'` (recomendado) vs novo `members.member_status`. *(ADR de PR-4.)*
8. **Shippar o engine antes do v2.7 ratificar?** O lifecycle é auto-referente (v2.7 §12 governa mudanças futuras mas v2.7 ainda não fechou chain). Recomendação: **shippar dormente** (build-ahead, go-live gated) — padrão do projeto.
9. **Calendário de feriados:** nacional + Goiás/GO (sede PMI-GO); capítulos parceiros em outros estados têm feriados estaduais distintos — escopo do `br_holidays.scope`.

---

## 8. Referências

- Issue #571. Análise: workflow `wf_6cbc5c94-631` (saída completa em `tasks/wfbhqy44s.output`).
- Cláusulas vivas: `document_versions` Política `8f4337e6` (v2.7-p128), Termo `29a2d175` (v2.7-p150-15-4-opcao-c).
- ADR-0016 (IP ratification, gates-as-data) · ADR-0102 (GR-1 visibility≠actionability) · ADR-0105 (#785 confidencial) · ADR-0068 (curadoria redraft).
- `docs/specs/SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md` · `docs/reference/V4_AUTHORITY_MODEL.md`.
- PARECER §C: `/home/vitormrodovalho/Downloads/nucleo-juridico-revisado/09-PARECER-tracking-blockchain-plataforma.md` (fora do repo).
- Gate G12 / dispatch outward: #334.

---

## 9. Correções da revisão adversarial (NORMATIVAS — incorporar na implementação)

Revisão por 3 lentes (`wf_baf67909-cb0`: data-architect + legal-counsel + security-engineer, cada uma tentando quebrar a spec; todas verdict `has_blockers`). Achados confirmados ao vivo. **Estas correções são vinculantes** — sobrescrevem o pseudocódigo de §5 onde conflitarem. Contradições entre revisores resolvidas por query deste turno: `knowledge_assets` **existe** (manter); `reacceptance_refusal` **não existe** em `offboard_reason_categories` (inserir); `engagements.status='suspended'` **já é setado** pelo cron de expiração (não espelhar).

### 9.1 Cross-cutting (todas as PRs)
- **RLS (GC-162):** TODAS as 4 tabelas novas (`instrument_version_bindings`, `member_reacceptance_obligations`, `reacceptance_objections`, `work_governing_version`) carregam RLS habilitada + policies (member-scoped onde aplicável; `manage_platform`/`view_pii` p/ admin). A spec de §5 omitiu — obrigatório.
- **Tenancy:** adicionar `organization_id uuid NOT NULL` às tabelas de re-aceite/objeção (paridade com governance_documents/approval_chains, p269).
- **GRANT/REVOKE:** `REVOKE EXECUTE FROM PUBLIC, anon` em TODOS os SECDEF novos (não só `stamp_work_governing_version`): `pin_instrument_version`, `reanchor_instrument_binding`, `open_reacceptance_obligations`, `respond_reacceptance_objection`, `_reacceptance_disengage`, etc.
- **Preservação de licença vs anonimização LGPD (invariante §4.11) — mecanismo escolhido = Opção B:** guard em `anonymize_by_engagement_kind` (crons jobid 15/17/71): pular person se `EXISTS (SELECT 1 FROM member_document_signatures WHERE member_id = <person→member> AND is_current = true)`. Contract test: person com signature `is_current=true` é EXCLUÍDA do output do cron. (Mudar `anonymization_policy` do kind voluntário = amplo demais, rejeitado.)

### 9.2 PR-1 (fundações)
- **`add_business_days` = `STABLE`** (lê `br_holidays`), NÃO `IMMUTABLE` ⇒ não pode ser usada em `GENERATED ALWAYS AS` nem em `DEFAULT`. Todas as datas derivadas são **computadas em RPC no momento do INSERT/UPDATE** (ver 9.5).
- **Estender `trg_document_version_immutable`** p/ bloquear mudança de `change_class` quando `locked_at IS NOT NULL` (`OR NEW.change_class IS DISTINCT FROM OLD.change_class`). Sem isso, um privilegiado reclassifica material→editorial pós-lock e anula silenciosamente as obrigações de re-aceite. Critério de aceite de PR-1.
- **`summary_pt/en/es`** (aviso-30d): DECISÃO = **colunas inline em `document_versions`** adicionadas em PR-1 (reusa padrão `privacy_policy_versions`). Resolve a ambiguidade que PR-4 deixou aberta.

### 9.3 PR-2 (version pin)
- **UNIQUE parcial:** PostgreSQL não aceita `UNIQUE(...) WHERE` inline. Usar statement separado: `CREATE UNIQUE INDEX ivb_active_unique ON instrument_version_bindings(bound_document_id, referenced_document_id) WHERE status='active';`.
- **Editorial auto-advance = append-only** (honra §4.1): `trg_propagate_version_change_class` faz **INSERT de nova row** (`status='active'`, novo `pinned_version_id`) + UPDATE da antiga p/ `superseded`, NÃO UPDATE in-place. Preserva histórico da versão pinada (relevante p/ versão regente de obra em período intermediário).
- **Backfill (query canônica):** os 4 cooperation_agreements pinam a Política vigente **na data de assinatura** via o snapshot de auditoria — `SELECT s.referenced_policy_version_id FROM approval_signoffs s JOIN approval_chains ac ON ac.id=s.approval_chain_id WHERE ac.document_id=<coop_id> AND s.gate_kind='president_go' ORDER BY s.signed_at DESC LIMIT 1`. (`gd.current_version_id` é só o atual; não há tabela histórica.)
- **Atomicidade:** CREATE TABLE + backfill dos 4 + ADD do invariante `no_dynamic_remission` ao `check_schema_invariants()` na **MESMA migration**. Fornecer o SQL do check (instrumentos que referenciam outro binding sem row ativa com pin não-nulo → violation_count).
- **Concorrência:** `reanchor_instrument_binding` usa `SELECT ... FOR UPDATE` na binding antiga (evita 2 ativas).
- **Editorial→cooperation_agreement auto-advance é INTENCIONAL** (editorial não muda obrigação; partes não re-assinam; o audit log satisfaz a ciência 12.3). Documentar no ADR.

### 9.4 PR-3 (cadeia material)
- **`_validate_gates_shape`:** estender os DOIS branches (ver invariante §4.4): kind IN-clause **+** threshold string `IN ('all','majority','window_optional')`.
- **`_can_sign_gate` (terminador `ELSE false`):** adicionar WHEN explícito p/ os 2 novos kinds — `partner_consultation` = mesmo predicado de `president_others` (capítulos CE/DF/MG/RS + chapter_board + legal_signer; o "não-bloqueante" vive em `_gate_threshold_met`, não aqui); `committee_majority` = stub `false` até §7.1 resolver o roster, OU predicado de designação. **Conflito de pureza (#654) resolvido:** o denominador/roster da maioria é lido do **snapshot** (`gate_state`) DENTRO de `_gate_threshold_met`, NUNCA tornando `_can_sign_gate` chain-state-aware.
- **Schema do `gate_state`:** `ALTER TABLE approval_chains ADD COLUMN gate_state jsonb DEFAULT '{}'` com shape `{<gate_kind>: {eligible_from timestamptz, eligible_snapshot int, committee_roster_ids uuid[], window_closes_at timestamptz, auto_closed_at timestamptz}}`. O RPC que abre/avança a chain escreve `eligible_from`+`eligible_snapshot`+`committee_roster_ids` quando o gate fica elegível; o cron escreve `auto_closed_at`.
- **`committee_majority` determinístico:** `count(signoffs WHERE signer_id = ANY(roster)) > floor(array_length(roster)/2)`; roster pinado na abertura (não live `_can_sign_gate` — senão encolhe mid-flight se um membro sair de função). Roster vazio na abertura → exceção (quórum, §7.1).
- **`partner_consultation` threshold = `'window_optional'`:** em `_gate_threshold_met` → TRUE quando `gate_state.auto_closed_at IS NOT NULL` (janela expirou) OU `count(signoffs)>=eligible_snapshot`.
- **`_enqueue_gate_notifications`:** CASE PT-BR p/ os 2 kinds (committee_majority: "Deliberação do Comitê de Curadoria"; partner_consultation: "Manifestação consultiva do capítulo — sem caráter de veto, prazo 15 dias úteis").
- **In-flight:** auditar se há chain de `policy` em `review` com o template antigo (`president_others` threshold 4) antes de trocar `resolve_default_gates('policy')`; a troca só afeta chains NOVAS (gates já commitados não mudam retroativamente).

### 9.5 PR-4 (re-aceite) — correções legais críticas
- **Ancoragem da janela (Termo 15.3(a)+(b)):** `window_opens_at = effective_from` (= `notified_at + 30 corridos`); `window_closes_at = add_business_days(effective_from, 15)`; `suspended_until = window_closes_at + INTERVAL '30 days'`. **NUNCA** ancorar em `notified_at` (encerraria a janela antes da vigência — cláusula mais restritiva que o contrato, aceite contestável).
- **Transição faltante:** cron faz `notified → in_window` em `effective_from` (sem ela, `in_window` nunca é alcançado).
- **Colunas de deadline = computadas em RPC** (não `DEFAULT` cross-column — proibido em PG; não `GENERATED` — `add_business_days` é STABLE): `open_reacceptance_obligations` insere `window_*`/`suspended_until` explícitos; `register_reacceptance_objection` insere `committee_due_at`; `respond_reacceptance_objection` seta `accommodation_window_closes_at`.
- **FK circular:** CREATE `reacceptance_objections` primeiro (FK `obligation_id` DEFERRABLE INITIALLY DEFERRED) ou `ALTER TABLE … ADD COLUMN objection_id` depois. Não há ordem ingênua que funcione.
- **Desligamento NÃO via `offboard_member`:** o shim `offboard_member(uuid,text,text,date)` **hardcoda `reason_category='administrative'`** (mig 20260424030000) e ambos os offboards exigem `auth.uid()` (cron não tem JWT). Criar `_reacceptance_disengage(p_member_id, p_reason_category, p_preserve_licenses bool)` SECDEF **sem** guard de `auth.uid()`, chamável por cron e por `refuse_reacceptance`; REVOKE FROM PUBLIC.
- **Novo código de categoria:** `INSERT INTO offboard_reason_categories (code,label,description) VALUES ('reacceptance_refusal', 'Recusa de re-aceite', 'Termo 15.3(e); licenças preservadas per 15.4.5.')` — confirmado AUSENTE (0 linhas).
- **Fan-out (GR-1 / leak #648/#653):** `open_reacceptance_obligations` cria obrigação SÓ p/ membros com `EXISTS (member_document_signatures WHERE member_id=m.id AND document_id=p_document_id AND is_current=true)` — **NUNCA** `members.is_active` (pegaria guests pré-onboarding). Critério de aceite: membro sem signature atual NÃO recebe obrigação.
- **'Suspenso' SSOT = `obligation.state`**, sem espelhar em `engagements.status='suspended'` (já usado pelo cron de expiração ⇒ conflito); o gate de acesso durante a suspensão lê a tabela de obrigação via helper RLS.
- **Acomodação (15.4.3(c)) expiry:** se não re-aceitou em 5 úteis → volta a `suspended` com clock retomado (`remaining = suspended_until_original − committee_responded_at`; se ≤0 → `lapsed_disengaged`).
- **accept→recirculate (15.4.3(a)):** **supersede** a obligation atual + abre **nova** (novo `effective_from`/aviso-30d/janela-15-úteis), reiniciando 15.3.
- **`reacceptance_objections.recirculated_chain_id`** FK → `approval_chains(id)` `ON DELETE SET NULL`.
- **Race em `window_closes_at`:** `express_reacceptance` e o cron usam `SELECT ... FOR UPDATE` (advisory lock) na obligation.
- **Editorial change (15d ciência, Política 12.3/Termo 15.2):** mecanismo de **notificação de ciência** (sem abrir obrigação) — atribuir a PR-4 como caminho separado do material; o cron de obrigação só trata material.
- **Feriados de parceiros:** `br_holidays.scope` deve cobrir CE/DF/MG/RS p/ os 15 úteis consultivos (PR-3) e re-aceite (PR-4) de voluntários desses estados; senão documentar a aproximação "calendário GO" como limitação conhecida.

### 9.6 PR-5 (versão regente por obra)
- **Termo regente correto (tie-break 15.4.6):** buscar a signature do autor vigente **à data da 1ª contribuição material**, não `is_current` no momento do stamp: `SELECT signed_version_id FROM member_document_signatures WHERE member_id=<autor> AND document_id=<termo> AND created_at <= first_material_contribution_at ORDER BY created_at DESC LIMIT 1`. Sem signature prévia → `governing_termo_version_id = NULL` + `requires_legal_review=true` (não falhar silenciosamente).
- **Dormancy enforçada por DB:** `governing_termo_version_id`/`governing_politica_version_id` `NOT NULL` na DDL + `stamp_work_governing_version` faz `IF (SELECT current_ratified_version_id FROM governance_documents WHERE doc_type='policy') IS NULL THEN RAISE` (impede congelar NULLs antes do v2.7 ratificar).
- **work_type:** REMOVER `publication_submission` (1:1 com `content_product` → double-stamp; `content_product` é a âncora canônica). Manter `content_product, tribe_deliverable, event_showcase, public_publication, knowledge_asset` (`knowledge_assets` **confirmado existe** ao vivo).
- **Trigger imutável escrito do zero:** bloqueia toda mutação EXCETO `superseded_by_id` (`pi_exclusion_assets` NÃO tem trigger imutável — corrigir a referência de §5 PR-5; só serve de template p/ sha256/OpenTimestamps, não p/ write-once).
- **RLS polimórfica:** helper `_work_initiative_id(work_type, work_id) returns uuid` (CASE por tipo) → policy chama `rls_can_see_initiative(_work_initiative_id(...))` (ADR-0105). Uma USING clause única não alcança o initiative_id dos 5 tipos.
- **Forward-compat Q5 (§7):** se a versão regente vier a ser **por-autor**, a chave `UNIQUE(work_type, work_id)` quebra. Adicionar `author_member_id uuid REFERENCES members(id)` nullable **agora** p/ poder entrar na chave sem migration de coluna depois.

### 9.7 Itens que permanecem abertos (não-bloqueantes; resolver no PR respectivo)
- §7.1 composição/quórum do Comitê (bloqueia PR-3 **go-live**, não o schema — usar stub `false`).
- Acordos bilaterais sob Material change da Política: presidentes re-assinam o Acordo ou a remissão absorve? (interpretação dos 4 acordos ativos — legal).
- Número exato da subcláusula do reorg +60d no Termo v2.7 (corpo menciona "60 dias"; confirmar nº).
