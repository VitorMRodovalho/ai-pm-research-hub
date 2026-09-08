// tests/contracts/2188-sonda-de-agenda-antes-do-despacho.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2188 fase 1 — o despacho registra o que a agenda mostrava.
 *
 * SINTOMA (04/09/2026): um candidato relatou que "não chega o e-mail" do agendamento. Os e-mails
 * chegavam. Ele clicou uma vez, em 31/07, caiu numa agenda SEM NENHUM HORÁRIO, e nunca mais
 * clicou — sete convites depois. 132 despachos produziram 6 reservas.
 *
 * O DEFEITO: `_dispatch_interview_booking_link` resolve o destino, emite o token, grava a linha e
 * dispara o e-mail sem em nenhum ponto perguntar se a agenda escolhida tem horário livre. O
 * despacho é sucesso em TODAS as superfícies (gate_passed, token emitido, email.delivered, linha
 * instrumented) enquanto o candidato vê porta fechada.
 *
 * O QUE ESTA FASE FECHA, e é o item 3 da issue: o log guardava a URL, não o ESTADO dela. Sem isso
 * nenhuma investigação reconstrói o que o candidato viu — a limitação que a própria apuração de
 * 04/09 registrou ("a disponibilidade foi medida HOJE").
 *
 * O QUE ELA NÃO FECHA, e o arquivo não finge que fecha: o rodízio ainda NÃO pula agenda vazia
 * (item 1), o despacho ainda NÃO falha de forma visível (item 2) e não há alerta operacional
 * (item 4). Os três dependem do dado que esta fase começa a produzir.
 *
 * A DISTINÇÃO QUE O ARQUIVO MAIS DEFENDE: `ok = false` (a sonda não conseguiu ler) e
 * `days_open = 0` (a agenda está fechada) NÃO são a mesma coisa. Confundi-las na fase 2 excluiria
 * um avaliador do rodízio por causa de uma falha de rede. Por isso o despacho só lê sondagem `ok`,
 * e um `agenda_days_open` nulo significa "não sabemos", nunca "estava fechada".
 *
 * Cross-ref: #2188, #1590 (ondas B/C/D — rodízio, blackouts, log de despacho), #1595, #2130/#2129
 * (mesma família: o sistema envia e não confere o outro lado).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const capDispatch = () => latestFunctionCapture(ROOT, '_dispatch_interview_booking_link');
const capRecord = () => latestFunctionCapture(ROOT, 'record_interview_agenda_probe');

/**
 * A onda inteira, lida pelo nome — a tabela, as políticas e os GRANT/REVOKE não são função e não
 * têm captura por `latestFunctionCapture`.
 *
 * ⚠️ São QUATRO arquivos, não um: a DDL saiu em quatro `apply_migration` (duas delas correção de
 * erro cometido na própria aplicação), e o guard ADR-0097 exige um `.sql` por tracking row. Ler
 * só o primeiro deixaria este arquivo afirmando sobre um recorte e ficando verde por ausência —
 * foi o que aconteceu quando a onda foi dividida, e este guard reprovou, que era o esperado.
 */
function migracaoDaOnda() {
  const arquivos = readdirSync(MIGRATIONS).filter((x) => /^20260908\d{6}_2188_/.test(x)).sort();
  // Piso explícito: se a onda encolher, o denominador encolhe junto e as asserções abaixo passariam
  // a valer sobre menos texto sem ninguém perceber.
  assert.ok(arquivos.length >= 4,
    `esperava os 4 arquivos da onda #2188, achei ${arquivos.length}: ${JSON.stringify(arquivos)}`);
  return arquivos.map((f) => readFileSync(join(MIGRATIONS, f), 'utf8')).join('\n');
}

/**
 * Violações do desenho do despacho. Lista vazia = saudável.
 * Serve ao corpo real E ao adulterado, que é o que torna a injeção de defeito significativa.
 */
function violacoesDespacho(corpo) {
  const v = [];

  // O ponto inteiro da fase: as duas colunas entram no INSERT do log.
  if (!/agenda_days_open,\s*agenda_probed_at/.test(corpo)) {
    v.push('o INSERT do log não grava agenda_days_open e agenda_probed_at');
  }

  // SÓ sondagem que conseguiu ler. Sem este filtro, uma sonda cega (ok=false, days_open NULL)
  // seria lida como estado da agenda.
  if (!/FROM public\.interview_agenda_probes pr[\s\S]{0,120}WHERE pr\.booking_url = v_url AND pr\.ok/.test(corpo)) {
    v.push('a leitura da sonda não filtra por ok — sonda cega viraria estado da agenda');
  }

  // A mais RECENTE, senão a primeira sondagem da história responde para sempre.
  if (!/ORDER BY pr\.probed_at DESC[\s\S]{0,40}LIMIT 1/.test(corpo)) {
    v.push('a leitura da sonda não pega a sondagem mais recente');
  }

  // A ordem: ler a sonda DEPOIS do INSERT gravaria nulo em toda linha.
  const iLeitura = corpo.indexOf('FROM public.interview_agenda_probes pr');
  const iInsert = corpo.indexOf('INSERT INTO public.selection_dispatch_url_log');
  if (!(iLeitura > 0 && iInsert > iLeitura)) {
    v.push('a leitura da sonda não precede o INSERT do log');
  }

  // A sonda é diagnóstico, não portão: esta fase NÃO pode ter passado a barrar despacho.
  // Se um dia barrar, é a fase 2 e este guard tem de ser reescrito de propósito, não por acidente.
  if (/v_agenda_days_open\s*=\s*0[\s\S]{0,120}RETURN/.test(corpo)) {
    v.push('o despacho passou a barrar por agenda vazia — isso é a fase 2, e muda o contrato');
  }

  // Controles negativos: o que as ondas anteriores garantiram continua de pé.
  if (!/superseded_at = now\(\)/.test(corpo)) {
    v.push('a aposentadoria da oferta anterior (#1590 onda D) saiu do corpo');
  }
  const iSupersede = corpo.indexOf('superseded_at = now()');
  if (!(iSupersede > 0 && iInsert > iSupersede)) {
    v.push('o supersede deixou de preceder o INSERT — apagaria a linha nova');
  }
  if (!/md5\(v_token\)/.test(corpo)) {
    v.push('o log voltou a guardar o token em vez do hash (#1590 onda D)');
  }
  if (!/'GATE_REFUSED'/.test(corpo)) {
    v.push('a recusa de gate deixou de ser devolvida sem levantar (#1594/#1595)');
  }
  if (!/'selection\.routing_fell_back_to_cycle'/.test(corpo)) {
    v.push('o evento de desvio para a agenda institucional (#1590 onda B) saiu do corpo');
  }
  return v;
}

/** Violações do desenho da escrita da sonda. */
function violacoesRecord(corpo) {
  const v = [];

  // Uma sondagem que afirma ter medido tem de dizer o que mediu.
  if (!/IF p_ok AND p_days_open IS NULL THEN[\s\S]{0,120}error/.test(corpo)) {
    v.push('ok=true sem days_open é aceito — a linha afirma ter medido e não diz o quê');
  }
  // Dono e ciclo são resolvidos AQUI: aceitá-los do chamador permite atribuir a sondagem ao
  // avaliador errado, e quem renderiza sabe a URL, não a quem ela pertence.
  if (/p_member_id|p_cycle_id/.test(corpo)) {
    v.push('a função aceita member_id/cycle_id do chamador em vez de resolvê-los');
  }
  if (!/FROM public\.selection_committee sc/.test(corpo)) {
    v.push('a resolução do dono não consulta o comitê');
  }
  if (!/nullif\(trim\(COALESCE\(p_booking_url, ''\)\), ''\)/.test(corpo)) {
    v.push('a URL não é normalizada — string vazia viraria linha');
  }
  return v;
}

// ── estático: o despacho ─────────────────────────────────────────────────────────────
test('#2188 static: o despacho lê a sonda antes de gravar, e só a sondagem que conseguiu ler', () => {
  const c = capDispatch();
  assert.ok(c?.body, 'alguma migration captura _dispatch_interview_booking_link');
  assert.deepEqual(violacoesDespacho(c.body), []);
});

test('#2188 static: reprova o despacho que lê sondagem cega como estado da agenda', () => {
  const { body } = capDispatch();
  const adulterado = body.replace('WHERE pr.booking_url = v_url AND pr.ok', 'WHERE pr.booking_url = v_url');
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoesDespacho(adulterado);
  assert.ok(v.some((m) => m.includes('não filtra por ok')),
    `esperava a violação do filtro de ok, e veio: ${JSON.stringify(v)}`);
});

test('#2188 static: reprova o despacho que grava a linha antes de ler a sonda', () => {
  const { body } = capDispatch();
  // Move a leitura para depois do INSERT: o efeito é gravar nulo em toda linha, em silêncio.
  const bloco = body.match(/ {2}SELECT pr\.days_open[\s\S]*?LIMIT 1;\n/);
  assert.ok(bloco, 'o bloco de leitura da sonda mudou de forma; reescreva a injeção');
  const adulterado = body.replace(bloco[0], '') + bloco[0];
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoesDespacho(adulterado);
  assert.ok(v.some((m) => m.includes('não precede o INSERT')),
    `esperava a violação de ordem, e veio: ${JSON.stringify(v)}`);
});

test('#2188 static: reprova o despacho que perde o supersede da oferta anterior', () => {
  const { body } = capDispatch();
  const adulterado = body.replace('superseded_at = now()', 'superseded_at = superseded_at');
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoesDespacho(adulterado);
  assert.ok(v.some((m) => m.includes('#1590 onda D')),
    `esperava a violação do supersede, e veio: ${JSON.stringify(v)}`);
});

// ── estático: a escrita da sonda ─────────────────────────────────────────────────────
test('#2188 static: a escrita da sonda exige número quando afirma ter medido', () => {
  const c = capRecord();
  assert.ok(c?.body, 'alguma migration captura record_interview_agenda_probe');
  assert.deepEqual(violacoesRecord(c.body), []);
});

test('#2188 static: reprova a escrita que aceita ok=true sem days_open', () => {
  const { body } = capRecord();
  const adulterado = body.replace(/IF p_ok AND p_days_open IS NULL THEN/, 'IF false THEN');
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoesRecord(adulterado);
  assert.ok(v.some((m) => m.includes('não diz o quê')),
    `esperava a violação do par ok/days_open, e veio: ${JSON.stringify(v)}`);
});

// ── estático: a superfície da tabela ─────────────────────────────────────────────────
test('#2188 static: a tabela nova nasce fechada, e as funções não nascem com EXECUTE para PUBLIC', () => {
  const sql = migracaoDaOnda();

  assert.match(sql, /ALTER TABLE public\.interview_agenda_probes ENABLE ROW LEVEL SECURITY/,
    'a tabela de sondagens sem RLS');
  assert.match(sql, /CREATE POLICY rpc_only_deny_all ON public\.interview_agenda_probes FOR ALL USING \(false\)/,
    'a tabela ganhou caminho direto: o desenho é RPC-only, como em selection_interviewer_blackouts (#1590 onda B)');

  // `CREATE FUNCTION` nasce com EXECUTE para PUBLIC, E o Supabase concede a `anon` NOMINALMENTE —
  // revogar de PUBLIC não alcança uma concessão nominal. Medido em 08/09: depois do primeiro
  // apply, as duas funções ainda tinham anon. Por isso o REVOKE tem de citar o papel.
  for (const fn of ['record_interview_agenda_probe', 'get_interview_agenda_health']) {
    const re = new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\([^;]*FROM PUBLIC, anon`);
    assert.match(sql, re, `${fn}: o REVOKE não nomeia anon, e FROM PUBLIC sozinho não o alcança`);
  }
  assert.doesNotMatch(sql, /GRANT EXECUTE ON FUNCTION public\.record_interview_agenda_probe[^;]*anon/,
    'a escrita da sonda foi concedida a anon');

  // O leitor existe: sem ele a sonda vira mais um sinal gravado sem consulta (a forma da #2130).
  assert.match(sql, /CREATE OR REPLACE FUNCTION public\.get_interview_agenda_health/,
    'a sonda não tem leitor');
  assert.match(sql, /can_by_member\(v_caller, 'manage_member'\)/,
    'o leitor da saúde das agendas não é escopado por capacidade');

  // O cron não pode bater num 401 quatro vezes ao dia quando o segredo não está configurado.
  assert.match(sql, /COALESCE\(current_setting\('app\.agenda_probe_internal_secret', true\), ''\) <> ''/,
    'o cron dispara mesmo sem o segredo configurado');
});

// ── DB-aware ────────────────────────────────────────────────────────────────────────
test('#2188 db: a tabela existe, as colunas do log existem, e a distinção ok/days_open é representável',
  { skip: dbGated ? false : skipMsg }, async () => {
    const c = sb();

    const { error: eProbe } = await c.from('interview_agenda_probes').select('id').limit(1);
    assert.equal(eProbe, null, `interview_agenda_probes inacessível: ${eProbe?.message}`);

    const { data: log, error: eLog } = await c
      .from('selection_dispatch_url_log')
      .select('id, agenda_days_open, agenda_probed_at')
      .limit(1);
    assert.equal(eLog, null, `as colunas novas do log não existem: ${eLog?.message}`);
    assert.ok(Array.isArray(log), 'consulta ao log não devolveu linhas');
  });

test('#2188 db: sondagem que afirma ter medido sem número é recusada',
  { skip: dbGated ? false : skipMsg }, async () => {
    const c = sb();
    const { data, error } = await c.rpc('record_interview_agenda_probe', {
      p_booking_url: 'https://calendar.app.google/__teste_2188__',
      p_ok: true,
      p_days_open: null,
    });
    assert.equal(error, null, `a RPC levantou em vez de devolver erro de domínio: ${error?.message}`);
    assert.equal(data?.error, 'ok=true requires days_open',
      `esperava a recusa do par ok/days_open, e veio: ${JSON.stringify(data)}`);

    // Controle positivo da MESMA medição: a recusa acima só significa algo se a chamada bem-formada
    // de fato grava. Sem isto, uma RPC quebrada em tudo passaria no teste acima.
    const { data: ok, error: e2 } = await c.rpc('record_interview_agenda_probe', {
      p_booking_url: 'https://calendar.app.google/__teste_2188__',
      p_ok: false,
      p_error: 'controle positivo do contract test #2188',
    });
    assert.equal(e2, null, `a chamada bem-formada falhou: ${e2?.message}`);
    assert.equal(ok?.success, true, `esperava gravação, e veio: ${JSON.stringify(ok)}`);

    // Limpa a linha do controle: a tabela é lida pela fase 2, e sujeira de teste com URL que não
    // existe no comitê viraria "agenda sem dono" numa apuração futura.
    if (ok?.probe_id) await c.from('interview_agenda_probes').delete().eq('id', ok.probe_id);
  });

// As DUAS grafias, e a ordem importa pouco: o CI exporta `SUPABASE_ANON_KEY` e o `.env` local usa
// `PUBLIC_SUPABASE_ANON_KEY`. Gatear só na segunda faria este teste SKIPAR em silêncio no CI, que
// é onde ele mais precisa rodar — e há um guard (#1518) que reprova exatamente esse descuido.
const ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;
const anonGated = !!(SUPABASE_URL && ANON_KEY);

test('#2188 db: anon NAO escreve sondagem — exercendo o privilégio, não lendo a linha do REVOKE',
  { skip: anonGated ? false : 'Skipped: SUPABASE_ANON_KEY (ou PUBLIC_SUPABASE_ANON_KEY) required' }, async () => {
    // O guard #883 afirmou por MESES a LINHA de um REVOKE enquanto o privilégio real era o oposto,
    // e nesta própria onda o `FROM PUBLIC` deixou `anon` com EXECUTE. Texto de migration não é
    // privilégio: o único jeito honesto de afirmar isso é chamando como anon.
    const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
    const r = await anon.rpc('record_interview_agenda_probe', {
      p_booking_url: 'https://calendar.app.google/__anon_nao_deveria_gravar__',
    });
    assert.notEqual(r.error, null,
      'anon executou record_interview_agenda_probe: uma sondagem forjada (ok=true, days_open=0) ' +
      'é exatamente o que a fase 2 leria para tirar um avaliador do rodízio');

    // Controle positivo na MESMA medição: a recusa acima só significa "barrado por privilégio" se
    // o mesmo cliente anon consegue falar com o PostgREST. Sem isto, uma URL errada ou uma chave
    // inválida produziria o mesmo erro e leria como segurança.
    const controle = await anon.rpc('get_public_platform_stats');
    assert.equal(controle.error, null,
      `o cliente anon não fala com o PostgREST, então a recusa acima não prova nada: ${controle.error?.message}`);
  });

test('#2188 db: nenhuma linha antiga do log finge ter sido medida',
  { skip: dbGated ? false : skipMsg }, async () => {
    const c = sb();
    // `agenda_days_open` nulo = não havia sondagem. O que NÃO pode existir é linha com número
    // gravado e sem carimbo de quando aquilo foi medido: um número sem data é um número velho
    // que ninguém consegue datar.
    const { data, error } = await c
      .from('selection_dispatch_url_log')
      .select('id, agenda_days_open, agenda_probed_at')
      .not('agenda_days_open', 'is', null)
      .is('agenda_probed_at', null);
    assert.equal(error, null, `consulta falhou: ${error?.message}`);
    assert.deepEqual(data, [], 'há despacho com contagem de agenda sem a data da sondagem');
  });
