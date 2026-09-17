// tests/contracts/2296-decisao-por-badge-e-dado-nao-prosa.test.mjs
// Registrar nas whitelists "test:behavioural" E "test:contracts" do package.json (#1109).
// (DB-aware: as camadas C, D e E abrem conexão. A e B são estáticas.)
/**
 * #2296 item 3 — a decisão por badge vira DADO, e o detector para de repetir o já decidido.
 *
 * MEDIDO EM 16/09: `_credly_unmapped_rows()` listava 39 badges / 64 ocorrências, e os 39 estavam
 * em `badge`/10 POR DECISÃO. Dos 39, 17 já estavam afirmados um a um em guard; os outros 22 só
 * tinham uma frase de família em comentário. Com a tabela semeada, o detector caiu para 22/23.
 *
 * ⚠️ A CAMADA E É A QUE IMPORTA, e nasce de um erro documentado. A camada G do guard irmão conta
 * que em 15/09 uma recomendação chegou ao dono sem a regra do #1209 na tela, e ele aprovou algo
 * que uma decisão anterior já tinha negado. Dado e código agora afirmam a mesma coisa em dois
 * lugares — e dois lugares divergem em silêncio, salvo se alguém os confrontar. A camada E é esse
 * confronto: toda linha da tabela é exercitada contra o classificador VIVO.
 *
 * Camadas:
 *   A (estático) a migration cria a tabela com RLS ligada e revoga anon.
 *   B (estático) o detector consulta a tabela antes de listar (a mudança de comportamento).
 *   C (vivo)     toda `decided_category` existe em CATEGORY_POINTS — domínio derivado do
 *                classificador, não uma segunda lista que envelhece sozinha (#1149).
 *   D (vivo)     nenhum badge com decisão registrada aparece no detector (a pós-condição).
 *   E (vivo)     para cada decisão registrada, o CLASSIFICADOR concorda com ela. Dado e código
 *                não podem divergir em silêncio.
 *
 * Cross-ref: #2296, #1209, #1149, #1087.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { classifyBadge, CATEGORY_POINTS } from '../../supabase/functions/_shared/classify-badge.ts';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const TABELA = 'credly_badge_decisions';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** A migration que cria a tabela, procurada por CONTEÚDO — renomear o arquivo não pode deixar o
 *  guard verde por não encontrar nada. */
function migrationDaTabela() {
  const achados = readdirSync(MIGRATIONS)
    .filter(f => f.endsWith('.sql'))
    .sort()
    .map(f => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .filter(src => src.includes(`CREATE TABLE IF NOT EXISTS public.${TABELA}`));
  assert.ok(achados.length >= 1, `nenhuma migration cria public.${TABELA}`);
  return achados[achados.length - 1];
}

// ═══════════════════════════════════════════════════════════════════════════
test('A · a tabela nasce com RLS ligada e fora do alcance de anon', () => {
  const src = migrationDaTabela();
  assert.match(src, new RegExp(`ALTER TABLE public\\.${TABELA} ENABLE ROW LEVEL SECURITY`),
    'tabela nova SEM RLS viola a regra do repo (LGPD GC-162)');
  assert.match(src, new RegExp(`REVOKE ALL ON public\\.${TABELA} FROM anon`),
    'sem o REVOKE, a tabela herda o GRANT amplo que o Supabase dá por default — as tabelas irmãs ' +
    'gamification_rules e chapter_registry ficaram assim e dependem só da RLS');
  assert.match(src, /rls_can\('manage_platform'\)/,
    'a escrita tem de exigir manage_platform, como em gamification_rules');
});

test('B · o detector consulta a tabela antes de listar', () => {
  const achados = readdirSync(MIGRATIONS)
    .filter(f => f.endsWith('.sql')).sort()
    .map(f => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .filter(src => src.includes('CREATE OR REPLACE FUNCTION public._credly_unmapped_rows()'));
  assert.ok(achados.length >= 1, 'nenhuma migration define _credly_unmapped_rows');
  const src = achados[achados.length - 1];

  // ⚠️ MEDE O CORPO DA FUNÇÃO, não o arquivo. A primeira versão desta camada procurava
  // /NOT EXISTS[\s\S]{0,200}credly_badge_decisions/ no arquivo INTEIRO — e casava o
  // `CREATE TABLE IF NOT EXISTS public.credly_badge_decisions` do topo, que não tem nada a ver
  // com o filtro. Ela passava com o filtro invertido E com a tabela trocada por outra. Foi o
  // teste de mutação que expôs isso; sem ele a camada teria entrado no repo como decoração.
  const i = src.indexOf('CREATE OR REPLACE FUNCTION public._credly_unmapped_rows()');
  const resto = src.slice(i);
  const fim = resto.indexOf('$function$;');
  assert.ok(fim > 0, 'o corpo de _credly_unmapped_rows não fecha com $function$;');
  const corpo = resto.slice(0, fim);

  assert.ok(
    new RegExp(`NOT\\s+EXISTS[\\s\\S]{0,200}public\\.${TABELA}`).test(corpo),
    'o detector voltou a listar sem perguntar se a decisão já existe. Sem esse filtro ele repete ' +
    'mensalmente uma lista em que nada é novo, e um detector que não separa "novo" de "já ' +
    'decidido" ensina o leitor a ignorar a lista inteira.',
  );
});

// ═══════════════════════════════════════════════════════════════════════════
test('C · toda categoria decidida existe no classificador (domínio derivado, não copiado)',
  { skip: !dbGated && skipMsg }, async () => {
  const { data, error } = await sb().from(TABELA).select('badge_name, decided_category');
  assert.equal(error, null, `leitura falhou: ${error?.message}`);
  assert.ok(data.length > 0, 'a tabela está vazia: as camadas C/D/E ficariam verdes sem medir nada');
  const validas = Object.keys(CATEGORY_POINTS);
  for (const linha of data) {
    assert.ok(validas.includes(linha.decided_category),
      `'${linha.badge_name}' decidido como '${linha.decided_category}', que não existe em ` +
      `CATEGORY_POINTS (${validas.join(', ')}). Categoria nova exige linha em gamification_rules, ` +
      'senão o #1149 reprova por drift de preço.');
  }
});

test('D · o detector é EXATAMENTE o universo menos os decididos (diferença simétrica)',
  { skip: !dbGated && skipMsg }, async () => {
  const c = sb();

  // ⚠️ ESTA CAMADA FOI REESCRITA quando a fila zerou. A primeira versão afirmava "nenhum decidido
  // aparece no detector" e carregava um controle positivo exigindo detector NÃO-VAZIO — e o próprio
  // comentário dela previa o que aconteceu: registradas as 39 decisões, o detector ficou vazio e o
  // controle passou a reprovar sobre estado correto. Contagem e não-vazio eram os sinais errados.
  //
  // O sinal certo é DIFERENÇA SIMÉTRICA nos dois sentidos, que funciona com a fila cheia OU vazia:
  //   universo − decididos  deve ser exatamente o que o detector lista  (nada esquecido)
  //   decididos − universo  deve ser vazio                              (nenhuma decisão órfã)
  const { data: pontos, error: e0 } = await c
    .from('gamification_points').select('reason')
    .eq('category', 'badge').ilike('reason', 'Credly:%');
  assert.equal(e0, null, `leitura de gamification_points falhou: ${e0?.message}`);
  const universo = new Set(pontos.map(p => p.reason.replace(/^Credly:\s*/, '')));
  assert.ok(universo.size > 0,
    'nenhum lançamento Credly em `badge`: o universo está vazio e esta camada não mediria nada');

  const { data: decisoes, error: e1 } = await c.from(TABELA).select('badge_name');
  assert.equal(e1, null);
  const decididos = new Set(decisoes.map(d => d.badge_name));

  const { data: pendentes, error: e2 } = await c.rpc('_credly_unmapped_rows');
  assert.equal(e2, null, `_credly_unmapped_rows falhou: ${e2?.message}`);
  const listados = new Set(pendentes.map(p => p.badge_name));

  const esperado = [...universo].filter(n => !decididos.has(n)).sort();
  const obtido = [...listados].sort();
  assert.deepEqual(obtido, esperado,
    'o detector divergiu de (universo − decididos). Se sobrou nome que já tem decisão, o filtro ' +
    'parou de funcionar ou o nome divergiu do que a tabela guarda; se falta nome sem decisão, o ' +
    'detector ficou cego para badge novo — que é a razão de ele existir.');

  const orfas = [...decididos].filter(n => !universo.has(n));
  assert.deepEqual(orfas, [],
    `há decisão registrada para badge que não existe em gamification_points: ${orfas.join(', ')}. ` +
    'Ou o nome foi digitado errado (e a decisão nunca vai casar), ou o lançamento foi estornado.');
});

test('E · o classificador VIVO concorda com cada decisão registrada',
  { skip: !dbGated && skipMsg }, async () => {
  const { data, error } = await sb().from(TABELA).select('badge_name, decided_category, decision_source');
  assert.equal(error, null);
  const divergentes = [];
  for (const linha of data) {
    const real = classifyBadge(linha.badge_name, '').category;
    if (real !== linha.decided_category) {
      divergentes.push(`${linha.badge_name}: tabela diz '${linha.decided_category}', classificador diz '${real}'`);
    }
  }
  assert.deepEqual(divergentes, [],
    'dado e código divergiram sobre o mesmo badge:\n  ' + divergentes.join('\n  ') +
    '\nA decisão registrada e o comportamento do classificador têm de contar a mesma história. ' +
    'Se a mudança é intencional, mude os DOIS — nunca só um lado (é a lição da camada G da #2296).');
});
