# CLOUDFLARE_ENV_INJECTION_VALIDATION.md

Runbook para validar injeção de variáveis públicas no Cloudflare Pages e saúde do bootstrap Supabase no frontend.

## Objetivo

Evitar regressão de incidentes onde `PUBLIC_SUPABASE_URL` e `PUBLIC_SUPABASE_ANON_KEY` chegam vazias no bundle/runtime.

## Pré-condições

- Deploy alvo concluído em `main`.
- Acesso ao painel Cloudflare Pages.
- Acesso ao navegador com DevTools.

## Checklist de validação (produção)

1. Verificar Deploy ativo:
   - branch: `main`
   - commit esperado: último commit de hotfix/rollout
2. Verificar variáveis em **Production**:
   - `PUBLIC_SUPABASE_URL`
   - `PUBLIC_SUPABASE_ANON_KEY`
3. Forçar novo deploy:
   - `Retry deployment` após qualquer ajuste de variável.

## Probe de runtime no navegador

No console (F12):

```js
console.log('runtime url', window.__PUBLIC_SUPABASE_URL);
console.log('runtime anon key exists', !!window.__PUBLIC_SUPABASE_ANON_KEY);
```

Esperado:

- URL com domínio `*.supabase.co`
- chave presente (`true`)

## Probe REST direto (sanidade)

```js
(async () => {
  const url = window.__PUBLIC_SUPABASE_URL;
  const key = window.__PUBLIC_SUPABASE_ANON_KEY;
  const r = await fetch(`${url}/rest/v1/tribes?select=id,name&limit=1`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` }
  });
  console.log('status', r.status);
  console.log('body', await r.text());
})();
```

Esperado:

- `status` 200
- payload JSON (não HTML de 404 do domínio Pages)

## Diagnóstico rápido por sintoma

- **404 HTML do próprio site**: URL runtime está vazia/errada (chamada relativa para `/rest/v1`).
- **401/403 Supabase**: chave inválida/revogada/projeto diferente.
- **200 com dados**: bootstrap Supabase saudável; investigar RLS/consulta se ainda houver tela vazia.

## Evidência mínima para fechamento

- URL do deploy validado
- print do console com runtime URL + probe REST
- status final (`ok` / `degradado`)
- referência no `docs/RELEASE_LOG.md`
