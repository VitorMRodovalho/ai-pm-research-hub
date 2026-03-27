## Dark Mode A11y Checklist

Objetivo: manter consistencia visual e acessibilidade minima entre superficies principais em `light` e `dark`.

### Quick audit (obrigatorio em PR de UI)

- Executar `./scripts/audit_dark_mode_a11y.sh`.
- Validar manualmente:
  - contraste em textos pequenos (badges, labels e placeholders);
  - foco visivel em inputs, selects e botoes;
  - estados hover/focus em cards e modais;
  - modais com fundo/overlay legiveis no tema escuro.

### Superficies alvo desta fase

- `src/pages/tribe/[id].astro` (kanban + modais)
- `src/pages/publications.astro`
- `src/pages/admin/webinars.astro`
- `src/pages/teams.astro`

### Gate de regressao

- Sempre rodar:
  - `npm test`
  - `npm run build`
  - `./scripts/audit_dark_mode_a11y.sh`
