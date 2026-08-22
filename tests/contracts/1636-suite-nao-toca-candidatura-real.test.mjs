// tests/contracts/1636-suite-nao-toca-candidatura-real.test.mjs
//
// #1636 — a suíte de contrato escolhia candidatura REAL de produção e escrevia nela.
//
// O ACHADO, medido em 08/08/2026 contra produção. Os testes DB-aware do arco do gate de entrevista
// escolhiam o alvo por PREDICADO sobre a base viva (`.eq('status','interview_pending')`, ciclo
// aberto / ciclo fechado) e chamavam `_issue_interview_booking_token_core` com `p_caller_id: null`.
// Como a metade (b) do #1594 exige que a linha de recusa COMMITE, cada `npm test` sedimentava
// recusas permanentes em prod:
//
//   gate_attempts ............ 663 linhas, 627 sem ator (94,6%)
//   candidaturas reais tocadas ... 13, e 3 delas concentravam 489 linhas
//   tokens de agendamento vivos .. 4, emitidos pelo run 31144140275 do CI (07/08 03:23–03:31),
//                                  `access_count` 0, válidos até 21/08, apontando para gente real
//
// A CORREÇÃO é `tests/helpers/selection-fixtures.mjs`: cada forma que o gate exige passa a ser
// construída como candidatura sintética (e-mail em domínio reservado por RFC 2606, convenção do
// #1437) e apagada no fim, com o CASCADE levando `gate_attempts`, entrevistas e avaliações junto.
//
// ESTE ARQUIVO É A TRAVA, e ela tem de existir em duas camadas porque as duas falham de jeitos
// diferentes:
//
//   Camada A (estática, SEMPRE roda) — guard de CLASSE sobre o código da suíte: quem exerce o
//     caminho de escrita do gate TEM de passar pelo helper. Um guard que enumerasse os 4 arquivos
//     conhecidos não impediria o quinto de nascer, e o quinto é exatamente como esta issue nasceu.
//
//   Camada B (DB-aware) — o EFEITO em produção. Camada A fica verde se alguém importar o helper e
//     mesmo assim varrer prod; só o banco sabe onde a linha caiu.
//
// ⚠️ POR QUE A CAMADA A NÃO PODE SER UM `grep`. Sete arquivos da suíte contêm a string
// `sb.rpc('selection_rescue_stuck_interview'` DENTRO DE UM LITERAL, porque inspecionam o código do
// admin e do MCP procurando por ela. Um grep os acusaria todos, e um guard que grita em trabalho
// correto é desligado na terceira vez. O scanner abaixo distingue CHAMADA de MENÇÃO, e os dois
// controles (positivo e negativo) provam que ele distingue — sem eles, um scanner quebrado que não
// acha nada passaria por vacuidade.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { RESERVED_DOMAIN, GRACE_MINUTES } from '../helpers/selection-fixtures.mjs';
import { rpcCallsIn } from '../helpers/rpc-call-scanner.mjs';
import { skipDataInvariant } from '../helpers/data-invariant-gate.mjs';

const DIR = 'tests/contracts';
const HELPER = 'selection-fixtures.mjs';

/**
 * Superfície de ESCRITA do gate de entrevista: RPCs que emitem token, despacham convite, queimam
 * cap ou movem status. Ler (`resolve_interview_booking_url`, `_audit_function_source`) não entra —
 * leitura não deixa rastro em candidatura nenhuma.
 */
const RPCS_QUE_ESCREVEM = [
  '_issue_interview_booking_token_core',
  '_dispatch_interview_booking_link',
  'notify_selection_cutoff_approved',
  'selection_rescue_unbooked_invite',
  'selection_rescue_stuck_interview',
  'schedule_interview',
  'mark_interview_status',
  'request_interview_reschedule',
  'request_interview_booking_link_via_token',
  'process_pending_reschedule_nudges',
  '_selection_unbooked_rescue_cron',
  '_selection_stuck_scheduled_rescue_cron',
  '_selection_cutoff_pending_cron',
];

/** Escrita direta na tabela de candidaturas (o 1613 muta `status` por UPDATE, sem RPC). */
function escreveDiretoEmCandidaturas(src) {
  return /\.from\(\s*['"]selection_applications['"]\s*\)[\s\S]{0,400}?\.(update|insert|upsert|delete)\(/.test(src);
}

/**
 * O arquivo declara que o alvo dele é SINTÉTICO — de um dos dois jeitos aceitos:
 *
 *   a) importa o helper compartilhado (`selection-fixtures.mjs`), ou
 *   b) monta a própria fixture num domínio reservado por RFC 2606 / RFC 6761.
 *
 * A alternativa (b) não é tolerância a duplicação: o `p693-dual-track-autolink-fkfix` precisa de
 * DUAS candidaturas com o MESMO e-mail e papéis diferentes (é assim que o gatilho de auto-link
 * dispara), e o helper compartilhado gera e-mail único por fixture justamente para manter aquele
 * gatilho inerte. Forçá-lo a usar o helper quebraria o teste. O que a regra cobra é a INVARIANTE
 * (o alvo não alcança pessoa nenhuma), não o módulo.
 *
 * ⚠️ Camada A é tripwire estático: ela vê o arquivo DECLARAR disciplina, não o efeito. Quem mede o
 * efeito é a camada B, contra o banco.
 */
function declaraAlvoSintetico(src) {
  return src.includes(HELPER) || /['"][^'"]*@(?:[^'"@]*\.)?(?:example\.(?:com|org|net)|test|invalid|localhost)['"]/i.test(src);
}

const ARQUIVOS = readdirSync(DIR)
  .filter((f) => f.endsWith('.test.mjs'))
  .map((f) => ({ nome: f, src: readFileSync(join(DIR, f), 'utf8') }));

/** Arquivos que EXERCEM o caminho de escrita do gate contra o banco. */
const EXERCEM = ARQUIVOS.filter(({ src }) => {
  const chamadas = rpcCallsIn(src);
  return RPCS_QUE_ESCREVEM.some((r) => chamadas.has(r)) || escreveDiretoEmCandidaturas(src);
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada A — o predicado tem dentes, e a regra vale para a CLASSE
// ─────────────────────────────────────────────────────────────────────────────
describe('#1636 A — quem exerce o gate passa pela fixture sintética', () => {
  it('CONTROLE POSITIVO: o scanner acha as chamadas reais dos 4 arquivos do arco', () => {
    // Sem isto, um scanner quebrado (que não achasse nada) deixaria a regra abaixo verde por
    // vacuidade — o modo de falha exato que o #1689 chamou de guard inerte.
    const esperado = {
      '1594-1595-gate-refusal-audit-and-reschedule-door.test.mjs': [
        '_issue_interview_booking_token_core', 'notify_selection_cutoff_approved',
      ],
      '1598-1599-rescue-refusal-and-cron-error-capture.test.mjs': [
        '_issue_interview_booking_token_core', 'selection_rescue_unbooked_invite',
      ],
      '1640-ia-fora-da-precondicao-do-convite.test.mjs': ['_issue_interview_booking_token_core'],
    };
    for (const [nome, rpcs] of Object.entries(esperado)) {
      const arq = ARQUIVOS.find((a) => a.nome === nome);
      assert.ok(arq, `arquivo do arco sumiu: ${nome}`);
      const achadas = rpcCallsIn(arq.src);
      for (const r of rpcs) {
        assert.ok(achadas.has(r), `o scanner não achou a chamada de ${r} em ${nome}`);
      }
    }
    // e o 1613 é pego pela OUTRA metade do predicado (ele muta por UPDATE, não por RPC).
    const t1613 = ARQUIVOS.find((a) => a.nome === '1613-interview-stage-entry-gate.test.mjs');
    assert.ok(t1613, 'arquivo do #1613 sumiu');
    assert.ok(
      escreveDiretoEmCandidaturas(t1613.src),
      'o predicado de escrita direta não vê o UPDATE de status do #1613',
    );
  });

  it('CONTROLE NEGATIVO: MENCIONAR a RPC dentro de um literal não conta como chamar', () => {
    // Estes três inspecionam o código do admin/MCP procurando a string. Um grep os acusaria, e
    // um guard que fica vermelho em trabalho correto é desligado.
    for (const nome of [
      'cutoff-approved-modal-button.test.mjs',
      'p283-411-w3-mcp-exposure.test.mjs',
      'cutoff-rpc-not-orphan.test.mjs',
    ]) {
      const arq = ARQUIVOS.find((a) => a.nome === nome);
      assert.ok(arq, `arquivo de controle sumiu: ${nome}`);
      assert.ok(
        arq.src.includes('sb.rpc('),
        `${nome} deveria CONTER a string — sem isso o controle não controla nada`,
      );
      const achadas = rpcCallsIn(arq.src);
      const falsos = RPCS_QUE_ESCREVEM.filter((r) => achadas.has(r));
      assert.deepEqual(
        falsos, [],
        `${nome} só MENCIONA a RPC num literal, e o scanner leu como chamada: ${falsos.join(', ')}`,
      );
    }
  });

  it('CONTROLE: a segunda via (fixture própria em domínio reservado) é reconhecida', () => {
    // Sem este controle o ramo (b) da regra vira código morto e apodrece calado. O `p693` é o
    // exemplo vivo: fixture própria, `@example.invalid`, e nenhuma linha do helper.
    const p693 = ARQUIVOS.find((a) => a.nome === 'p693-dual-track-autolink-fkfix.test.mjs');
    assert.ok(p693, 'o exemplo da segunda via sumiu — reapontar o controle');
    assert.ok(!p693.src.includes(HELPER), 'o p693 passou a usar o helper: este controle perdeu o objeto');
    assert.ok(declaraAlvoSintetico(p693.src), 'a segunda via deixou de ser reconhecida');

    // E o predicado precisa REPROVAR quem não declara nada: um teste inventado que escreve numa
    // candidatura sem dizer que ela é sintética.
    assert.ok(
      !declaraAlvoSintetico("await sb.from('selection_applications').update({ status: 'x' }).eq('id', alvo.id)"),
      'o predicado aceita um arquivo que não declara alvo sintético — não tem dentes',
    );
  });

  it('REGRA: todo arquivo que exerce o caminho de escrita usa alvo sintético', () => {
    assert.ok(
      EXERCEM.length >= 5,
      `esperava ao menos os 5 arquivos que escrevem, achei ${EXERCEM.length} — o predicado ficou cego`,
    );
    const semFixture = EXERCEM.filter((a) => !declaraAlvoSintetico(a.src)).map((a) => a.nome);
    assert.deepEqual(
      semFixture, [],
      'estes escrevem no caminho do gate sem declarar alvo sintético, logo escolhem candidatura ' +
        `real de produção: ${semFixture.join(', ')}`,
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada B — o efeito no banco
// ─────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SRK ? createClient(SUPABASE_URL, SRK, { auth: { persistSession: false } }) : null;

/**
 * Instante a partir do qual a regra vale. As 627 linhas anteriores são o incidente que motivou a
 * issue e ficam como história — apagá-las seria falsificar auditoria de tentativas que de fato
 * aconteceram. O que se afirma é a DIREÇÃO: daqui para a frente, nenhuma linha nova.
 */
const CUTOFF = '2026-08-09T00:00:00Z';

/**
 * Operações MANUAIS de GP, conhecidas e autorizadas, que produzem a mesma digital que este guard
 * caça. Não são regressão da suíte: são despachos reais decididos por uma pessoa.
 *
 * Por que um allowlist por ID e não um CUTOFF novo: mover o cutoff cegaria o guard para a janela
 * inteira desde 09/08, e o valor dele está justamente em vigiar essa janela. Um ID nomeado deixa o
 * guard ver tudo e ignorar só o evento que já foi explicado.
 *
 * Por que não um discriminador genérico: a operação manual grava `dispatch_source='cron'` no
 * metadata igual ao cron de verdade — aceitar isso como prova faria o guard passar a tolerar
 * QUALQUER chamada via service_role, que é exatamente o que ele existe para pegar. O cron real se
 * distingue por carimbar também a EXECUÇÃO (`selection.%cron_run%`, 197 linhas), e a chamada
 * manual não carimba.
 *
 * ⚠️ Uma entrada aqui é dívida, não isenção: enquanto `selection_rescue_unbooked_invite` não tiver
 * superfície (#1586), a única porta para despachar é o service_role, e toda operação manual vai
 * cair aqui. A saída é a tela do #1586, com autor autenticado — não o crescimento desta lista.
 */
const OPERACOES_MANUAIS_CONHECIDAS = new Set([
  // 14/08/2026 02:26:19Z — despacho de convite de agendamento decidido pelo PM na sessão do #1587,
  // para tirar a instrumentação da onda D (#1590) do vácuo: até então o log tinha 94 linhas e ZERO
  // instrumentadas, e nenhum número do funil podia ser publicado sem uma linha real. Chamado por
  // `selection_rescue_unbooked_invite` via REST/service_role, que é o caminho do cron, porque a
  // RPC não tem superfície (#1586). O e-mail foi enviado a um candidato real que esperava o
  // convite desde 04/08. Auditado em `admin_audit_log` como `selection.unbooked_invite_rescued`.
  '4b99b6dc-2eb3-450e-9448-3d78ca00ed32',

  // 20/08/2026 02:39:24Z, 02:39:38Z e 03:10:33Z — TRÊS tentativas de emitir o convite de
  // agendamento para a MESMA candidatura, feitas pelo PM por REST/service_role (a única porta
  // enquanto a RPC não tiver superfície, #1586 — daí o `caller_id` nulo).
  //
  // ⚠️ O PM declarou em 20/08 que o convite foi ERRO: não era para convidar sem o peer review
  // completo. Esta entrada NÃO é o registro de uma operação endossada, é o registro de uma
  // tentativa equivocada que o gate barrou. Fica aqui com essa leitura, de propósito.
  //
  // As três foram RECUSADAS pelo próprio gate (`P0002` / `GATE_NO_PEER_REVIEW`, `eval_count: 0`):
  // nenhum token foi emitido e nenhum e-mail saiu. O que elas registram é o gate FUNCIONANDO
  // exatamente como projetado, contra uma pressão de processo — a candidatura estava (e segue)
  // com ZERO avaliações de qualquer tipo.
  //
  // Contexto que o PM registrou junto: dispensar o gate por pressão de kickoff ou pedido de
  // patrocinador aconteceu em julho e está DESCONTINUADO por decisão dele. O fluxo estruturado
  // (2 avaliações antes do convite) é o caminho, e o gate é quem o sustenta.
  //
  // Descartada a hipótese que este guard nomeia na mensagem de falha ("algum teste voltou a
  // escolher alvo por predicado"). Três medições a derrubam: (a) a RPC resolve por
  // `id = p_application_id` estrito, sem re-resolver alvo, então o id real foi passado de
  // propósito; (b) os testes que batem nesta RPC e afirmam `GATE_NO_PEER_REVIEW` (#1640, #1594)
  // usam fixture `@example.com`; (c) re-executada a suíte INTEIRA em 20/08 04:12Z, nenhuma linha
  // nova apareceu. Se fosse teste, toda execução somaria uma.
  '6b68d5f8-f82f-4a81-8130-3f4596fd20cb',
  'ffefc7ba-48d8-48c1-9716-63ec3934c823',
  '62d63724-8bee-41ed-a8ea-4cefba297469',

  // 20/08/2026 11:50:38Z — QUARTA tentativa, mesma candidatura, mesma recusa
  // (`GATE_NO_PEER_REVIEW`). Posterior às três acima e anterior ao momento em que o PM registrou
  // a decisão de descontinuar a prática. Mesmo desfecho: recusada, sem token e sem e-mail.
  //
  // ⚠️ SINAL, não rotina: esta lista saiu de 1 para 5 entradas em UM dia, e as 4 últimas são a
  // mesma operação repetida contra a mesma candidatura. Isso não é o guard sendo chato, é a
  // ausência de superfície autenticada (#1586) transformando cada decisão manual em dívida de
  // teste. Enquanto o #1586 não existir, esta lista cresce a cada tentativa.
  'c5c2b7aa-e556-4f05-99fe-17c9f9522a93',

  // 21/08/2026 14:18:47Z — QUINTA tentativa, MESMA candidatura, MESMA recusa
  // (`P0002` / `GATE_NO_PEER_REVIEW`, `eval_count: 0`, `bypass_requested: false`). Nenhum token
  // emitido e nenhum e-mail enviado, como nas quatro anteriores.
  //
  // ⚠️ ESTA É A PRIMEIRA POSTERIOR À DECISÃO. As quatro acima são todas de 20/08, e foi em 20/08
  // que o PM registrou que dispensar o gate por pressão de prazo é prática DESCONTINUADA. Esta é
  // do dia seguinte. A lista deixou de ser o retrato de um dia ruim e virou série: 1 → 5 → 6.
  // O que ela mede continua sendo o mesmo: enquanto a RPC não tiver superfície autenticada
  // (#1586), toda decisão manual entra por service_role e vira dívida de teste.
  //
  // Medido ao vivo em 21/08: a candidatura segue com ZERO avaliações de qualquer tipo — o mesmo
  // estado que motivou as quatro recusas anteriores —, 0 tokens de agendamento vivos e status
  // `interview_pending`. O gate fez exatamente o que existe para fazer, pela quinta vez.
  //
  // A hipótese que a mensagem de falha deste guard nomeia ("algum teste voltou a escolher alvo por
  // predicado sobre produção") foi DESCARTADA por três medições desta sessão:
  //   (a) o arco inteiro do gate (71 testes, 5 arquivos, incluindo os que afirmam
  //       `GATE_NO_PEER_REVIEW`) rodou contra produção e `gate_attempts` ficou em 697 linhas antes
  //       e depois, com as MESMAS 9 sem ator pós-cutoff dos dois lados. Teste que varresse
  //       produção somaria linha PERMANENTE, como as 627 do incidente que abriu esta issue;
  //   (b) a Camada A passou inteira: todo arquivo que exerce o caminho de escrita declara alvo
  //       sintético;
  //   (c) `admin_audit_log` não tem NENHUMA linha na janela de ±10min — nem carimbo de cron, nem
  //       ação de ator. E o guard não está cego: os outros três sem-ator pós-cutoff que NÃO estão
  //       nesta lista (14/08 15:00, 17/08 15:30 ×2) TÊM carimbo (`stuck_rescue_cron_run`,
  //       `unbooked_rescue_cron_run`) e por isso ele nunca os acusou.
  //
  // 📌 Ao investigar a próxima: o guard reporta `application_id` na mensagem de falha, e esta
  // lista guarda `gate_attempts.id`. São colunas diferentes. "O ID que falhou não está na lista"
  // NÃO prova ofensor novo — cruze pelas duas chaves antes de concluir qualquer coisa.
  'ec7336f2-8c04-4a44-b1fc-794c83bd435c',
]);

// A2: a Camada B le LINHAS DE PRODUCAO, entao um despacho manual legitimo do PM a reprova em
// TODA branch. Foi o que congelou a fila por 5h22m54s em 21/08. Ela sai do portao required e
// passa a rodar no `invariants-check` (diario, estrito, nao-required), onde pode acusar sem
// travar merge de ninguem. A Camada A ACIMA continua no portao: ela e funcao do diff.
describe('#1636 B — nenhuma escrita nova de teste cai em candidatura real', {
  skip: skipDataInvariant(!!sb, 'sem SUPABASE_URL + SERVICE_ROLE_KEY'),
}, () => {
  it('depois do cutoff, tentativa de gate sem ator só existe se o CRON a explicar', async () => {
    // O cron de resgate roda como `service_role` e produz a MESMA digital da suíte (`caller_id`
    // nulo). O que separa os dois é o carimbo de execução no log de auditoria no mesmo instante —
    // foi assim que a análise de 08/08 separou 8 tokens do cron de 4 da suíte.
    //
    // Medido em 08/08 sobre 30 dias: 632 linhas sem ator, 4 explicadas pelo cron, 628 sem
    // explicação. O discriminador não é teórico.
    //
    // A correlação é feita aqui e não numa RPC nova de propósito: DDL aplicada em produção antes
    // do merge serializa todos os PRs abertos (#1633), e um guard não vale esse preço.
    const { data: tentativas, error } = await sb
      .from('gate_attempts')
      .select('id, application_id, attempted_at, rpc_name')
      .is('caller_id', null)
      .gte('attempted_at', CUTOFF);
    assert.ifError(error);

    // As operações manuais já explicadas saem ANTES da correlação com o cron: elas não têm carimbo
    // de execução para casar, e é justamente por isso que estão nomeadas uma a uma.
    const novas = (tentativas ?? []).filter((t) => !OPERACOES_MANUAIS_CONHECIDAS.has(t.id));
    if (!novas.length) return;   // nenhuma linha nova: é o estado esperado depois da correção

    const { data: crons, error: e1 } = await sb
      .from('admin_audit_log')
      .select('created_at')
      .like('action', 'selection.%cron_run%')
      .gte('created_at', new Date(Date.parse(CUTOFF) - 120_000).toISOString());
    assert.ifError(e1);
    const carimbos = (crons ?? []).map((c) => Date.parse(c.created_at));

    const JANELA_MS = 60_000;
    const semExplicacao = novas.filter(
      (t) => !carimbos.some((c) => Math.abs(c - Date.parse(t.attempted_at)) <= JANELA_MS),
    );
    if (!semExplicacao.length) return;

    // Sobrou tentativa sem ator e sem cron. Ela é aceitável APENAS se caiu em fixture sintética
    // (uma corrida simultânea pode ter a sua viva); em candidatura real, é a regressão.
    const ids = [...new Set(semExplicacao.map((t) => t.application_id))];
    const { data: apps, error: e2 } = await sb
      .from('selection_applications')
      .select('id, email')
      .in('id', ids);
    assert.ifError(e2);

    const porId = new Map((apps ?? []).map((a) => [a.id, a.email]));
    const ofensores = ids
      .filter((id) => !RESERVED_DOMAIN.test(porId.get(id) ?? ''))
      .map((id) => `${id} (${semExplicacao.filter((t) => t.application_id === id).length} linhas)`);

    assert.deepEqual(
      ofensores, [],
      'candidatura REAL recebeu tentativa de gate sem ator e sem cron que a explique — ' +
        'algum teste voltou a escolher alvo por predicado sobre produção',
    );
  });

  it('o allowlist de operações manuais fica em sincronia (sem entradas extintas)', async () => {
    // Ratchet: uma entrada que não corresponde mais a nenhuma linha viva vira ruído e, pior,
    // esconde que o guard deixou de vigiar aquele caso. O padrão é o dos allowlists do Q-C /
    // Phase C — a lista só encolhe.
    const ids = [...OPERACOES_MANUAIS_CONHECIDAS];
    if (!ids.length) return;
    const { data, error } = await sb.from('gate_attempts').select('id').in('id', ids);
    assert.ifError(error);
    const vivos = new Set((data ?? []).map((r) => r.id));
    assert.deepEqual(
      ids.filter((id) => !vivos.has(id)), [],
      'entrada do allowlist de operações manuais não corresponde a nenhuma linha viva em '
      + '`gate_attempts` — remova-a: enquanto ela ficar, o guard carrega uma isenção sem objeto.',
    );
  });

  it('nenhuma fixture sintética PERSISTE além da janela de graça', async () => {
    // A invariante é a do #1437: o problema não é a fixture existir (enquanto o teste roda, ela
    // existe), é ela SOBREVIVER. Runs de CI compartilham o banco de produção, então uma corrida
    // simultânea legitimamente tem a sua viva — daí a janela em vez de checagem de existência.
    const limite = new Date(Date.now() - GRACE_MINUTES * 60_000).toISOString();
    const { data, error } = await sb
      .from('selection_applications')
      .select('id, applicant_name, email, created_at, status')
      .lt('created_at', limite);
    assert.ifError(error);

    const sobreviventes = (data ?? []).filter((r) => RESERVED_DOMAIN.test(r.email ?? ''));
    // Itera e reporta cada uma: uma checagem existencial passa assim que a primeira parece ok.
    assert.deepEqual(
      sobreviventes.map((r) => `${r.id} ${r.email} (criada ${r.created_at}, status ${r.status})`),
      [],
      `fixture sintética viva há mais de ${GRACE_MINUTES}min — a limpeza do teste falhou, e a ` +
        'linha está em produção. Apagar é o conserto pontual; entender por que o `cleanup` não ' +
        'rodou é o conserto.',
    );
  });

  it('nenhum token de agendamento SOBREVIVE à limpeza da fixture', async () => {
    // `onboarding_tokens` NÃO tem FK para a candidatura: o vínculo é polimórfico
    // (`source_type='pmi_application'` + `source_id`), logo o CASCADE não o alcança. Foi
    // exatamente esse buraco que deixou 4 tokens vivos em 07/08 sem ninguém notar. Aqui ele é
    // asserção, não confiança no `cleanup`.
    //
    // ⚠️ A JANELA DE GRAÇA É OBRIGATÓRIA AQUI, e por um motivo diferente do teste anterior. O
    // caminho de PASSAGEM (#1640) emite um token e só o apaga no `after` do bloco: durante alguns
    // segundos existe, legitimamente, um token vivo sobre uma fixture viva. Sem a janela, este
    // guard ficaria vermelho porque OUTRA corrida estava fazendo o trabalho dela — e um guard que
    // acusa trabalho correto é desligado.
    const limite = Date.now() - GRACE_MINUTES * 60_000;
    const { data: tokens, error } = await sb
      .from('onboarding_tokens')
      .select('token, source_id, source_type, issued_at, expires_at')
      .contains('scopes', ['interview_booking'])
      .gt('expires_at', new Date().toISOString())
      .gte('issued_at', CUTOFF)
      .lt('issued_at', new Date(limite).toISOString());
    assert.ifError(error);
    if (!tokens?.length) return;

    const ids = [...new Set(tokens.map((t) => t.source_id).filter(Boolean))];
    const { data: apps, error: e2 } = await sb
      .from('selection_applications')
      .select('id, email')
      .in('id', ids);
    assert.ifError(e2);

    const emailPorId = new Map((apps ?? []).map((a) => [a.id, a.email]));
    const suspeitos = tokens.filter((t) => {
      const email = emailPorId.get(t.source_id);
      // (a) a candidatura ainda existe e é sintética → o `cleanup` não apagou o token
      if (email !== undefined) return RESERVED_DOMAIN.test(email ?? '');
      // (b) a candidatura SUMIU e o token ficou → o órfão que o vínculo polimórfico permite.
      //     Medido em 08/08: 0 órfãos em 17 tokens, então a linha de base é limpa.
      return true;
    });

    assert.deepEqual(
      suspeitos.map((t) => `${t.token.slice(0, 8)}… source=${t.source_id ?? 'nulo'} expira ${t.expires_at}`),
      [],
      'token de agendamento vivo sobreviveu à limpeza da fixture (ou ficou órfão de uma ' +
        'candidatura apagada) — é o buraco do vínculo polimórfico que deixou 4 tokens vivos em 07/08',
    );
  });
});
