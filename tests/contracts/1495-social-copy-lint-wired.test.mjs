// #1495 — o lint de copy por rede tem de estar NO CAMINHO do agendamento, não só disponível.
//
// O defeito que este teste guarda não é "a regra está errada", é "a regra não roda".
// As regras nasceram dentro de `scripts/lint-social-copy.mjs`, o que as deixava valendo
// apenas para quem lembrasse de invocá-lo à mão; quem agendava por `comms_post
// action='schedule'` passava direto. Helper de defesa sem consumidor não defende nada
// (mesma classe do #1485, `ip-rate-limit.ts` que existia e ninguém chamava).
//
// Por isso os asserts abaixo são de DUAS naturezas, e as duas importam:
//   1. fiação  — o módulo é importado pelos dois consumidores e ninguém redeclara regra;
//   2. comportamento — as regras realmente disparam nos textos reais de 27/07.
// Só (1) deixaria passar um módulo inerte; só (2) deixaria passar um módulo perfeito que
// nenhum caminho de escrita chama.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { lintCopy, textoDoPayload, avisosDeCopy, REGRAS } from '../../supabase/functions/_shared/social-copy-rules.mjs';

const MODULO = 'supabase/functions/_shared/social-copy-rules.mjs';
const CLI = 'scripts/lint-social-copy.mjs';
const MCP = 'supabase/functions/nucleo-mcp/index.ts';

const ler = (p) => readFileSync(p, 'utf8');

// ── 1. fiação ───────────────────────────────────────────────────────────────────

test('#1495: o CLI consome o módulo compartilhado em vez de declarar as próprias regras', () => {
  const cli = ler(CLI);
  assert.match(
    cli,
    /import\s*\{[^}]*lintCopy[^}]*\}\s*from\s*["'][^"']*social-copy-rules\.mjs["']/,
    `${CLI} deve importar lintCopy do módulo compartilhado.`
  );
  assert.ok(
    !/^\s*(export\s+)?const\s+REGRAS\s*=/m.test(cli),
    `${CLI} voltou a declarar REGRAS. As regras têm um dono só (${MODULO}); duas cópias divergem em silêncio.`
  );
});

test('#1495: os DOIS caminhos de agendamento do nucleo-mcp chamam o lint', () => {
  const mcp = ler(MCP);
  assert.match(
    mcp,
    /import\s*\{[^}]*avisosDeCopy[^}]*\}\s*from\s*["'][^"']*social-copy-rules\.mjs["']/,
    `${MCP} deve importar avisosDeCopy do módulo compartilhado.`
  );
  const chamadas = (mcp.match(/avisosDeCopy\s*\(/g) || []).length;
  assert.ok(
    chamadas >= 2,
    `avisosDeCopy é chamado ${chamadas}x em ${MCP}; esperado >= 2 (a tool raw schedule_comms_post ` +
    `E o comms_post semântico). Deixar um caminho sem lint torna o outro contornável.`
  );
});

test('#1495: o lint AVISA, nunca bloqueia (decisão do PM no issue)', () => {
  // Regra de estilo que trava publicação vira atrito na véspera de evento. O agendamento
  // acontece; o achado viaja junto. Um `return err(...)` derivado do lint seria a regressão.
  const linhas = ler(MCP).split('\n');
  linhas.forEach((linha, i) => {
    if (!/avisosDeCopy\s*\(/.test(linha)) return;
    const janela = linhas.slice(Math.max(0, i - 2), i + 3).join('\n');
    assert.ok(
      !/return\s+(err|invalid|denied)\s*\(/.test(janela),
      `linha ${i + 1} de ${MCP}: o resultado do lint aparece perto de um return de erro. ` +
      `O lint é aviso, não gate.`
    );
  });
});

test('#1495: nenhuma segunda cópia das regras no código-fonte', () => {
  // Uma regra qualquer serve de sonda: se o id aparece fora do módulo, alguém duplicou a tabela.
  const SONDA = 'linkedin-sem-hashtag';
  const raizes = ['scripts', 'src', 'supabase/functions'];
  const achados = [];
  const varrer = (dir) => {
    for (const nome of readdirSync(dir)) {
      if (nome === 'node_modules' || nome.startsWith('.')) continue;
      const p = join(dir, nome);
      const st = statSync(p);
      if (st.isDirectory()) { varrer(p); continue; }
      if (!/\.(mjs|js|ts|tsx|astro)$/.test(nome)) continue;
      if (ler(p).includes(SONDA)) achados.push(p);
    }
  };
  raizes.forEach(varrer);
  assert.deepEqual(
    achados,
    [MODULO],
    `a tabela de regras deve existir em um arquivo só. Encontrada em: ${achados.join(', ')}`
  );
});

// ── 2. comportamento ────────────────────────────────────────────────────────────

test('#1495: as regras reprovam a copy do LinkedIn que o time teve de editar', () => {
  // Texto equivalente ao que a plataforma publicou em 27/07 e o time encolheu em 25%.
  const publicado = [
    'Tem uma pergunta que quase ninguem faz antes de colar um documento de trabalho dentro de uma IA.',
    '',
    '📅 Terca, 4 de agosto, 19h00 as 20h30 (horario de Brasilia)',
    '💻 Online, gratuito, aberto ao publico e com gravacao',
    '🎟️ Inscricao: https://pmilatam.airmeet.com/e/8d047420',
    '',
    'O Nucleo IA & GP é uma iniciativa dos capítulos do PMI no Brasil, sediada no PMI-GO.',
    '',
    '#InteligenciaArtificial #GestaoDeProjetos',
  ].join('\n');

  const { erros, avisos } = lintCopy(publicado, 'linkedin');
  const ids = erros.map((e) => e.id);
  assert.ok(ids.includes('linkedin-sem-hashtag'), `esperado pegar hashtag; pegou: ${ids.join(', ')}`);
  assert.ok(ids.includes('linkedin-sem-boilerplate'), `esperado pegar o parágrafo institucional; pegou: ${ids.join(', ')}`);
  assert.ok(ids.includes('linkedin-cta-sem-emoji'), `esperado pegar o emoji no CTA; pegou: ${ids.join(', ')}`);
  assert.ok(avisos.length > 0, 'os cortes de "(horário de Brasília)" e da linha de formato são avisos, não erros');
});

test('#1495: as regras aprovam a copy D-1 escrita no padrão do time', () => {
  const d1 = [
    'Amanha, 19h00.',
    '',
    'Analise de cenario e gestao de portfolio com IA, com Fernando Carvalho, Diretor de Operacoes.',
    '',
    'Link do evento: https://pmilatam.airmeet.com/e/8d047420',
  ].join('\n');
  const { erros } = lintCopy(d1, 'linkedin');
  assert.deepEqual(erros, [], `a copy no padrão do time não pode reprovar: ${erros.map((e) => e.id).join(', ')}`);
});

test('#1495: o Instagram tem régua PRÓPRIA, não a do LinkedIn', () => {
  // O mesmo texto muda de veredito conforme o canal: é a razão de a regra existir.
  const comHashtagELink = 'Legenda do post.\n\nInscricao no link da bio.\n\n#IA #PMI';
  assert.deepEqual(lintCopy(comHashtagELink, 'instagram').erros, [], 'hashtag no IG é o padrão, não erro');
  assert.ok(
    lintCopy(comHashtagELink, 'linkedin').erros.some((e) => e.id === 'linkedin-sem-hashtag'),
    'a MESMA copy tem de reprovar no LinkedIn — senão a régua não é por canal'
  );
  assert.ok(
    lintCopy('Legenda com https://exemplo.com no meio.\n\n#IA', 'instagram').erros
      .some((e) => e.id === 'instagram-link-nao-clicavel'),
    'URL na legenda do IG é erro: lá o link não é clicável'
  );
});

test('#1495: peça sem texto (STORIES) não gera aviso de copy', () => {
  // Inventar aviso em peça muda é ruído, e ruído ensina a ignorar o aviso.
  assert.equal(textoDoPayload({ image_url: 'https://x/y.png', media_type: 'STORIES' }), null);
  assert.deepEqual(avisosDeCopy('instagram', { image_url: 'https://x/y.png' }), []);
});

test('#1495: avisosDeCopy lê o campo certo de cada canal', () => {
  // LinkedIn manda `text`, Instagram manda `caption`. Ler o campo errado devolve [] sempre,
  // que é exatamente o modo de falha silenciosa que este issue existe para matar.
  const li = avisosDeCopy('linkedin', { text: 'Post com #hashtag.', post_type: 'IMAGE' });
  assert.ok(li.some((a) => a.includes('linkedin-sem-hashtag')), `esperado achado lendo payload.text; veio: ${JSON.stringify(li)}`);
  const ig = avisosDeCopy('instagram', { caption: 'Legenda com https://exemplo.com', media_type: 'IMAGE' });
  assert.ok(ig.some((a) => a.includes('instagram-link-nao-clicavel')), `esperado achado lendo payload.caption; veio: ${JSON.stringify(ig)}`);
});

test('#1495: toda regra declara canal e nível válidos', () => {
  for (const r of REGRAS) {
    assert.ok(['linkedin', 'instagram', 'ambos'].includes(r.canal), `regra ${r.id} com canal inválido: ${r.canal}`);
    assert.ok(['erro', 'aviso'].includes(r.nivel), `regra ${r.id} com nível inválido: ${r.nivel}`);
    assert.equal(typeof r.testa, 'function', `regra ${r.id} sem função de teste`);
    assert.ok(r.msg && r.msg.length > 20, `regra ${r.id} com mensagem curta demais para orientar a correção`);
  }
});
