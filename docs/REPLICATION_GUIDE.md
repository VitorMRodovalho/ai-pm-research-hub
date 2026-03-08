# Guia de Replicação — Usar o Hub como Base para Outro Projeto

Este guia permite replicar o AI & PM Hub para outro chapter PMI, iniciativa de pesquisa ou projeto similar, mantendo a filosofia **replicável, integrável e seguro**.

---

## Pré-requisitos

- Node.js 18+
- Conta [Supabase](https://supabase.com) (free tier suficiente para dev)
- (Opcional) Cloudflare Pages para hosting
- (Opcional) Supabase CLI para migrações e Edge Functions

---

## 1. Clone e instale

```bash
git clone https://github.com/VitorMRodovalho/ai-pm-hub-v2.git seu-projeto
cd seu-projeto
npm install
```

---

## 2. Configure o Supabase

### 2.1 Criar projeto

1. [Supabase Dashboard](https://app.supabase.com) → New Project
2. Escolha região (ex.: South America — São Paulo)
3. Aguarde o projeto ser criado

### 2.2 Obter credenciais

Em **Project Settings → API**:
- **Project URL** → `PUBLIC_SUPABASE_URL`
- **anon public** key → `PUBLIC_SUPABASE_ANON_KEY`

### 2.3 Aplicar schema

```bash
supabase link --project-ref SEU_PROJECT_REF
supabase db push
```

Ou aplique manualmente as migrações em `supabase/migrations/` na ordem dos timestamps.

### 2.4 Auth (OAuth)

Para login com Google/LinkedIn:
- **Authentication → Providers** → habilitar Google e/ou LinkedIn
- Configurar URLs de callback conforme seu domínio

---

## 3. Variáveis de ambiente

Copie `.env.example` para `.env` e preencha:

```bash
cp .env.example .env
```

**Mínimo para rodar localmente:**
- `PUBLIC_SUPABASE_URL`
- `PUBLIC_SUPABASE_ANON_KEY`

**Para produção e integrações:** veja `.env.example` — cada variável está documentada.

---

## 4. Rodar localmente

```bash
npm run build
npm run dev -- --host 0.0.0.0 --port 4321
```

Acesse `http://localhost:4321`.

---

## 5. Deploy (Cloudflare Pages)

1. Conecte o repositório ao Cloudflare Pages
2. Build command: `npm run build`
3. Output directory: `dist`
4. Environment variables: configure `PUBLIC_SUPABASE_URL` e `PUBLIC_SUPABASE_ANON_KEY`

Sem outras variáveis, o app roda com placeholders onde houver dashboards (analytics, comms).

---

## 6. O que customizar para seu projeto

| Onde | O quê |
|------|------|
| `src/data/tribes.ts`, `chapters.ts` | Nomes de tribos e chapters |
| `src/i18n/` | Textos em PT/EN/ES |
| `docs/`, `README` | Branding e links |
| Supabase RLS | Políticas por tabela conforme seu modelo de acesso |

---

## 7. Segurança e integridade

- **Não commite** `.env` — está no `.gitignore`
- **RLS** no Supabase está habilitado; revise políticas para seu caso
- **Event Delegation** e `escapeHtml`/`escapeAttr` já aplicados no frontend (sem inline `onclick` com dados)
- Use **service role** apenas em Edge Functions/backend, nunca no frontend

---

## 8. Referências

- `docs/CURSOR_SETUP.md` — setup para desenvolvimento com Cursor
- `docs/DEPLOY_CHECKLIST.md` — checklist de produção
- `AGENTS.md` — contexto para assistentes de IA
- `.env.example` — referência de variáveis
