# SSR_SAFETY_SWEEP_FINAL.md

Checklist final para reduzir regressão SSR em páginas Astro com dados opcionais.

## Princípios de guarda

- Nunca assumir presença de arrays/objetos de RPC no SSR.
- Sempre usar fallback explícito (`?? []`, `?? null`) antes de renderizar props.
- Em componentes, preferir rendering condicional (`{value ? ... : ...}`).

## Rotas críticas auditadas

- `/`
- `/en`
- `/es`
- `/admin`
- `/admin/selection`
- `/admin/analytics`
- `/admin/curatorship`
- `/admin/comms`
- `/admin/webinars`
- `/attendance`
- `/artifacts`
- `/profile`

## Comandos de validação

```bash
npm run smoke:routes
npm run build
```

## Heurística de revisão rápida

1. Procurar uso direto de `.map` em dados de RPC sem fallback.
2. Procurar acesso direto a propriedades aninhadas sem `?.`.
3. Em frontmatter de páginas, garantir que todo valor passado a componente seja null-safe.
4. Se a rota for admin, validar também estado denied/loading sem assumir member carregado.

## Evidência mínima

- saída do smoke de rotas;
- build sem erro;
- entrada no `docs/RELEASE_LOG.md`.
