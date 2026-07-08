# ADR-0122 - Métrica do bypass-audit: contar só push na main sem PR mergeado

**Status:** Accepted (2026-07-08)
**Relacionado:** `.claude/rules/bypass-protocol.md` (Option C - Híbrido, p209) · #1142 (audit W28, 73 eventos) · #1182 (diagnóstico + spec) · `.github/workflows/bypass-audit-weekly.yml`

## Contexto

A auditoria semanal de bypass (W28, issue #1142) acusou **73 eventos contra limiar 2**. A inspeção (#1182 + re-contagem ao vivo em 08/07) mostrou que **69 dos 73 eram squash-merges de PRs revisados e mergeados** - falsos positivos. Só **4 eram pushes diretos reais** (3 commits docs de governança + 1 feat governado pelo ADR-0121, todos autorizados pelo owner na semana da virada C4).

A causa raiz NÃO era a definição da métrica: o workflow já tentava excluir squash-merges consultando `GET /commits/{sha}/pulls`. O que quebrou foi a **associação commit↔PR no GitHub após o history-rewrite + force-push de 04/07** (scrub do ADR-0120): os SHAs da main foram remapeados e os PRs continuam apontando os SHAs antigos pendurados, então a consulta retorna vazio para todo commit remapeado. Verificado ao vivo em 08/07: commits pós-rewrite (ex. PRs #1194/#1196) associam normalmente; commits remapeados retornam `[]`.

Agravante silencioso: o passo usava `2>/dev/null || echo 0`, tratando erro de API como "sem PR" sem qualquer sinal no report.

## Decisão

**Opção (a) do #1182: o bucket com threshold conta apenas commit na main SEM PR mergeado associado.** O report semanal passa a ter 3 buckets:

1. **`--admin` merges** - contam no threshold (inalterado).
2. **Pushes diretos SEM PR mergeado** - contam no threshold (limiar mantido em 2/semana).
3. **Pushes PR-backed** (squash-merges) - listados em `<details>` informativo, NÃO contam.

A associação commit→PR é resolvida em duas camadas, para ser robusta a history-rewrite:

1. `GET /commits/{sha}/pulls` filtrando PRs com `merged_at` (autoritativa com histórico intacto);
2. **Fallback rewrite-proof:** última referência `(#N)` no subject do commit (convenção do squash-merge do GitHub), verificada contra a API como PR realmente `merged`. Referência a issue (não-PR ou PR aberto) não passa na verificação e o commit cai no bucket contado.

Erro de API na checagem de associação agora **conta no bucket com threshold com a marca "(association check failed)"** - falha ruidosa na direção da revisão, nunca skip silencioso.

## Alternativa rejeitada

**Opção (b): require-PR via ruleset do GitHub.** Rejeitada pelo PMO (2026-07-07): repositório de dev solo onde os PRs já existem e são revisados; um ruleset só adicionaria atrito sem ganho de controle, e mataria a válvula de emergência que o Option C preserva deliberadamente.

**Condição de reversão explícita:** se entrar um segundo committer regular no repositório, reavaliar require-PR via ruleset (a premissa "dev solo com disciplina de PR" deixa de valer).

## Consequências

- O alerta semanal volta a significar alguma coisa: bucket contado = eventos que o protocolo realmente governa (`--admin` + push sem PR). W28 real: 4 eventos (ainda acima do limiar 2; parecer registrado no #1142 - semana excepcional da virada C4 + scrub, todos os 4 autorizados pelo owner).
- O audit fica imune a history-rewrites futuros (o fallback por subject não depende da associação do GitHub).
- Pushes docs-only continuam contando: o protocolo não tem carve-out por tipo de arquivo, e criar um aqui seria escopo além do #1182. Se o padrão "3 docs-push/semana" persistir fora de semanas excepcionais, tratar em decisão própria.
- Validação pendente: W29 deve sair com o bucket contado limpo (critério de aceite do #1182).
