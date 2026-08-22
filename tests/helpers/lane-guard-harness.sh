#!/usr/bin/env bash
# Harness do guard da faixa (#1923). Extrai o script embutido em
# .github/actions/wait-for-db-lane/action.yml e o executa contra um `gh` FALSO, para provar
# comportamento em vez de presenca de string.
#
# Uso: lane-guard-harness.sh <cenario> <dir-de-trabalho>
# Cenarios: filtro | cota-recupera | cota-nao-volta | erro-permanente
set -euo pipefail

CENARIO="$1"
WORK="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

mkdir -p "$WORK/bin" "$WORK/ws/.github/workflows"

python3 - "$ROOT/.github/actions/wait-for-db-lane/action.yml" "$WORK/lane.sh" <<'PY'
import sys, io, yaml
d = yaml.safe_load(io.open(sys.argv[1], encoding='utf-8'))
io.open(sys.argv[2], 'w', encoding='utf-8').write(d['runs']['steps'][0]['run'])
PY

# Dois workflows COM job de faixa, tres SEM. O filtro tem de enxergar exatamente os dois.
printf 'jobs:\n  validate:\n    steps:\n      - uses: ./.github/actions/wait-for-db-lane\n' > "$WORK/ws/.github/workflows/ci.yml"
printf 'jobs:\n  check-invariants:\n    steps:\n      - uses: ./.github/actions/wait-for-db-lane\n' > "$WORK/ws/.github/workflows/invariants-check.yml"
printf 'jobs:\n  analyze:\n    steps:\n      - run: echo codeql\n' > "$WORK/ws/.github/workflows/codeql.yml"
printf 'jobs:\n  deploy:\n    steps:\n      - run: echo deploy\n' > "$WORK/ws/.github/workflows/deploy.yml"
printf 'jobs:\n  deno:\n    steps:\n      - run: echo deno\n' > "$WORK/ws/.github/workflows/deno.yml"

cat > "$WORK/bin/gh" <<GHEOF
#!/usr/bin/env bash
# \`gh\` falso. Registra cada chamada em \$CALLS e responde conforme \$CENARIO.
echo "\$*" >> "$WORK/calls.log"
endpoint="\$2"

case "\$endpoint" in
  rate_limit)
    # reset daqui a 2s, para o cenario de recuperacao terminar rapido
    echo \$(( \$(date +%s) + 2 ))
    exit 0
    ;;
esac

case "$CENARIO" in
  cota-recupera)
    n=\$(grep -c 'actions/runs?per_page' "$WORK/calls.log" || true)
    if [ "\$n" -le 2 ]; then
      echo "gh: API rate limit exceeded for installation" >&2
      exit 1
    fi
    ;;
  cota-nao-volta)
    echo "gh: API rate limit exceeded for installation" >&2
    exit 1
    ;;
  erro-permanente)
    echo "gh: HTTP 401: Bad credentials" >&2
    exit 1
    ;;
esac

# Resposta feliz. 5 runs ativos: 2 de workflow de faixa, 3 nao.
case "\$endpoint" in
  *"actions/runs?per_page"*)
    printf '%s\t%s\n' 101 .github/workflows/ci.yml
    printf '%s\t%s\n' 102 .github/workflows/invariants-check.yml
    printf '%s\t%s\n' 103 .github/workflows/codeql.yml
    printf '%s\t%s\n' 104 .github/workflows/deploy.yml
    printf '%s\t%s\n' 105 .github/workflows/deno.yml
    ;;
  *"/jobs"*)
    # Só o run 101 tem job de faixa vivo, e ele SOU EU -> a faixa esta livre e o script sai 0.
    case "\$endpoint" in
      *"/101/"*) printf '%s\t%s\t%s\n' 2026-08-22T03:00:00Z 101 validate ;;
    esac
    ;;
esac
exit 0
GHEOF
chmod +x "$WORK/bin/gh"

: > "$WORK/calls.log"
set +e
PATH="$WORK/bin:$PATH" \
GITHUB_RUN_ID=101 GITHUB_JOB=validate \
GITHUB_REPOSITORY=fake/repo GITHUB_WORKSPACE="$WORK/ws" \
LANE_JOBS="validate check-invariants" \
MAX_WAIT="${MAX_WAIT:-3600}" STUCK_AFTER="${STUCK_AFTER:-1800}" \
API_RETRIES="${API_RETRIES:-3}" SETTLE="${SETTLE:-0}" \
RL_MAX_WAIT="${RL_MAX_WAIT:-6}" POLL="${POLL:-1}" POLL_LONG="${POLL_LONG:-1}" \
POLL_BACKOFF_AFTER="${POLL_BACKOFF_AFTER:-20}" \
bash "$WORK/lane.sh" > "$WORK/out.log" 2>&1
echo "exit=$?"
set -e
echo "jobs_calls=$(grep -c '/jobs' "$WORK/calls.log" || true)"
echo "runs_calls=$(grep -c 'actions/runs?per_page' "$WORK/calls.log" || true)"
