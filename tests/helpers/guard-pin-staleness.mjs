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

/** Caminho de migration fixado dentro de um arquivo de teste. Captura só a VERSÃO. */
const PIN_RE = /supabase\/migrations\/(\d{8,})_[A-Za-z0-9_.\-]*\.sql/g;

/** Cabeçalho de definição no lado das migrations. */
const DEF_RE = /\bCREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:"?public"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi;

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
    const sql = readFileSync(join(migrationsDir, file), 'utf8');
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
 */
export function scanStalePins(root, skip = new Set()) {
  const { newest, migrationFileCount } = buildNewestDefinitions(join(root, 'supabase/migrations'));

  let filesPinning = 0;
  // Quantos dos que fixam chegam a escrever um nome de função na forma que este scanner enxerga.
  // A diferença entre os dois é o PONTO CEGO declarado, e precisa ser medida em vez de estimada.
  let filesAsserting = 0;
  const pairs = [];
  const guards = new Set();

  for (const abs of walkTests(join(root, 'tests'))) {
    const rel = relative(root, abs);
    if (skip.has(rel)) continue;

    const src = readFileSync(abs, 'utf8');
    PIN_RE.lastIndex = 0;
    const pins = new Set([...src.matchAll(PIN_RE)].map((m) => m[1]));
    if (pins.size === 0) continue;
    filesPinning += 1;

    ASSERT_RE.lastIndex = 0;
    const asserted = new Set([...src.matchAll(ASSERT_RE)].map((m) => m[1].toLowerCase()));
    if (asserted.size > 0) filesAsserting += 1;

    for (const fn of asserted) {
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
