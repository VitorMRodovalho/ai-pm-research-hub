// tests/contracts/2400b-externo-escreve-so-na-iniciativa-que-entrou.test.mjs
// Register in "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: este arquivo
// toca o banco, e o guard #1908 exige que DB-gated rode na faixa SERIALIZADA (#1509).
/**
 * Participante EXTERNO escreve no quadro da iniciativa em que entrou, e em NENHUM outro.
 *
 * O CASO: a diretoria do Student Club Brasília entra no workgroup do Hackathon para contribuir.
 * Eles não são voluntários do Núcleo (não assinaram o termo, que medido em 21/09/2026 é EXCLUSIVO
 * do `kind='volunteer'`: 117 de 124 com termo, e ZERO nos outros 13 kinds). Logo o vínculo é
 * `kind='observer'`, que é como a plataforma expressa "externo, não-voluntário" — e a ADR-0131
 * decidiu que externo é atributo do VÍNCULO, não da pessoa.
 *
 * ⚠️ A ASSERÇÃO QUE IMPORTA NÃO É "O PAR EXISTE". É O ESCOPO.
 * `organization` daria a um externo escrita em QUALQUER quadro da plataforma, inclusive os de
 * iniciativa confidencial (ADR-0105). A diferença entre `initiative` e `organization` é uma
 * palavra no seed e é a diferença entre convidar alguém para um quadro e dar a ele a plataforma
 * inteira. Por isso este arquivo afirma sobre o ESCOPO, e a asserção de existência vem junto só
 * para o seed não sumir em silêncio.
 *
 * A invariante é DERIVADA, não uma lista: **nenhuma** concessão de `write_board` a um kind externo
 * pode ter escopo `organization` ou `global`. Uma linha nova amanhã cai no guard sozinha.
 *
 * Cross-ref: #2400, ADR-0131, ADR-0105, V4_AUTHORITY_MODEL.md:158 (o checklist que confirmou o gap).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

/** Kinds que representam vínculo EXTERNO ao Núcleo (sem termo de voluntário). */
const KINDS_EXTERNOS = ['observer', 'external_reviewer', 'institutional_auditor', 'sponsor', 'speaker'];

/**
 * Violações. Lista vazia = saudável. Serve às linhas REAIS e às adulteradas, que é o que torna a
 * mutação significativa: uma mutação que só confirma que o dado mudou não prova que o guard reprova.
 */
function violacoes(linhas) {
  const v = [];
  for (const l of linhas) {
    if (!KINDS_EXTERNOS.includes(l.kind)) continue;
    if (l.action !== 'write_board') continue;
    if (l.scope !== 'initiative') {
      v.push(
        `${l.kind} x ${l.role} concede write_board com escopo "${l.scope}": um vínculo EXTERNO ` +
        'passaria a escrever em qualquer quadro da plataforma, inclusive de iniciativa ' +
        'confidencial (ADR-0105). Escopo de externo é sempre `initiative`.',
      );
    }
  }
  return v;
}

test('externo com write_board só pode ter escopo initiative',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb()
      .from('engagement_kind_permissions')
      .select('kind, role, action, scope')
      .eq('action', 'write_board');
    assert.ifError(error);

    // CONTROLE POSITIVO: um scanner que não acha nada passaria por vacuidade. Medido em
    // 22/09/2026: 22 combos concedem write_board.
    assert.ok((data ?? []).length >= 20,
      `esperava >= 20 combos de write_board, achei ${data?.length}: se caiu, o filtro deixou de ` +
      'casar e o guard virou decorativo. Conserte o scanner, não a asserção.');

    assert.deepEqual(violacoes(data), []);
  });

test('o par observer x participant existe e é escopado à iniciativa',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb()
      .from('engagement_kind_permissions')
      .select('kind, role, action, scope')
      .eq('kind', 'observer').eq('role', 'participant').eq('action', 'write_board');
    assert.ifError(error);
    assert.equal((data ?? []).length, 1,
      'o par observer x participant x write_board sumiu: um participante externo volta a entrar ' +
      'numa iniciativa sem conseguir contribuir no quadro dela');
    assert.equal(data[0].scope, 'initiative',
      `o par existe mas com escopo "${data[0].scope}"`);
  });

test('reprova o escopo organization num kind externo', () => {
  // Mutação sobre a MESMA função de violações que o teste real usa. Não toca produção.
  const reais = [
    { kind: 'observer', role: 'participant', action: 'write_board', scope: 'initiative' },
    { kind: 'workgroup_member', role: 'participant', action: 'write_board', scope: 'initiative' },
  ];
  assert.deepEqual(violacoes(reais), [], 'o conjunto de controle deveria estar limpo');

  const adulterado = reais.map((l) =>
    l.kind === 'observer' ? { ...l, scope: 'organization' } : l);
  assert.notEqual(adulterado[0].scope, reais[0].scope, 'a injeção precisa mesmo alterar a linha');

  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('qualquer quadro')),
    `esperava a violação do escopo, e veio: ${JSON.stringify(v)}`);
});

test('reprova também o escopo global, não só organization', () => {
  // `global` é o outro valor que o CHECK da tabela admite, e seria ainda mais amplo.
  const adulterado = [{ kind: 'observer', role: 'participant', action: 'write_board', scope: 'global' }];
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('"global"')),
    `esperava a violação do escopo global, e veio: ${JSON.stringify(v)}`);
});
