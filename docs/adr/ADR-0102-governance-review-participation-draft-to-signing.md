# ADR-0102 — Governance review participation: read + comment from draft through signing (involved parties + Tier 2+)

- **Status:** Proposed (draft for council review — 2026-06-12)
- **Issue:** relates to #646 (draft preview no frontend — reader serves só current/locked), #625 (cohort/onboarding journey), #648/#653 (volunteer-term leak incident — the hardening this ADR must not undo)
- **Origin:** PM decision 2026-06-12 (Vitor): *"quem está envolvido nos documentos participa de comentário desde o draft, assim como Tier 2 pra cima — é um envolvimento deles, mesmo que não tenham necessidade de comentar ou de estar na rodada de assinatura, mas têm acesso, visibilidade e forma de opinar ativamente ainda em momento de idealização ou já em documento lacrado em fase de assinatura."*
- **Refs:** ADR-0041 (`participate_in_governance_review` é a action V4 do comentário), ADR-0007 (`can()`/`can_by_member()` source-of-truth de autoridade), ADR-0011 (V4 auth), ADR-0012 (schema consolidation/invariants), GC-162 (RLS/LGPD). Trio do fluxo: `get_pending_ratifications` / `_can_sign_gate` / `sign_ip_ratification`.

## Context

Hoje a plataforma **já desacopla comentar de assinar**, mas a participação de revisão é **estreita demais** e **tardia demais** para o valor que o PM quer (envolvimento desde a ideação). Estado aterrado em prod (`ldrfrvwhxsmgaabwmaik`, 2026-06-12):

1. **Comentar** (`create_document_comment(p_version_id, p_clause_anchor, p_body, p_visibility, p_parent_id)`): autoridade = `can_by_member(member, 'participate_in_governance_review')` (ADR-0041). **Não** checa se o membro é signatário nem se o gate dele está aberto → comentário já é, por design, independente de assinatura. `visibility ∈ ('curator_only','submitter_only','change_notes')`. `list_document_comments` mostra todos os comentários da versão a quem tem `participate_in_governance_review` (senão, só os próprios).
2. **Quem tem a capability hoje**: estreito — ~15 de 72 membros ativos (concentrado em `sponsor` 5/5, `manager` 2/2, `chapter_liaison` 3/4, +2 `researcher`, 1 `guest`, 1 `observer`, 1 `tribe_leader`). Não cobre "envolvidos na iniciativa" nem "Tier 2+" de forma sistemática.
3. **Ler o corpo** (`content_html`) é governado por RLS em `document_versions`, com dois regimes:
   - **Draft unlocked** (`locked_at IS NULL`): policy `document_versions_read_unlocked_drafts_admin` = `rls_can('manage_member')`. **Só o GP lê drafts em aberto.** É a fase de ideação — e é justamente onde está fechada.
   - **Versão locked**: policy `document_versions_read_published` = por `visibility_class` do doc (`public`/`active_members` → todo membro ativo; `legal_scoped` → só signatários; `admin_only` → `manage_member`; `audit_restricted` → `manage_platform`) **ou** `manage_member`.
4. **O modelo de tier** (app-layer `getAccessTier`, `src/lib/admin/constants.ts`): escada `superadmin > admin (manager/deputy_manager/co_gp) > leader (tribe_leader) > observer (sponsor/curator/chapter_liaison) > member (researcher/facilitator/communicator) > visitor (guest pelado)`. Org-chart: tier1 = GP+Deputy, tier2 = Patrocinadores e Pontos Focais, tier3 = Líderes de Tribo.
5. **"Envolvido no documento"** tem modelagem limpa: `governance_documents.initiative_id` → roster canônico V4 `v_initiative_roster` (NÃO `tribe_selections`, que é legado e drifta no offboard).

### A restrição que NÃO pode ser desfeita (incidente #648/#653)

O leak do termo de voluntário (2026-06-11) **não** foi "gente demais viu o doc". Foi um **card acionável de ASSINAR** empurrado a ~55 pessoas, incl. **25 guests pré-onboarding não-verificados**, porque `get_pending_ratifications` não impunha ordem de gate e o gate 5 `volunteers_in_role_active` (threshold `all`) ficava elegível a todo voluntário. O read-path foi corrigido (#653, capturado hoje em #656/#657). O **write-path continua furado (#654)**. Qualquer afrouxamento de leitura de draft tem que preservar a separação que o leak violou.

## Decision

Introduzir um regime de **participação de revisão de governança** que dá **leitura + comentário** a um público **escopado** — **(envolvidos na iniciativa do doc) ∪ (Tier 2+)** — **da fase de draft até a fase de assinatura**, governado por uma invariante dura:

> ### Invariante GR-1 — Visibilidade/comentário ≠ acionabilidade
> Ver o documento e comentar nele é aberto ao **público de revisão escopado**. O **CTA de assinar permanece gated** por `_can_sign_gate` + a lógica sequencial de `get_pending_ratifications` (read-path) **e** pelo write-path (#654, a fechar). Um revisor que não é signatário do gate vê o doc + comentários mas **nunca** vê "Revisar e assinar" nem gera uma `pending_ratification`. O leak confundiu as duas superfícies; este design as mantém ortogonais.

### Predicado de escopo (público de revisão de um doc)

```
review_audience(doc) :=
     member ∈ v_initiative_roster(doc.initiative_id)      -- envolvidos
  ∪  access_tier(member) >= <CORTE>                         -- Tier 2+ (a ratificar: 'observer' inclusivo)
  MENOS  access_tier(member) IN ('visitor')                 -- nunca visitor/guest pelado/não-verificado
  MENOS  membros não-verificados / pré-onboarding (coorte #625)
```

- **Corte de "Tier 2+":** proposta = `access_tier >= 'observer'` (inclui admin/leader/observer = GP/Deputy/co-GP + tribe_leaders + sponsors/curators/chapter_liaisons). **A ratificar pelo PM + security** se entra `member` (researcher) ou se para em `observer`.
- **Excluir sempre:** `visitor`/`guest` pelado e a coorte pré-onboarding não-verificada (os 25 guests ativos de hoje). Verificação live 2026-06-12: `member_affiliation_verifications` = **0 linhas**, 25 guests ativos — esta coorte **não** entra no público de revisão.

### Duas superfícies a mudar

| # | Superfície | Hoje | Alvo |
|---|---|---|---|
| A | **Ler draft unlocked** (`document_versions`, `locked_at IS NULL`) | só `manage_member` | nova RLS policy escopada a `review_audience(doc)` **e** `visibility_class` permitida |
| B | **Capability de comentar** (`create_document_comment` / `participate_in_governance_review`) | ~15 membros | concedida ao mesmo `review_audience` (via grant em `can()`/seed ou ampliação do gate do RPC) |

Ler sem comentar não basta; as duas andam juntas.

### Escopo por `visibility_class` (não-negociável, LGPD)

A abertura vale **só** para `visibility_class ∈ ('public','active_members')`. **NÃO** abrir `legal_scoped` (docs jurídicos assinados / PII), `admin_only`, `audit_restricted` — esses mantêm o regime atual. Defense-in-depth: o predicado de draft-read cruza `review_audience` **com** o allowlist de `visibility_class`.

## Non-goals

- **Não** dá poder de assinatura a ninguém (Invariante GR-1).
- **Não** abre docs `legal_scoped`/`admin_only`/`audit_restricted`.
- **Não** inclui visitor/guest/pré-onboarding não-verificado.
- **Não** resolve o write-path #654 (pré-requisito de segurança separado, mas relacionado — ver Consequências).
- **Não** é o preview de draft do #646 (esse é a superfície de *render*; este ADR é a *autoridade* por trás dela — os dois se encontram).

## Slices (1 PR cada, com QA/QC e tempo — execução pós-ratificação)

1. **Predicado + helper** (DB): `_can_review_document(member_id, document_id)` SECURITY DEFINER encapsulando `review_audience ∩ visibility_class allowlist`, com testes de exclusão (guest/visitor/pré-onboarding/legal_scoped). Contract test antes de qualquer policy.
2. **RLS A** (draft-read): nova policy `document_versions_read_drafts_review_audience` em paralelo à admin-only; ratchet de teste provando que o público novo lê e que os excluídos NÃO leem.
3. **Capability B**: conceder `participate_in_governance_review` ao `review_audience` (preferir grant em `can()`/seed sobre alargar o gate do RPC — manter source-of-truth única, ADR-0007). Reavaliar `visibility` dos comentários (talvez adicionar um nível visível ao público de revisão, hoje só curator/submitter/change_notes).
4. **Frontend**: superfície de leitura+comentário ancorado por cláusula para o público de revisão, na fase draft e na lacrada — encontra #646 (preview). Sem CTA de assinar para não-signatários (GR-1 no front).
5. **QA/QC + security review** (gate de release): security-engineer assina o predicado; contract tests provam GR-1 (nenhum sign-CTA/`pending_ratification` vaza para revisor não-signatário) + exclusão das coortes + scoping de `visibility_class`.

## Security & QA gates (obrigatórios antes de merge da Slice 2+)

- **security-engineer review** do predicado de escopo e das policies (domínio LGPD/RLS sobre doc de governança — superfície de incidente recente).
- Contract tests: (a) guest/visitor/pré-onboarding **não** leem draft; (b) `legal_scoped`/`admin_only` **não** abrem; (c) revisor não-signatário **não** vê sign-CTA nem gera `pending_ratification` (GR-1); (d) `v_initiative_roster` (não `tribe_selections`) é a fonte de "envolvido".

## Consequences

**Positivas:** envolvimento real desde a ideação (feedback barato antes do lock → menos rodadas R0x forçadas); coerente com o desacoplamento comentar≠assinar já existente; "Tier 2+ participa" vira regra sistemática, não capability ad-hoc de ~15.

**Custos/risco:** afrouxa RLS de governança (mitigado por GR-1 + scoping de visibility_class + exclusão de coortes + security review). **Dependência:** o write-path #654 deve ser fechado em paralelo — abrir leitura sem fechar a escrita de assinatura prematura amplia a superfície do mesmo incidente. **Recomendação:** sequenciar #654 (security) antes ou junto da Slice 2.

**Reversível:** as policies são aditivas; reverter = `DROP POLICY` + revogar o grant. Sem migração de dados.
