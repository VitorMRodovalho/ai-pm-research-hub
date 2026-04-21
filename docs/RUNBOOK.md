# Runbook — AI & PM Research Hub

> Guia operacional para o Deputy GP e operadores da plataforma.
> Última atualização: 27 Março 2026

---

## Acessos necessários

| Serviço | URL | Quem tem acesso |
|---------|-----|-----------------|
| Supabase Dashboard | https://supabase.com/dashboard/project/ldrfrvwhxsmgaabwmaik | GP (owner), Deputy (editor) |
| Cloudflare Workers | https://dash.cloudflare.com/ | GP (owner) |
| GitHub repo | https://github.com/VitorMRodovalho/ai-pm-research-hub | GP (owner), Deputy (collaborator) |
| Sentry | https://nucleo-ia.sentry.io/ | GP, Deputy |
| PostHog | https://us.posthog.com/ | GP |
| Resend | https://resend.com/ | GP |

---

## 1. Deploy

### Deploy automático (padrão)

Cada push para `main` no GitHub dispara GitHub Actions → Wrangler → deploy no Cloudflare Workers.

```bash
git push origin main
# → GitHub Actions runs wrangler deploy (Astro 6 SSR), deploys in ~3 min
# → URL: nucleoia.vitormr.dev
```

### Verificação pós-deploy

1. Abrir https://nucleoia.vitormr.dev
2. Login com Google → verificar que o dashboard carrega
3. Verificar Sentry: https://nucleo-ia.sentry.io/ — 0 novos erros
4. Verificar PostHog: pageviews chegando

### Rollback

```bash
# No Cloudflare Dashboard → Workers & Pages → ai-pm-research-hub → Deployments
# Clicar no deploy anterior → "Rollback to this deployment"
```

Ou via git:
```bash
git revert HEAD
git push origin main
```

---

## 2. Banco de Dados (Supabase)

### SQL Editor

Acessar: Supabase Dashboard → SQL Editor

**Regra:** Após qualquer alteração de função/RPC:
```sql
NOTIFY pgrst, 'reload schema';
```

### Migrations

```bash
# Ver estado das migrations
npx supabase migration list

# Se aplicou SQL direto no Dashboard, criar migration de repair:
# 1. Salvar o SQL em supabase/migrations/YYYYMMDDHHMMSS_descricao.sql
# 2. Marcar como aplicada:
npx supabase migration repair YYYYMMDDHHMMSS --status applied
```

### Backup

- **Automático:** GitHub Actions roda backup semanal
- **Manual:** Supabase Dashboard → Settings → Database → Backups

### pg_cron Jobs

4 jobs ativos. Para verificar:

```sql
SELECT jobid, jobname, schedule, command FROM cron.job ORDER BY jobid;
```

Para verificar execuções recentes:
```sql
SELECT jobid, jobname, status, return_message, start_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 20;
```

| Job | Schedule | O que faz | Se falhar |
|-----|----------|-----------|-----------|
| sync-credly-all | 5 dias, 03:00 UTC | Sync badges Credly → gamification_points | Badges ficam desatualizados. Rodar manualmente via Edge Function. |
| sync-attendance-points | 5 dias, 03:15 UTC | Recalcula XP de presença | XP de presença fica stale. Rodar manualmente no SQL Editor. |
| detect-detractors-weekly | Seg 14:00 UTC | Detecta ausências 21+ dias | GP não recebe alertas. Rodar: `SELECT detect_and_notify_detractors_cron();` |
| attendance-reminders-daily | Diário 14:00 UTC | Notifica eventos do dia | Membros não recebem lembrete. Rodar: `SELECT send_attendance_reminders_cron();` |

Para pausar/retomar um job:
```sql
-- Pausar
SELECT cron.unschedule('job-name');

-- Recriar
SELECT cron.schedule('job-name', 'cron-expression', $$SQL$$);
```

---

## 3. Autenticação

### Providers configurados

| Provider | Config location |
|----------|----------------|
| Google | Supabase Dashboard → Auth → Providers → Google |
| LinkedIn | Supabase Dashboard → Auth → Providers → LinkedIn (OIDC) |
| Microsoft | Supabase Dashboard → Auth → Providers → Azure (App ID: aea7f167, tenant: common) |

### Membro sem auth (não consegue logar)

1. Verificar se `members.auth_id` está NULL → membro nunca logou
2. O auto-bind funciona: quando o membro loga pela primeira vez, o email é matchado com `members.email` e `auth_id` é preenchido automaticamente
3. Se o email do provider é diferente do cadastrado: atualizar `members.email` no DB

### Resetar auth de um membro

```sql
-- Remove o vínculo (membro precisará logar novamente)
UPDATE members SET auth_id = NULL WHERE name ILIKE '%Nome%';
```

---

## 4. Email (Resend)

### Status atual

- Domínio: `nucleoia@pmigo.org.br`
- **DNS: PENDENTE** (3 records adicionados no HostGator, aguardando verificação)
- 8 templates de campanha prontos

### Quando DNS for verificado

1. Resend Dashboard → verificar domain status = "Verified"
2. Enviar email de teste via Supabase Edge Function `send-campaign`
3. Monitorar bounces e delivery rate no Resend Dashboard

### Regras de email

- **Remetente:** Sempre `nucleoia@pmigo.org.br`
- **Linguagem:** Sem jargão AI, sem buzzwords, tom profissional direto
- **LGPD:** Link de unsubscribe obrigatório em toda campanha

---

## 5. Edge Functions

### Listar functions deployadas

```bash
npx supabase functions list
```

### Deploy de uma function

```bash
npx supabase functions deploy nome-da-function
# Para functions sem JWT (cron-triggered ou com auth própria via proxy):
npx supabase functions deploy nome --no-verify-jwt
```

✅ **Recomendado:** manter `supabase/config.toml` versionado com o flag por função — o CLI lê o arquivo e aplica automaticamente em qualquer deploy, eliminando o risco de esquecer `--no-verify-jwt` (essa omissão causou outage de 4min em 2026-04-21; ver issue #80).

### Functions com --no-verify-jwt

- `nucleo-mcp` — auth via proxy Cloudflare (OAuth 2.1), não via Supabase JWT
- `sync-credly-all` — cron-triggered
- `sync-attendance-points` — cron-triggered
- `verify-credly` — cron-triggered

⚠️ Estas functions são acessíveis sem autenticação no nível do Supabase — responsabilidade de gating fica com o código da própria função (OAuth/API key/etc.). Não expor endpoints publicamente sem esse gate.

---

## 6. Monitoramento

### Sentry

- Dashboard: https://nucleo-ia.sentry.io/
- Org: `nucleo-ia`
- Projeto: `ai-pm-research-hub`

**Triagem semanal:**
1. Abrir Issues → filtrar `is:unresolved`
2. Priorizar por `Events` (frequência)
3. Issues com `0 Users` mas muitos events = provavelmente bots ou build artifacts
4. Issues `super_high` actionability = fix imediato

### PostHog

- Dashboard: https://us.posthog.com/
- Métricas chave: pageviews, unique users, feature usage

---

## 7. Offboarding de membros

### Mover para observer

```sql
UPDATE members SET
  member_status = 'observer',
  operational_role = 'observer',
  current_cycle_active = false,
  updated_at = now()
WHERE name ILIKE '%Nome%';
```

### Mover para alumni

```sql
UPDATE members SET
  member_status = 'alumni',
  is_active = false,
  current_cycle_active = false,
  operational_role = 'observer',
  updated_at = now()
WHERE name ILIKE '%Nome%';
```

**Nota:** Designações (ambassador, curator, etc.) são mantidas — são reconhecimento histórico.

---

## 8. Emergências

### Site fora do ar

1. Verificar Cloudflare Status: https://www.cloudflarestatus.com/
2. Verificar último deploy: Cloudflare Dashboard → Workers & Pages → Deployments
3. Se deploy quebrou: rollback para deploy anterior
4. Se Supabase down: verificar https://status.supabase.com/

### Supabase connection refused

1. Verificar se o projeto não está pausado (free tier pausa após inatividade)
2. Supabase Dashboard → Settings → General → "Resume project"
3. Aguardar ~2 min para restart

### Dados corrompidos

1. **NÃO** rodar UPDATE/DELETE sem WHERE clause
2. Backups disponíveis via Supabase Dashboard → Database → Backups
3. Para restaurar: abrir ticket no Supabase Support (Pro plan necessário para point-in-time recovery)

---

## Contatos de emergência

| Pessoa | Papel | Contato |
|--------|-------|---------|
| Vitor Rodovalho | GP (owner de tudo) | WhatsApp + email |
| Fabrício Costa | Deputy GP | WhatsApp |
| Ivan Lourenço | Sponsor PMI-GO (DNS HostGator) | WhatsApp |
