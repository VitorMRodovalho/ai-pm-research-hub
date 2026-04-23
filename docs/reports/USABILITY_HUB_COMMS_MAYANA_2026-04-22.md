# Hub de Comunicação — Relatório de Usabilidade + Sessão 23/Abr

**Origem:** Relatório Mayanna Duarte (`comms_leader`, Tribo 8), recebido 22/Abr.
**Sessão de follow-up:** 23/Abr p36 — GP Vitor + AI pair (debug mode).
**Status do relatório original:** `/home/vitormrodovalho/Downloads/A/relatorio_usabilidade_hub comunicação.pdf`
**Board afetado:** `Hub de Comunicação` (id `a6b78238-11aa-476a-b7e2-a674d224fd79`, scope=global, domain_key=communication).

---

## Sumário executivo

| # | Tipo | Item | Status | Prioridade |
|---|---|---|---|---|
| 01 | Bug | Comentários no card | **Pendente — feature ausente** | ALTA |
| 02 | Bug | Adicionar responsável redireciona | **Fix aplicado (code review) — aguarda commit+deploy+repro** | ALTA |
| 03 | Bug | Não consegue adicionar atividades (checklist) | **Investigar após fix #02 entrar em prod** | ALTA |
| 04 | Limitação | Vídeos > 5MB | **Fix aplicado via anexo-por-link** | MÉDIA |
| 05 | Limitação de permissão | Status "concluído" só GP | **Discussão de governança necessária** | MÉDIA |
| 06 | Melhoria | Menções `@` em comentários | **Depende de #01** | MÉDIA |
| 07 | Melhoria/Integração | Drive / repositório | **Resolvido parcialmente por #04 (link)** | MÉDIA |
| — | Bug adjacente | Carlos Magno não consegue editar perfil | **Investigação em aberto — precisa runtime evidence** | MÉDIA |

---

## Bug #02 — Adicionar responsável redireciona para outra página

### Raiz (confirmada por code review + git blame)

`src/components/board/MemberPicker.tsx` referenciava `i18n.searchMember` (linha 58) e `i18n.noMemberFound` (linha 95), mas `i18n` **não era importado nem prop**. Regressão introduzida em `295d399` (2/abr, "i18n phase 3f — batch translate 13 components"). Ao abrir o dropdown, `ReferenceError: i18n is not defined` derruba o componente; React boundary faz unmount do modal e o usuário percebe como "redirect".

MemberPickerMulti não foi afetado (aceita `i18n` como prop corretamente). Só MemberPicker (single) tinha o bug — usado quando o card não tem assignments no junction table (caminho legacy de `assignee_id`/`reviewer_id`).

### Fix aplicado (sessão 23/Abr)

- `src/components/board/MemberPicker.tsx` — `i18n?: BoardI18n` agora é prop opcional; acessos via `?.` com fallback PT-BR hardcoded.
- `src/components/board/CardDetail.tsx` — passa `i18n={i18n}` nos dois `<MemberPicker>`.
- `src/components/board/CardCreate.tsx` — idem.
- `src/types/board.ts` — adiciona campos `searchMember`, `noMemberFound`, `claimCard` em `BoardI18n` + `DEFAULT_I18N`.

Build `npx astro build` passa. `npm test` mantém 1313/22 (22 falhas pré-existentes em tribe_dashboard/curation, não relacionadas).

### Pendente

- [ ] Commit + deploy
- [ ] Mayanna reproduzir em prod e confirmar fix
- [ ] Confirmar se Bug #03 (checklist) desaparece junto (hipótese: modal caía antes de ela testar o checklist)

---

## Bug #03 — Checklist activities

### Análise de permissões (code review)

Mayanna tem `operational_role='researcher'` + `designations=['comms_leader']`. Board Hub de Comunicação é `board_scope='global'`. Em `src/hooks/useBoardPermissions.ts`:

- `isComms = true` (tem `comms_leader` nas designations)
- `isGlobal = true` (board_scope)
- `isCommsOnGlobal = true` → `canEditAny = true` → `canEdit = true` no `CardDetail`

Logo o checklist **deveria** aparecer para ela. Hipóteses candidatas:

- **H1 (mais provável):** Bug #02 derruba o modal antes dela chegar a testar o checklist → falso-positivo, vai sumir junto quando #02 for deploy
- **H2:** `mode='readonly'` sendo setado em algum fluxo (`CardDetail` bloqueia checklist quando readonly)
- **H3:** RPC `board_item_checklists` INSERT com RLS rejeitando → precisa logs da network tab
- **H4:** Botão "+" renderiza mas `onClick={addCheckItem}` falha silenciosamente por Supabase client ausente

### Pendente

- [ ] Aguardar fix #02 em prod
- [ ] Mayanna tentar checklist de novo
- [ ] Se persistir, instrumentar `CardDetail` com telemetria em `canEdit`/`addCheckItem`

---

## Bug #01 — Comentários no card (FEATURE AUSENTE)

Não há tabela `board_item_comments` no schema. `CardDetail.tsx` nunca teve seção de comentários. É desenvolvimento novo.

### Escopo estimado (~3-4h)

1. **Migration** — tabela `board_item_comments` (id, board_item_id, author_member_id, body, parent_id?, mentions[], created_at, edited_at, deleted_at)
2. **RLS** — `read_board_comment` derivado de `canView` do board + `write_board_comment` derivado de `canEditAny OR (assignee|author of card)`
3. **RPCs** — `add_board_comment`, `edit_board_comment` (within 15min, pattern de `document_comments`), `delete_board_comment`, `list_board_comments`
4. **UI** — seção no `CardDetail` entre Timeline e ações; editor com mentions autocomplete (depende de #06)
5. **i18n** — 3 dicionários (pt-BR / en-US / es-LATAM)
6. **Notifications** — integrar com `notifications.kind='comment_mention'` e `notifications.kind='comment_reply'` (seguir ADR-0022 batching quando aplicável — comment_mention deveria ser `transactional_immediate`? a definir)

### Cross-ref

- Pattern existente: `document_comments` (7 rows em prod, tem threading + clause_anchor + 15min edit window via `trg_document_comment_enforce_edit_window`). Reusar pattern.
- ADR-0022 (batching) — comment types a classificar

---

## Limitação #04 — Vídeos > 5MB — **Fix aplicado**

GP endossou o caminho "link em vez de upload" (preserva storage + LGPD).

### Fix aplicado (sessão 23/Abr)

- `src/components/board/CardDetail.tsx`:
  - Novo estado `linkUrl`, `linkName`, `showLinkInput`
  - Função `detectEmbed(url)` — identifica YouTube / Vimeo / Drive / Loom / generic
  - Handler `handleAddLink` — valida URL, pega hostname como label default, grava em `attachments` com `kind='link'` e `embed=<provider>`
  - UI: botão "🔗 Colar link" ao lado de "+ Anexar arquivo"; formulário expansível com URL + rótulo opcional
  - Rendering: ícone por provider (▶️ YouTube / 🎬 Vimeo / 📁 Drive / 🎥 Loom / 🔗 generic) + badge textual ao lado do nome
- `src/types/board.ts`:
  - `Attachment` ganha `kind?: 'file' | 'link'` e `embed?: 'youtube'|'vimeo'|'drive'|'loom'|'generic'`
  - Retrocompatível com anexos antigos (sem `kind` = 'file')

### Pendente

- [ ] Commit + deploy
- [ ] Confirmar com Mayanna

---

## Limitação #05 — Status "concluído" só GP

### Análise

Em `useBoardPermissions.ts`:
```
canMove = canManageBoard || isCommsOnGlobal || (isOwnTribe && tier <= 4)
```

Mayanna (`comms_leader` em board global) tem `canMove=true`. O motivo dela ver "só GP pode" deve ser um caso específico ou experimentação com usuário diferente. **Confirmar com ela qual card + qual perfil ela estava logada.**

### Alternativa proposta pela Mayanna

"Revisar política de permissões para permitir que o responsável pela entrega atualize o status de conclusão"

Isso já seria equivalente a `canMove = ... || isCardAssignee` — factível, mas é decisão de governança (GP pode querer controlar transição "done" para garantir curadoria antes).

### Pendente

- [ ] Confirmar reprodução específica com Mayanna
- [ ] Decisão GP: card assignee pode mover para "done"? Ou apenas `in_review` e GP faz o último passo?

---

## Melhoria #06 — Menções `@` em comentários

Depende de #01 (comentários). Pattern sugerido:

- Detectar `@username` no body do comment
- Resolver contra `members.name`/`email`
- Criar `notifications.kind='comment_mention'` para cada menção
- Per ADR-0022: notification com `delivery_mode='transactional_immediate'` (menção é contextual)

---

## Melhoria #07 — Drive / repositório — **Parcialmente resolvida por #04**

Com anexo-por-link, usuária pode:
- Colar link Google Drive de arquivo único
- Colar link de pasta Drive compartilhada (links de pasta funcionam igual a arquivo — `drive.google.com/drive/folders/...`)

Para repositório **nativo** centralizado (fora do card):
- `hub_resources` table já existe (330 rows) — pode ser nova seção no board do comms
- Alternativa: bootstrap uma pasta raiz no Drive do Núcleo e linkar via `admin_links` (Tier 4)

### Pendente (opcional)

- [ ] Decisão: usar Drive como Single Source of Truth para arquivos da comms? Se sim, uma seção dedicada no board ou no navbar.

---

## Bug adjacente — Carlos Magno não consegue editar perfil

### Contexto reportado

GP Vitor (WhatsApp 23/Abr): "Carlos Magno me informou que ele não consegue, pós logado, ir no Perfil dele, editar as informações dele próprio. Ele realmente é um voluntário inativo, mas o Perfil dele deveria ficar inativo?"

### Estado atual no banco

```
member_id: f43ce173-****-****-****-f2ea47eabd5d
name:      Carlos Magno do HUB Cerrado
auth_id:   <set, login OK — UUID omitido por higiene de secret scan>
member_status:    alumni
operational_role: alumni
is_active:        false
designations:     []
tribe_id:         null
organization_id:  2b4f58ab-7c45-4170-8718-b77ee69ff906  (= auth_org(), RLS passa)
offboarded_at:    NULL  ⚠️  inconsistência (alumni sem offboard registrado)
inactivated_at:   2026-03-07 00:44:08  (data = created_at → provavelmente nunca ativou)
updated_at:       2026-04-23 19:05:36  (modificado hoje — por quem?)
```

### Code review — não encontrei bloqueio para alumni

- `src/pages/profile.astro:269` — `shouldRedirectFromProfile(member)` só redireciona se `operational_role === 'guest'`. Alumni passa.
- RLS em `members`:
  - `members_select_own` (SELECT, `auth_id = auth.uid()`) — passa
  - `member_update_own_profile` + `members_update_own` (UPDATE, `auth_id = auth.uid()`) — passa
  - `members_v4_org_scope` (ALL restrictive, `organization_id = auth_org()`) — passa
- RPCs:
  - `get_member_by_auth` — SECURITY DEFINER, não filtra status
  - `member_self_update`, `update_my_profile` — ambos chave por `auth_id = auth.uid()`, sem check de status

### Hipóteses de por que ele reporta "não consegue"

- **H1:** Chega no `/profile` mas form renderiza sem campos populados (alumni `operational_role` não está em `OPROLE_LABELS` de `profile.astro:217` — pode quebrar rendering de algum bloco e triggerar JS error silencioso)
- **H2:** Chega mas salvar falha silenciosamente (sem toast de erro)
- **H3:** `renderProfile` tem caminho hidden que oculta a section "Personal data"/"Save" quando `is_active=false`
- **H4:** Session mismatch — `auth.uid()` retorna UUID diferente do `members.auth_id` (usuário reautenticou com outro provider, criando novo user em `auth.users`)
- **H5:** Nav.astro retorna `_member = null` por algum caminho e dispara `nav:guest-with-session` → `renderNotRegistered()`

### Decisão de governança (separada do bug)

**O perfil de alumni DEVE continuar editável.** Razões:

1. **LGPD Art. 18 V** — direito de retificação é um direito do titular de dados, independente de status operacional
2. **UX** — se ex-voluntário quer atualizar LinkedIn/telefone para receber digest de alumni ou aceitar retorno futuro, precisa conseguir
3. **Precedente** — Pedro Henrique (offboardado hoje) também virou `observer` e deveria conseguir editar

O que **não deve** ser editável por alumni: `operational_role`, `designations`, `tribe_id`, `is_superadmin` (isso já é true — campos de governança não aparecem em `/profile` hoje).

### Pendente

- [ ] Pedir ao Carlos para gravar print/vídeo da tela + console DevTools ao tentar acessar `/profile`
- [ ] Ou: logar com a conta dele em ambiente de teste para reproduzir
- [ ] Se confirmado, instrumentar `profile.astro` com logs em `boot()` para capturar qual branch dispara (nav:member recebido? shouldRedirectFromProfile retorna true? `_member` null?)
- [ ] Adicionar `alumni` + `observer` em `OPROLE_LABELS` de `profile.astro:217-218` (fix UX mesmo que não seja o root cause)
- [ ] Normalizar Carlos no banco: setar `offboarded_at` para bater com `inactivated_at` OU retornar `member_status` para `inactive` se ele nunca foi voluntário (data suggere que não)

---

## Trabalho operacional aplicado na sessão (não relacionado ao report)

### Pedro Henrique Rodrigues Mendes — desligamento voluntário

Decidido via WhatsApp 22/Abr 12:40. Aplicado:

- `member_status`: active → **observer**
- `operational_role`: researcher → **guest** (recalculado pelo trigger `sync_operational_role_cache` — alumni/observer sem engagement ativo = guest; este é o comportamento V4 correto, não um erro)
- `designations`: `{}`
- Engagement `volunteer/researcher` em Governança & Trustworthy AI (Tribo 7) → `offboarded`
- Audit trail em `admin_audit_log`: `member.status_transition` + `member.role_change`
- Reason: `personal_agenda: desligamento voluntário — porta aberta`

### Roberto Macêdo — observer/curator na Tribo 8

Decidido 22/Abr com base em pedido do GP:

- Novo engagement: `kind=observer`, `role=curator`, `initiative_id=9cbaf0b9` (Inclusão & Colaboração & Comunicação)
- Metadata: "Apoio em metodologia de escrita e aumento de impacto dos artigos em publicação"
- Mantidos os 6 engagements ativos anteriores dele (chapter_board, ambassador, committee_coordinator Curadoria, committee_member Publicações, speaker LATAM LIM)

---

## Próximos passos recomendados

1. **Imediato (GP + dev team):** revisar este doc + decidir se commita os fixes #02 e #04 hoje/amanhã
2. **Curto prazo (1-2 dias):** confirmar reprodução de #03 com Mayanna após deploy do #02; investigar Carlos Magno
3. **Médio prazo (1-2 semanas):** scope de #01 (comentários) + #06 (menções) — abrir spec em `docs/specs/`
4. **Longo prazo:** decisão formal sobre #05 (permissão de concluir para assignee)
