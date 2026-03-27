# Kanban UX + Dark Mode Epic (2026-Q1)

## Objetivo

Evoluir a experiência operacional do Hub para um padrão mais fluido (estilo Linear/Trello), mantendo governança de acesso e sem bypass de RLS.

## Escopo aprovado (fase incremental)

1. **Dark Mode Foundation (já entregue)**
   - Toggle no drawer de perfil.
   - Persistência em `localStorage` (`ui_theme`).
   - Ativação por `data-theme` no `html`.
2. **Kanban Details Modal (já entregue)**
   - Clique no card para editar.
   - Criação rápida por coluna.
   - Arquivamento seguro via RPC.
3. **Kanban Metadata (já entregue)**
   - Edição de labels/checklist.
   - Exibição de progresso no card.

## Próximo passo técnico recomendado (Astro Islands)

### Por que

- O board atual em JS vanilla atende ao MVP, mas fica caro para evoluir drag/drop avançado.
- Funcionalidades como reorder estável, acessibilidade de teclado, auto-scroll e nested interactions são mais seguras com libs maduras.

### Direção

- Introduzir **Astro Island React** para o board da tribo:
  - `@astrojs/react`
  - `@dnd-kit/core` + `@dnd-kit/sortable`
- Manter o restante da página em Astro SSR.
- O Island conversa apenas com RPCs aprovadas (`list_board_items`, `move_board_item`, `upsert_board_item`, `admin_archive_board_item`).

## Contratos de UX mínimos para fase Island

- Clique em card abre modal lateral/central com:
  - Título
  - Descrição
  - Responsável
  - Status
  - Prazo
  - Lixeira (soft delete/archive)
- Drag/drop com feedback visual por coluna.
- Modo teclado para movimentação básica (a11y).

## Regras de governança

- Sem hard delete.
- Toda remoção operacional deve usar arquivamento.
- ACL obrigatória em backend (não confiar em gate de frontend).
- Toda mudança de contrato exige atualização em `docs/RELEASE_LOG.md`.

## Critério de saída do épico

- Fluxo operacional da tribo executável sem retorno à Home para contexto.
- Board com edição completa no modal.
- Tema escuro consistente nas superfícies mais usadas (tribe/admin/webinars/teams/nav).
