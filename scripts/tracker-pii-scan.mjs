#!/usr/bin/env node
// Varredura agendada de dado pessoal no tracker PUBLICO deste repositorio (condicao 3 da decisao do GP de manter
// o repo publico, 10/10/2026).
//
// O QUE ELA LE, e por que o historico de edicao e obrigatorio: editar o corpo nao apaga a revisao, e quem abre
// "editado" ve o texto anterior. Uma varredura so de corpos pode relatar zero com o dado a um clique.
//
// Fontes: titulo e corpo de issue e de PR, comentario de issue e de PR, corpo de review, comentario de review, e o
// historico de edicao COMPLETO de todo no que ja foi editado (`lastEditedAt`), paginado de 100 em 100. Fora: o
// historico de TITULO, que o GitHub nao expoe em UserContentEdit (so o titulo atual e varrido), e Discussions, que
// estao desligadas no repo; se forem ligadas, a execucao FALHA dizendo que ha fonte nao coberta.
//
// SAIDA: o dado NUNCA sai daqui. O log do Actions de repo publico e publico, entao o log leva so o estado do
// controle e quantos nos e revisoes foram varridos. Nem a contagem de achados, nem SE houve achado: o fim da
// execucao escreve a mesma linha e sai com o mesmo codigo com aviso ou sem aviso, porque a escolha entre duas
// linhas ja diria a quem le o log que existe algo novo. O relatorio, com contagem e links, vai por notificacao da
// plataforma a quem tem `manage_platform`. O estado do que ja foi avisado mora no `admin_audit_log`, como hash do
// no e da revisao, nunca o valor.
//
// CONTROLES, todos antes de relatar, e cada um capaz de dizer nao:
//   - do DETECTOR: um texto sintetico passa pela MESMA funcao de deteccao. Se nao for pego, a execucao falha antes
//     de varrer: zero com o detector quebrado e o pior resultado possivel, porque certifica;
//   - da COLETA: o numero de issues e de PRs coletados tem de alcancar o `totalCount` do repositorio, e todo no
//     editado tem de devolver exatamente o `totalCount` das suas revisoes. Coleta parcial falha, nunca relata;
//   - da ENTREGA: depois de avisar, conta as notificacoes criadas. Se nenhuma nasceu (destinatario que silenciou o
//     tipo, por exemplo), falha e NAO grava o estado, para avisar de novo na proxima.
//
// Uso:
//   node scripts/tracker-pii-scan.mjs              (Actions: GITHUB_TOKEN, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
//   node scripts/tracker-pii-scan.mjs --dry-run    (local: so contagens no terminal; nao notifica nem grava)
//
// Guard: tests/contracts/tracker-pii-scan.test.mjs.
import { createHash } from 'node:crypto';

// ── Detector ──────────────────────────────────────────────────────────────────────────────────────────────────

// E-mail PESSOAL = dominio de consumo. Endereco institucional fica fora de proposito (pedido da decisao de 10/10).
// A lista e incompleta por construcao: provedor regional que nao esta aqui nao e pego. Os provedores globais
// valem em qualquer pais (`outlook.pt`, `yahoo.es`) pela regra de baixo.
export const DOMINIOS_DE_CONSUMO = new Set([
  'gmail.com', 'googlemail.com', 'icloud.com', 'me.com', 'mac.com', 'protonmail.com', 'proton.me', 'pm.me',
  'mail.com', 'zoho.com', 'uol.com.br', 'bol.com.br', 'terra.com.br', 'ig.com.br', 'globo.com', 'globomail.com',
  'r7.com',
]);
const PROVEDOR_GLOBAL = /^(?:gmail|hotmail|outlook|live|msn|yahoo|ymail|aol|gmx|yandex|icloud)\.(?:com?\.)?[a-z]{2,3}$/;

// Quantificadores LIMITADOS (64 no local, 63 por rotulo, 8 rotulos): com `+` sem teto, um texto longo sem '@'
// custa tempo quadratico, e qualquer conta que comente numa issue publica poderia cegar o robo estourando o job.
const RE_EMAIL = /(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]{1,64}@((?:[A-Za-z0-9-]{1,63}\.){1,8}[A-Za-z]{2,24})(?![A-Za-z0-9-])/g;
const LOCAL_DE_SISTEMA = /^(?:no-?reply|do-?not-?reply|donotreply|noreply\+.*|mailer-daemon|postmaster)$/i;

export function emailsPessoais(texto) {
  const achados = [];
  for (const m of texto.matchAll(RE_EMAIL)) {
    const local = m[0].slice(0, m[0].indexOf('@'));
    const dominio = m[1].toLowerCase();
    if (LOCAL_DE_SISTEMA.test(local)) continue;
    if (/(^|\.)(example\.(com|org|net)|invalid|test|example|localhost|local)$/.test(dominio)) continue;
    if (dominio.endsWith('users.noreply.github.com')) continue;
    if (!DOMINIOS_DE_CONSUMO.has(dominio) && !PROVEDOR_GLOBAL.test(dominio)) continue;
    achados.push(m.index);
  }
  return achados;
}

// Separador de telefone: espaco, ponto, hifen e os tracos que editores de texto poem no lugar do hifen.
const S = '[\\s.\\-\\u2013\\u2014]';
// Telefone FORMATADO: o separador ou o prefixo e o que distingue de um numero qualquer.
const RE_TELEFONE_FORMATADO = [
  new RegExp(`\\+55${S}?\\(?[1-9]{2}\\)?${S}?9?\\d{4}${S}?\\d{4}(?!\\d)`, 'g'),                 // +55 (62) 99999-9999
  new RegExp(`\\(\\s?[1-9]{2}\\s?\\)${S}?(?:9${S}?)?\\d{4}${S}?\\d{4}(?!\\d)`, 'g'),             // (62) 9 9999-9999
  new RegExp(`(?<![\\d/.-])[1-9]{2}${S}9${S}?\\d{4}${S}\\d{4}(?!\\d)`, 'g'),                    // 62 99999-9999
  new RegExp(`(?<![\\d/.-])[1-9]{2}${S}9\\d{8}(?!\\d)`, 'g'),                                   // 62 999999999
  new RegExp(`(?<![\\w+])\\+(?!55)[1-9]\\d{0,2}(?:${S}\\(?\\d{1,4}\\)?){2,4}(?!\\d)`, 'g'),     // +351 912 345 678
  /(?<![\w+])\+(?!55)[1-9]\d{9,13}(?!\d)/g,                                                     // +351912345678
];
// Telefone SEM formatacao: celular BR de 11 digitos (DDD + 9 + 8), ou 13 com o 55. So conta COM CONTEXTO, porque
// sozinho ele colide com CPF, id de run, timestamp e contador.
const RE_TELEFONE_CRU = /(?<![\w.-])(?:55)?[1-9]{2}9\d{8}(?![\w-])/g;
const CONTEXTO_DE_TELEFONE = /\b(?:tel|telefone|fone|cel|celular|whats|whatsapp|zap|phone|mobile|contato|contact)\b|wa\.me|api\.whatsapp/i;
// Linha de LISTA, e nao linha de TABELA: medido em 10/10, as duas linhas de tabela que casavam eram celulas de
// identificador numerico, nenhuma um telefone. Tabela fica so com contexto de palavra.
const LINHA_DE_LISTA = /^\s*(?:[-*+]|\d+[.)])\s/;

function palavraEm(texto, inicio, fim) {
  let a = inicio;
  let b = fim;
  while (a > 0 && !/\s/.test(texto[a - 1])) a--;
  while (b < texto.length && !/\s/.test(texto[b])) b++;
  return texto.slice(a, b);
}

// Numero dentro de URL (exceto link de WhatsApp) nao e telefone. UUID e hash nao precisam de regra propria: as
// bordas das regex (`(?<![\w.-])`, `(?![\w-])`, `(?!\d)`) ja recusam digito colado em letra ou hifen.
const dentroDeUrl = (texto, inicio, fim) => {
  const palavra = palavraEm(texto, inicio, fim);
  return /https?:\/\/|www\./i.test(palavra) && !/wa\.me|whatsapp/i.test(palavra);
};
// "run 123..." / "job 123..." so exclui o numero CRU: a palavra "job" perto de um telefone formatado ("vaga (job),
// ligue (62) ...") e conversa comum, e o formato ja diz que e telefone.
const depoisDeRun = (texto, inicio) =>
  /\b(?:run|runs|job|jobs|run_id|attempt)\b[^\n]{0,20}$/i.test(texto.slice(Math.max(0, inicio - 25), inicio));

export function telefones(texto, { cru = true } = {}) {
  // Um mesmo numero casa mais de um padrao ("+55 (62) ..." casa o primeiro e o segundo): conta por TRECHO, e o
  // trecho que sobrepoe um ja contado nao conta de novo.
  const trechos = [];
  const sobrepoe = (a, b) => trechos.some(([x, y]) => a < y && x < b);
  for (const re of RE_TELEFONE_FORMATADO) {
    for (const m of texto.matchAll(re)) {
      const fim = m.index + m[0].length;
      const digitos = m[0].replace(/\D/g, '').length;
      if (digitos < 10 || digitos > 15) continue;
      if (sobrepoe(m.index, fim) || dentroDeUrl(texto, m.index, fim)) continue;
      trechos.push([m.index, fim]);
    }
  }
  const formatados = trechos.map(([a]) => a);
  const crus = [];
  if (cru) {
    for (const m of texto.matchAll(RE_TELEFONE_CRU)) {
      const fim = m.index + m[0].length;
      if (sobrepoe(m.index, fim) || dentroDeUrl(texto, m.index, fim) || depoisDeRun(texto, m.index)) continue;
      const inicioDaLinha = texto.lastIndexOf('\n', m.index) + 1;
      const antes = texto.slice(Math.max(inicioDaLinha, m.index - 40), m.index);
      const linha = texto.slice(inicioDaLinha, m.index);
      if (CONTEXTO_DE_TELEFONE.test(antes) || LINHA_DE_LISTA.test(linha)) crus.push(m.index);
    }
  }
  return { formatados, crus };
}

/** Contagens por tipo num texto. E a MESMA funcao que julga o tracker e o texto sintetico do controle. */
export function detectar(texto, opcoes) {
  if (!texto) return { email: 0, telefone: 0, telefoneCru: 0 };
  const t = telefones(texto, opcoes);
  return { email: emailsPessoais(texto).length, telefone: t.formatados.length, telefoneCru: t.crus.length };
}

// O texto sintetico do controle positivo. Montado em tempo de execucao para nao deixar um endereco literal no
// repositorio (o scan de PII do pre-commit o barraria, e com razao). Numeros reservados: 0000 no assinante.
export function textoDeControle() {
  const arroba = '@';
  const email = ['controle', 'sintetico'].join('.') + arroba + ['gmail', 'com'].join('.');
  return [
    `Contato do voluntario: ${email}`,
    'Telefone: (62) 90000-0000',
    'whats 62900000000',
    'International: +351 900 000 000',
    // Negativos: tem de continuar invisiveis.
    `Bot: noreply${arroba}github.com, exemplo${arroba}example.com`,
    'run 12345678901 em https://github.com/o/r/actions/runs/62900000000',
    'id 3f2504e0-4f89-11d3-9a0c-0305e82c3301, sha 62900000000abcdef',
    'versao 20261010120000 e contador 62900000000 sem contexto',
  ].join('\n');
}
export const ESPERADO_NO_CONTROLE = { email: 1, telefone: 2, telefoneCru: 1 };

export function controlePositivo(detector = detectar) {
  const obtido = detector(textoDeControle());
  const ok = Object.entries(ESPERADO_NO_CONTROLE).every(([k, v]) => obtido[k] === v);
  return { ok, obtido };
}

export function impressao(...partes) {
  return createHash('sha256').update(partes.join(':')).digest('hex');
}

// ── Coleta (GraphQL) ──────────────────────────────────────────────────────────────────────────────────────────

const [OWNER, REPO] = (process.env.GITHUB_REPOSITORY || 'VitorMRodovalho/ai-pm-research-hub').split('/');
let custo = 0;
export const custoGraphql = () => custo;

/** Erro com codigo e SEM mensagem de terceiro: o catch so imprime o codigo. */
const falha = (code) => Object.assign(new Error(code), { code });

// Espera entre tentativas. Limite secundario do GitHub pede ~1 min; `retry-after` vence quando vier.
export const ESPERAS_MS = [15000, 30000, 60000, 120000];

async function gql(query, variables = {}) {
  for (let tentativa = 0; ; tentativa++) {
    const r = await fetch('https://api.github.com/graphql', {
      method: 'POST',
      headers: { Authorization: `bearer ${process.env.GITHUB_TOKEN}`, 'Content-Type': 'application/json' },
      // O custo vai junto em toda consulta: e ele que diz se a varredura cabe no limite do GITHUB_TOKEN.
      body: JSON.stringify({ query: query.replace(/\}\s*$/, ' rateLimit { cost remaining } }'), variables }),
    });
    const j = await r.json().catch(() => ({}));
    // NOT_FOUND num lote de `nodes(ids)` e no apagado no meio da varredura: o no some (null) e o resto vale.
    const errosReais = (j.errors ?? []).filter((e) => e.type !== 'NOT_FOUND');
    if (r.ok && j.data && errosReais.length === 0) {
      custo += j.data.rateLimit?.cost ?? 0;
      return j.data;
    }
    if (tentativa >= ESPERAS_MS.length) throw falha(`graphql_http_${r.status}_${errosReais[0]?.type ?? 'sem_tipo'}`);
    const retryAfter = Number(r.headers?.get?.('retry-after')) * 1000;
    await new Promise((res) => setTimeout(res, retryAfter > 0 ? retryAfter : ESPERAS_MS[tentativa]));
  }
}

const CAMPOS = '__typename id url body lastEditedAt';
const PAGINA = 'pageInfo { hasNextPage endCursor }';

/** Percorre uma conexao paginada e entrega cada no. */
async function* paginar(montar, extrair) {
  let after = null;
  do {
    const conexao = extrair(await gql(montar(), { after }));
    for (const n of conexao.nodes) yield n;
    after = conexao.pageInfo.hasNextPage ? conexao.pageInfo.endCursor : null;
  } while (after);
}

/** O resto de uma conexao aninhada, a partir do cursor em que a pagina de dentro parou. */
async function resto(tipo, id, campo, conexao, subcampos = CAMPOS) {
  const nos = [...conexao.nodes];
  let after = conexao.pageInfo.hasNextPage ? conexao.pageInfo.endCursor : null;
  while (after) {
    const data = await gql(`query($id: ID!, $after: String) { node(id: $id) { ... on ${tipo} { ${campo}(first: 100, after: $after) { nodes { ${subcampos} } ${PAGINA} } } } }`, { id, after });
    const c = data.node?.[campo];
    if (!c) break; // o pai sumiu no meio da varredura
    nos.push(...c.nodes);
    after = c.pageInfo.hasNextPage ? c.pageInfo.endCursor : null;
  }
  return nos;
}

async function coletarConteudo() {
  const nos = [];
  let issues = 0;
  let prs = 0;
  for await (const i of paginar(
    () => `query($after: String) { repository(owner: "${OWNER}", name: "${REPO}") { issues(first: 50, after: $after) { nodes { ${CAMPOS} title comments(first: 100) { nodes { ${CAMPOS} } ${PAGINA} } } ${PAGINA} } } }`,
    (d) => d.repository.issues,
  )) {
    issues++;
    nos.push({ ...i, classe: 'issue' });
    for (const c of await resto('Issue', i.id, 'comments', i.comments)) nos.push({ ...c, classe: 'comentario' });
  }
  const REVIEW = `${CAMPOS} comments(first: 30) { nodes { ${CAMPOS} } ${PAGINA} }`;
  for await (const p of paginar(
    () => `query($after: String) { repository(owner: "${OWNER}", name: "${REPO}") { pullRequests(first: 25, after: $after) { nodes { ${CAMPOS} title comments(first: 50) { nodes { ${CAMPOS} } ${PAGINA} } reviews(first: 30) { nodes { ${REVIEW} } ${PAGINA} } } ${PAGINA} } } }`,
    (d) => d.repository.pullRequests,
  )) {
    prs++;
    nos.push({ ...p, classe: 'pr' });
    for (const c of await resto('PullRequest', p.id, 'comments', p.comments)) nos.push({ ...c, classe: 'comentario' });
    for (const r of await resto('PullRequest', p.id, 'reviews', p.reviews, REVIEW)) {
      nos.push({ __typename: r.__typename, id: r.id, url: r.url, body: r.body, lastEditedAt: r.lastEditedAt, classe: 'review' });
      for (const c of await resto('PullRequestReview', r.id, 'comments', r.comments)) nos.push({ ...c, classe: 'comentario_de_review' });
    }
  }
  return { nos, issues, prs };
}

const EDICOES = `userContentEdits(first: 100) { totalCount nodes { id diff deletedAt } ${PAGINA} }`;

/** Historico COMPLETO de edicao dos nos editados. Devolve {noId: [{id, diff, deletedAt}]} e os nos que sumiram. */
async function coletarRevisoes(nos) {
  const editados = nos.filter((n) => n.lastEditedAt);
  const revisoes = new Map();
  let sumiram = 0;
  const TIPOS = [...new Set(editados.map((n) => n.__typename))];
  for (let i = 0; i < editados.length; i += 40) {
    const lote = editados.slice(i, i + 40);
    const frag = TIPOS.map((t) => `... on ${t} { id ${EDICOES} }`).join(' ');
    const data = await gql(`query($ids: [ID!]!) { nodes(ids: $ids) { ${frag} } }`, { ids: lote.map((n) => n.id) });
    for (const [k, n] of data.nodes.entries()) {
      if (!n?.id) { sumiram++; continue; }
      const todas = await resto(lote[k].__typename, n.id, 'userContentEdits', n.userContentEdits, 'id diff deletedAt');
      // Controle da COLETA: o historico tem de vir inteiro. A pagina de 100 sem paginar perdia justamente as
      // revisoes mais ANTIGAS, que e onde costuma estar o texto original.
      if (todas.length !== n.userContentEdits.totalCount || todas.length === 0) throw falha('historico_incompleto');
      revisoes.set(n.id, todas);
    }
  }
  return { editados: editados.length, sumiram, revisoes };
}

/** Coleta tudo e so devolve se a coleta estiver completa. */
export async function coletar() {
  const tot = await gql(`query { repository(owner: "${OWNER}", name: "${REPO}") { hasDiscussionsEnabled issues { totalCount } pullRequests { totalCount } } }`);
  if (tot.repository.hasDiscussionsEnabled) throw falha('fonte_nao_coberta_discussions');
  const { nos, issues, prs } = await coletarConteudo();
  // Controle da COLETA: paginacao que parou no meio relataria zero sobre o que nao leu.
  if (issues < tot.repository.issues.totalCount || prs < tot.repository.pullRequests.totalCount) throw falha('coleta_incompleta');
  const r = await coletarRevisoes(nos);
  return { nos, ...r };
}

// ── Julgamento ────────────────────────────────────────────────────────────────────────────────────────────────

const mesmoTexto = (a, b) => (a ?? '').trim() === (b ?? '').trim();

/**
 * Achados por no e por revisao. A impressao e do no + revisao + tipo, nunca do valor. O corpo atual de um no
 * editado ja e a revisao mais nova do historico, entao so entra como 'atual' quando nao estiver la (senao o mesmo
 * achado sairia duas vezes). Revisao apagada (`deletedAt`) nao entra: o GitHub ja nao a mostra.
 * Limite conhecido: quando um corpo nunca editado e editado depois, o achado dele passa de 'atual' para o id da
 * revisao e e avisado mais uma vez. Repetir uma vez e o lado seguro.
 */
export function julgar(nos, revisoes, detector = detectar) {
  const achados = [];
  for (const n of nos) {
    const edicoes = (revisoes.get(n.id) ?? []).filter((e) => !e.deletedAt);
    const fontes = [];
    if (n.title) fontes.push({ rev: 'titulo', texto: n.title, historico: false });
    if (!edicoes.some((e) => mesmoTexto(e.diff, n.body))) fontes.push({ rev: 'atual', texto: n.body, historico: false });
    for (const e of edicoes) fontes.push({ rev: e.id, texto: e.diff, historico: !mesmoTexto(e.diff, n.body) });
    for (const f of fontes) {
      const d = detector(f.texto || '');
      for (const tipo of ['email', 'telefone', 'telefoneCru']) {
        if (d[tipo] > 0) achados.push({ no: n.id, url: n.url, classe: n.classe, historico: f.historico, tipo, impressao: impressao(n.id, f.rev, tipo) });
      }
    }
  }
  return achados;
}

/** O corpo do aviso: so contagem e links. Nenhum trecho do texto achado entra aqui. */
export function corpoDoAviso(novos) {
  const porTipo = (t) => novos.filter((a) => a.tipo === t).length;
  const urls = [...new Set(novos.map((a) => a.url))];
  const noHistorico = new Set(novos.filter((a) => a.historico).map((a) => a.url)).size;
  return [
    `${urls.length} item(ns) do tracker público com possível dado pessoal novo desde o último aviso.`,
    `Achados: e-mail pessoal ${porTipo('email')}, telefone formatado ${porTipo('telefone')}, telefone sem formatação com contexto ${porTipo('telefoneCru')}.`,
    `${noHistorico} deles aparecem em revisão antiga do histórico de edição, que continua visível em "editado".`,
    'Itens:',
    ...urls.map((u) => `- ${u}`),
  ].join('\n');
}

// ── Execucao ──────────────────────────────────────────────────────────────────────────────────────────────────

let etapa = 'inicio';
// A MESMA linha nos dois finais (com aviso e sem aviso): ver SAIDA no cabecalho.
const FIM = 'relatorio: concluido';

/** Le todas as linhas de uma consulta, de 1000 em 1000: o teto do PostgREST corta em silencio. */
async function todas(consulta) {
  const linhas = [];
  for (let de = 0; ; de += 1000) {
    const { data, error } = await consulta().range(de, de + 999);
    if (error) throw falha(`banco_${error.code ?? 'sem_codigo'}`);
    linhas.push(...data);
    if (data.length < 1000) return linhas;
  }
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const controle = controlePositivo();
  if (!controle.ok) {
    console.error('controle positivo FALHOU: o detector nao pegou o texto sintetico. Nada foi relatado.');
    process.exit(1);
  }
  console.log('controle positivo: ok');
  if (!process.env.GITHUB_TOKEN) throw falha('sem_github_token');

  etapa = 'coleta';
  const { nos, editados, sumiram, revisoes } = await coletar();
  const nRevisoes = [...revisoes.values()].reduce((s, r) => s + r.length, 0);
  const achados = julgar(nos, revisoes);
  console.log(`varridos: ${nos.length} nos, ${editados} editados, ${nRevisoes} revisoes, ${sumiram} sumiram; custo GraphQL ${custo}`);

  if (dryRun) {
    // So no terminal local, nunca no Actions: contagens por fonte, sem links nem trechos.
    const conta = (f) => new Set(achados.filter(f).map((a) => a.no)).size;
    console.log(JSON.stringify({
      nos_com_achado: conta(() => true),
      atual: conta((a) => !a.historico),
      historico: conta((a) => a.historico),
      por_tipo: { email: conta((a) => a.tipo === 'email'), telefone: conta((a) => a.tipo === 'telefone'), telefoneCru: conta((a) => a.tipo === 'telefoneCru') },
    }));
    return;
  }

  etapa = 'estado';
  const { createClient } = await import('@supabase/supabase-js');
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const ja = await todas(() => sb.from('admin_audit_log').select('metadata').eq('action', 'tracker_pii.alerted').order('created_at'));
  const avisadas = new Set(ja.flatMap((r) => r.metadata?.impressoes ?? []));
  const novos = achados.filter((a) => !avisadas.has(a.impressao));
  if (novos.length === 0) {
    console.log(FIM);
    return;
  }

  etapa = 'destinatarios';
  // Destinatario: quem gere a plataforma, o mesmo criterio do aviso de falha do Drive (#2454).
  const membros = await todas(() => sb.from('members').select('id').eq('member_status', 'active').not('auth_id', 'is', null).order('id'));
  const gestores = [];
  for (const m of membros) {
    const { data: pode, error } = await sb.rpc('can_by_member', { p_member_id: m.id, p_action: 'manage_platform' });
    if (error) throw falha(`banco_${error.code ?? 'sem_codigo'}`);
    if (pode === true) gestores.push(m.id);
  }
  if (gestores.length === 0) throw falha('sem_destinatario');

  etapa = 'aviso';
  const corpo = corpoDoAviso(novos);
  const desde = new Date(Date.now() - 60000).toISOString();
  for (const id of gestores) {
    const { error } = await sb.rpc('create_notification', {
      p_recipient_id: id,
      p_type: 'tracker_pii_found',
      p_title: 'Possível dado pessoal no tracker público',
      p_body: corpo,
      p_link: '/admin',
    });
    if (error) throw falha(`banco_${error.code ?? 'sem_codigo'}`);
  }
  // Controle da ENTREGA: `create_notification` devolve vazio tambem quando o destinatario silenciou o tipo. Se
  // nenhum aviso nasceu, ninguem foi avisado, e gravar o estado calaria o achado para sempre.
  const { count: entregues, error: e4 } = await sb.from('notifications').select('id', { count: 'exact', head: true })
    .eq('type', 'tracker_pii_found').in('recipient_id', gestores).gte('created_at', desde);
  if (e4) throw falha(`banco_${e4.code ?? 'sem_codigo'}`);
  if (!entregues) throw falha('aviso_nao_entregue');

  etapa = 'gravacao';
  // Grava o estado DEPOIS de avisar: se a gravacao falhar, o pior caso e avisar de novo, nunca calar.
  const { error: e3 } = await sb.from('admin_audit_log').insert({
    action: 'tracker_pii.alerted',
    target_type: 'github_tracker',
    metadata: { impressoes: [...new Set(novos.map((a) => a.impressao))], destinatarios: entregues },
  });
  if (e3) throw falha(`banco_${e3.code ?? 'sem_codigo'}`);
  console.log(FIM);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    // So a ETAPA e o CODIGO, nunca a mensagem: a recusa do banco ecoa a linha ("Failing row contains ..."), e a
    // linha do aviso leva os links. O log e publico.
    console.error(`falhou na etapa ${etapa}: codigo ${e?.code ?? e?.name ?? 'sem_codigo'}`);
    process.exit(1);
  });
}
