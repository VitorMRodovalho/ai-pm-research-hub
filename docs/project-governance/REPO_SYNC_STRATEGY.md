# Repo Sync Strategy (Dev ↔ Prod)

## Objetivo

Evitar drift entre os repositórios de desenvolvimento e produção e garantir que qualquer operador autorizado consiga repetir o fluxo sem depender de contexto de sessão.

## Contexto

- Repositório de trabalho atual: `origin` (`ai-pm-research-hub`).
- Em ambientes que possuem remote adicional de deploy, usar `production` para o push final em produção.
- Quando o remote `production` não estiver configurado localmente, registrar isso explicitamente no release log e manter deploy via fluxo padrão do `origin/main`.

## Fluxo oficial por sprint

1. **Implementação e audit local**
   - `npm test`
   - `npm run build`
   - `npm run smoke:routes`
   - `supabase db push` quando houver migration pendente
2. **Commit por concern**
   - mensagem clara, sem misturar SQL + UI no mesmo commit quando possível
3. **Push de desenvolvimento**
   - `git push origin main`
4. **Push de produção (quando remote existir)**
   - `git push production main`
5. **Registro**
   - atualizar `docs/RELEASE_LOG.md` com escopo, validação e evidências
   - manter `backlog-wave-planning-updated.md` e docs de governança alinhados

## Checklist de verificação de sync

- `git status` limpo antes do push
- `git rev-parse HEAD` registrado na nota da sprint/release
- `git remote -v` confirmado para saber se `production` está disponível
- migrations locais e remotas alinhadas (`supabase migration list`)

## Operação de contingência

Se um operador secundário assumir:

1. conferir acesso ao GitHub + Supabase + Cloudflare
2. seguir exatamente este fluxo
3. registrar qualquer divergência operacional em `docs/RELEASE_LOG.md`
