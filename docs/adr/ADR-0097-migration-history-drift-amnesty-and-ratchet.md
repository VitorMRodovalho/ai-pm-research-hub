# ADR-0097: Migration history drift — amnesty + ratchet baseline

- Status: Accepted
- Data: 2026-05-22 (p224)
- Aprovado por: Vitor (PM) em 2026-05-22 (decisão p224 WATCH-185 discovery, path δ Hybrid)
- Autor: Vitor (PM) + Claude (discovery + drafting)
- Escopo: Tratamento da divergência histórica entre `supabase_migrations.schema_migrations` (tracked rows) e `supabase/migrations/*.sql` (local files)

## Contexto

Audit p223 (`/audit` skill, finding #17) detectou drift de **669 rows** entre file count e tracked rows (1112 `.sql` files vs 1781 tracked). Audit p224 (WATCH-185 discovery) refinou para set-difference exato:

- **694 versions em `schema_migrations` SEM `.sql` local** (tracked − local)
- **15 `.sql` locais SEM row em `schema_migrations`** (local − tracked)
- **41 rows em `schema_migrations` com `statements` NULL ou empty array `'{}'`** (registered without body — 12 destes ALSO missing file, worst case "truly lost"; 2 são empty-array — `supabase migration repair` artifact — ver sediment abaixo)
- **Live DB state**: 1742 rows com body capturado + 1779 rows com name preenchido. **Live infra 100% funcional**.

### Origem do drift

Pré-GC-097 era (anterior a 2026-04-13): migrations aplicadas via:
- `apply_migration` MCP que não escrevia local file
- Studio Dashboard SQL editor (zero migration tracking)
- `execute_sql` MCP usado para DDL (violação do GC-097 rule)
- `supabase migration repair --status applied <ts>` sem corresponding `.sql` file

GC-097 (`.claude/rules/database.md`) foi instituído depois e estabeleceu o protocolo manual sync: após `apply_migration`, sempre `Write` o local file + `migration repair --status applied`. Discipline mantida em sessões pós-GC-097 (recent files `20260805000000`/`001`/`002`/`003` todos têm files + bodies corretos).

### Discovery analítica (sample n=20 de 694 missing files)

| Padrão | Count | % | Exemplos |
|---|---|---|---|
| DDL recoverable (statements has body) | 14 | 70% | CREATE OR REPLACE FUNCTION; ALTER TABLE; triggers; COMMENT-deprecation |
| DML backfill (data ops) | 4 | 20% | UPDATE events normalization; INSERT audit log backfill |
| EMPTY (marked-applied without body) | 1 | 5% | `ip2b_v22_seed_termo` (truly lost, body only in pg_proc) |
| Hotfix/reapply (redundante) | 1 | 5% | `p179_reapply_file_verbatim_with_comments` |

Extrapolation: ~485 DDL recoverable / ~140 DML / ~35 EMPTY / ~35 hotfix nos 694.

### 15 orphan files (local sem tracked row) — 3 clusters

1. **p64 cluster (Apr 26-27, 3 files)**: `20260426234500_incident_p64_revert_accidental_signoff_adendo_ip.sql` + Pacote M ADR-0028→0029 work + audit helper
2. **p125-E1/E2/p126-E3 cluster (May 18, 11 files)**: série completa do selection PMI 3D + service history + anonymize cron + returning member trigger — sprint inteiro não registrado
3. **TAP CPMAI R00 seed (Jun 18, 1 file, ~60KB)**: seed data 863 linhas aplicado direct via dashboard

## Decisão

**Aceitar drift histórico como amnistia documentada + estabelecer ratchet via CI gate.**

Path δ (Hybrid amnesty + ratchet) escolhido entre 4 caminhos avaliados:

| Opção | Custo | Risco UX | Recovery |
|---|---:|---|---|
| α — Amnesty puro (document only) | 15min | none | none — drift continua crescendo invisível |
| β — Snapshot único consolidado (dump 1742 bodies → 1 migration) | 3-4h | medium (parser pode quebrar) | partial — 41 EMPTY ainda need pg_proc |
| γ — Per-version recovery (write file por version) | 12-15h+ | low | full — mas custo desproporcional |
| **δ — Hybrid amnesty + ratchet** | **1h** | **none** | **prevent-going-forward only** |

PM escolheu **δ** em p224 com justificativa:

1. **Funcional impact = 0 hoje**: live DB tem todo DDL aplicado + features funcionam + contract tests passam. Risco surface APENAS em `supabase db reset` rebuild from files, que não acontece em prod.
2. **Recovery custo desproporcional**: 12-15h para reconstruir migrations que não trazem benefício imediato. Tempo melhor investido em features.
3. **GC-097 já enforça going-forward discipline**: drift NEW não cresce desde p86 onde a regra foi instituída.
4. **Ratchet baseline pega novos drifts**: contract test `rpc-migration-coverage.test.mjs` extends com 3 assertions que falham se drift counts AUMENTAREM, garantindo zero new entries.

## Implementação

### 1. Audit helper RPC

Migration `20260805000003_p224_audit_schema_migrations_versions.sql` cria `public._audit_list_schema_migrations()` (SECDEF + GRANT EXECUTE TO service_role) que retorna `TABLE(version text, name text, has_body boolean)`. Permite o test contract leer schema_migrations sem dar service_role acesso direto ao schema interno.

### 2. 3 baseline files (allowlists)

- `docs/audit/MIGRATION_FILE_DRIFT_BASELINE_P224.txt` — 694 versions tracked sem .sql local
- `docs/audit/MIGRATION_ORPHAN_LOCAL_BASELINE_P224.txt` — 15 .sql locais sem tracked row
- `docs/audit/MIGRATION_EMPTY_STATEMENTS_BASELINE_P224.txt` — 41 versions com statements vazio (39 IS NULL + 2 empty-array `'{}'` artifact de `supabase migration repair` — sediment p224 §3)

### 3. Contract test ratchet (9 test cases)

`tests/contracts/rpc-migration-coverage.test.mjs` extended com:

- 3 NEW-drift assertions (uma por baseline) — falha se algum entry NOVO aparece fora da allowlist
- 3 STALE assertions — falha se baseline tem entries que não estão mais no live state (ratchet DOWN required)
- 3 SIZE assertions — falha se allowlist file size diverge do constant no test (forces baseline bump on every cleanup)

Constants:
- `MISSING_FILE_DRIFT_BASELINE_SIZE = 694`
- `ORPHAN_LOCAL_BASELINE_SIZE = 15`
- `EMPTY_STATEMENTS_BASELINE_SIZE = 41`

### 4. CI gate

Test roda no offline CI baseline (only file-existence asserts) + with-DB CI when SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY env vars present. CI sentinel já existente (p177) garante que com-DB tests NÃO skipam silenciosamente em CI context.

## Consequências

### Positivas

- **Zero functional regression**: live DB unchanged + tests continuam passando.
- **Drift growth blocked**: qualquer commit que aumente missing/orphan/empty counts falha CI test.
- **Discovery documentado**: ADR + 3 baselines + P162 log entry preservam audit trail completo.
- **Ratchet DOWN possible**: futuras sessões podem capturar missing versions individualmente (write local file + `migration repair --status applied`), decrementando baseline naturalmente.
- **Side-effect descoberto**: `supabase migration repair --status applied` backfilla automaticamente body de OUTRAS migrations registradas-sem-body quando local file existe — pattern útil para limpeza incremental. **CAVEAT (sediment p224)**: o backfill pode produzir `statements='{}'` (empty array) em vez de populated array ou NULL. Three-valued SQL `IS NOT NULL AND len>0` retorna NULL para empty arrays, confundindo audit queries naive. RPC helper `_audit_list_schema_migrations()` herda esse artifact; test layer (JS) trata `!has_body` corretamente. Documentado no header do baseline empty-statements.

### Negativas

- **694 missing files permanecem**: `supabase db reset` from local files NÃO reproduzirá estado prod completamente. Mitigação: prod nunca faz `db reset`; LOCAL_QA workflow (`docs/operations/LOCAL_QA.md`) usa `db pull --linked` para sincronizar.
- **12 truly-lost migrations** (`ip2b_v22_seed_*` + `ip3e_gate_matrix_v2`): body só inferrable via `pg_proc`/`pg_policies` introspection. Não recuperável via `migration repair`. Aceito porque feature está live e funcional.
- **Audit advisor sempre vê drift**: future audit reports continuarão flagando o gap (1112 files vs ~1784 rows). ADR-0097 serve como audit trail explícito para "finding investigated + accepted".

### Sediment learnings (p224)

Durante a implementação destes 3 baselines + ratchet, três artifacts/sediment surgiram:

1. **`apply_migration` MCP usa NOW() como version, ignora prefix do name**: passei `name=20260805000003_p224_audit_schema_migrations_versions` para apply_migration MCP, e ele criou row com `version=20260523024043` (current timestamp UTC) + `name` literal preservado. Tive que rodar `supabase migration repair --status applied 20260805000003` separadamente para registrar a version canônica. Duplicate row deletada via DML (`DELETE FROM supabase_migrations.schema_migrations WHERE version='20260523024043'`). Lesson: SEMPRE rodar `migration repair --status applied <canonical-version>` E depois deletar a shadow row criada por apply_migration (ou usar nome explicitamente sem prefix).
2. **`supabase migration repair` produz `statements='{}'` para alguns rows**: durante o repair --status applied 20260805000003 (que cascade-tocou outros rows), 2 rows (`20260721000000` + `20260722000000`) tiveram bodies set para empty array em vez de NULL ou populated. Provável artifact CLI quando local file não pode ser parsed em statements distintos. Affects audit query SQL `IS NOT NULL AND len>0` que retorna NULL (não FALSE) — three-valued logic gotcha. RPC `_audit_list_schema_migrations()` herda esse artifact (has_body=NULL para empty array). Test layer JS trata `!has_body` corretamente (NULL é falsy). Direct SQL queries devem usar `array_length(statements,1) IS NULL` para capturar ambos.
3. **Cascade backfill behavior é volátil**: o mesmo `migration repair` que aparentemente backfillou 2 rows (visível em count 41→39 transient) depois revertia/não persistia ao DELETE de outra row. Estado final: 41 empty total. **Conclusão**: tratar `migration repair` cascade como best-effort, não rely on it para limpeza determinística. Baseline truth = direct query, não RPC.
4. **PostgREST RPC TABLE return pagination trap**: o primeiro design do `_audit_list_schema_migrations()` retornava `TABLE(version, name, has_body)`. PostgREST aplica `LIMIT 1000` server-side em qualquer RPC com TABLE return — Range header + `?limit=10000` query param + `Prefer: count=exact` foram TODOS ignorados. Test ratchet falhava com STALE/NEW false-positives porque só via 1000 das 1785 rows. **Fix**: migration `20260805000004` reescreve RPC para retornar `jsonb` agregado (single row containing array) — não paginado. Lesson: NUNCA usar TABLE return em RPC quando volume pode exceder 1000 rows. Sempre `RETURNS jsonb` com `jsonb_agg(...)`.

## Critério de revisão

Este ADR deve ser revisado se:

1. **Drift counts crescerem** sem PM ack + baseline bump (CI gate falha).
2. **`supabase db reset` virar requisito** (local QA forced rebuild from files) — momento natural para path β (snapshot consolidado).
3. **Auditoria externa flagar como blocker** (não internal advisor).
4. **GC-097 protocol breakdown**: se novas drift entries começarem a aparecer regularmente, indicar enforcement gap — investigar root cause antes de aceitar amnesty new entries.

## Follow-up planejado

**Não comprometido em sprint específico.** Path δ é definitivo a menos que critério de revisão acima dispare.

Quando refactor for executado (path β recomendado):

1. Capturar live bodies de 1742 rows com body via `pg_dump --schema-only --no-owner --no-acl` ou query estruturada.
2. Consolidar em 1 migration `<future-ts>_drift_snapshot_consolidated.sql`.
3. Marcar todos 694 missing como "captured by snapshot" — remover do baseline (ratchet to 0).
4. Os 12 truly-lost migrations: introspect pg_proc + pg_policies, reconstruir DDL, capturar como migrations individuais.

## Referências

- Audit p223 finding #17 (P162 log #185 WATCH-AUDIT-HIGH-17) — origin
- Audit p224 discovery (sample analysis + path decision)
- `.claude/rules/database.md` GC-097 protocol — preventive going-forward rule
- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` — related drift class (function body divergence)
- `docs/operations/LOCAL_QA.md` (p202 issue #164) — `db pull --linked` workflow avoids db reset
- ADR-0029 — sibling pattern (Pacote M retroactive retirement amnesty + ratchet)
- Migration `20260805000003_p224_audit_schema_migrations_versions.sql` — RPC helper
- Baselines: `docs/audit/MIGRATION_FILE_DRIFT_BASELINE_P224.txt` + `MIGRATION_ORPHAN_LOCAL_BASELINE_P224.txt` + `MIGRATION_EMPTY_STATEMENTS_BASELINE_P224.txt`
- Contract test: `tests/contracts/rpc-migration-coverage.test.mjs` (9 new test cases)
