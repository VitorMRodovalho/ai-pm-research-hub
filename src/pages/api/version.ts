/**
 * #2255 — a rota que responde "qual commit esta publicado aqui".
 *
 * POR QUE ELA EXISTE. A A3 fez o deploy depender do `CI Validate` por `workflow_run`. Quando o
 * `CI Validate` nao fecha verde, o run do Deploy termina como **`skipped`** — e `skipped` nao e
 * vermelho em lugar nenhum: nao falha check, nao abre issue, nao aparece em varredura que procure
 * `failure`. Medido em 13/09/2026: 9 SHAs da `main` tiveram skip e nunca um success, e 5 dos ultimos
 * 12 `CI Validate` da main falharam (todos por `browser_guards`, que e a #2231).
 *
 * A outra metade do problema era esta: **nao havia como perguntar a producao qual commit ela roda.**
 * O `deploy.yml` nao carimbava SHA nenhum e nao existia rota de versao. Entao o atraso era invisivel
 * nas DUAS pontas, e descobri-lo exigiu cruzar o historico de runs do Deploy a mao.
 *
 * O QUE ESTA ROTA TORNA POSSIVEL: "producao esta atras da main?" vira uma requisicao, e o cron de
 * heartbeat (`ci-heartbeat-monitor.yml`, job `monitor_deploy_lag`) passa a responder isso sozinho.
 *
 * O VALOR E DE BUILD, NAO DE RUNTIME. `import.meta.env.PUBLIC_RELEASE_SHA` e substituido pelo Vite no
 * momento do build, entao o que esta rota devolve e o commit de que este bundle foi construido — que
 * e exatamente a pergunta. Um valor lido do ambiente do Worker em runtime responderia outra coisa
 * (o que o ambiente diz hoje), e poderia divergir do codigo que esta servindo.
 *
 * `stamped: false` significa "este build nao recebeu o carimbo" (build local, ou deploy anterior a
 * esta mudanca). E DIFERENTE de "nao consegui ler", e quem consome tem de tratar os dois separados:
 * confundi-los faz uma falha de rede parecer recuperacao. Ver o job do heartbeat.
 */
import type { APIRoute } from 'astro';

export const prerender = false;

// Substituidos no BUILD. Ver o bloco `env:` do passo `npm run build` em `.github/workflows/deploy.yml`.
const sha = import.meta.env.PUBLIC_RELEASE_SHA || '';
const builtAt = import.meta.env.PUBLIC_RELEASE_BUILT_AT || '';
const runId = import.meta.env.PUBLIC_RELEASE_RUN_ID || '';

export const GET: APIRoute = async () => {
  return new Response(
    JSON.stringify({
      stamped: Boolean(sha),
      sha: sha || null,
      short_sha: sha ? sha.slice(0, 8) : null,
      built_at: builtAt || null,
      // O run do Deploy que publicou, para ir do sintoma ao log em um clique.
      deploy_run_id: runId || null,
    }),
    {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        // OBRIGATORIO. Uma resposta cacheada devolveria o SHA do build ANTERIOR, que e precisamente
        // o defeito que esta rota existe para detectar: o detector leria "em dia" durante todo o
        // periodo em que a producao estivesse atrasada. O guard de contrato afirma este header.
        'Cache-Control': 'no-store, no-cache, must-revalidate',
      },
    },
  );
};
