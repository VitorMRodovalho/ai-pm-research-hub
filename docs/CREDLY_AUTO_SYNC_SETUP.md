# Credly Auto Sync Setup (S10)

## Objetivo
Executar `sync-credly-all` automaticamente toda semana sem depender de ação manual no painel.

## Componentes entregues
- Workflow agendado: `.github/workflows/credly-auto-sync.yml`
- Hardening da Edge Function `sync-credly-all` para modo cron via header `x-cron-secret`

## Pré-requisitos
1. Edge Function `sync-credly-all` deployada com código atualizado.
2. Segredo configurado na Edge Function:
   - `SYNC_CREDLY_CRON_SECRET` (valor forte, aleatório)
3. Segredos configurados no GitHub (repositório que executa o workflow):
   - `SUPABASE_URL` (ex.: `https://<project-ref>.supabase.co`)
   - `SUPABASE_ANON_KEY`
   - `SYNC_CREDLY_CRON_SECRET` (mesmo valor da Edge Function)

## Deploy da função
```bash
supabase functions deploy sync-credly-all
```

## Verificação rápida (manual)
Rodar via curl com os mesmos headers do workflow:
```bash
curl -X POST "${SUPABASE_URL}/functions/v1/sync-credly-all" \
  -H "Content-Type: application/json" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
  -H "x-cron-secret: ${SYNC_CREDLY_CRON_SECRET}" \
  --data '{}'
```

## Resultado esperado
JSON com:
- `success: true`
- `execution_mode: "cron"`
- contadores de sucesso/falha por membro processado.

## Observações de segurança
- Não expor `SYNC_CREDLY_CRON_SECRET` em client/browser.
- Rotacionar segredo periodicamente.
- Em caso de vazamento, regenerar segredo no Supabase + GitHub imediatamente.
