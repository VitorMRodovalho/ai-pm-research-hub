# Disaster Recovery — POP de Restauração

**S-DR1** — Procedimento operacional para restauração de backup e PITR no AI & PM Research Hub.

---

## Escopo

Este documento cobre:
- **Supabase** (PostgreSQL, auth, storage, Edge Functions)
- **Cloudflare Workers** (frontend)
- **GitHub** (repositório — backup implícito via controle de versão)

---

## 1. Supabase — Banco de dados

### 1.0 Arquitetura de backup (atualizada 2026-06-10, #618 — Option C)

**Um motor, três locais.** O dump é sempre o `pg_dump` 17 real (via session pooler, IPv4):

| # | Camada | Cadência | Retenção | Onde |
|---|--------|----------|----------|------|
| 1 | Backup diário da plataforma Supabase | diário (~04:14 UTC) | 7 dias (Pro) | Supabase (verificar: Management API `GET /v1/projects/{ref}/database/backups`) |
| 2 | `pg_dump` semanal — workflow `backup-database.yml` | domingos 23:00 UTC + `workflow_dispatch` | 8 cópias / 60 dias | GitHub Actions artifacts (`db-backup-*`) |
| 3 | **Offsite**: o MESMO dump → Cloudflare R2 | mesmo run do item 2 | lifecycle do bucket | bucket `nucleoia-db-backups` (ENAM) |

> **Histórico (#618):** até 2026-06-10 as camadas 2 e 3 estavam AMBAS quebradas em silêncio —
> a 2 por senha sem percent-encoding no secret (+ client PG16 vs servidor PG17 + pg_wrapper
> resolvendo pro cluster local do runner), a 3 porque o EF `backup-to-r2` (aposentado) não
> tinha R2 creds, tinha gate quebrado-aberto e o dump era um JSON de 28 tabelas stale — não
> restore-grade. O cron `backup-to-r2-weekly` (job 12) foi desagendado (mig
> `20260805000141`). O secret `SUPABASE_DB_URL` usa o formato **session pooler**
> (`postgres.{ref}@aws-1-sa-east-1.pooler.supabase.com:5432`) com senha só-alfanumérica.
> Lição: `pg_cron 'succeeded'` ≠ EF/HTTP 200 — cruzar com `net._http_response` (TTL ~6h).

Secrets do workflow: `SUPABASE_DB_URL` (obrigatório) + `R2_ACCOUNT_ID` /
`R2_BACKUP_ACCESS_KEY_ID` / `R2_BACKUP_SECRET_ACCESS_KEY` (offsite; o passo R2 é skip-com-warning
enquanto ausentes). Restaurar do artefato/R2: `gunzip -c backup_*.sql.gz | psql "$DATABASE_URL"`.

### 1.1 Backups automáticos

- Supabase faz **backup diário** de todos os projetos.
- Retenção por plano:
  - **Free**: sem backup automático; usar `supabase db dump` manualmente.
  - **Pro**: últimos 7 dias.
  - **Team**: últimos 14 dias.
  - **Enterprise**: até 30 dias.

### 1.2 Point-in-Time Recovery (PITR)

Disponível em Pro/Team/Enterprise como add-on:
- Restauração com granularidade de segundos.
- Habilitar em: Dashboard → Project Settings → Add-ons → PITR.
- Cobrança por hora conforme retenção (7, 14 ou 28 dias).

### 1.3 Restaurar via Dashboard

1. Acessar [Supabase Dashboard](https://supabase.com/dashboard) → projeto.
2. Database → **Backups**.
3. Selecionar o ponto de restauração e confirmar.

⚠️ O projeto fica inacessível durante a restauração. Tempo varia com tamanho do banco.

### 1.4 Restaurar via Management API (PITR)

```bash
curl -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/backups/restore-pitr" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recovery_time_target_unix": "<unix_timestamp>"}'
```

`recovery_time_target_unix`: timestamp Unix do momento desejado.

### 1.5 Backup manual (Free tier ou extra)

```bash
supabase db dump -f backup_$(date +%Y%m%d).sql
```

Restaurar (cuidado: sobrescreve):

```bash
psql $DATABASE_URL < backup_YYYYMMDD.sql
```

### 1.6 Pós-restauração

- **Senhas de roles customizadas**: resetar após restauração.
- **Replication slots**: se usados, dropar antes e recriar depois.
- Validar Edge Functions e auth.

---

## 2. Supabase — Edge Functions

As funções estão em `supabase/functions/` e são versionadas no Git.

**Restaurar**:
```bash
supabase functions deploy verify-credly
supabase functions deploy sync-comms-metrics
supabase functions deploy sync-knowledge-insights
# ... outras conforme necessário
```

Secrets são configurados no Dashboard; conferir após restore do projeto.

---

## 3. Cloudflare Workers

### 3.1 Rollback de deploy

1. Cloudflare Dashboard → Pages → projeto.
2. **Deployments** → selecionar deploy estável anterior.
3. **Rollback to this deployment**.

### 3.2 Re-deploy a partir do Git

```bash
git checkout <commit-estavel>
git push origin main
```

Ou disparar deploy manual no Dashboard.

### 3.3 Variáveis de ambiente

Conferir em Settings → Environment variables. Em caso de perda, recriar a partir de `.env.example` e `docs/DEPLOY_CHECKLIST.md`.

---

## 4. Checklist de incidente

1. **Identificar** o escopo (banco, frontend, auth, functions).
2. **Isolar** se possível (manutenção, redirect).
3. **Restaurar** conforme seção acima.
4. **Validar**:
   - `npm run smoke:routes` (ou smoke manual em produção).
   - Login, admin, gamification, artifacts.
5. **Registrar** em `docs/RELEASE_LOG.md` (incidente + restauração).

---

## 5. Contatos e referências

- **Supabase Docs**: https://supabase.com/docs/guides/platform/backups
- **PITR**: https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery
- **Cloudflare Workers**: https://developers.cloudflare.com/pages/
- **Repositório**: fonte de verdade para código; migrations em `supabase/migrations/`

---

## 6. Drill de redução de bus-factor (operador secundário)

Objetivo: validar que um segundo operador consegue executar recuperação e deploy sem dependência tácita do mantenedor principal.

### Checklist do drill

1. Operador secundário executa restore de cenário em ambiente controlado (ou simulação documentada).
2. Operador secundário executa:
   - `npm test`
   - `npm run build`
   - `npm run smoke:routes`
   - `supabase migration list`
3. Operador secundário valida acesso a:
   - GitHub repo/settings essenciais
   - Supabase project
   - Cloudflare Workers
4. Resultado do drill é registrado em `docs/RELEASE_LOG.md` com:
   - quem executou
   - data/hora
   - evidências e gaps

### Evidência obrigatória

Usar template: `docs/project-governance/BUS_FACTOR_DRILL_EVIDENCE_TEMPLATE.md`.
Registro de execução atual: `docs/project-governance/BUS_FACTOR_DRILL_RUN_2026-03-11.md`.

Critério mínimo de aprovação do drill:

1. Fluxo executado sem intervenção técnica direta do mantenedor principal.
2. Evidências anexadas (logs, screenshots e referência de commit).
3. Gaps convertidos em ações com owner e prazo.
