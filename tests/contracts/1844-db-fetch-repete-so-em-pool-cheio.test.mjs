/**
 * #1844 — o `dbFetch` repete APENAS em saturação de pool, e não esconde falha real.
 *
 * O risco de um helper de retentativa é virar tapete: se ele repetir qualquer erro, um defeito
 * de verdade passa a se apresentar como lentidão, e o CI deixa de ser sinal. Este guard fixa as
 * duas direções, porque só a primeira seria confortável e enganosa.
 *
 * O caso que motivou (medido em 17-18/08/2026): PostgREST devolve `PGRST003` com HTTP 504 quando
 * o pool está no teto — em repouso são 6 conexões ociosas, sob carga chegou a 15 ativas, e
 * `check_schema_invariants()` sozinho leva 2,53 s por chamada. Três PRs sem relação nenhuma
 * ficaram vermelhas por isso, e um teste ficou 61 s pendurado antes de devolver o 504.
 */

import { describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';
import { dbFetch, ehSaturacaoDePool, TENTATIVAS } from '../helpers/db-fetch.mjs';

const resposta = (status, corpo) =>
  new Response(corpo, { status, headers: { 'Content-Type': 'application/json' } });

const POOL_CHEIO = JSON.stringify({
  code: 'PGRST003', details: null, hint: null,
  message: 'Timed out acquiring connection from connection pool.',
});

describe('#1844 — dbFetch repete só em pool cheio', () => {
  it('reconhece PGRST003 em 504, e NÃO confunde com outro 504', async () => {
    assert.equal(await ehSaturacaoDePool(resposta(504, POOL_CHEIO)), true);
    assert.equal(await ehSaturacaoDePool(resposta(504, '{"message":"gateway timeout"}')), false,
      'um 504 que não é do pool não é retentável — repetir esconderia o defeito real');
    assert.equal(await ehSaturacaoDePool(resposta(500, POOL_CHEIO)), false,
      'só 503/504 são a forma da saturação; 500 com o mesmo texto é outra coisa');
  });

  it('repete quando o pool está cheio, e devolve o sucesso que vier depois', async (t) => {
    let chamadas = 0;
    const original = globalThis.fetch;
    globalThis.fetch = async () => {
      chamadas++;
      return chamadas === 1 ? resposta(504, POOL_CHEIO) : resposta(200, '[]');
    };
    t.after(() => { globalThis.fetch = original; });

    const res = await dbFetch('http://exemplo/rpc/x', { method: 'POST' });
    assert.equal(res.status, 200, 'a segunda tentativa deveria ter passado');
    assert.equal(chamadas, 2, 'uma repetição basta quando a segunda responde');
  });

  it('NÃO repete erro que não é do pool — 400 sai na primeira', async (t) => {
    let chamadas = 0;
    const original = globalThis.fetch;
    globalThis.fetch = async () => { chamadas++; return resposta(400, '{"message":"bad request"}'); };
    t.after(() => { globalThis.fetch = original; });

    const res = await dbFetch('http://exemplo/rpc/x', { method: 'POST' });
    assert.equal(res.status, 400);
    assert.equal(chamadas, 1,
      'repetir um 400 transformaria defeito determinístico em lentidão, e o CI deixaria de ser sinal');
  });

  it('pool cheio PERSISTENTE continua vermelho — o helper não engole', async (t) => {
    let chamadas = 0;
    const original = globalThis.fetch;
    globalThis.fetch = async () => { chamadas++; return resposta(504, POOL_CHEIO); };
    t.after(() => { globalThis.fetch = original; });

    const res = await dbFetch('http://exemplo/rpc/x', { method: 'POST' });
    assert.equal(res.status, 504, 'esgotadas as tentativas, a última recusa é devolvida');
    assert.equal(chamadas, TENTATIVAS, `deveria tentar ${TENTATIVAS} vezes e parar`);
  });

  it('toda chamada leva limite de espera — sem isso a saturação vira trava de 95 min', async (t) => {
    let recebido = null;
    const original = globalThis.fetch;
    globalThis.fetch = async (_url, opts) => { recebido = opts; return resposta(200, '[]'); };
    t.after(() => { globalThis.fetch = original; });

    await dbFetch('http://exemplo/rpc/x', { method: 'POST' });
    assert.ok(recebido?.signal, 'o fetch precisa receber um AbortSignal');
    assert.equal(typeof recebido.signal.aborted, 'boolean');
  });
});
