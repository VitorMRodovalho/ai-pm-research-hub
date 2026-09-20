#!/usr/bin/env bash
set -euo pipefail

# Publica o artefato de redirect versionado (infra/pages-redirect) no projeto
# Cloudflare Pages "ai-pm-research-hub", que detem nucleoia.pmigo.org.br.
#
# Ver ADR-0130. O projeto NAO constroi por push (deployments_enabled=false):
# este script e o unico caminho de publicacao, e e proposital.
#
# Uso:
#   scripts/deploy-pages-redirect.sh            # preview, nao toca producao
#   scripts/deploy-pages-redirect.sh --prod     # producao

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/infra/pages-redirect"
PROJECT="ai-pm-research-hub"
CANONICAL="https://nucleoia.vitormr.dev"

PROD=0
[[ "${1:-}" == "--prod" ]] && PROD=1

if [[ ! -f "${SRC_DIR}/_redirects" ]]; then
  echo "FAIL: ${SRC_DIR}/_redirects nao existe"
  exit 1
fi

# O diretorio tem de conter APENAS o _redirects. Um index.html aqui seria
# servido em "/" e o redirect nunca dispararia nessa rota.
extra="$(find "${SRC_DIR}" -type f ! -name '_redirects' | wc -l)"
if [[ "${extra}" -ne 0 ]]; then
  echo "FAIL: ${extra} arquivo(s) alem do _redirects em ${SRC_DIR}:"
  find "${SRC_DIR}" -type f ! -name '_redirects'
  echo "Um asset estatico tem precedencia sobre a regra e mata o redirect."
  exit 1
fi

if [[ "${PROD}" -eq 1 ]]; then
  BRANCH="main"
  echo "== PRODUCAO: isto troca o que nucleoia.pmigo.org.br serve =="
else
  BRANCH="preview-$(date -u +%Y%m%d%H%M%S)"
  echo "== PREVIEW (${BRANCH}): producao nao e tocada =="
fi

"${ROOT_DIR}/node_modules/.bin/wrangler" pages deploy "${SRC_DIR}" \
  --project-name "${PROJECT}" --branch "${BRANCH}" --commit-dirty=true \
  | tee /tmp/pages-redirect-deploy.$$.log

url="$(grep -oE 'https://[a-z0-9-]+\.'"${PROJECT}"'\.pages\.dev' /tmp/pages-redirect-deploy.$$.log | head -1)"
rm -f /tmp/pages-redirect-deploy.$$.log
if [[ -z "${url}" ]]; then
  echo "FAIL: nao consegui ler a URL do deploy no log"
  exit 1
fi

echo
echo "== verificacao: o redirect tem de preservar o caminho e a query =="
fail=0
for path in "/" "/verify/TESTE-123" "/a/b/c?x=1&y=2"; do
  hdr="$(curl -sS -D - -o /dev/null --max-time 25 "${url}${path}")"
  code="$(printf '%s' "${hdr}" | awk 'BEGIN{IGNORECASE=1}/^HTTP\//{c=$2}END{print c}')"
  loc="$(printf '%s' "${hdr}" | awk 'BEGIN{IGNORECASE=1}/^location:/{print $2}' | tr -d '\r')"
  want="${CANONICAL}${path}"
  if [[ "${code}" == "301" && "${loc}" == "${want}" ]]; then
    echo "OK   ${path} -> ${loc}"
  else
    echo "FAIL ${path} -> code=${code} loc=${loc} (esperado 301 ${want})"
    fail=1
  fi
done

# Controle positivo: o destino tem de responder de verdade, nao so redirecionar.
final="$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 30 "${url}/verify/TESTE-123")"
if [[ "${final}" == "200" ]]; then
  echo "OK   destino final responde 200"
else
  echo "FAIL destino final respondeu ${final}"
  fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo
  echo "FALHOU. Rollback: repromover o deployment anterior no painel do Pages."
  exit 1
fi

echo
echo "PASS  ${url}"
[[ "${PROD}" -eq 1 ]] && echo "Confira tambem: https://nucleoia.pmigo.org.br/verify/TESTE-123"
exit 0
