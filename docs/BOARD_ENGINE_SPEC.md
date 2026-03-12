# BoardEngine — Spec Técnica do Componente Genérico de Boards

**Data:** 12 de março de 2026  
**Autor:** Claude (a pedido de Vitor Maia Rodovalho, PM)  
**Status:** Spec para desenvolvimento  
**Schema base:** `project_boards` (13 boards) + `board_items` (354 cards) + `board_lifecycle_events`

---

## 1. VISÃO GERAL

Um único componente React (`BoardEngine`) que renderiza qualquer board do sistema,
consumindo diretamente o schema existente no Supabase. Zero tabelas novas.

```
<BoardEngine boardId="a6b78238-..." />           → Hub de Comunicação
<BoardEngine boardId="430df293-..." />           → T1: Radar Tecnológico
<BoardEngine boardId="86a8959c-..." />           → Publicações & Submissões
<BoardEngine domainKey="communication" />         → Resolve pelo domain_key
<BoardEngine tribeId={6} scope="tribe" />         → Board da Tribo 6
```

### 1.1 Instâncias previstas (já existem no DB)

| domain_key               | board_scope | Boards ativos | Uso                                      |
|--------------------------|-------------|---------------|------------------------------------------|
| research_delivery        | tribe       | 8 (T1–T8)    | Trabalho interno de cada tribo           |
| communication            | global      | 1 (Hub)       | Substitui Trello da equipe de Comms      |
| publications_submissions | global      | 1             | Publicações & submissões PMI             |
| (curatorship)            | global      | —             | Curadoria de conhecimento (view filtrada)|

### 1.2 O que o BoardEngine NÃO é

- Não é uma aplicação separada (é um componente React dentro do Astro)
- Não requer tabelas novas (consome `project_boards` + `board_items` + `board_lifecycle_events`)
- Não substitui o Supabase como source of truth (é uma view de leitura/escrita)
- Não é Trello/Jira (é focado nas jornadas específicas do Núcleo)

---

## 2. MAPEAMENTO SCHEMA → UI

### 2.1 project_boards → Board Config

```
board_name        → Título do board
columns (jsonb[]) → Colunas do Kanban (já são ["backlog","todo","in_progress","review","done"])
domain_key        → Routing + permissões
board_scope       → "global" | "tribe" (controla quem vê)
tribe_id          → Se scope=tribe, filtra por tribo
is_active         → Board visível ou arquivado
source            → "trello" | "notion" | "manual" (badge de origem)
```

### 2.2 board_items → Card

```
title             → Título do card
description       → Corpo (markdown com links — já tem dados ricos do Trello)
status            → Coluna atual ("backlog", "todo", "in_progress", "review", "done")
assignee_id       → UUID do membro responsável (FK → members)
reviewer_id       → UUID do revisor/curador (FK → members)
tags[]            → Tags livres (text[])
labels (jsonb)    → Labels coloridos (futuro: [{color, text}])
due_date          → Data limite
position          → Ordem dentro da coluna (int, para DnD)
attachments       → [{name, url}] — já tem dados do Trello
checklist         → [{text, done}] — subtarefas
curation_status   → Status de curadoria ("draft", "review", "approved", "rejected")
curation_due_at   → SLA de curadoria
cycle             → Ciclo do Núcleo (3 = atual)
source_card_id    → ID original do Trello/Notion (rastreabilidade)
source_board      → Board de origem (rastreabilidade)
```

### 2.3 board_lifecycle_events → Audit Trail

```
action            → "status_change", "assigned", "reviewed", "created", "archived"
previous_status   → Status anterior
new_status        → Status novo
reason            → Comentário/justificativa
actor_member_id   → Quem fez a ação
created_at        → Quando
```

---

## 3. ARQUITETURA DO COMPONENTE

```
src/components/islands/BoardEngine.tsx          ← Componente principal (Astro Island)
src/components/board/BoardKanban.tsx            ← View Kanban (colunas + DnD)
src/components/board/BoardList.tsx              ← View Lista (futuro, toggle)
src/components/board/CardCompact.tsx            ← Card no board (resumo)
src/components/board/CardDetail.tsx             ← Card expandido (modal/drawer)
src/components/board/CardCreate.tsx             ← Formulário de criação
src/components/board/CardChecklist.tsx          ← Subtarefas dentro do card
src/components/board/CardAttachments.tsx        ← Anexos do card
src/components/board/CardTimeline.tsx           ← Histórico (lifecycle_events)
src/components/board/MemberPicker.tsx           ← Seletor de assignee/reviewer
src/components/board/TagEditor.tsx              ← Editor de tags inline
src/components/board/BoardFilters.tsx           ← Barra de filtros
src/components/board/BoardHeader.tsx            ← Título + stats + ações
src/hooks/useBoard.ts                          ← Hook: fetch board + items
src/hooks/useBoardMutations.ts                 ← Hook: create/update/move/delete
src/hooks/useBoardFilters.ts                   ← Hook: search + filter state
src/hooks/useBoardPermissions.ts               ← Hook: quem pode o quê
src/types/board.ts                             ← Types TypeScript
```

### 3.1 Fluxo de dados

```
                    ┌─────────────────────┐
                    │   Astro Page (.astro)│
                    │                     │
                    │  <BoardEngine       │
                    │    boardId="..."     │
                    │    client:load />    │
                    └────────┬────────────┘
                             │ hydrate
                    ┌────────▼────────────┐
                    │   BoardEngine.tsx    │
                    │                     │
                    │  useBoard(boardId)   │──── sb.from('project_boards')
                    │  useBoardMutations() │──── sb.from('board_items')
                    │  useBoardFilters()   │──── client-side filter
                    │  useBoardPermissions │──── member role check
                    └────────┬────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼───┐  ┌──────▼─────┐  ┌─────▼──────┐
     │ BoardHeader│  │BoardFilters│  │BoardKanban │
     │ title,stats│  │search,tags │  │ DndContext │
     └────────────┘  └────────────┘  │            │
                                     │ Column × N │
                                     │  Card × M  │
                                     └─────┬──────┘
                                           │ click
                                     ┌─────▼──────┐
                                     │ CardDetail  │
                                     │ modal/drawer│
                                     │             │
                                     │ ┌─────────┐ │
                                     │ │Checklist│ │
                                     │ │Attach.  │ │
                                     │ │Timeline │ │
                                     │ │Assignee │ │
                                     │ │Tags     │ │
                                     │ └─────────┘ │
                                     └─────────────┘
```

---

## 4. FEATURES POR COMPONENTE

### 4.1 BoardHeader

- Título do board (de `project_boards.board_name`)
- Badge de origem: 🟦 Trello | 🟨 Notion | ✋ Manual
- Stats: total cards, por status, overdue count
- Botão "+ Novo Card"
- Toggle view: Kanban | Lista (futuro)
- Badge de tribo (se `board_scope = 'tribe'`)

### 4.2 BoardFilters

- Search (título + descrição)
- Filtro por status (multi-select das colunas)
- Filtro por assignee (MemberPicker)
- Filtro por tags
- Filtro por due_date (vencidos, próximos 7 dias, sem data)
- Filtro por curation_status (para boards de curadoria)
- Clear all filters

### 4.3 BoardKanban (usa @dnd-kit)

- Colunas dinâmicas (lê `project_boards.columns`)
- Labels customizáveis por coluna:

```ts
const COLUMN_LABELS: Record<string, ColumnMeta> = {
  backlog:     { label: 'Backlog',      icon: '📋', color: 'slate'   },
  todo:        { label: 'A Fazer',      icon: '📌', color: 'blue'    },
  in_progress: { label: 'Em Andamento', icon: '🔨', color: 'amber'   },
  review:      { label: 'Revisão',      icon: '🔍', color: 'purple'  },
  done:        { label: 'Concluído',    icon: '✅', color: 'emerald' },
};
```

- DnD com @dnd-kit (PointerSensor + TouchSensor + KeyboardSensor)
- Reorder dentro da mesma coluna (atualiza `position`)
- Move entre colunas (atualiza `status` + registra `board_lifecycle_events`)
- Column count badge
- Empty column placeholder

### 4.4 CardCompact (card no board)

Informação visível sem abrir o card:

```
┌──────────────────────────────────┐
│ 📄 Planejamento ciclo 3          │  ← title
│                                  │
│ 🏷️ tag1  tag2                    │  ← tags (max 3)
│ 📎 3  ☑️ 2/5  📅 15 Mar          │  ← attachments, checklist, due_date
│                                  │
│ 👤 Avatar   🔍 Avatar            │  ← assignee + reviewer
│ ┌──────────┐ ┌──────────┐       │
│ │ ✅ Aprovar│ │ 🔍 Revisar│       │  ← quick actions (contextual)
│ └──────────┘ └──────────┘       │
└──────────────────────────────────┘
```

Badges condicionais:
- 📎 N — se `attachments.length > 0`
- ☑️ X/Y — se `checklist.length > 0` (done/total)
- 📅 Date — se `due_date` existe (vermelho se vencido)
- 🔴 SLA — se `curation_due_at` está próximo/vencido
- 🟦 Trello — se `source = 'trello'`
- 👤 Avatar — se `assignee_id` existe

### 4.5 CardDetail (modal/drawer ao clicar)

Layout em duas colunas no desktop, scroll no mobile:

**Coluna principal (esquerda):**
- Título (editável inline)
- Descrição (editável, markdown preview)
- Checklist/Subtarefas (add, toggle, delete, reorder)
- Attachments (lista com links clicáveis, badge de tipo)
- Comentários/Timeline (lifecycle_events cronológico)

**Sidebar (direita):**
- Status (dropdown — move entre colunas)
- Assignee (MemberPicker)
- Reviewer (MemberPicker)
- Tags (TagEditor)
- Labels (color picker, futuro)
- Due Date (date picker)
- Curation Status (se board tem curadoria)
- Ciclo (read-only ou editável)
- Source info (Trello/Notion link original)
- Ações: Arquivar, Duplicar, Mover para outro board

### 4.6 CardCreate

Formulário minimalista (não pedir tudo de cara):

```
┌─────────────────────────────────────┐
│ Título *                            │
│ [____________________________]      │
│                                     │
│ Descrição (opcional)                │
│ [____________________________]      │
│ [____________________________]      │
│                                     │
│ Responsável    │ 👤 Selecionar      │
│ Tags           │ 🏷️ Adicionar       │
│ Data limite    │ 📅 Selecionar      │
│                                     │
│        [ Criar Card ]               │
└─────────────────────────────────────┘
```

- Card criado no status `backlog` por padrão
- `position` = max(position) + 1 na coluna
- `board_lifecycle_events` registra criação
- `cycle` = ciclo atual (3)

### 4.7 CardChecklist

O campo `checklist` já é `jsonb` com default `'[]'::jsonb`.

Estrutura esperada:
```json
[
  { "text": "Definir escopo do artigo", "done": true },
  { "text": "Pesquisar referências", "done": false },
  { "text": "Redigir primeiro draft", "done": false }
]
```

UI:
- Checkbox + texto para cada item
- Add new item (input + Enter)
- Delete item (X)
- Drag reorder (opcional, pode ser V2)
- Progress bar visual (2/5 = 40%)
- Inline edit do texto

### 4.8 CardAttachments

O campo `attachments` já é `jsonb` com dados reais do Trello.

Estrutura existente:
```json
[
  {
    "name": "Mapa Brasil_NIA_Post 1.png",
    "url": "https://trello.com/1/cards/.../download/..."
  }
]
```

UI:
- Lista de links clicáveis com ícone por tipo (📄 doc, 🖼️ imagem, 🔗 link)
- Badge de contagem no CardCompact
- Futuro: upload via Supabase Storage

### 4.9 CardTimeline (lifecycle_events)

Consulta `board_lifecycle_events` filtrado por `item_id`.

```
📋 12 Mar 14:30 — Vitor moveu de "Backlog" para "Em Andamento"
👤 12 Mar 15:00 — Fabricio atribuído como revisor
✅ 13 Mar 09:15 — Fabricio aprovou
   Motivo: "Artigo bem estruturado, pronto para publicação"
```

### 4.10 MemberPicker

Dropdown que busca membros por tribo (se board é tribe-scoped) ou todos (se global).

```sql
-- Para boards de tribo:
SELECT id, full_name, avatar_url FROM members WHERE tribe_id = $1 AND is_active = true;

-- Para boards globais:
SELECT id, full_name, avatar_url FROM members WHERE is_active = true;
```

Mostra avatar + nome, search integrado.

---

## 5. PERMISSÕES (useBoardPermissions)

Baseado no `operational_role` e `designations` do membro logado + `board_scope`:

| Ação                    | Superadmin | Manager | Tribe Leader | Researcher | Comms Team | Observer |
|-------------------------|-----------|---------|-------------|------------|------------|----------|
| Ver board global        | ✅        | ✅      | ✅          | ✅         | ✅         | ✅       |
| Ver board da própria tribo | ✅     | ✅      | ✅          | ✅         | —          | ✅       |
| Ver board de outra tribo | ✅       | ✅      | ❌          | ❌         | —          | ❌       |
| Criar card              | ✅        | ✅      | ✅          | ✅         | ✅ (comms) | ❌       |
| Editar próprio card     | ✅        | ✅      | ✅          | ✅         | ✅         | ❌       |
| Editar qualquer card    | ✅        | ✅      | ✅ (tribo)  | ❌         | ❌         | ❌       |
| Mover card (DnD)        | ✅        | ✅      | ✅          | ✅ (próprio)| ✅ (comms)| ❌       |
| Atribuir assignee       | ✅        | ✅      | ✅ (tribo)  | ❌         | ✅ (comms) | ❌       |
| Aprovar/Rejeitar (curation) | ✅    | ✅      | ✅ (tribo)  | ❌         | ❌         | ❌       |
| Deletar/Arquivar card   | ✅        | ✅      | ✅ (tribo)  | ❌         | ❌         | ❌       |

Implementação via RLS no Supabase + check client-side para esconder botões.

---

## 6. RPCs NECESSÁRIAS (Supabase)

O frontend deve usar RPCs `SECURITY DEFINER` para evitar recursão RLS.

### 6.1 Leitura

```sql
-- Busca board config + items em uma chamada
CREATE OR REPLACE FUNCTION get_board(p_board_id uuid)
RETURNS jsonb AS $$
  SELECT jsonb_build_object(
    'board', (SELECT row_to_json(b) FROM project_boards b WHERE b.id = p_board_id),
    'items', (
      SELECT coalesce(jsonb_agg(row_to_json(i) ORDER BY i.position), '[]'::jsonb)
      FROM board_items i WHERE i.board_id = p_board_id
    ),
    'member_count', (
      SELECT count(*) FROM board_items i 
      WHERE i.board_id = p_board_id AND i.assignee_id IS NOT NULL
    )
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Busca timeline de um card
CREATE OR REPLACE FUNCTION get_card_timeline(p_item_id uuid)
RETURNS SETOF board_lifecycle_events AS $$
  SELECT * FROM board_lifecycle_events 
  WHERE item_id = p_item_id 
  ORDER BY created_at DESC;
$$ LANGUAGE sql SECURITY DEFINER;

-- Busca membros para o MemberPicker
CREATE OR REPLACE FUNCTION get_board_members(p_board_id uuid)
RETURNS TABLE(id uuid, full_name text, avatar_url text) AS $$
  SELECT m.id, m.full_name, m.avatar_url
  FROM members m
  WHERE m.is_active = true
  AND (
    -- Se board é global, retorna todos
    EXISTS (SELECT 1 FROM project_boards b WHERE b.id = p_board_id AND b.board_scope = 'global')
    OR
    -- Se board é tribe, retorna membros da tribo
    EXISTS (
      SELECT 1 FROM project_boards b 
      WHERE b.id = p_board_id AND b.board_scope = 'tribe' AND m.tribe_id = b.tribe_id
    )
  )
  ORDER BY m.full_name;
$$ LANGUAGE sql SECURITY DEFINER;
```

### 6.2 Escrita

```sql
-- Criar card
CREATE OR REPLACE FUNCTION create_board_item(
  p_board_id uuid,
  p_title text,
  p_description text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_tags text[] DEFAULT '{}',
  p_due_date date DEFAULT NULL
) RETURNS uuid AS $$
DECLARE
  v_id uuid;
  v_max_pos int;
BEGIN
  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = p_board_id AND status = 'backlog';
  
  INSERT INTO board_items (board_id, title, description, assignee_id, tags, due_date, position, cycle)
  VALUES (p_board_id, p_title, p_description, p_assignee_id, p_tags, p_due_date, v_max_pos, 3)
  RETURNING id INTO v_id;
  
  -- Log lifecycle event
  INSERT INTO board_lifecycle_events (board_id, item_id, action, new_status, actor_member_id)
  VALUES (p_board_id, v_id, 'created', 'backlog', auth.uid());
  
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mover card (DnD ou dropdown)
CREATE OR REPLACE FUNCTION move_board_item(
  p_item_id uuid,
  p_new_status text,
  p_new_position int DEFAULT 0,
  p_reason text DEFAULT NULL
) RETURNS void AS $$
DECLARE
  v_old_status text;
  v_board_id uuid;
BEGIN
  SELECT status, board_id INTO v_old_status, v_board_id
  FROM board_items WHERE id = p_item_id;
  
  -- Update item
  UPDATE board_items 
  SET status = p_new_status, position = p_new_position, updated_at = now()
  WHERE id = p_item_id;
  
  -- Reorder siblings
  UPDATE board_items 
  SET position = position + 1 
  WHERE board_id = v_board_id AND status = p_new_status 
    AND position >= p_new_position AND id != p_item_id;
  
  -- Log lifecycle event
  INSERT INTO board_lifecycle_events 
    (board_id, item_id, action, previous_status, new_status, reason, actor_member_id)
  VALUES 
    (v_board_id, p_item_id, 'status_change', v_old_status, p_new_status, p_reason, auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Atualizar card (título, descrição, tags, due_date, assignee, checklist, etc.)
CREATE OR REPLACE FUNCTION update_board_item(
  p_item_id uuid,
  p_fields jsonb  -- {"title": "...", "assignee_id": "...", "checklist": [...], etc.}
) RETURNS void AS $$
DECLARE
  v_board_id uuid;
  v_old_assignee uuid;
  v_new_assignee uuid;
BEGIN
  SELECT board_id, assignee_id INTO v_board_id, v_old_assignee
  FROM board_items WHERE id = p_item_id;
  
  -- Dynamic update based on provided fields
  UPDATE board_items SET
    title = coalesce(p_fields->>'title', title),
    description = coalesce(p_fields->>'description', description),
    assignee_id = CASE WHEN p_fields ? 'assignee_id' 
                       THEN (p_fields->>'assignee_id')::uuid 
                       ELSE assignee_id END,
    reviewer_id = CASE WHEN p_fields ? 'reviewer_id' 
                       THEN (p_fields->>'reviewer_id')::uuid 
                       ELSE reviewer_id END,
    tags = CASE WHEN p_fields ? 'tags' 
                THEN ARRAY(SELECT jsonb_array_elements_text(p_fields->'tags'))
                ELSE tags END,
    due_date = CASE WHEN p_fields ? 'due_date' 
                    THEN (p_fields->>'due_date')::date 
                    ELSE due_date END,
    checklist = CASE WHEN p_fields ? 'checklist' 
                     THEN p_fields->'checklist' 
                     ELSE checklist END,
    attachments = CASE WHEN p_fields ? 'attachments' 
                       THEN p_fields->'attachments' 
                       ELSE attachments END,
    curation_status = coalesce(p_fields->>'curation_status', curation_status),
    updated_at = now()
  WHERE id = p_item_id;
  
  -- Log assignment change
  v_new_assignee := CASE WHEN p_fields ? 'assignee_id' 
                         THEN (p_fields->>'assignee_id')::uuid 
                         ELSE v_old_assignee END;
  IF v_new_assignee IS DISTINCT FROM v_old_assignee THEN
    INSERT INTO board_lifecycle_events 
      (board_id, item_id, action, reason, actor_member_id)
    VALUES 
      (v_board_id, p_item_id, 'assigned', 
       'Atribuído a ' || coalesce((SELECT full_name FROM members WHERE id = v_new_assignee), 'N/A'),
       auth.uid());
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Duplicar card
CREATE OR REPLACE FUNCTION duplicate_board_item(
  p_item_id uuid,
  p_target_board_id uuid DEFAULT NULL  -- NULL = mesmo board
) RETURNS uuid AS $$
DECLARE
  v_new_id uuid;
  v_board_id uuid;
  v_max_pos int;
BEGIN
  SELECT coalesce(p_target_board_id, board_id) INTO v_board_id FROM board_items WHERE id = p_item_id;
  
  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = v_board_id AND status = 'backlog';
  
  INSERT INTO board_items (board_id, title, description, tags, labels, checklist, attachments, cycle, position)
  SELECT v_board_id, title || ' (cópia)', description, tags, labels, checklist, attachments, cycle, v_max_pos
  FROM board_items WHERE id = p_item_id
  RETURNING id INTO v_new_id;
  
  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES (v_board_id, v_new_id, 'created', 'Duplicado de ' || p_item_id::text, auth.uid());
  
  RETURN v_new_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mover card para outro board
CREATE OR REPLACE FUNCTION move_item_to_board(
  p_item_id uuid,
  p_target_board_id uuid
) RETURNS void AS $$
DECLARE
  v_old_board_id uuid;
  v_max_pos int;
BEGIN
  SELECT board_id INTO v_old_board_id FROM board_items WHERE id = p_item_id;
  
  SELECT coalesce(max(position), -1) + 1 INTO v_max_pos
  FROM board_items WHERE board_id = p_target_board_id AND status = 'backlog';
  
  UPDATE board_items 
  SET board_id = p_target_board_id, status = 'backlog', position = v_max_pos, updated_at = now()
  WHERE id = p_item_id;
  
  -- Log in both boards
  INSERT INTO board_lifecycle_events (board_id, item_id, action, reason, actor_member_id)
  VALUES 
    (v_old_board_id, p_item_id, 'moved_out', 'Movido para outro board', auth.uid()),
    (p_target_board_id, p_item_id, 'moved_in', 'Recebido de outro board', auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## 7. PÁGINAS ASTRO (ROUTING)

Cada jornada tem sua página, mas todas usam o mesmo componente:

```
src/pages/admin/curatorship.astro     → <BoardEngine domainKey="publications_submissions" mode="curation" />
src/pages/admin/comms.astro           → <BoardEngine domainKey="communication" />
src/pages/tribe/[id]/board.astro      → <BoardEngine tribeId={id} scope="tribe" />
src/pages/publications.astro          → <BoardEngine domainKey="publications_submissions" />

# Versões i18n:
src/pages/en/admin/curatorship.astro  → (mesma coisa, i18n em inglês)
src/pages/es/admin/curatorship.astro  → (mesma coisa, i18n em espanhol)
```

O prop `mode` controla quais features extras são visíveis:
- `mode="default"` → Board completo (criar, editar, mover, atribuir)
- `mode="curation"` → Mostra curation_status, SLA badges, rubric dialog
- `mode="readonly"` → Apenas visualização (para observers)

---

## 8. DEPENDÊNCIAS

```bash
npm install @dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities
# O @dnd-kit continua sendo a engine de DnD — é a peça certa para esse job.
# O erro foi usar só ela sem construir as camadas de produto em cima.
```

Nenhuma outra dependência externa necessária. O restante é React + Tailwind + Supabase client (já no projeto).

---

## 9. PLANO DE IMPLEMENTAÇÃO (Sprints sugeridos)

### Sprint 1 — Fundação (1 semana)
- [ ] Criar RPCs: `get_board`, `move_board_item`, `create_board_item`
- [ ] Criar `BoardEngine.tsx` com `useBoard` hook
- [ ] `BoardKanban` com @dnd-kit (colunas dinâmicas do DB)
- [ ] `CardCompact` com badges (attachments, checklist, due_date, assignee)
- [ ] Integrar na `/admin/curatorship` substituindo o Island atual
- **Entrega:** Board funcional com DnD, cards mostram dados reais, criar card básico

### Sprint 2 — Card Detail (1 semana)
- [ ] `CardDetail` modal com layout 2 colunas
- [ ] Edição inline de título e descrição
- [ ] `CardChecklist` com add/toggle/delete
- [ ] `MemberPicker` para assignee e reviewer
- [ ] `TagEditor` inline
- [ ] Due date picker
- [ ] RPC: `update_board_item`
- **Entrega:** Card expandido com todas as features de edição

### Sprint 3 — Lifecycle + Permissões (1 semana)  
- [ ] `CardTimeline` consumindo `board_lifecycle_events`
- [ ] `useBoardPermissions` hook
- [ ] Esconder botões baseado em permissão
- [ ] RPC: `get_card_timeline`
- [ ] Registrar todos os eventos (move, assign, edit)
- **Entrega:** Audit trail completo, permissões funcionais

### Sprint 4 — Multi-board + Comms (1 semana)
- [ ] Página `/tribe/[id]/board.astro` para boards de tribo
- [ ] Integrar na `/admin/comms` (substitui Trello)
- [ ] `duplicate_board_item` RPC
- [ ] `move_item_to_board` RPC
- [ ] Board selector (para mover cards entre boards)
- **Entrega:** Comms team migrado do Trello, tribos com boards próprios

### Sprint 5 — Polish + Webinars (1 semana)
- [ ] `BoardFilters` completo (search, assignee, tags, due_date)
- [ ] Keyboard shortcuts (N = novo card, / = search)
- [ ] Mobile responsiveness final
- [ ] Webinars board (se schema de webinars convergir)
- [ ] Smoke tests
- **Entrega:** Production-ready para todos os 66+ membros

---

## 10. DECISÃO PENDENTE: CURADORIA COMO BOARD OU COMO VIEW

Hoje a curadoria usa `curation_status` dentro de `board_items` + RPCs separadas (`list_curation_board`, `curate_item`).

**Opção A — Curadoria como mode do BoardEngine:**
- `mode="curation"` mostra badges de SLA, rubric dialog, curation_status
- Filtra cards que têm `curation_status != 'approved'`
- Usa as mesmas RPCs do BoardEngine (`move_board_item` com status mapping)
- PRO: Uma abstração, zero código duplicado
- CON: Precisa mapear curation_status para as colunas do board

**Opção B — Curadoria como view separada sobre os mesmos dados:**
- Mantém o Island atual como read-model
- Cards de curadoria são puxados de múltiplos boards (cross-board)
- PRO: Curadoria é cross-board por natureza (revisa itens de todas as tribos)
- CON: Dois componentes para manter

**Recomendação:** Opção B para a view de curadoria cross-board (comitê revisa tudo), 
Opção A para curadoria intra-board (líder revisa cards da própria tribo).

---

*Esta spec mapeia 100% para o schema Supabase existente. Zero tabelas novas.
O @dnd-kit é a engine correta — o gap era a camada de produto em cima.*
