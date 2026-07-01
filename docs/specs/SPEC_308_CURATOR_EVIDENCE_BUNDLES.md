# SPEC — #308 Curator Contribution Evidence Bundles & Bilingual Verifiable Declarations

> **Status:** Draft de planejamento aprovado para decomposição. Deliverable de #308 = **arquitetura, não código** (issue `type:task`, planning). Decisões de modelagem do PM **RESOLVIDAS** (AskUserQuestion 2026-06-30) — ver §1.3.
>
> **Data:** 2026-06-30
>
> **Origem:** Issue #308 (`governance: curator contribution evidence bundles and bilingual certificates`). PM framing: capacidade **institucional** (não aconselhamento jurídico/imigratório individual) de dar lastro verificável de **função exercida** e **ações realizadas** por membros/curadores, com rastreabilidade e saída bilíngue PT-BR / EN-US.
>
> **Método:** Workflow ultracode `wf_8f991faa-ec0` — design 4-lentes (data-architect · legal-counsel · security-engineer · product-leader) → síntese opus → **revisão adversarial 3-céticos** (senior-eng · security · legal) que leu as migrations ao vivo e produziu **6 blockers + 12 high + 12 medium + 7 low**. Grounding re-verificado ao vivo em prod `ldrfrvwhxsmgaabwmaik` (2 claims adversariais eram *stale* — ver §0.2).
>
> **ADR:** **ADR-0119** (novo) — relaciona ADR-0098/0099/0101/0102/0105/0108/0117, cumpre ADR-0099 §2.9 (evidence-anchoring diferido da Wave 6).
>
> **Escopo-irmão:** **#311** (OPEN) = modelo genérico de evidence-bundle p/ **todos** os papéis/tiers. #308 define o modelo **curador/revisão-de-artigo** que #311 generaliza. `member_contribution_evidence` é o agregador curation-scoped que #311 envolve.

---

## 0. Correção de grounding (LEIA ANTES)

### 0.1 Estado atual (queries ao vivo, prod, 2026-06-30)

| Objeto | Fato aterrado | Implicação |
|---|---|---|
| `certificates` | **46 linhas**; tipos `volunteer_agreement=41`, `alumni_recognition=4`, `contribution=1`; **todas pt-BR**; todas com `function_role`; colunas `content_snapshot jsonb`, `verification_code`, `signature_hash`, `counter_signed_by/at`, `counter_signature_hash`, `period_start/end`, `template_id`, `pdf_url`; ADR-0098 autogen PDF via trigger. #181 counter-sign landou como **colunas** (não tabela). | **O gap NÃO é o primitivo de certificado.** É a camada upstream: congelar versão + agregar + snapshot bilíngue. |
| `curation_review_log` | **0 linhas** (fluxo p197 wired + contract-tested #194, zero dado de produção); colunas `board_item_id`, `curator_id`, `criteria_scores jsonb`, `feedback_notes`, `decision`, `review_round`, `metadata`, `completed_at`; **keyed só a `board_item_id`** — sem referência a versão/snapshot. | Camada desenhada **à frente dos dados** → decomposição enxuta (§8). Gap 1 confirmado. |
| `board_item_files` | **22 linhas**; `drive_file_id`, `drive_file_url`, `filename`, `mime_type`, `size_bytes`; **sem `revision_id`, sem hash**. | Gap 1: semântica de versão fraca. |
| `board_lifecycle_events` | **1928 linhas**; CHECK ampliado p/ 37 ações (#300). | Trilha operacional (agregada, não congelada). |
| `content_products` | **37 linhas** (ADR-0099, superfície canônica da "obra"); todas `source_kind='external'`; status `under_review=31`/`published=6`. | Bundle **referencia** (FK), nunca duplica. |
| `publication_submissions` | **37 linhas**; `content_product_id NOT NULL`. | Elo obra→submissão. |
| `engagements` | **198 linhas** (V4, ADR-0006). `can()`/`can_by_member()` = autoridade (ADR-0007); `operational_role` é **cache**. | Gap 4: função-no-período vem de `engagements`, nunca do cache. |
| `member_document_signatures` | **0 linhas** (sign-path Camada 5 dormente). | Elo de assinatura indisponível hoje. |
| `document_versions` / `governance_documents` | 52 / 19 linhas. `work_governing_version` (ADR-0117) = versão regente da obra. | |
| `manual_sections` | trilíngue (`title/content_pt/en/es`), versionado (`manual_version` R3), hierárquico, `approved_by ARRAY`; seções relevantes: **§3.6** Comitê de Curadoria, **§3.9** Reconhecimento de Contribuições e Registro Institucional, **§4** Processos, **§5** Qualidade/Ética/Conformidade. | Alvo do critério 3 (trigger de revisão do Manual). |

### 0.2 Correções de claims adversariais (re-aterradas ao vivo — migrations tinham drift)

A revisão adversarial leu **arquivos de migration**; duas claims não batem com o corpo **vivo**:

1. **`get_all_certificates` NÃO vaza `content_snapshot`** (a claim de "leak de content_snapshot" da síntese estava *stale*). **PORÉM** a função **É anon-executável ao vivo** (`has_function_privilege` = `anon,authenticated,service_role`) — SECDEF sobre a tabela inteira de certificados (46 linhas, join com PII). Item real do PR-0 = **`REVOKE EXECUTE … FROM anon`** (classe #965), **não** strip de coluna.
2. **`submit_curation_review` NÃO usa mais `operational_role`** ao vivo (`uses_operational_role_cache = false`) — a claim adversarial vinha da migration `20260316140000` (corpo desde então atualizado). **Logo o item "swap operational_role → can_by_member em submit_curation_review" SAI do PR-0.** As chaves de `criteria_scores` estão confirmadas ao vivo: `ARRAY['clarity','originality','adherence','relevance','ethics']`, valores 1-5.

Reais e vivos (confirmados):
- `curation_review_log` tem policy **`curation_review_log_read` com `USING(true)`** (+ `curation_review_log_v4_org_scope` ALL). Dívida latente (0 linhas hoje, mas furo assim que houver dado).
- `verify_certificate` (anon) **resolve `counter_signed_by` → NOME de membro** (`SELECT name INTO v_countersigner_name FROM members WHERE id = cert.counter_signed_by`) e menciona `issued_by` — **leak de PII de terceiro na /verify pública**. Pré-existente; sibling issue (§8).

---

## 1. Objetivo, escopo e decisões

### 1.1 Objetivo

Modelar **a evidência como fonte primária** e **certificados como derivações verificáveis** dela, para responder — **por artigo/artefato** — quem revisou, o que foi revisado, **qual versão**, qual decisão, quais critérios, qual feedback, e **qual declaração pode ser verificada depois**, em PT-BR + EN-US, com postura de privacidade explícita.

### 1.2 Escopo / Fora de escopo

**Dentro (#308):** camada de evidência de **curadoria/revisão de artigo** — snapshot de artefato, envelope de revisão normalizado, bundle por-(artigo, rodada), agregador `member_contribution_evidence`, categoria de certificado **DACO** (ações por obra) + **DFEP** (função exercida, como *documento companheiro*), postura de privacidade em 3 tiers (Tier 1+2 shipados, Tier 3 deferido), bilíngue no snapshot, trigger de revisão do Manual.

**Fora (defere a #311 / follow-up):** modelo genérico de `evidence_bundles` cross-engagement; tiers de certificado multi-ciclo; `get_member_evidence_bundle(p_scope)` unificado; **Tier 3** (link assinado externo — decisão PM Q4); categoria **DPG** (participação genérica — não-curadoria, cabe a #311); ancoragem OTS completa (defere a #569/ADR-0101 Slice 4; #308 provê só o **placeholder estrutural** — ver §11 F-H10).

### 1.3 Decisões de modelagem do PM (AskUserQuestion, 2026-06-30) — RESOLVIDAS

| # | Decisão | Escolha | Consequência |
|---|---|---|---|
| **Q1** Decomposição | **Enxuto: PR-0 + PR-1 agora** | 2 issues de valor imediato + 1 guarda-chuva **#308-B** a abrir quando o 1º ciclo real de curadoria começar. Evita ruído no tracker à frente de `curation_review_log=0`. |
| **Q2** DFEP (função exercida) | **Documento companheiro** | `function_held` cross-referencia `volunteer_agreement.verification_code` via `content_snapshot.basis_volunteer_agreement_code`. Nunca instrumento primário duplicado; valor só p/ público externo (ex.: versão EN). Fecha o conflito de duplo-instrumento (§11 F-H8). |
| **Q3** Nome no /verify Tier 1 | **Omitir o nome** | Nome do curador só aparece quando ele **ativamente** compartilha (Tier 2 auth). Impede colheita anônima de nome+função+período. |
| **Q4** Tier 3 (link externo) | **Fora do #308 (follow-up)** | Tier 1 (/verify) + Tier 2 (self autenticado) já satisfazem os ACs. `certificate_share_tokens` + re-check de confidencialidade + soft-revoke viram issue follow-up. |

---

## 2. Estado atual vs. gaps (grounded)

| Gap (#308) | O que EXISTE | O que FALTA | Onde resolve |
|---|---|---|---|
| **1** snapshot/congelamento de versão | `board_item_files` (22, sem revision/hash); `curation_review_log` keyed só a board_item | Captura imutável por-versão (qual byte-sequence foi revisado) | `curation_artifact_snapshots` (§3.1) — **com `digest_status`** |
| **2** normalização do envelope de revisão | `curation_review_log` (0) tem `criteria_scores`, `feedback_notes`, `decision`, `review_round` | FK `artifact_snapshot_id`; CHECK das 5 chaves numéricas; **colunas de versão regente por-revisão** | `curation_review_log` (§3.1, PR-1) |
| **3** agregação por-artigo | Fragmentado: `board_lifecycle_events` (1928) + `curation_review_log` (0) + `drive_curation_grants` | Envelope determinístico por-(artigo, rodada) com `content_snapshot` congelado imutável | `curation_evidence_bundles` (§3.2, #308-B) |
| **4** função/papel de V4 | `engagements` (198); `can_by_member()` | RPC lendo `engagements` (NÃO `operational_role`); sign-path indisponível (0 linhas) | `member_contribution_evidence` (§3.3, #308-B) |
| **5** cert bilíngue + verificação + snapshot imutável | `certificates` (46, todas pt-BR; snapshot; verification; autogen) | Novos tipos; snapshot bilíngue; hash reproduzível; verify type-aware | Extensões de cert (§3.4/§4, #308-B) |
| **6** superfícies frontend | `/admin/curatorship`, `/certificates` | Registro de snapshot; request/preview/issue/download | #308-B |
| **7** Manual de Governança | Manual §3.6/§3.9/§4/§5 | Cláusulas de registro de evidência, categorias de declaração, bilíngue, imutabilidade | §7 (Camada 5 material) |
| **8** auditoria & privacidade | ADR-0098 /verify metadata-only; ADR-0105 gate confidencial; `pii_access_log` | Field-lists por-tier; verify type-aware; log de GP-lê-outro | §5 |

---

## 3. Modelo proposto

Três tabelas novas + extensões de certificado + RPCs. **Tudo referencia `content_products` por FK; nada duplica** suas colunas (título/status/instrumento são lidos por JOIN no momento da montagem e **congelados** no `content_snapshot`, durável depois).

### 3.1 `curation_artifact_snapshots` (Gap 1) — PR-1

Tabela nova (não extensão de `board_item_files`: um item tem N arquivos; "artefato ausente" é estado válido; revisões retroativas de Drive não se aplicam às 22 linhas atuais). Reusa o **padrão digest-only ADR-0101** (SHA-256, a obra nunca sai do Núcleo).

```sql
CREATE TABLE public.curation_artifact_snapshots (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  initiative_id       uuid,                   -- NULLABLE (grounding #988): board_item.board_id -> project_boards.initiative_id é nullable (2/25 boards org-level; NULL=visível, rls_can_see_initiative(NULL)=TRUE). DENORMALIZADO no capture p/ gate ADR-0105 sem JOIN
  board_item_id       uuid NOT NULL REFERENCES public.board_items(id) ON DELETE RESTRICT,
  board_item_file_id  uuid REFERENCES public.board_item_files(id)  ON DELETE RESTRICT,  -- nullable
  document_version_id uuid REFERENCES public.document_versions(id) ON DELETE RESTRICT,  -- nullable (a FK É a versão, imutável ADR-0113)
  content_product_id  uuid REFERENCES public.content_products(id)  ON DELETE RESTRICT,  -- seam ADR-0099 (nullable)
  file_digest         text,                   -- SHA-256 hex; ver digest_status
  digest_status       text NOT NULL DEFAULT 'pending'
                        CHECK (digest_status IN ('pending','verified','unresolvable')),  -- §11 F-B3/F-B5
  drive_revision_id   text,                   -- INTERNO — jamais surfaceado por RPC nem congelado no snapshot (§11 F-H6)
  version_label       text NOT NULL,
  metadata_snapshot   jsonb,                  -- filename/mime/size denormalizados (sobrevive rename/move)
  review_round        smallint NOT NULL DEFAULT 1 CHECK (review_round >= 1),
  capture_trigger     text NOT NULL DEFAULT 'manual_gp'
                        CHECK (capture_trigger IN ('curation_pending','manual_gp','retroactive')),
  captured_by         uuid REFERENCES public.members(id) ON DELETE RESTRICT,
  snapshot_at         timestamptz NOT NULL DEFAULT now(),
  created_at          timestamptz NOT NULL DEFAULT now()
);
-- idempotência real (§11 F-M-unique):
CREATE UNIQUE INDEX cas_item_file_round ON public.curation_artifact_snapshots(board_item_id, board_item_file_id, review_round)
  WHERE board_item_file_id IS NOT NULL;
CREATE UNIQUE INDEX cas_item_docver_round ON public.curation_artifact_snapshots(board_item_id, document_version_id, review_round)
  WHERE document_version_id IS NOT NULL;
-- NB: governing_version_id NÃO vive aqui (YAGNI §11 F-M-gov) — vive no bundle (uma versão por (artigo,rodada)).
```

**Mecanismo (PR-1, behavior-neutral):** RPC SECDEF **manual** `register_curation_artifact_snapshot(...)` — **sem trigger** (auto-capture com Drive `revisionId` via EF = enhancement go-live diferida; muda comportamento + chamada outbound não roda em trigger). `curation_review_log` ganha `artifact_snapshot_id uuid REFERENCES curation_artifact_snapshots(id) ON DELETE SET NULL` (nullable; 0 linhas = compat grátis). `criteria_scores` ganha CHECK das 5 chaves (§11 F-M-criteria). **Colunas de versão regente por-revisão** (§11 F-M-gov-per-reviewer): `reviewer_governing_politica_version_id uuid`, `reviewer_governing_termo_version_id uuid` (ambas nullable) — gravadas no INSERT do log, congeladas depois no bundle.

`digest_status`: `pending` (aguarda cômputo), `verified` (digest confere com a revisão aberta pelo curador), `unresolvable` (Drive inacessível). **DACO não embute em `artifacts[]` nenhum artefato com `digest_status <> 'verified'`** — lista-os em seção separada "sem âncora criptográfica — sujeito a verificação manual" (§11 F-B3/F-B5). GP-provided-after-the-fact é **proibido** para DACO com pretensão de validade externa.

### 3.2 `curation_evidence_bundles` (Gaps 2+3) — #308-B

Bundle é **por-(artigo, rodada)**, agregando **todos** os revisores/ações (a visão por-membro é o RPC §3.3). **Sem coluna `member_id`.** Revisores via **join table FK-safe** (§11 F-H1), não `uuid[]`.

```sql
CREATE TABLE public.curation_evidence_bundles (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  initiative_id         uuid NOT NULL,        -- denormalizado p/ ADR-0105
  board_item_id         uuid NOT NULL REFERENCES public.board_items(id) ON DELETE RESTRICT,
  content_product_id    uuid REFERENCES public.content_products(id) ON DELETE RESTRICT,   -- REFERÊNCIA, nunca duplica
  governing_version_id  uuid REFERENCES public.document_versions(id) ON DELETE RESTRICT,  -- ADR-0117
  review_round          smallint NOT NULL DEFAULT 1 CHECK (review_round >= 1),
  review_cycle_label    text NOT NULL,
  content_snapshot      jsonb,                -- congelado no finalize; bilíngue; montado por jsonb_build_object allowlist (§11 F-H6)
  final_decision        text CHECK (final_decision IN ('approved','returned_for_revision','rejected')),
  submitted_for_curation_at timestamptz,
  finalized_at          timestamptz,
  finalized_by          uuid REFERENCES public.members(id) ON DELETE RESTRICT,
  status                text NOT NULL DEFAULT 'open' CHECK (status IN ('open','finalized','revoked')),
  revoked_at timestamptz, revoked_by uuid REFERENCES public.members(id), revoke_reason text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ceb_finalized_complete CHECK (
    status <> 'finalized'
    OR (content_snapshot IS NOT NULL AND finalized_at IS NOT NULL
        AND final_decision IS NOT NULL
        AND content_product_id IS NOT NULL))   -- §11 F-M-cp: DACO exige âncora de obra
);
CREATE UNIQUE INDEX ceb_board_item_round ON public.curation_evidence_bundles(board_item_id, review_round);

-- join table FK-safe (autoridade de RLS + evidência de contribuinte) — §11 F-H1
CREATE TABLE public.curation_bundle_reviewers (
  bundle_id   uuid NOT NULL REFERENCES public.curation_evidence_bundles(id) ON DELETE CASCADE,
  member_id   uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  review_role text,
  PRIMARY KEY (bundle_id, member_id)
);
```

**Lock (imutabilidade):** trigger **fresco** `trg_curation_bundle_immutable` — **NÃO** reusar `trg_work_governing_version_immutable` verbatim (checa colunas de OUTRA tabela → seria inerte, §11 F-H2). `BEFORE UPDATE`: se `NEW.status='finalized'` e qualquer de {`content_snapshot`,`final_decision`,`finalized_at`,`finalized_by`,`board_item_id`,`review_round`,`content_product_id`} `IS DISTINCT FROM OLD` → `RAISE … ERRCODE '55000'`; só `revoked_*` mutável.

**Congelamento (`_finalize_evidence_bundle`, PRIVADO):** helper interno (`_` prefixo, `REVOKE EXECUTE FROM PUBLIC,anon,authenticated` — §11 F-B4); **NUNCA endpoint público**. Recebe `final_decision` **como parâmetro** de quem o chama (não re-deriva; §11 F-H3): decisão = espelho da transição terminal de `submit_curation_review` (`approved` quando distinct-approved ≥ required; `rejected` em modo unânime; senão `returned_for_revision`). Bloqueia se `content_products.status='archived'` (§11 F-L-cur003, write-gate não drift-check). Monta `content_snapshot` via **`jsonb_build_object` com allowlist explícita** (proíbe `drive_revision_id`, `captured_by`, `created_at`). O wire-in a `submit_curation_review` é **go-live gated no #308-B**, nunca em PR-1/PR-2 (§11 F-B2).

### 3.3 `member_contribution_evidence(p_member_id, p_period_start, p_period_end)` — #308-B

RPC read SECDEF. Gate `manage_platform OR manage_member OR self`. **Autoridade de `engagements`, não `operational_role`** (Gap 4). Filtro `rls_can_see_initiative` por-artefato (ADR-0105, omissão silenciosa). Loga GP-lê-outro em `admin_audit_log` (LGPD Art.37). Composição sem duplicar `content_products`:
- `roles_held` ← `engagements` (labels via `engagement_kinds`), excluindo cache;
- `curation_reviews` ← `curation_review_log` LEFT JOIN bundles;
- `publication_contributions` ← `content_products WHERE proposer_member_id = p_member_id` (novo índice `content_products(proposer_member_id, created_at)`);
- `evidence_bundles` ← via `curation_bundle_reviewers` WHERE `member_id = p_member_id AND status='finalized'`.

**Blind-review (§11 F-H11/F-M-blind):** em Tier 2, **não** retorna identidades de outros revisores — só `reviewer_count` agregado + a própria contribuição do caller; UUIDs de outros só p/ `manage_platform`.

### 3.4 Extensões de certificado — #308-B

- `type` CHECK: **DROP + re-CREATE** (achar o nome do constraint primeiro, não chutar) += `function_held`, `curation_contribution`. **DPG removido do #308** (§11 F-L-dpg; cabe a #311; `contribution` fica intocado).
- **Bilíngue = UMA linha** (§11 F-L-onerow / decisão PM Q2 bilíngue): `content_snapshot` com sub-objetos `pt_BR`+`en_US`, **um** `verification_code`, **um** `signature_hash`. `p_language` só escolhe a língua primária do PDF; ambas as línguas sempre congeladas. Sem `paired_language_certificate_id`.
- `signature_hash` **definido** p/ novos tipos (§11 F-H9): `SHA-256(content_snapshot::text || member_id::text || issued_at::text || 'nucleo-ia-contrib-salt')`.

### 3.5 Inventário de RPCs

| RPC | Gate | PR | Notas |
|---|---|---|---|
| `register_curation_artifact_snapshot` | `curate_content OR manage_platform` | **PR-1** | manual; `ON CONFLICT DO NOTHING`; REVOKE PUBLIC/anon/authenticated |
| `_finalize_evidence_bundle` | **PRIVADO** (só service_role/postgres) | #308-B | congela snapshot bilíngue; recebe `final_decision` param; REVOKE all |
| `member_contribution_evidence` | `manage_platform OR manage_member OR self` | #308-B | autoridade de `engagements`; blind-review Tier 2; log Art.37 |
| `issue_contribution_certificate` | **`manage_member`** (emissão = lifecycle, NÃO `curate_content`) | #308-B | popula snapshot de `member_contribution_evidence`; ADR-0098 autogena PDF |
| `verify_certificate` (**estendido type-aware**, §11 F-H4) | anon | #308-B | **um** RPC, **uma** rota `/verify`; projeção de campos por `type` |

---

## 4. Categorias de declaração

Duas categorias no #308 (DPG cai). Cada uma mapeia colunas existentes de `certificates`.

| Categoria | `type` | Fonte de verdade | Colunas | Counter-sign | Bilíngue |
|---|---|---|---|---|---|
| **DFEP** — Função Exercida no Período (**documento companheiro**, Q2) | `function_held` | `engagements` (NÃO cache) **+** `content_snapshot.basis_volunteer_agreement_code` (cross-ref ao volunteer_agreement) | `function_role`←engagement; `period_start/end`←datas; `source='platform'` | **Obrigatório** (GP) | traduzido: título/label da função/descrição; sem `artifacts[]` |
| **DACO** — Ações/Contribuições por Obra | `curation_contribution` | `curation_artifact_snapshots` + `curation_review_log` + `content_products` | `content_snapshot` (bilíngue, `artifacts[]`); `verification_code`; `template_id` | **Obrigatório** (GP) | `artifacts[]`: título, `target_instrument`, `review_round`, `version_label`, decisão, `criteria_summary` (narrativo, **nunca scores crus**), `doi_or_url` (só público), `digest_status`, `pi_ots_status` |

**DFEP como documento companheiro (Q2):** nunca instrumento primário. `content_snapshot.basis_volunteer_agreement_code` = o `verification_code` do `volunteer_agreement` pai, tornando a cadeia explícita. Invariante: nenhum `function_held` sem `volunteer_agreement` correspondente (ou flag de waiver) — §11 F-H8.

---

## 5. Privacidade & acesso — 3 tiers

**RLS (todas as tabelas novas): deny-all; leitura só por SECDEF; SEM policy `FOR INSERT/ALL` p/ `authenticated`** (policy de INSERT deixaria curador forjar snapshot). Todo RPC SECDEF segue #965: `REVOKE FROM PUBLIC, anon, authenticated; GRANT TO authenticated`. Bundle RLS = `EXISTS(SELECT 1 FROM curation_bundle_reviewers WHERE bundle_id = id AND member_id = auth_member_id()) OR rls_can('manage_platform')`. Ghost → `member_id NULL` → nada.

- **Tier 1 — PÚBLICO `/verify/{code}` (metadata-only).** `verify_certificate` **estendido type-aware** (um RPC, uma rota — §11 F-H4). Skeleton concreto `jsonb_build_object` (§11 F-H5), para `valid=true`: `{valid, type, title, function_role, period_start, period_end, issued_at, issuing_organization, language, has_counter_signature, counter_signed_at, authorized_by, content_snapshot_hash}` onde `authorized_by="Presidência, Núcleo IA e GP"` (string org) e **`content_snapshot_hash`** = SHA-256 do snapshot sem salt (permite verificador externo conferir a tradução recebida — §11 F-H9). **Bloqueado:** nome do titular (**Q3=omitir**), nome do counter-signer/issuer (§11 F-M-names), `revoked_reason`, `content_snapshot` cru, scores, `feedback_notes`, títulos/autores de artigo, Drive URLs, `signed_ip/user_agent`, `pdf_url`. Não-emitido (não-achado/revogado/rejeitado) → **`{valid:false}` só**, sem discriminante (§11 F-H5). Código: `CURAT-YYYY-<18 hex>` via **`encode(gen_random_bytes(9),'hex')`** (72 bits crypto, pgcrypto; nunca `md5(random())` — §11 F-M-entropy).
- **Tier 2 — AUTENTICADO self.** `member_contribution_evidence(self)` + `get_my_certificates`. Nome próprio, próprio `signed_ip/user_agent` (Art.18 II — **nunca do counter-signer**), próprios scores/notes, lista de artefatos por **digest** (sem Drive URL). Bloqueado: scores/notes de outros revisores do mesmo artefato (blind-review); identidades de outros revisores (§11 F-H11).
- **Tier 3 — link assinado externo.** **FORA do #308 (Q4)** → follow-up. Quando shipar: `certificate_share_tokens` (token = `gen_random_uuid()` bare, tabela separada, jamais derivado de bundle_id) + `get_shared_evidence_bundle` **re-checando `rls_can_see_initiative` a CADA resgate** + soft-revoke ao virar confidencial (§11 F-M-tier3).

**Carve-out confidencial (ADR-0105, NÃO-NEGOCIÁVEL, verbatim no ADR):** todo RPC SECDEF lendo `curation_artifact_snapshots`, `curation_evidence_bundles`, `curation_review_log`, `board_item_files` ou `board_items` **DEVE** aplicar `rls_can_see_initiative(initiative_id)` e **omitir silenciosamente** linhas confidenciais (sem placeholder redigido, sem revelar contagem). O `initiative_id` denormalizado existe p/ manter o filtro sem JOIN.

**LGPD:** `export_my_data` (#568) **deve** ser estendido p/ incluir os bundles (Art.18 V) — **child issue bloqueante do go-live de emissão** (§11 F-L-lgpd), não diferível indefinidamente. Cron de anonimização 5y **deve** cobrir `captured_by`, `finalized_by` e os `member_id` em `curation_bundle_reviewers` (curator_id → hash, Art.18 VI, nunca hard-delete de registro institucional de revisão). Nome de terceiro (autor não-membro) **excluído** até publicação; DOI basta depois (Art.6 III; Lei 9.610 Art.27/29 — declarar **a ação de revisão**, nunca autoria/qualidade da obra).

---

## 6. Bilíngue (nível template / content_snapshot)

Bilíngue **assado na emissão, nunca traduzido post-hoc** (AC 6). `issue_contribution_certificate` aceita `p_language` e congela **ambas** as variantes no `content_snapshot` no INSERT. Verbatim (nomes, IDs, códigos, datas, DOIs) idêntico entre línguas; traduzidos (títulos, labels de função, decisões, `criteria_summary`) em `pt_BR` e `en_US`. Labels de enum via dicionários `/src/i18n/`. `criteria_summary` pode ser AI-draft (`ai_draft:true`) mas exige revisão GP antes do counter-sign — **com guardas estruturais anti-PII** (§11 F-M-aidraft). Se EN-US indisponível na emissão → emissão **bloqueada** (nada de cert meio-bilíngue) OU emite pt-BR-only marcando EN diferido (decisão de implementação #308-B). Invariante `CUR_004` exige ambas as chaves.

---

## 7. Trigger de revisão do Manual (critério 3)

Emitir declaração = mudança `change_class='material'` → as emendas roteiam por **Camada 5 (ADR-0113/0115)** antes de vigorar. **Dividir em DOIS approval-chains** (§11 F-H12):

- **Chain 1 (procedural, `material`):** §3.6/§4 (Curadoria) **§4.X — Registro de Evidência de Curadoria** (na atribuição/entrada em `curation_pending`, snapshot imutável: file id, SHA-256 quando disponível, rodada, metadados; base probatória do DACO; substituição de arquivo → novo snapshot em nova rodada); **§3.9/§5 (Certificados e Declarações)** §5.1 categorias DFEP/DACO + fontes; §5.2 DFEP+DACO exigem counter-sign GP antes de emissão externa; §5.3 toda declaração em PT-BR+EN-US, trava na emissão, sem tradução posterior; §5.4 `/verify` = metadata mínimo, conteúdo completo só ao titular; §5.5 declaração emitida+counter-signed é imutável — correção = revogar+reemitir com referência, histórico retido (Art.37); **§6.X (PI)** para obras no registro de exclusão-PI (ADR-0101), digest OTS-confirmado é evidência de anterioridade que o DACO pode referenciar.
- **Chain 2 (substantivo — exige advogado licenciado ANTES do chain):** **§7.X (Mudança de Controle)** — mudanças materiais de critério/processo de curadoria **não retroagem** sobre DACOs já emitidos; o snapshot imutável registra a versão do Manual vigente na emissão. Cláusula de não-retroatividade num documento auto-emendável tem peso legal próprio; não pode ser assinada no mesmo evento que procedimentos operacionais.

---

## 8. Decomposição (enxuta — decisão PM Q1)

**Fundação behavior-neutral = PR-0, PR-1.** Resto colapsado em **#308-B**, a abrir quando o 1º ciclo real de curadoria começar (padrão Camada 5 dormant-until-data, mas sem criar 4-5 issues paradas à frente de `curation_review_log=0`).

| Issue | Título | Escopo | Comportamento | Aceite (chave) |
|---|---|---|---|---|
| **#308-PR0** | `fix(security): #308-PR0 — curation_review_log RLS deny-all + REVOKE anon get_all_certificates` | (a) DROP `curation_review_log_read USING(true)` → `FOR SELECT USING(false)` (leitura só por SECDEF); (b) `REVOKE EXECUTE ON get_all_certificates(text,text,boolean) FROM anon`; (c) adicionar `initiative_id` a `curation_review_log` (denormalizar de board_items) p/ gate ADR-0105 futuro. **NÃO** mexe em `submit_curation_review` (corpo vivo já não usa cache — §0.2). | neutral (hardening) | policy deny-all; anon sem EXECUTE (sweep #965 exclui); `initiative_id` populado; contract green |
| **#308-PR1** | `feat(evidence): #308-PR1 — curation_artifact_snapshots + review-log FK + criteria/version anchors` | `curation_artifact_snapshots` (deny-all RLS, `digest_status`, 2 UNIQUE idempotência); `register_curation_artifact_snapshot` SECDEF; `curation_review_log.artifact_snapshot_id` + `reviewer_governing_politica/termo_version_id` + CHECK 5-chaves criteria; **sem trigger** | **neutral** | tabela+RLS; RPC idempotente `ON CONFLICT`; snapshots confidenciais omitidos (test); REVOKE PUBLIC/anon/authenticated; digest_status default `pending`; build+test green |
| **#308-B** | `feat(evidence): #308-B — evidence bundle + cert issuance (abrir no 1º ciclo real)` | Guarda-chuva colapsando bundle (`curation_evidence_bundles` + join table + trigger imutável + `_finalize` privado), `member_contribution_evidence`, categorias DFEP-companheiro/DACO, snapshot bilíngue 1-linha, `verify_certificate` type-aware, UI (3 superfícies), 2 MCP tools, contract tests (invariantes), **extensão `export_my_data` (bloqueante do go-live)** | go-live gated | a definir na abertura; herda §3.2–§6 + §11 |

**Sibling (pré-existente, não-#308-child):** `verify_certificate` expõe **NOME** do counter-signer/issuer na /verify anônima → substituir por string org (grounded ao vivo §0.2). Prioridade medium.

**Sequência:** PR-0 → PR-1 → (#308-B quando houver dado). Menor PR de valor = **PR-1** (captura âncoras de versão no próximo ciclo real). Caveat ADR-0097: mergear PR-da-migration antes de rebasear irmãos.

---

## 9. Invariantes (CUR_001–CUR_010)

- `CUR_001` bundle finalizado ⇒ `content_snapshot` NOT NULL + `final_decision` + `content_product_id` NOT NULL (CHECK estrutural).
- `CUR_002` snapshot carrega âncora de versão válida (uma de file/docver, estrutural).
- `CUR_003` **`_finalize_evidence_bundle` rejeita finalizar contra `content_product` arquivado** (write-gate, **não** drift-check — §11 F-L-cur003; arquivamento pós-finalize NÃO invalida o histórico).
- `CUR_004` certs `function_held`/`curation_contribution` carregam ambas as chaves `pt_BR`+`en_US` (estrutural); `CUR_004-b` `signature_hash` NOT NULL nesses tipos.
- `CUR_005` emissão gated `manage_member`, nunca `curate_content` (GR-1 análogo).
- `CUR_006` /verify exclui artigos/scores/notes/nomes(titular+counter-signer)/Drive-URLs/`revoked_reason`/`signed_ip`; não-emitido → `{valid:false}` indistinguível (contract test).
- `CUR_007` papel vem de `engagements`, não `operational_role` (assert de corpo/contrato).
- `CUR_008` linhas de iniciativa confidencial omitidas silenciosamente de todo RPC de evidência (contract test).
- `CUR_009` nenhum cert `curation_contribution` fica `issued` enquanto seu bundle está `revoked` (§11 F-B6).
- `CUR_010` nenhum `content_snapshot` de DACO de obra `independent_blind` referencia outro revisor por nome/ID antes de a obra chegar a `published` (§11 F-H11).

---

## 10. ADR-0119 (resumo — doc completo em `docs/adr/ADR-0119-*.md`)

**Título:** ADR-0119 — Curator Contribution Evidence Bundles and Bilingual Verifiable Declarations.

**Decisão:** evidência = fonte primária, certificados = derivações verificáveis. `curation_artifact_snapshots` (freeze por-versão, digest-only + `digest_status`), `curation_evidence_bundles` (envelope por-(artigo,rodada), snapshot congelado imutável via trigger **fresco**, revisores via join table FK-safe), `member_contribution_evidence` (visão por-membro, autoridade de `engagements`). Categorias **DFEP-companheiro** + **DACO**; bilíngue 1-linha travado na emissão; DFEP/DACO exigem counter-sign GP. 3 tiers (público metadata-only via `verify_certificate` type-aware + código 72-bit / autenticado self / **Tier 3 diferido**), todos sob gate confidencial ADR-0105. Fundação **behavior-neutral agora** (0 linhas); emissão/UI gated por dado + 1ª requisição; emendas do Manual por Camada 5 material (2 chains).

**Relaciona/amenda:** relaciona ADR-0098; **cumpre ADR-0099 §2.9** (evidence-anchoring diferido); reusa ADR-0101 (digest + OTS opcional); espelha GR-1 do ADR-0102 (visibilidade ≠ autoridade de emissão); depende de ADR-0105 (confidencial), ADR-0108 (ledger de grant), ADR-0117 (versão regente), ADR-0006/0007. **Não** absorve #311.

---

## 11. Correções da revisão adversarial (NORMATIVAS — incorporar na implementação)

> 6 blockers + 12 high + selecionados medium/low. IDs referenciados no corpo acima.

**Blockers**
- **F-B1** (PR-0 stale): PR-0 colapsa a UM item de cert — `REVOKE anon get_all_certificates` — **não** strip de `content_snapshot` (a função não vaza; re-aterrado §0.2). O item de RLS `curation_review_log USING(true)` é a outra metade real.
- **F-B2** (behavior-neutral falso): **remover** o wire-in de `_finalize_evidence_bundle` em `submit_curation_review` de qualquer PR fundacional. Modificar o corpo de um RPC de produção **não** é neutral, mesmo com callee no-op. Wire-in vai p/ #308-B go-live gated.
- **F-B3/F-B5** (imutabilidade ilusória / cadeia inverificável): `file_digest` nullable = ponteiro Drive mutável. Introduzir `digest_status ('pending'|'verified'|'unresolvable')`; **DACO não embute artefato com status≠verified** (lista em seção "sem âncora"); digest obtido por EF na captura OU out-of-band com trilha em `admin_audit_log`; **GP-provided-after-the-fact proibido** p/ validade externa. Não reivindicar valor probatório ADR-0101 antes disso.
- **F-B4** (`finalize` público forjável): renomear `_finalize_evidence_bundle` (privado), `REVOKE EXECUTE FROM PUBLIC,anon,authenticated`; **remover da tabela de RPCs públicos**; contract test assertando zero EXECUTE p/ anon/authenticated (padrão ratchet #965).
- **F-B6** (revogação não-cascateia → instrumento falso): escolha explícita no ADR = **proíbe revogar bundle depois de cert emitido** (revogação vira ação de cert: `revoke_certificate` + `revoked_reason`; bundle intacto p/ auditoria). Adicionar `CUR_009`.

**High**
- **F-H1** (`uuid[]` sem FK): substituir `reviewer_member_ids uuid[]` por join table `curation_bundle_reviewers` (FK-safe, per-reviewer metadata); RLS via `EXISTS`. `uuid[]` só como cache read-only pós-finalize, nunca autoridade de RLS.
- **F-H2** (trigger inerte): `trg_curation_bundle_immutable` **fresco** enumerando as colunas certas; `trg_work_governing_version_immutable` checa outra tabela.
- **F-H3** (decisão ambígua): `final_decision` = espelho da transição terminal de `submit_curation_review`, **passado como param**; `_finalize` não re-deriva.
- **F-H4** (2 verify RPCs / rota ambígua): **estender `verify_certificate`** com projeção type-aware (`type IN ('function_held','curation_contribution')` → field-list Tier-1); **dropar** `verify_contribution_certificate`. Uma RPC, uma rota. **Corrigir junto** o leak de nome (F-M-names).
- **F-H5** (oracle de discriminante): especificar Tier-1 como `jsonb_build_object` concreto; qualquer código não-emitido → `{valid:false}` só, sem `error:`.
- **F-H6** (`drive_revision_id` congelado): `content_snapshot` montado por `jsonb_build_object` com **allowlist**; proibir `drive_revision_id`, `captured_by`, `created_at`. Contract test: chave `drive_revision_id` ausente do snapshot.
- **F-H7** (anon grant vivo): PR-0 `REVOKE EXECUTE ON get_all_certificates FROM anon` (grounded ao vivo §0.2); `authenticated` fica (função gateia internamente); **não** adicionar à allowlist #965.
- **F-H8** (duplo-instrumento): **decisão PM Q2 = DFEP companheiro** — cross-ref `basis_volunteer_agreement_code`; invariante nenhum `function_held` sem `volunteer_agreement` (ou waiver).
- **F-H9** (hash indefinido): `signature_hash = SHA-256(content_snapshot::text||member_id::text||issued_at::text||'nucleo-ia-contrib-salt')`; expor `content_snapshot_hash` (sem salt) no Tier-1 p/ verificação externa. `CUR_004-b`.
- **F-H10** (Frontiers sem elo OTS): adicionar `pi_exclusion_asset_ids uuid[]` ao `content_snapshot` (congelado no finalize; array vazio se sem registro PI — ausência honesta, não silenciosa); surfaçar `pi_ots_status` por artefato. Ancoragem OTS completa defere a #569; **placeholder estrutural entra no #308** desde PR-1.
- **F-H11** (blind-review acadêmico): p/ `review_mode='independent_blind' AND status<>'published'` — congelar só COUNT (não UUIDs) até `published`; UUIDs em coluna audit-only deny-all; redigir título até publicar; `CUR_010`.
- **F-H12** (Manual §7 mal-roteado): dividir emenda em **2 chains** (§7). Chain 2 (não-retroatividade) exige advogado licenciado antes.

**Medium/Low selecionados**
- **F-M-criteria**: CHECK das 5 chaves `clarity/originality/adherence/relevance/ethics` (1-5), nomeadas no ADR.
- **F-M-gov**: `governing_version_id` só no bundle (não no snapshot — YAGNI/dormente).
- **F-M-gov-per-reviewer**: versão regente por-revisor gravada no INSERT do log (não no finalize; tie-break Termo 15.4.6 ancora na 1ª contribuição), colunas nullable em PR-1.
- **F-M-unique**: 2 UNIQUE parciais em `curation_artifact_snapshots` (idempotência real).
- **F-M-cp**: `content_product_id NOT NULL` p/ bundle finalizado (âncora legal do DACO).
- **F-M-names**: `verify_certificate` não expõe nome de counter-signer/issuer (org string) — corrigido junto de F-H4.
- **F-M-entropy**: `encode(gen_random_bytes(9),'hex')` (72 bits), nunca `md5(random())`; regex `^CURAT-[0-9]{4}-[0-9A-F]{18}$`.
- **F-M-aidraft**: AI-draft opera só sobre scores numéricos + metadados da obra (**nunca** `feedback_notes` como contexto); trigger BEFORE INSERT regex anti-nome com override GP explícito (`summary_reviewed_for_pii:true`).
- **F-M-tier3**: (quando Tier 3 shipar) `get_shared_evidence_bundle` re-checa `rls_can_see_initiative` a cada resgate; soft-revoke ao virar confidencial.
- **F-M-lgpd**: `export_my_data` estendido = **bloqueante** do go-live de emissão; cron 5y cobre as colunas de identidade novas.
- **F-L-cur003**: `CUR_003` = write-gate em `_finalize`, não drift-check.
- **F-L-dpg**: DPG removido do #308 (cabe a #311).
- **F-L-onerow**: bilíngue 1-linha (fecha §9 Q2 do skeleton).
- **F-L-tests**: contract tests split — schema-shape (offline sempre) vs behavioral (DB-gated, SKIP até haver dado, header documentando — precedente `194-p197-review-flow-contracts.test.mjs`); registrar no `package.json` (lição #965).

---

## 12. Questões abertas (pós-decisões PM)

Resolvidas: Q1 (enxuto) · Q2 (DFEP companheiro) · Q3 (omitir nome Tier 1) · Q4 (Tier 3 fora). Remanescentes (não-bloqueantes; resolver no #308-B):
1. EN-US indisponível na emissão → bloquear vs pt-BR-only-com-EN-diferido (implementação #308-B).
2. Ancoragem OTS completa p/ DACO acadêmico — coordenar com #569/ADR-0101 Slice 4 (placeholder estrutural já entra).
3. AI-draft de `criteria_summary`: EF vs plpgsql inline (definir no #308-B; guardas F-M-aidraft valem em ambos).

---

## 13. Referências

- Issue #308 (planning) · #311 (genérico, OPEN) · #181/#190/#301/#166/#194/#64/#201 (CLOSED — matéria-prima) · #568 (`export_my_data`) · #569 (ADR-0101 PI/OTS).
- ADRs: 0098 (cert PDF autogen + /verify soft-private) · 0099 (content_products obra) · 0101 (digest-only + OpenTimestamps) · 0102 (governance review + RLS document_versions + leak #648/#653) · 0105 (confidential gate) · 0108 (curation drive grants) · 0113 (change_class/dias-úteis) · 0115 (Gate Matrix v3) · 0117 (work_governing_version) · 0006/0007 (V4 engagements/authority).
- Manual R3 §3.6/§3.9/§4/§5/§7. Camada 5 (#571 umbrella CLOSED).
- Workflow: `wf_8f991faa-ec0` (design 4-lentes + síntese + adversarial 3-céticos). Grounding ao vivo prod `ldrfrvwhxsmgaabwmaik` 2026-06-30.
