#!/usr/bin/env bash
# Registro de lanes (#2477). A sessao principal e quem abre lanes; toda worktree fica registrada.
#
# POR QUE (25/09/2026): uma worktree de lane, aberta fora da sessao principal, aplicou 2 migrations
# direto no banco compartilhado, e a principal nem sabia que ela existia. O registro e o que torna
# uma worktree desconhecida VISIVEL no inicio de cada sessao.
#
# O registro fica FORA do repositorio (o repo e publico, e o nome de uma lane de advisory ja diz
# demais): ${LANE_REGISTRY:-$HOME/projects/_pmo/lanes/ai-pm-research-hub.tsv}
# Formato TSV: caminho <TAB> branch <TAB> aberta_em (UTC) <TAB> proposito
#
# Uso:
#   scripts/lane-registry.sh register <caminho-da-worktree> "<proposito>"
#   scripts/lane-registry.sh orquestrador <session_id> "<nota>"   # designacao do GP (#2477)
#   scripts/lane-registry.sh check [<cwd>]     # SessionStart: status da orquestradora e alertas
#
# A sessao ORQUESTRADORA e a unica que escreve no banco compartilhado (.claude/hooks/db-write-gate.py).
# A designacao fica em ${LANE_ORCH_FILE:-$HOME/projects/_pmo/lanes/ai-pm-research-hub.orquestrador}.
set -uo pipefail

REG="${LANE_REGISTRY:-$HOME/projects/_pmo/lanes/ai-pm-research-hub.tsv}"
ORQ="${LANE_ORCH_FILE:-$HOME/projects/_pmo/lanes/ai-pm-research-hub.orquestrador}"
GATE_COPY="${LANE_GATE_COPY:-$HOME/projects/_pmo/lanes/db-write-gate.py}"
MODE="${1:-}"

abspath() { (cd "$1" 2>/dev/null && pwd -P) || echo "$1"; }

case "$MODE" in
  register)
    ALVO="$(abspath "${2:-}")"
    PROP="${3:-}"
    [ -n "${2:-}" ] || { echo "uso: $0 register <caminho> \"<proposito>\"" >&2; exit 2; }
    [ -n "$PROP" ] || { echo "ERRO: registre o PROPOSITO da lane (3o argumento)." >&2; exit 2; }
    mkdir -p "$(dirname "$REG")"
    [ -f "$REG" ] || printf 'caminho\tbranch\taberta_em\tproposito\n' > "$REG"
    if cut -f1 "$REG" | grep -qxF "$ALVO"; then
      echo "  ✓ lane ja registrada: $ALVO"
    else
      BR="$(git -C "$ALVO" branch --show-current 2>/dev/null)"
      printf '%s\t%s\t%s\t%s\n' "$ALVO" "${BR:-?}" "$(date -u +%Y-%m-%dT%H:%MZ)" "$PROP" >> "$REG"
      echo "  ✓ lane registrada em $REG"
    fi
    ;;
  orquestrador)
    SID="${2:-}"; NOTA="${3:-}"
    [ -n "$SID" ] && [ -n "$NOTA" ] || { echo "uso: $0 orquestrador <session_id> \"<nota: quem designou e quando>\"" >&2; exit 2; }
    mkdir -p "$(dirname "$ORQ")"
    printf '%s\t%s\t%s\n' "$SID" "$(date -u +%Y-%m-%dT%H:%MZ)" "$NOTA" > "$ORQ"
    echo "  ✓ orquestradora designada: ${SID:0:8} ($ORQ)"
    ;;
  check)
    CWD="${2:-$PWD}"
    # So a sessao PRINCIPAL checa: numa lane, git-dir difere de git-common-dir.
    GD="$(git -C "$CWD" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
    CD="$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    [ -n "$GD" ] && [ -n "$CD" ] || exit 0
    [ "$(abspath "$GD")" = "$(abspath "$CD")" ] || exit 0
    PRINCIPAL="$(abspath "$(git -C "$CWD" rev-parse --show-toplevel)")"
    mapfile -t WTS < <(git -C "$CWD" worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print}')
    FORA=()
    for w in "${WTS[@]}"; do
      w="$(abspath "$w")"
      [ "$w" = "$PRINCIPAL" ] && continue
      if [ ! -f "$REG" ] || ! cut -f1 "$REG" | grep -qxF "$w"; then FORA+=("$w"); fi
    done
    if [ "${#FORA[@]}" -gt 0 ]; then
      echo "⚠️ LANES FORA DO REGISTRO (${#FORA[@]}): worktree que a sessao principal nao abriu ou nao registrou."
      printf '   - %s\n' "${FORA[@]}"
      echo "   Descubra quem a abriu e para que ANTES de qualquer merge ou escrita no banco; registre com"
      echo "   scripts/lane-registry.sh register <caminho> \"<proposito>\" (registro: $REG)."
    fi
    # Status da orquestradora: o SessionStart recebe o session_id no JSON do stdin.
    SID=""
    if [ ! -t 0 ]; then SID="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id",""))
except Exception: print("")' 2>/dev/null)"; fi
    ORQ_ID="$( [ -f "$ORQ" ] && grep -v '^#' "$ORQ" | head -1 | cut -f1 )"
    if [ -z "$ORQ_ID" ]; then
      echo "⚠️ NENHUMA SESSAO ORQUESTRADORA designada: o gate nega DDL e escrita via SQL a todos ate o GP designar."
    elif [ -n "$SID" ] && [ "$SID" = "$ORQ_ID" ]; then
      echo "Esta sessao (${SID:0:8}) e a ORQUESTRADORA designada: unica que escreve no banco compartilhado."
    elif [ -n "$SID" ]; then
      echo "Esta sessao (${SID:0:8}) NAO e a orquestradora (${ORQ_ID:0:8}): DDL e escrita via SQL serao negadas."
    fi
    # Mais de uma sessao do Claude no clone principal e o arranjo que produziu o incidente de 25/09.
    # Chave no EXECUTAVEL (exe), nao no nome do processo (comm), que o processo escolhe. Um find so,
    # sem um fork por processo: a varredura cabe no SessionStart (~0,1 s medido).
    N=0
    while read -r EXE; do
      [ "$(readlink "${EXE%/exe}/cwd" 2>/dev/null)" = "$PRINCIPAL" ] && N=$((N+1))
    done < <(find /proc -maxdepth 2 -name exe -lname '*/claude/versions/*' 2>/dev/null)
    if [ "$N" -gt 1 ]; then
      echo "⚠️ $N SESSOES DO CLAUDE NO CLONE PRINCIPAL. So uma e a orquestradora; as outras nao abrem lane nem escrevem no banco."
    fi
    # A copia do gate usada pelo hook de usuario tem de ser igual a versao do repo.
    REPO_GATE="$PRINCIPAL/.claude/hooks/db-write-gate.py"
    if [ -f "$REPO_GATE" ] && [ -f "$GATE_COPY" ] && ! cmp -s "$REPO_GATE" "$GATE_COPY"; then
      echo "⚠️ A copia do gate em $GATE_COPY difere de .claude/hooks/db-write-gate.py: atualize a copia (cp)."
    fi
    ;;
  *)
    echo "uso: $0 register <caminho> \"<proposito>\" | orquestrador <session_id> \"<nota>\" | check [<cwd>]" >&2
    exit 2
    ;;
esac
exit 0
