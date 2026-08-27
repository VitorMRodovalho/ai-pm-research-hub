# Consultas operacionais: coorte aprovada e atribuição de ator

> Medido e validado em 26–27/08/2026. **Os números aqui envelhecem — re-execute.** O que vale
> permanentemente é a FORMA da consulta: quais tabelas, quais chaves, e as armadilhas.

Este arquivo existe porque duas perguntas operacionais recorrentes não têm superfície de leitura
pronta, e responder cada uma exigiu meia dúzia de consultas — com três leituras erradas no caminho,
todas documentadas abaixo para não se repetirem.

---

## 1. "Os aprovados entram na reunião quinzenal?"

**A audiência de evento é REGRA, não lista.** Ninguém é "inserido". `event_audience_rules` guarda a
regra e `is_event_mandatory_for_member(event_id, member_id)` a resolve pessoa a pessoa.

⚠️ **`get_event_audience()` devolve as REGRAS, não as pessoas.** Ela retorna
`(rule_id, attendance_type, target_type, target_value, invited_members)` — uma linha por regra. Usar
`... IN (SELECT member_id FROM get_event_audience(...))` **não** falha: o `member_id` resolve para o
escopo EXTERNO por correlação, e a consulta devolve um número plausível e falso. Foi o erro cometido
em 27/08. **Use sempre a função de decisão, nunca um `IN` sobre a de regras.**

O predicado real de `all_active_operational` (lido do corpo vivo):

```
is_active = true
AND NOT ('curator' = ANY(designations))
AND (tribe_id IS NOT NULL OR operational_role IN ('manager','deputy_manager'))
```

Ou seja: **o discriminador é TER TRIBO.** Aprovado sem tribo fica fora de *todas* as gerais, não só
da próxima.

```sql
WITH aprov AS (
  SELECT DISTINCT ON (lower(a.email)) a.applicant_name, a.email, m.id AS member_id, m.is_active
  FROM selection_applications a
  JOIN selection_cycles c ON c.id = a.cycle_id AND c.status = 'open'
  LEFT JOIN members m ON lower(m.email) = lower(a.email)
  WHERE a.status = 'approved'
  ORDER BY lower(a.email), a.id
)
SELECT count(*) AS aprovados,
       count(*) FILTER (WHERE member_id IS NULL) AS sem_registro_de_membro,
       count(*) FILTER (WHERE member_id IS NOT NULL AND NOT coalesce(is_active,false)) AS inativos,
       count(*) FILTER (WHERE member_id IS NOT NULL AND coalesce(is_active,false)
                          AND public.is_event_mandatory_for_member('<event_id>', member_id)) AS ja_obrigatorios,
       count(*) FILTER (WHERE member_id IS NOT NULL AND coalesce(is_active,false)
                          AND NOT public.is_event_mandatory_for_member('<event_id>', member_id)) AS ativos_de_fora
FROM aprov;
```

⚠️ O `DISTINCT ON (lower(email))` não é decoração: há candidaturas duplicadas por pessoa (dual-track
pesquisador/líder), e sem ele a mesma pessoa conta duas vezes.

## 2. Vagas por tribo

Teto = `platform_settings.max_members_per_tribe` (SSOT, **não** hardcode). Ocupação = engajamentos
`kind='volunteer'` ativos e não revogados, na iniciativa `kind='research_tribe'` e `status='active'`.

```sql
WITH cap AS (SELECT (value #>> '{}')::int AS teto FROM platform_settings WHERE key = 'max_members_per_tribe')
SELECT i.legacy_tribe_id AS tribo, i.title,
       count(*) FILTER (WHERE e.kind='volunteer' AND e.status='active' AND e.revoked_at IS NULL AND e.role='leader')  AS lideres,
       count(*) FILTER (WHERE e.kind='volunteer' AND e.status='active' AND e.revoked_at IS NULL AND e.role<>'leader') AS pesquisadores,
       (SELECT teto FROM cap) - count(*) FILTER (WHERE e.kind='volunteer' AND e.status='active' AND e.revoked_at IS NULL) AS vagas
FROM initiatives i
LEFT JOIN engagements e ON e.initiative_id = i.id
WHERE i.kind = 'research_tribe' AND i.status = 'active'
GROUP BY i.id, i.title, i.legacy_tribe_id
ORDER BY vagas DESC;
```

## 3. Onboarding da coorte aprovada

```sql
WITH aprov AS (
  SELECT DISTINCT ON (lower(a.email)) a.id AS app_id, a.applicant_name, a.email
  FROM selection_applications a JOIN selection_cycles c ON c.id = a.cycle_id AND c.status = 'open'
  WHERE a.status = 'approved' ORDER BY lower(a.email), a.id
)
SELECT count(*) AS aprovados,
       count(*) FILTER (WHERE p.total = 0)                       AS sem_jornada_nenhuma,
       count(*) FILTER (WHERE p.total > 0 AND p.feitos = 0)      AS com_jornada_zero_passos,
       count(*) FILTER (WHERE p.feitos > 0 AND p.feitos < p.total) AS em_andamento,
       count(*) FILTER (WHERE p.total > 0 AND p.feitos = p.total)  AS concluido
FROM aprov
LEFT JOIN LATERAL (
  SELECT count(*) AS total, count(*) FILTER (WHERE op.status = 'completed') AS feitos
  FROM onboarding_progress op WHERE op.application_id = aprov.app_id
) p ON true;
```

⚠️ **Não filtre por `metadata->>'phase'`** — 0 das 899 linhas de `onboarding_progress` carregam essa
chave, e o filtro devolve vazio para todo mundo (defeito da #1997, corrigido na `20260826144210`).

---

## 4. Atribuição de ator: quem fez, quem tirou, quem aprovou

Esta é a parte que mais engana, e três leituras erradas foram cometidas antes de acertar.

### 4.1 Dois espaços de UUID na MESMA linha

| coluna | guarda | join correto |
|---|---|---|
| `engagements.granted_by` | **`person_id`** | `persons.id` (ou `members.person_id`) |
| `engagements.revoked_by` | **`person_id`** | idem |
| `engagements.metadata->>'reviewed_by'` | **`member_id`** | `members.id` |

**`JOIN members m ON m.id = e.granted_by` devolve NULL em silêncio** — não erro, NULL. Quem lê
"concedido_por: null" conclui "o log não registrou", e está errado: o log registrou, no outro espaço
de id. Para resolver com segurança, teste os três:

```sql
SELECT (SELECT name FROM members WHERE id = :id)        AS casa_em_member_id,
       (SELECT name FROM members WHERE person_id = :id) AS casa_em_person_id,
       (SELECT name FROM members WHERE auth_id = :id)   AS casa_em_auth_id;
```

### 4.2 `granted_by` é quem ADICIONOU. Quem removeu está em `revoked_by`

Ler `granted_by` de um engajamento revogado e chamar aquilo de "quem removeu" é o erro mais fácil de
cometer — e atribui a uma pessoa um ato que não é dela. As duas colunas são independentes.

```sql
SELECT m.name AS pessoa, i.legacy_tribe_id AS tribo,
       (SELECT name FROM members WHERE person_id = e.granted_by) AS adicionou,
       (SELECT name FROM members WHERE person_id = e.revoked_by) AS removeu,
       (SELECT name FROM members WHERE id = (e.metadata->>'reviewed_by')::uuid) AS aprovou,
       e.granted_at, e.revoked_at, e.revoke_reason, e.metadata->>'source' AS origem
FROM engagements e
JOIN initiatives i ON i.id = e.initiative_id
JOIN members m ON m.person_id = e.person_id
WHERE i.kind = 'research_tribe';
```

### 4.3 O `source` do metadata distingue COMO a pessoa entrou

- `tribe_request_approved` → **a pessoa pediu** e um líder aprovou. Carrega `requested_at`,
  `invitation_id` e `review_authority`. É o fluxo self-service **com** revisão.
- `manage_initiative_engagement` → **alocação manual** por admin/owner. Carrega `invoked_as`.
- `approve_selection_application` → o engajamento org-wide que nasce da aprovação no ciclo
  (`initiative_id` NULL — **não** é tribo).

⚠️ **`tribe_selections` NÃO é onde a escolha atual é registrada.** É o outro caminho (`select_tribe`,
sem revisão de líder). Em 27/08 a última linha dela era de 10/07, e concluir daí "ninguém usa o
self-service" foi **falso**: a coorte de agosto usou o caminho de pedido+aprovação, que grava em
`engagements.metadata`. Fonte errada, conclusão invertida. Ver #1962 (dois prazos em duas tabelas).

### 4.4 O log grava QUEM, não POR ONDE

`granted_by`/`revoked_by` vêm de `auth.uid()` resolvido em `persons` — é a identidade autenticada, e
não há fallback (a RPC recusa com `Not authenticated` se não resolver). Então a linha é confiável
sobre **quem**, e muda para **o quê** quando a ação entra pelo MCP: uma sessão de agente operando com
o token OAuth da pessoa grava a pessoa.

Para descobrir o CANAL, cruze com `mcp_usage_log` pelo segundo:

```sql
SELECT created_at, tool_name, member_id, success
FROM mcp_usage_log
WHERE created_at BETWEEN :t - interval '10 seconds' AND :t + interval '10 seconds';
```

Caso real (19/08/2026): um engajamento de tribo criado às 15:25:52 e revogado às 21:08:06 batia, no
segundo, com duas chamadas de `engagement_write` no `mcp_usage_log`. O dono não reconhecia o ato — e
o log não estava errado: **as duas ações entraram pelo MCP, autenticadas como ele.** Sem o cruzamento,
a leitura natural é "a pessoa fez", e a conclusão sobre responsabilidade sai errada.

---

## Lacuna de superfície de leitura (registrada em issue)

`list_initiative_engagements` já resolve `granted_by` corretamente e o nomeia bem
(`granted_by_person_id`, `granted_by_name`). Mas **não expõe `revoked_by` nem
`metadata.reviewed_by`** — devolve `revoked_at` e `revoke_reason` e para aí. Responder "quem tirou
esta pessoa da tribo?" ou "qual líder aprovou?" exige consulta direta à tabela, que é o que este
arquivo documenta. Ver a issue de acompanhamento.
