# ADR-0008: Per-Kind Engagement Lifecycle with Explicit LGPD Basis

- Status: Accepted
- Data: 2026-04-11
- Aprovado por: Vitor (PM) em 2026-04-11
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Modelo de Domínio V4 — Decisão 5/6

## Contexto

Hoje existe um lifecycle único, canônico e bem testado: **VEP → Selection → Termo de Voluntariado → Ciclo Ativo → Offboard → Anonymize (5 anos)**. Este é o caminho feliz do voluntário de tribo — fonte da confiança LGPD do Núcleo.

Mas nem todo vínculo passa por esse fluxo:

| Engagement kind | Lifecycle apropriado | Base legal LGPD |
|-----------------|---------------------|-----------------|
| `research_tribe_member` | VEP → Selection → Termo → Ciclo 6m → Offboard → Anonymize 5a | Execução de contrato (Lei 9.608) |
| `research_tribe_leader` | VEP → Selection → Termo → Ciclo 6m → Offboard → Anonymize 5a | Execução de contrato |
| `study_group_owner` (Herlon CPMAI) | VEP fast-track → Termo → 9m → Offboard → Anonymize 5a | Execução de contrato |
| `study_group_participant` (inscrito CPMAI) | Consent + termo de uso → Curso → Certificado → Delete 2a | Consent + execução |
| `congress_committee` | Convite → Termo simplificado → 4 semanas → Encerrar | Execução contrato curto |
| `guest_speaker` (palestrante externo) | Convite → Consent imagem → 30 dias → Delete | Consent |
| `partner_contact` | Registro pelo manager → Legítimo interesse → Sem fim → Delete on request | Legítimo interesse |
| `chapter_board_liaison` | Designação pelo chapter → Sem termo Núcleo → Revogável | Relação capítulo |
| `ambassador` (mérito, Herlon) | Nomeação → Sem termo → Indefinido (revogável) → Delete on request | Consent |

Hardcodar um lifecycle único no código gera exceções por toda parte. `sign_volunteer_agreement()` assume que o período vem de VEP. Ghost resolution assume que a pessoa é voluntário. Offboard flow assume termo vigente.

LGPD Art. 7 + Art. 15 exigem base legal e prazo de retenção **explícitos por finalidade**. Isto não pode ser implícito no código.

## Decisão

1. **Cada `engagement_kind` declara seu lifecycle como configuração**. Tabela `engagement_kinds`:
   ```sql
   engagement_kinds (
     slug text PK,                         -- 'research_tribe_member', 'study_group_owner', etc
     display_name text,
     description text,
     requires_vep boolean,
     requires_selection boolean,
     agreement_template_id uuid NULL,      -- FK → governance_documents
     legal_basis text CHECK (legal_basis IN ('contract_volunteer','contract_course','consent','legitimate_interest','chapter_delegation')),
     default_duration_days int NULL,       -- null = indefinite
     max_duration_days int NULL,           -- hard cap
     requires_active_agreement boolean,    -- gate: can() exige termo vigente
     retention_after_offboard interval,    -- '5 years', '2 years', '30 days', immediate
     anonymization_policy text,            -- 'anonymize', 'delete', 'retain_for_legal'
     renewable boolean,
     auto_expire_behavior text,            -- 'suspend', 'offboard', 'notify_only'
     notification_30d_before_expiry boolean,
     created_by_role text[],               -- quem pode criar engagements deste kind
     revocable_by_role text[],             -- quem pode revogar
     organization_scoped boolean,          -- true se engagement é org-wide (ex: manager)
     initiative_kinds_allowed text[],      -- quais kinds de initiative aceitam este engagement_kind
     metadata_schema jsonb                 -- JSON schema dos campos customizados
   );
   ```
2. **Fluxos existentes** (sign_volunteer_agreement, offboard, anonymize cron) passam a ler o lifecycle do `engagement_kind`, não hardcode. Cada fluxo vira uma máquina de estados parametrizada.
3. **Anonymization cron** (hoje roda global com 5 anos) passa a iterar por kind respeitando `retention_after_offboard`:
   - Voluntários: 5 anos (LGPD + obrigação legal trabalhista)
   - Inscritos de curso: 2 anos após conclusão (Art. 16 II — cumprimento de obrigação legal)
   - Palestrantes: 30 dias após evento (minimização)
   - Partners: delete on request (legítimo interesse revogável)
4. **Templates de termo** (`governance_documents`) ganham FK direto do `engagement_kind`. Um kind = um template. Versionado.
5. **Notificações de expiração** parametrizadas por kind — 30 dias antes, no dia, 7 dias após.

## Consequências

**Positivas:**
- LGPD by design, não by exception. Cada kind declara sua base legal e prazo.
- Anonymize cron defensável em auditoria: "por que este inscrito foi deletado em 2 anos e o voluntário em 5?" — está na tabela.
- Criar um novo tipo de engagement = uma linha em `engagement_kinds` + configurar template de termo. Sem código novo.
- Renovação / expiração explícitas e auditáveis.

**Negativas / custos:**
- Migração de `sign_volunteer_agreement()` para ler kind configuration.
- Anonymize cron precisa iterar por kind. Mais complexo, mas mais correto.
- Configuração inicial de ~10 kinds iniciais exige cuidado jurídico (base legal + retenção).

**Neutras:**
- Usuários finais não percebem mudança direta. Sistema de notificação de termo expirando já existe — só fica parametrizado.

## Alternativas consideradas

- **(A) Lifecycle único com branches no código** — rejeitado, fragmenta e esconde decisões LGPD.
- **(B) Lifecycle como policy em código (Rego / OPA)** — rejeitado, excesso de infraestrutura para o tamanho do problema.
- **(C) Config-driven lifecycle no banco (escolhida)** — simples, auditável, extensível.

## Relações com outros ADRs

- Depende de ADR-0006 (engagements) e ADR-0007 (authority)
- Pré-requisito de ADR-0009 (config-driven) — kinds editáveis em admin UI
- Refatora `sign_volunteer_agreement()` e `anonymize_old_members_cron`

## Critérios de aceite

- [ ] Tabela `engagement_kinds` com seed inicial de ~10 kinds cobrindo todos os perfis da tabela do Contexto
- [ ] Jurídico (Claudio Torres ou assessoria) revisou base legal + retenção de cada kind
- [ ] `sign_volunteer_agreement()` reescrito para ler template + duração do kind
- [ ] Anonymize cron parametrizado por kind (2 anos, 5 anos, 30 dias, on-request)
- [ ] Notificação de expiração parametrizada
- [ ] Admin UI lista todos os kinds com suas configurações
- [ ] Testes cobrindo: voluntário ativa/renova, inscrito conclui e é deletado em 2a, palestrante expira em 30d
