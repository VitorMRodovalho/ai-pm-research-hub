# ADR-0016: IP Ratification Governance Model — gates como data, autoridade em camadas

- Status: Accepted
- Data: 2026-04-20
- Aprovado por: Vitor (PM) em 2026-04-20 (sessão p32, defaults aceitos do plano IP-2)
- Autor: Vitor (PM) + Claude (comitê arquitetural) + platform-guardian (audit 20/Abr p32)
- Escopo: Formaliza as decisões arquiteturais do subsistema de ratificação de documentos de governança (CR-050 / IP Policy). Cobre modelo de aprovação multi-gate, assinatura externa, imutabilidade de versões, estratégia de autoridade em camadas e auditoria.

## Contexto

Phase IP-1 (sessão p30, commits `6646d3d` + `e14d30c` + `eef876b`) entregou foundation DB do subsistema de ratificação:

- 5 tabelas novas: `document_versions`, `approval_chains`, `approval_signoffs`, `document_comments`, `member_document_signatures`
- 2 invariants novos: J_current_version_published + K_external_signer_integrity
- 1 cert type: `ip_ratification`
- 1 engagement_kind: `external_signer`
- 4 RPCs: `_can_sign_gate`, `create_external_signer_invite`, `sign_ip_ratification`, `get_pending_ratifications`
- 12 policies RLS base
- 5 documentos v2.1 seeded + 4 approval_chains em `review`

O subsistema resolve um requisito novo: assinar documentos com peso legal (Política de PI, Termos de Compromisso, Adendos) em cadeias de aprovação multi-gate envolvendo atores internos (curadores, líderes, manager) e externos (5 presidentes de capítulos, AIPM Ambassadors internacionais). Guardian audit 20/Abr identificou este subsistema como não-coberto pelos ADRs 0001-0015 e recomendou documentação formal antes de Phase IP-2.

### Forças em tensão

1. **Peso legal vs agilidade operacional** — a IP Policy tem peso jurídico (parecer `2026-04-19-legal-counsel-ip-review.md`, APROVADO COM RESSALVAS, 6 P1 + 7 P2 + 4 Red Flags). Rows de versão, assinatura e ratificação precisam ser imutáveis e auditáveis. Ao mesmo tempo, o fluxo não pode bloquear o chapter presidente típico com 17 campos de formulário.

2. **Atores externos vs modelo V4 `engagements`** — 5 presidentes de capítulo não são volunteers, não aparecem em `members`/`persons` canonical paths, mas precisam de autoridade derivada e auditada igual aos internos. Não queremos uma tabela `external_approvers` paralela (ADR-0006 one-definition-per-entity).

3. **Gates como código vs gates como dados** — uma solução com `if role=curator then ...` mantém CI simples mas cria explosão quando adicionamos Ambassadors, Board members, observadores. Solução com gates em jsonb introduz 1 nível de indireção mas permite configuração sem migração.

4. **Autoridade canônica (`can()`) vs elegibilidade de assinatura** — ADR-0011 estabelece `can()` como única fonte de autoridade. Mas "este curator específico pode assinar esta cláusula específica deste documento específico?" é pergunta mais fina que `can_by_member('manage_member')` resolve.

5. **Transparência vs privacidade** — RLS policies iniciais (IP-1 migration `20260429040000`) abriram `approval_chains` e `approval_signoffs` com `USING (true)` para qualquer authenticated. Guardian flagou: precisa scopar para "chains onde o membro é signatário" ou "chains de documentos que o membro precisa ratificar". Transparência total pode vazar padrões comportamentais (quem demora a assinar, quem rejeitou o quê).

## Decisão

### D1 — Modelo de aprovação: **gates como dados** em `approval_chains.gates jsonb`

A cadeia de aprovação de uma versão é armazenada como array jsonb:

```json
[
  {"kind": "curator", "threshold": 1, "order": 1},
  {"kind": "leader", "threshold": 1, "order": 2},
  {"kind": "president_go", "threshold": 1, "order": 3},
  {"kind": "president_others", "threshold": 4, "order": 4},
  {"kind": "member_ratification", "threshold": null, "order": 5}
]
```

- `kind` é semantic enum (curator, leader, president_go, president_others, member_ratification, external_signer)
- `threshold` é quantos signoffs do kind são necessários; `null` = todos elegíveis
- `order` é sequência; gate N só é unlocked quando gate N-1 é satisfeito
- **Status de cada gate é COMPUTED** via query em `approval_signoffs` (não armazenado). `approval_chains.status` reflete o macro-estado (`draft`/`review`/`approved`/`active`/`withdrawn`/`superseded`).

**Consequência positiva**: adicionar um novo tipo de gate (ex: `board_member_ratification` para Conselho quando criado) não exige migration — é seed em engagement_kind_permissions + config no chain.

**Consequência negativa**: PM precisa ler jsonb para entender o fluxo de um chain específico. Mitigação: admin UI `/admin/governance/ip-ratification` renderiza o gate config visualmente.

### D2 — Atores externos: novo `engagement_kind = 'external_signer'`

Presidentes de capítulos e Ambassadors (que não são membros do Núcleo e não têm `member_status=active`) são modelados como:

1. `persons` row (sem `auth_id` inicialmente — magic link gera)
2. `members` row com `operational_role = 'external_signer'` + `member_status = 'alumni'` ou `inactive` (não-active para não contaminar rosters)
3. `auth_engagements` row com `kind = 'external_signer'` + scope opcional (`president_go`, `ambassador_us`, etc.)
4. RPC `create_external_signer_invite` gate: `can_by_member(caller, 'manage_member')`

**Invariant K_external_signer_integrity** garante que `members.operational_role='external_signer'` sempre tem row correspondente em `auth_engagements` com kind batendo.

**Consequência positiva**: reutilização completa do V4 authority model. External signer pode ser promovido a member full (flip de status + engagement kind change) sem mudança estrutural.

**Consequência negativa**: mistura conceitual — external signer aparece em `members` count raw. Mitigação: views `active_members` e `public_members` filtram por `member_status='active'`.

### D3 — Autoridade em camadas: `can()` para autoridade, `_can_sign_gate` para elegibilidade

Separação explícita:

| Camada | Pergunta | Implementação |
|---|---|---|
| **Autoridade** | "Pode invocar a RPC?" | `can_by_member(member_id, 'manage_member' \| 'write' \| ...)` — ADR-0011 canônico |
| **Elegibilidade de gate** | "Este signer pode satisfazer este gate específico neste chain?" | `_can_sign_gate(chain_id, gate_kind, member_id)` — domain-specific, hardcoded mapping role↔gate_kind |
| **Visibilidade** | "Pode LER este signoff?" | RLS policy visibility-scoped (D5 abaixo) |

`_can_sign_gate` NÃO viola ADR-0011 porque não gate geral de CRUD — é mapping de semantic gate kinds para attributes de member elegível. O caller ainda precisa passar `can_by_member` antes de chegar em `_can_sign_gate`.

### D4 — Imutabilidade de versões

`document_versions.locked_at IS NOT NULL` ⇒ row imutável via `trg_document_version_immutable` trigger. Campos bloqueados: `content_html`, `content_markdown`, `content_diff_json`, `version_number`, `version_label`, `document_id`, `locked_at`.

Invariant **J_current_version_published** garante que `governance_documents.current_version_id` sempre aponta para uma row com `locked_at IS NOT NULL`. Cache column `current_version_id` tem trigger sync.

`approval_signoffs` é **append-only** via `trg_approval_signoff_immutable` trigger (UPDATE bloqueado). Para "revogar" signoff, insere-se nova row com `signoff_type='rejection'`. Hash SHA-256 em `signature_hash` permite verificação post-hoc.

### D5 — Estratégia de autoridade para auditoria

**Audit trail tem 3 camadas complementares:**

1. **`approval_signoffs`** — auditoria de assinaturas (append-only, hash-verified, content snapshot).
2. **`admin_audit_log`** — auditoria de eventos de lifecycle de `document_versions` (publish, lock, superseded) via trigger `trg_document_version_audit`. Adicionado em Phase IP-2.
3. **`document_comments`** — discussão de autoria (visibility-scoped). Edições com window 15min via `document_comment_edits` sub-table (Phase IP-2).

`admin_audit_log` action naming: `document_version.published`, `document_version.locked`, `document_version.superseded`.

### D6 — Visibilidade RLS tightened

Remover `USING (true)` em `approval_chains` / `approval_signoffs` SELECT policies. Substituir por:

```sql
-- approval_chains SELECT:
USING (
  EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
          AND can_by_member(m.id, 'manage_member'))  -- admin
  OR id IN (SELECT approval_chain_id FROM approval_signoffs
            WHERE signer_id IN (SELECT id FROM members WHERE auth_id = auth.uid()))  -- é signer
  OR document_id IN (SELECT document_id FROM member_document_signatures
                     WHERE member_id IN (SELECT id FROM members WHERE auth_id = auth.uid()))  -- ratificou
  OR document_id IN (SELECT id FROM governance_documents WHERE status = 'active')  -- docs ativos visíveis a todos authenticated
)

-- approval_signoffs SELECT: mesma condição aplicada ao chain_id parent
```

**Consequência positiva**: member comum não vê quem demorou a assinar um Adendo privado.

**Consequência negativa**: queries de admin dashboard precisam JOIN com chains visíveis; RPC `get_pending_ratifications` já é SECURITY DEFINER então bypassa. Performance: chains/signoffs são low-volume (estimativa ~100-500 rows/ano).

### D7 — Certificate integration

Cada signoff de gate `member_ratification` emite `certificates` row com `type='ip_ratification'` via `sign_ip_ratification` RPC. Badge Credly opcional (out of scope IP-2, candidato IP-4). Certificate é a "entrega legal" da ratificação.

## Alternatives Considered

### A1 — Tabela dedicada por documento (rejeitada)
`ip_policy_signatures`, `ip_adendo_signatures`, `ip_cooperation_signatures` separate tables. Rejeitada: viola ADR-0009 (config-driven over per-case tables). 3 tabelas hoje, 10 amanhã, schema fragmentado.

### A2 — Gates hardcoded em enum (rejeitada)
`gate_kind` como CHECK enum ('curator', 'leader', ...). Rejeitada: adicionar novo kind exige migration. Conflita com D1 (dados > código).

### A3 — `external_signers` tabela separada (rejeitada)
Presidentes em tabela dedicada com próprio auth. Rejeitada: duplica modelo V4 (persons + auth_engagements), quebra ADR-0006 one-definition-per-entity, quebra `can()` single-source.

### A4 — Aprovação linear (rejeitada)
Um único aprovador = feito. Rejeitada: documentos de peso legal precisam multi-gate (curador reviewa texto, líder approva política, presidente autoriza cessão). Aprovação linear força hierarquia rígida.

### A5 — Signatures como `admin_audit_log` entries (rejeitada)
Reuso de `admin_audit_log` para signoffs. Rejeitada: signoff tem shape estruturado (hash, content_snapshot, sections_verified, comment_body) que não cabe em `action + details jsonb` genérico. Audit log fica para lifecycle events (D5 camada 2).

## Consequências

### Positivas
- Adicionar novo tipo de documento ou gate é config, não migration
- External signers reusam infraestrutura V4 (can, engagements, auth)
- Audit trail legal-grade (hash + content snapshot + append-only)
- Invariants J+K previnem drift silencioso
- Documento ratificado + certificate = prova legal integrada

### Negativas / Riscos
- gates jsonb não é type-safe no schema — mal-formação cabe em CHECK constraint separado (TODO IP-2)
- `_can_sign_gate` é domain-specific hardcoded — cada novo gate_kind requer patch nesse RPC. Mitigação: manter lista curta (hoje 6 kinds); se virar >10, migrar para tabela `gate_kind_eligibility`.
- Member comum não vê status global de ratificações (UX trade-off). Mitigação: `/admin/governance/ip-ratification` para líderes, `/governance/ip-agreement` para self (Phase IP-3).

### Dívidas técnicas reconhecidas
- [IP-2] `document_comment_edits` sub-table com 15min edit window trigger
- [IP-2] `document_versions` lifecycle audit trigger (publish/lock → admin_audit_log)
- [IP-2] RLS tightening approval_chains/signoffs (D6 acima)
- [IP-3] `/governance/ip-agreement` member-facing viewer + scroll tracking (UX.Q1)
- [IP-3] Magic-link EF `external-signer-magic-link`
- [IP-4] Seed 5 presidentes via `create_external_signer_invite` (gated por RF-2/RF-3)
- [futuro] CHECK constraint validando shape de `approval_chains.gates` jsonb

### Dependências externas não cobertas por esta ADR
- **RF-2 (IRRF)**: Política §4.5.4 menciona royalties — validar com especialista tributário antes de IP-4 seed + primeiro pagamento
- **RF-3 (GDPR UE)**: Ambassadors residentes UE — consultar advogado europeu antes de formalizar acordo
- **Validação advogado humano BR**: Ivan indicou contato; pendente resposta sobre Roberto's 2 pontos + novos P1 pós-v2.1

## Relacionados

- CR-050 v2.1 — `docs/council/cr-050-v2.1-source/*.md` (5 documentos fonte)
- Spec autoritativa — `docs/council/2026-04-19-ip-ratification-decisions.md`
- Parecer jurídico — `docs/council/2026-04-19-legal-counsel-ip-review.md`
- Platform audit — `docs/council/2026-04-20-ip1-platform-guardian-audit.md` (guardian session p32, embebido no log)
- ADR-0005 — initiatives como primitivo (tribes/members paralelo)
- ADR-0006 — persons + engagements identity model
- ADR-0007 — `can()` authority grant via engagements
- ADR-0009 — config-driven (contra tabelas per-case)
- ADR-0011 — V4 auth pattern (can_by_member mandatory)
- ADR-0012 — schema consolidation (cache columns com trigger)
- ADR-0013 — log table taxonomy (admin_audit_log scope)
- ADR-0014 — log retention policy (window para audit entries)

## Validação

Invariants automatizados cobrem integridade estrutural:
- J_current_version_published = 0 violations (current_version_id aponta para locked version)
- K_external_signer_integrity = 0 violations (operational_role=external_signer tem auth_engagements match)

Contract tests esperados Phase IP-2:
- `tests/contracts/schema-invariants.test.mjs` (invariants J+K já cobertos via check_schema_invariants)
- `tests/contracts/approval-rls-tightness.test.mjs` (novo) — detecta regressão de `USING (true)` em approval_* tables

Smoke tests Phase IP-1 (p30) + baseline Phase IP-2 (p32):
- 1332 unit tests, 0 fail
- npx astro build 0 errors
- 11/11 invariants violations=0
