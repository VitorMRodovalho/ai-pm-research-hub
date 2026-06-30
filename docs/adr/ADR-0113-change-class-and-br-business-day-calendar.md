# ADR-0113 — Material/Editorial como campo de 1ª classe + calendário de dias úteis BR (#973, PR-1 de #571)

**Status:** Accepted (2026-06-30, #973 — PR-1 da Camada 5 / #571)
**Relacionado:** ADR-0016 (IP ratification, gates-as-data) · `docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md` §5 PR-1 + §9 · `lock_document_version` (subsistema de `document_versions`, não o Manual 2-of-N) · privacy_policy_versions.summary_* (template do aviso-30d) · #334 (gate G12 do dispatch outward, dormente).
**Migration:** `20260805000301_571_pr1_camada5_change_class_and_business_days.sql`.

## Contexto

A Camada 5 (#571) opera o ciclo **classificação → ratificação → notificação → re-aceite → desfecho** de um instrumento de governança binding quando ele sofre uma **Material change**. A decomposição (SPEC §5) identificou **dois primitivos cross-cutting** dos quais WA1/WA2/WA3 dependem, e que por isso formam o **PR-1 (fundações), behavior-neutral**:

1. **Classificação Material vs Editorial** como dado estruturado por versão. Hoje a materialidade só vive em `version_label` (texto livre); não há campo. O teste de 5 pontos vive em Política 12.2; o aceite tácito (art. 111 CC) é válido **só** para Editorial (Termo 15.4.4).
2. **Calendário de dias úteis brasileiro.** Os prazos do Termo/Política são em **dias úteis** (re-aceite 15, Comitê 10, acomodação 5, consulta a parceiros 15) e **dias corridos** (pré-aviso 30, suspensão +30). Antes deste PR não existia `add_business_days` nem tabela de feriados (`add_business_days`=0 funções; `br_holidays`=0).

## Decisão

**1. `document_versions.change_class text CHECK (change_class IN ('editorial','material'))` — nullable, resolvido no lock, nunca defaultado.**

A classificação é uma decisão deliberada (Política 12.2), não derivável silenciosamente. O campo é nullable; é resolvido em `lock_document_version` (ver 4) e **congelado** depois (ver 3). Adicionadas também `summary_pt/en/es` (inline, espelhando `privacy_policy_versions`) — colunas do **aviso-30d** que PR-4 consome (SPEC §9.2 fixou inline em `document_versions`, resolvendo a ambiguidade que PR-4 deixava aberta).

**2. Calendário: tabela `br_holidays` + `add_business_days`/`business_days_between` STABLE (não IMMUTABLE).**

`br_holidays(holiday_date pk, label, scope CHECK('national','GO'))`, RLS habilitada (GC-162), leitura pública (referência não-PII), escrita só via service_role/migration (RLS default-deny). Seed **2025–2030**: 9 feriados nacionais fixos/ano + Sexta-feira Santa (Easter-2) como `national`; Carnaval seg+ter (Easter-48/-47), Corpus Christi (Easter+60) e Aniversário de Goiânia (24/10) como `GO` — datas móveis verificadas por Computus gregoriano. Incluir dias amplamente não-úteis é **pró-voluntário** (estende a janela, tie-break 15.4.6).

As funções são **STABLE** (leem `br_holidays`), nunca IMMUTABLE — logo **não podem entrar em `GENERATED`/`DEFAULT`** (SPEC §9.2). Os PRs seguintes computam os prazos **em RPC no momento do INSERT/UPDATE**, não em colunas geradas. São TZ-aware (`America/Sao_Paulo`, sem DST desde 2019) e excluem **todos** os feriados independentemente de `scope` — o calendário da sede (GO) é a aproximação canônica; feriados dos estados-parceiros (CE/DF/MG/RS) são limitação conhecida diferida a PR-3/PR-4 (SPEC §9.5). Ambas dão `RAISE WARNING` fora de 2025–2030 para que a falta de cobertura futura seja **ruidosa, não silenciosa**.

**3. `trg_document_version_immutable` estendido para congelar `change_class` quando `locked_at IS NOT NULL`.**

Adicionado `OR NEW.change_class IS DISTINCT FROM OLD.change_class` ao predicado de imutabilidade (SPEC §9.2). Sem isso, um privilegiado reclassificaria material→editorial pós-lock e anularia silenciosamente as obrigações de re-aceite. `change_class` continua **gravável durante o próprio UPDATE do lock** (naquele instante `OLD.locked_at IS NULL`, então o ramo de imutabilidade é pulado).

**4. `lock_document_version` ganha `p_change_class text DEFAULT NULL` — BACKWARD-COMPATIBLE (sem RAISE em NULL).**

DROP+CREATE (mudança de aridade 2→3, GC-097). Chamadas antigas de 2 args resolvem via o DEFAULT. Precedência: param explícito > valor pré-setado no rascunho; validado quando presente; **NULL permitido** (não levanta). A classificação obrigatória é imposta na **UI** (seletor Material/Editorial no modal de lock, que desabilita o confirm até a escolha) e exposta como param opcional na MCP tool. Manter o RPC backward-compatible foi deliberado: aplicar a migration ao **DB de produção compartilhado** não pode quebrar o botão "Lacrar" do frontend já deployado antes do deploy do novo bundle.

**5. Helper `map_cr_type_to_change_class(text)` — mapeamento explícito documentado.**

editorial→editorial; operational/structural/emergency→material; NULL/desconhecido→NULL (não resolvido; humano classifica). IMMUTABLE, search_path pinado.

**6. Higiene: reconciliação de `governance_documents.version` ← label da versão corrente.**

A coluna `gd.version` lia marcadores de rascunho obsoletos (Política/Termo/adendos = `v2.3-adr0068-draft`; Anexo = NULL) enquanto `current_version_id` apontava para v2.7/v2.6. A reconciliação corrige **apenas** as 6 linhas com marcador de rascunho (`version IS NULL OR ILIKE '%draft%'`), deixando labels limpos (`R2`, `v1.0`, `R3-C3`, `v2.2`, `R00`) intactos — esses têm dependência literal em `src/lib/certificates/pdf.ts`. O frontend lê `document_versions.version_label` (não `gd.version`), então é seguro; o único efeito é o rodapé de fallback de PDF dos 6 docs passar a mostrar o label correto (obsoleto→correto).

## Por que o caminho do `change_class` é `lock_document_version`, não `confirm_manual_version`

A SPEC §5 PR-1 instrui "wire `confirm_manual_version`". Verificação ao vivo provou que `confirm_manual_version(p_proposal_id)` é o fluxo **2-of-N do Manual de Governança** que escreve linhas em `governance_documents` (doc_type='manual') e **nunca toca `document_versions`** — onde `change_class` vive. O caminho real de "versão lacrada" (o critério de aceite "toda nova versão lacrada carrega change_class") é o subsistema `upsert_document_version` (rascunho) → `lock_document_version` (lacra + abre approval_chain). A SPEC §0 já avisava que partes foram escritas sobre snapshots desatualizados; esta é uma correção de inconsistência interna, não desvio de escopo. O mapeamento `cr_type→change_class` (subsistema do Manual/CRs) é fornecido como **helper testável** para uso na classificação dirigida por CR.

## Contrato interim / forward-compat (ler antes de PR-2..5)

- `change_class IS NULL` significa **não-classificado**. As 41 versões já lacradas — e qualquer versão lacrada por um caller que não passe `p_change_class` (o frontend/MCP até o deploy do seletor; `recirculate_governance_doc`) — ficam NULL, e o trigger estendido **congela** esse NULL.
- A lógica de Material change a jusante (PR-3 cadeia, PR-4 re-aceite) **DEVE** tratar `change_class IS NULL` como **NÃO-material** (fail-safe: nenhuma obrigação de re-aceite). Toda a máquina é dormente até o Termo/Política v2.7 ratificarem e o dispatch ser des-gateado (#334), então um NULL no interim não abre nada.
- O deploy da EF `nucleo-mcp` (que expõe o param `change_class` na tool) e do Worker (frontend com o seletor) acompanham o release; até lá o caminho backward-compatible mantém tudo funcionando.

## Alternativas rejeitadas

- **`lock_document_version` levanta em NULL (enforcement duro):** quebraria o frontend já deployado na janela entre apply-migration e deploy do Worker (DB compartilhado) — não behavior-neutral. Trocado por enforcement na UI + contrato fail-safe a jusante.
- **`change_class` em `governance_documents` (grão documento):** o grão correto é a **versão** (cada versão tem sua própria materialidade); o Manual usa governance_documents-por-versão, mas os instrumentos da Camada 5 (Política/Termo/Anexo) usam `document_versions`.
- **`add_business_days` IMMUTABLE p/ usar em GENERATED:** lê `br_holidays` ⇒ não é imutável; forçar quebraria ao re-seedar feriados (SPEC §9.2).
- **Reconciliar `gd.version` em TODAS as linhas:** sobrescreveria labels limpos (`R3-C3`) com placeholders e arriscaria a lógica de cert PDF; escopado só aos marcadores de rascunho.

## Consequências

- Toda nova versão lacrada **pela UI/MCP** carrega `change_class`; legados ficam NULL (tratado como não-material). Imutável pós-lock.
- O calendário BR existe e é testado (`add_business_days('2026-04-20',1)` pula Tiradentes → 22/04; pula Carnaval). PRs 2–5 computam prazos em úteis/corridos sem reinventar a base.
- `check_schema_invariants()` permanece 0 violações (coluna nullable + tabela de referência sem FK a iniciativas; AJ não se aplica).
- Contract test `tests/contracts/571-pr1-camada5-foundations.test.mjs` (estático + DB-aware) trava a fundação no CI.
