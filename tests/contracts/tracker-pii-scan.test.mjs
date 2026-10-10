// tests/contracts/tracker-pii-scan.test.mjs
/**
 * O robo de PII do tracker publico (condicao 3 da decisao do GP de manter o repo publico, 10/10/2026).
 * Hermetico: nao toca rede nem banco. Exerce o detector, o julgamento e o corpo do aviso pela MESMA funcao que o
 * job usa, e afirma sobre o script e o workflow o que decide o efeito: o controle positivo antes de relatar, o
 * historico de edicao como fonte, o log publico sem dado, o estado sem valor.
 *
 * Os textos de teste sao montados em tempo de execucao: nenhum endereco literal fica no repositorio.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';
import {
  detectar, controlePositivo, julgar, corpoDoAviso, impressao, emailsPessoais, telefones, coletar, noreplyDoGithub,
} from '../../scripts/tracker-pii-scan.mjs';

const SCRIPT = readFileSync('scripts/tracker-pii-scan.mjs', 'utf8');
const WORKFLOW = readFileSync('.github/workflows/tracker-pii-scan.yml', 'utf8');
const maskJs = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/([^:'"`])\/\/[^\n'"`]*$/gm, '$1');
const CODIGO = maskJs(SCRIPT);
const A = '@';
const emailDeConsumo = (local) => `${local}${A}gmail.com`;

function corpoDe(nome) {
  const i = CODIGO.indexOf(`async function ${nome}(`);
  assert.ok(i >= 0, `funcao ${nome} nao achada`);
  const j = CODIGO.indexOf('\n}\n', i);
  return CODIGO.slice(i, j);
}

test('controle positivo: passa com o detector real e REPROVA com um detector quebrado', () => {
  assert.equal(controlePositivo().ok, true, 'o detector real tem de pegar o texto sintetico');
  assert.equal(controlePositivo(() => ({ email: 0, telefone: 0, telefoneCru: 0 })).ok, false,
    'detector que nao acha nada tem de reprovar o controle (senao o zero certifica)');
  assert.equal(controlePositivo((t) => ({ ...detectar(t), telefoneCru: 0 })).ok, false,
    'perder so o telefone sem formatacao tambem reprova');
});

test('o job falha ANTES de varrer quando o controle nao passa', () => {
  const main = corpoDe('main');
  assert.match(main, /const controle = controlePositivo\(\);\s*if \(!controle\.ok\) \{[^}]*process\.exit\(1\);\s*\}/,
    'controle reprovado tem de sair com 1 dentro do proprio if');
  assert.ok(main.indexOf('controlePositivo()') < main.indexOf('await coletar()'),
    'o controle roda antes da coleta, e portanto antes de qualquer relatorio');
});

test('e-mail: so dominio de consumo, com as exclusoes de sistema', () => {
  assert.equal(emailsPessoais(`fale com ${emailDeConsumo('fulano.x')}`).length, 1);
  assert.equal(emailsPessoais(`x${A}outlook.pt e y${A}yahoo.com.ar`).length, 2, 'provedor global vale em qualquer pais');
  assert.equal(emailsPessoais(`(${emailDeConsumo('fulano.x')}).`).length, 1, 'pontuacao em volta nao impede');
  for (const t of [`noreply${A}gmail.com`, `x${A}example.com`, `x${A}empresa.invalid`, `123+bot${A}users.noreply.github.com`, `pessoa${A}pmigo.org.br`]) {
    assert.equal(emailsPessoais(t).length, 0, `nao conta: ${t.replace(/^[^@]+/, '<local>')}`);
  }
});

test('o noreply do GitHub e o dominio EXATO, nao um sufixo', () => {
  assert.equal(noreplyDoGithub('users.noreply.github.com'), true);
  assert.equal(noreplyDoGithub('xusers.noreply.github.com'), false, 'sem o ponto e outro dominio');
  assert.equal(noreplyDoGithub('users.noreply.github.com.evil.com'), false, 'prefixo nao basta');
});

test('telefone: formatado conta; sem formatacao so com contexto ou em lista; exclusoes valem', () => {
  assert.equal(telefones('ligue (62) 90000-0000').formatados.length, 1);
  assert.equal(telefones('ligue +55 (62) 90000-0000').formatados.length, 1, 'um numero, dois padroes: conta uma vez');
  assert.equal(telefones('ligue +55 62 9 0000-0000').formatados.length, 1, 'o 9 separado');
  assert.equal(telefones('ligue (62) 9 0000-0000').formatados.length, 1, 'o 9 separado depois do DDD entre parenteses');
  assert.equal(telefones('ligue 62 900000000').formatados.length, 1, 'DDD separado e o resto colado');
  assert.equal(telefones('ligue (62) 90000\u20130000').formatados.length, 1, 'traco no lugar do hifen');
  assert.equal(telefones('ligue +351900000000').formatados.length, 1, 'internacional sem separador, com o +');
  assert.equal(telefones('para a vaga (job) ligue (62) 90000-0000').formatados.length, 1, 'a palavra job nao apaga o formatado');
  assert.equal(telefones('whats: 62900000000').crus.length, 1, 'sem formatacao com palavra de contexto');
  assert.equal(telefones('- fulano 62900000000').crus.length, 1, 'sem formatacao em item de lista');
  assert.equal(telefones('contador 62900000000 hoje').crus.length, 0, 'sem formatacao e sem contexto nao conta');
  assert.equal(telefones('| 62900000000 | x |').crus.length, 0, 'celula de tabela nao e lista (medido: era identificador)');
  assert.equal(telefones('tel https://x.y/p/62900000000').crus.length, 0, 'dentro de URL nao conta');
  assert.equal(telefones('tel https://wa.me/5562900000000').crus.length, 1, 'link de WhatsApp conta');
  assert.equal(telefones('tel 62900000000abcdef').crus.length, 0, 'digito colado em hash (depois) nao conta');
  assert.equal(telefones('tel abcdef62900000000').crus.length, 0, 'digito colado em hash (antes) nao conta');
  assert.equal(telefones('tel 3f2504e0-62900000000').crus.length, 0, 'pedaco de UUID nao conta');
  assert.equal(telefones('tel 3f25 (62) 90000-0000abc').formatados.length, 1, 'formatado: letra depois nao impede');
  assert.equal(telefones('- run 62900000000').crus.length, 0, 'id de execucao nao conta, mesmo em lista');
  assert.equal(telefones('tel 62900000000', { cru: false }).crus.length, 0, 'a forma crua desliga pela opcao');
});

test('o detector e linear: texto hostil longo nao cega o robo', () => {
  const hostil = ['a'.repeat(200000), 'a.'.repeat(100000), '9'.repeat(200000), `${'a'.repeat(100000)}${A}${'b-'.repeat(50000)}`];
  const t0 = process.hrtime.bigint();
  for (const h of hostil) detectar(h);
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  assert.ok(ms < 2000, `quatro textos de 200 mil caracteres levaram ${ms.toFixed(0)} ms`);
  assert.equal(emailsPessoais(`${'x'.repeat(70)}${A}gmail.com`).length, 0, 'local acima de 64 nao casa (nem por pedaco)');
});

test('julgar: titulo entra; o corpo atual de no editado nao conta duas vezes', () => {
  const no = { id: 'NO2', url: 'u', title: `contato ${emailDeConsumo('t.x')}`, body: 'tel (62) 90000-0000', classe: 'issue' };
  const sem = julgar([no], new Map());
  assert.deepEqual(sem.map((a) => a.tipo).sort(), ['email', 'telefone'], 'titulo e corpo de no nunca editado');
  const com = julgar([no], new Map([['NO2', [{ id: 'E9', diff: 'tel (62) 90000-0000' }]]]));
  assert.equal(com.filter((a) => a.tipo === 'telefone').length, 1, 'o corpo atual ja e a revisao mais nova: um achado, nao dois');
  assert.equal(com.find((a) => a.tipo === 'telefone').historico, false, 'a revisao igual ao corpo atual nao e historico');
});

test('julgar le o HISTORICO DE EDICAO, nao so o corpo, e ignora revisao apagada', () => {
  const no = { id: 'NO1', url: 'https://github.com/o/r/issues/1', body: 'limpo agora', classe: 'issue' };
  const rev = new Map([['NO1', [{ id: 'E1', diff: `antes: ${emailDeConsumo('fulano.x')}` }, { id: 'E2', diff: `tel (62) 90000-0000`, deletedAt: '2026-10-01' }]]]);
  const achados = julgar([no], rev);
  assert.deepEqual(achados.map((a) => [a.tipo, a.historico]), [['email', true]],
    'o e-mail so no historico e achado; a revisao apagada nao entra');
  assert.deepEqual(julgar([no], new Map()), [], 'sem revisoes e com corpo limpo, nada');
});

test('a impressao e do no, da revisao e do tipo, nunca do valor', () => {
  const no = { id: 'NO1', url: 'u', body: '', classe: 'issue' };
  const a = julgar([no], new Map([['NO1', [{ id: 'E1', diff: emailDeConsumo('um.x') }]]]))[0];
  const b = julgar([no], new Map([['NO1', [{ id: 'E1', diff: emailDeConsumo('outro.y') }]]]))[0];
  assert.equal(a.impressao, b.impressao, 'valores diferentes na mesma revisao dao a mesma impressao');
  assert.equal(a.impressao, impressao('NO1', 'E1', 'email'));
});

test('o corpo do aviso leva contagem e link, nunca o dado', () => {
  const email = emailDeConsumo('fulano.x');
  const no = { id: 'NO1', url: 'https://github.com/o/r/issues/7', body: `contato ${email} tel (62) 90000-0000`, classe: 'issue' };
  const corpo = corpoDoAviso(julgar([no], new Map()));
  const itens = corpo.split('\n').filter((l) => l.startsWith('- '));
  assert.deepEqual(itens, ['- https://github.com/o/r/issues/7'], 'o link do item vai, como linha propria da lista');
  assert.ok(!corpo.includes(email) && !/90000/.test(corpo), 'nem o e-mail nem o telefone vao');
  assert.match(corpo, /e-mail pessoal 1, telefone formatado 1/);
});

test('o log publico nao carrega achado: depois do ramo local, so texto fixo', () => {
  const main = corpoDe('main');
  const i = main.indexOf('if (dryRun) {');
  assert.ok(i >= 0, 'o ramo local (dry-run) existe');
  const fimDryRun = main.indexOf('return;\n  }', i);
  assert.ok(fimDryRun > i && main.indexOf("await import('@supabase/supabase-js')") > fimDryRun,
    'o ramo local retorna antes de chegar ao banco');
  assert.match(main, /console\.log\(`varridos: \$\{nos\.length\} nos, \$\{editados\} editados, \$\{nRevisoes\} revisoes, \$\{sumiram\} sumiram; custo GraphQL \$\{custo\}`\);/,
    'antes do ramo local, o unico log com valor e o do volume varrido');
  assert.equal([...main.slice(0, i).matchAll(/console\.(?:log|error)\(/g)].length, 3, 'e so tres logs antes do ramo local');
  assert.doesNotMatch(CODIGO, /console\.(?:warn|info|debug|table|dir)\(|process\.std(?:out|err)\.write/, 'nenhuma outra saida de log');
  const resto = main.slice(fimDryRun);
  const logs = [...resto.matchAll(/console\.(?:log|error)\(([^;]*)\);/g)].map((m) => m[1]);
  assert.ok(logs.length >= 2, 'os logs do caminho real foram achados');
  assert.deepEqual([...new Set(logs)], ['FIM'], 'os dois finais (com e sem aviso) escrevem a MESMA linha, e so ela');
  assert.equal(logs.length, 2, 'os dois finais existem');
  assert.match(CODIGO, /const FIM = '[^'$`]*';/, 'a linha final e literal fixo');
  assert.match(CODIGO, /console\.error\(`falhou na etapa \$\{etapa\}: codigo \$\{e\?\.code \?\? e\?\.name \?\? 'sem_codigo'\}`\);/,
    'a falha loga so etapa e codigo, nunca a mensagem (que ecoa a linha recusada)');
});

test('o estado grava so impressoes, e DEPOIS de avisar', () => {
  const main = corpoDe('main');
  const ins = main.match(/from\('admin_audit_log'\)\.insert\(\{([\s\S]*?)\}\);/);
  assert.ok(ins, 'o insert do estado existe');
  assert.match(ins[1], /metadata: \{ impressoes: \[\.\.\.new Set\(novos\.map\(\(a\) => a\.impressao\)\)\], destinatarios: entregues \}/,
    'metadata leva so as impressoes e quantos destinatarios');
  assert.ok(main.indexOf("rpc('create_notification'") < main.indexOf("from('admin_audit_log').insert"),
    'avisar antes de gravar: falha na gravacao repete o aviso, nunca o cala');
  assert.match(main, /const novos = achados\.filter\(\(a\) => !avisadas\.has\(a\.impressao\)\);/,
    'so o que nao foi avisado vira aviso');
});

test('o workflow: diario, so leitura no GitHub, sem dry-run, segredo so no passo', () => {
  assert.match(WORKFLOW, /schedule:\s*\n\s*- cron: '\d+ \d+ \* \* \*'/, 'cron diario');
  assert.match(WORKFLOW, /permissions:\s*\n\s*contents: read\s*\n\s*issues: read\s*\n\s*pull-requests: read\s*\n/, 'permissoes so de leitura');
  assert.doesNotMatch(WORKFLOW, /:\s*write\b/, 'nenhuma permissao de escrita');
  assert.match(WORKFLOW, /run: node scripts\/tracker-pii-scan\.mjs\s*$/m, 'roda o caminho real, sem --dry-run');
  assert.doesNotMatch(WORKFLOW, /\becho\b|set -x/, 'nada ecoado no log');
  assert.match(WORKFLOW, /scan:\s*\n\s*if: github\.ref == 'refs\/heads\/main'/, 'so roda a partir da main');
  assert.match(WORKFLOW, /actions\/checkout@v\d+\s*\n\s*with:\s*\n\s*persist-credentials: false/, 'checkout sem credencial persistida');
  assert.match(WORKFLOW, /run: npm ci --ignore-scripts\s*$/m, 'instalacao sem scripts antes do passo com segredo');
  const passo = WORKFLOW.slice(WORKFLOW.indexOf('- name: Varredura do tracker'));
  assert.equal((WORKFLOW.match(/secrets\./g) ?? []).length, 3, 'tres segredos no arquivo');
  assert.equal((passo.match(/secrets\./g) ?? []).length, 3, 'e os tres so no passo da varredura');
});

// ── Coleta, com o fetch simulado: a paginacao aninhada e o historico inteiro sao exercidos, nao so lidos ──

function simular({ issuesTotal = 1, discussions = false, edicoesTotal = 101 } = {}) {
  const pag = (n, c) => ({ hasNextPage: !!c, endCursor: c ?? null });
  const resp = (data) => ({ ok: true, status: 200, headers: new Map(), json: async () => ({ data: { ...data, rateLimit: { cost: 1 } } }) });
  const edicao = (k) => ({ id: `E${k}`, diff: k === 101 ? `original: ${emailDeConsumo('antigo.x')}` : `revisao ${k}`, deletedAt: null });
  return async (_url, opts) => {
    const { query, variables } = JSON.parse(opts.body);
    if (query.includes('hasDiscussionsEnabled')) return resp({ repository: { hasDiscussionsEnabled: discussions, issues: { totalCount: issuesTotal }, pullRequests: { totalCount: 1 } } });
    if (query.includes('issues(first: 50')) return resp({ repository: { issues: { nodes: [{ __typename: 'Issue', id: 'I1', url: 'https://github.com/o/r/issues/1', body: 'revisao 1', title: 't', lastEditedAt: '2026-10-01', comments: { nodes: [{ __typename: 'IssueComment', id: 'C1', url: 'u/c1', body: 'oi', lastEditedAt: null }], pageInfo: pag(1, 'k1') } }], pageInfo: pag() } } });
    if (query.includes('... on Issue { comments(first: 100, after')) return resp({ node: { comments: { nodes: [{ __typename: 'IssueComment', id: 'C2', url: 'u/c2', body: `tel (62) 90000-0000`, lastEditedAt: null }], pageInfo: pag() } } });
    if (query.includes('pullRequests(first: 25')) return resp({ repository: { pullRequests: { nodes: [{ __typename: 'PullRequest', id: 'P1', url: 'u/p1', body: '', title: 'p', lastEditedAt: null, comments: { nodes: [], pageInfo: pag() }, reviews: { nodes: [{ __typename: 'PullRequestReview', id: 'R1', url: 'u/r1', body: '', lastEditedAt: null, comments: { nodes: [], pageInfo: pag() } }], pageInfo: pag() } }], pageInfo: pag() } } });
    if (query.includes('nodes(ids')) return resp({ nodes: variables.ids.map((id) => (id === 'I1' ? { id, userContentEdits: { totalCount: edicoesTotal, nodes: Array.from({ length: 100 }, (_, k) => edicao(k + 1)), pageInfo: pag(1, 'e100') } } : null)) });
    if (query.includes('... on Issue { userContentEdits(first: 100, after')) return resp({ node: { userContentEdits: { nodes: [edicao(101)], pageInfo: pag() } } });
    throw new Error(`consulta nao simulada: ${query.slice(0, 80)}`);
  };
}

async function comFetch(f, corpo) {
  const antes = globalThis.fetch;
  globalThis.fetch = f;
  try { return await corpo(); } finally { globalThis.fetch = antes; }
}

test('coleta: pagina comentario aninhado e o historico alem de 100, e acha o dado na revisao MAIS ANTIGA', async () => {
  const { nos, revisoes, editados } = await comFetch(simular(), () => coletar());
  assert.ok(nos.some((n) => n.id === 'C2'), 'o comentario da segunda pagina foi coletado');
  assert.deepEqual(nos.map((n) => n.classe).sort(), ['comentario', 'comentario', 'issue', 'pr', 'review']);
  assert.equal(editados, 1);
  assert.equal(revisoes.get('I1').length, 101, 'as 101 revisoes vieram, nao so as 100 da primeira pagina');
  const achados = julgar(nos, revisoes);
  assert.ok(achados.some((a) => a.no === 'I1' && a.tipo === 'email' && a.historico), 'o e-mail da revisao 101 foi achado');
  assert.ok(achados.some((a) => a.no === 'C2' && a.tipo === 'telefone'), 'o telefone do comentario paginado foi achado');
});

test('coleta: incompleta FALHA, nunca relata', async () => {
  await assert.rejects(comFetch(simular({ edicoesTotal: 102 }), () => coletar()), { code: 'historico_incompleto' },
    'historico com menos revisoes que o totalCount');
  await assert.rejects(comFetch(simular({ issuesTotal: 2 }), () => coletar()), { code: 'coleta_incompleta' },
    'menos issues coletadas que o totalCount do repositorio');
  await assert.rejects(comFetch(simular({ discussions: true }), () => coletar()), { code: 'fonte_nao_coberta_discussions' },
    'Discussions ligadas sao fonte que o robo nao le');
});

test('a entrega e conferida antes de gravar o estado', () => {
  const main = corpoDe('main');
  const i = main.indexOf("rpc('create_notification'");
  const j = main.indexOf("from('admin_audit_log').insert");
  const k = main.indexOf("if (!entregues) throw falha('aviso_nao_entregue');");
  assert.ok(i >= 0 && k > i && j > k, 'avisa, confere que algum aviso nasceu, e so entao grava');
  assert.match(main, /from\('notifications'\)\.select\('id', \{ count: 'exact', head: true \}\)\s*\.eq\('type', 'tracker_pii_found'\)\.in\('recipient_id', gestores\)\.gte\('created_at', desde\);/,
    'a conferencia conta avisos deste tipo, destes destinatarios, desta execucao');
  assert.match(main, /const ja = await todas\(/, 'o estado e lido inteiro, paginado');
});

test('o aviso sai por e-mail NA HORA: o tipo do script e o mapeado como imediato, no SQL e no catalogo', () => {
  const tipo = CODIGO.match(/p_type: '([a-z_]+)'/)?.[1];
  assert.equal(tipo, 'tracker_pii_found', 'o script cria avisos deste tipo');
  const helper = maskJs(latestFunctionCapture(process.cwd(), '_delivery_mode_for').body).replace(/^\s*--.*$/gm, '');
  const caso = helper.slice(helper.indexOf('CASE p_type'), helper.indexOf('ELSE'));
  assert.match(caso, new RegExp(`WHEN '${tipo}'\\s+THEN 'transactional_immediate'`),
    'a captura mais nova de _delivery_mode_for manda o tipo para o e-mail imediato, dentro do CASE');
  const catalogo = JSON.parse(readFileSync('docs/adr/ADR-0022-notification-types-catalog.json', 'utf8'));
  assert.equal(catalogo.types[tipo]?.delivery_mode, 'transactional_immediate', 'o catalogo ADR-0022 diz o mesmo');
});
