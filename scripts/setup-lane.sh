#!/usr/bin/env bash
# Prepara uma worktree de lane para trabalhar. Idempotente: rodar de novo e seguro.
#
# POR QUE ISTO EXISTE (08-09/09/2026). Uma lane e um `git worktree`, e worktree compartilha o
# `.git` mas NAO compartilha o que o git ignora. Consequencia medida na `.wt-campanha`:
#
#   node_modules: AUSENTE   -> `./node_modules/.bin/astro build` nao roda, e o gate de build do
#                              projeto (CLAUDE.md) e obrigatorio antes de commitar
#   .env:         AUSENTE   -> build e testes DB-aware nao rodam; os DB-aware SKIPAM em silencio,
#                              que e pior que falhar
#   branch:       24 commits atras da main, apontando para uma branch ja mergeada
#
# Nenhum dos tres grita. A lane parece pronta e so falha quando alguem tenta o gate, ou pior,
# fica verde por ausencia.
#
# Uso:
#   scripts/setup-lane.sh <caminho-da-worktree> [nome-da-branch]
#   scripts/setup-lane.sh ../.wt-campanha lane/webinar-t11
#   scripts/setup-lane.sh ../.wt-campanha            # so verifica, nao troca de branch
#
# Rode a partir da arvore principal (a que TEM .env), porque e dela que o .env e copiado.

set -uo pipefail

ALVO="${1:-}"
BRANCH="${2:-}"
PRINCIPAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "$ALVO" ]; then
  echo "uso: scripts/setup-lane.sh <caminho-da-worktree> [nome-da-branch]" >&2
  exit 2
fi
if [ ! -d "$ALVO" ]; then
  echo "ERRO: $ALVO nao existe. Crie a worktree primeiro:" >&2
  echo "  git worktree add $ALVO -b <branch> origin/main" >&2
  exit 2
fi

ALVO="$(cd "$ALVO" && pwd)"
echo "lane:       $ALVO"
echo "principal:  $PRINCIPAL"
[ "$ALVO" = "$PRINCIPAL" ] && { echo "ERRO: alvo e a arvore principal." >&2; exit 2; }

FALHAS=0
aviso() { echo "  ⚠ $*"; FALHAS=$((FALHAS+1)); }
ok()    { echo "  ✓ $*"; }

# ── 1. git ────────────────────────────────────────────────────────────────────
echo
echo "[1/4] git"
git -C "$ALVO" fetch -q --all --prune 2>/dev/null

if [ -n "$BRANCH" ]; then
  # A branch nova nasce de origin/main, NAO do HEAD atual: em arvore compartilhada o HEAD pode
  # estar dezenas de commits atras, e a branch nasceria velha sem ninguem perceber.
  if git -C "$ALVO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$ALVO" checkout -q "$BRANCH" && ok "na branch $BRANCH (ja existia)"
  else
    git -C "$ALVO" checkout -q -b "$BRANCH" origin/main && ok "branch $BRANCH criada de origin/main"
  fi
fi

ATUAL="$(git -C "$ALVO" branch --show-current)"
ATRAS="$(git -C "$ALVO" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
SUJO="$(git -C "$ALVO" status --porcelain | wc -l)"
echo "  branch: ${ATUAL:-<detached>}"
[ "$ATRAS" = "0" ] && ok "em dia com origin/main" || aviso "$ATRAS commit(s) atras de origin/main"
[ "$SUJO" = "0" ] && ok "arvore limpa" || echo "  ℹ $SUJO arquivo(s) modificado(s)"

# ── 2. .env ───────────────────────────────────────────────────────────────────
echo
echo "[2/4] .env (worktree NAO herda arquivo ignorado)"
if [ -f "$PRINCIPAL/.env" ]; then
  if [ -f "$ALVO/.env" ] && cmp -s "$PRINCIPAL/.env" "$ALVO/.env"; then
    ok ".env presente e identico ao da principal"
  else
    cp "$PRINCIPAL/.env" "$ALVO/.env" && ok ".env copiado da arvore principal"
  fi
  for k in PUBLIC_SUPABASE_URL PUBLIC_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY; do
    grep -q "^$k=" "$ALVO/.env" && ok "$k" || aviso "$k ausente: testes DB-aware vao SKIPAR em silencio"
  done
else
  aviso "a arvore principal nao tem .env; nada a copiar"
fi

# ── 3. dependencias ───────────────────────────────────────────────────────────
echo
echo "[3/4] node_modules"
if [ -x "$ALVO/node_modules/.bin/astro" ]; then
  ok "node_modules presente (astro executavel)"
else
  echo "  instalando com npm ci (demora alguns minutos)..."
  ( cd "$ALVO" && npm ci >/tmp/setup-lane-npmci.log 2>&1 )
  if [ -x "$ALVO/node_modules/.bin/astro" ]; then
    ok "npm ci concluido"
  else
    aviso "npm ci falhou; veja /tmp/setup-lane-npmci.log"
  fi
fi

# ── 4. memoria ────────────────────────────────────────────────────────────────
# O namespace de memoria do Claude vem do CAMINHO, entao uma worktree nasce com namespace
# proprio e VAZIO. As lanes deste repo resolvem com symlink para o namespace da principal.
echo
echo "[4/4] memoria do Claude"
ns() { echo "$1" | sed 's|/|-|g; s|\.|-|g'; }
NS_ALVO="$HOME/.claude/projects/$(ns "$ALVO")/memory"
NS_PRIN="$HOME/.claude/projects/$(ns "$PRINCIPAL")/memory"
if [ -L "$NS_ALVO" ]; then
  ok "symlink para $(readlink "$NS_ALVO" | sed "s|$HOME|~|")"
elif [ -d "$NS_ALVO" ]; then
  N=$(ls "$NS_ALVO" | wc -l); M=$(ls "$NS_PRIN" 2>/dev/null | wc -l)
  aviso "namespace PROPRIO com $N arquivos (a principal tem $M). Para unificar:"
  echo "      rm -rf '$NS_ALVO' && ln -s '$NS_PRIN' '$NS_ALVO'"
else
  mkdir -p "$(dirname "$NS_ALVO")"
  ln -s "$NS_PRIN" "$NS_ALVO" && ok "symlink criado"
fi

# ── resumo ────────────────────────────────────────────────────────────────────
echo
if [ "$FALHAS" = "0" ]; then
  echo "✅ lane pronta. Gate antes de commitar:  ./node_modules/.bin/astro build  &&  npm test"
else
  echo "⚠️  lane preparada com $FALHAS pendencia(s) acima. Resolva antes de confiar num verde."
fi
exit 0
