#!/usr/bin/env bash
# browser_guards com retry E diagnostico que chega ao RESUMO do job.
#
# POR QUE A INSTRUMENTACAO (#2343, 17/09/2026). Este job e `required` e falhou 10 vezes em um dia.
# Como ele ja tentava 2x internamente, cada "falha" do CI representa **duas** tentativas perdidas —
# o que derruba a leitura de "flake que o retry conserta". Padrao medido no mesmo dia:
#
#   3 PRs que mexem SO em documentacao   3 execucoes cada, 2-3 falhas cada
#   2 PRs que mexem em codigo de verdade 1 execucao cada, ZERO falhas
#
# Isso e o inverso do que uma leitura por conteudo prediria, e aponta para causa ambiental. A raiz
# no log e sempre a mesma (`Unable to resolve .../BaseLayout.astro` no workerd, mais timeout),
# variando so a pagina.
#
# O diagnostico ja existia no log bruto e NAO chegava ao resumo — classe do #1910, em que uma lane
# reprovou 4x sem ninguem ver o texto que nomeava a causa. Este script passa a escrever no
# `$GITHUB_STEP_SUMMARY` o numero de tentativas e a ASSINATURA classificada, para que a fase 2 da
# investigacao tenha dado em vez de impressao.
#
# ⚠️ De proposito, mexe em UM fator so: instrumentacao. O cooldown de 5s segue como estava — mudar
# retry e medicao juntos impediria atribuir a melhora (ou a piora) a qualquer um dos dois.
#
# FASE 2 (26/09/2026): o retry passa a partir do estado de um JOB NOVO. Medido em dois runs da main
# (36194865818 e 36191415317): a tentativa 2 subia em ~5,5 s contra ~11 s da 1, SEM nenhuma linha do
# otimizador de dependencias do Vite, e falhava com a MESMA assinatura. Um re-run do job, que parte
# de `npm ci` sem esses diretorios, passava. A 2 herdava o estado de runtime que a 1 deixou:
# `node_modules/.vite` (deps, deps_ssr, deps_astro) e `.wrangler` (state e tmp do workerd). Um fator
# so, de novo: apagar esse estado antes do retry. A instrumentacao da fase 1 fica como estava.
set -uo pipefail

attempt=1
max_attempts=2
log_dir="${RUNNER_TEMP:-/tmp}"
assinaturas=""

classificar() {
  local log="$1"
  local achou=""
  grep -qF 'Unable to resolve' "$log" 2>/dev/null && grep -qF 'BaseLayout.astro' "$log" 2>/dev/null \
    && achou="${achou}workerd-nao-resolve-BaseLayout "
  grep -qE 'workerd/jsg.*failed' "$log" 2>/dev/null && achou="${achou}workerd-jsg-throw "
  grep -qE 'Timeout [0-9]+ms exceeded' "$log" 2>/dev/null && achou="${achou}timeout-playwright "
  grep -qE 'ECONNREFUSED|EADDRINUSE' "$log" 2>/dev/null && achou="${achou}porta-ou-conexao "
  # Tres estados: sem assinatura conhecida NAO e "sem problema", e "nao classificada".
  [ -z "$achou" ] && achou="assinatura-NAO-classificada "
  printf '%s' "$achou"
}

# Estado de runtime que a tentativa anterior deixa e que um job novo nao tem (ambos no .gitignore).
limpar_estado_de_runtime() {
  local vite wrangler
  vite=$(find node_modules/.vite -type f 2>/dev/null | wc -l)
  wrangler=$(find .wrangler -type f 2>/dev/null | wc -l)
  rm -rf node_modules/.vite .wrangler
  echo "[browser-guards] estado de runtime apagado antes do retry: node_modules/.vite=${vite} arquivos, .wrangler=${wrangler} arquivos"
}

paginas_citadas() {
  grep -oE '/[a-z0-9-]+ [0-9]+ms' "$1" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' '
}

while [ "$attempt" -le "$max_attempts" ]; do
  log="${log_dir}/browser-guards-attempt-${attempt}.log"
  echo "[browser-guards] attempt ${attempt}/${max_attempts}"
  # `pipefail` garante que o status vem do npm, nao do tee.
  if npm run test:browser:guards 2>&1 | tee "$log"; then
    echo "[browser-guards] success on attempt ${attempt}"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      {
        echo "### browser_guards: verde na tentativa ${attempt} de ${max_attempts}"
        [ "$attempt" -gt 1 ] && echo "⚠️ Precisou de retry — a tentativa 1 falhou com: \`$(classificar "${log_dir}/browser-guards-attempt-1.log")\`, e a ${attempt} passou partindo de estado limpo (fase 2). Conta para a estatistica do #2343."
      } >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
  fi
  sig="$(classificar "$log")"
  assinaturas="${assinaturas}tentativa ${attempt}: ${sig}| "
  echo "[browser-guards] attempt ${attempt} FALHOU — assinatura: ${sig}"
  if [ "$attempt" -lt "$max_attempts" ]; then
    echo "[browser-guards] retrying after short cooldown..."
    sleep 5
    limpar_estado_de_runtime
  fi
  attempt=$((attempt + 1))
done

echo "[browser-guards] failed after ${max_attempts} attempts"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### browser_guards REPROVOU nas ${max_attempts} tentativas"
    echo
    echo "**Assinaturas classificadas:** \`${assinaturas}\`"
    echo
    echo "**Paginas citadas no log:** \`$(paginas_citadas "${log_dir}/browser-guards-attempt-${max_attempts}.log")\`"
    echo
    echo "Se a assinatura for \`workerd-nao-resolve-BaseLayout\`, este e o flake conhecido do **#2343**"
    echo "— 10 falhas em 17/09, quase todas em PR que so mexe em documentacao, e o job ja tenta 2x"
    echo "internamente. **Nao e o seu diff.** Re-rode e registre a ocorrencia na #2343."
    echo
    echo "Se a assinatura for \`assinatura-NAO-classificada\`, e falha NOVA: leia o log do artefato"
    echo "antes de re-rodar, e acrescente a assinatura em \`scripts/run_browser_guards_with_retry.sh\`."
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit 1
