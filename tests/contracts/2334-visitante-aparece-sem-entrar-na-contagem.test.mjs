// tests/contracts/2334-visitante-aparece-sem-entrar-na-contagem.test.mjs
// Registrar nas whitelists "test:behavioural" E "test:contracts" do package.json (#1109).
// (DB-aware: as camadas C, D e E abrem conexão. A e B são estáticas.)
/**
 * #2334 fase 2, fatia 1 — o visitante APARECE na tribo, e NÃO entra na contagem.
 *
 * O líder em formação visita tribos como `observer` para conhecer modelos de condução. O vínculo
 * não consome vaga nem popula `members.tribe_id` — mas ele também não aparecia na lista, porque
 * `v_initiative_roster` exclui observer nas duas pontas.
 *
 * ⚠️ A DECISÃO DE DESENHO QUE ESTE GUARD PROTEGE: a view NÃO foi aberta. Ela é consumida por 12
 * funções, duas das quais são portões de AUTORIDADE (`_can_sign_gate`,
 * `_can_manage_recurring_rule`) e cinco CONTAM. Abrir a view mudaria as 12 de uma vez, e bastaria
 * um consumidor de contagem esquecido para o visitante contar em silêncio — o modo de falha de
 * #2323, #2325 e #2286. Só a RPC da tela une os visitantes.
 *
 * ⚠️ LIMITE DO TESTE DE MUTAÇÃO AQUI, e vale dizer: mutar o ARQUIVO só exercita as camadas
 * estáticas. C, D e E leem o BANCO, que continua com a função aplicada — então uma mutação de
 * arquivo passa por elas sem reprovar. Elas foram validadas por evidência direta (medem o
 * comportamento real com dados reais) e por controles positivos internos: cada uma verifica que
 * há visitante para medir antes de afirmar, e D afirma a igualdade contagem == efetivos, que
 * quebra se o visitante entrar no denominador.
 *
 * Camadas:
 *   A (estático) a view continua excluindo observer — se alguém "simplificar" abrindo-a, reprova.
 *   B (estático) a RPC une visitantes e marca `is_visitor`.
 *   C (vivo)     o visitante APARECE no roster da tribo visitada, marcado.
 *   D (vivo)     e NÃO entra em `get_initiative_roster_count` nem em `v_tribe_active_members`
 *                (a vaga do teto). É a metade que o recorte "aparecer sem contar" exige.
 *   E (vivo)     quem é efetivo numa tribo NÃO é marcado visitante nela (precedência).
 *
 * Cross-ref: #2334, #2333, ADR-0105.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
// #2461: kind='observer' com papel de participacao e participante EXTERNO (ADR-0131), conta e nao e
// visitante. Visitante e o observer com qualquer outro papel.
const VISITOR_EXCLUDED_ROLES = '(participant,coordinator)';
const MIGRATIONS = join(ROOT, 'supabase/migrations');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** Corpo da RPC, na ÚLTIMA migration que a define. */
function corpoDaRpc() {
  const achados = readdirSync(MIGRATIONS)
    .filter(f => f.endsWith('.sql')).sort()
    .map(f => readFileSync(join(MIGRATIONS, f), 'utf8'))
    .filter(s => s.includes('CREATE OR REPLACE FUNCTION public.get_initiative_roster_members('));
  assert.ok(achados.length >= 1, 'nenhuma migration define get_initiative_roster_members');
  const src = achados[achados.length - 1];
  const i = src.indexOf('CREATE OR REPLACE FUNCTION public.get_initiative_roster_members(');
  const resto = src.slice(i);
  const fim = resto.indexOf('$function$;');
  assert.ok(fim > 0, 'o corpo não fecha com $function$;');
  return resto.slice(0, fim);
}

// ═══════════════════════════════════════════════════════════════════════════
test('A · a view v_initiative_roster continua EXCLUINDO observer', { skip: !dbGated && skipMsg }, async () => {
  // Medido pelo EFEITO, não pelo texto da view: se ela tivesse sido aberta, um observer ativo
  // apareceria nela. Isso sobrevive a uma reescrita que mude a forma e preserve o comportamento.
  const { data: vis, error: e2 } = await sb()
    .from('engagements').select('person_id, initiative_id')
    .eq('status', 'active').eq('kind', 'observer').not('role', 'in', VISITOR_EXCLUDED_ROLES)
    .not('initiative_id', 'is', null).limit(1);
  assert.equal(e2, null);
  if (!vis?.length) return; // sem observer ativo, esta camada não tem o que medir

  const { data: roster, error: e3 } = await sb()
    .from('v_initiative_roster').select('person_id')
    .eq('initiative_id', vis[0].initiative_id).eq('person_id', vis[0].person_id);
  assert.equal(e3, null);
  assert.equal(roster.length, 0,
    'a view v_initiative_roster passou a incluir observer. Ela alimenta 12 funções, duas delas ' +
    'portões de AUTORIDADE e cinco de CONTAGEM — abrir a view faz o visitante contar em silêncio ' +
    'em qualquer consumidor esquecido. A inclusão do visitante é feita na RPC da tela, não aqui.');
});

test('B · a RPC une os visitantes e marca is_visitor', () => {
  const corpo = corpoDaRpc();
  // ⚠️ O PADRÃO É ESPECÍFICO DE PROPÓSITO. A primeira versão desta asserção era /is_visitor/ solto,
  // e passava com o campo REMOVIDO do UNION — porque a string ainda aparecia nos comentários e na
  // projeção externa. Foi o teste de mutação que expôs isso. Aqui casamos o ponto exato onde o
  // visitante é MARCADO, e a projeção que o entrega.
  assert.match(corpo, /true\s+AS\s+is_visitor/,
    'a RPC parou de MARCAR o visitante no ramo do UNION: sem isso a tela não consegue rotulá-lo e ' +
    'ele aparece com o papel do cache global (um líder em formação vira "Líder de Tribo" numa ' +
    'tribo que não lidera — foi o que a tela mostrou em 17/09)');
  assert.match(corpo, /u\.is_visitor/,
    'a projeção externa parou de devolver is_visitor: o campo existe no UNION mas não chega à tela');
  assert.match(corpo, /kind\s*=\s*'observer'/,
    'a RPC parou de unir os visitantes — eles somem da lista da tribo visitada');
  assert.match(corpo, /rls_can_see_initiative/,
    'o gate de iniciativa confidencial (ADR-0105) sumiu da primeira linha: roster confidencial vazaria');
});

// ═══════════════════════════════════════════════════════════════════════════
test('C · o visitante APARECE no roster, marcado', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const { data: vis, error } = await c.from('engagements')
    .select('person_id, initiative_id').eq('status','active').eq('kind','observer')
    .not('role','in',VISITOR_EXCLUDED_ROLES).not('initiative_id','is',null).limit(1);
  assert.equal(error, null);
  if (!vis?.length) return; // nenhuma visita ativa: nada a medir

  const { data: roster, error: e2 } = await c.rpc('get_initiative_roster_members',
    { p_initiative_id: vis[0].initiative_id });
  assert.equal(e2, null, `get_initiative_roster_members falhou: ${e2?.message}`);
  const visitantes = (roster || []).filter(r => r.is_visitor === true);
  assert.ok(visitantes.length > 0,
    'há visita ativa na iniciativa, mas o roster não devolveu nenhum is_visitor=true — o visitante ' +
    'voltou a ficar invisível na tribo que está visitando');
});

test('D · e NÃO entra na contagem nem ocupa vaga', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const { data: vis } = await c.from('engagements')
    .select('person_id, initiative_id').eq('status','active').eq('kind','observer')
    .not('role','in',VISITOR_EXCLUDED_ROLES).not('initiative_id','is',null).limit(1);
  if (!vis?.length) return;
  const iniciativa = vis[0].initiative_id;

  const { data: roster } = await c.rpc('get_initiative_roster_members', { p_initiative_id: iniciativa });
  const { data: contagem, error: e2 } = await c.rpc('get_initiative_roster_count', { p_initiative_id: iniciativa });
  assert.equal(e2, null);

  const efetivos = (roster || []).filter(r => !r.is_visitor).length;
  const visitantes = (roster || []).filter(r => r.is_visitor).length;

  assert.equal(contagem, efetivos,
    `a contagem oficial (${contagem}) divergiu dos efetivos do roster (${efetivos}). O visitante ` +
    'entrou no denominador — é exatamente o que o recorte "aparecer sem contar" proíbe.');
  assert.ok(visitantes > 0, 'controle: sem visitante no roster esta camada não discrimina nada');

  // A vaga do teto: v_tribe_active_members é a fonte do limite por tribo e NÃO pode incluí-lo.
  const { data: vagas, error: e3 } = await c.from('v_tribe_active_members')
    .select('person_id').eq('initiative_id', iniciativa).eq('person_id', vis[0].person_id);
  assert.equal(e3, null);
  assert.equal(vagas.length, 0,
    'o visitante passou a ocupar vaga no teto da tribo — quem visita não consome vaga de pesquisador');
});

test('E · quem é EFETIVO numa tribo não é marcado visitante nela', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  // Pessoa com engajamento volunteer ativo numa research_tribe: no roster daquela iniciativa
  // ela tem de sair como is_visitor=false, mesmo que seja observer em OUTRA.
  const { data: efetivo, error } = await c.from('engagements')
    .select('person_id, initiative_id').eq('status','active').eq('kind','volunteer')
    .not('initiative_id','is',null).limit(1);
  assert.equal(error, null);
  if (!efetivo?.length) return;

  const { data: roster } = await c.rpc('get_initiative_roster_members',
    { p_initiative_id: efetivo[0].initiative_id });
  const { data: m } = await c.from('members').select('id').eq('person_id', efetivo[0].person_id).limit(1);
  if (!m?.length) return;
  const linha = (roster || []).find(r => r.id === m[0].id);
  assert.ok(linha, 'o membro efetivo sumiu do roster da própria iniciativa');
  assert.equal(linha.is_visitor, false,
    'um membro EFETIVO foi marcado como visitante na própria tribo — a precedência do DISTINCT ON ' +
    'quebrou, e quem é membro pleno passaria a aparecer rotulado como visita');
});
