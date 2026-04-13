# Herlon VEP Parallel Track

- **Criado:** 2026-04-11
- **Status:** **Revisado conforme decisão D5 (2026-04-11)** — Herlon NÃO entra operacionalmente agora. PM cria VEP vaga em paralelo; plataforma entra pronta para recebê-lo na Fase 3/4 do V4.
- **Owner:** Vitor (PM)
- **Objetivo:** Garantir que Herlon tenha todos os artefatos de governança **carregados na plataforma** (VEP opportunity, ghost resolvido) durante o refactor V4, de forma que quando a plataforma estiver pronta, o onboarding operacional dele seja instantâneo e sem débito técnico.

## Por que é parallel track (revisado — D5)

**Decisão D5 (2026-04-11):** Herlon NÃO é ativado operacionalmente no modelo V3. O PM rejeitou o `is_superadmin` temporário e rejeitou o `tribe_leader` sem tribo. Em vez disso:

1. Durante o refactor V4, **apenas os artefatos de governança** são carregados na plataforma (VEP opportunity formal, ghost login já resolvido).
2. Nenhuma mudança em `operational_role`, `designations` ou permissões até a plataforma estar pronta no modelo V4.
3. Quando Fase 3 (Persons+Engagements) ou Fase 4 (Authority derivation) estiverem prontas, Herlon é onboard como o primeiro consumidor do novo modelo, sem dívida técnica.
4. Compromissos externos (PMI-CE, alunos) são comunicados: "estamos preparando a plataforma para receber o preparatório, lançamento gated na entrega do modelo V4".

Isso é mais lento, mas é honesto com o princípio de governança máxima. O PM assumiu explicitamente este trade-off.

## Estado atual pós-D5

- [x] Herlon tem `auth_id` vinculado (ghost resolvido em 2026-04-11)
- [x] Email secundário PMI-CE registrado
- [x] Board CPMAI existe com 4 cards atribuídos
- [x] `operational_role = observer` **mantido** — nenhuma mudança até plataforma V4 estar pronta
- [x] `designations = [ambassador]` **mantido**
- [x] Nenhuma concessão temporária de `is_superadmin`
- [ ] VEP opportunity criada pelo PM em paralelo (step 1 abaixo)
- [ ] Herlon é onboard no V4 (Fase 3 ou Fase 4) como primeiro consumidor do novo modelo

## Fluxo formal (VEP-first)

### Passo 1 — Criar VEP Opportunity (manager)

```sql
INSERT INTO vep_opportunities (
  opportunity_id,
  title,
  description,
  chapter_posted,
  role_default,
  positions_available,
  time_commitment,
  start_date,
  end_date,
  is_active,
  metadata
) VALUES (
  gen_random_uuid(),
  'Gerente de Projeto — Grupo de Estudos Preparatório CPMAI (Ciclo 3)',
  'Liderança operacional do grupo de estudos preparatório para certificação PMI-CPMAI™. Responsabilidades: recrutamento de facilitadores, timeline, webinar de lançamento, critérios de inscrição, operação do curso, interface com PMI-CE. Posição com escopo de 9 meses alinhada ao Ciclo 3 do Núcleo IA.',
  'PMI-CE',
  'leader',
  1,
  '5-10 hours per month',
  '2026-04-15',
  '2026-12-31',
  true,
  jsonb_build_object(
    'initiative_slug', 'cpmai_prep_ciclo3',
    'invitation_only', true,
    'invited_by', '<vitor_member_id>',
    'fast_track_justification', 'Convite direto fundamentado em histórico de embaixador PMI-CE e especialista CPMAI-adjacente. Seleção formal dispensada por Change Request aprovada pelos presidentes de capítulo.'
  )
);
```

### Passo 2 — Change Request formal (governance)

A plataforma exige que mudanças de papel relevantes passem por Change Request aprovada pelos 5 presidentes de capítulo (ver `feedback_cr_approval_by_chapter_presidents.md`). Para VEP de convite direto:

- Criar CR: `"Convite direto ao Herlon Alves de Sousa para GP do Grupo de Estudos CPMAI"`
- Justificativa: embaixador PMI-CE ativo 2025, contexto do curso CPMAI demanda velocidade, conhecimento local, interface natural com OKRs 2026 do PMI-CE (alinha com KR1.1, KR1.2, KR3.2)
- Aprovação: 5 presidentes (Vitor pode facilitar o fluxo)
- Registro: `governance_change_requests` com link para a VEP opportunity

### Passo 3 — Selection Application (fast-track documentado)

```sql
INSERT INTO selection_applications (
  id,
  vep_opportunity_id,
  email,
  full_name,
  chapter,
  status,
  created_at,
  metadata
) VALUES (
  gen_random_uuid(),
  '<vep_uuid_do_passo_1>',
  '<email_herlon>',
  'Herlon Alves de Sousa',
  'PMI-CE',
  'accepted',
  now(),
  jsonb_build_object(
    'fast_track', true,
    'change_request_id', '<cr_uuid_do_passo_2>',
    'accepted_by', '<vitor_member_id>',
    'accepted_at', now()
  )
);
```

### Passo 4 — Notificar Herlon para assinar o Termo

- Notificação no app + email: "Você foi aceito como GP do Grupo de Estudos Preparatório CPMAI. Acesse seu perfil para assinar o Termo de Voluntariado Ciclo 2026."
- Link direto para `/member/volunteer-agreement`

### Passo 5 — Herlon assina o Termo

- Herlon acessa `/member/volunteer-agreement`, revisa o termo, assina
- RPC `sign_volunteer_agreement('pt-BR')` é chamada
- A RPC **já funciona** no modelo V3 e vai pegar automaticamente as datas (2026-04-15 → 2026-12-31) da VEP criada no Passo 1 (ver migration `20260410150000_issue64c_volunteer_agreement_dates_from_vep.sql`)
- Certificate gerado, hash registrado, notificação para chapter board do PMI-CE

### Passo 6 — Ativar operational_role

```sql
UPDATE members SET
  operational_role = 'tribe_leader',  -- V3 fit mais próximo para "lidera uma sub-iniciativa"
  designations = array_append(designations, 'cpmai_gp'),
  is_active = true,
  updated_at = now()
WHERE id = '<herlon_member_id>';

INSERT INTO member_role_changes (
  member_id,
  old_role, new_role,
  changed_by,
  reason,
  effective_date
) VALUES (
  '<herlon_member_id>',
  'observer', 'tribe_leader',
  '<vitor_member_id>',
  'VEP <vep_uuid> — Convite formal como GP do Grupo de Estudos CPMAI. CR <cr_uuid>.',
  '2026-04-15'
);
```

**Nota de governança:** `tribe_leader` sem `tribe_id` é um hack documentado no V3 — Herlon NÃO lidera uma tribo de pesquisa, mas o papel operacional (canWrite nas RPCs do CPMAI) requer este valor no modelo atual. O refactor V4 resolve isso nativamente (engagement kind = `study_group_owner` com role = `owner`).

**Filtros a verificar antes:** Qualquer relatório que hoje conta "quantos tribe_leaders" precisa filtrar `WHERE tribe_id IS NOT NULL` para não incluir o Herlon como líder de tribo fantasma. Mapear todos os lugares em Fase 0 do refactor como parte do inventário.

### Passo 7 — Acesso ao subsistema CPMAI

Hoje as tabelas `cpmai_*` têm RLS `rpc_only_deny_all` e quase nenhuma RPC exposta. Herlon precisa ter pelo menos acesso de leitura/escrita ao curso `draft`. Opções:

**Opção curta (correta no V3):** adicionar gate nas RPCs do CPMAI quando elas existirem — checar `canWrite(member) OR <herlon condition>`. Mas o CPMAI mal tem RPCs hoje; este caminho vai gerar código temporário.

**Opção pragmática (recomendada):** dar ao Herlon `is_superadmin = true` temporariamente **com data de expiração explícita** e **registro em audit log**:

```sql
UPDATE members SET is_superadmin = true WHERE id = '<herlon_id>';
INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
VALUES (
  '<vitor_id>',
  'temporary_superadmin_grant',
  'member',
  '<herlon_id>',
  jsonb_build_object(
    'reason', 'CPMAI GP onboarding pré-V4',
    'expires_at', '2026-07-31',
    'revoke_trigger', 'V4 Phase 4 (authority derivation) ativa',
    'approved_by_cr', '<cr_uuid>'
  )
);
```

**Esta opção é aceitável porque:**
1. Tem expiração explícita amarrada à entrega da Fase 4 do refactor V4.
2. Registrada em audit log com motivo e aprovação.
3. Será **automaticamente revogada** quando authority derivation (ADR-0007) entrar em produção — o engagement do Herlon vai limitar acesso ao scope correto.
4. Herlon é confiável: embaixador verificado, contato direto do Vitor, histórico de 2025.

### Passo 8 — Comunicação

- Atualizar `/cpmai` landing: adicionar card "GP do Grupo de Estudos" com foto + nome do Herlon (depende de issue-06 ser corrigida primeiro — i18n collision)
- Notificar Pedro Henrique e equipe do board CPMAI sobre a formalização
- Herlon comunica PMI-CE sobre o papel ativado

### Passo 9 — Handoff ao refactor V4

Quando Fase 3 do V4 rodar (`persons + engagements`), o Herlon será migrado:
- `member` → `person` + 2 engagements (`ambassador` merit + `study_group_owner` CPMAI)
- O engagement CPMAI herda a VEP + certificate criados aqui
- `is_superadmin = true` é **removido** automaticamente (authority derivation cobre o caso)
- O flag de `revoke_trigger` no audit log vira alerta de reconciliação

## Checklist executivo

- [ ] **Dia 1:** Criar VEP Opportunity (Passo 1)
- [ ] **Dia 1:** Abrir Change Request (Passo 2)
- [ ] **Dia 2-3:** Coletar aprovações dos 5 presidentes de capítulo (Passo 2)
- [ ] **Dia 3:** Criar Selection Application fast-track (Passo 3)
- [ ] **Dia 3:** Notificar Herlon (Passo 4)
- [ ] **Dia 4-7:** Herlon assina termo (Passo 5)
- [ ] **Dia 7:** Atualizar role (Passo 6)
- [ ] **Dia 7:** Grant superadmin temporário (Passo 7)
- [ ] **Dia 7:** Corrigir issue-06 (i18n collision CPMAI) — pré-requisito para Passo 8
- [ ] **Dia 8:** Comunicar internamente (Passo 8)
- [ ] **Q3:** Handoff automático durante Fase 4 V4 (Passo 9)

## Riscos deste parallel track

| Risco | Mitigação |
|-------|-----------|
| `tribe_leader` sem tribo confunde relatórios | Inventariar e filtrar todos os relatórios durante Fase 0 V4 |
| `is_superadmin` temporário é esquecido e persiste | Audit log com expires_at + reconciliação obrigatória em Fase 4 |
| CR não é aprovada pelos 5 presidentes a tempo | Plano B: Vitor lidera formalmente até CR aprovar, depois passa bastão |
| Herlon não assina termo em tempo hábil | Sem assinatura, sem role — política clara, sem exceção |

## Referências

- Modelo V3: `docs/adr/ADR-0002-role-model-v3-operational-role-and-designations.md`
- Modelo V4 (destino): `docs/refactor/DOMAIN_MODEL_V4_MASTER.md`
- Governance CR por presidentes: `project_cr_approval_by_chapter_presidents` (memória)
- Sign volunteer agreement RPC: `20260410150000_issue64c_volunteer_agreement_dates_from_vep.sql`
