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

**Exemplo concreto (#1152 — aprovar a VERSÃO ≠ assinar a CONTRAPARTE do instrumento):**
- `president_go` aprova a **versão** do documento (torná-la vigente) e exige SEMPRE `legal_signer`
  (SEDE/board PMI-GO). Ivan Lourenço (`chapter_board` + `legal_signer`, PMI-GO) satisfaz.
- Lorena Souza tem `['chapter_board', 'voluntariado_director']` mas NÃO `legal_signer`. Em
  `_can_sign_gate(lorena, chain, 'president_go', 'volunteer_term_template')` → **`false`** (o carve-out
  `voluntariado_director` foi REMOVIDO em #1152/#1155, mig `20260805000353`; corpo vivo hoje):
  ```sql
  v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(designations)
    AND 'legal_signer' = ANY(designations)   -- sem carve-out voluntariado_director
  ```
- Por quê: aprovar a versão do template (governança documental) é ato distinto de assinar a
  **contraparte** da entidade promotora em cada Termo EXECUTADO junto ao voluntário. A contra-assinatura
  da Lorena é mecânica **pós-aprovação**, por-adesão (roteada via `signature_flow` / fila), NÃO um gate
  de versão. Fundir os dois era o defeito do #1152 (e um cheiro de segregação de funções). Ver
  memória `reference-volunteer-term-countersign-lorena`.
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
| Aprovar VERSÃO de termo voluntariado (`president_go`) | 2 (designation `legal_signer` + `chapter_board` + chapter='PMI-GO') — #1152: NÃO `voluntariado_director` | — |
| Assinar CONTRAPARTE de cada Termo executado (Lorena) | pós-aprovação, por-adesão via `signature_flow` — NÃO é gate de versão | — |
| Assinar IP Adendo como curator | 2 (designation `curator`) — gate kind `curator` | — |
| Comentar em document chain | 1 (`participate_in_governance_review`) | — (ADR-0041) |
| Ler PII de membros | 1 (`view_pii`) | 3 (RPC scope-filtered como `get_chapter_dashboard`) |
| Ler dashboards do próprio chapter | 1 (`view_chapter_dashboards`) | 3 (`get_volunteer_agreement_status` faz scope inline) |
| Ler analytics globais (todos chapters) | 1 (`view_internal_analytics` + `manage_platform`) | — |
| Aprovar gate `chapter_witness` | 2 (designation `chapter_liaison` OR `chapter_board` em grace window) | — |
| Gerenciar tribo própria (líder) | 1 (`manage_event` + `write_board` em escopo initiative) | — |

Quando uma capability tem path alternativo (3), **a action V4 (path 1) é a porta de entrada**, e o RPC implementa o scoping. Não há gap se o path 3 já cobre o caso. Não adicionar combos novos ao path 1 sem confirmar que isso não duplica o que o path 3 já faz.

---

## Mapa função → gate de assinatura (`_can_sign_gate`) — #1152

Fonte de verdade = **corpo vivo** de `public._can_sign_gate` (`pg_get_functiondef`), não este doc.
A tabela abaixo é o retrato do corpo vivo (auditado 2026-07-21); atualize junto com qualquer DDL.

| `gate_kind` | Quem satisfaz (predicado) | Observação |
|---|---|---|
| `curator` | `can_by_member('curate_content')` | Path 1 (não designation). ADR-0087. |
| `leader` | `sign_chain_leader` **E** líder da iniciativa DO documento | #666: `project_charter` sem iniciativa falha CLOSED; docs org sem iniciativa (policy/cooperation/termo) caem no bare capability. |
| `leader_awareness` | `sign_chain_leader` (amplo) | Ciência, não aprovação. |
| `submitter_acceptance` | `member.id = submitter` | Quem abriu a chain aceita. |
| `president_go` | PMI-GO + `chapter_board` + `legal_signer` | **#1152/#1155: SEM `voluntariado_director`.** Aprova a VERSÃO. |
| `president_others` | CE/DF/MG/RS + `chapter_board` + `legal_signer` | Simétrico ao president_go. |
| `partner_consultation` | mesmo predicado de `president_others` | Caráter consultivo/janelado vive em `_gate_threshold_met` (`window_optional`, não-bloqueante), NUNCA aqui (#654/#975). |
| `committee_majority` | **`false` (STUB)** | Até §7.1 fixar roster/quórum do Comitê de Curadoria. `ip_committee` designation = 0 membros hoje. Go-live: trocar por `'ip_committee' = ANY(designations)`. |
| `cert_director_go` | PMI-GO + `certificacao_director` (+ doc `project_charter`) | ADR-0016 Am.4. Validação interna, não contra-assinatura jurídica. |
| `chapter_witness` | `chapter_liaison` (role/designation) OU `chapter_vice_president` (fallback se não há liaison) OU `chapter_board` em janela de graça 60d de cooperation_agreement | — |
| `volunteers_in_role_active` | active + NÃO pré-onboarding + engagement volunteer ativo (researcher/leader/manager) | #625: exclui pré-onboarding (defeito circular #654). |
| `external_signer` | `auth_engagements.kind='external_signer'` autoritativo | — |
| `member_ratification` | **`false` (STUB legado)** | — |

**Distinção-chave (#1152): aprovação de VERSÃO ≠ contraparte do INSTRUMENTO.** Gates aprovam a versão
do documento (torná-la vigente). Assinar a contraparte da entidade promotora em cada Termo executado
(Lorena, `voluntariado_director`) é mecânica pós-aprovação, por-adesão, via `signature_flow` — **não** é
um `gate_kind`. Nunca reintroduzir `voluntariado_director` em `president_go`.

**Resíduo aberto #1152 (Achado 2) — `committee_majority` no default de `policy`.** `resolve_default_gates('policy')`
ainda entrega `committee_majority` (order 1, `false`) → uma policy que use o DEFAULT trava no gate 1. Mas a
policy real em uso (PI, `cfb15185`) já roda numa **chain custom** `[curator, leader_awareness,
submitter_acceptance, president_go, president_others]` que evita o stub. Nada travado hoje; o fix do default
é forward-only e é uma decisão de barra de aprovação (ver decisão pendente na fila Wave 2 do #1152).

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

## Eixo ortogonal: visibilidade ≠ autoridade-de-ação (ADR-0105, #785)

Os três caminhos acima respondem **"o caller PODE fazer a action X?"** (autoridade-de-ação). A
confidencialidade de iniciativas (ADR-0105) introduz um **eixo ortogonal** que responde uma pergunta
diferente: **"o caller PODE VER esta linha?"** (visibilidade). Não confundir os dois — uma iniciativa
confidencial não muda quem tem `write_board` ou `manage_member`; muda apenas quem enxerga suas linhas.

**Mecanismo:** helper único `rls_can_see_initiative(p_initiative_id)` (`SECURITY DEFINER STABLE`) que
reusa o mesmo padrão de scope do Caminho 1 (`auth_engagements.initiative_id`, como `view_pii` faz).
Retorna `true` para:
- `initiative_id IS NULL` (linhas org-level sem iniciativa — read-all preservado);
- iniciativa `standard` (piso = org-members-only, inalterado);
- iniciativa `confidential` em que o caller tem engagement autoritativo;
- superadmin / `manage_platform` (decisão PM #1 — GP sempre vê).

**Por que é um eixo separado e não um Caminho 4:** os Caminhos 1–3 concedem *capacidade de agir*; o gate
de visibilidade *filtra linhas* numa dimensão de confidencialidade. Como o helper devolve `true` para tudo
que não é confidencial, o caminho não-confidencial é byte-idêntico ao anterior — não há gap a auditar nos
Caminhos 1–3 por causa dele.

**Defesa em profundidade (obrigatória):** RLS (RESTRICTIVE SELECT cascade) **e** gate explícito nas RPCs
`SECURITY DEFINER` de leitura são ambos necessários — SECDEF **bypassa** RLS, então RLS sozinha não basta.
⚠️ **Checklist ao criar uma RPC SECDEF nova que lê** `initiatives`/`events`/`project_boards`/`board_items`/
`meeting_artifacts`/`tribe_deliverables`/`recurring_meeting_rules`/`governance_documents`: chamar
`rls_can_see_initiative()` (ou o resolver `rls_can_see_board()`/`rls_can_see_artifact_link()`), senão a RPC
**vaza** linhas confidenciais. Curadoria exclui confidenciais por padrão (decisão PM #2); agregados públicos
filtram `visibility <> 'confidential'`.

**Quem seta a visibilidade:** `create_initiative` (qualquer criador na org — subir o muro é inócuo) e
`update_initiative` (gated pelo `can(...,'manage_member','initiative',id)` já existente — coordenador/GP;
baixar `confidential→standard` expõe dados, logo fica atrás desse mesmo gate + oversight de GP).

## Gate de leitura de governança: `rls_is_authoritative_member` (não `rls_is_member`)

Há dois helpers de leitura que parecem intercambiáveis mas **não são**:

- `rls_is_member()` = **existência de linha** (`EXISTS member WHERE auth_id = auth.uid()`). Sem filtro
  `is_active`: passa até membro inativo/offboarded com linha remanescente ou guest pré-onboarding.
- `rls_is_authoritative_member()` = ativo **e** `operational_role` real (`NOT NULL`, `<> 'guest'`,
  `<> 'institutional_auditor'`).

**Regra (sedimentada #1397 → #1408 → #1419):** a superfície de **leitura de aprovação de governança** é
gated no helper **estreito** `rls_is_authoritative_member()`, não no amplo `rls_is_member()`:
- `get_cr_approval_status` + policy SELECT de `cr_approvals` — estreitados no #1408 (defense-in-depth do #1397).
- `get_governance_dashboard` — estreitado no **#1419** (migração `20260805000464`). Antes, qualquer linha em
  `members` lia o corpo completo de toda CR pendente (title/description/justification/proposed_changes/impact)
  + stats de quórum. Não vazava PII nem voto de terceiro (só `my_vote` + agregados), mas o *conteúdo* das
  propostas de governança é a mesma classe de dado que o #1408 fechou. Caller autenticado porém
  não-autoritativo agora recebe `{error:'not_authorized'}`; o frontend renderiza a mensagem de acesso em vez
  de um dashboard zerado enganoso (defere ao gate do servidor, não duplica o predicado de autoridade em TS).

**Assimetria read↔write resolvida:** o *write* (`approve_change_request`) já era authority-gated (#1397); o
#1419 alinhou o *read* ao mesmo nível. Nota: `rls_is_authoritative_member` (read) é **mais amplo** que a
autoridade de *aprovar* (sponsor/`manage_platform`) — um líder autoritativo navega as CRs pendentes mas só
sponsors/GP votam. Isso é intencional (mesmo modelo do #1408).

**Precedente do sweep de policies:** `20260805000246_rls_phase2_authoritative_member.sql` fez esse swap em 23
policies SELECT mas deixou corpos de função intactos. As RPCs SECDEF de governança são o análogo-por-função
desse trabalho — ao criar uma RPC de leitura sobre superfície de governança, gate em `rls_is_authoritative_member()`.

## Quando este doc precisa de update

- **Path 4 emerge:** se uma 4ª maneira de conceder autoridade é introduzida (ex: ABAC com row-level expressions). Adicionar com exemplo + procedure update.
- **Designation nova:** quando uma nova designation é introduzida (ex: `voluntariado_co_director`), adicionar à matriz na seção "Caminho 2".
- **ADR novo de auth:** se ADR-00XX altera o modelo (ex: ADR-0070+ adiciona `manage_member_in_chapter`), refletir aqui.
- **Eixo de visibilidade novo:** se um novo valor de `initiatives.visibility` (ex: `restricted_to_kinds`) ou uma nova dimensão de confidencialidade for introduzida (ADR-0105), atualizar a seção "Eixo ortogonal".

Mantenedor: PM (Vitor) ou platform-guardian agent quando audit V4 for executado.
