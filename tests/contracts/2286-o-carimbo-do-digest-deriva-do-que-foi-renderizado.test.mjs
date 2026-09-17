// tests/contracts/2286-o-carimbo-do-digest-deriva-do-que-foi-renderizado.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2286 — o digest carimbava como entregue o que nunca renderizou.
 *
 * MEDIDO em 17/09/2026, na fonte viva: 31 tipos com `delivery_mode='digest_weekly'`,
 * 4.388 linhas carimbadas com `digest_delivered_at`, e 4.283 delas (97,6%) nunca
 * chegaram ao e-mail. 2.701 tambem nunca foram lidas no sino — perda de sinal, nao
 * so metrica errada. A issue registrava 76 linhas em 2 tipos.
 *
 * A perda tinha TRES camadas, e cada assercao abaixo fecha uma:
 *
 *   1. 27 tipos sem secao na RPC (1.277 carimbadas) -> o `ELSE` do CASE.
 *   2. 2 secoes que a RPC montava e o renderizador da EF NUNCA desenhou
 *      (`new_assignments`, `attendance_reminders_pending`, criadas em p95 #99 1A/1B;
 *      3.006 carimbadas) -> a PARIDADE derivada abaixo. Elas tinham ZERO ocorrencia
 *      no repositorio inteiro, e nenhum guard perguntava pela volta.
 *   3. `consumed_notification_ids` era um SELECT paralelo as secoes -> a unicidade
 *      do `FROM public.notifications`.
 *
 * POR QUE A PARIDADE E DERIVADA, e nao uma lista de nomes: a lista de nomes envelhece
 * junto com quem a escreveu. Aqui as secoes saem do CORPO da funcao, entao uma secao
 * nova nasce coberta — e uma secao nova sem bloco no e-mail reprova sozinha.
 *
 * Cross-ref: #2286, #1470 (janela por occurred_at, preservada), #1932 (a migration
 * precisa SER a captura), ADR-0022.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const EF_PATH = resolve(ROOT, 'supabase/functions/send-notification-email/index.ts');
// Comentarios MASCARADOS de proposito: a primeira versao deste guard usava o texto cru e
// ficava verde com o bloco REMOVIDO, porque a string sobrevivia no comentario que explica
// a secao. O teste de mutacao pegou — mesma classe do /is_visitor/ solto na #2335.
const ef = maskJsComments(readFileSync(EF_PATH, 'utf8'));

// Captura VIGENTE, nunca um caminho fixo: fixar o `.sql` faria estas asserções falarem
// de um texto que a produção deixou de executar (classe do #1932).
const capDigest = latestFunctionCapture(ROOT, 'get_weekly_member_digest');
const capCron = latestFunctionCapture(ROOT, 'generate_weekly_member_digest_cron');
const digestSemComentario = maskLineComments(capDigest?.block ?? '');
const cronSemComentario = maskLineComments(capCron?.block ?? '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

/**
 * As secoes que a RPC alimenta a partir de `notifications`, lidas do CASE que classifica
 * cada linha pendente. Deriva do corpo para que uma secao nova nasca coberta.
 */
function secoesDeNotificacaoDaRpc(corpo) {
  const nomes = new Set();
  for (const m of corpo.matchAll(/\bTHEN\s+'([a-z_]{4,40})'/g)) nomes.add(m[1]);
  const fallback = corpo.match(/\bELSE\s+'([a-z_]{4,40})'\s*\n?\s*END\s+AS\s+secao/i);
  if (fallback) nomes.add(fallback[1]);
  return [...nomes];
}

// ── ESTATICO: a RPC ───────────────────────────────────────────────────────────────────

test('#2286 static: existe captura vigente das duas funcoes da cadeia', () => {
  assert.ok(capDigest, 'alguma migration captura get_weekly_member_digest');
  assert.ok(capCron, 'alguma migration captura generate_weekly_member_digest_cron');
});

test('#2286 static: o CASE tem ELSE — nenhum tipo pode sumir por omissao', () => {
  // O ramo que transforma "sumir" em "aparecer": sem ele, um tipo novo volta a ser
  // carimbado sem nunca ser montado, que e o defeito inteiro da #2286.
  assert.match(digestSemComentario, /\bELSE\s+'other_notifications'\s*\n?\s*END\s+AS\s+secao/i,
    'o CASE que classifica a notificacao precisa de um ELSE que recolha o que nao casou');
});

test('#2286 static: o carimbo NAO tem SELECT proprio sobre notifications', () => {
  // A causa raiz: `consumed_notification_ids` era uma segunda varredura, independente
  // das secoes, logo podia afirmar entrega do que ninguem montou. Uma unica leitura da
  // tabela torna a divergencia impossivel de escrever por distracao.
  const leituras = [...digestSemComentario.matchAll(/FROM\s+public\.notifications\b/gi)].length;
  assert.equal(leituras, 1,
    `esperava UMA leitura de public.notifications na RPC, achei ${leituras} — ` +
    'um segundo SELECT reabre a classe do #2286');
  assert.match(digestSemComentario, /'consumed_notification_ids',\s*v_consumed/,
    'o carimbo tem de ser a variavel derivada do mesmo conjunto que alimentou as secoes');
});

test('#2286 static: #1470 preservado — xp_delta ainda janela por occurred_at', () => {
  // Redefinir a funcao inteira e a forma mais facil de apagar em silencio uma invariante
  // de outra issue. Esta assercao existe para que isso reprove.
  assert.match(digestSemComentario, /COALESCE\(gp\.occurred_at, gp\.created_at\) >= v_window_start/,
    'xp_delta usa COALESCE(occurred_at, created_at) — invariante do #1470');
});

// ── ESTATICO: a paridade que faltava ──────────────────────────────────────────────────

test('#2286: PARIDADE — toda secao de notificacao da RPC tem bloco no renderizador', () => {
  const secoes = secoesDeNotificacaoDaRpc(digestSemComentario);
  // Controle positivo: se a derivacao devolver pouca coisa, a assercao passaria por vazio.
  assert.ok(secoes.length >= 6,
    `a derivacao achou apenas ${secoes.length} secoes (${secoes.join(', ')}) — ` +
    'se o CASE mudou de forma, conserte a derivacao antes de confiar no verde');
  const ausentes = secoes.filter((s) => !ef.includes(s));
  assert.deepEqual(ausentes, [],
    `a RPC monta secoes que o e-mail nao desenha: ${ausentes.join(', ')}. ` +
    'Foi exatamente assim que new_assignments e attendance_reminders_pending ficaram ' +
    '3.006 linhas carimbadas sem nunca aparecer (#2286).');
});

test('#2286: o orquestrador CONTA toda secao de notificacao', () => {
  // has_content decide se o digest sai. Uma secao que ele nao conta fica invisivel
  // justamente para quem so tem aquilo — e ai o conserto nao alcanca ninguem.
  const secoes = secoesDeNotificacaoDaRpc(digestSemComentario);
  const ausentes = secoes.filter((s) => !cronSemComentario.includes(s));
  assert.deepEqual(ausentes, [],
    `has_content ignora secoes: ${ausentes.join(', ')} — membro cujo unico conteudo for ` +
    'uma delas cai em no_content_skip');
});

// ── DB: a camada VIVA ─────────────────────────────────────────────────────────────────

test('#2286 db: a migration É a captura — md5 do arquivo bate com o corpo VIVO',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    for (const [nome, cap] of [['get_weekly_member_digest', capDigest],
                               ['generate_weekly_member_digest_cron', capCron]]) {
      const md5Arquivo = createHash('md5').update(cap.body.replace(/\s+/g, ' ')).digest('hex');
      const vivas = (data ?? []).filter((f) => f.proname === nome);
      assert.equal(vivas.length, 1, `esperava UMA ${nome} viva, achei ${vivas.length}`);
      assert.equal(vivas[0].body_md5, md5Arquivo,
        `${nome}: o corpo vivo divergiu da captura mais nova (${cap.file}) — classe do #1932`);
      assert.equal(vivas[0].is_secdef, true, `${nome} continua SECURITY DEFINER`);
    }
  });

test('#2286 db: nos digests ja gerados pela versao nova, o carimbo é subconjunto do montado',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Auto-identificavel: um digest gerado pela versao nova carrega a chave
    // `other_notifications`. Nao ha data de corte a manter sincronizada.
    const { data, error } = await sb()
      .from('notifications')
      .select('id, body, digest_batch_id, created_at')
      .eq('type', 'weekly_member_digest')
      .order('created_at', { ascending: false })
      .limit(20);
    assert.ifError(error);

    const novos = (data ?? []).filter((n) => {
      try { return JSON.parse(n.body ?? '{}')?.sections?.other_notifications !== undefined; }
      catch { return false; }
    });

    // TRES estados: "nenhum digest novo ainda" NAO e aprovacao. O cron roda aos sabados,
    // entao ate o primeiro disparo esta assercao nao mediu nada — e diz isso.
    if (novos.length === 0) {
      console.log('#2286 NAO MEDIDO: nenhum digest gerado pela versao nova ainda ' +
        '(o cron roda sabado 12:00 UTC). A assercao de inclusao volta a medir no proximo disparo.');
      return;
    }

    for (const dig of novos) {
      const payload = JSON.parse(dig.body);
      const montados = new Set();
      const colher = (arr) => (Array.isArray(arr) ? arr : []).forEach((x) => x?.id && montados.add(x.id));
      const s = payload.sections ?? {};
      colher(s.cards?.new_assignments); colher(s.engagements_new); colher(s.attendance_reminders_pending);
      colher(s.broadcasts); colher(s.governance_pending); colher(s.other_notifications);

      const carimbados = payload.consumed_notification_ids ?? [];
      const foraDoMontado = carimbados.filter((id) => !montados.has(id));
      assert.deepEqual(foraDoMontado, [],
        `digest ${dig.id}: ${foraDoMontado.length} id(s) carimbados sem aparecer em secao nenhuma — ` +
        'o carimbo voltou a ser uma afirmacao paralela (#2286)');
    }
  });
