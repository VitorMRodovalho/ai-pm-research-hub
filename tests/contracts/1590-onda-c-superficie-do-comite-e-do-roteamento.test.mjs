/**
 * Contract: #1590 onda C — o comite ganha superficie de roteamento.
 *
 * Nas palavras do PM (13/08): entram na tela de selecao presidentes, admin da plataforma, gestao e
 * quem estiver listado no comite — e e no comite que se define quem observa e quem avalia. Isso
 * torna o comite o MECANISMO DE CONTROLE DE ACESSO, e ate esta onda ele so se editava por SQL:
 * `selection_committee.interview_booking_url` decidia 30 dos 30 ultimos despachos de researcher e
 * nao tinha tela nem MCP.
 *
 * Medido em 13/08/2026, ciclo `cycle4-2026`, ANTES da migration:
 *   - 3 avaliadores roteaveis (todos por committee_override) + 4 observadores sem URL
 *   - 94 despachos; 0 linhas em selection_interviewer_blackouts (a onda B subiu a tabela SEM escrita)
 *   - 2 de 87 membros ativos tem manage_member — e as MESMAS 2 tem promote
 *   - o avaliador cuja agenda recebe o candidato nao conseguia cadastrar a propria agenda em lugar
 *     nenhum: a unica tela de URL e /admin/members/[id] (superadmin) e edita o caminho de MENOR
 *     precedencia (members.interview_booking_url)
 *
 * Prova comportamental ao vivo, em transacao abortada (13/08), atuando como cada perfil:
 *   avaliador le o painel                -> ok, can_manage=false, 3 roteaveis
 *   mascara                              -> ve a PROPRIA URL, nao ve a do GP
 *   bloqueia a si mesmo                  -> ok, ativo hoje, self_service=true
 *   depois do bloqueio                   -> 2 roteaveis, motivo ["blocked_window"]
 *   bloqueia OUTRO                       -> recusado (manage_member)
 *   troca a PROPRIA URL                  -> ok
 *   troca a URL do OUTRO                 -> recusado
 *   auto-promocao a lead                 -> recusado (promote)
 *   auto-desligamento / auto-religamento -> permitido / RECUSADO
 *   url `javascript:`                    -> recusada no servidor
 *   clear de bloqueio inexistente        -> mesma mensagem de bloqueio alheio (sem oraculo)
 *   observadora cadastra URL             -> ok, e continua NAO roteavel (role_not_routable)
 *   forasteiro le o painel               -> Unauthorized
 *   GP bloqueia terceiro                 -> ok, self_service=false
 *   picker: bloqueando o escolhido       -> passa ao proximo; comite inteiro -> cycle_fallback;
 *                                           janela so no futuro -> nao bloqueia hoje
 *   nada persistiu apos o ROLLBACK       -> 0 bloqueios, 0 auditorias, 0 URLs de prova
 *
 * Camadas: A estatica sobre a captura da migration, com a INVERSA de cada afirmacao (afirmacao sem
 * inversa fica verde com o mecanismo removido); B o predicado da TELA exercido pelo modulo real,
 * que junto com A fixa "publico do servidor == publico da tela"; A' md5 do corpo VIVO contra a
 * captura; C invariantes ao vivo, read-only.
 *
 * Migration: 20260813181215_1590_onda_c_superficie_do_comite_e_do_roteamento.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody,
} from '../helpers/rpc-body-drift-parser.mjs';
import { canAccessAdminRoute } from '../../src/lib/admin/route-access.ts';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const MIGRATION = '20260813181215_1590_onda_c_superficie_do_comite_e_do_roteamento.sql';

const CHAVES = {
  overview: 'get_selection_routing_overview@p_cycle_id uuid',
  bloquear: 'set_interviewer_routing_block@p_cycle_id uuid, p_member_id uuid, p_starts_on date, p_ends_on date, p_reason text',
  desbloquear: 'clear_interviewer_routing_block@p_block_id uuid',
  comite: 'manage_selection_committee@p_cycle_id uuid, p_action text, p_member_id uuid, p_role text, p_interview_booking_url text, p_can_interview boolean',
};

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function captura(chave) {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(chave);
  assert.ok(cap, `sem captura de migration para ${chave}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === chave);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${chave}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b, #1710). */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

async function rest(caminho, init) {
  return fetch(`${SUPABASE_URL}/rest/v1/${caminho}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      ...(init?.headers ?? {}),
    },
  });
}

// ── A: a captura da migration ────────────────────────────────────────────────────────────

test('#1590C A: o publico da leitura e o publico da TELA, e nao o da RPC vizinha', () => {
  const { body, file } = captura(CHAVES.overview);
  const codigo = achatado(body);

  // Os quatro eixos que a tela declara (route-access.ts): comite do ciclo, sponsor, GP, superadmin.
  assert.match(codigo, /v_is_committee OR v_can_manage OR COALESCE\(v_caller\.is_superadmin, false\) OR \('sponsor' = ANY/,
    `${file}: o publico do servidor deixou de ser o publico declarado na tela`);

  // A INVERSA, que e a licao medida da onda A: espelhar o predicado de `get_selection_dashboard`
  // (`view_internal_analytics` U comite) zerava a coorte de 9 e CRIAVA 6 no sentido inverso — 6
  // chapter_liaison entrariam numa rota de PII de candidato por uma porta que o menu nunca ofereceu.
  assert.doesNotMatch(codigo, /view_internal_analytics/,
    `${file}: o eixo de capacidade voltou; ele abre 6 chapter_liaison que o menu nunca ofereceu`);
});

test('#1590C A: a URL crua so sai para a propria linha e para quem tem manage_member', () => {
  const { body, file } = captura(CHAVES.overview);
  const codigo = achatado(body);

  assert.match(codigo, /'booking_url', CASE WHEN v_can_manage OR sc\.member_id = v_caller\.id/,
    `${file}: a URL de agenda passou a sair para todo o publico do painel`);
  assert.match(codigo, /'committee_url', CASE WHEN v_can_manage OR sc\.member_id = v_caller\.id/,
    `${file}: idem para a URL da linha do comite`);
  assert.match(codigo, /'fallback_url', CASE WHEN v_can_manage/,
    `${file}: a agenda institucional do ciclo e configuracao de GP`);

  // A INVERSA: `has_url` existe justamente para o resto do publico ver "tem agenda / nao tem" SEM
  // receber o link. Se ele sumir, ou a tela perde a informacao ou alguem devolve a URL crua.
  assert.match(codigo, /'has_url', COALESCE\(sc\.interview_booking_url, m\.interview_booking_url\) IS NOT NULL/,
    `${file}: sem has_url a tela so tem duas saidas, e uma delas e vazar o link`);
});

test('#1590C A: o painel NAO promete posicao na fila', () => {
  const { body, file } = captura(CHAVES.overview);
  const codigo = achatado(body);

  // Medido em 13/08: 5 despachos com timestamp IDENTICO (mesma transacao) em 06/08, e o desempate
  // `ORDER BY ... , sc.member_id` mandou 3 deles para o menor member_id. Enquanto isso nao for
  // corrigido, publicar "proximo da fila" e publicar promessa que o codigo nao cumpre.
  assert.doesNotMatch(codigo, /next_in_queue|proximo_da_fila|queue_position/i,
    `${file}: o painel passou a prometer ordem de fila; o desempate do picker ainda concentra despachos`);

  // O que ELE publica sao fatos: contagem e data do ultimo despacho.
  assert.match(codigo, /'dispatch_count', COALESCE\(d\.n, 0\)/, `${file}: sumiu a contagem de despachos`);
  assert.match(codigo, /'last_dispatched_at', d\.last/, `${file}: sumiu a data do ultimo despacho`);
});

test('#1590C A: a contagem usa os filtros do PROPRIO picker, e os totais saem do mesmo json', () => {
  const { body, file } = captura(CHAVES.overview);
  const codigo = achatado(body);

  // Contar por outro recorte publicaria um numero que nao e o que decide o rodizio (#1066).
  assert.match(codigo, /FROM public\.selection_dispatch_url_log l WHERE l\.cycle_id = sc\.cycle_id AND l\.track = 'researcher'/,
    `${file}: a contagem deixou de usar os filtros do lookback do picker`);

  // Duas implementacoes da mesma pergunta divergem (#1710: a metrica dizia 100% e a grade 61%).
  assert.match(codigo, /FROM json_array_elements\(v_members\) e/,
    `${file}: os totais passaram a vir de um segundo predicado em vez do json ja montado`);
});

test('#1590C A: "nao roteavel" diz POR QUE, com as quatro causas', () => {
  const { body, file } = captura(CHAVES.overview);
  const codigo = achatado(body);

  // O NOME do campo tambem e contrato: renomea-lo deixa os quatro motivos no corpo e a tela sem
  // eles. Descoberto por mutacao ao escrever este arquivo — a versao anterior deste teste ficava
  // verde com `not_routable_reasons` renomeado.
  assert.match(codigo, /'not_routable_reasons', \(/,
    `${file}: o campo que a tela le mudou de nome`);

  for (const motivo of ['role_not_routable', 'permanently_off', 'no_booking_url', 'blocked_window']) {
    assert.match(codigo, new RegExp(`'${motivo}'`),
      `${file}: sumiu a causa ${motivo}; um booleano mudo devolve a pessoa ao SQL para descobrir o porque`);
  }

  // E o proprio `routable_now` tem de continuar sendo os TRES eixos + a janela, na mesma ordem
  // logica do picker — senao a tela afirma roteavel para quem o rodizio nao escolhe.
  assert.match(codigo, /sc\.role IN \('evaluator', 'lead'\) AND sc\.can_interview AND COALESCE\(sc\.interview_booking_url, m\.interview_booking_url\) IS NOT NULL AND NOT COALESCE\(blk\.blocked_now, false\)/,
    `${file}: routable_now divergiu do predicado do picker`);
});

test('#1590C A: as escritas de bloqueio gateiam pelo RECURSO, antes de escrever', () => {
  const bloquear = captura(CHAVES.bloquear);
  const codigo = achatado(bloquear.body);

  assert.match(codigo, /IF p_member_id IS DISTINCT FROM v_caller AND NOT v_can_manage THEN/,
    `${bloquear.file}: o gate parou de olhar para o alvo — e a classe do #1728 (622 pares indevidos no #1710)`);

  // O gate tem de vir ANTES de qualquer escrita, e antes do lookup: um gate depois do INSERT nao e
  // gate, e um lookup antes do gate vira oraculo de existencia.
  const iGate = codigo.indexOf('IF p_member_id IS DISTINCT FROM v_caller');
  const iLookup = codigo.indexOf('FROM public.selection_committee sc JOIN public.selection_cycles');
  const iInsert = codigo.indexOf('INSERT INTO public.selection_interviewer_blackouts');
  assert.ok(iGate > -1 && iLookup > iGate && iInsert > iGate,
    `${bloquear.file}: a ordem gate -> lookup -> escrita foi quebrada`);

  // A borda de fuso da onda B vale para a ESCRITA tambem: `starts_on` nulo = hoje LOCAL.
  assert.match(codigo, /v_hoje date := \(now\(\) AT TIME ZONE 'America\/Sao_Paulo'\)::date/,
    `${bloquear.file}: a data de referencia da escrita precisa ser a local (#1727)`);
  assert.doesNotMatch(codigo, /CURRENT_DATE/,
    `${bloquear.file}: CURRENT_DATE e UTC; das 21h a meia-noite ele grava o dia seguinte`);

  assert.match(codigo, /'selection\.routing_block_set'/, `${bloquear.file}: a escrita deixou de ser auditada`);
});

test('#1590C A: desbloquear nao devolve oraculo de existencia, e guarda o historico', () => {
  const { body, file } = captura(CHAVES.desbloquear);
  const codigo = achatado(body);

  // Mensagem UNICA para "nao existe" e "nao e sua": mensagens separadas contam a quem nao passa no
  // gate se aquele id existe.
  assert.match(codigo, /IF NOT FOUND OR \(v_row\.member_id IS DISTINCT FROM v_caller AND NOT v_can_manage\) THEN/,
    `${file}: as duas recusas voltaram a ser distinguiveis`);
  assert.match(codigo, /'Block not found or unauthorized'/, `${file}: a mensagem unica mudou`);

  // A linha some da tabela de ESTADO, entao o historico precisa sobreviver na de HISTORICO.
  const iDelete = codigo.indexOf('DELETE FROM public.selection_interviewer_blackouts');
  const iAudit = codigo.indexOf("'selection.routing_block_cleared'");
  assert.ok(iDelete > -1 && iAudit > iDelete,
    `${file}: apagar sem auditar apaga tambem a memoria de que houve bloqueio`);
  for (const campo of ['starts_on', 'ends_on', 'reason']) {
    assert.match(codigo, new RegExp(`'${campo}', v_row\\.${campo}`),
      `${file}: o metadata perdeu ${campo}; sem a janela inteira o log nao reconstroi o bloqueio`);
  }
});

test('#1590C A: os tres gates do update, e o que cada um impede', () => {
  const { body, file } = captura(CHAVES.comite);
  const codigo = achatado(body);

  // (1) recurso: a propria linha, ou manage_member.
  assert.match(codigo, /IF p_member_id IS DISTINCT FROM v_caller_id AND NOT v_can_manage THEN/,
    `${file}: o update deixou de olhar para o alvo`);
  // (2) papel: so com promote — senao o observador se promove a avaliador e entra no rodizio.
  assert.match(codigo, /IF p_role IS NOT NULL AND p_role IS DISTINCT FROM v_before\.role AND NOT v_can_promote THEN/,
    `${file}: autosservico passou a poder trocar o proprio papel no comite`);
  // (3) religar can_interview: ato de GP. Desligar-se e autosservico.
  assert.match(codigo, /IF p_can_interview IS TRUE AND NOT v_before\.can_interview AND NOT v_can_manage THEN/,
    `${file}: quem foi desligado pelo GP passou a poder se religar`);

  // add/remove NAO mudaram de gate nesta onda.
  assert.match(codigo, /IF p_action = 'add' THEN IF NOT v_can_promote THEN/, `${file}: o gate do add mudou`);
  assert.match(codigo, /ELSIF p_action = 'remove' THEN IF NOT v_can_promote THEN/, `${file}: o gate do remove mudou`);

  // A URL vira href numa tela de admin: `javascript:` escapa de qualquer escape de HTML.
  assert.match(codigo, /v_url !~\* '\^https:\/\/'/, `${file}: a validacao de esquema da URL sumiu`);

  // `p_role` com default 'evaluator' tornaria "nao mandou papel" indistinguivel de "mandou
  // avaliador", e um update de URL rebaixaria um lead em silencio.
  const sql = readFileSync(join(MIGRATIONS_DIR, MIGRATION), 'utf8');
  assert.match(achatado(sql), /p_role text DEFAULT NULL/,
    'p_role voltou a ter default: o update perde a diferenca entre ausente e evaluator');

  assert.match(codigo, /'selection\.committee_routing_updated'/, `${file}: o update deixou de ser auditado`);
  // O log e lido por mais gente que o painel: guarda presenca/ausencia, nunca a URL.
  assert.match(codigo, /'url_before_present'/, `${file}: o log passou a guardar a URL em vez da presenca dela`);
  assert.doesNotMatch(codigo, /'url_before', v_before\.interview_booking_url/,
    `${file}: a URL crua entrou no audit log`);
});

test('#1590C A: a migration revoga o EXECUTE publico das quatro funcoes', () => {
  const sql = achatado(readFileSync(join(MIGRATIONS_DIR, MIGRATION), 'utf8'));

  // `CREATE FUNCTION` concede EXECUTE a PUBLIC por padrao (#1710/#1592), e `manage_selection_committee`
  // — uma RPC de ESCRITA — estava alcancavel por anon antes desta migration (medido em 13/08).
  for (const assinatura of [
    'public.get_selection_routing_overview\\(uuid\\)',
    'public.set_interviewer_routing_block\\(uuid, uuid, date, date, text\\)',
    'public.clear_interviewer_routing_block\\(uuid\\)',
    'public.manage_selection_committee\\(uuid, text, uuid, text, text, boolean\\)',
  ]) {
    assert.match(sql, new RegExp(`REVOKE EXECUTE ON FUNCTION ${assinatura} FROM PUBLIC, anon`),
      `falta o REVOKE de ${assinatura} — a RPC nasce publicada para anon`);
    assert.match(sql, new RegExp(`GRANT EXECUTE ON FUNCTION ${assinatura} TO authenticated, service_role`),
      `falta o GRANT de ${assinatura} — revogar sem conceder deixa a tela sem porta`);
  }
});

// ── B: o predicado da TELA, exercido ─────────────────────────────────────────────────────
//
// A camada A fixa o TEXTO do publico no servidor; esta exerce o predicado da tela sobre os mesmos
// perfis. Juntas afirmam "servidor e tela descrevem o mesmo publico" sem escrever uma terceira
// implementacao do predicado. Perfis reais medidos em 13/08 (nomes fora daqui: o repo e publico).

const AVALIADOR = { operational_role: 'tribe_leader', designations: [], is_superadmin: false, selection_committee_role: 'evaluator' };
const OBSERVADOR = { operational_role: 'chapter_liaison', designations: [], is_superadmin: false, selection_committee_role: 'observer' };
const SPONSOR = { operational_role: 'sponsor', designations: ['sponsor'], is_superadmin: false, selection_committee_role: null };
const GP = { operational_role: 'manager', designations: [], is_superadmin: false, selection_committee_role: 'evaluator' };
const LIAISON_SEM_COMITE = { operational_role: 'chapter_liaison', designations: [], is_superadmin: false, selection_committee_role: null };
const PESQUISADOR = { operational_role: 'researcher', designations: [], is_superadmin: false, selection_committee_role: null };

test('#1590C B: o publico do painel e o publico da pagina, nas duas direcoes', () => {
  for (const [rotulo, perfil] of [['avaliador', AVALIADOR], ['observador', OBSERVADOR], ['sponsor', SPONSOR], ['GP', GP]]) {
    assert.equal(canAccessAdminRoute(perfil, 'admin_selection'), true,
      `${rotulo} deixou de alcancar a pagina que hospeda o painel`);
  }
  // A INVERSA — sem ela o teste fica verde com o gate removido inteiro. Os 6 chapter_liaison FORA do
  // comite sao exatamente a coorte que a onda A decidiu nao abrir; estende-los e decisao do PM.
  for (const [rotulo, perfil] of [['chapter_liaison fora do comite', LIAISON_SEM_COMITE], ['pesquisador', PESQUISADOR]]) {
    assert.equal(canAccessAdminRoute(perfil, 'admin_selection'), false,
      `${rotulo} passou a alcancar a rota de PII de candidato`);
  }
});

// ── D: a superficie, nas duas direcoes ───────────────────────────────────────────────────

const PAGINA = readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8');

test('#1590C D: a aba de comite alcanca as 11, e os controles de comite seguem gateados', () => {
  const aba = PAGINA.match(/<button data-sel-tab="committee"[^>]*>/)?.[0];
  assert.ok(aba, 'a aba de comite sumiu da pagina');

  // A aba PRECISA abrir para quem nao tem manage_member: o autosservico e o motivo da onda. Medido
  // em 13/08: 2 de 87 ativos tem manage_member, e a aba escondida deixava os outros 9 do publico da
  // tela sem porta nenhuma para o proprio cadastro de agenda.
  assert.doesNotMatch(aba, /data-sel-requires/,
    'a aba de comite voltou a exigir manage_member — o avaliador perde a porta da propria agenda');

  // A INVERSA, obrigatoria: abrir a ABA nao pode abrir a ESCRITA de comite. Sem estas duas
  // afirmacoes, remover o gate inteiro deixaria este teste verde.
  assert.match(PAGINA, /<div id="committee-add-card" class="[^"]*" data-sel-requires="manage_member">/,
    'o cartao de ADICIONAR ao comite perdeu o gate de manage_member');
  assert.match(PAGINA, /data-sel-requires="manage_member" data-action="remove-committee"/,
    'o botao de REMOVER do comite perdeu o gate de manage_member');
});

test('#1590C D: a tela nao decide autoridade por conta propria', () => {
  // O `is_self` / `can_manage` vem da RPC, que e quem tambem RECUSA. Um segundo predicado no
  // cliente (por exemplo comparar operational_role) divergiria do servidor no primeiro papel novo.
  assert.match(PAGINA, /const eu = c\.is_self === true;/, 'a linha deixou de usar o is_self do servidor');
  assert.match(PAGINA, /const podeEscrever = eu \|\| podeGerir;/, 'a decisao por linha mudou de forma');
  assert.match(PAGINA, /data\?\.caller\?\.can_manage === true/, 'o can_manage deixou de vir do payload da RPC');

  // Uma leitura so: duas listas da mesma coorte divergem no primeiro campo que uma sabe e a outra nao.
  assert.doesNotMatch(PAGINA, /sb\.rpc\('get_selection_committee'/,
    'a leitura antiga do comite voltou ao lado da nova — duas listas da mesma coorte');
});

test('#1590C D: os rotulos de motivo e de precedencia existem nos 3 dicionarios', () => {
  const CHAVES_I18N = [
    'admin.selection.tabCommitteeRouting', 'admin.selection.routingAxesHint',
    'admin.selection.routingNoQueueNote', 'admin.selection.routingSummary',
    'admin.selection.routingReasonRoleNotRoutable', 'admin.selection.routingReasonPermanentlyOff',
    'admin.selection.routingReasonNoBookingUrl', 'admin.selection.routingReasonBlockedWindow',
    'admin.selection.routingSourceCommitteeOverride', 'admin.selection.routingSourceMemberGlobal',
    'admin.selection.routingPauseHint', 'admin.selection.routingUrlHint',
  ];
  for (const dicionario of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = readFileSync(resolve(ROOT, `src/i18n/${dicionario}.ts`), 'utf8');
    for (const chave of CHAVES_I18N) {
      assert.ok(src.includes(`'${chave}'`), `${dicionario}: falta a chave ${chave}`);
    }
  }
});

// ── A': o corpo VIVO nao derivou da captura ──────────────────────────────────────────────

test("#1590C A': o corpo vivo das quatro funcoes bate com a captura", { skip: dbGated ? false : skipMsg }, async () => {
  const res = await rest('rpc/_audit_list_public_function_bodies', { method: 'POST', body: '{}' });
  assert.equal(res.status, 200, `_audit_list_public_function_bodies devolveu ${res.status}`);
  const linhas = await res.json();
  assert.ok(Array.isArray(linhas) && linhas.length > 0, 'catalogo vivo veio vazio');

  for (const [rotulo, chave] of Object.entries(CHAVES)) {
    const [nome, args] = chave.split('@');
    const viva = linhas.find(l => l.proname === nome && normalizeBody(l.identity_args ?? '') === normalizeBody(args));
    assert.ok(viva, `${rotulo}: ${nome}(${args}) nao encontrada no catalogo vivo`);
    const { bodyHash, file } = captura(chave);
    assert.equal(viva.body_md5, bodyHash,
      `${rotulo}: o corpo VIVO divergiu de ${file}. Alguem aplicou DDL fora de migration, ou a migration foi editada depois de aplicada.`);
  }
});

// ── C: o invariante ao vivo, read-only ───────────────────────────────────────────────────

test('#1590C C: nenhuma das quatro aparece na varredura de alcance anonimo', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await rest('rpc/_audit_secdef_public_grant_drift', { method: 'POST', body: '{}' });
  assert.equal(res.status, 200, `_audit_secdef_public_grant_drift devolveu ${res.status}`);
  const linhas = await res.json();
  const nomes = new Set((Array.isArray(linhas) ? linhas : []).map(l => l.proname));

  for (const chave of Object.values(CHAVES)) {
    const nome = chave.split('@')[0];
    assert.equal(nomes.has(nome), false,
      `${nome} voltou a ser alcancavel por anon/PUBLIC — o REVOKE da migration nao esta valendo`);
  }
});

test('#1590C C: toda URL de agenda cadastrada no comite e https', { skip: dbGated ? false : skipMsg }, async () => {
  const res = await rest('selection_committee?select=cycle_id,member_id,interview_booking_url&interview_booking_url=not.is.null');
  assert.equal(res.status, 200);
  const linhas = await res.json();

  const fora = linhas.filter(l => !/^https:\/\//i.test(String(l.interview_booking_url)));
  assert.deepEqual(fora.map(l => l.member_id), [],
    `URL de agenda fora do esquema https encontrada; ela vira href numa tela de admin`);
});

test('#1590C C: bloqueio so existe para quem esta no comite daquele ciclo', { skip: dbGated ? false : skipMsg }, async () => {
  const [bloqRes, comiteRes] = await Promise.all([
    rest('selection_interviewer_blackouts?select=id,cycle_id,member_id,starts_on,ends_on'),
    rest('selection_committee?select=cycle_id,member_id'),
  ]);
  assert.equal(bloqRes.status, 200);
  assert.equal(comiteRes.status, 200);
  const bloqueios = await bloqRes.json();
  const comite = new Set((await comiteRes.json()).map(c => `${c.cycle_id}|${c.member_id}`));

  // ⚠️ Com zero bloqueios este invariante e VACUO — ausencia de uso, nao imunidade. Ele deixa de
  // ser vacuo na primeira pausa cadastrada pela tela, que e o que esta onda entrega.
  const orfaos = bloqueios.filter(b => !comite.has(`${b.cycle_id}|${b.member_id}`));
  assert.deepEqual(orfaos, [],
    `bloqueio para quem nao esta no comite do ciclo: a escrita foi feita fora da RPC (${JSON.stringify(orfaos.slice(0, 3))})`);

  // A janela invertida ja e barrada pelo CHECK da onda B; aqui o que se afirma e que a RPC nao
  // encontrou um caminho para criar uma (por exemplo aceitando ends_on < starts_on por outro campo).
  const invertidas = bloqueios.filter(b => b.ends_on !== null && b.ends_on < b.starts_on);
  assert.deepEqual(invertidas, [], 'janela invertida: bloqueio que nunca vale e ninguem percebe');
});
