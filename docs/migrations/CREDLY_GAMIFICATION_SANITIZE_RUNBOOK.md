# Credly/Gamification Sanitize Runbook (v1)

## Objetivo
Sanear inconsistências legadas em `gamification_points` e `members.credly_badges`:
- corrigir pontuação Credly divergente do tier atual,
- remover duplicados por `member_id + reason` (case-insensitive),
- remover double-counting entre `Curso: CODE` e `Credly: ...` para mini trilha,
- preencher `tier/points` faltantes no JSON de badges quando inferível.

## Arquivos
- `docs/migrations/credly-gamification-audit-v1.sql`
- `docs/migrations/credly-gamification-sanitize-v1.sql`
- `docs/migrations/credly-gamification-hardening-v1.sql`
- `docs/migrations/credly-gamification-hardening-rollback-v1.sql`

## Ordem de execução
1. Rodar `credly-gamification-audit-v1.sql` e salvar resultado (`before`).
2. Rodar `credly-gamification-sanitize-v1.sql` em produção.
3. Rodar novamente `credly-gamification-audit-v1.sql` e comparar (`after`).
4. (Opcional recomendado) Rodar `credly-gamification-hardening-v1.sql` para criar índice parcial único anti-duplicação.

## Resultado esperado (DoD de banco)
- Nenhum caso de Tier 1 com 10 pontos (ex.: PMP/CPMAI).
- Nenhum caso de Tier 2 conhecido (`business intelligence`, `scrum foundation`, `sfpc`) com 15 pontos.
- Nenhum duplicado Credly por `member_id + lower(trim(reason))`.
- Nenhum double-counting manual/Credly para os 8 cursos da mini trilha.
- `null_tier_badges = 0` e `missing_tier_key_badges = 0` (quando inferência possível a partir de points/tier).

## Observações
- O script cria backup em `public._bak_gp_credly_sanitize_v1` antes de alterar dados.
- Se precisar rollback do hardening, usar `credly-gamification-hardening-rollback-v1.sql`.
- O `create unique index concurrently` não deve rodar dentro de transação (`BEGIN/COMMIT`).
