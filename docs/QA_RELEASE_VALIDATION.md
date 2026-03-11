# Protocolo de Validação de QA & Release

## 1. Continuous Integration (CI)
Todos os Pull Requests e pushes para a branch `main` devem passar pelo pipeline automatizado de CI (`.github/workflows/ci.yml`).
O CI garante que:
- `npm test`: Testes unitários passem (ex: regras de ACL, Credly, roteamento).
- `npm run build`: O Astro compile com sucesso (garantia de SSR).
- `npm run smoke:routes`: O servidor local suba e as rotas críticas (`/`, `/admin`, `/gamification`, etc.) retornem HTTP 200 sem quebrar.

## 2. Branch Protection
A branch `main` é protegida. 
- Você não pode realizar o "Merge" de um PR se o check `validate` do CI falhar.
- Pushes diretos para a `main` devem ser evitados.

## 3. Log de Release Manual
Após um deploy com sucesso em produção (Cloudflare Pages), o desenvolvedor deve atualizar o arquivo `docs/RELEASE_LOG.md` com as evidências.

## 4. Checklist UX Operacional (Dark Mode + Kanban)

Para releases que impactam operação de tribos e produtividade:

- Verificar toggle de tema no drawer de perfil:
  - alterna entre claro/escuro sem reload
  - persiste preferência no `localStorage` (`ui_theme`)
- Verificar `/teams` e `/webinars` em dark mode (contraste e legibilidade)
- Verificar `/tribe/[id]`:
  - clique no card abre modal de detalhes
  - criação rápida por coluna (`+`) funciona
  - salvar título/descrição/status/responsável/prazo/tags/labels/checklist
  - arquivamento de card não faz hard delete (status arquivado no backend)

## 5. Validação assistida por operador secundário (bus-factor)

Em mudanças críticas de UX:

1. Um segundo operador (não autor da mudança) executa o checklist do item 4.
2. Registrar evidências (capturas + observações) em `docs/project-governance/`.
3. Se houver divergência, abrir issue e bloquear fechamento de sprint até correção.

## 6. Gate unificado para release de UX (Kanban + Dark)

Antes de liberar mudanças em superfícies de Kanban/Dark, executar:

```bash
npm run qa:kanban
```

Esse gate executa em sequência:
- `./scripts/audit_dark_mode_a11y.sh`
- `npm test`
- `npm run build`
- `npm run smoke:routes`

## 7. Baseline visual dark mode (pré-release)

Antes de publicar mudanças amplas de UI, execute:

```bash
npm run audit:dark:baseline
```

Esse comando valida pré-requisitos de baseline visual e executa auditoria rápida de cobertura dark mode.

## 8. Contraste + snapshots por persona

Para gerar baseline visual completo (incluindo capturas multilíngue), execute:

```bash
npm run audit:dark:contrast
```

Esse fluxo roda:
- `audit_dark_mode_a11y.sh`
- `audit_dark_mode_visual_baseline.sh`
- `screenshots:multilang`
