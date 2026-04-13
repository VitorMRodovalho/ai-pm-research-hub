# ADR-0006: Person + Engagement Identity Model

- Status: Accepted
- Data: 2026-04-11
- Aprovado por: Vitor (PM) em 2026-04-11
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Modelo de Domínio V4 — Decisão 3/6

## Contexto

Hoje `members` é uma tabela catch-all que mistura perfis distintos:

| Perfil | Base legal LGPD | Termo | Hoje |
|--------|-----------------|-------|------|
| Voluntário ativo (Vitor, Pedro) | Execução de contrato de voluntariado (Lei 9.608) | Assinado e vigente | `members` |
| Embaixador / mérito (Herlon) | Consent para uso de nome | Pode estar vencido | `members` com designation ambassador |
| Chapter board (diretor PMI-CE) | Relação com capítulo, não Núcleo | N/A | `members` com designation chapter_board |
| Partner contact (CTO de empresa parceira) | Legítimo interesse / consent | N/A | `members.partner_contact` (hack) |
| Palestrante externo de webinar | Consent para publicação | N/A | Sem modelo |
| Inscrito CPMAI não-voluntário | Consent + execução (curso) | Termo de uso, não voluntariado | Sem modelo |
| Congress attendee | Legítimo interesse para evento | N/A | Sem modelo |

LGPD Art. 7º exige **base legal específica por finalidade**. Mesclar perfis distintos em uma tabela com booleans viola o princípio da minimização e fragmenta o inventário de dados pessoais, dificultando o atendimento de direitos do titular (Art. 18) e o mapeamento de fluxos (KR4.1 PMI-CE).

Herlon é o exemplo canônico: ele é um `ambassador` (engagement de mérito, sem termo vigente) e ativo para virar `study_group_owner` no CPMAI (novo engagement com VEP + termo novo). Essas são duas realidades distintas sobre a mesma pessoa — não um membro com dois flags.

## Decisão

1. **Introduzir `persons` como identidade universal** da plataforma. Uma `person` tem: `id`, `name`, `email`, `photo_url`, `linkedin_url`, `pmi_id (nullable)`, `consent_status`, `auth_id (nullable)`. Uma pessoa existe **uma vez** no sistema, independente de quantos papéis/engagements ela acumule.
2. **Introduzir `engagements` como vínculo temporal-contextual**. Um engagement representa "Pessoa X participa da Iniciativa Y com papel Z durante período P sob base legal B, ancorado no artefato de governança G". Schema mínimo:
   ```sql
   engagements (
     id uuid PK,
     person_id uuid FK → persons(id),
     organization_id uuid FK → organizations(id),
     initiative_id uuid FK → initiatives(id) NULL,  -- null se engagement for org-wide (ex: manager)
     kind text,                                      -- FK → engagement_kinds(slug)
     role text,                                      -- owner, co_lead, facilitator, participant, guest, observer
     status text,                                    -- pending, active, suspended, expired, offboarded, anonymized
     start_date date, end_date date,
     vep_opportunity_id uuid NULL,                  -- ancora VEP
     agreement_certificate_id uuid NULL,            -- FK → certificates (termo assinado)
     legal_basis text,                               -- contract_volunteer, consent, legitimate_interest
     granted_by uuid FK → persons(id),
     granted_at timestamptz,
     revoked_at timestamptz NULL,
     revoked_by uuid NULL,
     revoke_reason text NULL,
     metadata jsonb                                  -- kind-specific fields
   );
   ```
3. **`members` vira uma view de compatibilidade** — `SELECT * FROM persons JOIN engagements ... WHERE status='active' AND kind IN (kinds considerados "membro voluntário")`. Todo código legado continua funcionando. Novo código usa `persons` + `engagements`.
4. **Base legal LGPD é propriedade do `engagement_kind`** (ver ADR-0008). Cada kind declara: que base legal usa, se exige termo, qual template de termo, qual lifecycle, qual retenção pós-offboard.
5. **Herlon como caso de teste**: após implementação, ele terá duas linhas em `engagements`:
   - `kind=ambassador, status=active, legal_basis=consent, end_date=null, agreement=null` (mérito, sem termo)
   - `kind=study_group_owner, status=pending, legal_basis=contract_volunteer, vep_opportunity_id=<nova>, agreement=<assinatura pendente>` (papel operacional CPMAI)

## Consequências

**Positivas:**
- LGPD by design — base legal e retenção explícitas por engagement, não booleans em members.
- Histórico íntegro — sair do Núcleo não deleta person, só encerra engagement.
- Reuso de identidade entre orgs — mesma person pode ter engagements em orgs diferentes.
- Palestrante externo, partner contact, inscrito CPMAI — todos caem no mesmo modelo (engagement com legal_basis=consent, sem termo, fim definido).
- Auditoria de "quem pode ver PII dos inscritos CPMAI em 11/Abr" vira query de uma linha em `engagements`.
- Revogação limpa: basta `UPDATE engagements SET status='revoked', revoked_at=now()`.

**Negativas / custos:**
- Refactor grande. Todas as queries que hoje fazem `SELECT * FROM members WHERE operational_role=...` precisam virar join via engagements.
- Ghost resolution (o que fizemos hoje para o Herlon) precisa ser repensado: hoje o ghost fica em `auth.users` sem link para `members`. Após refactor, fica sem link para `persons`.
- View de compatibilidade precisa ser rápida — potencial impacto de performance se mal indexada.
- Rewrite do `sign_volunteer_agreement()` para escrever em engagements ao invés de campos de members.

**Neutras:**
- Do ponto de vista do usuário final, nada muda — "eu sou o Vitor, manager do Núcleo IA" continua sendo a percepção. O modelo interno é que generaliza.

## Alternativas consideradas

- **(A) Manter `members` com booleans e novas colunas por caso** — rejeitado por razões LGPD.
- **(B) `members` + tabelas auxiliares separadas (external_speakers, partner_contacts)** — rejeitado por fragmentar identidade (mesma pessoa aparece em 3 tabelas).
- **(C) Persons + Engagements (escolhida)** — unifica identidade, separa contexto.

## Relações com outros ADRs

- Depende de ADR-0004 (tenancy) — person pode ter engagements em múltiplas orgs
- Depende de ADR-0005 (initiative) — engagement aponta para initiative
- Pré-requisito de ADR-0007 (authority derivada de engagements)
- Pré-requisito de ADR-0008 (lifecycle por kind)
- **Substitui parcialmente ADR-0002** (Role Model V3): operational_role continua existindo como atalho/cache, mas fonte de verdade muda para engagements

## Critérios de aceite

- [x] `persons` + `engagements` + `engagement_kinds` tabelas criadas — `20260413300000`, `20260413310000`, `20260413320000`
- [x] Backfill: 71 persons + 96 engagements criados de members ativos — `20260413310000`, `20260413320000`
- [ ] View `members_compat` mantém todo código legado funcionando — **POSTERGADO Fase 7** (130+ FKs impedem conversão)
- [ ] `sign_volunteer_agreement()` reescrito para popular `engagements.agreement_certificate_id` — **POSTERGADO Fase 5**
- [x] Ghost resolution atualiza `persons.auth_id` — backfill de members.auth_id em `20260413310000`; fluxo novos logins pendente (dívida no master doc)
- [ ] Herlon tem 2 engagements distintos (ambassador + study_group_owner) — **PENDENTE** aguarda VEP formal
- [ ] Export LGPD gera JSON por engagement com base legal — **POSTERGADO Fase 5**
- [ ] MCP tools migram para `getPerson() + getActiveEngagements()` — **POSTERGADO Fase 7**
