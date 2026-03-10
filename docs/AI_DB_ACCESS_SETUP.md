# Configuração de Acesso do Assistente (Cursor) ao Supabase

Este documento descreve como habilitar o assistente de IA a consultar a arquitetura do banco, gerar migrações e manter a infraestrutura limpa.

---

## O que já funciona (sem config extra)

| Ação | Comando / Método | Status |
|------|------------------|--------|
| **Introspectar schema (gerar tipos)** | `supabase gen types typescript --linked` | ✅ Funciona |
| **Auditar migrations local vs remoto** | `supabase migration list` | ✅ Funciona |
| **Consultas REST API** | `curl` + `source .env` + `PUBLIC_SUPABASE_URL` e `PUBLIC_SUPABASE_ANON_KEY` | ✅ Funciona |
| **Ler migrações locais** | Arquivos em `supabase/migrations/` | ✅ Sempre |
| **Escrever novas migrações** | Criar arquivos `.sql` em `supabase/migrations/` | ✅ Sempre |
| **Supabase CLI linkado** | Projeto `ai-pm-hub` (ldrfrvwhxsmgaabwmaik) | ✅ Configurado |

O assistente consegue:
- Gerar tipos do schema remoto e ler a estrutura (tabelas, colunas, FKs)
- Confirmar `Local == Remote` no histórico de migrations do projeto linkado
- Executar consultas via REST API (com `source .env` antes; sujeito a RLS da chave anon)
- Criar migrações idempotentes
- Propor limpeza de estrutura legada com base no schema conhecido

---

## O que precisa de configuração adicional

### 1. Dump completo do schema (DDL) — para auditoria e documentação

O comando `supabase db dump --linked` requer **Docker** em execução (usa pg_dump em container).

**Alternativa sem Docker:** use a connection string direta:

```bash
# Adicione ao .env (NUNCA commitar):
# DATABASE_URL=postgresql://postgres.[PROJECT_REF]:[PASSWORD]@aws-0-sa-east-1.pooler.supabase.com:5432/postgres

# Obtenha em: Supabase Dashboard → Project Settings → Database → Connection string (URI)
```

Depois, com `psql` instalado:

```bash
psql "$DATABASE_URL" -c "\dt"   # listar tabelas
psql "$DATABASE_URL" -f script.sql  # executar SQL
```

Ou com Supabase CLI (se pg_dump estiver no PATH):

```bash
supabase db dump --db-url "$DATABASE_URL" -f docs/schema-snapshot.sql --schema public
```

### 2. PostgreSQL client (psql) — para queries ad-hoc

Instalação:
- **Ubuntu/Debian**: `sudo apt install postgresql-client`
- **macOS**: `brew install libpq` (adiciona psql)
- **Windows**: [PostgreSQL installer](https://www.postgresql.org/download/)

Com `psql` + `DATABASE_URL` no `.env`, o assistente pode rodar queries via terminal.

### 3. Docker (opcional) — para fluxo completo do Supabase CLI

Se Docker estiver rodando:
- `supabase db dump --linked` funciona
- `supabase db push` e `supabase db reset` (local) funcionam

---

## Checklist de habilitação

Para maximizar o que o assistente pode fazer:

- [x] **1. Gerar tipos do schema**  
  Script `npm run db:types` adicionado. Gera `src/lib/database.gen.ts`. O assistente lê esse arquivo para entender a estrutura. Execute quando o schema mudar.

- [ ] **2. (Opcional) DATABASE_URL no .env**  
  Copiar a connection string do Supabase Dashboard. Garantir que `.env` está no `.gitignore` (não commitar).

- [ ] **3. (Opcional) Instalar psql**  
  Para queries diretas e execução de scripts SQL.

- [ ] **4. (Opcional) Iniciar Docker**  
  Para `supabase db dump --linked` e fluxo local completo.

---

## Limitações que não podem ser resolvidas por config

- **Supabase Dashboard**: o assistente não acessa o navegador nem o dashboard. Tudo via CLI ou API.
- **Edge Functions deploy**: `supabase functions deploy` roda no seu ambiente; o assistente só prepara o código.
- **Cloudflare / GitHub Secrets**: o assistente não tem credenciais próprias; usa o que está configurado na sua máquina ou em CI.

---

## Próximos passos sugeridos

1. **Imediato**: adicionar script `db:types` e gerar `src/lib/database.gen.ts` — o assistente passa a ter visão do schema.
2. **Quando precisar de queries/dump**: configurar `DATABASE_URL` + `psql`.
3. **Para fluxo local completo**: manter Docker disponível quando for usar `supabase db dump/reset`.
