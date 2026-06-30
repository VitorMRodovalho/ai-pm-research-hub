# ADR-0112 — Portabilidade institucional para migração/encerramento (#572 Block A)

**Status:** Accepted (2026-06-29, #572 Block A)
**Relacionado:** ADR-0007 (V4 `can()` autoridade) · ADR-0010 (wiki = conhecimento narrativo; dados operacionais ficam no SQL) · #568 (export por-titular Art.18 — `export_my_data`) · #963/#570 (anti-open-relay nos grants) · Parecer Técnico-Jurídico 01/2026 rec (g) · doc4 §6.4 · `docs/operations/INSTITUTIONAL_EXPORT_RUNBOOK.md` · `docs/legal/INSTITUTIONAL_EXPORT_DATA_DICTIONARY.md`.
**Migration:** `20260805000299_572_block_a_institutional_export_rpcs.sql`.

## Contexto

O Parecer 01/2026 rec (g) + doc4 §6.4 exigem **portabilidade institucional**: na **migração** da plataforma para um operador-sucessor ou no **encerramento** do Programa, o controlador (PMI-GO/GP) precisa exportar **todos os dados operacionais + logs de auditoria** em formato **aberto/não-proprietário/interoperável**, acompanhados de um **dicionário de dados** (leitura/validação/reimportação), preservando integridade/completude e **registrando a própria exportação no audit log**. Isso é **distinto** do direito de portabilidade **individual** do titular (LGPD Art. 18, V), já entregue por `export_my_data` (#568) — não confundir os dois frameworks de conformidade.

A plataforma tem escala pequena (≈201 tabelas / ≈65k linhas / ≈99 MB no schema `public`, + `z_archive`). A operação é **rara** (no máximo uma vez na vida da plataforma).

## Decisão

**1. Mecanismo = `pg_dump` pela conexão Postgres direta + 4 RPCs SECDEF de apoio.**

O dump em massa é `pg_dump --schema=public --schema=z_archive --no-owner --no-acl --format=plain` (SQL aberto: DDL + `COPY`, reimportável com `psql` num **Postgres 14+ compatível com Supabase** — o schema `auth` e suas funções `auth.uid()`/`auth.role()` devem pré-existir, pois as políticas RLS dumpadas as referenciam; num Postgres puro as políticas RLS precisam de pós-processamento antes do restore). Rodado numa única transação `REPEATABLE READ` (com a janela de manutenção do runbook §1 cobrindo o intervalo manifest→dump), garante **consistência de snapshot** (todas as tabelas no mesmo ponto no tempo) — *essa* é a garantia de "integridade/completude" do critério de aceitação. Os dados **nunca trafegam por HTTP/PostgREST**.

Rejeitados:
- **RPC mega-JSON** (`export_institutional_data()` retornando o banco inteiro): a 65k linhas gera 100–300 MB de texto, estoura o `statement_timeout` de 60s do PostgREST, e perde fidelidade de enum/FK/ordem topológica.
- **Edge Function streaming+ZIP**: 200+ LOC de encanamento + teto de memória do Deno (~150 MB) para uma operação que roda no máximo uma vez; vira artefato vivo sem callers.
- **RPCs por-tabela iteradas por um orquestrador**: sem isolamento de snapshot entre chamadas → FK pendente no output (falha de correção num export crítico de integridade).

Em volta do `pg_dump`, a migration `…299` cria **4 RPCs SECDEF** (migration capturada; sem novo primitivo de autoridade):
- `generate_institutional_export_manifest(p_justification, p_export_id, p_trigger_event)` — manifesto de integridade pré-dump: **SHA-256 por tabela** (`extensions.digest`; hash de conteúdo até 20k linhas, hash count-only acima, para não estourar o timeout) + **hash agregado**; **justificativa obrigatória** (≥10 chars), **rate-limit 5/30 dias**, e **auditoria fase-1** (`institutional_export.manifest_generated`).
- `export_institutional_data_dictionary()` — dicionário legível por máquina (tabela/coluna/tipo/PK-FK/RLS) para `public` + `z_archive`, com `excluded_schemas` e `rls_note`.
- `export_redacted_settings()` — **única** via de export de `site_config`/`platform_settings` (cujos dados são `--exclude-table-data` no `pg_dump`), com chaves `_secret`/`_token`/`_key` mascaradas para `[REDACTED]`.
- `register_institutional_export_completion(p_export_id, p_dump_sha256, p_dump_bytes, p_notes)` — **auditoria fase-2** (`institutional_export.completed`), valida que existe um manifesto para o `export_id`.

**2. Autoridade = `can_by_member('manage_platform') AND caller_chapter_scope() IS NULL` (GP/sede), em todas as 4 RPCs.**

`manage_platform` é o gate GP-global canônico (ADR-0007). **Não** `view_pii` — esta é detida por ~11 parceiros de capítulo e gateá-la seria exatamente o vazamento cross-capítulo que a FU-2 (Onda 2) fechou. O `caller_chapter_scope() IS NULL` é defense-in-depth (espelha o gate de `export_audit_log_csv`). Grants: `REVOKE PUBLIC/anon` + `GRANT authenticated, service_role` (anti-open-relay #963/#570; o gate interno faz a autorização real; `service_role` permite os contract tests rodarem).

**Risco aceito — autorização por ator único.** Um único JWT `manage_platform` comprometido pode disparar o dump. Os controles (rate-limit + justificativa obrigatória + auditoria de duas fases) são **detecção/dissuasão, não prevenção**. Dual-control (tabela de aprovação por 2 GPs) fica como **follow-up**, deliberadamente fora do Block A dado que migração/encerramento é evento raro e deliberado. *(Aceitação explícita do PM/DPO registrada no fechamento do PR.)*

**3. Decomposição & red lines.**
- **Block C** (retenção/anonimização) já está **live** (crons `lgpd-anonymize-inactive-monthly`, `v4-anonymize-by-kind-monthly`, `log-retention-monthly`, `ots-retention-monthly`). **Block A** entrega aqui. **Block B** (portabilidade **cross-operador**: PostHog/Anthropic/Credly sob DPA/SCC) permanece **aberto, gated em G12/#334**. **#572 NÃO fecha** com Block A.
- **Excluir absolutamente** os schemas `auth` (hashes de senha Argon2/bcrypt, tokens OAuth — propriedade do operador de autenticação Supabase; migrar pelo canal Auth próprio) e `vault` (segredos). Naturalmente fora de `--schema=public/z_archive`; nomeados em `excluded_schemas` como defense-in-depth.
- **Redigir** segredos em `site_config`/`platform_settings` (hoje exatamente `arm116_calendar_webhook_secret`).
- **Mídia Art. 11** (vídeo/áudio em Drive/YouTube): **não** entra no dump de banco (só URLs). Destino em encerramento segue o caminho separado do #905 sob decisão do DPO (base legal Art. 11).
- **Integridade = snapshot, NÃO hash-chain.** O runbook/ADR **não** afirmam que o dump "prova a cadeia de auditoria" — hash-chain append-only nativa do `admin_audit_log` é escopo de #574 e não está live. A garantia documentada é estritamente **completude de snapshot**.

**4. Gatilho = runbook GP-operado, sem UI nova, sem EF.** O `pg_dump` exige a senha da connection-string (Supabase dashboard → Settings → Database), inalcançável por qualquer RPC — logo um não-DBA não consegue auto-servir um dump (feature, não bug). Procedimento em `docs/operations/INSTITUTIONAL_EXPORT_RUNBOOK.md`.

## Consequências

- A capacidade de portabilidade institucional existe, é auditável (duas fases) e documentada, com superfície de exfiltração mínima (o dump em massa não passa por nenhum endpoint).
- Reúso pesado dos idiomas `export_my_data`/`export_audit_log_csv` + `caller_chapter_scope`; nenhum novo primitivo de autoridade.
- Follow-ups (não-bloqueantes): dual-control (autorização por 2 GPs) · invariante de "export órfão" (manifesto sem completion >72h — hoje consultável por query, não invariante) · wrapper MCP do passo pré-dump para auto-serviço GP · decisão DPO sobre pré-membros (#905) e mídia Art. 11 no dump em cenário real.
