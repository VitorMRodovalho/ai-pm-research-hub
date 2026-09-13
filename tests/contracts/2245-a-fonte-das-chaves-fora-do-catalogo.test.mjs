// tests/contracts/2245-a-fonte-das-chaves-fora-do-catalogo.test.mjs
// Register in the "test:behavioural" AND "test:contracts" whitelists in package.json (#1109).
// (DB-aware: as camadas B a D abrem conexao. Hermético iria para test:structural — guard do #1908.)
/**
 * #2245 — o catalogo de onboarding e obrigatorio, e a FONTE parou de semear fora dele.
 *
 * A HISTORIA QUE ESTE ARQUIVO EXISTE PARA IMPEDIR DE SE REPETIR:
 *
 *   02/09  a decisao 3 da #2131 apaga 145 linhas de 29 pessoas. Estado: ZERO chaves fora do catalogo.
 *   10/09  as duas primeiras pessoas aprovadas depois disso recriam o defeito inteiro: 10 linhas.
 *   13/09  a fonte e fechada, e a FK torna a classe impossivel.
 *
 * A migration de 02/09 nao foi descuidada — mediu antes, conferiu FK e triggers, afirmou a
 * pos-condicao, e ate escreveu "SE VOLTAR: join_whatsapp volta pelo CATALOGO". O que faltou foi
 * ALCANCE: ela tratou `onboarding_progress` como a coisa a limpar, quando aquilo era o EFEITO. A
 * fonte e um JSONB por ciclo (`selection_cycles.onboarding_steps`) que `approve_selection_application`
 * le sem validar contra o catalogo.
 *
 * POR ISSO A CAMADA QUE MAIS IMPORTA AQUI E A **C**, e nao a B. Um teste que so olhasse
 * `onboarding_progress` (o efeito) teria ficado VERDE em 03/09, VERDE em 09/09, e vermelho so em
 * 10/09 depois que duas pessoas reais ja tivessem sido afetadas. A camada C olha a FONTE, e teria
 * reprovado em 03/09 — antes de qualquer pessoa ser atingida.
 *
 * As camadas:
 *
 *   A (estatico)  a migration filtra pelo CATALOGO, nao por uma lista das cinco escrita a mao.
 *                 Uma lista literal envelhece: a sexta chave fora do catalogo passaria por ela.
 *   B (vivo)      zero linhas de `onboarding_progress` fora do catalogo — o EFEITO.
 *   C (vivo)      zero chaves fora do catalogo no JSONB de QUALQUER ciclo — a FONTE.
 *   D (vivo)      a FK existe de fato em `pg_constraint` — a ESTRUTURA, nao o arquivo que a declara.
 *
 * A distincao B/C/D e a mesma que a #2131 pagou: arquivo declara, dado mostra o efeito, e so o
 * catalogo do Postgres mostra se o portao esta realmente pendurado.
 *
 * Cross-ref: #2245, #2131 (a limpeza que voltou), #2132, #1875 (o "6 de 12"), #1997.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** A migration desta onda, achada pelo marcador `_2245_` — nao por caminho fixo (#2116). */
function migracaoDaOnda() {
  const f = readdirSync(MIGRATIONS).filter((x) => /_2245_/.test(x) && x.endsWith('.sql')).sort();
  assert.equal(f.length, 1, `esperava 1 migration de #2245, achei ${f.length}: ${JSON.stringify(f)}`);
  return maskLineComments(readFileSync(join(MIGRATIONS, f[0]), 'utf8'));
}

// ═══════════════════════════════════════════════════════════════════════════
test('#2245 A: a limpeza filtra pelo CATALOGO, nao por uma lista das cinco', () => {
  const sql = migracaoDaOnda();

  assert.match(sql, /UPDATE\s+public\.selection_cycles/i,
    'a migration deve tocar a FONTE (selection_cycles), nao so o efeito');
  assert.match(sql, /FROM\s+public\.onboarding_steps/i,
    'o filtro deve consultar o catalogo onboarding_steps');
  assert.match(sql, /ADD\s+CONSTRAINT\s+onboarding_progress_step_key_fkey[\s\S]{0,200}REFERENCES\s+public\.onboarding_steps/i,
    'a migration deve declarar a FK para o catalogo');

  // A INVERSA que importa: nenhuma das cinco chaves pode aparecer como LITERAL no SQL executavel.
  // Se aparecer, o conserto virou lista de nomes e a sexta chave escapa.
  for (const k of ['accept_terms', 'join_whatsapp', 'kick_off', 'platform_access', 'profile_complete']) {
    assert.doesNotMatch(sql, new RegExp(`'${k}'`),
      `a chave '${k}' aparece como literal no SQL: o conserto tem de ser derivado do catalogo, senao a PROXIMA chave fora do catalogo passa`);
  }
});

test('#2245 B (efeito): nenhuma linha de onboarding_progress fora do catalogo', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const c = sb();
  const { data: cat, error: e1 } = await c.from('onboarding_steps').select('id');
  assert.equal(e1, null, `catalogo: ${e1?.message}`);
  assert.ok((cat ?? []).length >= 5, `controle positivo: catalogo com ${(cat ?? []).length} passos`);

  const { data: rows, error: e2 } = await c.from('onboarding_progress').select('id, step_key, member_id').limit(5000);
  assert.equal(e2, null, `progresso: ${e2?.message}`);
  assert.ok((rows ?? []).length > 0, 'controle positivo: a tabela de progresso nao pode estar vazia');

  const ids = new Set((cat ?? []).map((s) => s.id));
  const fora = (rows ?? []).filter((r) => !ids.has(r.step_key));
  const porChave = {};
  for (const r of fora) porChave[r.step_key] = (porChave[r.step_key] ?? 0) + 1;

  assert.deepEqual(porChave, {}, [
    'Linha de onboarding_progress com step_key que o catalogo nao conhece.',
    '',
    'Sem rotulo e sem ordem, a trilha nao renderiza esses passos, ninguem consegue conclui-los, e',
    'eles contam contra a pessoa em qualquer leitura com denominador cru (#1875).',
    '',
    `Fora do catalogo: ${JSON.stringify(porChave)}`,
  ].join('\n'));
});

test('#2245 C (FONTE): nenhum ciclo semeia chave fora do catalogo — a camada que teria pego 10/09', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const c = sb();
  const { data: cat, error: e1 } = await c.from('onboarding_steps').select('id');
  assert.equal(e1, null, `catalogo: ${e1?.message}`);
  const ids = new Set((cat ?? []).map((s) => s.id));

  const { data: ciclos, error: e2 } = await c.from('selection_cycles').select('cycle_code, status, onboarding_steps');
  assert.equal(e2, null, `ciclos: ${e2?.message}`);
  assert.ok((ciclos ?? []).length > 0, 'controle positivo: nenhum ciclo lido');

  const violacoes = [];
  for (const ci of ciclos ?? []) {
    for (const step of Array.isArray(ci.onboarding_steps) ? ci.onboarding_steps : []) {
      const k = step?.key;
      if (k && !ids.has(k)) violacoes.push(`${ci.cycle_code}(${ci.status}): ${k}`);
    }
  }

  assert.deepEqual(violacoes.sort(), [], [
    'Ciclo com chave de onboarding fora do catalogo no proprio JSONB.',
    '',
    'ESTA e a camada que a #2131 nao teve. Ela apagou as LINHAS e deixou o JSONB intacto, entao',
    'um teste sobre `onboarding_progress` ficou verde por oito dias e so reprovou depois que as',
    'duas primeiras pessoas aprovadas recriaram o defeito. Limpar o efeito sem tocar a fonte faz o',
    'defeito voltar com data marcada.',
    '',
    `Violacoes: ${JSON.stringify(violacoes)}`,
  ].join('\n'));
});

test('#2245 D (estrutura): a FK MORDE — o INSERT fora do catalogo e recusado por ELA', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const c = sb();

  // ⚠️ PRECISA DE UM member_id REAL. A primeira versao desta camada usava um uuid zerado, e assim o
  // INSERT era recusado pela FK de `members` ANTES de chegar na de `step_key` — ou seja, passaria
  // identico com e sem a FK de #2245. Controle que nao podia dar outro resultado.
  const { data: membro, error: eM } = await c.from('members').select('id').limit(1).single();
  assert.equal(eM, null, `nao consegui um member_id real: ${eM?.message}`);

  const CHAVE = '__chave_que_o_catalogo_nao_conhece__';
  const { data: inserida, error } = await c
    .from('onboarding_progress')
    .insert({ member_id: membro.id, step_key: CHAVE, status: 'pending' })
    .select('id');

  if (!error) {
    // Nao deveria acontecer. Limpa o que entrou ANTES de reprovar, para o teste nao deixar residuo.
    const ids = (inserida ?? []).map((r) => r.id);
    if (ids.length) await c.from('onboarding_progress').delete().in('id', ids);
    assert.fail(
      'o INSERT com step_key fora do catalogo foi ACEITO: a FK de #2245 nao esta pendurada. '
      + `(${ids.length} linha(s) inserida(s) e removida(s) pelo proprio teste)`,
    );
  }

  // E recusado PELA FK certa, nao por outra restricao qualquer.
  const msg = String(error.message || '') + ' ' + String(error.details || '');
  assert.match(msg, /onboarding_progress_step_key_fkey|step_key/i,
    `recusado pelo motivo ERRADO — a asserção so vale se a recusa vier da FK de step_key: ${msg}`);
  assert.doesNotMatch(msg, /member_id_fkey/i,
    `recusado pela FK de members, nao pela de step_key: o controle nao discrimina. ${msg}`);
});
