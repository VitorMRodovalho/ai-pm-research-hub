# ADR-0017: Schema↔Code Contract Audit Methodology (pre-DROP COLUMN checklist)

- Status: Proposed
- Data: 2026-04-21
- Autor: Claude (debug session 9908f3, follow-up #79 #80 #81) — aguardando aprovação PM
- Escopo: Formaliza o processo de auditoria obrigatório antes de executar `ALTER TABLE ... DROP COLUMN` em qualquer tabela com refs distribuídas por funções, views, policies, triggers, edge functions e frontend. Padroniza dimensões de busca para evitar falsos-negativos do tipo que causaram as issues #79 e #80.

## Contexto

ADR-0015 (Tribes Bridge Consolidation) definiu o caminho de deprecação de `tribe_id` em 14 tabelas. A execução foi dividida em phases 3a/3b/3c/3d/3e aplicando `DROP COLUMN` em batches. Os writers e readers afetados foram refatorados **imediatamente antes** de cada drop via audit da `pg_proc.prosrc`.

Essa auditoria, porém, foi **incompleta em duas fases consecutivas**:

### Incidente 1 — Phase 3d project_boards (2026-04-15)

Migration `20260428030000` droppou `project_boards.tribe_id`. Trigger `enforce_project_board_taxonomy` (BEFORE INSERT/UPDATE) ainda fazia `NEW.tribe_id` e passou a bloquear silenciosamente TODOS os writes em `project_boards`. Só foi detectado 5 dias depois via sweep manual (commit `589064f`, migration `20260505010000`). 9 funções foram corrigidas tardiamente.

### Incidente 2 — Phase 3e events (2026-04-18)

Migration `20260428050000` droppou `events.tribe_id`. Batch B (migration `20260427150000`) fez audit escrevendo:

```sql
-- Not in scope (confirmed no-op via prosrc audit):
--   - update_event_instance      — UPDATE SET does not touch tribe_id
--   - update_future_events_in_group — UPDATE SET does not touch tribe_id
--   - drop_event_instance        — UPDATE SET does not touch tribe_id
--   - upsert_event_agenda        — UPDATE SET does not touch tribe_id
--   - upsert_event_minutes       — UPDATE SET does not touch tribe_id
--   - update_event_duration      — UPDATE SET does not touch tribe_id
```

A auditoria olhou **apenas cláusulas `UPDATE SET`** e classificou 6 funções como no-op. Na prática, 5 dessas 6 funções fazem `SELECT tribe_id INTO ...` ou `WHERE tribe_id = ...` para enforcement de tribe-scope — quebraram em runtime quando chamadas pela primeira vez pós-drop.

Detectado 2026-04-21 quando o GP tentou mover um evento via MCP Claude.ai (issue #79). Adicionalmente, a mesma classe de bug estava no worker TypeScript `nucleo-mcp/index.ts` (issue #80) afetando 6 MCP tools — Phase 7b da migration V4 ("frontend migration COMPLETE") havia cobrido `src/` mas esquecido a edge function.

### Padrão compartilhado

Ambos os incidentes têm root cause metodológica idêntica:

1. **Superfície de busca incompleta** — audit olhou só `UPDATE SET` ou só `pg_proc`, sem varrer triggers / views / RLS / TS layer.
2. **Padrão de expressão incompleto** — `WHERE col = ...`, `SELECT col INTO ...`, `RETURNING col`, `ORDER BY col`, `embedded col via PostgREST` são todos igualmente capazes de falhar pós-drop.
3. **Sem check pós-drop** — nenhuma smoke test automático validou que o write/read real continua funcionando end-to-end antes do deploy.
4. **Sem alerting** — `list_boards` ficou 6 dias quebrado em prod sem nenhum alerta (nenhum usuário tinha precisado do tool até 2026-04-21).

## Decisão

**Adotar checklist de 8 dimensões como gate obrigatório antes de qualquer `ALTER TABLE ... DROP COLUMN` em colunas que participam de FK, scope enforcement ou lookup cross-table.**

### D1 — Checklist estruturada

A migration que executa o `DROP COLUMN` deve ter um comment header documentando que cada dimensão foi auditada, ex:

```sql
-- Pre-drop audit para <table>.<column>:
-- [x] D1 SELECT-direct:       0 matches (pg_proc.prosrc)
-- [x] D2 SELECT-INTO:         0 matches
-- [x] D3 WHERE/AND:           0 matches
-- [x] D4 UPDATE SET:          0 matches
-- [x] D5 INSERT-into-col:     0 matches
-- [x] D6 Trigger NEW/OLD:     0 matches
-- [x] D7 RLS policies:        0 matches (pg_policy.polqual)
-- [x] D8 Views + matviews:    0 matches (pg_views.definition)
-- [x] D9 Edge functions TS:   0 matches (grep supabase/functions/)
-- [x] D10 Frontend TS/astro:  0 matches (grep src/)
-- [x] D11 Scripts + cron:     0 matches (grep scripts/ + cron.job)
-- Smoke post-drop: executed 3 representative RPCs/MCP calls with success
```

### D2 — Dimensões canônicas (11)

Cada dimensão tem um SQL ou grep pattern específico que DEVE rodar:

| # | Dim | Padrão de busca | Falhas se ausente |
|---|---|---|---|
| D1 | SELECT direct | `pg_proc.prosrc ~* 'SELECT[^;]*\\<tbl\\.col\\>'` | `SELECT e.tribe_id` em embed |
| D2 | SELECT INTO | `pg_proc.prosrc ~* 'SELECT[^;]*col[^;]*INTO'` | #79 update_event_instance |
| D3 | WHERE / AND | `pg_proc.prosrc ~* 'WHERE[^;]*\\mcol\\M'` | #79 conflict check |
| D4 | UPDATE SET | `pg_proc.prosrc ~* 'UPDATE[^;]*SET[^;]*col\\s*='` | — (cobertura histórica) |
| D5 | INSERT INTO col | `pg_proc.prosrc ~* 'INSERT INTO[^;]*\\(\\s*col\\s*[,\\)]'` | dual-write writers |
| D6 | Trigger NEW/OLD | `pg_proc.prosrc ~* '\\W(NEW\\|OLD)\\.col\\W'` + `pg_trigger` | Phase 3d trigger silent block |
| D7 | RLS policies | `pg_policy`: `polqual ~* col` ou `polwithcheck ~* col` | privilege escalation |
| D8 | Views / matviews | `pg_views.definition ~* col` + `pg_matviews` | JOIN de view breaks |
| D9 | Edge functions TS | grep `supabase/functions/**/*.ts` | #80 |
| D10 | Frontend TS/astro | grep `src/**/*.{ts,tsx,astro}` | UX silent fail |
| D11 | Scripts + cron | grep `scripts/**/*.ts` + `cron.job.command` | cron silent fail |

### D3 — Gate automatizado (preventivo)

Criar `public.check_schema_drift(p_table text, p_column text)` retornando `TABLE(dimension text, refs int, locations text[])`. Rodar durante migration (no mesmo BEGIN; END;) antes do `DROP COLUMN`. Se qualquer dimensão retornar > 0 refs, a migration deve `RAISE EXCEPTION`.

```sql
-- Exemplo de uso em migration:
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM public.check_schema_drift('events', 'tribe_id') WHERE refs > 0
  LOOP
    RAISE EXCEPTION 'Pre-drop audit failed: dim=% refs=% at %', r.dimension, r.refs, r.locations;
  END LOOP;
END $$;

ALTER TABLE public.events DROP COLUMN tribe_id;
```

Essa função cobre D1-D8 automaticamente. D9-D11 continuam requerendo grep CI (fora do banco).

### D4 — Smoke test pós-drop

Cada drop deve ser seguido de `SELECT public.smoke_<table>_<col>_post_drop()` — uma função que executa 3-5 chamadas representativas e retorna OK ou RAISE. Ex.: para `events.tribe_id` drop:

```sql
CREATE OR REPLACE FUNCTION public.smoke_events_tribe_id_post_drop()
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.get_tribe_events_timeline(1, 5, 5);           -- reader
  PERFORM public.update_event_instance('<fixture_id>', …);     -- writer  (H1 #79)
  PERFORM public.drop_event_instance('<fixture_id>', false);   -- writer
  PERFORM public.generate_agenda_template(1);                  -- reader
  RETURN 'OK — 4/4 calls passed';
END $$;
```

Essa função é EPHEMERAL — pode ser dropada após a migration confirmar sucesso.

### D5 — TS layer não-bloqueante mas obrigatório

Como PostgREST / supabase-js não tem acesso ao `pg_proc.prosrc` para checar compile-time, a camada TS é checada via grep CI. Migration pode prosseguir mesmo se TS tem refs stale (o bug só aparece em runtime da edge function ou do browser), mas o deploy do worker/frontend DEVE ser bloqueado se grep retornar matches.

Regra de CI (nova, proposta):

```yaml
# .github/workflows/schema-contract-check.yml
- name: No stale refs to dropped columns
  run: |
    # Read dropped columns from the latest 10 migrations + docs/refactor/DROPPED_COLUMNS.md
    # Grep each (table.column) pattern against supabase/functions/ and src/
    # Fail if any match
```

`docs/refactor/DROPPED_COLUMNS.md` seria um apêndice versionado listando colunas dropadas e data, para o CI não precisar parsear migration SQL.

## Consequências

### Positivas

- **Zero-surpresa em drops futuros** — mesma metodologia aplicada a Phase 5 C4 (members.tribe_id) ou qualquer drop subsequente vai surface o blast radius antes do deploy.
- **Rollback fácil** — se o gate D3 falha, a migration inteira aborta via RAISE em transação. Nenhum estado parcial.
- **Documentação auto-coletada** — o comment header da migration vira histórico auditável.
- **Dois dias de economia por drop** — #79 e #80 juntos consumiram ~1 dia de sessão debug. Gate automático teria prevenido.

### Negativas

- **Mais 30-60min por migration drop** — escrever o DO block + smoke test. Aceitável para ops com baixa frequência (drops são raros).
- **Função `check_schema_drift` precisa manutenção** — regex/padrões evoluem conforme codebase. Mantê-la em `public` com tests.
- **CI adiciona latência ao pipeline** — grep de ~5 diretórios leva 1-3s. Aceitável.

### Não-consequências (forças que NÃO mudam)

- Não altera o modelo de deploy atual (supabase CLI + git push).
- Não substitui `check_schema_invariants()` — aquele cobre data integrity; este cobre code↔schema contract. Complementares.
- Não é migration retroativa — só aplica a drops futuros (post-2026-04-21).

## Alternativas consideradas

1. **Apenas grep global** (sem função pg) — rejeitada: grep sobre `pg_proc.prosrc` requer consulta SQL, que é mais robusta que ler dump de schema via CI.
2. **Migração via feature flags (coluna `*_v2`)** — rejeitada: aumenta complexity do schema, já temos dual-write pattern estabelecido em ADR-0015. ADR-0017 complementa, não substitui.
3. **Deploy em janela de manutenção** — não resolve o problema fundamental (silenciamento de falhas via `data` sem `error`).
4. **CI test que chama cada RPC em staging** — rejeitada: não temos ambiente staging permanente; contract test em pg_proc é proxy suficiente.

## Métricas de sucesso

- Taxa de bugs pós-drop: **0 em 3 próximos drops** (baseline: 2 em 2 últimos drops — Phase 3d + Phase 3e).
- Tempo entre drop e detecção de regressão: < 1h (baseline: 3-6 dias).

## Referências

- Issue #79 — RPCs com refs stale a `events.tribe_id`
- Issue #80 — Worker TS com refs stale a `events.tribe_id` + `project_boards.tribe_id`
- Issue #81 item #3 — proposta inicial desta ADR
- ADR-0015 — Tribes Bridge Consolidation (refactor cujos drops expuseram o gap)
- Commit `589064f` — sweep retroativo Phase 3d (precedente do padrão de fix)
- Commit `c5b1447` — migration 20260505030000, fix canônico #79
- Commit `b91db51` — worker refactor #80
