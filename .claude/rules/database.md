---
description: Database rules — GC-097 pre-commit validation, RPC signature changes, DDL via apply_migration (not execute_sql), apply queue and the orchestrator gate, LGPD/RLS, V4 authority audit
paths:
  - "supabase/migrations/**"
  - "supabase/functions/**"
  - "**/*.sql"
  - "src/lib/database.gen.ts"
---

# Database Rules

> Path-scoped (2026-05-30): loads only when SQL/migration/EF files are in context. If it loads on every session
> anyway, the harness ignores `paths:` — verify with `/memory`. (See `reference_process_fix_and_context_hygiene_2026_05_30`.)

## Pre-Commit Validation (GC-097)
1. Check FK constraints: `SELECT constraint_name, pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'TABLE'::regclass AND contype = 'f';`
2. Verify `auth.uid()` vs `members.id` — events.created_by FK → auth.users(id), NOT members(id)
3. Test the RPC with real data via MCP execute_sql
4. Column names: members uses `name` (not `full_name`), `credly_url` (not `credly_username`)
5. Array types: members.designations is `text[]` (not jsonb). Use `&&` not `?|`

## RPC Signature Changes
1. Use DROP + CREATE (not CREATE OR REPLACE) when changing parameter types or count
2. Check overloaded functions: `SELECT count(*) FROM pg_proc WHERE proname = 'X'`
3. After applying to DB: `NOTIFY pgrst, 'reload schema'`
4. Mark migration as applied: `supabase migration repair --status applied TIMESTAMP`

## DDL must go through `apply_migration` — NEVER `execute_sql`
**Track Q-C (p50, ratified 2026-04-25):** the live `import_vep_applications` and `exec_portfolio_health` bodies drifted from every migration file because earlier sessions ran `CREATE OR REPLACE FUNCTION` via `execute_sql` (or the dashboard SQL editor). 92 functions ended up as orphans with no migration capture (see `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`).

Rule:
- `mcp__claude_ai_Supabase__execute_sql` is for **read-only or DML** (SELECT, INSERT/UPDATE/DELETE on data, NOTIFY, EXPLAIN). Test calls during validation are fine.
- `mcp__claude_ai_Supabase__apply_migration` is for **all DDL** (CREATE/ALTER/DROP on tables, functions, types, policies, triggers, indexes, views; GRANT/REVOKE; COMMENT ON). Including `CREATE OR REPLACE FUNCTION`.
- **`apply_migration` via MCP applies DDL to remote DB AND registers a tracking row.** It does not write a
  local migration file, but it DOES insert a row into `supabase_migrations.schema_migrations`, stamped with
  its own **wall-clock** version (e.g. `20260913020632`) and the `name` you passed.

  > ⚠️ **This line used to say the opposite** ("it does NOT register the version"), and that sentence caused
  > the same defect three times — 2026-07-17 (#1408), 2026-07-18 (#1419) and 2026-09-13 (#2130). Following it,
  > you run `migration repair`, which inserts a SECOND row for your local file's version. The result is two
  > tracking rows for one migration, one of them with no local file, and
  > `tests/contracts/rpc-migration-coverage.test.mjs` reports it as `NEW missing-file drift`.
  >
  > Measured 2026-09-13: `apply_migration` registered `20260913020632` (1 statement, the whole blob) while
  > `repair` registered `20260912234500` (10 statements). Same `name`, both live.
  >
  > **And do not confirm it by probing the version you expect** — `WHERE version = '<your timestamp>'` returns
  > 0 and reads as "not registered". Query by `name`, or by today's date prefix.

  **Preferred ritual — ONE `apply_migration` call, then adopt its version (no `repair`, nothing to delete):**
  1. `apply_migration(name, query)`.
  2. Read the version it registered: `SELECT version FROM supabase_migrations.schema_migrations WHERE name = '<name>' ORDER BY version DESC LIMIT 1`.
  3. Write the local file as `supabase/migrations/<that version>_<name>.sql`, byte-identical to what you applied.
     The row is now canonical: `statements` is already populated, and the tracking table is never touched by hand.
  4. `NOTIFY pgrst, 'reload schema'` via `execute_sql` if the change affects the PostgREST surface.

  This works whenever the registered (real-date) version sorts AFTER the current head — true since the sequence
  returned to real dates. If you made SEVERAL `apply_migration` calls, each left its own row: prefer editing the
  local file and re-applying the WHOLE file over stacking corrective calls, and if rows are already stacked,
  delete the extras by **EXACT** version (never `LIKE`), then verify with a FRESH `execute_sql` — a
  `DELETE ... RETURNING` plus a sibling `count(*)` in ONE statement shows the pre-delete snapshot.
- Without the manual sync, `tests/contracts/rpc-migration-coverage.test.mjs` will fail in CI when a new function appears in `pg_proc` without a `CREATE FUNCTION` block in any migration — catches accidental DDL via the wrong tool **and** the apply_migration MCP gap.
- **Contract test CI gate (p174 sediment)**: the Q-C orphan check requires `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` env vars; without them tests SKIP silently (offline baseline check still passes). Confirmed fix: `.github/workflows/ci.yml` `Run Unit Tests` step now uses `${{ secrets.SUPABASE_URL }}` + `${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}` (p174, 2026-05-17). Without those secrets configured in GH repo settings, the gate still silently skips — verify periodically that CI is actually running the DB-aware tests, not just the offline baseline.
- **Phase C body-hash drift gate (p175 extension)**: orphan check alone misses the case where a function IS captured by SOME migration but the live body has since diverged (the drift class that motivated p52/p174). Phase C compares `md5(regexp_replace(prosrc, '\s+', ' ', 'g'))` between live (via `_audit_list_public_function_bodies()` RPC) and the latest CREATE FUNCTION capture per `(name, normalized_args)` key. Baseline allowlist of currently-drifted keys lives at `docs/audit/RPC_BODY_DRIFT_ALLOWLIST_P175.txt` (225 entries at p175). Tests ratchet DOWN as drift is recovered via apply_migration. Shared parser at `tests/helpers/rpc-body-drift-parser.mjs` (consumed by both the test and `scripts/audit-rpc-body-drift.mjs`); SQL-side normalization must stay byte-equivalent to the helper's `normalizeBody()` — break it and EVERY function appears drifted.

## LGPD Compliance (GC-162)
- All new tables MUST have RLS enabled
- No anon access to PII (members.email, phone, pmi_id, auth_id)
- Ghost users (authenticated without member record) get NOTHING from PII tables
- Public data via SECURITY DEFINER RPCs only (get_public_leaderboard, get_public_platform_stats)

## V4 Authority audit — before proposing seed expansion
**Sediment p122e:** auditorias mecânicas de `engagement_kind_permissions` × actions produzem false positives recorrentes porque V4 tem três caminhos paralelos de autoridade (combos seedados + designation-based gates + RPC inline scoping). Antes de declarar gap ou propor `INSERT INTO engagement_kind_permissions ...`, executar o **procedimento de 5 etapas** em `docs/reference/V4_AUTHORITY_MODEL.md` (matriz capability→path + checklist).

⚠️ **A etapa 0 é a mais nova e a que já foi esquecida uma vez** (2026-09-22, #2417): `engagement_kind_permissions` diz o que o par CONCEDE; `engagement_kinds.initiative_kinds_allowed` diz se o kind pode sequer ser **ATADO** àquela espécie de iniciativa, e `manage_initiative_engagement` valida esse segundo antes de olhar o primeiro. O par `observer × participant → write_board` (#2416) passou nas 4 etapas, foi seedado com escopo correto e guard próprio, e **alcançava 0 linhas**, porque `observer` não era admissível em `workgroup`. Um seed inalcançável fica verde em todo teste de permissão que existe — é conteúdo, não efeito. Pergunte **quantas linhas o caminho novo alcança HOJE** logo depois de aplicar, e deixe o número no registro.

Anti-pattern documentado: "seed expansion como atalho" em actions destrutivas (`manage_member`, `manage_platform`) cria privilege escalation que viola invariante "member lifecycle = GP-only" (LGPD Art. 18).

## Fila de apply e a sessão orquestradora (detalhe; o resumo MANDATÓRIO fica no CLAUDE.md)
Movido verbatim do CLAUDE.md em 30/10/2026, para o CLAUDE.md caber em cada pedido.

**IMPORTANT — YOU MUST:** antes de qualquer `apply_migration`, confirme **DUAS** condições, não uma:

```bash
gh pr list --state open                       # (1) zero PRs abertas
gh run list --limit 30 --json name,status \
  --jq '[.[]|select(.status!="completed")|select(.name|test("Validate|Invariants|DB Types"))]|length'
                                              # (2) zero jobs de banco em voo — SEM --branch
```

⚠️ **Fila de PRs vazia NÃO é banco livre, e o próprio ato de esvaziá-la é o que arma o perigo.**
Mergear **zera** `gh pr list` e, no mesmo segundo, **dispara** `CI Validate` e `Schema Invariants`
sobre a `main`, no mesmo banco compartilhado. Medido em 18/09: `gh pr list` vazio com 2 jobs de banco
rodando. É o instante em que a tela parece mais liberada e em que mais dá vontade de escrever.
**Não recorte por `--branch`:** o recorte por branch zera no instante do merge, e é ele que cria o
ponto cego. Filtre por **nome de job**, porque são esses três que disputam o banco.

O resto continua valendo: `apply_migration` atinge o banco **compartilhado** na hora, e enquanto o
`.sql` não está no ref sob teste, aquele ref **não explica o estado do banco** — o vermelho está
CORRETO. A `main` **não é exceção**.

- Quatro mordidas em 17/09/2026, todas da mesma regra:
  1. `test:verdict` local rodando durante o CI da própria PR ⇒ fixture órfã violou invariante e
     derrubou **15 asserções** (a suíte escreve em produção e o `cleanup()` morre com a rede);
  2. branch criada a partir da `main` **depois** de aplicar DDL ⇒ PR de um único `.md` reprovou por
     tabela órfã;
  3. DDL aplicada com a `main` ainda sem o arquivo ⇒ **3 alertas do CI Monitor** e ~1h de produção
     desalinhada;
  4. a quarta foi **evitada** aplicando com a fila vazia — custo zero.
- **Só a sessão ORQUESTRADORA escreve no banco (#2477, decisão do GP em 25/09/2026).** O hook
  `.claude/hooks/db-write-gate.py` **nega** `apply_migration` e `execute_sql` com escrita neste
  projeto a toda sessão cujo `session_id` não é o designado em
  `~/projects/_pmo/lanes/ai-pm-research-hub.orquestrador`, esteja ela numa lane ou no clone
  principal; sem designação, nega a todas. Leitura passa, mas a de quem não é a orquestradora volta
  reescrita para rodar numa transação somente leitura: o texto do SQL não diz o que uma função chamada faz,
  e quem recusa a escrita é o Postgres. Controle de transação (`COMMIT`, `BEGIN`…) nessa leitura é negado. Uma cópia roda também como hook de
  **usuário** (`~/.claude/settings.json`), para cobrir lanes em branch antiga. Lane prepara o pacote
  (o `.sql` e a verificação) e manda para a orquestradora. Trocar a orquestradora é decisão do GP:
  `scripts/lane-registry.sh orquestrador <session_id> "<nota>"`. Origem: em 25/09 duas migrations
  foram aplicadas por uma sessão que não era a orquestradora e rodava no **clone principal**, e por
  isso um gate por diretório não a teria barrado.
- **O mesmo hook cobre o Bash (pacote A, GP 25/09/2026).** O MCP não é o único caminho: o token de
  gestão da conta roda SQL de qualquer tipo, DDL incluído, pela `api.supabase.com` ou pela CLI ligada,
  e em todos os projetos da conta. Para quem não é a orquestradora, neste repositório (clone ou lane)
  ou em comando que cite o ref deste projeto, o hook nega `api.supabase.com`, `supabase
  db|migration|functions|gen|…`, `psql`, `npm run db:types`, `check_advisors` e a leitura do token.
  O token mora em `~/.config/supabase-mgmt/token` (600, fora de todo repo), e
  `with-supabase-token <comando>` o carrega para um comando só. Deploy de EF, `db:types` e advisors
  ficam com a orquestradora. A chave service_role do `.env` das lanes **não** é coberta: alcança só
  DML, e os testes com banco precisam dela.
- **Para a orquestradora, o mesmo hook pergunta** quando o banco está ocupado (matcher `mcp__*__apply_migration`):
  ele devolve `permissionDecision: ask` e **nomeia qual das duas condições disparou**, contando PRs
  abertas E jobs de banco em voo. ⚠️ A primeira versão do hook (17/09) consultava **só** a fila de
  PRs, e por isso teria liberado uma DDL em 18/09 com dois jobs de banco rodando na `main`: **o
  mecanismo herdou o ponto cego da regra que mecanizava.** Exercitado nos dois sentidos antes de
  subir, e a versão antiga fica silenciosa no caso exato em que a nova dispara. O hook é o mecanismo; esta seção é o porquê. Memória não intercepta — a regra já existia
  em memória nas três primeiras mordidas e não impediu nenhuma.
- **Aplicar e commitar são UM passo.** Depois do `apply_migration`: ler a versão registrada,
  nomear o `.sql` com ela, conferir o md5 do corpo vivo contra o arquivo, commitar. Sem intervalo.
- **Não rode `npm run test:verdict` enquanto o CI de qualquer PR sua estiver no ar.** Nem o
  `with-db-lease` (local × local) nem o `wait-for-db-lane` (job × job) cobrem o eixo **local × CI**.
