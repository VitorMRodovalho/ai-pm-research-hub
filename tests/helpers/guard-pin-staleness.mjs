/**
 * Scanner compartilhado do #1932 — guards que fixam uma migration VENCIDA.
 *
 * O padrão dominante de guard estático neste repo é fixar um arquivo de migration e afirmar
 * propriedades sobre o texto dele:
 *
 *     const MIG = resolve(ROOT, 'supabase/migrations/20260805000130_p568_....sql');
 *     const body = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';
 *     assert.match(body, /IF NOT public\.can_by_member\(v_caller_id, 'view_pii'\) THEN/);
 *
 * Isso prova "a propriedade valia NAQUELA versão". Mas o guard se LÊ como "a propriedade vale".
 * Migration é história imutável: quando uma posterior redefine a mesma função, o arquivo fixado
 * não muda, e o guard segue VERDE descrevendo um corpo que a produção não executa mais. Se a
 * migration posterior tivesse AFROUXADO o portão, o guard teria ficado verde do mesmo jeito.
 *
 * Instância provada (#1932): `568-consent-records-lgpd-read.test.mjs` afirma o portão
 * `can_by_member(..., 'view_pii')` de `admin_list_member_consents` lendo a migration de 05/08,
 * enquanto a definição vigente (22/08) usa `can_org_by_member`.
 *
 * ⚠️ Fixar NÃO é errado por si. Para "esta migration entregou X", ler o arquivo dela é o teste
 * certo. O defeito é usar a mesma forma para afirmar INVARIANTE CORRENTE de segurança, LGPD ou
 * autoridade, onde a pergunta é "a função ainda faz X?" e não "a migration fez X?".
 *
 * Consumido por `tests/contracts/1932-guard-fixa-captura-vencida.test.mjs`.
 *
 * `latestFunctionCapture()` é a saída (1) da issue: o guard que afirma invariante CORRENTE resolve a
 * captura mais nova daquela função em vez de fixar um arquivo. Um guard que a usa para a função X
 * deixa de contar como dívida para X — o scanner reconhece a chamada e considera o par resolvido,
 * então converter um guard tira a linha da base sozinho, sem edição manual da lista.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

/**
 * Nome de função afirmado por um guard. Casa a forma de código SQL e a forma de literal de
 * regex, que é como quase todo guard escreve: `public\.nome_da_funcao\(`.
 * Os separadores aceitam tanto espaço real quanto o `\s+` escrito dentro do literal.
 */
const SEP = '\\s*(?:\\\\s\\+|\\s)*';
const ASSERT_RE = new RegExp(
  `CREATE${SEP}OR${SEP}REPLACE${SEP}FUNCTION${SEP}public\\s*\\\\?\\.\\s*([a-z_][a-z0-9_]*)`,
  'gi',
);

/**
 * Migration fixada dentro de um arquivo de teste. Captura só a VERSÃO.
 *
 * DUAS formas, porque só a primeira era óbvia e a segunda é invisível para ela:
 *
 *   a) caminho inteiro num literal   `'supabase/migrations/20260805000130_x.sql'`
 *   b) nome de arquivo SOZINHO       `resolve(MIGRATIONS_DIR, '20260805000023_x.sql')`
 *
 * A forma (b) aparece sempre que o diretório vira uma constante à parte, e nesses arquivos o único
 * casamento da forma (a) costuma ser a linha do cabeçalho JSDoc que DOCUMENTA a migration. Ou seja:
 * sem reconhecer (b), o guard lia o comentário e ignorava o código.
 */
const PIN_RE = /(?:supabase\/migrations\/|['"`])(\d{8,})_[A-Za-z0-9_.\-]*\.sql/g;

/**
 * Chamada que RESOLVE a dívida: `latestFunctionCapture(ROOT, 'nome_da_funcao')`. O par (guard, nome)
 * que aparece aqui lê a captura vigente, então não é dívida — mesmo que o arquivo siga fixando
 * outras migrations para afirmar entrega histórica.
 */
const RESOLVED_RE = /latestFunctionCapture\(\s*[^,)]+,\s*['"`]([a-z_][a-z0-9_]*)['"`]/g;

/** Cabeçalho de definição no lado das migrations. */
const DEF_RE = /\bCREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:"?public"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi;


/**
 * Neutraliza comentários de linha SQL (`-- ...`) PRESERVANDO offsets: cada caractere comentado vira
 * espaço, e as quebras de linha ficam. Assim a posição achada no texto mascarado indexa o texto
 * ORIGINAL sem conversão.
 *
 * Existe porque o preâmbulo de migration costuma DESCREVER o que a migration faz, e a descrição
 * contém o cabeçalho literal:
 *
 *     --   3. CREATE OR REPLACE FUNCTION public.lgpd_execute_retroactive_deletion(
 *
 * Sem mascarar, isso conta como definição: infla o catálogo, pode eleger a migration ERRADA como a
 * mais nova de uma função, e faz o detector de sobrecarga acusar duas assinaturas onde há uma.
 */
export function maskLineComments(sql) {
  return sql.replace(/--[^\n]*/g, (m) => ' '.repeat(m.length));
}


/**
 * Neutraliza comentário JS, preservando offsets. Necessário pelo mesmo motivo do lado SQL: o
 * cabeçalho JSDoc de um guard costuma DESCREVER a migration, e a descrição cita o cabeçalho
 * literal da função:
 *
 *     *   - CREATE OR REPLACE FUNCTION lgpd_execute_retroactive_deletion — PM
 *
 * Sem mascarar, o arquivo conta como se afirmasse a definição daquela função, quando não afirma
 * nada — nem em asserção aparece.
 *
 * Bloco `/* … *\/` é mascarado sempre. Linha `//` só quando abre a linha, porque um `//` no meio
 * da linha pode ser parte de um literal de regex (`/a\/b/`) e mascarar ali comeria código.
 */
export function maskJsComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/^([ \t]*)\/\/[^\n]*/gm, (m, indent) => indent + ' '.repeat(m.length - indent.length));
}

/**
 * Posições de nome que aparecem dentro de `assert.doesNotMatch(...)`. Ali o nome é afirmado como
 * AUSENTE — "esta migration não pode redefinir X" — que é entrega histórica legítima e o oposto de
 * depender da definição de X. Contar como dívida inverte o sentido da asserção.
 */
function dentroDeDoesNotMatch(src, idx) {
  const janela = src.lastIndexOf('assert.', idx);
  if (janela === -1) return false;
  return src.startsWith('assert.doesNotMatch', janela);
}

/**
 * Catálogo: nome de função → a migration MAIS NOVA que a (re)define.
 *
 * Derivado do diretório, nunca de lista de nomes escrita à mão: uma lista apodrece na primeira
 * função nova e o guard passa a medir um universo menor do que existe.
 */
export function buildNewestDefinitions(migrationsDir) {
  const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  const newest = new Map();

  for (const file of files) {
    const version = file.split('_')[0];
    const sql = maskLineComments(readFileSync(join(migrationsDir, file), 'utf8'));
    DEF_RE.lastIndex = 0;
    let m;
    while ((m = DEF_RE.exec(sql)) !== null) {
      const name = m[1].toLowerCase();
      const cur = newest.get(name);
      if (!cur || version > cur.version) newest.set(name, { version, file });
    }
  }

  return { newest, migrationFileCount: files.length };
}

/** Todo `*.test.mjs` sob um diretório, recursivo. */
function walkTests(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) walkTests(p, out);
    else if (entry.name.endsWith('.test.mjs')) out.push(p);
  }
  return out;
}

export const pairKey = (guard, fn) => `${guard}|${fn}`;

/**
 * Varre os guards e devolve os pares (guard, função) em que o guard NÃO fixa a migration que
 * carrega a definição mais nova daquela função.
 *
 * A pergunta é "o guard aponta para a captura mais nova?", e não "o guard fixa uma versão alta?".
 * As duas divergem: um arquivo pode fixar uma migration POSTERIOR à definidora sem fixar a
 * definidora, e nesse caso continua afirmando sobre texto que não é o vigente.
 *
 * @param {string} root        raiz do repo
 * @param {Set<string>} skip   caminhos relativos a ignorar (o próprio guard, p.ex.)
 * @param {{testsDir?:string, migrationsDir?:string}} dirs  sobrepõe os diretórios — existe para o
 *        CONTROLE POSITIVO poder rodar sobre um fixture sintético. Sem isso, a única prova de que a
 *        detecção funciona seria "ainda há dívida real no repo", que deixa de valer justamente
 *        quando o trabalho termina.
 */
export function scanStalePins(root, skip = new Set(), dirs = {}) {
  const migrationsDir = dirs.migrationsDir ?? join(root, 'supabase/migrations');
  const testsDir = dirs.testsDir ?? join(root, 'tests');
  const { newest, migrationFileCount } = buildNewestDefinitions(migrationsDir);

  let filesPinning = 0;
  // Quantos dos que fixam chegam a escrever um nome de função na forma que este scanner enxerga.
  // A diferença entre os dois é o PONTO CEGO declarado, e precisa ser medida em vez de estimada.
  let filesAsserting = 0;
  const pairs = [];
  const guards = new Set();

  for (const abs of walkTests(testsDir)) {
    const rel = relative(root, abs);
    if (skip.has(rel)) continue;

    const src = maskJsComments(readFileSync(abs, 'utf8'));
    PIN_RE.lastIndex = 0;
    const pins = new Set([...src.matchAll(PIN_RE)].map((m) => m[1]));
    if (pins.size === 0) continue;
    filesPinning += 1;

    ASSERT_RE.lastIndex = 0;
    const asserted = new Set(
      [...src.matchAll(ASSERT_RE)]
        .filter((m) => !dentroDeDoesNotMatch(src, m.index))
        .map((m) => m[1].toLowerCase()),
    );
    if (asserted.size > 0) filesAsserting += 1;

    RESOLVED_RE.lastIndex = 0;
    const resolved = new Set([...src.matchAll(RESOLVED_RE)].map((m) => m[1].toLowerCase()));

    for (const fn of asserted) {
      if (resolved.has(fn)) continue; // lê a captura vigente: não é dívida
      const def = newest.get(fn);
      if (!def) continue; // afirma função que nenhuma migration define: fora do escopo deste guard
      if (pins.has(def.version)) continue; // fixa a captura mais nova: em dia
      pairs.push({ guard: rel, fn, newestVersion: def.version, newestFile: def.file });
      guards.add(rel);
    }
  }

  pairs.sort((a, b) => pairKey(a.guard, a.fn).localeCompare(pairKey(b.guard, b.fn)));
  return { filesPinning, filesAsserting, pairs, guards, migrationFileCount, catalogSize: newest.size };
}

/** Lê a linha de base: uma entrada `guard|funcao` por linha, `#` é comentário. */
export function parseBaseline(text) {
  return text
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
}

/**
 * A captura VIGENTE de uma função: o último `CREATE [OR REPLACE] FUNCTION public.<name>` em ordem
 * cronológica de migration. É o que um guard de invariante corrente deve ler, no lugar de fixar um
 * arquivo (saída (1) do #1932).
 *
 * ⚠️ LANÇA em vez de devolver vazio. Um helper que devolvesse `''` para função inexistente ou
 * renomeada transformaria toda asserção do guard em `match('', ...)` — vermelho, tudo bem — mas
 * `doesNotMatch('', ...)` ficaria VERDE, e é justamente a forma das asserções de PII ("não vaza
 * hash", "não usa o campo errado"). Silêncio nessa direção é o defeito que o #1932 existe para pegar.
 *
 * @returns {{file:string, version:string, block:string, body:string}}
 */
export function latestFunctionCapture(root, name, migrationsDir = join(root, 'supabase/migrations')) {
  const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  const headerRe = new RegExp(
    `\\bCREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:"?public"?\\s*\\.\\s*)?"?${name}"?\\s*\\(`,
    'gi',
  );

  let hit = null;
  for (const file of files) {
    const original = readFileSync(join(migrationsDir, file), 'utf8');
    // Busca no texto mascarado, fatia no ORIGINAL: o mascaramento preserva offsets de propósito,
    // para o bloco devolvido conter os comentários que os guards às vezes afirmam.
    const sql = maskLineComments(original);
    headerRe.lastIndex = 0;
    const starts = [];
    let m;
    while ((m = headerRe.exec(sql)) !== null) starts.push(m.index);
    if (starts.length === 0) continue;

    // Sobrecarga: duas assinaturas na MESMA migration tornam "o último bloco" uma escolha cega, e a
    // escolha errada afirma sobre a função irmã. Nenhum alvo de hoje tem sobrecarga; se aparecer,
    // este helper precisa passar a casar por assinatura — reprovar é melhor que adivinhar.
    if (starts.length > 1) {
      const distintas = new Set(
        starts.map((i) => sql.slice(i, sql.indexOf(')', i) + 1).replace(/\s+/g, ' ')),
      );
      if (distintas.size > 1) {
        throw new Error(
          `latestFunctionCapture: ${name} tem ${distintas.size} assinaturas em ${file}. ` +
            'O helper resolve por NOME e não sabe escolher; case por assinatura antes de usar.',
        );
      }
    }

    const start = starts[starts.length - 1];
    const after = sql.slice(start);
    const as = after.match(/\bAS\s+(\$[a-zA-Z_]*\$)/);
    if (!as) continue;
    const openAt = as.index + as[0].length;
    const close = after.indexOf(as[1], openAt);
    if (close === -1) continue;
    const semi = after.indexOf(';', close + as[1].length);
    hit = {
      file,
      version: file.split('_')[0],
      block: original.slice(start, start + (semi === -1 ? close + as[1].length : semi + 1)),
      body: original.slice(start + openAt, start + close),
    };
  }

  if (!hit) {
    throw new Error(
      `latestFunctionCapture: nenhuma migration define public.${name}. ` +
        'Função renomeada/removida, ou o nome está errado no guard.',
    );
  }
  return hit;
}
