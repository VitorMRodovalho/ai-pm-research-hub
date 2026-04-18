# IP Ratification On-Platform — PM Decisions on 10 Open Questions

**Date:** 2026-04-19 (p29)
**PM decisions:** Vitor (input na sessão p29)
**Status:** Decisões registradas — desbloqueia Phase IP-1 planning (não execution)
**Predecessor:** `docs/council/2026-04-18-ip-ratification-planning.md`

---

## Directive from PM

> "esqueça CBGPL como constraint, fazer o certo para a plataforma ir pro destino que procuramos"

Traduz: decisões devem otimizar para **correctness + longevidade arquitetural + governança**, não prazo de demo. Timeline CBGPL (28/Abr) NÃO condiciona design.

> "deixo tua maturidade em produtos digitais e governança para dar resposta final em qual caminho ir"

Onde PM delegou, proposta tem **Recommendation + Rationale** abaixo. Aceito via silence-is-approval ou overridable no start da Phase IP-1.

---

## Decisions

### UX.Q1 — Scroll 100% obrigatório?

**PM: SIM — obrigatório.**

> "é quase como uma evidência de que a pessoa realmente acessou todo documento, se não leu é pq não quis"

**Implementação:**
- Tracking: `IntersectionObserver` por seção marcando `sections_read` em localStorage + backend (via `sign_ip_ratification` payload)
- UI: progress bar "seção X/Y" + botão "Assinar" disabled até 100%
- Audit: `approval_signoffs.content_snapshot` inclui `sections_verified[]` com timestamps por seção
- Rationale: alinha com prática docusign/getac, evidência de acesso em disputas legais

### UX.Q2 — Tier 1 pode comentar?

**PM: SIM — prerrogativa de questionar.**

> "é tardio mas se chegar a esta questão ele tem o direito, em princípio os demais deveriam ter feito o papel de revisão para deixar inquestionável, mas o Tier1 tem a prerrogativa de questionar/comentar"

**Implementação:**
- `document_comments.visibility`: apenas `public` + `curator_only` (sem `admin_only` exclusion)
- Tier 1 comenta com visibility='public'
- Curadores/líderes recebem notification quando Tier 1 comment chega na fase de ratificação
- UX: badge "questão do Tier 1" destacando que é fase madura (após curator review)
- Rationale: legítima due process — quem assina o doc é o Tier 1, ele tem direito de questionar antes

### UX.Q3 — Diff baseline varia por ciclo de entrada?

**PM: SIM — baseline clara, versionamento honrado.**

> "importante por governança de que uma mudança futura em documentação, não revisa o que a pessoa assinou e tem referenciado no documento dele"

**Implementação:**
- Nova tabela `member_document_signatures`: `(member_id, document_id, signed_version_id, signed_at)`
- Diff viewer lê `member.last_signed_version_id` vs `document.current_version_id`
- Certificados referenciam version_id exato assinado (não current)
- Upgrade path: quando nova versão publicada, trigger `trg_new_version_requires_resign` dispara notification → membro vê diff + assina novamente
- `content_snapshot` na certificate preserva texto da versão assinada (imutável)
- Rationale: core de IP governance — assinatura referencia estado fixo do documento

### UX.Q4 — Parceiros externos: viewer ou token separado? (PM pediu expansão)

**PM: "preciso que voce me traga uma expansão desta duvida com cenario e recomendacao e o pq"**

#### Cenário real

3 contextos concretos exigem ratificação por externos:

1. **AIPM Ambassadors** (41 voluntários, 18 países) — Vitor + Fabrício são os embaixadores; outros 39 são "affiliated" mas o termo de cooperação precisaria ratificação formal se quisermos trocar IP entre AIPM e Núcleo.
2. **Christine (PMI-WDC)** — explorando AI initiative com Núcleo; pode assinar um `MOU` de cooperação como executiva do chapter DC, não como "membro Núcleo".
3. **5 presidentes PMI-GO/CE/DF/SP/RJ** — não são membros técnicos operacionais, mas precisam ratificar IP Policy como governança dos capítulos.

Pergunta de negócio: **external signer tem que virar "member" Núcleo?**

#### 3 opções

**Opção A — Force onboarding como member.**
- Todos os external signers viram members com role `chapter_board_external` ou `external_partner`.
- **Pro**: auditoria uniforme; um único conceito "signer = member"; LGPD coverage automático via `privacy_consent` pattern.
- **Con**: força conta Google/GitHub OAuth em 5 presidentes + 39 ambassadors + parceiros futuros. **Barreira política e UX real** — vários presidentes não vão querer conta "numa plataforma de outro capítulo". Pollui `members` table com entidades que não fazem attendance.

**Opção B — Magic-link puro (sem member row).**
- Email → click → viewer → sign. Zero conta. `approval_signoffs.signer_id IS NULL` + `external_signer_name/email/org`.
- **Pro**: friction zero; scale natural para novos parceiros.
- **Con**: perfil do signer é "string jogada no banco" — sem histórico, sem revisões pendentes, sem trail quando muda de cargo. Difícil comprovar identidade em disputa (magic link pode ser interceptado em inbox compartilhada).

**Opção C — Híbrida com "guest signer".** (RECOMENDAÇÃO)
- `members` table ganha role novo: `external_signer` (não-Tier, não participa de attendance/XP).
- Magic-link cria conta leve: email + nome + organização + relationship_description.
- `privacy_consent_version` preenchido no ato do magic-link (LGPD OK).
- Token valid 72h; após clicar, conta persiste (pode re-entrar com magic-link futuro).
- `approval_signoffs.signer_id` sempre aponta para member UUID (uniforme).
- RLS: `external_signer` NÃO vê outros members, não aparece em rosters, não conta em KPIs.

#### Recomendação: Opção C

Razões (por ordem de peso):

1. **Auditoria uniforme**: um único schema de `signoff_id → signer_id UUID`. Querries de compliance (ex: "quantos president signoffs em 2026?") não precisam `COALESCE(signer_id, external_signer_name)`. Crucial quando tivermos disputas IP daqui 2-5 anos.
2. **LGPD compliance por construção**: member row tem `privacy_consent_accepted_at + version`. Magic-link flow grava consentimento no instante da primeira entrada. Extern signer tem recurso de `export_my_data` + `anonymize_on_request` igual ao interno.
3. **Friction zero**: external nunca precisa criar password. Reentradas são sempre magic-link 72h. Na prática, assinam 1-2x por ano (quando há nova versão de documento) — magic-link é suficiente.
4. **Escala**: 39 ambassadors + 5 presidentes + parceiros futuros = cresce orgânico. Member table já suporta role-based filtering; só precisa `operational_role IN (...)` filter em queries de "plataforma-facing".
5. **Prepare para Opção 2 se precisar**: se 1 presidente recusar a conta leve, magic-link com `signer_id IS NULL` ainda é possível via feature flag. Opção C é superset, não conflita.

**Não é Opção A** porque polui o core conceito "member" (implica attendance, XP, gamification). Conta leve `external_signer` é claramente fora desse modelo.

**Não é Opção B** porque perde audit trail longitudinal. Um presidente que assinou 3 docs em 2026 e renovou em 2027 não tem entidade consolidada — só 4 rows de signoffs com strings.

**Trade-off assumido**: Opção C exige 1 migration extra (`external_signer` role + constraint que impede Tier operations) e 1 RLS sweep para excluir `external_signer` de member-facing views. Custo ~1 sessão. Benefício dura 5-10 anos.

### UX.Q5 — Não-assinatura em 30d?

**PM: Bloqueio, mas com alertas/lembretes antes (DocuSign pattern).**

> "assim como plataformas como docusign tem que ter disparo de alertas/lembretes"

**Implementação:**
- D-14 email reminder + in-app badge
- D-7 email urgent + banner workspace
- D-3 email final + notification push
- D-1 email "último dia"
- D+0 bloqueio: `member.can_access_platform = false` até assinar (exceto `/governance/ip-agreement` accessível)
- D+7 escalate: notification para manager/sponsor
- Gamification impact: NÃO — ratificação é governança, não performance

### DataArq.Q1 — `current_version_id` cache ou computed?

**Recomendação: CACHE com trigger sync.**

Razão: leituras de `document.current_version_id` ocorrem em TODO page load de document viewer. Para 70 membros × 10 reloads/mês × 4 docs = ~2800 queries/mês. Computed = 4 rows scanned × 2800 = 11200 scan-rows/mês. Cache = 2800 direct lookups. Pattern já validado no V4 (operational_role é cache trigger-synced per ADR-0007/0011).

Trigger: `trg_sync_current_version_on_publish` (AFTER UPDATE ON document_versions WHERE locked_at IS NOT NULL) — atualiza `governance_documents.current_version_id` ao locking.

Invariant (ADR-0012): `I_current_version_published`: `governance_documents.current_version_id` deve apontar para `document_versions` com `locked_at IS NOT NULL`.

### DataArq.Q2 — `gates` config vs state?

**Decisão: CONFIG ONLY (ADR-0012 mandato).**

Gate structure armazenada como `jsonb`:
```json
[
  {"kind": "curator",          "threshold": 1, "order": 1},
  {"kind": "leader",           "threshold": 1, "order": 2},
  {"kind": "president_go",     "threshold": 1, "order": 3},
  {"kind": "president_others", "threshold": 4, "order": 4},
  {"kind": "member_ratification", "threshold": "all", "order": 5}
]
```

Status de cada gate é **computed via query** em `approval_signoffs`:
```sql
-- Gate X está "satisfied"?
SELECT count(*) >= gate.threshold FROM approval_signoffs
WHERE approval_chain_id = :id AND gate_kind = gate.kind;
```

### DataArq.Q3 — Comment edit window?

**Recomendação: 15 minutos edit window + audit trail para edits.**

Pattern DocuSign/Notion/Slack: usuário pode corrigir typo nos primeiros minutos. Após 15min, edit cria `document_comment_edits` row preservando history + notificação "(editado em 2026-04-20 15:30)".

Implementação:
- `document_comments.updated_at`: ≤ 15min do `created_at` → edit direto
- Após 15min: INSERT em `document_comment_edits` (previous_body, edited_at, edited_by)
- UI: badge "(editado)" com tooltip histórico
- Trigger: `trg_comment_edit_window_enforce` para gate do UPDATE pós-15min

### DataArq.Q4 — `ip_ratification` certificate type ou new entity?

**Recomendação: Type extension (`certificate.type = 'ip_ratification'`).**

Razão: volume esperado ~280 signoffs (70 membros × 4 docs), crescendo ~150/ano. Cabe no schema atual sem proliferação de tabelas. Re-avaliar se volume exceder 5K rows ou se surgirem metadados muito divergentes (ex: ratificação com pagamento, o que não acontece aqui).

Vantagens:
- Reaproveita `verify_certificate(code)` RPC
- `get_my_certificates()` MCP tool já funciona
- PDF template reutilizável com variação por `type`
- LGPD export automático via `export_my_data()`

### DataArq.Q5 — Presidentes: members ou external?

**Decisão (ligada à UX.Q4 Opção C): HYBRID via `external_signer` role.**

Presidentes viram members com:
- `operational_role = 'external_signer'`
- `designations = ['chapter_president', 'pmi_go' | 'pmi_ce' | ...]`
- `is_active = true` mas excluídos de `active_members` default view (extra WHERE clause)
- Onboarding via magic-link (não OAuth)
- Mesmo audit trail de qualquer member

---

## Arquitetura de resposta às OQs

Essas 10 decisões impactam 4 áreas do schema novo IP-1:

| Área | Decisão afetada | Delivery |
|---|---|---|
| `member_document_signatures` | UX.Q3 (baseline por ciclo) | Phase IP-1 |
| `external_signer` role + magic-link flow | UX.Q4 + DataArq.Q5 | Phase IP-1 + IP-4 |
| `approval_chains.gates` jsonb config + compute status | DataArq.Q2 | Phase IP-1 |
| `document_comment_edits` table + 15min window | DataArq.Q3 | Phase IP-2 |
| `certificate.type='ip_ratification'` | DataArq.Q4 | Phase IP-1 (seed) |
| `governance_documents.current_version_id` cache + trigger | DataArq.Q1 | Phase IP-1 |
| Scroll tracking + `sections_verified` | UX.Q1 | Phase IP-3 |
| Gate comments visibility 'public' para Tier 1 | UX.Q2 | Phase IP-2 |
| Reminder cadence D-14/-7/-3/-1 + D+0 block | UX.Q5 | Phase IP-2 |

Total: 6 tabelas novas, 1 role novo, 1 certificate type novo, 3 triggers novos, 1 invariant novo.

---

## Revised Phased Implementation

### Phase IP-1: Foundation (2 sessões — revisado de 1)
- 5 tabelas core: `document_versions`, `approval_chains`, `approval_signoffs`, `document_comments`, `member_document_signatures`
- `external_signer` role + RLS
- `ip_ratification` certificate type seed
- Magic-link RPC para external onboarding
- Invariant I_current_version_published + I_external_signer_integrity
- Seed de 5 documentos v1 (convertidos de .docx via pandoc)

### Phase IP-2: Admin workflow (2 sessões — revisado de 1-2)
- Admin UI para upload/edit documents + diff preview
- Curator/leader approval panels + comment threads
- Gate advance FSM + notifications
- Reminder cadence cron (D-14/-7/-3/-1)
- `document_comment_edits` table + 15min trigger

### Phase IP-3: Member ratification (2 sessões)
- `/governance/ip-agreement` page com viewer + diff
- Scroll tracking + `sections_verified` + botão progressivo
- Profile gate check inline
- Magic-link flow UI para external
- Certificate issue + badge display

### Phase IP-4: External signers + hardening (1 sessão)
- Presidentes seed (5 magic-links com relationship='chapter_president')
- AIPM Ambassador seed
- Dashboard admin para monitorar external signer status
- D+0 bloqueio via `can_access_platform` flag + middleware
- E2E smoke tests para external flow

**Total revisado**: 7 sessões (antes 4-6). Start quando PM decidir — não há gate temporal arquitetural. Completion razoável estimada em 4-6 semanas após kickoff.

---

## Dependencies & Unblocking

✅ PM decisões nas 10 OQs — RESOLVED (esta doc)

⏸ Bloqueadores remanescentes:
- **Legal-counsel review dos 5 .docx v2** — pendente `pandoc` conversion. Sessão dedicada pós-CBGPL.
- **Ivan + 4 presidentes sign-off político do v2** — track político paralelo (Ivan conversa 20-21/Abr; Marcio apoia CBGPL 28/Abr).
- **Accountability-advisor session** — validar minimum audit trail + PMI governance alignment.

✅ Não-bloqueadores (pode avançar em paralelo):
- Phase 5 A3-A6 (ADR-0015 members.tribe_id) — independent domain
- LIM submission (1ª semana Mai) — independent
- CPMAI launch (15 Mai) — independent

---

## Next Actions

Timing flexível — nenhuma ação abaixo é gated por CBGPL. Podem ocorrer antes, durante ou depois conforme capacity do PM. Não há correlação arquitetural com o demo.

1. **Ativáveis a qualquer momento** (não bloqueiam um ao outro):
   - Spawnear legal-counsel para review v2 docs (pré-requisito: pandoc conversion dos 5 .docx)
   - Spawnear accountability-advisor para audit trail spec
   - Kickoff Phase IP-1 (foundation tables + seeds) — pode começar antes dos anteriores; Phase IP-1 cria só infra, não depende do conteúdo legal final

2. **Validações políticas paralelas** (não bloqueiam design):
   - Ivan + 2 presidentes sobre Opção C (external_signer magic-link) ser aceitável
   - Roberto sobre os 2 pontos dele ajustados nos v2 docs

3. **Sobre este documento**:
   - Autoritativo sobre arquitetura IP daqui para frente
   - Overridable via novo PM decision (registrar em ADR se mudar)
   - Execução em fases só começa quando PM decidir — nenhum hard gate temporal

---

**Document owner:** Vitor (PM).
**Autor das recomendações:** Claude Opus 4.7 (ai-engineer + data-architect + ux-leader compiled por PM directive "maturidade em produtos digitais e governança").
**Aprovado em:** 2026-04-19 (PM responses na sessão p29).
