# ADR-0114 — Version-pin instrumento→versão + vedação de remissão dinâmica (#974, PR-2 de #571)

**Status:** Accepted (2026-06-30, #974 — PR-2 da Camada 5 / #571)
**Relacionado:** ADR-0016 (IP ratification, gates-as-data — **este ADR a amenda**) · ADR-0113 (PR-1: change_class + calendário BR, fundação que este PR usa) · `docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md` §5 PR-2 + §9.1 + §9.3 · ADR-0105 (#785 confidencial — **NÃO** se aplica: tabela não-initiative-linked).
**Migration:** `20260805000302_974_pr2_camada5_instrument_version_bindings.sql`.

## Contexto

A frente **WA3** da Camada 5 (Termo 15.4.1) exige **fixar (pin)** a versão de um instrumento de governança que outro instrumento referencia, **vedando a remissão dinâmica** — a prática de escrever "a Política … vigente", que resolve para o estado vivo a cada leitura. Remissão dinâmica é perigosa em litígio: a obrigação muda silenciosamente quando a Política muda, sem re-aceite das partes.

Antes deste PR não havia tabela de binding instrumento→versão; a única coluna cross-ref (`related_manual_sections`) é NULL em toda linha e não é um pin.

## Correção de grounding (a premissa de backfill da SPEC §9.3 estava factualmente errada)

A SPEC §9.3 instruía: "backfill dos 4 cooperation_agreements pinando a Política **vigente na data de assinatura**, via o snapshot `approval_signoffs.referenced_policy_version_id` do gate `president_go`." **Verificação ao vivo (2026-06-30) provou isso inimplementável:**

1. Os 4 acordos bilaterais ATIVOS (PMI-GO↔CE/DF/MG/RS) foram **assinados em dez/2025** e ratificados por uma **chain sintética p257** (gate `member_ratification` / signoff `acknowledge`, `referenced_policy_version_id = NULL`). **Há ZERO `president_go` signoffs** — a query canônica de §9.3 retorna NULL para os 4.
2. Os **corpos dos 4 acordos NÃO citam a Política** nem "vigente". O instrumento que carrega a remissão dinâmica ("a Política de Governança de PI vigente") é o **Adendo de PI aos Acordos de Cooperação** (`doc_type='cooperation_addendum'`, "*Aplica-se aos 4 acordos bilaterais*"), hoje **`under_review` — não ratificado**.
3. A **1ª versão LACRADA da Política é de abr/2026** (v2.1); os acordos são de dez/2025. **"Versão na data de assinatura" não existe.**

**Decisão PM (`AskUserQuestion`, 2026-06-30):** backfill = **4 bindings (cada acordo→Política)**, pin = **head vigente da Política** (`v2.7-p128`, `8f4337e6`) — o valor que a remissão dinâmica do Adendo resolveria hoje. As alternativas (1 binding Adendo→Política; pin "na assinatura"; backfill 0) foram apresentadas e rejeitadas pelo PM. O pin é **antecipatório**: ver Consequências.

## Decisão

**1. Tabela `instrument_version_bindings` — SSOT do pin instrumento→versão; `pinned_version_id NOT NULL` veda remissão dinâmica por construção.**

`(bound_document_id, referenced_document_id, pinned_version_id NOT NULL, pin_clause_ref, re_anchor_required, last_material_version_id, status, …)`. O pin é uma **referência dura a `document_versions.id`** (imutável, lacrada), nunca um label ou texto "vigente". UNIQUE parcial via statement separado (`CREATE UNIQUE INDEX … WHERE status='active'` — PG não aceita `UNIQUE(...) WHERE` inline). **Append-only:** editorial auto-advance e re-âncora inserem nova row + supersede a antiga (`status='superseded'`), nunca UPDATE in-place do pin (honra invariante §4.1, preserva o histórico de pins p/ a versão regente de obra em período intermediário — PR-5). RLS habilitada (GC-162): leitura = `manage_platform`; **nenhuma policy de escrita** ⇒ writes só via RPCs SECDEF / service_role / migration. **Não é initiative-linked** ⇒ invariante AJ (#785) não se aplica.

**2. Trigger `trg_propagate_version_change_class` — propaga a classificação da nova versão lacrada do instrumento REFERENCIADO.**

`AFTER UPDATE OF locked_at, change_class … WHEN (OLD.locked_at IS NULL AND NEW.locked_at IS NOT NULL AND NEW.change_class IS NOT NULL)` — fire só na transição de lock com classe resolvida (o `WHEN` evita a frame PL/pgSQL em toda UPDATE de rascunho). `change_class IS NULL` ⇒ no-op (não-material fail-safe, contrato ADR-0113):
- **editorial** ⇒ **append-only auto-advance** de cada binding ativo do referenced (supersede a antiga, insere nova ativa pinada na nova versão). Editorial não muda obrigação; partes não re-assinam; o audit log satisfaz a ciência (Política 12.3). O cursor usa `FOR UPDATE` para serializar locks editoriais concorrentes do mesmo referenced (evita violação do índice parcial único).
- **material** ⇒ seta `re_anchor_required=true` + `last_material_version_id` nos bindings ativos. **NÃO move o pin** — re-âncora é ato humano expresso (`reanchor_instrument_binding`).
- Ambos os ramos **escrevem `admin_audit_log`** (`actor_id=NULL` = ação de sistema, precedente em mig …266) — o canal de auditoria que a SPEC §9.3 invoca para a ciência 12.3.

**3. RPCs SECDEF (REVOKE de PUBLIC/anon/authenticated; gate uniforme `manage_platform`):**
- `pin_instrument_version(bound, referenced, pinned_version, clause_ref)` — valida que a versão pertence ao referenced E está **lacrada** (pin duro ≠ rascunho); append-only.
- `reanchor_instrument_binding(binding, new_version, justification)` — **único caminho que limpa `re_anchor_required`**; `SELECT … FOR UPDATE` na binding antiga (evita 2 ativas); **exige avanço do pin** (rejeita `new_version = pinned atual` — Termo 15.4.1 re-âncora expressa); justificativa ≥10 chars.
- `list_stale_instrument_bindings()` — read p/ dashboard (par com `get_version_diff(pinned, current)`); `is_behind` NULL-safe quando o referenced não tem versão corrente lacrada.

O gate de **leitura é `manage_platform`** (não `manage_member`), alinhado à RLS SELECT e às escritas — sem assimetria de privilégio através da fronteira SECDEF (achado da revisão adversarial).

**4. Invariante `AN_no_dynamic_remission_cooperation` em `check_schema_invariants()` (na MESMA migration — §9.3).**

Todo `cooperation_agreement` ativo deve ter um binding ativo referenciando a Política (`doc_type='policy'`). **Gated em `cooperation_addendum` ativo (ratificado): dormente até o Adendo importar a Política nos acordos.** Pré-ratificação, nenhum instrumento ratificado obriga os acordos a pinar a Política — forçar o pin manufaturaria um vínculo sem consentimento da contraparte (achado do legal-counsel; Art. 104, II CC/02). Severity `high` (correto para o estado pós-ratificação). Baseline 0 (hoje dormente; os 4 pins existem de qualquer modo).

**5. Amenda ADR-0016:** o pin é `document_version_id` imutável (não label), **por-instância** (par bound/referenced). `approval_signoffs.referenced_policy_version_id` permanece **snapshot de auditoria** ("versão corrente no momento da assinatura"), **NÃO** o SSOT do binding — manter separado para não reintroduzir remissão dinâmica.

## Pin antecipatório (caráter jurídico — revisão do legal-counsel incorporada)

Os 4 pins são **registros preventivos / antecipatórios**, não declarações de vínculo vigente:
- O `pin_clause_ref` e a descrição da invariante AN afirmam **explicitamente** que o Adendo está `under_review`, que os acordos não citam a Política, e que **nenhuma obrigação contratual vincula os acordantes até a ratificação do Adendo**. (A revisão adversarial pegou versões anteriores que afirmavam, no presente, que o Adendo "importa a Política" / "resolve hoje" — corrigidas.)
- Quando a Política/Adendo ratificarem (possível versão posterior), uma Material change da Política dispara `re_anchor_required` e o GP **re-ancora expressamente** via `reanchor_instrument_binding` citando o ato de ratificação.
- O auto-advance editorial produz **efeito jurídico pleno apenas após a ratificação do Adendo** (antes, os parceiros não adotaram o regime §12.3). O risco é baixo (versão editorial da Política antes da ratificação é improvável) e o `notes` da row auto-advanced não afirma ratificação.
- **Questão aberta (SPEC §9.7, escopo PR-3):** uma Material change da Política dispara só `re_anchor_required` no pin (comportamento desta PR) ou também exige aditamento assinado dos 4 acordos bilaterais? Resposta do legal/PM antes do go-live do Adendo.

## Alternativas rejeitadas

- **Backfill "versão na data de assinatura" (SPEC §9.3 literal):** não existe — a Política não tinha versão lacrada quando os acordos foram assinados.
- **1 binding Adendo→Política** (mais preciso juridicamente): não honra o critério de aceite "4 acordos com binding ativo" e fixaria um instrumento `under_review`. (Apresentado ao PM, rejeitado.)
- **Backfill 0 / só schema (dormente):** não cumpre o critério de aceite. (Apresentado, rejeitado.)
- **Invariante AN sempre-ativo (sem gate de Adendo ratificado):** manufatura pressão para pinar novos acordos sem base contratual ratificada (legal-counsel). Gated em `cooperation_addendum` ativo.
- **UPDATE in-place do pin no auto-advance:** quebra append-only (§4.1); perde o histórico de pins.
- **Pin = label de texto (`consent_records.policy_version` style):** é remissão dinâmica disfarçada (invariante §4.8). `pinned_version_id` é FK dura a `document_versions`.

## Consequências

- 4 bindings ativos pós-backfill (verificado: cada acordo→Política, pinado em `v2.7-p128` lacrado; `re_anchor_required=false`). `check_schema_invariants()` = 0 (AN dormente, count 0). Behavior-neutral salvo o backfill.
- O subsistema de version-pin está pronto; PR-5 (versão regente por obra) e PR-3/PR-4 reusam `change_class` (PR-1) + este pin. O trigger fica dormente até uma versão classificada lacrar.
- **Limitação conhecida:** a invariante AN verifica "qualquer policy doc", não "a Política de PI" especificamente (hoje há exatamente 1 doc `doc_type='policy'`). Se um 2º doc `policy` for criado, tightenar a invariante (`doc_type='ip_policy'` subtype ou match de título).
- Contract test `tests/contracts/571-pr2-camada5-version-pin.test.mjs` (estático + DB-aware) trava o subsistema no CI.

## Mecânica de apply (registro)

Migration aplicada via **Supabase Management API `/database/query`** (mesmo backend do `apply_migration` MCP), POSTando os **bytes exatos do arquivo local** — garante `file == live` (body-drift gate verde) sem reprodução manual da função `check_schema_invariants()` de ~600 linhas e **sem phantom row** (a API não toca `schema_migrations`). Versão registrada via `supabase migration repair --status applied 20260805000302`. `supabase db push` é inviável neste repo (o `schema_migrations` remoto tem centenas de versões históricas pré-renumeração sem arquivo local).
