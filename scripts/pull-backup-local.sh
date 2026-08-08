#!/usr/bin/env bash
# pull-backup-local.sh — traz o backup semanal do banco para a maquina local e, opcionalmente,
# ENSAIA a restauracao.
#
# Por que existe (medido em 08/08/2026):
#
#   1. TERCEIRA COPIA. O dump semanal vivia em dois lugares, GitHub artifacts e Cloudflare R2,
#      ambos na nuvem e ambos alcancados pelas mesmas credenciais. Uma copia local e a unica que
#      sobrevive a perda de acesso as duas contas.
#
#   2. BACKUP SO E BACKUP DEPOIS DE RESTAURADO. O workflow verificava que o arquivo existe, que o
#      gzip abre e que tem mais de 1 KB. O backup de 03/08 passava nos tres e perdia
#      `admin_audit_log` inteiro: 67.494 linhas na origem, ZERO no restaurado (#1684).
#
#   3. AMBIENTE DE TESTE DE PERSONA. Gates que resolvem por `auth.uid()` nao sao mensuraveis nem
#      por SQL em producao (entra como service_role) nem pelo conector MCP (entra como o dono).
#      Numa copia restaurada, `set role authenticated` + `set_config('request.jwt.claim.sub', ...)`
#      testa qualquer perfil. Foi assim que #1591 e #1682 sairam do achismo.
#
# ⚠️ O ARQUIVO BAIXADO CONTEM PII. O diretorio de destino nasce 0700, os dumps 0600, e o script
#    RECUSA um destino que esteja dentro de um repositorio git.
#
# Uso:
#   scripts/pull-backup-local.sh                  # baixa o mais novo e poda
#   scripts/pull-backup-local.sh --restore        # baixa e ensaia a restauracao
#   scripts/pull-backup-local.sh --keep 4         # muda a retencao
#   scripts/pull-backup-local.sh --install-timer  # instala o timer semanal do systemd --user
#
# Requer: gh (autenticado), jq, unzip. Para --restore, docker.

set -euo pipefail

REPO="${NUCLEO_BACKUP_REPO:-VitorMRodovalho/ai-pm-research-hub}"
DEST="${NUCLEO_BACKUP_HOME:-$HOME/.local/share/nucleo-backups}"
KEEP="${NUCLEO_BACKUP_KEEP:-8}"
PG_IMAGE="${NUCLEO_BACKUP_PG_IMAGE:-supabase/postgres:17.6.1.084}"
DO_RESTORE=0
INSTALL_TIMER=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)          DEST="$2"; shift 2 ;;
    --keep)          KEEP="$2"; shift 2 ;;
    --repo)          REPO="$2"; shift 2 ;;
    --image)         PG_IMAGE="$2"; shift 2 ;;
    --restore)       DO_RESTORE=1; shift ;;
    --install-timer) INSTALL_TIMER=1; shift ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf '\033[0;31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }

# ── install-timer ────────────────────────────────────────────────────────────
if [ "$INSTALL_TIMER" = "1" ]; then
  UNITS="$HOME/.config/systemd/user"
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  mkdir -p "$UNITS"
  cat > "$UNITS/nucleo-backup-pull.service" <<EOF
[Unit]
Description=Traz o backup semanal do Nucleo IA para a maquina local e ensaia a restauracao
Documentation=https://github.com/$REPO/blob/main/scripts/pull-backup-local.sh

[Service]
Type=oneshot
ExecStart=$SELF --restore
# O dump tem PII: nada de log verboso no journal do usuario.
StandardOutput=journal
EOF
  cat > "$UNITS/nucleo-backup-pull.timer" <<'EOF'
[Unit]
Description=Backup local semanal do Nucleo IA (segunda de manha, depois do dump de domingo 23:00 UTC)

[Timer]
OnCalendar=Mon *-*-* 09:00:00
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now nucleo-backup-pull.timer
  log "timer instalado. Proxima execucao:"
  systemctl --user list-timers nucleo-backup-pull.timer --no-pager | sed -n '1,2p'
  exit 0
fi

# ── pre-condicoes ────────────────────────────────────────────────────────────
command -v gh   >/dev/null || die "gh nao encontrado"
command -v jq   >/dev/null || die "jq nao encontrado"
command -v unzip >/dev/null || die "unzip nao encontrado"
gh auth status >/dev/null 2>&1 || die "gh nao autenticado (rode: gh auth login)"

# O destino NAO pode estar dentro de um repositorio: o dump tem PII e um `git add -A` distraido
# alcancaria 121 membros e 81 candidatos. Isto e barreira, nao conselho.
mkdir -p "$DEST"
if git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "destino '$DEST' esta dentro de um repositorio git. Escolha um caminho fora (o dump tem PII)."
fi
chmod 700 "$DEST"

# ── qual e o artefato mais novo ──────────────────────────────────────────────
log "procurando o backup mais recente em $REPO..."
# Duas armadilhas do `gh api`, ambas pegas ao testar o script em 08/08:
#   1. `--paginate` emite UM documento JSON POR PAGINA. Sem juntar, o filtro roda por pagina e
#      devolve um objeto por pagina — o script montava uma URL com dois ids concatenados.
#   2. `--slurp` junta as paginas num array, mas e INCOMPATIVEL com `--jq`. Dai o pipe externo.
NEWEST=$(gh api "repos/$REPO/actions/artifacts" --paginate --slurp \
  | jq -c '[.[].artifacts[] | select((.name|startswith("db-backup-")) and (.expired|not))]
           | sort_by(.created_at) | last // empty')
[ -n "$NEWEST" ] || die "nenhum artefato db-backup-* disponivel (todos expirados?)"

ART_ID=$(jq -r '.id'         <<<"$NEWEST")
ART_NAME=$(jq -r '.name'     <<<"$NEWEST")
ART_WHEN=$(jq -r '.created_at' <<<"$NEWEST")
ART_SIZE=$(jq -r '.size_in_bytes' <<<"$NEWEST")
log "mais recente: $ART_NAME ($ART_WHEN, $((ART_SIZE/1024/1024)) MB)"

STAMP="${ART_NAME#db-backup-}"
TARGET="$DEST/backup_${STAMP}.sql.gz"

if [ -f "$TARGET" ]; then
  log "ja existe localmente, nada a baixar: $(basename "$TARGET")"
else
  # Idade do backup: se o cron de domingo falhou, o mais novo pode ter semanas. Avisar e o
  # ponto — um backup velho e silencioso e pior que um erro barulhento.
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  log "baixando..."
  gh api "repos/$REPO/actions/artifacts/$ART_ID/zip" > "$TMP/a.zip"
  unzip -o -q "$TMP/a.zip" -d "$TMP"
  SRC=$(find "$TMP" -name '*.sql.gz' -print -quit)
  [ -n "$SRC" ] || die "o artefato nao contem .sql.gz"
  gzip -t "$SRC" || die "gzip corrompido — NAO substituindo a copia local anterior"
  mv "$SRC" "$TARGET"
  chmod 600 "$TARGET"
  log "gravado: $(basename "$TARGET") ($(du -h "$TARGET" | cut -f1))"
fi

AGE_DAYS=$(( ( $(date -u +%s) - $(date -u -d "$ART_WHEN" +%s) ) / 86400 ))
if [ "$AGE_DAYS" -gt 9 ]; then
  printf '\033[1;33mATENCAO:\033[0m o backup mais novo tem %s dias. O cron de domingo pode estar falhando.\n' "$AGE_DAYS"
fi

# ── poda ─────────────────────────────────────────────────────────────────────
mapfile -t ALL < <(ls -1 "$DEST"/backup_*.sql.gz 2>/dev/null | sort -r)
if [ "${#ALL[@]}" -gt "$KEEP" ]; then
  for old in "${ALL[@]:$KEEP}"; do
    log "podando (retencao $KEEP): $(basename "$old")"
    rm -f "$old"
  done
fi
log "copias locais: $(ls -1 "$DEST"/backup_*.sql.gz 2>/dev/null | wc -l) (retencao $KEEP)"

[ "$DO_RESTORE" = "1" ] || exit 0

# ── ensaio de restauracao ────────────────────────────────────────────────────
command -v docker >/dev/null || die "--restore precisa de docker"
CTR="nucleo-restore-probe-$$"
# O log de erro do restore fica APENAS quando o ensaio falha: ele e o unico jeito de diagnosticar,
# e pode conter linhas de dado (foi assim que a cascata do COPY apareceu). Em caso de sucesso e
# apagado; em caso de falha fica 0600 e o caminho e impresso.
cleanup() { docker rm -f "$CTR" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# O volume do container vive na raiz do docker, nao no destino. Avisar se a raiz estiver apertada:
# uma base restaurada ocupa perto de 1 GB e um disco cheio aborta o restore pela metade, que e a
# forma mais confusa de falhar.
FREE_MB=$(df -Pm /var/lib/docker 2>/dev/null | awk 'NR==2{print $4}' || df -Pm / | awk 'NR==2{print $4}')
[ "${FREE_MB:-0}" -gt 3000 ] || printf '\033[1;33mATENCAO:\033[0m so %s MB livres onde o docker guarda dados.\n' "${FREE_MB:-?}"

log "subindo $PG_IMAGE..."
docker run -d --name "$CTR" -e POSTGRES_PASSWORD=probe_ephemeral -e POSTGRES_DB=postgres "$PG_IMAGE" >/dev/null

# ⚠️ `pg_isready` no socket unix NAO e sinal de prontidao nesta imagem. O init sobe um servidor
# TEMPORARIO que escuta so no socket, roda os scripts e o DESLIGA antes de subir o definitivo.
# Medido em 08/08: t=3s o socket aceita e o TCP nao; t=4s o TCP aceita. Conectar no temporario
# faz o restore morrer no meio (`FATAL: the database system is shutting down`) e devolver um banco
# VAZIO — que e exatamente como um backup ruim se parece. O TCP discrimina porque o servidor de
# init roda com listen_addresses vazio.
READY=0
for _ in $(seq 1 60); do
  if docker exec "$CTR" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then READY=1; break; fi
  sleep 2
done
[ "$READY" = "1" ] || die "o Postgres do container nao ficou pronto em 120s"

log "restaurando $(basename "$TARGET")..."
gunzip -c "$TARGET" | docker exec -i "$CTR" psql -U postgres -d postgres -q \
  >/dev/null 2> "$DEST/restore.err" || true

q() { docker exec "$CTR" psql -U postgres -tAc "$1"; }
FAIL=0

# (a) A cascata do COPY. Um unico "syntax error" significa que o psql saiu de um bloco COPY e
# passou a ler dado como comando — foi assim que o admin_audit_log se perdeu inteiro.
SYNTAX=$(grep -c "syntax error" "$DEST/restore.err" || true)
if [ "$SYNTAX" -ne 0 ]; then
  printf '\033[0;31mFALHOU:\033[0m %s erros de sintaxe no restore (perda silenciosa de dado)\n' "$SYNTAX"
  grep -oE "ERROR:  [a-z ]+" "$DEST/restore.err" | sort | uniq -c | sort -rn | head -5
  FAIL=1
else
  log "ok: 0 erro de sintaxe"
fi

# (b) Tabelas que nao podem voltar vazias.
for T in admin_audit_log members board_items events selection_applications notifications; do
  N=$(q "select count(*) from public.$T;" 2>/dev/null || echo 0)
  if [ "${N:-0}" -eq 0 ]; then
    printf '\033[0;31mFALHOU:\033[0m %s restaurou VAZIA\n' "$T"; FAIL=1
  else
    log "ok: $T = $N"
  fi
done

# (c) Pisos estruturais (medidos em 08/08: 213 tabelas, 518 FKs).
TABLES=$(q "select count(*) from pg_tables where schemaname='public';")
FKS=$(q "select count(*) from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where n.nspname='public' and c.contype='f';")
[ "$TABLES" -ge 200 ] || { printf '\033[0;31mFALHOU:\033[0m so %s tabelas (piso 200)\n' "$TABLES"; FAIL=1; }
[ "$FKS"    -ge 500 ] || { printf '\033[0;31mFALHOU:\033[0m so %s FKs (piso 500)\n' "$FKS"; FAIL=1; }
log "estrutura: $TABLES tabelas, $FKS chaves estrangeiras"

# (d) O que este backup NAO restaura, por desenho — informativo, nao falha.
ORFAOS=$(q "select count(*) from public.members m where m.auth_id is not null and not exists (select 1 from auth.users u where u.id=m.auth_id);")
printf '\033[1;33mnota:\033[0m --exclude-schema=auth deixa %s membros com auth_id orfao. O banco volta, o login nao.\n' "$ORFAOS"

if [ "$FAIL" = "0" ]; then
  rm -f "$DEST/restore.err"
  printf '\033[0;32m✅ Ensaio OK\033[0m — %s restaura: %s tabelas, %s FKs, 0 erro de sintaxe.\n' "$(basename "$TARGET")" "$TABLES" "$FKS"
else
  chmod 600 "$DEST/restore.err" 2>/dev/null || true
  printf 'log do restore preservado em %s (0600, pode conter dado — apague depois de diagnosticar)\n' "$DEST/restore.err"
  die "ensaio de restauracao FALHOU — o backup nao e confiavel"
fi
