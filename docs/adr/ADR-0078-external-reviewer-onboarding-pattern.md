# ADR-0078 — External Reviewer Onboarding & Access Pattern

**Status:** PROPOSED — Round 2.5 (legal-counsel parecer incorporado; pending Ângelina curation + Ivan DPO sign-off)
**Date:** 2026-05-10 (p148, Round 1 → Round 2 → Round 2.5 same session)
**Author:** Claude (drafted) · PM aprovou 5/5 decisions Round 2; legal-counsel parecer (`docs/council/decisions/2026-05-10-p148-legal-counsel-adr0078-external-reviewer-nda.md`) incorporado Round 2.5; Ângelina curation + Ivan DPO sign-off pendentes para Round 3
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
- `operational_role='external_reviewer'` — **novo valor (PM-confirmed Round 2)**. Adicionar via migration:
  - Se `operational_role` for enum: `ALTER TYPE operational_role_enum ADD VALUE 'external_reviewer'`
  - Se for text + CHECK: alterar CHECK constraint para incluir `'external_reviewer'`
  - Atualizar `sync_operational_role_cache` trigger para mapear engagement_kind='external_reviewer' → operational_role='external_reviewer' (V4 cache, ADR-0007)
  - Test obrigatório pré-prod: criar engagement → trigger fire → cache atualizado corretamente
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
  - **Show:** documento (current version), VersionDiffViewer (se houver prevVersion), ClauseCommentDrawer (filtrado — ver visibility scope abaixo)
  - `canComment=true` (sempre — é o ponto)
  - `isCurator=false`, `isSubmitter=false` (reviewer externo é uma terceira persona)
  - Banner topo: "Você está revisando como `{{role}} ({{review_scope}})`. Comentários ficam visíveis para a equipe Núcleo + outros revisores. Sessão expira em `{{end_date}}`."

**Visibility scope para external_reviewer (PM-confirmed Round 2):**

| Visibility | Externo lê? | Externo escreve? |
|---|---|---|
| `public` | ✅ sim | ✅ sim (default ao publicar) |
| `curator_only` | ❌ **NÃO** — fail-closed | ❌ não |
| `submitter_only` | ❌ não | ❌ não |
| `change_notes` | ❌ não (notas internas do GP) | ❌ não |

Implementação: `list_document_comments` RPC ganha branch — se caller é `external_reviewer` (`person_id` linkado a engagement_kind=external_reviewer ativo), filtra `WHERE visibility = 'public'`. Default visibility no comment form do externo é `public` (não há outras opções no dropdown). Migrações de RLS em `document_comments` precisam refletir esse fail-closed (não delegar só ao RPC — defense-in-depth).

Implementação: branch nas 3 seções condicionais por `variant === 'admin'`. Diff esperado: ~80-120L em `ReviewChainIsland.tsx`. Zero regressão admin (default preservado).

### D5 — `external_reviewer_agreement_v1` NDA-lite template

Novo `governance_documents` row (não `approval_chain` — é template estático, não revisado):

- `slug='external_reviewer_agreement_v1'`, `title='Termo de Revisão Externa — Núcleo IA & Project Management'`, `doc_type='agreement_template'`
- Conteúdo (PT-BR canonical, EN/ES traduzidos posteriormente; **versão Round 2.5 pós-legal-counsel parecer**):
  - **Cláusula 1: Objeto** — direito não-exclusivo de visualização e comentário em documentos específicos atribuídos pela coordenação.
  - **Cláusula 2: Confidencialidade** — não divulgar conteúdo pre-publication a terceiros sem autorização escrita. *[Round 2.5 IS-1 nota inline para Ângelina considerar]:* avaliar se cláusula deve adicionar "exceto colaboradores diretos sob mesmo dever profissional de sigilo" para cobrir orientadores acadêmicos, sócios de escritório, ou co-autores legítimos.
  - **Cláusula 3: Propriedade Intelectual (IC-2 incorporado Round 2.5):**

    "Os comentários submetidos pelo Revisor integram o histórico do documento na plataforma (provenance de auditoria), sem cessão de direitos autorais do Revisor sobre o conteúdo de seus comentários. O Revisor concede à Núcleo IA & GP licença não-exclusiva, gratuita, de uso interno e irrevogável exclusivamente para fins de revisão do documento objeto deste Termo, pelo prazo do Engajamento acrescido do período de retenção (2 anos). A Núcleo não citará comentários nominalmente em publicações externas sem autorização escrita prévia do Revisor. Para revisores em vínculo acadêmico (Cenário C), reserva-se o direito de negociar cláusula adicional de co-autoria ou acknowledgment antes da ratificação deste Termo."

    *Justificativa Round 2.5:* Lei 9.610/98 Art. 49 exige interpretação restritiva — escopo de uso prévio + ressalva acadêmica + vedação de citação nominal sem autorização eliminam ambiguidade. Mitiga risco deontológico OAB para Cenário A (Ângelina advogada) e tensão Princípio 7 ADR-0076 (Trentim firewall — comentários jurídicos não viram "assessoria pública" sem opt-in).
  - **Cláusula 4: Vigência** — alinhado com `engagement.end_date` (90d default, renovável). Revogação imediata por qualquer parte via comunicação por escrito. *[Round 2.5 IS-2 nota inline]:* avaliar com Ângelina se inserir "salvo por justa causa, a revogação administrativa notificará o Revisor com antecedência mínima de 48 horas" para proteção do revisor em fim de revisão em andamento.
  - **Cláusula 5: LGPD (IC-1 + 3 gaps incorporados Round 2.5):**

    "O tratamento de dados pessoais do Revisor (nome, email, conteúdo de comentários, metadados de acesso) tem como base legal o consentimento expresso (Art. 7º, I, Lei 13.709/2018 — LGPD). Os dados são retidos por 2 (dois) anos após o término do Engajamento (`retention_days_after_end=730`), prazo necessário para fins de auditoria de governança documental, sendo anonimizados automaticamente após esse período (`anonymization_policy='anonymize'`).

    **Identidade do Controlador:** Núcleo IA & GP, núcleo de pesquisa institucional vinculado ao **PMI Goiás (PMI-GO Chapter)**. Encarregado de Proteção de Dados (DPO) institucional: **Ivan** (contato via canal institucional indicado na plataforma e portal LGPD do PMI-GO).

    **Direitos do titular (Art. 18 LGPD):** O Revisor tem os direitos de (i) confirmação da existência de tratamento, (ii) acesso aos dados, (iii) correção de dados incompletos, inexatos ou desatualizados, (iv) anonimização, bloqueio ou eliminação de dados desnecessários, excessivos ou tratados em desconformidade, (v) portabilidade dos dados, (vi) eliminação dos dados tratados com base no consentimento, (vii) informação sobre entidades públicas e privadas com as quais o Controlador realizou uso compartilhado de dados, (viii) informação sobre a possibilidade de não fornecer consentimento e sobre as consequências da negativa, (ix) revogação do consentimento, todos exercíveis pelo canal institucional indicado acima.

    **Revogação a qualquer tempo (Art. 8º, §5º LGPD):** O Revisor pode revogar este consentimento a qualquer momento, sem ônus, mediante uso da função 'Encerrar minha revisão' disponível na plataforma ou por comunicação escrita ao endereço institucional do Controlador. A revogação encerra imediatamente o acesso à plataforma. Dados já registrados permanecem sujeitos ao prazo de retenção de 2 (dois) anos para fins de auditoria, após os quais são anonimizados automaticamente."

    *Justificativa Round 2.5:* IC-1 (Art. 8º §5 nomeado expressamente — alinha template com self-revoke implementado em D6); 3 LGPD audit-gaps fechados (Controlador nomeado com chapter PMI-GO, DPO Ivan referenciado, Art. 18 completo com 9 direitos enumerados). Pendente Ivan DPO sign-off para confirmar (a) identificador institucional preciso (CNPJ se aplicável), (b) URL canônica do canal institucional/portal LGPD, (c) prazo de resposta a solicitações (Resolução CD/ANPD 2/2022 orienta 15 dias — opcional mas defensável).
  - **Cláusula 6: Não-vínculo + escopo restrito** — termo NÃO cria relação trabalhista, voluntariado formal (sem VEP), nem direito a credly badge. Este termo destina-se exclusivamente a revisores externos voluntários ou peer-reviewers em vínculo recíproco (cenários A/B/C abaixo). Engajamentos comerciais (consultoria remunerada), parcerias institucionais (sponsors), ou instrumentos com órgãos públicos requerem instrumento jurídico próprio (MSA, MOU, convênio) — não esse template. *[Round 2.5 IS-4 nota inline]:* avaliar com Ângelina se incluir "A Núcleo poderá mencionar o Revisor em agradecimentos públicos de documentos revisados, salvo manifestação em contrário do Revisor no ato da ratificação" — positivo para revisores que valorizam acknowledgment de portfolio.
  - **Cláusula 7 (opcional, IS-3 nota inline):** se Ângelina entender necessário para clareza geográfica, adicionar "As eventuais controvérsias decorrentes deste Termo seguem a legislação brasileira aplicável." Foro de eleição pode ser omitido em template volunteer-grade.

**Cenários cobertos vs excluídos (PM-confirmed Round 2):**

| # | Cenário | NDA-lite cabe? | Razão |
|---|---|---|---|
| **A** | Curador externo voluntário PMI (ex: Ângelina advogada PMI-GO) | ✅ default | Vínculo voluntário PMI culture; pre-publication; IP review |
| **B** | Peer-reviewer técnico inter-chapter (ex: Roberto PMI-CE) | ✅ sim | Reciprocidade volunteer + interesse mutuo |
| **C** | Academic peer-reviewer (orientador acadêmico) | ✅ sim | Pode requerer tweak Cláusula 3 se academic norms exigem co-authorship |
| **D** | Consultor remunerado (advogado externo contratado) | ❌ não — usar MSA + NDA comercial | Commercial relationship requires commercial instrument |
| **E** | Sponsor/partner (Microsoft, etc.) reviewing co-branded draft | ❌ não — usar partnership MOU | Partnership tem instrumento próprio (cooperation agreement) |
| **F** | Reviewer de instituição pública/governamental | ⚠️ case-by-case — escalar legal-counsel | LAI + transparência podem exigir convênio formal |
| **G** | Diretoria capítulo PMI federado (presidente assinando) | ❌ não — usar `external_signer` existente | Outro trilho legal (legitimate_interest, sign authority) |

**Gating no invite RPC (D1) reforçado:** UI do invite oferece dropdown:

```
Cenário do convite:
  ( ) Voluntário/peer-reviewer (default — usa NDA-lite v1)
  ( ) Outro caso (consultor remunerado, partner, gov) — escalar pra GP/legal antes
```

Se "Outro caso" selecionado, o RPC retorna `{error: 'requires_escalation', message: 'Use commercial NDA / MOU / convênio. Não criar engagement por este RPC.'}`. Sistema não permite NDA-lite ser usado fora dos cenários A/B/C.

Ratificação: nova RPC `sign_external_reviewer_agreement(engagement_id, version_label)` — insere row em `external_reviewer_agreements` (nova tabela mínima: `id, engagement_id FK, agreement_version, signed_at, ip_address, user_agent`). Required ANTES do primeiro `create_document_comment` chamado por external_reviewer (gate na RPC: `_can_comment_as_external(member_id, version_id)` checks ratification).

**Legal-counsel pré-revisão concluída Round 2.5** (`docs/council/decisions/2026-05-10-p148-legal-counsel-adr0078-external-reviewer-nda.md`): APROVADO COM AJUSTES. Issues críticos IC-1 (Cláusula 5 Art. 8 §5) + IC-2 (Cláusula 3 escopo licença + ressalva acadêmica) + 3 gaps LGPD (Controlador, DPO, Art. 18 completo) já incorporados na redação acima. Issues secundários IS-1, IS-2, IS-3, IS-4 marcados como notas inline para Ângelina avaliar na curadoria.

**Sequência de curadoria pós-Round 2.5:**

1. **Ângelina** recebe template v1.1 (versão atualmente neste ADR) com contexto explícito sobre conflict of interest natural (transparência = proteção mútua). Pedido especial: confirmar Cláusula 3 à luz de obrigações deontológicas OAB.
2. Consolidar **v1.2** com retorno dela; encaminhar a **Ivan DPO** focado exclusivamente nos 3 elementos LGPD pendentes de detalhe operacional: (a) CNPJ/identificador institucional preciso PMI-GO, (b) URL canônica do canal institucional/portal LGPD, (c) prazo de resposta a solicitações (15 dias Res. ANPD 2/2022 — opcional).
3. **Wave 1 (D5) só após etapas 1 + 2.**
4. IS-1 a IS-4: Ângelina absorve na curadoria ou ficam para v1.2 (não-bloqueantes).

Backup curator: external advisor (~R$ 5-10K) só se Ângelina declinar OU council/Ivan levantarem issue de governance no Round 3 sign-off.

### D6 — `revoke_external_reviewer` RPC + admin UI + **self-revoke (PM-confirmed Round 2)**

**Admin-revoke RPC:** `revoke_external_reviewer(p_engagement_id uuid, p_reason text)`:

- Gate: `manage_member`
- Sets `engagements.status='offboarded'`, `engagements.end_date=CURRENT_DATE`
- Sets `members.is_active=false` (se NÃO houver outros engagements ativos para o mesmo `person_id`)
- Invalida sessões Supabase Auth do auth_user vinculado (via admin API `auth.admin.signOut`)
- Audit: `action='external_reviewer_revoked'`, `target_type='engagement'`, `metadata={reason, revoked_by_actor_type:'admin'}`

**Self-revoke RPC (Round 2 add):** `self_revoke_my_external_reviewer_engagement(p_reason text DEFAULT NULL)`:

- Gate: caller `auth.uid()` deve ter active engagement_kind=external_reviewer (sem `manage_member` requirement)
- Mesmas mutations: status='offboarded', end_date=CURRENT_DATE, is_active=false (se único engagement)
- Sessão Supabase invalidada imediatamente (caller é forçado a logout no próximo request)
- Audit: `action='external_reviewer_self_revoked'`, `metadata={reason, revoked_by_actor_type:'self'}`
- Sem confirmação pesada — single button (no double-confirm modal). LGPD pattern: revogação de consentimento deve ser tão simples quanto a concessão.

**UI Locations:**
- **Admin:** card no admin/governance ou novo `/admin/external-reviewers` listando engagements ativos + botão "Revogar" + razão obrigatória.
- **External (variant):** botão discreto no header da landing `/external/governance/[chainId]`: "Encerrar minha revisão". Clica → modal leve com textarea opcional (não bloqueante) + "Confirmar encerramento". Nenhum admin-approval intermediário.

**Por que self-revoke importa (LGPD):** revogação de consentimento (Art. 8º §5º) deve ser facilitada pelo controlador. Se externo só pode pedir revogação por email manual ao admin, ANPD audit pode flagear como fricção indevida. Botão direto = compliance-clean.

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

- `members.operational_role` enum precisa de novo valor `external_reviewer` (D1 Round 2). ALTER TYPE migration + sync_operational_role_cache trigger update obrigatório. Test pré-prod: criar engagement → cache espelhado.
- `actor_type` em `admin_audit_log` precisa aceitar novo valor — verificar CHECK constraint atual.
- `document_comments` RLS policy precisa fail-closed para external_reviewer × non-public visibilities (D4 Round 2 defense-in-depth — não delegar só ao RPC).
- `list_document_comments` RPC ganha branch para external_reviewer (filtra `WHERE visibility='public'`). Test contractual: external_reviewer + curator_only comment → 0 rows.

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
- 2026-05-10 (p148, Round 1): ADR drafted após T-15 partial-ship descoberto via verify-before-pick rule. Commit `7f3b9be`. PROPOSED.
- 2026-05-10 (p148, Round 2 — same session): PM aprovou 5/5 decisions:
  - (1) Wave count: 6 OK
  - (2) NDA: scope explícito A/B/C cobertos, D-G excluídos; Ângelina cura
  - (3) `operational_role` enum: adicionar `external_reviewer`; trigger sync_operational_role_cache cobre
  - (4) Self-revoke: incluído (LGPD Art. 8 §5)
  - (5) Visibility: externos NÃO veem curator_only/submitter_only/change_notes; só `public`; default no comment form é `public`-único
- 2026-05-10 (p148, Round 2.5 — same session): legal-counsel parecer (council artifact `docs/council/decisions/2026-05-10-p148-legal-counsel-adr0078-external-reviewer-nda.md`). Veredito: APROVADO COM AJUSTES. PM aprovou caminho A. Incorporados:
  - IC-1 (Cláusula 5 Art. 8 §5 nomeado expressamente)
  - IC-2 (Cláusula 3 escopo de uso + ressalva acadêmica + vedação citação nominal)
  - 3 LGPD gaps (Controlador PMI-GO nomeado, DPO Ivan referenciado, Art. 18 com 9 direitos enumerados)
  - IS-1 a IS-4 marcados como notas inline para Ângelina avaliar
- Pending: Ângelina curation v1.1 → v1.2 + Ivan DPO sign-off (CNPJ/URL/prazo de resposta) → Round 3 (sign-off final + status ACCEPTED).
