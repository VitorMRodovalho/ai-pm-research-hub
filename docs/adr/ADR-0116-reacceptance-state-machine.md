# ADR-0116 — Máquina de estados de re-aceite de Material change (#976, PR-4 de #571)

**Status:** Accepted (2026-06-30, #976 — PR-4 da Camada 5 / #571)
**Relacionado:** ADR-0016 (IP ratification, gates-as-data — família legal-ops) · ADR-0113 (PR-1: `change_class` + calendário BR — usado p/ a janela em dias úteis) · ADR-0114 (PR-2: version-pin) · ADR-0115 (PR-3: cadeia de ratificação material) · ADR-0102 (GR-1 visibility≠actionability) · ADR-0105 (#785 confidencial) · ADR-0013 (auditabilidade no grão do alvo) · `docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md` §5 PR-4 + §9.5.
**Migration:** `20260805000304_976_pr4_camada5_reacceptance_state_machine.sql`.
**Gate de go-live:** #334 (G12 DPO/ANPD) + PM-OK + ratificação do Termo/Política v2.7.

## Contexto

A frente **WA1** da Camada 5 (Política **12.2.1**; Termo **15.3, 15.4.3, 15.4.4, 15.4.5**) exige que, quando um instrumento binding sofre uma **Material change**, o sistema dirija de ponta a ponta o ciclo **aviso-30d (corridos) → janela de re-aceite de 15 dias úteis → suspensão de +30d (corridos) → desligamento**, admitindo **objeção fundamentada** (15.4.3) e **recusa expressa** (15.3(e)), e **preservando as licenças de PI já concedidas** mesmo no desligamento (15.4.5).

O estado vivo não tinha onde um status de re-aceite viver: `member_document_signatures` só registra aceite **concluído**; não havia obrigação, janela, deadline nem enum de estado; o único terminal (`admin_offboard_member`) é one-way e **exige `auth.uid()`** (inviável por cron). O `engagements.status='suspended'` **já é usado** pelo cron de expiração (jobid 18), então não pode ser reusado como SSOT do "suspenso" do re-aceite.

## Decisão

**1. Duas tabelas; SSOT do "suspenso" em `obligation.state`.**

`member_reacceptance_obligations` (máquina de estados por `(membro, documento, versão-material)`) + `reacceptance_objections` (objeção 15.4.3). FK circular resolvida por `ALTER ADD objection_id` após ambas existirem. RLS member-scoped (leitura do próprio + admin `manage_member`); escritas **só** via RPCs SECDEF (sem policy de DML ⇒ default-deny p/ PostgREST). **O estado "suspenso" do re-aceite vive em `obligation.state='suspended'`, NUNCA espelhado em `engagements.status`** (que já significa "suspenso por expiração" — ambiguidade de discriminação).

**2. Ancoragem de prazos em `effective_from`, nunca em `notified_at` (§9.5 / Termo 15.3(a)+(b)).**

`effective_from = notified_at + 30 corridos` (vigência) · `window_opens_at = effective_from` · `window_closes_at = add_business_days(effective_from, 15)` · `suspended_until = window_closes_at + 30 corridos`. Ancorar em `notified_at` encerraria a janela **antes da vigência** — cláusula mais restritiva que o contrato. Como `add_business_days` é **STABLE** (não IMMUTABLE), as colunas de deadline são **computadas em RPC no INSERT**, nunca em `DEFAULT`/`GENERATED`.

**3. `_reacceptance_disengage` — desligamento SEM `auth.uid()`.**

Novo SECDEF (REVOKE PUBLIC/anon/authenticated), chamável por cron e por `refuse_reacceptance`. **NÃO** é o shim `offboard_member` (que hardcoda `reason_category='other'` e exige JWT). Replica a mecânica de `admin_offboard_member` (member_status→`inactive` reversível, role→`none`, engagements→`offboarded`, skip do step `volunteer_term`) **sem** o gate de auth, e **nunca toca `member_document_signatures`** (licenças preservadas, 15.4.5). `p_preserve_licenses=false` é rejeitado (preservação é incondicional por 15.4.5). Notifica o titular da decisão adversa no momento em que ocorre.

**4. RPCs do ciclo.**

- `open_reacceptance_obligations(doc, to_version, dry_run=true)` — **OUTWARD-gated** (`manage_platform`), só p/ `change_class='material'` (editorial/`NULL` ⇒ nenhuma obrigação, aceite tácito 15.4.4). **Fan-out por `member_document_signatures.is_current=true`, NUNCA `members.is_active`** (não pega guests pré-onboarding — superfície do leak #648/#653 / GR-1). `dry_run=true` por DEFAULT.
- `express_reacceptance` — INSERT no ledger (auto-supersede via `trg_member_doc_sig_supersede_previous`), permitido em `in_window`/`suspended` (tardio 15.3(c))/`accommodation_window`; `FOR UPDATE`.
- `register_reacceptance_objection` — congela a cascata (`objection_pending`); `committee_due_at = add_business_days(now, 10)`.
- `respond_reacceptance_objection` — gate `manage_platform` (placeholder até §7.1): **accepted** → `superseded` + recirculação manual do GP (15.4.3(a)); **rejected** → retoma a cascata com prazos **estendidos pelo período de deliberação** (pausa-e-retoma); **accommodation** → janela de 5 úteis (15.4.3(c)).
- `refuse_reacceptance` — recusa expressa (15.3(e)): desligamento imediato, independente da cascata; resolve a objeção pendente se houver.
- `link_reacceptance_recirculation` — fecha a trilha `recirculated_chain_id` após o GP recircular um instrumento de objeção acolhida.
- `notify_editorial_change_awareness` — caminho de **ciência** (15d, Política 12.3 / Termo 15.2) p/ editorial, **sem** abrir obrigação.
- `get_my_reacceptance_obligations` — leitura member-scoped p/ a UI (banner/countdown).

**5. Cron `reacceptance-lifecycle-sweep-daily` (jobid 74, 07:15 UTC).**

Idempotente: `notified→in_window` (em `effective_from`) · `in_window→suspended` (em `window_closes_at`) · `suspended→lapsed_disengaged` (em `suspended_until`, via `_reacceptance_disengage`) · expiração de acomodação → retoma a suspensão com **clock recalculado** (§9.5: `accommodation_window_closes_at + (suspended_until_orig − committee_responded_at)`) ou lapse · log idempotente de objeção vencida (SLA 10 úteis do Comitê) p/ o dashboard do GP. **`objection_pending` nunca avança** (cascata congelada por design). `FOR UPDATE` nas linhas que disparam desligamento.

**6. Preservação de licença (15.4.5) — Opção B + visibilidade ao DPO.**

Guard nas crons de anonimização que tocam membros — `anonymize_by_engagement_kind` (jobid 17) e `anonymize_inactive_members` (jobid 15): pulam quem detém `member_document_signatures.is_current=true`. `anonymize_premember_applications` (jobid 71) **não** recebe guard (pré-membros não têm ledger). O skip é **in-loop com audit** `lgpd.anonymization_deferred_ip_license` ⇒ o DPO tem visibilidade; requisições **LGPD Art. 18(IV)** de titulares com licença viva roteiam ao DPO (tradeoff Art. 16(I) base de retenção por licença × Art. 18(IV) apagamento) — **não** processadas automaticamente.

**7. Categorias de saída.** `reacceptance_refusal` (15.3(e)) + `reacceptance_lapse` (15.3(c)/(d)) em `offboard_reason_categories` (`is_volunteer_fault=false`, `preserves_return_eligibility=true`).

## Dormência e go-live (build-ahead)

- **Behavior-neutral no apply:** nada dispara sozinho. `open_reacceptance_obligations(dry_run=false)` é a única superfície de fan-out e é **OUTWARD-gated #334 + PM-OK**; com `member_document_signatures = 0` ao vivo, o alvo é vazio. O cron diário varre uma tabela vazia (no-op).
- **UI adiada ao go-live** (decisão PM 2026-06-30): só backend + `get_my_reacceptance_obligations` nesta PR. O banner/objeção/i18n entram quando #334 ungatea e a revisão GR-1 importa de fato (mesmo padrão das PR-2/PR-3, dormentes).
- **`check_schema_invariants()` = 41 (0 violações).** Esta PR **não** adiciona invariante — a preservação de licença é coberta por contract test (`tests/contracts/976-pr4-camada5-reaceite.test.mjs`).

## Correções da revisão adversarial (4 lentes, `wf_e3135226-e45`, ANTES do apply)

Todas as 4 lentes (legal / data-arch / security / senior-eng) deram `APPLY_AFTER_FIXES`; o "BLOCKER" da data-arch (nullability dos FKs do ledger) foi re-verificado ao vivo como **falso-positivo** (os 3 FK são nullable). Incorporados antes do apply:

- **HIGH (legal+senior-eng):** clock de acomodação recalculado por §9.5 (a acomodação é uma **pausa**; sem isto o membro perdia 5 úteis) — **verificado no smoke** (`suspended_until` estendido pelos dias da pausa).
- **HIGH (data-arch+security):** notificação de objeção rejeitada reflete o estado **real** retomado (nunca aponta data passada como prazo ativo; nunca mensageia um membro já desligado).
- **HIGH (legal):** aceite de objeção **não** recircula automaticamente — texto corrigido + audit `action_required_by_gp` + RPC `link_reacceptance_recirculation` p/ fechar a trilha `recirculated_chain_id`.
- **HIGH (legal):** guard de licença com **visibilidade ao DPO** (audit `lgpd.anonymization_deferred_ip_license`) + roteamento Art.18 ao DPO documentado.
- **MEDIUM:** `_reacceptance_disengage` RAISE (não soft-return) em member-not-found (callers PERFORM abortam a transição em vez de marcar terminal silenciosamente); `notify_editorial_change_awareness` ganha guard de `locked_at`; `refuse_reacceptance` resolve a objeção órfã; notificação de desligamento no `_reacceptance_disengage`; cron log de SLA do Comitê vencido.
- **LOW:** estado morto `pending_notification` removido; `express_reacceptance` com NULLs explícitos nos FK; `open` distingue net-new × duplicados; `get_my` conta dias úteis da acomodação; comment de `notified_at` (aviso efetivo vs entrega de email); `p_preserve_licenses=false` rejeitado.

## Itens abertos (go-live — não bloqueiam o backbone dormente)

1. **§7.1** composição/quórum do "Comitê de Curadoria" — o gate de `respond_reacceptance_objection` usa `manage_platform` como placeholder.
2. **Minimização proporcional (PR futuro):** ao preservar a licença, anonimizar campos PII não essenciais à autoria (telefone, endereço, data de nascimento), mantendo só `name` + o row do ledger (LGPD Art. 6º III). Hoje latente (`member_document_signatures = 0`).
3. **UI** (banner/objeção/recusa + i18n 3 línguas) + emenda dos seeds (cláusula Art.8-A / 15.3) no go-live.
4. **Feriados de parceiros** (CE/DF/MG/RS): a janela usa o calendário GO/sede (limitação conhecida, herdada de PR-1).
