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
 * ⚠️ O FUNIL TEM PORTA PROPRIA, E O DETECTOR NAO A LIA (10/10/2026). Dois candidatos aprovados no
 * ciclo aberto, convertidos pelo funil, reprovaram a catraca minutos depois de criados: sem login,
 * com vinculo de voluntario, sem claim e sem convite da ficha. Mas a porta deles ja tinha saido: o
 * e-mail `selection_approved` ("acesse a plataforma para iniciar o onboarding"), enviado no mesmo
 * minuto. A conta nasce de OAuth e o reconhecimento liga pelo e-mail do membro (#2273), entao com o
 * aviso entregue a bola esta com a pessoa — o mesmo criterio do convite da ficha.
 *
 * O que conta, e o que NAO conta, foi decidido medindo, nao por janela de tempo:
 *   - `selection_approved` com `email_sent_at` e sem falha de entrega CONTA. Medido: 75 dessas
 *     notificacoes, todas com envio, nenhuma com status de falha.
 *   - `engagement_welcome` NAO conta. A pessoa que originou a #2427 (lider criada fora do funil,
 *     `76a38ad4`) recebeu esse e-mail em 19/09 e continuou travada: ele descreve o vinculo, nao
 *     abre porta. Contar o welcome teria escondido o proprio caso fundador.
 *   - Token do portal (`onboarding_tokens`, `pmi_application`) so conta valido e com escopo
 *     `profile_completion`, que e o portal com caminho para a conta (#2273). O de
 *     `interview_booking` agenda entrevista e NAO leva para dentro: medido, os 9 tokens validos de
 *     10/10 eram todos desse escopo, e um dos dois casos nem tinha token valido.
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
  // b7418d4d (volunteer × researcher, desde 2026-09-10) saiu em 23/09: ganhou login as 17:05 UTC.
  // A catraca reprovou a main pedindo exatamente isto, que e o comportamento desenhado.
  // 76a38ad4 (workgroup_coordinator × leader, desde 2026-09-19) saiu em 25/09: recebeu o convite
  // de acesso do botao da ficha (member.access_invite_sent), que so passou a contar como porta
  // quando o detector aprendeu a le-lo (#2461).
];
const CONHECIDOS = new Set(BASELINE.map((b) => b.opaco));

/**
 * O aviso de aprovacao so e porta se SAIU e nao voltou. Status nulo com envio e o caso comum (o
 * webhook de entrega nem sempre chega); qualquer status alem de `delivered` (bounce, reclamacao,
 * atraso) nao conta, e a pessoa volta a aparecer como travada, que e o lado seguro.
 */
export function aprovacaoEntregue(n) {
  return !!n.email_sent_at && (n.email_delivery_status == null || n.email_delivery_status === 'delivered');
}

/**
 * Pessoas com o portal do token aberto: token -> candidatura (`source_id`) -> pessoa, pelo vinculo
 * ESTRUTURAL `engagements.selection_application_id`, o mesmo do resolvedor do portal (#2273).
 * Funcao propria para a juncao ser exercida pela mutacao, e nao so o classificador.
 */
export function pessoasComPortal(tokens, origens) {
  const candidaturaAberta = new Set(tokens.map((t) => t.source_id));
  return new Set(origens.filter((o) => candidaturaAberta.has(o.selection_application_id)).map((o) => o.person_id));
}

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
    // A porta do funil: o aviso de aprovacao entregue, ou o portal do token ainda aberto.
    // O aviso so vale para o que o FUNIL criou. Quem foi aprovado um dia e depois ganhou vinculo por
    // outro caminho (ficha, importacao) nunca foi avisado DESSE vinculo, e sem isto o aviso antigo
    // viraria porta permanente. Regra estrutural, sem janela de tempo.
    .filter((m) => !(m.aprovacao_entregue && (m.vinculos_fora_do_funil ?? 0) === 0))
    .filter((m) => !m.portal_aberto)
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
    .from('engagements').select('person_id, status, kind, initiative_id, selection_application_id').eq('status', 'active');
  assert.ifError(e2);
  // Candidatura -> pessoa pelo vinculo ESTRUTURAL, o mesmo do resolvedor do portal (#2273). Le
  // todo engagement com candidatura, nao so o ativo: a candidatura e a origem, o status nao muda isso.
  const { data: origens, error: e5, count: nOrigens } = await c
    .from('engagements').select('person_id, selection_application_id', { count: 'exact' })
    .not('selection_application_id', 'is', null);
  assert.ifError(e5);
  const { data: aprovacoes, error: e6, count: nAprovacoes } = await c
    .from('notifications').select('recipient_id, email_sent_at, email_delivery_status', { count: 'exact' })
    .eq('type', 'selection_approved');
  assert.ifError(e6);
  // O teto de linhas do PostgREST corta em silencio: leitura truncada vira gente falsamente travada.
  assert.equal(origens.length, nOrigens, `leitura truncada: ${origens.length} de ${nOrigens} engagements com candidatura`);
  assert.equal(aprovacoes.length, nAprovacoes, `leitura truncada: ${aprovacoes.length} de ${nAprovacoes} avisos de aprovacao`);
  const { data: tokens, error: e7 } = await c
    .from('onboarding_tokens').select('source_id')
    .eq('source_type', 'pmi_application').contains('scopes', ['profile_completion'])
    .is('consumed_at', null).gt('expires_at', new Date().toISOString());
  assert.ifError(e7);
  const { data: claims, error: e3 } = await c
    .from('email_verification_pending').select('target_member_id, purpose').eq('purpose', 'account_claim');
  assert.ifError(e3);
  // #2461: o convite do GP (admin_send_member_access, #2427) registra o ENVIO no audit log, nao em
  // email_verification_pending. Sem ler isto, todo convidado pelo botao da ficha aparecia travado.
  const { data: convites, error: e4 } = await c
    .from('admin_audit_log').select('target_id').eq('action', 'member.access_invite_sent');
  assert.ifError(e4);

  const comIniciativa = new Map();
  const voluntario = new Map();
  const foraDoFunil = new Map();
  for (const e of engs) {
    if ((e.initiative_id || e.kind === 'volunteer') && !e.selection_application_id) {
      foraDoFunil.set(e.person_id, (foraDoFunil.get(e.person_id) ?? 0) + 1);
    }
    if (e.initiative_id) comIniciativa.set(e.person_id, (comIniciativa.get(e.person_id) ?? 0) + 1);
    if (e.kind === 'volunteer') voluntario.set(e.person_id, (voluntario.get(e.person_id) ?? 0) + 1);
  }
  const comClaim = new Set([...claims.map((c2) => c2.target_member_id), ...convites.map((v) => v.target_id)]);
  const comAprovacao = new Set(aprovacoes.filter(aprovacaoEntregue).map((n) => n.recipient_id));
  const comPortal = pessoasComPortal(tokens, origens);

  return membros.map((m) => ({
    aprovacao_entregue: comAprovacao.has(m.id),
    portal_aberto: comPortal.has(m.person_id),
    vinculos_fora_do_funil: foraDoFunil.get(m.person_id) ?? 0,
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
    assert.ok(membros.some((m) => m.auth_id === null && m.tem_claim),
      'controle positivo: ninguem sem login com convite — o eixo do convite nao esta sendo lido');
    // O eixo do aviso de aprovacao: estavel porque conta quem JA entrou tambem. Vazio aqui quer dizer
    // que o tipo da notificacao ou o recipient_id deixou de casar, e todo aprovado pareceria travado.
    // O eixo do portal nao tem controle vivo: na medicao de 10/10 havia 0 tokens validos de
    // profile_completion. Ele fica provado pela mutacao abaixo, nao por esta varredura.
    assert.ok(membros.some((m) => m.aprovacao_entregue),
      'controle positivo: ninguem com aviso de aprovacao entregue — o eixo do funil nao esta sendo lido');

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
  // Baseline FICTICIO: o real pode estar vazio, e a catraca precisa ser exercida mesmo assim.
  const BASE_F = [{ opaco: '8e8e8e8e', desde: '2026-09-01' }];
  const CONHECIDOS_F = new Set(BASE_F.map((b) => b.opaco));
  const achadosFicticios = [
    ...BASE_F,                                          // os ja conhecidos
    { opaco: '9f9f9f9f', desde: '2026-09-23' }, // uma pessoa NOVA travada
  ];
  const novosDetectados = achadosFicticios.filter((t) => !CONHECIDOS_F.has(t.opaco));
  assert.deepEqual(novosDetectados, [{ opaco: '9f9f9f9f', desde: '2026-09-23' }],
    'catraca: pessoa nova travada tem de aparecer como NOVA, nao se diluir no baseline');

  // E o outro sentido: se alguem do baseline sair da lista, a catraca tem de PEDIR o encolhimento.
  const semUmDoBaseline = BASE_F.slice(1);
  const vivosFicticios = new Set(semUmDoBaseline.map((t) => t.opaco));
  const resolvidos = [...CONHECIDOS_F].filter((o) => !vivosFicticios.has(o));
  assert.deepEqual(resolvidos, [BASE_F[0].opaco],
    'catraca: quem foi resolvido tem de ser cobrado para sair do baseline');

  // Mutacao 5 — a porta do funil (10/10). O caso real de hoje: aprovado, convertido, sem login, com
  // vinculo de voluntario, sem claim, com o aviso de aprovacao entregue. Nao esta travado; sem o
  // aviso, esta. As duas metades juntas: so a primeira passaria com o filtro removido E com o campo
  // nunca preenchido.
  const doFunil = { id: 'ffffffff-6', auth_id: null, member_status: 'active', vinculos_com_iniciativa: 0, vinculos_voluntario: 1, tem_claim: false, aprovacao_entregue: true, portal_aberto: false, vinculos_fora_do_funil: 0, criado: '2026-10-10' };
  assert.deepEqual(travados([doFunil]), [],
    'mutacao 5a: aprovado com o aviso entregue tem porta, nao esta travado');
  assert.deepEqual(travados([{ ...doFunil, aprovacao_entregue: false }]), [{ opaco: 'ffffffff', desde: '2026-10-10' }],
    'mutacao 5b: sem o aviso de aprovacao, o mesmo aprovado esta travado');
  assert.deepEqual(travados([{ ...doFunil, aprovacao_entregue: false, portal_aberto: true }]), [],
    'mutacao 5c: com o portal do token aberto, tem porta');
  assert.deepEqual(travados([{ ...doFunil, vinculos_fora_do_funil: 1 }]), [{ opaco: 'ffffffff', desde: '2026-10-10' }],
    'mutacao 5d: aviso de aprovacao antigo nao abre porta para vinculo criado fora do funil');

  // Mutacao 7 — a juncao do portal: token -> candidatura -> pessoa. So o token valido da PROPRIA
  // candidatura liga a pessoa; o de outra candidatura nao.
  const origensF = [
    { person_id: 'p-1', selection_application_id: 'app-1' },
    { person_id: 'p-2', selection_application_id: 'app-2' },
  ];
  assert.deepEqual([...pessoasComPortal([{ source_id: 'app-1' }], origensF)], ['p-1'],
    'mutacao 7a: o token da candidatura app-1 abre o portal de p-1, e so de p-1');
  assert.deepEqual([...pessoasComPortal([{ source_id: 'app-9' }], origensF)], [],
    'mutacao 7b: token de candidatura sem vinculo nao liga ninguem');

  // Mutacao 6 — o que NAO e aviso entregue. Nao enviado, ou devolvido, nao abre porta.
  assert.equal(aprovacaoEntregue({ email_sent_at: '2026-10-10T15:30:00Z', email_delivery_status: null }), true,
    'mutacao 6a: enviado sem retorno de entrega conta');
  assert.equal(aprovacaoEntregue({ email_sent_at: '2026-10-10T15:30:00Z', email_delivery_status: 'delivered' }), true,
    'mutacao 6b: entregue conta');
  assert.equal(aprovacaoEntregue({ email_sent_at: null, email_delivery_status: null }), false,
    'mutacao 6c: aviso criado e nunca enviado nao e porta');
  assert.equal(aprovacaoEntregue({ email_sent_at: '2026-10-10T15:30:00Z', email_delivery_status: 'bounced' }), false,
    'mutacao 6d: aviso devolvido nao e porta');

  // Mutacao 4 — o detector nao pode passar por vacuidade com lista vazia.
  assert.deepEqual(travados([]), [], 'lista vazia produz lista vazia — por isso o controle positivo existe');
});
