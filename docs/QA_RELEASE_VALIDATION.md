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
