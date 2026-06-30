# ADR-0117 — Audit-trail por obra + versão regente (#977, PR-5 de #571)

**Status:** Accepted (2026-06-30, #977 — PR-5 da Camada 5 / #571 — **último slice**; #571 fecha após)
**Relacionado:** ADR-0016 (IP ratification, gates-as-data — família legal-ops) · ADR-0113 (PR-1: `change_class` + calendário BR) · ADR-0114 (PR-2: version-pin) · ADR-0115 (PR-3: cadeia de ratificação material) · ADR-0116 (PR-4: máquina de re-aceite) · ADR-0105 (#785 confidencial — gate `rls_can_see_initiative`) · ADR-0013 (auditabilidade no grão do alvo) · `docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md` §5 PR-5 + §9.6.
**Migration:** `20260805000305_977_pr5_camada5_work_governing_version.sql`.
**Gate de go-live:** ratificação da Política/Termo v2.7 (a Política precisa de `current_ratified_version_id` ≠ NULL — hoje NULL ⇒ dormente).

## Contexto

A frente **WA4** da Camada 5 (Termo **15.4.1** regra + **15.4.7** ledger + **15.4.6** tie-break) exige fixar, por **obra**, a versão regente (Política + Termo) sob a qual ela foi constituída, ancorada na **1ª contribuição material**, como **registro imutável** de auditoria — para que uma mudança material *posterior* dos instrumentos não altere o regime jurídico de uma obra já criada.

O estado vivo não tinha onde esse stamp viver: `first_ratified_version_id` existe só no grão **documento**; "obra" abrange ≥5 tabelas (`content_products` 37, `tribe_deliverables` 71, `event_showcases` 25, `public_publications` 7, `knowledge_assets` 1) sem entidade canônica unificadora; e a fonte runtime ainda está vazia (`current_ratified_version_id` da Política = NULL; `member_document_signatures` = 0) — um stamp hoje **congelaria NULLs**. **Opção A** (Adendo Retificativo consolidado no Termo, decisão PM 2026-06-29) ⇒ **um** `governing_termo_version_id`, sem composto e sem `NULL` ambíguo.

## Decisão

**1. Uma tabela polimórfica `work_governing_version`; `UNIQUE` parcial = 1 stamp ATIVO por obra.**

`(work_type, work_id)` polimórfico (sem FK em `work_id`; integridade via RPC + contract test). `work_type ∈ {content_product, tribe_deliverable, event_showcase, public_publication, knowledge_asset}` — **`publication_submission` REMOVIDO** (1:1 com `content_product` via `content_product_id NOT NULL` ⇒ double-stamp, §9.6). `CREATE UNIQUE INDEX … WHERE superseded_by_id IS NULL` garante um stamp ativo por obra; `author_member_id` nullable **agora** p/ forward-compat da Q5 (regência por-autor — a chave viraria `(work_type, work_id, author_member_id)` sem migration de coluna).

**2. Dormancy enforçada por DB + reconciliação da contradição §9.6 (D1).**

§9.6/#977 dizem **ambos** `governing_*_version_id` "NOT NULL" **e** "sem assinatura prévia ⇒ `governing_termo_version_id=NULL` + `requires_legal_review=true`" — auto-contraditório. Resolução (adjudicada pela revisão adversarial 4-lentes, **todas concordam**):
- **`governing_politica_version_id NOT NULL`** — é o **gate de dormancy**, não constraint violável: `stamp_work_governing_version` faz `RAISE` (`SQLSTATE 55000`) enquanto a Política ativa tiver `current_ratified_version_id IS NULL` ⇒ nenhuma linha pode existir com Política NULL.
- **`governing_termo_version_id NULLABLE`** — a assinatura por-autor pode **genuinamente faltar** (co-autor convidado, obra anterior à adesão; `member_document_signatures = 0` hoje). NULL + `requires_legal_review=true` defere ao DPO (tie-break 15.4.6) em vez de **fabricar uma relação contratual inexistente** (registro probatório falso, Lei 9.610/98). `NOT NULL` aqui bloquearia o stamp das 37+ obras pré-existentes.

A dormancy é ainda mais robusta com um **count-guard determinístico**: `stamp` exige exatamente 1 doc `policy` com `status <> 'superseded'` (multi-doc é padrão vivo — há 2 `volunteer_term_template`) ⇒ sem `LIMIT 1` ambíguo que pudesse pegar um draft (trava permanente) ou um doc forjado (bypass).

**3. Termo regente = tie-break 15.4.6, não `is_current` no stamp-time.**

A assinatura do autor **vigente à data da 1ª contribuição material**: `signed_version_id` de `member_document_signatures` do autor com `COALESCE(signed_at, created_at) <= first_material_contribution_at ORDER BY … DESC LIMIT 1` (o **ato de assinar**, não o insert da linha). Resolve por `doc_type='volunteer_term_template'` via JOIN (há 2 docs — o autor pode ter assinado qualquer um), nunca por id hardcoded. A âncora `first_material_contribution_at` default = `work.created_at` (Q4); **`RAISE`** quando ambos `created_at` e o param são NULL (não silenciar p/ `now()`, que produziria tie-break perverso).

**4. `trg_work_governing_version_immutable` — write-once escrito do zero.**

`BEFORE UPDATE OR DELETE`: bloqueia **toda** mutação (incluindo a PK `id`) **exceto** `superseded_by_id` (+ `updated_at`); bloqueia `DELETE`. Correção apenas pela **cadeia `superseded_by_id`** (retificação legal). FK self-ref **`DEFERRABLE INITIALLY DEFERRED` + `ON DELETE RESTRICT`** p/ habilitar a cadeia futura (UPDATE old → INSERT new numa tx sem violar o UNIQUE parcial). `pi_exclusion_assets` **não** tem trigger imutável (§9.6 corrige a referência de §5) — só serve de template sha256/OpenTimestamps. Trigger é **puro** (sem `SECURITY DEFINER` — só compara OLD/NEW + RAISE).

**5. RLS polimórfica (ADR-0105) + reader SECDEF com guard cross-org.**

`_work_initiative_id(work_type, work_id)` (SECDEF STABLE, CASE por tipo: `event_showcase` via `event_id → events.initiative_id`; `knowledge_asset → NULL`) → policies espelham `tribe_deliverables`: **PERMISSIVE** read p/ `authenticated` + **RESTRICTIVE** `AJ_wgv_confidential_visibility` (`rls_can_see_initiative(_work_initiative_id(...))`) + **RESTRICTIVE** `wgv_org_scope` (`organization_id = auth_org() OR organization_id IS NULL`). `get_work_governing_version` (SECDEF) reaplica `rls_can_see_initiative` **e** o tenancy inline (SECDEF bypassa o RESTRICTIVE org-scope ⇒ sem isto vazaria `attribution_text`/nome PII cross-org). `stamp` é `manage_platform` (GP vê confidencial por design; o gate confidencial vive no read-path). Todos os SECDEF: `SET search_path 'public','pg_temp'` + `REVOKE PUBLIC, anon`.

**6. `organization_id` NULLABLE — obra org-agnóstica.**

`knowledge_assets` não tem org nem initiative; o stamp guarda `organization_id = NULL` (não pina na org do *stamper*). NULL-org = universalmente legível (a cláusula `OR organization_id IS NULL` do org-scope é **load-bearing**, não dead code). `event_showcase` resolve a org via `events.organization_id` (`event_showcases` não tem coluna própria — `es.organization_id` seria crash).

**7. Snapshot denormalizado + enquadramento.**

`attribution_text` (FK **+** snapshot p/ durabilidade "preservada independentemente de mudanças posteriores") **bifurca em `requires_legal_review`**: quando o Termo não pôde ser resolvido, o texto declara explicitamente "Termo NÃO verificado — requer revisão jurídica" (nunca afirma um Termo inexistente). `enquadramento jsonb` default derivado (autoral 9.610/1998, com nota de que revisão jurídica pode reclassificar p/ 9.609 software / 9.279 propriedade industrial); overridable por param.

## Dormência e go-live (build-ahead)

- **Behavior-neutral no apply:** `stamp_work_governing_version` faz `RAISE` enquanto a Política não ratificar (`current_ratified_version_id IS NULL` ao vivo). Nenhuma linha é criada (0 rows); nenhum dispatch OUTWARD (não é a superfície do leak #648/#653 — só escreve registro de auditoria). **Verificado no smoke** (DO + RAISE rollback): `dormancy_raised=t sqlstate=55000`, helper resolve initiative corretamente, trigger bloqueia UPDATE/DELETE e permite `superseded_by_id`.
- **`check_schema_invariants()` = 41 (0 violações).** Esta PR **não** adiciona invariante — um invariante "toda obra published tem stamp" falharia já (37+ obras, 0 stamps na dormência). O mecanismo é coberto por contract test (`tests/contracts/977-pr5-camada5-work-governing-version.test.mjs`).

## Correções da revisão adversarial (4 lentes, `wf_408319e9-850`, ANTES do apply) — 12 fixes

Todas as 4 lentes (legal / data-arch / security / senior-eng) deram `APPLY_AFTER_FIXES`; D1 adjudicado (manter Política NOT NULL + Termo NULLABLE). Incorporados antes do apply (2 gates verificados ao vivo: `events.organization_id` existe; `governance_documents.status ∈ {active,draft,under_review}`, 1 doc policy):

- **BLOCKER:** `es.organization_id` não existe → org via `events.organization_id` (M1); trigger imutável protege a PK `id` (M2); FK `superseded_by_id` `DEFERRABLE INITIALLY DEFERRED` + `ON DELETE RESTRICT` (M3).
- **HIGH:** `get_` reaplica tenancy cross-org (SECDEF bypassa o RESTRICTIVE → vazaria nome PII, M4); `attribution_text` bifurca em `requires_review` + embute labels reais (não afirmar Termo inexistente = registro probatório falso, classe vedada no PR-2, M5); dormancy gate determinístico + count-guard (`status <> 'superseded'`, M6).
- **MEDIUM:** tie-break por `signed_at` (ato de assinar) não `created_at` (M7); trigger sem `SECURITY DEFINER` (puro, M8); retorno idempotente inclui `work_type`/`work_id` (M9); remove dead code `v_init` + comenta ausência de gate ADR-0105 no write-path (M10).
- **LOW:** `v_first` RAISE se ambos NULL (não silenciar p/ `now()`, M11); `stamp` guarda cross-org (M12).
- **Rejeitado (R1):** `OR organization_id IS NULL` **não** é dead code — é load-bearing sob a decisão M0 (org NULLABLE).

## Itens abertos (go-live — não bloqueiam o backbone dormente)

1. **§7 Q5** — governing Termo **por-autor vs por-obra** em obras multi-autor (co-autores podem ter assinado versões diferentes). Coluna `author_member_id` já prevista p/ entrar na chave `UNIQUE` sem migration de coluna.
2. **§7 Q4** — o que conta como "1ª contribuição material" (default = `created_at`; ruling jurídico pode escolher first-drafted/first-author).
3. **RPC de retificação/supersede** (cadeia `superseded_by_id`) — fora de escopo do PR-5; a tabela já está desenhada p/ ele (FK deferível + trigger permite o campo).
4. **Backfill dos 37+ stamps** — só após v2.7 ratificar (a Política precisa de `current_ratified_version_id`); obras cujo autor não assinou ainda receberão `requires_legal_review=true`.
