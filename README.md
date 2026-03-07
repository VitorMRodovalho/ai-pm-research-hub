# Núcleo IA & GP

Plataforma oficial do **Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos** (AI & PM Research Hub), iniciativa colaborativa dos capítulos PMI no Brasil.

## O que é este projeto

O Hub é o produto digital que sustenta a operação do Núcleo IA & GP:
- gestão de membros e papéis operacionais
- acompanhamento de tribos e ciclos
- trilha de capacitação e gamificação
- governança documental e histórico de decisões

Este repositório **não é um starter genérico**. Ele contém o front-end, integrações e regras de negócio reais da operação do Núcleo.

## Stack Tech for Good (Custo Zero)

Arquitetura priorizada para impacto, simplicidade operacional e custo mensal zero na camada principal:

- `Astro` + `Tailwind`: frontend rápido, SSR/SSG, manutenção simples
- `Supabase`: auth, banco PostgreSQL, RPCs, edge functions
- `Cloudflare Pages`: deploy e borda global no plano gratuito
- `GitHub`: versionamento, colaboração e trilha de auditoria

Princípio: **usar ferramentas robustas de baixo custo para maximizar continuidade do projeto voluntário**.

## Como rodar localmente

### Pré-requisitos

- `Node.js` 20+
- `npm`
- conta/projeto Supabase (cloud)

### 1. Instalar dependências

```bash
npm install
```

### 2. Configurar variáveis de ambiente

Crie `.env` a partir de `.env.example`:

```bash
cp .env.example .env
```

Preencha:

- `PUBLIC_SUPABASE_URL`
- `PUBLIC_SUPABASE_ANON_KEY`

### 3. Subir ambiente local

```bash
npm run dev
```

App local padrão: `http://localhost:4321`

### 4. Validar qualidade antes de push

```bash
npm test
npm run build
npm run smoke:routes
```

## Supabase local

A operação corrente está conectada ao projeto Supabase cloud via `.env`.

Uso de Supabase local é opcional e avançado; mantenha alinhamento com a modelagem e RPCs documentadas em [`docs/MIGRATION.md`](docs/MIGRATION.md) e em [`docs/migrations/`](docs/migrations/).

## Governança V3 (Regras do Projeto)

As decisões de arquitetura e produto seguem o modelo V3:

1. Separação entre `operational_role` e `designations` como padrão.
2. `members` representa estado atual; histórico vive em `member_cycle_history`.
3. Compatibilidade legada (`role`, `roles`) é temporária e controlada.
4. Mudanças de produção exigem validação e registro documental.
5. O Hub é a fonte de verdade para métricas operacionais e gamificação.

Referências obrigatórias:
- [`docs/GOVERNANCE_CHANGELOG.md`](docs/GOVERNANCE_CHANGELOG.md)
- [`docs/MIGRATION.md`](docs/MIGRATION.md)
- [`backlog-wave-planning-updated.md`](backlog-wave-planning-updated.md)
- [`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md)
- [`docs/RELEASE_LOG.md`](docs/RELEASE_LOG.md)

## Estrutura principal

```text
src/                  # aplicação Astro
supabase/functions/   # edge functions
tests/                # testes unitários e de comportamento
docs/                 # governança, migração, plano e base de conhecimento
scripts/              # scripts operacionais (ex: smoke de rotas)
```

## Contribuição

Antes de abrir PR:

1. leia [`CONTRIBUTING.md`](CONTRIBUTING.md)
2. valide testes/build/smoke
3. descreva impacto funcional e técnico
4. atualize documentação de governança/release quando aplicável

## Licença

- Código: [`MIT`](LICENSE)
- Documentação: `CC BY-SA 4.0`

---

PMI®, PMBOK®, PMP® e PMI-CPMAI™ são marcas registradas do Project Management Institute, Inc. Este projeto é colaborativo entre capítulos e não representa endosso formal do PMI Global.
