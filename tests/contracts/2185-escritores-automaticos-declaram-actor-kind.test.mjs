// tests/contracts/2185-escritores-automaticos-declaram-actor-kind.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2185 — os três escritores automáticos de `pii_access_log` DECLARAM `actor_kind = 'automation'`.
 *
 * A metade receptora (#2159) criou a coluna e o trigger que classifica quem não declara. Esta afirma
 * a outra ponta: enquanto os escritores não declararem, tudo que eles gravam cai em `unknown`, e
 * `unknown` deixa de significar "alguém escreveu sem dizer de onde" para significar "o caminho de
 * sempre". A coluna perderia o sentido no dia seguinte ao de ter sido criada.
 *
 * ⚠️ A DECLARAÇÃO É VERDADEIRA POR CONSTRUÇÃO, e é isso que este guard protege. As três funções
 * começam com `IF current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE`. Não existe
 * caminho em que uma pessoa autenticada as execute. Se alguém relaxar essa guarda, `'automation'`
 * vira mentira — daí o teste que exige a guarda de papel junto da declaração.
 *
 * ⚠️ `accessor_id` CONTINUA NULL, de propósito. A coluna não substitui o nulo, ela o explica:
 * nulo + `automation` lê "não há pessoa"; nulo + `unknown` lê "ninguém registrou quem foi". Eram o
 * mesmo silêncio até a #2159. Um "conserto" que preenchesse `accessor_id` com um ator sintético
 * esbarraria no guard #1437 e é o caminho explicitamente rejeitado no docket de 04/09.
 *
 * ⚠️ O RATCHET VIVO ESTÁ ATRÁS DE `skipDataInvariant` (A2). Ele é função do estado do banco, não do
 * diff: um caminho novo escrevendo sem declarar sobe o contador, e o autor da PR que reprovar por
 * isso não tem como consertá-lo. Portão required que o autor não consegue acionar é pedágio, e a
 * resposta racional a pedágio é o bypass.
 *
 * Cross-ref: #2185, #2159 (a metade receptora), #2176 e #2180 (as outras faces do mesmo buraco).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { skipDataInvariant } from '../helpers/data-invariant-gate.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } })
  : null;

/** Captura mais nova de cada função, por varredura ordenada das migrations (#1932). */
function capturaMaisNova(assinatura) {
  const dir = resolve(ROOT, 'supabase/migrations');
  const arq = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()
    .filter((f) => readFileSync(resolve(dir, f), 'utf8').includes(assinatura)).pop();
  assert.ok(arq, `nenhuma migration captura ${assinatura}`);
  const txt = readFileSync(resolve(dir, arq), 'utf8');
  const i = txt.indexOf(assinatura);
  const fim = txt.indexOf('$function$;', i);
  return { arquivo: arq, corpo: txt.slice(i, fim > i ? fim : undefined) };
}

const ESCRITORES = [
  ['get_initiative_drive_roster(p_initiative_id uuid)', 'reconcile_initiative_drive_access'],
  ['get_offboarded_member_emails()', 'audit_drive_offboarding_access'],
  ['get_offboarded_member_emails(p_member_id uuid)', 'audit_drive_offboarding_access'],
];

for (const [assinatura, contexto] of ESCRITORES) {
  test(`#2185 estático: ${assinatura} declara actor_kind na escrita`, () => {
    const { corpo } = capturaMaisNova(`FUNCTION public.${assinatura}`);
    assert.match(corpo, /INSERT INTO public\.pii_access_log[^;]*actor_kind/s,
      'a lista de colunas do INSERT não inclui actor_kind: a linha cairia em unknown pelo trigger');
    assert.match(corpo, /'automation'/,
      `${assinatura} não declara 'automation' — o valor teria de vir do trigger, que classifica unknown`);
    assert.ok(corpo.includes(contexto), `o contexto ${contexto} sumiu do INSERT`);
  });

  test(`#2185 estático: ${assinatura} mantém a guarda de service_role`, () => {
    // Sem esta guarda, uma pessoa autenticada poderia executar a função e 'automation' viraria
    // mentira: haveria pessoa, e o log diria que não havia.
    const { corpo } = capturaMaisNova(`FUNCTION public.${assinatura}`);
    assert.match(corpo, /current_caller_role\(\)\s+IS\s+DISTINCT\s+FROM\s+'service_role'/,
      'a guarda de papel sumiu: a declaração de automation deixa de ser verdadeira por construção');
  });

  test(`#2185 estático: ${assinatura} continua gravando accessor_id NULL`, () => {
    // A coluna EXPLICA o nulo, não o substitui. Preencher accessor com ator sintético foi
    // explicitamente rejeitado (esbarra no guard #1437, que caça linha sintética alcançável).
    const { corpo } = capturaMaisNova(`FUNCTION public.${assinatura}`);
    assert.match(corpo, /SELECT\s+NULL,\s*mid,/,
      'o accessor deixou de ser NULL: se virou ator sintético, isso é decisão de produto, não refactor');
  });
}

test('#2185 estático: o guard REPROVA se a declaração for removida (injeção)', () => {
  // Sem provar que a injeção produz o defeito E que o teste roda, exit 0 não significa nada.
  const { corpo } = capturaMaisNova('FUNCTION public.get_initiative_drive_roster(p_initiative_id uuid)');
  const comDefeito = corpo
    .replace(/,\s*actor_kind\)/, ')')
    .replace(/,\s*'automation'\n/, '\n');
  assert.doesNotMatch(comDefeito, /INSERT INTO public\.pii_access_log[^;]*actor_kind/s,
    'a injeção não removeu actor_kind da lista de colunas — o teste acima afirmaria sobre nada');
});

test('#2185 vivo: nenhuma linha ficou em unknown (ratchet)',
  { skip: skipDataInvariant(!!sb, 'sem SUPABASE_URL + SERVICE_ROLE_KEY') }, async () => {
  const { count: desconhecidos, error } = await sb.from('pii_access_log')
    .select('*', { count: 'exact', head: true }).eq('actor_kind', 'unknown');
  assert.ifError(error);

  // CONTROLE POSITIVO: sem ele, "0 unknown" é indistinguível de "a leitura não enxerga nada".
  const { count: automacao } = await sb.from('pii_access_log')
    .select('*', { count: 'exact', head: true }).eq('actor_kind', 'automation');
  assert.ok(automacao > 0, 'nenhuma linha automation — a leitura não está enxergando a coluna');

  assert.equal(desconhecidos, 0,
    `${desconhecidos} linhas de PII escritas sem declarar origem (esperado 0). ` +
    'Algum caminho novo grava em pii_access_log sem passar actor_kind: encontre-o pelo `context`.');
});
