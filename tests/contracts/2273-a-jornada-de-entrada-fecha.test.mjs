// tests/contracts/2273-a-jornada-de-entrada-fecha.test.mjs
// Registrar nas whitelists "test:behavioural" E "test:contracts" do package.json (#1109).
// (DB-aware: as camadas A, C, D, E e F abrem conexão. As B e G são herméticas.)
/**
 * #2273 — a jornada de entrada FECHA: o portal deixa de falar por chave crua, e deixa de
 * terminar num botão que leva a um muro.
 *
 * O QUE A MEDIÇÃO DE 14/09 MOSTROU, e que este arquivo existe para não deixar regredir:
 *
 *   * A jornada NÃO estava quebrada. `members.auth_id.first_link` tem 68 eventos, o
 *     `rotated_secondary` 14 e o `claim` self-service 2. Dos 27 que ficaram elegíveis ao
 *     first_link desde 29/06, 25 ligaram. O zero de setembro é fila seca, não defeito — e foi
 *     quase lido como "parou de funcionar" até o CONTROLE (quantos ficaram elegíveis por semana)
 *     desmentir. Ausência dentro de um recorte não é evidência sem o denominador ao lado.
 *   * Das 10 pessoas sem conta em 150 dias, SEIS são `chapter_liaison` ou `guest` criados
 *     administrativamente, sem candidatura e sem token. A #2273 não as alcança, e um teste que
 *     medisse "10 sem conta" estaria medindo outra população.
 *   * 88% das contas nascem de OAuth. A pessoa já criava conta sozinha; faltava o portal dizer
 *     COM QUAL e-mail.
 *
 * ⚠️ A ARMADILHA QUE DECIDE O DESENHO: o reconhecimento liga conta nova a membro pelo e-mail
 * PRIMÁRIO DO MEMBRO. Um acesso criado em outro endereço nasce ghost. Por isso nada nesta onda
 * aceita e-mail vindo do cliente, e a camada E é a que prova isso na superfície de permissão.
 *
 * As camadas, e por que cada uma precisa existir:
 *
 *   A (vivo)     `consume_onboarding_token` devolve `step_catalog` com o catálogo inteiro, e todo
 *                passo do progresso da fixture tem rótulo humano.
 *   B (hermético) A MORDIDA da camada A. Um teste que só afirmasse "tem rótulo" ficaria VERDE pelo
 *                fallback `?? step.step_key` e não discriminaria nada — o defeito A era
 *                exatamente um fallback sempre acionado. Aqui a mesma asserção é aplicada a
 *                payloads fabricados, e ela TEM de reprovar com o catálogo vazio.
 *   C (vivo)     `account_state` discrimina as três condições do seu próprio AND, cada uma
 *                isolada por uma fixture, em vez de um único caso verde.
 *   D (vivo)     `request_portal_account_setup` recusa o que deve recusar e NÃO consome o token —
 *                `access_count` é o único sinal de que a pessoa clicou no link do e-mail, e um
 *                pedido de acesso somado ali apagaria a métrica de intenção.
 *   E (estrutura) a superfície de permissão: anon alcança as duas RPCs do portal e NENHUMA das
 *                outras. Grant é estado do catálogo do Postgres, não do arquivo que o declara.
 *   F (vivo)     o detector do ponto cego roda, e não vaza endereço.
 *   G (estático) o componente consulta o CATÁLOGO antes do JSONB, e o ramo de aprovado não é mais
 *                um link solitário. Derivado do arquivo, não de lista de nomes.
 *
 * Cross-ref: #2273, #2265 (a reemissão do link), #2245 (a fonte das chaves fora do catálogo),
 * #1997 (a identidade do evento do modal), #1636 (nenhuma candidatura real é tocada).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { createSyntheticApplication } from '../helpers/selection-fixtures.mjs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const COMPONENTE = join(ROOT, 'src/components/pmi-onboarding/PMIOnboardingPortal.tsx');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
// O fallback de nome não é cosmético: o CI exporta `SUPABASE_ANON_KEY` e o `.env` local usa o
// prefixo `PUBLIC_` (mesma razão registrada na #1294).
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/** Token descartável para uma candidatura sintética. O `cleanup()` da fixture apaga por source_id. */
async function emitirToken(c, applicationId, { expiraEmMinutos = 30 } = {}) {
  const token = `t2273_${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`;
  // `organization_id` e NOT NULL, e a org certa e a DA CANDIDATURA: um token emitido sob outra
  // org descreveria um vinculo que nao existe.
  const { data: app, error: eApp } = await c
    .from('selection_applications').select('organization_id').eq('id', applicationId).single();
  assert.ifError(eApp);
  const { error } = await c.from('onboarding_tokens').insert({
    token,
    source_type: 'pmi_application',
    source_id: applicationId,
    scopes: ['profile_completion'],
    issued_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + expiraEmMinutos * 60_000).toISOString(),
    organization_id: app.organization_id,
    issued_by_worker: 'test-2273',
  });
  assert.ifError(error);
  return token;
}

/** Membro sintético que o resolvedor acha pelo e-mail da candidatura (o caminho (b) da função). */
async function criarMembroPara(c, email, nome) {
  const { data, error } = await c.from('members')
    .insert({ name: `__1636_synthetic__ ${nome}`, email, is_active: false, current_cycle_active: false })
    .select('id').single();
  assert.ifError(error);
  return data.id;
}

/**
 * A ASSERÇÃO SOB TESTE, isolada numa função para que a camada B possa mordê-la.
 *
 * Ela afirma o que o defeito A violava: todo passo do progresso tem rótulo vindo do CATÁLOGO.
 * Repare no que ela NÃO faz — não aceita "existe algum texto", porque o fallback sempre produzia
 * texto (a chave crua). Ela exige que a chave esteja no catálogo e que o rótulo seja diferente
 * dela nas três línguas.
 */
function afirmaRotulosDoCatalogo(payload) {
  const catalogo = payload.step_catalog ?? [];
  assert.ok(Array.isArray(catalogo) && catalogo.length > 0,
    'step_catalog veio vazio: o portal voltaria a resolver rótulo pelo JSONB por ciclo, que está em 0');

  const porChave = new Map(catalogo.map((e) => [e.key, e]));
  for (const passo of payload.onboarding_progress ?? []) {
    const entrada = porChave.get(passo.step_key);
    assert.ok(entrada,
      `o passo '${passo.step_key}' não está no catálogo: a pessoa leria a chave crua`);
    for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
      const rotulo = entrada.label?.[lang];
      assert.ok(rotulo && rotulo.trim().length > 0,
        `'${passo.step_key}' sem rótulo em ${lang}`);
      assert.notEqual(rotulo, passo.step_key,
        `'${passo.step_key}' em ${lang} tem rótulo IGUAL à chave: isso é o fallback, não o catálogo`);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// A — DEFEITO A, vivo: o rótulo vem do catálogo
// ═══════════════════════════════════════════════════════════════════════════
test('A · consume_onboarding_token devolve o catálogo, e todo passo tem rótulo humano', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const fx = await createSyntheticApplication(c, { cycleStatus: 'closed', status: 'approved', label: '2273a' });
  try {
    const token = await emitirToken(c, fx.application.id);
    const { data, error } = await c.rpc('consume_onboarding_token', { p_token: token });
    assert.ifError(error);

    afirmaRotulosDoCatalogo(data);

    // O catálogo devolvido é O catálogo, não um recorte que envelhece à parte dele.
    const { count, error: e2 } = await c
      .from('onboarding_steps').select('id', { count: 'exact', head: true });
    assert.ifError(e2);
    assert.equal(data.step_catalog.length, count,
      `step_catalog tem ${data.step_catalog.length} mas o catálogo tem ${count}: a RPC está filtrando`);

    // E o CONTRASTE que nomeia o defeito: a fonte antiga continua vazia. Sem esta linha o teste
    // ficaria verde mesmo num mundo onde o JSONB tivesse sido populado à mão — e aí ele estaria
    // afirmando outra coisa, não que o leitor mudou de fonte.
    const doCiclo = data.cycle?.onboarding_steps ?? [];
    assert.equal(doCiclo.length, 0,
      `o JSONB por ciclo deixou de estar vazio (${doCiclo.length}): re-meça antes de confiar nesta camada`);
  } finally {
    await fx.cleanup();
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// B — A MORDIDA: a asserção da camada A reprova quando o defeito volta
// ═══════════════════════════════════════════════════════════════════════════
test('B · a asserção MORDE: catálogo vazio ou incompleto tem de reprovar', async () => {
  const progresso = [{ step_key: 'complete_profile', status: 'pending' }];
  const catalogoBom = [{
    key: 'complete_profile',
    label: { 'pt-BR': 'Complete seu perfil', 'en-US': 'Complete your profile', 'es-LATAM': 'Complete su perfil' },
    description: {},
  }];

  // Controle POSITIVO: com catálogo cheio e JSONB vazio, tem de PASSAR. É o cenário que a issue
  // nomeia como o que deve ficar verde, e sem ele os três controles negativos abaixo poderiam
  // estar passando por um erro que reprova tudo.
  assert.doesNotThrow(
    () => afirmaRotulosDoCatalogo({ step_catalog: catalogoBom, onboarding_progress: progresso, cycle: { onboarding_steps: [] } }),
    'catálogo cheio + JSONB vazio deveria passar: é exatamente o estado que a correção produz',
  );

  // Negativo 1 — catálogo vazio (o defeito A na sua forma pura).
  assert.throws(
    () => afirmaRotulosDoCatalogo({ step_catalog: [], onboarding_progress: progresso }),
    /step_catalog veio vazio/,
    'com o catálogo vazio a asserção passou: ela não discrimina nada',
  );

  // Negativo 2 — catálogo existe mas não cobre a chave do progresso.
  assert.throws(
    () => afirmaRotulosDoCatalogo({
      step_catalog: [{ key: 'outra_coisa', label: { 'pt-BR': 'x', 'en-US': 'x', 'es-LATAM': 'x' } }],
      onboarding_progress: progresso,
    }),
    /não está no catálogo/,
    'chave ausente do catálogo passou: a pessoa leria a chave crua e o teste não veria',
  );

  // Negativo 3 — o rótulo É a chave. Este é o disfarce mais perigoso do fallback: há texto, e o
  // texto é a chave. Um teste que só checasse presença ficaria verde aqui.
  assert.throws(
    () => afirmaRotulosDoCatalogo({
      step_catalog: [{ key: 'complete_profile', label: { 'pt-BR': 'complete_profile', 'en-US': 'complete_profile', 'es-LATAM': 'complete_profile' } }],
      onboarding_progress: progresso,
    }),
    /IGUAL à chave/,
    'rótulo idêntico à chave passou: o teste aceitaria o fallback como se fosse o catálogo',
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// C — DEFEITO B, vivo: `account_state` discrimina cada condição do seu AND
// ═══════════════════════════════════════════════════════════════════════════
test('C · account_state separa aprovado-sem-conta de não-aprovado e de sem-membro', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();

  // (i) aprovado COM membro e sem conta → pode pedir acesso. O caso das 4 pessoas medidas.
  const fxOk = await createSyntheticApplication(c, { cycleStatus: 'closed', status: 'approved', label: '2273ci' });
  let membroOk = null;
  // (ii) NÃO aprovado, com membro → a mesma forma, e mesmo assim não pode: quem está em avaliação
  //      ainda não tem lugar para entrar.
  const fxPend = await createSyntheticApplication(c, { cycleStatus: 'closed', status: 'submitted', label: '2273cii' });
  let membroPend = null;
  // (iii) aprovado SEM membro → não há primário para ler, e o portal não pode inventar um.
  const fxSemMembro = await createSyntheticApplication(c, { cycleStatus: 'closed', status: 'approved', label: '2273ciii' });

  try {
    membroOk = await criarMembroPara(c, fxOk.application.email, 'c-i');
    membroPend = await criarMembroPara(c, fxPend.application.email, 'c-ii');

    const ler = async (appId) => {
      const token = await emitirToken(c, appId);
      const { data, error } = await c.rpc('consume_onboarding_token', { p_token: token });
      assert.ifError(error);
      return data.account_state;
    };

    const aOk = await ler(fxOk.application.id);
    assert.equal(aOk.member_exists, true, '(i) o membro existe e não foi resolvido');
    assert.equal(aOk.has_account, false, '(i) membro sintético nasce sem auth_id');
    assert.equal(aOk.can_request_setup, true, '(i) aprovado + membro + sem conta tem de poder pedir acesso');
    assert.ok(aOk.masked_email, '(i) sem e-mail mascarado o portal não consegue dizer com qual endereço entrar');
    // A máscara é máscara: não pode conter a parte local inteira do endereço.
    const localOk = fxOk.application.email.split('@')[0];
    assert.ok(!aOk.masked_email.includes(localOk),
      `(i) o mascarado '${aOk.masked_email}' contém a parte local crua: não está mascarando`);

    const aPend = await ler(fxPend.application.id);
    assert.equal(aPend.member_exists, true, '(ii) o membro existe');
    assert.equal(aPend.can_request_setup, false,
      '(ii) candidatura não aprovada não pode pedir acesso — o gate de status não está discriminando');

    const aSem = await ler(fxSemMembro.application.id);
    assert.equal(aSem.member_exists, false, '(iii) não deveria existir membro para esta candidatura');
    assert.equal(aSem.can_request_setup, false, '(iii) sem membro não há primário para ler');
    assert.equal(aSem.masked_email, null, '(iii) sem membro não pode haver e-mail mascarado');
  } finally {
    if (membroOk) await c.from('members').delete().eq('id', membroOk);
    if (membroPend) await c.from('members').delete().eq('id', membroPend);
    await fxOk.cleanup();
    await fxPend.cleanup();
    await fxSemMembro.cleanup();
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// D — DEFEITO B, vivo: a RPC recusa o que deve, e NÃO consome o token
// ═══════════════════════════════════════════════════════════════════════════
test('D · request_portal_account_setup recusa não-aprovado e preserva access_count', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const fx = await createSyntheticApplication(c, { cycleStatus: 'closed', status: 'submitted', label: '2273d' });
  let membro = null;
  try {
    membro = await criarMembroPara(c, fx.application.email, 'd');
    const token = await emitirToken(c, fx.application.id);

    const antes = await c.from('onboarding_tokens')
      .select('access_count, consumed_at').eq('token', token).single();
    assert.ifError(antes.error);
    assert.equal(antes.data.access_count, 0, 'o token nasce com access_count 0');

    const { data, error } = await c.rpc('request_portal_account_setup', { p_token: token });
    assert.ifError(error);
    assert.equal(data.success, false, 'candidatura submitted não pode receber link de acesso');
    assert.equal(data.state, 'not_approved', `recusou pelo motivo errado: ${JSON.stringify(data)}`);

    // A invariante mais sutil da onda. `access_count` é o ÚNICO sinal que diz se a pessoa clicou
    // no link do e-mail — foi por ele que se soube que uma das quatro clicou e outra não. Se um
    // pedido de acesso o incrementasse, o sinal de intenção passaria a medir duas coisas
    // diferentes somadas, e nunca mais se saberia qual.
    const depois = await c.from('onboarding_tokens')
      .select('access_count, consumed_at, last_accessed_at').eq('token', token).single();
    assert.ifError(depois.error);
    assert.equal(depois.data.access_count, 0,
      'request_portal_account_setup consumiu o token: access_count deixou de medir clique no e-mail');
    assert.equal(depois.data.consumed_at, null, 'o token foi marcado como consumido por um pedido de acesso');

    // Token inexistente não pode vazar a diferença entre "não existe" e "existe e é de outro".
    const inv = await c.rpc('request_portal_account_setup', { p_token: 'nao_existe_2273_xxxxxxxxxxxxxxxx' });
    assert.ifError(inv.error);
    assert.equal(inv.data.state, 'invalid_or_expired');
  } finally {
    if (membro) await c.from('members').delete().eq('id', membro);
    await fx.cleanup();
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// E — a superfície de permissão, lida do catálogo do Postgres
// ═══════════════════════════════════════════════════════════════════════════
test('E · anon alcança as duas RPCs do portal, e é barrado nas outras três', { skip: (dbGated && ANON_KEY) ? false : 'Skipped: anon key required' }, async () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });

  // A medição é o EXERCÍCIO, não a leitura do .sql: um GRANT que a migration declara mas que um
  // REVOKE posterior derrubou continuaria escrito no arquivo e ausente do banco.
  //
  // O token abaixo é sintaticamente válido e não existe. Isso é o que separa os dois desfechos:
  // quem TEM execute chega ao corpo da função e responde sobre o token; quem NÃO tem é barrado
  // antes, pelo PostgREST. Sem um argumento que atravesse, "deu erro" não distinguiria as duas.
  const TOKEN_INEXISTENTE = 'nao_existe_2273_yyyyyyyyyyyyyyyy';

  // ── CONTROLE POSITIVO: anon PRECISA alcançar estas duas, senão o portal anônimo não abre.
  const r1 = await anon.rpc('request_portal_account_setup', { p_token: TOKEN_INEXISTENTE });
  assert.ifError(r1.error);
  assert.equal(r1.data?.state, 'invalid_or_expired',
    'anon não conseguiu executar request_portal_account_setup: a segunda via do portal está fechada');

  const r2 = await anon.rpc('consume_onboarding_token', { p_token: TOKEN_INEXISTENTE });
  assert.ok(r2.error, 'token inexistente deveria levantar dentro da função');
  assert.match(String(r2.error.message), /Invalid or expired/i,
    `anon foi barrado ANTES do corpo de consume_onboarding_token (o portal não abriria): ${r2.error.message}`);

  // ── CONTROLE NEGATIVO: estas três não podem ser alcançadas por anon.
  const barradas = [
    ['detect_unlinked_accounts', {}],
    ['_mask_email', { p_email: 'alguem@example.com' }],
    ['_portal_member_for_application', { p_application_id: '00000000-0000-0000-0000-000000000000' }],
  ];
  for (const [fn, args] of barradas) {
    const { data, error } = await anon.rpc(fn, args);
    assert.ok(error, `anon executou ${fn}, que deveria estar fora do seu alcance (devolveu ${JSON.stringify(data)})`);
    // E barrado por PERMISSÃO, não por a função ter sumido: as duas dão erro, e só uma é o que
    // este teste afirma.
    assert.doesNotMatch(String(error.message), /does not exist|not find the function/i,
      `${fn} não existe mais — o teste estaria verde pela ausência, não pelo portão: ${error.message}`);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// F — o detector do ponto cego roda e não vaza endereço
// ═══════════════════════════════════════════════════════════════════════════
test('F · detect_unlinked_accounts responde e devolve e-mail mascarado', { skip: !dbGated && skipMsg }, async () => {
  const c = sb();
  const { data, error } = await c.rpc('detect_unlinked_accounts');
  assert.ifError(error);
  assert.equal(data.success, true);
  assert.equal(typeof data.count, 'number', 'o detector tem de devolver uma contagem');
  assert.ok(Array.isArray(data.members), 'o detector tem de devolver a lista');
  assert.equal(data.members.length, data.count,
    'a contagem e a lista discordam: uma das duas está medindo outra coisa');

  for (const m of data.members) {
    assert.ok(!('email' in m), 'o detector devolveu o endereço cru; só a máscara pode sair');
    if (m.masked_email) {
      assert.match(m.masked_email, /\*\*\*/, `'${m.masked_email}' não parece mascarado`);
    }
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// G — estático: o componente mudou de fonte, e o ramo de aprovado tem ação própria
// ═══════════════════════════════════════════════════════════════════════════
test('G · o portal resolve rótulo pelo catálogo e o aprovado tem caminho para dentro', () => {
  // ⚠️ Comentarios MASCARADOS antes de medir. Sem isso o guard casa o proprio comentario que
  // descreve o anti-padrao: este arquivo cita `open-auth-modal` para explicar por que ele NAO
  // deve existir, e a asserção de ausencia reprovaria o codigo correto. Medido nesta sessao.
  const src = maskJsComments(readFileSync(COMPONENTE, 'utf8'));

  // O defeito A na sua forma literal: resolver o rótulo SÓ pelo JSONB por ciclo.
  assert.doesNotMatch(
    src,
    /const\s+def\s*=\s*cycle\.onboarding_steps\.find[\s\S]{0,120}?def\?\.label\s*\?\?\s*step\.step_key/,
    'o componente voltou a resolver o rótulo apenas pelo JSONB por ciclo (o defeito A)',
  );

  assert.match(src, /payload\.step_catalog/,
    'o componente não lê `step_catalog`: os rótulos do catálogo não chegam à tela');

  // A ORDEM importa, e é o que a correção é: catálogo primeiro, JSONB depois, chave por último.
  const iCatalogo = src.indexOf('stepCatalog.get(stepKey)');
  const iCiclo = src.indexOf('cycle.onboarding_steps?.find');
  assert.ok(iCatalogo > 0, 'a consulta ao catálogo sumiu do resolvedor de rótulo');
  assert.ok(iCiclo > 0, 'o JSONB por ciclo deixou de ser consultado: um ciclo com rótulo próprio pararia de ser respeitado');
  assert.ok(iCatalogo < iCiclo,
    'o JSONB por ciclo é consultado ANTES do catálogo: com o JSONB vazio isso não muda nada hoje, mas inverte a fonte de verdade');

  // #1997: a identidade do evento que o AuthModal escuta é `open-auth` em `document`. Um
  // `open-auth-modal` em `window` não abre nada — foi medido, e era o botão de /workspace.
  assert.match(src, /document\.dispatchEvent\(new CustomEvent\('open-auth'\)\)/,
    'o portal não abre o modal de login pela identidade que o AuthModal escuta');
  assert.doesNotMatch(src, /'open-auth-modal'/,
    'voltou a identidade de evento que a #1997 mediu como inerte');

  assert.match(src, /request_portal_account_setup/,
    'a segunda via (link por e-mail) não está ligada no componente');

  // O ramo de aprovado não pode voltar a ser um link solitário para trás do login.
  const iAprovado = src.indexOf('{isApproved && (');
  assert.ok(iAprovado > 0, 'o ramo isApproved sumiu');
  const bloco = src.slice(iAprovado, iAprovado + 4000);
  assert.match(bloco, /onClick=\{openLogin\}/,
    'o ramo de aprovado não oferece o login ali mesmo: volta a ser e-mail → portal → botão → muro');
});
