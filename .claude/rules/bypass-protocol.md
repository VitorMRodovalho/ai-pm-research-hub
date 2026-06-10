# --admin / Bypass Protocol (post-p209 governance)

**Status:** active since 2026-05-21 (p209 close, WATCH-207.D resolution path C — Híbrido)
**Threshold:** **2 bypass events / 7-day window** before mandatory pause + audit
**Audit cron:** `.github/workflows/bypass-audit-weekly.yml` (Mondays 10:00 UTC, opens issue with previous week's bypass count + breakdown)

## Background

Between 2026-05-18 → 2026-05-21 (p199 → p209 close), **16 bypass events** were issued (9 `gh pr merge --admin` + 7 direct pushes to main). Each was justified at the moment, but cumulative pattern showed erosion: "CI is already red, just go" became default mode.

Option B (revoke --admin entirely) was rejected — solo owner needs flexibility for emergencies. Option C (this protocol) keeps --admin AVAILABLE but adds tripwire automation.

## Criteria — when --admin is legitimate

A bypass IS legitimate if **ALL** apply:

1. **CI red was NOT caused by this PR** (pre-existing fail or external infra issue)
2. **A tracking issue is filed BEFORE merge** documenting the root cause (e.g., #226 BUG-225.A)
3. **PR comment explicitly notes** "--admin bypass — pre-existing CI red, see issue #X"
4. **A follow-up issue exists** committing to remediation within N sessions (or this PR IS the remediation)
5. **No more than 2 bypasses in current 7-day window** (per weekly audit)

A bypass is NOT legitimate if ANY apply:

- CI red was caused by this PR's own changes
- "Just to ship faster" (impatience) without external blocker
- Skipping required reviews because reviewer is slow
- Bypassing failed security/lint checks introduced by this PR

## Protocol when threshold (2/week) is hit

1. **Pause merges** until weekly audit reviewed
2. **Review weekly audit issue** — was each justification legitimate per above criteria?
3. **If YES** (all legitimate): document why this week was unusual + acknowledge
4. **If NO** (any not legitimate): file remediation issue for the root cause that forced impatient bypass; commit to fix BEFORE next bypass

## Protocol per single --admin merge

Use as comment template in PR:

```
## --admin bypass justification

- CI failure cause: <pre-existing OR introduced-by-PR — only pre-existing allowed>
- Tracking issue: #<N>
- Why bypass over wait-for-fix: <one sentence>
- Follow-up commitment: <issue ref OR commit ref>
- Week bypass count (pre-merge): <run audit query>
```

## Direct push to main (no PR)

Same criteria applies, with addition:

- Issue must be filed BEFORE push (no retroactive justification)
- Commit message includes `Bypass-Reason:` trailer (informational, GitHub doesn't enforce)
- Counts as 1 bypass event in weekly audit

## Audit script (manual on-demand)

```bash
# Quick check: bypass events in last 7 days
gh pr list --state merged --search "merged:>$(date -d '7 days ago' +%Y-%m-%d)" --json number,mergedAt,mergeCommit --jq '.[] | select(.mergeCommit) | .number' | while read PR; do
  COMMIT=$(gh pr view $PR --json mergeCommit -q .mergeCommit.oid)
  CHECKS_STATUS=$(gh api repos/VitorMRodovalho/ai-pm-research-hub/commits/$COMMIT/check-runs --jq '[.check_runs[] | select(.name=="validate") | .conclusion] | first')
  if [ "$CHECKS_STATUS" != "success" ]; then
    echo "PR #$PR — validate=$CHECKS_STATUS — likely --admin merge"
  fi
done
```

## Dependabot PRs (política #611 — Option A, ratificada PM 2026-06-10)

**Fato estrutural:** GitHub **não injeta repo secrets** em workflow runs disparados pelo
Dependabot. O sentinel do `validate` (`SUPABASE_URL` + `SERVICE_ROLE_KEY` obrigatórios)
falha portanto em **todo** PR do Dependabot, para sempre — não é flake, não é regressão,
não debugar (descoberta 2026-06-10, PRs #598/#255; ver #611).

**Política (Option A — supersede-as-policy):**

1. **NUNCA mergear um PR do Dependabot** (nem com `--admin` — um Dependabot vermelho
   não satisfaz nenhum critério de bypass legítimo acima: o red É causado pela natureza
   do run, e mergear pularia TODOS os contract tests DB-aware).
2. Cada onda de **security alerts** é resolvida por **PR local de higiene** (autoria
   humana/assistida) onde o CI roda completo com secrets — padrão do PR #609.
3. PRs do Dependabot existentes são **fechados como superseded** com referência a #611
   (feito 2026-06-10 para #149–#153).
4. `dependabot.yml` opera com `open-pull-requests-limit: 0` (alerts-only): o feed de
   alertas continua dirigindo o trabalho, sem acumular PRs vermelhos imergeáveis.

**Por que não carve-out no sentinel (Option B, rejeitada):** um skip condicionado a
`github.actor == 'dependabot[bot]'` criaria um segundo significado de "CI verde" — o
audit semanal de bypass raciocina sobre conclusões do `validate`, e um verde-sem-DB-gates
contaminaria essa superfície, além de exigir guarda contra actor spoofing. Option C
(`pull_request_target` com secrets) é o foot-gun canônico de Actions — auto-rejeitada.

**Reconsiderar** apenas se a cadência de alertas crescer a ponto de o supersede local
virar imposto semanal (histórico: ~1 onda/mês).

## Cross-ref

- WATCH-207.D (P162 log #95): origin of bypass erosion concern
- WATCH-209.C (P162 log #99): direct push counting addition
- p209 close handoff: 16 bypass events documented + Option C decision
- #611: Dependabot supersede-as-policy (seção acima, 2026-06-10)
- CLAUDE.md: references this file in operational rules
