# ADR-0078 — External Reviewer Onboarding & Access Pattern

**Status:** PROPOSED
**Date:** 2026-05-10 (p148)
**Author:** Claude (drafted) · PM/Council review pending
**Supersedes:** none
**Related:** ADR-0006 (Person + Engagement Identity Model) · ADR-0007 (Authority as Engagement Grant) · ADR-0008 (Engagement Lifecycle Config) · ADR-0070 (External Speaker Artifact Conventions) · ADR-0076 (PMI 3-d Volunteer Model + Phase B Base Legal) · `feedback_lawyer_pathway_angelina_pmi_go.md`

---

## Contexto

### Driver

Curadores externos de governance documents (a primeira persona é **Ângelina Ourem**, advogada voluntária PMI-GO, R$ 0/h por convenção da diretoria do capítulo) hoje revisam Política IP / cooperation agreements offline via DOCX export (shipped p128 D2, commit `b8c3e24`). Esse fluxo perde provenance: comentários voltam por email, são re-digitados manualmente em `document_comments`, e a auditoria fica fragmentada entre o ChainCommentDrawer (provenance via `from_version_id`/`is_inherited`) e a thread de email da curadora.

T-15 (LOW-MEDIUM no batch p128) propôs eliminar o atrito permitindo que reviewers externos comentem diretamente na plataforma — sem onboarding pleno de membro, sem autoridade de assinatura.

### O que já está em produção

A camada de schema foi shipped na sessão p130:

- **Migration `20260518130000_p130_t15_external_reviewer_engagement_kind.sql`** (applied)
- `engagement_kinds` row: `slug='external_reviewer'`, `legal_basis='consent'`, `requires_agreement=true` (template `external_reviewer_agreement_v1` referenciado mas não criado), `default_duration_days=90`, `max_duration_days=365`, `retention_days_after_end=730`, `is_initiative_scoped=false`, `anonymization_policy='anonymize'`, `renewable=true`, `auto_expire_behavior='notify_only'`, `notify_before_expiry_days=14`, `created_by_role={manager}`, `revocable_by_role={manager}`
- `engagement_kind_permissions` row: `('external_reviewer', 'reviewer', 'participate_in_governance_review', 'organization', ...)`

Este ADR **não re-litiga** essas decisões de schema (locked). A camada user-facing — invite, autenticação, UI, revoke, NDA, audit — segue aberta. Este documento spec'a essa camada.

### Distinção crítica: external_signer vs external_reviewer

| Aspecto | `external_signer` (existente, ADR-0016) | `external_reviewer` (este ADR) |
|---|---|---|
| Autoridade | **Assina** gates específicos (`gate_kind='external_signer'`) | **Comenta**; nunca assina (fail-closed via gates checking designations) |
| Persona típica | Presidente capítulo PMI federado, signatário institucional | Advogada voluntária PMI-GO, peer-reviewer técnico, especialista convidado |
| Legal basis | `legitimate_interest` (vínculo institucional formal) | `consent` (revisão pode ser sobre conteúdo pre-publication; consentimento explícito ao termo) |
| Retention | Default kinds (1825d) | 730d (2y, alinhado com candidate; LGPD-min para conteúdo pre-publication) |
| Lifecycle | Revoga após sign event | Renewable; `auto_expire_behavior='notify_only'` |
| Magic-link | Phase IP-3 EF (existente) | Reutilizar mesmo EF — escopo no `redirect_to` (D2 abaixo) |

---

## Decisão

### D1 — `create_external_reviewer_invite` RPC

Mirror semântico de `create_external_signer_invite`. Mesmo gate (`manage_member`), mesma estrutura person + member + engagement, mas:

- `engagement_kind='external_reviewer'`, `role='reviewer'`
- `start_date=CURRENT_DATE`, `end_date=CURRENT_DATE + interval '90 days'` (default; admin pode override até `max_duration_days=365`)
- `legal_basis='consent'`, `is_authoritative=true`
- `consent_status='pending_magic_link'`, `consent_version='v1-external-reviewer'`
- `operational_role='external_reviewer'` (novo valor — adicionar à enum `members.operational_role` SE ainda não existir; verificar em V4 cache)
- `member_status='active'`, `is_active=true`, `chapter='EXTERNAL'`
- `metadata.review_scope` (per JSONB schema seedado): `'legal' | 'technical' | 'editorial' | 'peer'` (required)
- `metadata.review_target_doc_type`: opcional, FK lógica para `governance_documents.doc_type`
- `metadata.organization_affiliation`: free text (ex: "PMI-GO Diretoria Jurídica")

Audit log: `action='external_reviewer_invite_created'`, `target_type='member'`.

Returns: `{success, person_id, member_id, email, magic_link_url}` (URL gerada inline via Supabase Auth admin API ou enfileirada via campaign_send_one_off).

### D2 — Magic-link auth flow

**Reutilizar pattern Phase IP-3 EF existente** (mesma EF que dispara magic-link para `external_signer`). Diferenças:

- `redirect_to=https://nucleoia.vitormr.dev/external/governance/<chain_id>` (D3 abaixo)
- Email template `magic_link_external_reviewer_v1` (novo) — body distinto:
  - Saudação personalizada (`{{first_name}}`)
  - Contexto do convite ("Você foi convidado a revisar o documento `{{document_title}}` versão `{{version_label}}` por `{{inviter_name}}`")
  - Link de revisão única (single-use, expira em 24h após first click; sessão Supabase expira em `engagement.end_date`)
  - Lembrete sobre o termo de revisão (`{{agreement_url}}`) — ratificação obrigatória ANTES do primeiro comentário (D4 abaixo)
  - Footer: revisor pode pedir cancelamento via reply

Token security: leverage Supabase Auth magic-link infra (HMAC-signed, server-validated). NUNCA gerar token custom.

### D3 — Landing page `/external/governance/[chainId]`

Nova rota (`src/pages/external/governance/[chainId].astro`) — fora de `/admin/`:

- Layout: `BaseLayout.astro` (não `AdminLayout` — sem sidebar admin, sem nav cross-section)
- Header minimalista: logo Núcleo + título "Revisão externa de documento" + indicação do tempo restante (`engagement.end_date - now()`)
- Body: `<ReviewChainIsland client:load chainId={chainId} variant="external" />` (D4)
- Footer: link para suporte (e-mail institucional do GP, configurado via env) + link para o termo (D5)

Acesso:
- Se não autenticado → redirect para login com `?redirect_to=` preserve
- Se autenticado mas SEM `external_reviewer` engagement ativo apontando para esse chain (via `chain.document_id → document.organization_id`) → 403 com mensagem "Acesso de revisor expirado ou não autorizado"
- Se ratificação do termo (D5) pendente → redirect inline para `/external/agreement/[engagement_id]` (full-screen ratification, similar ao ip-agreement.astro pattern)

### D4 — `ReviewChainIsland` scoped variant `external`

Adicionar prop `variant?: 'admin' | 'external'` (default `'admin'`):

- `variant='external'`:
  - **Hide:** painel de gates (assinatura), botões "Assinar como X", auditoria por gate, recirculation control
  - **Show:** documento (current version), VersionDiffViewer (se houver prevVersion), ClauseCommentDrawer (full)
  - `canComment=true` (sempre — é o ponto)
  - `isCurator=false`, `isSubmitter=false` (reviewer externo é uma terceira persona; visibility de comments fica `public` por default)
  - Banner topo: "Você está revisando como `{{role}} ({{review_scope}})`. Comentários ficam públicos para a equipe Núcleo. Sessão expira em `{{end_date}}`."

Implementação: branch nas 3 seções condicionais por `variant === 'admin'`. Diff esperado: ~80-120L em `ReviewChainIsland.tsx`. Zero regressão admin (default preservado).

### D5 — `external_reviewer_agreement_v1` NDA-lite template

Novo `governance_documents` row (não `approval_chain` — é template estático, não revisado):

- `slug='external_reviewer_agreement_v1'`, `title='Termo de Revisão Externa — Núcleo IA & Project Management'`, `doc_type='agreement_template'`
- Conteúdo (PT-BR canonical, EN/ES traduzidos posteriormente):
  - Cláusula 1: Objeto — direito não-exclusivo de visualização e comentário em documentos específicos atribuídos pela coordenação
  - Cláusula 2: Confidencialidade — não divulgar conteúdo pre-publication a terceiros sem autorização escrita
  - Cláusula 3: Propriedade Intelectual — comentários submetidos integram o histórico do documento (`document_comments` provenance) sem cessão de direitos do revisor sobre suas próprias contribuições. Revisor concede licença não-exclusiva à Núcleo para uso interno dos comentários no ciclo de revisão.
  - Cláusula 4: Vigência — alinhado com `engagement.end_date` (90d default, renovável). Revogação imediata por qualquer parte via comunicação por escrito.
  - Cláusula 5: LGPD — base legal `consent` (Art. 7º I); dados pessoais (nome, email, comentários) retidos por 2 anos pós-engagement (`retention_days_after_end=730`); anonimização automática após. Revisor pode solicitar export ou deleção a qualquer tempo (canal institucional do controlador ou portal LGPD).
  - Cláusula 6: Não-vínculo — termo NÃO cria relação trabalhista, voluntariado formal (sem VEP), nem direito a credly badge. Revisor externo é uma figura específica para o ciclo de revisão.

Ratificação: nova RPC `sign_external_reviewer_agreement(engagement_id, version_label)` — insere row em `external_reviewer_agreements` (nova tabela mínima: `id, engagement_id FK, agreement_version, signed_at, ip_address, user_agent`). Required ANTES do primeiro `create_document_comment` chamado por external_reviewer (gate na RPC: `_can_comment_as_external(member_id, version_id)` checks ratification).

**Legal-counsel review obrigatório antes do template ir para active.** Ângelina pode ser a curadora desse termo (validação cruzada: ela é a primeira usuária E a primeira reviewer juridica).

### D6 — `revoke_external_reviewer` RPC + admin UI

RPC: `revoke_external_reviewer(p_engagement_id uuid, p_reason text)`:

- Gate: `manage_member`
- Sets `engagements.status='offboarded'`, `engagements.end_date=CURRENT_DATE`
- Sets `members.is_active=false` (se NÃO houver outros engagements ativos para o mesmo `person_id`)
- Invalida sessões Supabase Auth do auth_user vinculado (via admin API `auth.admin.signOut`)
- Audit: `action='external_reviewer_revoked'`, `metadata.reason`

UI: card no admin/governance ou novo `/admin/external-reviewers` listando todos external_reviewer engagements ativos com botão "Revogar" + campo razão obrigatório.

### D7 — Audit + observability

Todo acesso de external_reviewer logs duplo:

- `mcp_usage_log` (se via MCP — improvável para reviewer; ignorar)
- `admin_audit_log` com `actor_type='external_reviewer'` (novo valor — adicionar à enum/check) sempre que reviewer externo:
  - Cria comment
  - Visualiza documento (heavy? talvez log apenas first-view + last-view por sessão para evitar spam)
  - Revoga próprio acesso

Operational dashboard adendum: nova section em `/admin/governance/documents` (T-14 ja trilingue) listando "Revisores externos ativos" — counts por chain, próximos a expirar (<14d), revogados recentemente.

### D8 — Sequência de implementação proposta

1. **Wave 1 (~2h):** D1 RPC + D5 template (sem ratification — versão minimal para teste). Smoke via MCP.
2. **Wave 2 (~2h):** D2 magic-link EF + D3 landing page (mock variant). Magic-link end-to-end test com email teste.
3. **Wave 3 (~3h):** D4 ReviewChainIsland variant='external'. Real reviewer test com Ângelina (Vitor convida).
4. **Wave 4 (~1h):** D5 ratification flow + RPC gate em create_document_comment.
5. **Wave 5 (~1h):** D6 revoke RPC + UI.
6. **Wave 6 (~1h):** D7 audit additions + dashboard section.
7. **Total: ~10h** (vs estimativa original 3-4h em p128 — refinada após descobrir schema parcial + escopo NDA real).

---

## Consequências

### Positivas

- **Elimina DOCX offline workflow** — provenance, single source of truth, audit completo
- **Habilita Ângelina + futuros peer-reviewers** sem onboarding completo de membro
- **Reusa pattern existente** (external_signer Phase IP-1/IP-3) — magic-link infra, person+member+engagement model, audit hooks
- **LGPD-clean by design** — base legal `consent`, retention 2y, anonymização auto
- **Reduz ciclo governance** — 1 ciclo de revisão Política IP hoje gasta 2-3 dias entre export+comentário+re-import; in-platform reduz para hours

### Negativas / riscos

- **Surface area de auth aumenta** — magic-link path adiciona vetor de phishing potencial. Mitigação: links single-use + 24h expiry + warning anti-phishing no email body
- **Gestão de NDA template requer legal-counsel sign-off** — pré-requisito para shipping D5
- **Operational overhead** — admin precisa convidar manualmente cada reviewer (não há self-signup). Aceitável para volume esperado (<10 reviewers ativos simultaneamente)
- **Risco de comments inadequados** — reviewer externo pode comentar em escopo errado. Mitigação: review_scope no metadata + UI banner contextual
- **Possível confusão com external_signer** — UI/docs precisam distinguir explicitamente

### Quebras de invariantes potenciais

- `members.operational_role` enum precisa de novo valor `external_reviewer` — verificar se existe; se não, ALTER TYPE (migration). Risk: V4 cache trigger pode ignorar valor não-mapeado. Test obrigatório pré-prod.
- `actor_type` em `admin_audit_log` precisa aceitar novo valor — verificar CHECK constraint atual.

---

## Alternativas consideradas

### A) Manter DOCX export-only (status quo)

- ❌ Atrito permanente, perde provenance, incompatível com sucessores estratégicos PMI-CE pilot.

### B) Convidar reviewer como `guest` engagement_kind

- ❌ guest é genérico (acesso temporário limitado, 30d default). Não tem permissions específicas para governance review. Não tem NDA template. Não tem retention 2y.

### C) Convidar como member completo (volunteer × researcher)

- ❌ Overhead onboarding excessivo (VEP, agreement de voluntariado, badge credly, gamification). Reviewer não é voluntário Núcleo — é especialista terceiro.

### D) Reusar `external_signer` para comment-only

- ❌ Conflito de autoridade: external_signer assina chains. Reviewer NÃO deve poder assinar. Misturar levaria a privilege confusion + risk de assinatura acidental.

### E) **external_reviewer dedicated kind (esta ADR)** ✅

- Schema isolado, permissions mínimas, NDA-lite template, retention LGPD-min, fail-closed em sign gates.

---

## Critérios de aceite

- [ ] D1 `create_external_reviewer_invite` RPC implementado + smoke (MCP execute_sql)
- [ ] D2 magic-link template + EF dispatch funcional + email teste recebido
- [ ] D3 `/external/governance/[chainId]` rota + redirects validados (não-auth, sem-engagement, ratification-pending)
- [ ] D4 `ReviewChainIsland` variant='external' rendering correto + admin variant inalterado (regression test)
- [ ] D5 `external_reviewer_agreement_v1` aprovado por **legal-counsel** (Ângelina ou external advisor)
- [ ] D5 ratification flow funcional + gate em create_document_comment para external_reviewer
- [ ] D6 revoke RPC + admin UI + sessão Supabase invalidada confirmada
- [ ] D7 audit logs gravados em admin_audit_log com `actor_type='external_reviewer'`
- [ ] End-to-end test: Vitor convida Ângelina → Ângelina recebe email → ratifica termo → comenta em chain → admin revoga → Ângelina perde acesso
- [ ] LGPD: Ivan DPO sign-off no fluxo (consent flow + retention + anonymization)

---

## Anti-patterns (PR review checklist)

1. **NÃO bypassar V4 authority** — toda RPC nova checa `can_by_member()` ou helper específico. Não inline `WHERE operational_role = 'external_reviewer'`.
2. **NÃO permitir external_reviewer em sign gates** — `_can_sign_gate` deve continuar checando designations específicas que reviewer NÃO tem por convenção. Test obrigatório: external_reviewer tenta `sign_ip_ratification` → must fail.
3. **NÃO persistir token magic-link em URL após first use** — Supabase Auth single-use é o contrato.
4. **NÃO estender retention além de 730d sem novo consent** — auto-anonymize cron é load-bearing.
5. **NÃO permitir self-signup external_reviewer** — somente via invite RPC gateada por manage_member.
6. **NÃO emitir credly badge para external_reviewer** — não é voluntário; explicitamente excluído da gamification pipeline.

---

## Rollback

Se feature precisa ser retirada:

1. `revoke_external_reviewer` em todos engagements ativos (com razão `'feature_rollback'`)
2. `UPDATE engagement_kinds SET status='deprecated' WHERE slug='external_reviewer'` (se status column exists; senão, soft-delete)
3. `DELETE FROM engagement_kind_permissions WHERE kind='external_reviewer'`
4. Remover rota `/external/governance/[chainId]` + componente variant
5. Remover RPCs `create_external_reviewer_invite`, `revoke_external_reviewer`, `sign_external_reviewer_agreement`
6. Marcar `external_reviewer_agreement_v1` como `superseded`
7. Anonimizar dados de external_reviewers passados via cron LGPD (retention já cobre — natural decay)

Reversibilidade: ~2h para rollback completo. Engagements existentes sobrevivem como histórico até retention expirar.

---

## Relações

- **Estende:** ADR-0006 (Person + Engagement Identity Model) — external_reviewer é nova engagement kind no modelo
- **Usa:** ADR-0007 (Authority as Engagement Grant) — permissão via engagement_kind_permissions
- **Usa:** ADR-0008 (Engagement Lifecycle Config) — auto_expire_behavior, renewable, retention
- **Análogo a:** ADR-0070 (External Speaker) — pattern de pessoa externa com escopo limitado
- **Coordena com:** ADR-0076 (PMI 3-d Volunteer + Phase B) — base legal consent vs legitimate_interest distinção
- **Inspirado por:** Phase IP-1/IP-3 external_signer pattern (não tem ADR dedicado; documentado em migration headers)

---

## Ledger histórico

- 2026-05-09 (p130): Schema layer shipped — migration `20260518130000_p130_t15_external_reviewer_engagement_kind.sql` aplicada. engagement_kind + permission seedados. Plumbing user-facing deferida.
- 2026-05-10 (p148): ADR drafted após T-15 partial-ship descoberto via verify-before-pick rule. Status PROPOSED, awaiting PM + legal-counsel + DPO review (Ivan).
