// tests/contracts/2427-vinculo-ativo-sem-porta-de-entrada.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: toca o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * Vinculo ativo pressupoe uma porta de entrada. Quem tem autoridade e nao tem como entrar esta
 * TRAVADO, e hoje isso nao aparece em lugar nenhum.
 *
 * O CASO (#2427): criar alguem como membro e liga-lo a uma iniciativa da AUTORIDADE. Nao da CONTA.
 * O mecanismo de conta existe e funciona — `request_account_claim` + `confirm_account_claim`,
 * `email_verification_pending` com 64 linhas — mas ele e **self-service e puxado**: exige
 * `auth.uid()`, ou seja, a pessoa ja precisa ter criado conta e ter ido procurar o proprio registro.
 *
 * ⇒ Quem e criado FORA do funil de selecao nunca e avisado de que existe registro, de que precisa
 * criar conta, e de que depois precisa vincular. O mecanismo nao esta quebrado: esta sem quem o
 * acione.
 *
 * Medido em 23/09/2026: **11** membros ativos sem `auth_id`, dos quais **8 com vinculo ativo** e
 * **0 com convite de conta emitido**. O mais antigo esta assim desde **06/03/2026** — mais de seis
 * meses com autoridade e sem porta. O caso que tornou isto visivel foi a lider de um workgroup,
 * criada em 19/09, que coordena um quadro que nao consegue abrir.
 *
 * ⚠️ O PREDICADO FOI AFUNILADO DEPOIS DE MEDIR, E ISSO E O PONTO.
 * A primeira versao deste guard contava "vinculo ativo sem login e sem convite" e achava **8**.
 * Medindo o que aqueles 8 eram: **12 dos 13 vinculos nao tinham `initiative_id`** — eram
 * `chapter_board`, `sponsor` e `observer` em escopo de ORGANIZACAO, ou seja, cadastro
 * institucional (diretoria de capitulo parceiro, patrocinador) que plausivelmente existe para
 * aparecer no organograma e nunca precisou de tela.
 *
 * Um guard que acusa 8 quando ~2 importam vira ruido que ninguem olha, e ai ele para de proteger.
 * E endurecer um portao com falso positivo conhecido gera pressao CONTRA o portao. Entao o
 * predicado passou a exigir que a pessoa tenha vinculo **com iniciativa** ou vinculo de
 * **voluntario** — os dois casos em que a tela E o trabalho. Resultado: **2**, os dois de setembro.
 *
 * ⚠️ E POR QUE UMA CATRACA, E NAO UM ZERO: os 2 sao passado. Exigir zero hoje deixaria o guard
 * vermelho por historico. O baseline e NOMEADO, com data, e so pode ENCOLHER: caso novo reprova;
 * caso resolvido reprova pedindo que o baseline diminua.
 *
 * Cross-ref: #2427, #2400/#2416 (o par externo que pressupoe acesso sem te-lo), ADR-0131.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

/**
 * As 2 pessoas que ja estavam travadas quando o detector nasceu (depois de afunilar o predicado), por prefixo OPACO do id
 * (repositorio publico: nada de nome ou e-mail aqui).
 *
 * Cada uma com o que ela custa: quantos vinculos ativos ela tem, e desde quando. Sem isso,
 * "2 travados" e um numero sem dono, e ninguem sabe qual resolver primeiro.
 */
const BASELINE = [
  { opaco: 'b7418d4d', motivo: 'volunteer × researcher', desde: '2026-09-10' },
  { opaco: '76a38ad4', motivo: 'workgroup_coordinator × leader (com iniciativa)', desde: '2026-09-19' },
];
const CONHECIDOS = new Set(BASELINE.map((b) => b.opaco));

/**
 * Travado = membro ATIVO, sem `auth_id`, COM vinculo ativo e SEM convite de conta emitido.
 *
 * As quatro condicoes juntas importam. Sem `auth_id` e sem vinculo e cadastro inerte, nao gente
 * esperando. Com convite emitido a bola esta com a pessoa, nao com a casa.
 *
 * Recebe as linhas como dado puro: e a MESMA funcao que julga o estado real e o adulterado do
 * teste de mutacao.
 */
export function travados(membros) {
  return membros
    .filter((m) => m.member_status === 'active')
    .filter((m) => m.auth_id === null)
    .filter((m) => !m.tem_claim)
    // A tela E o trabalho: vinculo ligado a uma INICIATIVA, ou vinculo de VOLUNTARIO do Nucleo.
    // Cadastro institucional em escopo de organizacao (chapter_board, sponsor, observer) fica de
    // fora de proposito — ver o afunilamento no cabecalho.
    .filter((m) => (m.vinculos_com_iniciativa ?? 0) > 0 || (m.vinculos_voluntario ?? 0) > 0)
    .map((m) => ({ opaco: String(m.id).slice(0, 8), desde: m.criado }));
}

async function lerMembros() {
  const c = sb();
  const { data: membros, error: e1 } = await c
    .from('members').select('id, auth_id, member_status, person_id, created_at');
  assert.ifError(e1);
  const { data: engs, error: e2 } = await c
    .from('engagements').select('person_id, status, kind, initiative_id').eq('status', 'active');
  assert.ifError(e2);
  const { data: claims, error: e3 } = await c
    .from('email_verification_pending').select('target_member_id, purpose').eq('purpose', 'account_claim');
  assert.ifError(e3);

  const comIniciativa = new Map();
  const voluntario = new Map();
  for (const e of engs) {
    if (e.initiative_id) comIniciativa.set(e.person_id, (comIniciativa.get(e.person_id) ?? 0) + 1);
    if (e.kind === 'volunteer') voluntario.set(e.person_id, (voluntario.get(e.person_id) ?? 0) + 1);
  }
  const comClaim = new Set(claims.map((c2) => c2.target_member_id));

  return membros.map((m) => ({
    id: m.id,
    auth_id: m.auth_id,
    member_status: m.member_status,
    vinculos_com_iniciativa: comIniciativa.get(m.person_id) ?? 0,
    vinculos_voluntario: voluntario.get(m.person_id) ?? 0,
    tem_claim: comClaim.has(m.id),
    criado: (m.created_at || '').slice(0, 10),
  }));
}

test('#2427 catraca — nenhum vinculo ativo NOVO sem porta de entrada',
  { skip: dbGated ? false : skipMsg }, async () => {
    const membros = await lerMembros();

    // Controle positivo duplo: a varredura precisa estar vendo uma base real E o eixo do claim.
    // Com qualquer uma das leituras vazia, a lista de travados tambem sai vazia — e o verde seria
    // por vacuidade, que e exatamente como este defeito sobreviveu seis meses.
    assert.ok(membros.length >= 50,
      `controle positivo: a varredura achou so ${membros.length} membros`);
    assert.ok(membros.some((m) => m.auth_id !== null),
      'controle positivo: ninguem com auth_id — a coluna nao esta sendo lida');
    assert.ok(membros.some((m) => m.vinculos_com_iniciativa > 0),
      'controle positivo: ninguem com vinculo ligado a iniciativa — a juncao por person_id nao casa');
    assert.ok(membros.some((m) => m.vinculos_voluntario > 0),
      'controle positivo: ninguem com vinculo de voluntario — o campo kind nao esta sendo lido');

    const achados = travados(membros);
    const novos = achados.filter((t) => !CONHECIDOS.has(t.opaco));
    assert.deepEqual(novos, [],
      'alguem ganhou vinculo ativo sem ter como entrar na plataforma: autoridade concedida e ' +
      'nenhuma porta. Emita o convite de conta, ou registre por que esta pessoa nao precisa de ' +
      'tela (#2427)');

    // A catraca tambem aperta: resolvido tem de SAIR do baseline, senao o numero mente para baixo.
    const vivos = new Set(achados.map((t) => t.opaco));
    const jaResolvidos = [...CONHECIDOS].filter((o) => !vivos.has(o));
    assert.deepEqual(jaResolvidos, [],
      'estas pessoas nao estao mais travadas: tire do BASELINE para a catraca nao afrouxar (#2427)');
  });

test('#2427 mutacao — o detector reprova cada forma do defeito, pela MESMA funcao', () => {
  const OK = [
    { id: 'aaaaaaaa-1', auth_id: 'uid-1', member_status: 'active', vinculos_com_iniciativa: 2, vinculos_voluntario: 0, tem_claim: false, criado: '2026-09-01' },
    { id: 'bbbbbbbb-2', auth_id: null, member_status: 'active', vinculos_com_iniciativa: 0, vinculos_voluntario: 0, tem_claim: false, criado: '2026-09-01' },
    { id: 'cccccccc-3', auth_id: null, member_status: 'active', vinculos_com_iniciativa: 1, vinculos_voluntario: 0, tem_claim: true, criado: '2026-09-01' },
    { id: 'dddddddd-4', auth_id: null, member_status: 'alumni', vinculos_com_iniciativa: 1, vinculos_voluntario: 0, tem_claim: false, criado: '2026-09-01' },
  ];
  assert.deepEqual(travados(OK), [],
    'controle sem mutacao: com login, sem vinculo, com claim, ou inativo — nenhum esta travado');

  // Mutacao 1 — o caso REAL: ativo, sem login, com vinculo, sem claim.
  const travado = [{ id: 'eeeeeeee-5', auth_id: null, member_status: 'active', vinculos_com_iniciativa: 1, vinculos_voluntario: 0, tem_claim: false, criado: '2026-09-23' }];
  assert.deepEqual(travados(travado), [{ opaco: 'eeeeeeee', desde: '2026-09-23' }],
    'mutacao 1: o detector tem de achar autoridade sem porta');

  // Mutacao 2 — cada condicao sozinha NAO pode disparar: o detector precisa das quatro juntas,
  // senao ele acusa cadastro inerte e vira ruido que ninguem olha.
  for (const [nome, linha] of [
    ['tem login', { ...travado[0], auth_id: 'uid' }],
    ['sem vinculo', { ...travado[0], vinculos_com_iniciativa: 0, vinculos_voluntario: 0 }],
    ['ja tem claim', { ...travado[0], tem_claim: true }],
    ['nao esta ativo', { ...travado[0], member_status: 'inactive' }],
  ]) {
    assert.deepEqual(travados([linha]), [], `mutacao 2 (${nome}): nao pode contar como travado`);
  }

  // Mutacao 3 — A CATRACA, nao so o classificador. Injeta uma pessoa nova travada no conjunto
  // REAL e confirma que ela e sinalizada como NOVA. Sem isto, o `deepEqual(novos, [])` do teste
  // vivo estaria verde e nunca teria sido exercido: provar que `travados()` classifica nao prova
  // que a catraca acusa.
  const achadosFicticios = [
    ...BASELINE,                                        // os ja conhecidos
    { opaco: '9f9f9f9f', desde: '2026-09-23' }, // uma pessoa NOVA travada
  ];
  const novosDetectados = achadosFicticios.filter((t) => !CONHECIDOS.has(t.opaco));
  assert.deepEqual(novosDetectados, [{ opaco: '9f9f9f9f', desde: '2026-09-23' }],
    'catraca: pessoa nova travada tem de aparecer como NOVA, nao se diluir no baseline');

  // E o outro sentido: se alguem do baseline sair da lista, a catraca tem de PEDIR o encolhimento.
  const semUmDoBaseline = BASELINE.slice(1);
  const vivosFicticios = new Set(semUmDoBaseline.map((t) => t.opaco));
  const resolvidos = [...CONHECIDOS].filter((o) => !vivosFicticios.has(o));
  assert.deepEqual(resolvidos, [BASELINE[0].opaco],
    'catraca: quem foi resolvido tem de ser cobrado para sair do baseline');

  // Mutacao 4 — o detector nao pode passar por vacuidade com lista vazia.
  assert.deepEqual(travados([]), [], 'lista vazia produz lista vazia — por isso o controle positivo existe');
});
