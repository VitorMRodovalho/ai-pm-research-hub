# ADR-0119 — Curator Contribution Evidence Bundles and Bilingual Verifiable Declarations

| Field | Value |
|---|---|
| Status | **Accepted (planning)** — 2026-06-30. Deliverable de #308 (planning issue) = arquitetura, não código. PM modeling decisions resolvidas (AskUserQuestion 2026-06-30). |
| Date | 2026-06-30 |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude (Anthropic)) |
| Issue | #308 (`governance: curator contribution evidence bundles and bilingual certificates`) |
| Spec | `docs/specs/SPEC_308_CURATOR_EVIDENCE_BUNDLES.md` |
| Supersedes | none |
| Amends | none |
| Related | ADR-0098 (cert PDF autogen + `/verify` soft-private) · **ADR-0099 §2.9** (evidence-anchoring diferido da Wave 6 — este ADR o cumpre) · ADR-0101 (digest-only + OpenTimestamps) · ADR-0102 (governance review + RLS `document_versions` + leak #648/#653; GR-1 visibilidade≠autoridade) · ADR-0105 (confidential-initiative gate) · ADR-0108 (curation drive grants) · ADR-0113 (change_class/dias-úteis BR) · ADR-0115 (Gate Matrix v3) · ADR-0117 (work_governing_version) · ADR-0006/0007 (V4 engagements/authority) · GC-162 (RLS/LGPD) |
| Scope boundary | **#311** (OPEN) = modelo genérico de evidence-bundle p/ todos os papéis/tiers. Este ADR modela **curador/revisão-de-artigo**; `member_contribution_evidence` é o agregador curation-scoped que #311 envolve. **Não** absorve #311. |
| Method | Workflow ultracode `wf_8f991faa-ec0` (design 4-lentes → síntese → adversarial 3-céticos: 6 blockers + 12 high incorporados). Grounding ao vivo prod `ldrfrvwhxsmgaabwmaik` 2026-06-30. |

---

## Contexto

A Plataforma precisa de uma **capacidade institucional** (não aconselhamento individual) de dar lastro verificável de **função exercida** e **ações realizadas** por membros/curadores, respondendo — **por artigo/artefato** — quem revisou, o quê, **qual versão**, qual decisão, quais critérios, qual feedback, e qual declaração é verificável depois, em PT-BR + EN-US.

Grounding ao vivo (2026-06-30): o **primitivo de certificado já é capaz** — `certificates` (46 linhas) carrega `content_snapshot jsonb`, `verification_code`, `signature_hash`, counter-sign (colunas, #181), `function_role`, `period_start/end`, `language`, `pdf_url` (autogen ADR-0098). **O gap é upstream:** (1) `board_item_files` (22) e `curation_review_log` (**0 linhas**, keyed só a `board_item_id`) não congelam a versão exata revisada; (2) não há envelope agregado por-artigo; (3) função-no-período não é derivada de `engagements` (198). A obra canônica é `content_products` (37, ADR-0099); a versão regente é `work_governing_version` (ADR-0117).

Como `curation_review_log = 0 linhas`, a camada é desenhada **à frente dos dados** — o que dita uma decomposição **enxuta** (fundação behavior-neutral agora; emissão/UI dormentes até dado + 1ª requisição).

## Decisão

**Modelar a evidência como fonte primária e certificados como derivações verificáveis dela.**

1. **`curation_artifact_snapshots`** (PR-1) — freeze por-versão do artefato revisado, padrão **digest-only ADR-0101** (SHA-256, a obra nunca sai do Núcleo). `digest_status ∈ ('pending','verified','unresolvable')` torna a ausência de âncora **machine-visible**; um DACO **não** embute artefato com `status≠verified` (lista-o em seção "sem âncora criptográfica"). `drive_revision_id` é interno e **jamais** surfaceado nem congelado. Sem trigger (auto-capture é enhancement diferida); RPC `register_curation_artifact_snapshot` manual, idempotente (2 UNIQUE parciais).

2. **`curation_evidence_bundles`** (#308-B) — envelope **por-(artigo, rodada)** agregando todos os revisores; `content_snapshot` congelado no finalize por `_finalize_evidence_bundle` **PRIVADO** (`REVOKE … FROM PUBLIC,anon,authenticated`), imutável via trigger **fresco** `trg_curation_bundle_immutable`. Revisores via **join table FK-safe** `curation_bundle_reviewers` (não `uuid[]`). `final_decision` = espelho da transição terminal de `submit_curation_review`, **passado como parâmetro** (não re-derivado). `content_snapshot` montado por `jsonb_build_object` com **allowlist** (proíbe `drive_revision_id`/`captured_by`).

3. **`member_contribution_evidence`** (#308-B) — visão por-membro; **autoridade de `engagements`, não do cache `operational_role`** (Gap 4). Filtro `rls_can_see_initiative` por-artefato (ADR-0105, omissão silenciosa); loga GP-lê-outro (Art.37); blind-review em Tier 2 (só contagem + a própria contribuição).

4. **Categorias de declaração** (#308-B): **DFEP** (`function_held`) como **documento companheiro** que cross-referencia `volunteer_agreement.verification_code` (nunca instrumento primário duplicado — fecha o conflito com os 41 `volunteer_agreement` que já gravam função+período); **DACO** (`curation_contribution`) por-obra. **DPG removido** (participação genérica cabe a #311). Bilíngue = **uma linha** (`content_snapshot` com `pt_BR`+`en_US`, **um** `verification_code`, **um** `signature_hash = SHA-256(content_snapshot||member_id||issued_at||salt)`), **travado na emissão** (nunca traduzido depois). DFEP/DACO exigem **counter-sign GP** antes de emissão externa; emissão gated `manage_member` (nunca `curate_content`).

5. **Três tiers de acesso** — **Tier 1 público `/verify/{code}`** metadata-only via `verify_certificate` **estendido type-aware** (uma RPC, uma rota; **omite o nome do titular** e do counter-signer — org string `authorized_by`; expõe `content_snapshot_hash` p/ verificação externa; não-emitido → `{valid:false}` sem discriminante; código `CURAT-YYYY-<18 hex>` via `gen_random_bytes`, 72 bits). **Tier 2 autenticado self.** **Tier 3 (link assinado externo) DIFERIDO** (follow-up). Tudo sob o **carve-out confidencial ADR-0105** (`rls_can_see_initiative`, omissão silenciosa; `initiative_id` denormalizado em cada tabela nova).

6. **Manual de Governança** — emendas roteiam por **Camada 5 material (ADR-0113/0115)** em **dois approval-chains**: Chain 1 procedural (§3.6/§4 registro de evidência, §3.9/§5 categorias/bilíngue/verificação/imutabilidade, §6 PI); Chain 2 substantivo (§7 não-retroatividade) — exige **advogado licenciado antes**.

7. **Decomposição enxuta** (PM Q1): **PR-0** (hardening: `curation_review_log` RLS deny-all + `REVOKE anon get_all_certificates` + `initiative_id` denormalizado) → **PR-1** (`curation_artifact_snapshots` + FK/âncoras no log) → **#308-B** (guarda-chuva do bundle/emissão, a abrir no 1º ciclo real). Fundação **behavior-neutral**; sem wire-in a RPC de produção até o go-live gate.

## Invariantes (CUR_001–CUR_010)

`CUR_001` bundle finalizado ⇒ snapshot + decisão + `content_product_id` NOT NULL · `CUR_002` snapshot com âncora de versão válida · `CUR_003` finalize rejeita `content_product` arquivado (**write-gate, não drift**) · `CUR_004(+b)` novos tipos têm `pt_BR`+`en_US` e `signature_hash` NOT NULL · `CUR_005` emissão `manage_member`≠`curate_content` · `CUR_006` /verify sem artigos/scores/notes/nomes/Drive-URLs/`revoked_reason`/`signed_ip`; não-emitido indistinguível · `CUR_007` papel de `engagements` · `CUR_008` confidencial omitido silenciosamente · `CUR_009` nenhum DACO `issued` com bundle `revoked` (bundle não-revogável após cert emitido) · `CUR_010` DACO de obra `independent_blind` não nomeia outro revisor antes de `published`.

## Consequências

**Positivas:** evidência auditável e verificável desacoplada do instrumento; certificado é derivação com hash reproduzível externamente; fundação neutra captura âncoras no próximo ciclo real sem risco; reusa primitivos existentes (certificados, content_products, digest ADR-0101, gate confidencial); escopo delimitado vs #311.

**Custos / riscos aceitos:** camada dorme até haver dado de curadoria (`curation_review_log=0`); ancoragem OTS completa fica p/ #569 (só placeholder estrutural aqui); `export_my_data` estendido é **bloqueante do go-live de emissão** (LGPD Art.18 V); Tier 3 diferido (Tier 1+2 já satisfazem os ACs); dependência de counter-sign GP manual antes de emissão externa.

**Pré-existentes surfaçados (sibling, não-#308-child):** `verify_certificate` expõe **nome** de counter-signer/issuer na /verify anônima (grounded ao vivo) → substituir por string org; corrigido junto da extensão type-aware do #308-B, mas rastreado como issue própria.

## Alternativas rejeitadas

- **DFEP como cert primário standalone** — rejeitado: conflita com o `volunteer_agreement` (dois instrumentos sobre a mesma função/período). Adotado: documento companheiro (PM Q2).
- **`reviewer_member_ids uuid[]`** — rejeitado: sem FK, UUIDs stale silenciosos, quebra RLS e conteúdo do cert. Adotado: join table.
- **Reusar `trg_work_governing_version_immutable` verbatim** — rejeitado: checa colunas de outra tabela → guard inerte. Adotado: trigger fresco por-tabela.
- **`verify_contribution_certificate` como RPC separada** — rejeitado: duas RPCs p/ uma rota `/verify`, roteamento ambíguo. Adotado: `verify_certificate` estendido type-aware.
- **Bilíngue em duas linhas pareadas** — rejeitado: dois códigos/hashes/PDFs, revoke sincronizado, 0 demanda bilíngue provada. Adotado: uma linha (PM/adversarial).
- **6-7 child issues à frente dos dados** — rejeitado: PRs 3-6 sem comportamento verificável até 1º ciclo. Adotado: enxuto (PM Q1).
- **Tier 3 no #308** — diferido (PM Q4).
