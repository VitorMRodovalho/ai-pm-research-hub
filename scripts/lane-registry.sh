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
#   scripts/lane-registry.sh check [<cwd>]     # imprime alerta se houver worktree fora do registro
set -uo pipefail

REG="${LANE_REGISTRY:-$HOME/projects/_pmo/lanes/ai-pm-research-hub.tsv}"
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
    ;;
  *)
    echo "uso: $0 register <caminho> \"<proposito>\" | check [<cwd>]" >&2
    exit 2
    ;;
esac
exit 0
