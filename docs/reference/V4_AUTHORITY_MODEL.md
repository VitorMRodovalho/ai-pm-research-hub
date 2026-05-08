# V4 Authority Model — três caminhos paralelos + procedimento de audit

**Status:** Operational reference
**Created:** 2026-05-08 (p122e — sediment de auditoria que falhou em ADR-0041 follow-up)
**Audience:** quem audita permissões V4, propõe seed expansion, ou converte gates V3→V4
**Cross-refs:** [ADR-0007](../adr/ADR-0007-authority-as-engagement-grant.md) (engagement-grants source of truth), [ADR-0011](../adr/ADR-0011-v4-auth-pattern-rpcs-mcp.md) (V4 auth pattern em RPCs+MCP), [ADR-0041](../adr/ADR-0041-governance-review-action-and-9-fns.md) (participate_in_governance_review action)

---

## Por que este doc existe

A V4 (refactor concluído 2026-04-13) substituiu role-list hardcoded por autoridade derivada de engagements. Mas a transição preservou **três mecanismos paralelos** de concessão de autoridade — cada um para um caso de uso distinto. Auditorias mecânicas que olham apenas um dos três produzem **false positives recorrentes** ("a action X só tem 3 combos seedados, há um gap!") que levam a propostas perigosas (seed expansion ampla → privilege escalation).

Este doc descreve os três caminhos, dá exemplos concretos de cada um, e fornece um procedimento de audit que evita o false positive.

---

## Os três caminhos paralelos

### Caminho 1 — `engagement_kind_permissions` (o canônico V4)

**Tabela:** `engagement_kind_permissions(kind, role, action, scope, description)`

**Como funciona:** quando uma RPC faz `can_by_member(member_id, 'action_x')`, a função olha as `auth_engagements` ativas do membro e verifica se algum `(kind, role)` está seedado para `action_x`. Resultado é boolean.

**Quando usar:** autoridade que se concede via tipo-de-vínculo (volunteer × manager → tudo de gestão; chapter_board × board_member → ler chapters). É o modelo recomendado para qualquer action nova.

**Exemplo concreto:**
- Vitor tem `volunteer × manager` engagement → `can_by_member(vitor, 'manage_member')` retorna `true` porque a seed `('volunteer','manager','manage_member','organization')` existe.
- Fabricio tem `volunteer × co_gp` → mesmo resultado para `manage_platform`.

**Como auditar:**
```sql
SELECT kind, role, scope FROM engagement_kind_permissions WHERE action = 'X';
```

---

### Caminho 2 — gates baseados em **designations**

**Onde vive:** `_can_sign_gate(member_id, chain_id, gate_kind, doc_type)` é o exemplo mais relevante. Helpers similares (`_can_witness_chapter`, `chapter_grace_window`) seguem o mesmo padrão. Não usa `can_by_member`; verifica `members.designations[]` diretamente.

**Como funciona:** designations são tags imutáveis no perfil do membro (`legal_signer`, `voluntariado_director`, `chapter_liaison`, `chapter_board`, `curator`, `founder`, etc). Gates específicos do fluxo de assinatura legal aceitam combinações de designations que NÃO mapeiam 1:1 para engagement_kind_permissions.

**Por que não foi substituído pelo Caminho 1:** designations carregam semântica institucional (legal_signer = pessoa designada juridicamente como signatária; voluntariado_director = papel formal no chapter board). Esses são fatos institucionais, não vínculos operacionais derivados de cycles/initiatives. Misturar os dois confundiria semântica.

**Exemplo concreto:**
- Lorena Souza tem designations `['chapter_board', 'voluntariado_director']` + chapter `'PMI-GO'`.
- Em `_can_sign_gate(lorena, chain, 'president_go', 'volunteer_term_template')`:
  ```sql
  v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(designations)
    AND ('legal_signer' = ANY(designations)
      OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(designations)))
  ```
  → Lorena passa pelo branch `voluntariado_director` mesmo sem `legal_signer`.
- `can_by_member(lorena, 'manage_member')` retorna `false` corretamente — ela NÃO deve poder ativar/desativar membros (operação GP-only).

**Como auditar:**
```sql
-- Listar gates designation-based em pg_proc
SELECT proname, regexp_matches(prosrc, '''([a-z_]+)''\s*=\s*ANY\(\s*[a-z_]+\.?designations\s*\)', 'g')
FROM pg_proc WHERE pronamespace='public'::regnamespace AND prosrc LIKE '%designations%';
```

---

### Caminho 3 — RPCs com **inline scoping** (`v_caller_chapter`, `v_caller_tribe_id`)

**Onde vive:** dentro do corpo de RPCs específicos (read endpoints, dashboards). Padrão típico:
```sql
SELECT m.chapter INTO v_caller_chapter FROM members WHERE auth_id = auth.uid();
-- ...
WHERE (v_is_manage_member OR m.chapter = v_caller_chapter)
```

**Como funciona:** o RPC concede acesso a uma operação ampla (ex: ler agreement_status de todos os membros), mas o resultado é **escopado automaticamente** ao chapter/tribe do caller. Apenas usuários com authority global (`manage_member`) recebem dados de todos os chapters; demais usuários autorizados (chapter_board engagement) recebem apenas o próprio chapter.

**Quando usar:** quando o caso de uso pede granularidade chapter-scope sem precisar de uma action V4 nova. Padrão "least-privilege via filter".

**Exemplo concreto:**
- `get_volunteer_agreement_status()`:
  - Gate de entrada: `manage_member OR (chapter_board engagement active)`
  - Lorena entra (tem `chapter_board × board_member` ativo)
  - Resultado: `members WHERE (v_is_manage_member OR m.chapter = v_caller_chapter)` → para Lorena, retorna apenas membros PMI-GO
  - Mesmo membros de PMI-CE não aparecem na resposta — invisível por design

**Como auditar:**
```sql
-- RPCs com pattern inline scoping
SELECT proname FROM pg_proc 
WHERE pronamespace='public'::regnamespace
  AND prosecdef
  AND prosrc ~ 'v_caller_(chapter|tribe_id|person_id)';
```

---

## Matriz: capability → path correto

| Capability | Path canônico | Path alternativo |
|---|---|---|
| Ativar/desativar membro globalmente | 1 (`manage_member`) | — |
| Anonimizar membro (LGPD Art.18) | 1 (`manage_member`) | — |
| Assinar termo voluntariado como president_go | 2 (designation `voluntariado_director` + `chapter_board` + chapter='PMI-GO') | — |
| Assinar IP Adendo como curator | 2 (designation `curator`) — gate kind `curator` | — |
| Comentar em document chain | 1 (`participate_in_governance_review`) | — (ADR-0041) |
| Ler PII de membros | 1 (`view_pii`) | 3 (RPC scope-filtered como `get_chapter_dashboard`) |
| Ler dashboards do próprio chapter | 1 (`view_chapter_dashboards`) | 3 (`get_volunteer_agreement_status` faz scope inline) |
| Ler analytics globais (todos chapters) | 1 (`view_internal_analytics` + `manage_platform`) | — |
| Aprovar gate `chapter_witness` | 2 (designation `chapter_liaison` OR `chapter_board` em grace window) | — |
| Gerenciar tribo própria (líder) | 1 (`manage_event` + `write_board` em escopo initiative) | — |

Quando uma capability tem path alternativo (3), **a action V4 (path 1) é a porta de entrada**, e o RPC implementa o scoping. Não há gap se o path 3 já cobre o caso. Não adicionar combos novos ao path 1 sem confirmar que isso não duplica o que o path 3 já faz.

---

## Procedimento de audit (CHECKLIST 4 etapas)

Antes de declarar gap em `engagement_kind_permissions` ou propor seed expansion, executar **as 4 verificações**:

### ☐ Etapa 1 — Listar combos seedados
```sql
SELECT kind, role, scope FROM engagement_kind_permissions WHERE action = '<action>';
```
Sai com lista de N combos.

### ☐ Etapa 2 — Listar RPCs que usam a action
```sql
SELECT proname FROM pg_proc 
WHERE pronamespace='public'::regnamespace
  AND prosrc ~ ('can_by_member\([^,]+,\s*''<action>''');
```

Para cada RPC retornado, **abrir o body e verificar se o gate é puro (`IF NOT can_by_member(X)`) ou composto (`IF NOT (can_by_member(X) OR can_by_member(Y) OR ...)`)**. Composto = path alternativo path 1 já existe.

### ☐ Etapa 3 — Procurar designation-based gates equivalentes
```sql
SELECT proname FROM pg_proc 
WHERE pronamespace='public'::regnamespace
  AND prosrc ~ '<related_concept>\s*=\s*ANY\(';
```
Ex: para audit de `manage_member`, buscar `'voluntariado_director' = ANY`, `'chapter_board' = ANY`, etc. Designation-based gates podem cobrir a capability sem combo seedado.

### ☐ Etapa 4 — Procurar RPCs scope-filtered relacionados
```sql
SELECT proname FROM pg_proc 
WHERE pronamespace='public'::regnamespace
  AND prosecdef
  AND prosrc ~ 'v_caller_(chapter|tribe_id|person_id)'
  AND prosrc ILIKE '%<concept>%';
```
Ex: para `manage_member`, buscar `prosrc ILIKE '%volunteer%'` ou `%agreement%` para encontrar RPCs como `get_volunteer_agreement_status` que escopam por chapter sem precisar de combo extra.

### Se as 4 etapas terminarem sem path alternativo encontrado E o caso de uso real está bloqueado → **aí sim** é gap. Documentar com:
1. Caso de uso concreto (membro real bloqueado, RPC real falhando)
2. Por que paths 2 e 3 não cobrem (citação do código)
3. Proposta de seed (kind × role × action) com **justificativa de princípio LGPD/governance** para cada combo proposto

---

## Anti-pattern: seed expansion como atalho para "gap" não verificado

**Sintoma:** auditor olha `engagement_kind_permissions` × actions, vê N combos pequeno (ex: 3), conclui que falta cobertura, propõe ADD `chapter_board × X` sem verificar paths 2 e 3.

**Risco:**
- Em actions destrutivas (`manage_member`, `manage_platform`): privilege escalation. Member lifecycle vira acessível a chapter board → quebra invariante "anonimização é GP-only" (LGPD Art. 18).
- Em actions read: ainda assim cria duplo path (RPC composto OR + seed combo) — drift de governance, harder to reason about.

**Caso de exemplo (não fazer):** p122e proposed Solution C foi seed `chapter_board × board_member → manage_member`. Solution era WRONG porque (a) member lifecycle é GP-only by design, (b) Lorena já tinha tudo via paths 2+3 (`voluntariado_director` designation para sign + `get_volunteer_agreement_status` para read).

**Como evitar:** rodar o procedimento de audit acima ANTES de redigir proposta de seed.

---

## Quando este doc precisa de update

- **Path 4 emerge:** se uma 4ª maneira de conceder autoridade é introduzida (ex: ABAC com row-level expressions). Adicionar com exemplo + procedure update.
- **Designation nova:** quando uma nova designation é introduzida (ex: `voluntariado_co_director`), adicionar à matriz na seção "Caminho 2".
- **ADR novo de auth:** se ADR-00XX altera o modelo (ex: ADR-0070+ adiciona `manage_member_in_chapter`), refletir aqui.

Mantenedor: PM (Vitor) ou platform-guardian agent quando audit V4 for executado.
