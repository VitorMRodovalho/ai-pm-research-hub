/**
 * #2395b - uma ilha nao pode transformar "ainda nao carregou" em "nao existe".
 *
 * Origem (20/09/2026): a aba "Quadro" da pagina de iniciativa imprimia a string
 * `Supabase not available` sobre um board que existe e tem 14 cards. Uma sessao par relatou
 * ausencia de dado por causa disso, e o controle do projeto dela ficou fora da plataforma.
 *
 * Causa: `InitiativeBoardWrapper` lia `window.navGetSb()` UMA vez e desistia. `navGetSb` e
 * definido pela nav (`Nav.astro`), e as ilhas hidratam por conta propria, entao a primeira
 * leitura pode acontecer antes. O esperador canonico `waitForSb` (15 x 250ms) ja existia e e
 * exportado por `src/hooks/useBoard.ts`, o MESMO hook que o `BoardEngine` usa uma camada
 * abaixo: o componente morria antes de chegar na espera que estava logo ali.
 *
 * FORMA DA ASSERCAO: nao basta procurar a string `waitForSb` no arquivo, porque ela sobrevive
 * num import morto ou num comentario. Cada assercao recorta o bloco que decide e liga a
 * condicao ao resultado, e os comentarios sao mascarados antes de medir.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const R = (p) => { const f = join(__dirname, p); return existsSync(f) ? readFileSync(f, 'utf8') : ''; };

const WRAPPER = maskJsComments(R('../../src/components/initiatives/InitiativeBoardWrapper.tsx'));
const HOOK    = maskJsComments(R('../../src/hooks/useBoard.ts'));

test('#2395b o esperador canonico existe e e exportado', () => {
  assert.ok(HOOK.length > 0, 'src/hooks/useBoard.ts nao foi lido');
  assert.match(HOOK, /async function waitForSb\(/, 'waitForSb sumiu do hook');
  assert.match(HOOK, /export\s*\{[^}]*waitForSb[^}]*\}/,
    'waitForSb deixou de ser exportado: quem depende dele quebra em silencio');
});

test('#2395b o wrapper AGUARDA o cliente, em vez de ler uma vez', () => {
  assert.ok(WRAPPER.length > 0, 'InitiativeBoardWrapper.tsx nao foi lido');
  // condicao amarrada ao resultado: a atribuicao do cliente tem de ser um await do esperador.
  assert.match(WRAPPER, /const\s+sb\s*=\s*await\s+waitForSb\(/,
    'o wrapper voltou a resolver o cliente sem esperar; a aba imprime ausencia sobre board que existe');
  assert.match(WRAPPER, /import\s*\{[^}]*waitForSb[^}]*\}\s*from/,
    'waitForSb nao esta importado');
});

test('#2395b o wrapper NAO redefine um getSb de uma tentativa so', () => {
  assert.doesNotMatch(WRAPPER, /function\s+getSb\s*\(\s*\)\s*\{[^}]*navGetSb/,
    'voltou a existir um getSb local de uma leitura, que e exatamente o defeito');
});

test('#2395b nenhuma ilha declara ausencia do cliente sem ter esperado', () => {
  // Varre as ilhas e reprova quem tem erro TERMINAL de cliente ausente e nenhum sinal de espera.
  // O detector foi exercido nos dois sentidos: no arquivo pre-patch ele acusa, no pos-patch nao.
  const raiz = join(__dirname, '../../src/components');
  const arquivos = [];
  (function anda(d) {
    for (const nome of readdirSync(d)) {
      const f = join(d, nome);
      if (statSync(f).isDirectory()) anda(f);
      else if (/\.(tsx|ts)$/.test(nome)) arquivos.push(f);
    }
  })(raiz);
  assert.ok(arquivos.length > 50, `varredura rasa demais (${arquivos.length} arquivos): o teste passaria por vacuidade`);

  const ESPERA = /waitForSb|setTimeout|setInterval|retr|attempt|await new Promise|requestAnimationFrame/;
  const TERMINAL = /setError\((['"])Supabase not available/;

  const culpados = arquivos.filter((f) => {
    const src = readFileSync(f, 'utf8');
    if (!src.includes('navGetSb')) return false;
    return TERMINAL.test(src) && !ESPERA.test(src);
  }).map((f) => f.replace(raiz, 'src/components'));

  assert.deepEqual(culpados, [],
    'ilha que consome navGetSb, imprime "Supabase not available" e nao espera por ele: ' +
    'isso transforma corrida de carregamento em afirmacao de ausencia.');
});
