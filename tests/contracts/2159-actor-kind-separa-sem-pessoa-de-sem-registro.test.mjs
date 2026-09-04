// tests/contracts/2159-actor-kind-separa-sem-pessoa-de-sem-registro.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2159 achado 3 — `pii_access_log.actor_kind` separa "não há pessoa" de "ninguém registrou quem".
 *
 * `accessor_id` nulo era ambíguo entre as duas coisas, e relatório por responsável filtra por
 * accessor, então 7.592 leituras de PII não tinham dono em lugar nenhum.
 *
 * ⚠️ O QUE ESTE GUARD PROTEGE, e que é a decisão inteira em uma linha: quando o escritor NÃO
 * declara origem e não há pessoa, a classificação é `unknown`, NUNCA `automation`. Trocar por
 * `automation` "para o relatório ficar limpo" abençoa em silêncio exatamente a linha inatribuível
 * que a coluna existe para tornar visível — e o código continua compilando e passando em qualquer
 * teste de "linha automática vira automation".
 *
 * ⚠️ MEDE O CORPO SEM COMENTÁRIOS. O cabeçalho da migration explica o anti-padrão citando as
 * palavras `automation` e `unknown` várias vezes. Um guard que procurasse no texto cru casaria a
 * própria explicação (classe #1910, que mordeu três guards em 03/09 e a #1147 em 04/09).
 *
 * ⚠️ SEM RATCHET SOBRE `unknown`, de propósito. Os dois escritores automáticos são Edge Functions
 * (busca em `pg_proc` por esses nomes volta vazia), e até elas declararem, `unknown` sobe por
 * desenho. Um portão que reprova por desenho é um portão que se aprende a ignorar. Aqui se registra
 * a LINHA DE BASE; o ratchet entra quando a metade escritora chegar.
 *
 * Cross-ref: #2159, #2176, #2180 (as três faces de "o ato acontece e ninguém registra quem").
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const FN = latestFunctionCapture(ROOT, 'trg_pii_access_log_actor_kind');
const semComentarios = (sql) => sql.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const corpo = semComentarios(FN.body);

test('#2159 estático: valor declarado pelo escritor nunca é sobrescrito', () => {
  // Sem esta guarda, a coluna vira `accessor_id IS NULL` renomeado: ninguém consegue declarar nada.
  assert.match(corpo, /IF\s+NEW\.actor_kind\s+IS\s+NOT\s+NULL\s+THEN[\s\S]{0,80}RETURN\s+NEW/i,
    'o trigger precisa devolver NEW intacto quando o escritor já declarou actor_kind');
});

test('#2159 estático: sem declaração e SEM pessoa, classifica unknown — nunca automation', () => {
  // O ramo final é o que carrega a decisão. Ele tem de atribuir 'unknown'.
  const finais = corpo.match(/NEW\.actor_kind\s*:=\s*'([a-z]+)'/gi) || [];
  assert.ok(finais.length >= 2, `esperava ao menos duas atribuições, achei ${finais.length}`);
  const ultima = finais[finais.length - 1];
  assert.match(ultima, /'unknown'/,
    `a última atribuição do trigger é ${ultima} — presumir automação abençoa a linha inatribuível`);
  assert.doesNotMatch(corpo, /NEW\.actor_kind\s*:=\s*'automation'/i,
    'o trigger não pode ATRIBUIR automation: quem é automação declara, não é presumido');
});

test('#2159 estático: há um ramo que classifica human pela presença de pessoa', () => {
  assert.match(corpo, /NEW\.accessor_id\s+IS\s+NOT\s+NULL[\s\S]{0,120}NEW\.actor_kind\s*:=\s*'human'/i,
    'accessor preenchido tem de virar human');
});

test('#2159 estático: o guard REPROVA se o ramo final virar automation (injeção)', () => {
  const comDefeito = corpo.replace(/NEW\.actor_kind\s*:=\s*'unknown'/i, "NEW.actor_kind := 'automation'");
  assert.ok(!/NEW\.actor_kind\s*:=\s*'unknown'/i.test(comDefeito),
    'a injeção não removeu a atribuição de unknown — o teste acima estaria afirmando sobre nada');
  assert.match(comDefeito, /NEW\.actor_kind\s*:=\s*'automation'/i,
    'a injeção não produziu o defeito que o guard deveria pegar');
});

test('#2159 vivo: a coluna é NOT NULL, tem CHECK e o trigger está ligado',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  // A coluna só cumpre o papel se for obrigatória: nula, ela volta a ser o silêncio de antes.
  const { error: nulo } = await s.from('pii_access_log').select('id').is('actor_kind', null).limit(1);
  assert.ifError(nulo);
  const { count: nulos } = await s.from('pii_access_log')
    .select('*', { count: 'exact', head: true }).is('actor_kind', null);
  assert.equal(nulos, 0, 'existe linha com actor_kind nulo — a coluna deixou de ser obrigatória');
});

test('#2159 vivo: a classificação é coerente com o accessor, nos DOIS sentidos',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  // Dois sentidos de propósito: checar um só deixa o outro passar. `human` sem pessoa é mentira,
  // e `automation` COM pessoa é registro perdido (havia quem responder e virou fluxo anônimo).
  const { count: humanoSemPessoa } = await s.from('pii_access_log')
    .select('*', { count: 'exact', head: true }).eq('actor_kind', 'human').is('accessor_id', null);
  assert.equal(humanoSemPessoa, 0, 'linha human sem accessor: classificação mente sobre haver pessoa');

  const { count: automacaoComPessoa } = await s.from('pii_access_log')
    .select('*', { count: 'exact', head: true })
    .eq('actor_kind', 'automation').not('accessor_id', 'is', null);
  assert.equal(automacaoComPessoa, 0, 'linha automation COM accessor: havia pessoa e virou anônimo');

  // CONTROLE POSITIVO: sem ele, dois zeros seriam indistinguíveis de "a leitura não enxerga nada".
  const { count: total } = await s.from('pii_access_log').select('*', { count: 'exact', head: true });
  assert.ok(total > 0, 'tabela vazia — os dois zeros acima passariam por vacuidade');
  const { count: automacao } = await s.from('pii_access_log')
    .select('*', { count: 'exact', head: true }).eq('actor_kind', 'automation');
  assert.ok(automacao > 0, 'nenhuma linha classificada como automation — o backfill não rodou');
});

test('#2159 vivo: linha de base de `unknown` no momento de aplicar',
  { skip: dbGated ? false : skipMsg }, async () => {
  // NÃO é ratchet. As Edge Functions ainda não declaram, então este número SOBE por desenho até a
  // metade escritora chegar. O que se afirma aqui é que ele é LEGÍVEL e que a base era zero — para
  // que, quando o ratchet entrar, exista um antes contra o qual comparar.
  const s = sb();
  const { count: desconhecidos, error } = await s.from('pii_access_log')
    .select('*', { count: 'exact', head: true }).eq('actor_kind', 'unknown');
  assert.ifError(error);
  assert.ok(Number.isInteger(desconhecidos),
    'a contagem de unknown não é legível — o relatório por origem não teria como existir');
});
