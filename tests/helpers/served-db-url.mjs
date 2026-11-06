/**
 * #2974: qual banco o `astro dev` de um harness de teste SERVE de fato.
 *
 * O @astrojs/cloudflare, ao subir, escreve em process.env as [vars] do wrangler.toml mescladas com o .dev.vars ou o
 * .env (loadWranglerEnv), sem olhar o que o processo já trazia. O wrangler.toml tem o PUBLIC_SUPABASE_URL do projeto
 * de produção, então um PUBLIC_SUPABASE_URL falso no ambiente do passo não chega à página: a página carrega o de
 * produção, e o navegador e o SSR do teste falam com ele. Quem muda o valor servido é o .dev.vars, que, quando existe,
 * também faz o .env ser ignorado.
 *
 * Por isso a guarda não afirma sobre o ambiente, e sim sobre o valor que o dev server serve. Ela lê o módulo do
 * cliente que o Vite transforma (CAMINHO_SEM_SSR), que não passa pelo SSR e não toca o banco, ANTES de qualquer
 * página: a página inicial faz o SSR do BaseLayout, que já lê o banco.
 *
 * Três estados. Local (127.0.0.1 ou localhost) segue. Outro host recusa. Sem valor legível também recusa, porque um
 * PUBLIC_SUPABASE_URL vazio faz o cliente cair no fallback de produção de src/lib/supabase.ts. Quem recusa sai com
 * SAIDA_NAO_MEDIDO, e o retry do CI não repete a tentativa: a configuração não muda entre uma e outra.
 *
 * Este módulo só DECIDE. Quem mata o servidor e sai é o harness.
 */

/** Módulo do cliente transformado pelo Vite: traz o import.meta.env servido e não passa pelo SSR. */
export const CAMINHO_SEM_SSR = '/src/lib/supabase.ts';
/** Código de saída de quem recusa por não poder afirmar que o banco é local. */
export const SAIDA_NAO_MEDIDO = 3;

export const LOCAL = 'local';
export const NAO_LOCAL = 'nao-local';
export const ILEGIVEL = 'ilegivel';

const HOSTS_LOCAIS = new Set(['127.0.0.1', 'localhost']);

// O Vite serve `import.meta.env = {..., "PUBLIC_SUPABASE_URL": "<valor>", ...}` na primeira linha do módulo, e o
// define:vars do Nav serve `const NAV_PUBLIC_SUPABASE_URL = "<valor>";`. Os dois valores saem de JSON.stringify.
const NO_MODULO = /"PUBLIC_SUPABASE_URL"\s*:\s*("(?:[^"\\]|\\.)*")/g;
const NO_SSR = /\bNAV_PUBLIC_SUPABASE_URL\s*=\s*("(?:[^"\\]|\\.)*")/g;

function valorUnico(texto, re, onde) {
  const achados = [...String(texto ?? '').matchAll(re)];
  if (achados.length !== 1) {
    return { erro: `${onde} tem ${achados.length} ocorrência(s) de PUBLIC_SUPABASE_URL, e a guarda espera exatamente 1` };
  }
  return { valor: JSON.parse(achados[0][1]) };
}

/** Decide sobre um valor de PUBLIC_SUPABASE_URL. O host sai de `new URL`, nunca de prefixo de texto. */
export function avaliarUrl(valor) {
  const v = typeof valor === 'string' ? valor.trim() : '';
  if (!v) {
    return { estado: ILEGIVEL, motivo: 'PUBLIC_SUPABASE_URL servido está vazio, e o cliente cai no fallback de produção de src/lib/supabase.ts' };
  }
  let host;
  try {
    host = new URL(v).hostname;
  } catch {
    return { estado: ILEGIVEL, motivo: `PUBLIC_SUPABASE_URL servido não é uma URL (${v})` };
  }
  if (HOSTS_LOCAIS.has(host)) return { estado: LOCAL, valor: v, host };
  return { estado: NAO_LOCAL, valor: v, host, motivo: `o dev server serve PUBLIC_SUPABASE_URL em ${host}, que não é local` };
}

/** Decide sobre o texto do módulo servido em CAMINHO_SEM_SSR. */
export function avaliarModuloCliente(texto) {
  const lido = valorUnico(texto, NO_MODULO, `o módulo servido em ${CAMINHO_SEM_SSR}`);
  if (lido.erro) return { estado: ILEGIVEL, motivo: lido.erro };
  return avaliarUrl(lido.valor);
}

/** Confere o define:vars do SSR de uma página contra o valor que o cliente recebeu. */
export function conferirSsr(html, valorDoCliente) {
  const lido = valorUnico(html, NO_SSR, 'o HTML da página');
  if (lido.erro) return { estado: ILEGIVEL, motivo: lido.erro };
  const v = typeof lido.valor === 'string' ? lido.valor.trim() : '';
  if (v !== valorDoCliente) {
    return { estado: ILEGIVEL, motivo: `o SSR serve PUBLIC_SUPABASE_URL ${v || '(vazio)'}, e o cliente recebeu ${valorDoCliente}` };
  }
  return avaliarUrl(v);
}

export function mensagemNaoMedido(quem, avaliacao) {
  return (
    `${quem}: não medido: ${avaliacao.motivo}. Nenhuma página foi aberta. ` +
    'O valor servido vem do wrangler.toml, do .dev.vars ou do .env, nunca do ambiente do processo: ' +
    'ponha um .dev.vars com a URL e a chave falsas, como faz o .github/workflows/ci.yml.'
  );
}
