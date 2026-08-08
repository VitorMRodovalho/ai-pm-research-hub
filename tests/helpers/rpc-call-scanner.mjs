// tests/helpers/rpc-call-scanner.mjs
//
// #1636 — distinguir CHAMAR uma RPC de MENCIONÁ-LA.
//
// Sete arquivos da suíte contêm a string `sb.rpc('selection_rescue_stuck_interview'` dentro de um
// literal, porque inspecionam o código do admin e do MCP procurando exatamente por ela. Um guard
// baseado em grep acusaria todos, e um guard que fica vermelho em trabalho correto é desligado na
// terceira vez (a mesma armadilha do guard que persegue captura hardcoded, #1682/#569).
//
// Daí o scanner: varre caractere a caractere, pula comentários, literais de string e literais de
// regex, e só então procura `.rpc(` seguido do nome. Regex PRECISA ser tratada: `/…'P0001'…/` tem
// aspas soltas que jogariam o scanner em modo string e o fariam perder o resto do arquivo — que é
// como ele falha em silêncio, achando MENOS do que existe.

/**
 * O caractere anterior significativo decide se `/` abre uma regex ou é divisão. Depois de um
 * identificador, número, `)` ou `]`, é divisão; em qualquer outro contexto, regex. É a heurística
 * padrão, e basta aqui porque o alvo é código de teste, não JS arbitrário.
 */
function podeSerRegex(anterior) {
  if (anterior === undefined) return true;
  return !/[\w$)\]]/.test(anterior);
}

/**
 * Nomes de RPC efetivamente INVOCADOS em `src` (`.rpc('nome'` fora de string/comentário/regex).
 *
 * @param {string} src código-fonte JavaScript
 * @returns {Set<string>}
 */
export function rpcCallsIn(src) {
  const nomes = new Set();
  let i = 0;
  let anterior;   // último caractere de código visto, para decidir regex vs divisão

  while (i < src.length) {
    const c = src[i];

    if (c === '/' && src[i + 1] === '/') {
      const nl = src.indexOf('\n', i);
      i = nl === -1 ? src.length : nl + 1;
      continue;
    }
    if (c === '/' && src[i + 1] === '*') {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? src.length : end + 2;
      continue;
    }
    if (c === '/' && podeSerRegex(anterior)) {
      // corpo da regex: `\` escapa, `[...]` é classe (onde `/` não fecha nada)
      i += 1;
      let emClasse = false;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === '[') emClasse = true;
        else if (src[i] === ']') emClasse = false;
        else if (src[i] === '/' && !emClasse) { i += 1; break; }
        else if (src[i] === '\n') break;   // regex não atravessa linha: era divisão, desiste
        i += 1;
      }
      while (i < src.length && /[a-z]/.test(src[i])) i += 1;   // flags
      anterior = '/';
      continue;
    }
    if (c === "'" || c === '"' || c === '`') {
      i += 1;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === c) { i += 1; break; }
        i += 1;
      }
      anterior = c;
      continue;
    }

    if (src.startsWith('.rpc(', i)) {
      let j = i + 5;
      while (j < src.length && /\s/.test(src[j])) j += 1;
      const q = src[j];
      if (q === "'" || q === '"' || q === '`') {
        const fim = src.indexOf(q, j + 1);
        if (fim > j) nomes.add(src.slice(j + 1, fim));
      }
      i += 5;
      anterior = '(';
      continue;
    }

    if (!/\s/.test(c)) anterior = c;
    i += 1;
  }
  return nomes;
}
