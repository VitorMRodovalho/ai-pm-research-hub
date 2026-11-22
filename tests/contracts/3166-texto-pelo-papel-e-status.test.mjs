/**
 * #3166: textos que não olham o papel nem o status da pessoa.
 *
 * S7 (parcerias): o botão de retroceder status chamava admin_update_partner_status com o status
 * anterior. O funil é só para a frente (ADR-0033), a função recusa a volta no corpo, e a tela, que lia
 * só o `error`, dizia "Status retrocedido." sem mudar nada. O botão sai enquanto a função recusar.
 *
 * Comentários JS e SQL saem antes do assert.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments as maskJs, maskLineComments as maskSql } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');

function latestSqlBody(name) {
  const dir = resolve(ROOT, 'supabase/migrations');
  const head = `CREATE OR REPLACE FUNCTION public.${name}(`;
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()
    .filter((f) => maskSql(readFileSync(resolve(dir, f), 'utf8')).includes(head));
  assert.ok(files.length, `alguma migration define ${name}`);
  const sql = maskSql(readFileSync(resolve(dir, files.at(-1)), 'utf8'));
  const a = sql.lastIndexOf(head);
  return { file: files.at(-1), body: sql.slice(a, sql.indexOf('$function$;', a)) };
}

test('#3166 S7: a tela de parcerias não oferece voltar status enquanto a função recusa a volta', () => {
  const { file, body } = latestSqlBody('admin_update_partner_status');
  const blocks = /IF[\s\S]{0,400}?THEN\s+RETURN jsonb_build_object\('success', false, 'error', 'backward_transition_blocked'/.test(body);
  const island = maskJs(read('src/components/islands/PartnerPipelineIsland.tsx'));
  const calls = [...island.matchAll(/sb\.rpc\('admin_update_partner_status', \{[^}]*p_new_status: ([a-zA-Z_.[\]]+)/g)].map((m) => m[1]);
  const rpcCheckedCalls = [...island.matchAll(/rpcChecked\(sb, 'admin_update_partner_status', \{[\s\S]*?p_new_status: ([a-zA-Z_.[\]]+)/g)].map((m) => m[1]);
  if (blocks) {
    assert.doesNotMatch(island, /PREV_STATUS|Retrocedido|retrocedido/, `${file} recusa a volta: a ilha não pode ter botão nem texto de retroceder`);
    for (const v of [...calls, ...rpcCheckedCalls]) {
      assert.doesNotMatch(v, /prev/i, `${file} recusa a volta: nenhuma chamada manda o status anterior`);
    }
  }
  assert.ok(blocks, `${file}: a recusa da volta continua; se a função passar a aceitar, reveja este guard`);
});

// ── A5, A6, A7, A8 e A10: o texto segue o papel e o status de quem lê ──
// Comentários JS e HTML saem antes do assert; o HTML repete até estabilizar (CodeQL
// js/incomplete-multi-character-sanitization).
function stripHtmlComments(src) {
  let prev;
  let out = src;
  do { prev = out; out = out.replace(/<!--[\s\S]*?-->/g, ''); } while (out !== prev);
  return out;
}
const flat = (p) => stripHtmlComments(maskJs(read(p))).replace(/\s+/g, ' ');
const DICT = (l) => read(`src/i18n/${l}.ts`);
const LANGS = ['pt-BR', 'en-US', 'es-LATAM'];
const keyIn = (src, k) => new RegExp(`'${k.replace(/\./g, '\\.')}': '([^']+)'`).exec(src)?.[1];

test('#3166 A5: /certificates decide pelo Nav antes de ler, e sem cadastro ou com falha não vê "nenhum certificado"', () => {
  const s = flat('src/pages/certificates.astro');
  assert.match(s, /<GuestNoMember lang=\{lang\} id="certs-guest" \/>/, 'o bloco de quem não tem cadastro está na página');
  assert.match(s, /<MemberLoadFailed lang=\{lang\} id="certs-failed" \/>/, 'o bloco de falha de carga está na página');
  const decide = /const r = await waitMemberResolved\(\); if \(r\.kind === 'member-failed' \|\| r\.kind === 'no-member' \|\| \(r\.kind === 'member' && !isRegisteredMember\(r\.member\)\)\) \{ container\.classList\.add\('hidden'\); document\.getElementById\(r\.kind === 'member-failed' \? 'certs-failed' : 'certs-guest'\)\?\.classList\.remove\('hidden'\); return; \}/.exec(s);
  assert.ok(decide, 'sem cadastro vê o bloco da #3086 e a falha vê o bloco de falha, e a página para ali');
  const leitura = s.search(/\.rpc\('get_my_certificates'/);
  assert.ok(leitura > -1 && decide.index < leitura, 'a decisão vem antes de qualquer leitura dos certificados');
});

test('#3166 A6: /minhas-avaliacoes separa as duas recusas e o "sem ciclo" do "avaliou tudo"', () => {
  const s = flat('src/pages/minhas-avaliacoes.astro');
  assert.match(s, /if \(\/not on this cycle committee\/i\.test\(msg\)\) \{ showDenied\(I\.notCommittee\); return; \}/, 'só a recusa de comitê diz comitê');
  assert.match(s, /if \(\/\^Not authenticated\/i\.test\(msg\)\) \{ showDenied\(I\.notActiveMember\); return; \}/, 'sem membro ativo tem texto próprio');
  assert.doesNotMatch(s, /'42501'[^;]*\) \{ showDenied\(I\.notCommittee\)/, 'o código 42501 sozinho não decide "comitê"');
  assert.match(s, /if \(pending\.length === 0\) \{ const emptyText = data\?\.cycle_code \? I\.noPending : I\.noCycle;/, 'fila vazia sem ciclo diz que não há ciclo');
  assert.match(s, /\$\{esc\(emptyText\)\}/, 'o vazio mostra o texto escolhido');
  assert.equal(keyIn(DICT('pt-BR'), 'myEvals.noCycle'), 'Nenhum ciclo de seleção está em avaliação agora.');
  assert.equal(keyIn(DICT('pt-BR'), 'myEvals.notActiveMember'), 'Esta tela é para membros ativos do Núcleo.');
  for (const l of LANGS) for (const k of ['myEvals.noCycle', 'myEvals.notActiveMember']) assert.ok(keyIn(DICT(l), k), `${l}: ${k}`);
});

test('#3166 A7: /minhas-vagas mostra o próximo passo só com a lista, e o vazio por conflito diz quantas', () => {
  const s = flat('src/pages/minhas-vagas.astro');
  assert.match(s, /<div id="mv-next-step" class="hidden /, 'o banner nasce escondido');
  assert.match(s, /function showOnly\([^)]*\) \{ \['mv-loading'[^\]]*\]\.forEach\(\(id\) => \{[\s\S]{0,120}?\}\); \$\('mv-next-step'\)\?\.classList\.toggle\('hidden', which !== 'list'\);/, 'o banner aparece só com a lista');
  assert.match(s, /if \(apps\.length === 0\) \{ showNotice\(omitidas > 0 \? `\$\{I\.omitted\} \$\{omitidas\}` : I\.empty\); return; \}/, 'vazio com omitidas mostra a contagem');
});

test('#3166 A8: /workspace pede alocação só ao pesquisador sem tribo; os demais veem as iniciativas', () => {
  const s = flat('src/pages/workspace.astro');
  assert.match(s, /\} else if \(member\.operational_role === 'researcher'\) \{ \$noTribe\?\.classList\.remove\('hidden'\); \} else \{ document\.getElementById\('wk-outside-tribes'\)\?\.classList\.remove\('hidden'\); \}/, 'o texto de alocação só para researcher');
  assert.match(s, /<div id="wk-outside-tribes" class="hidden[^"]*">\s*<p[^>]*>\{WK\.outsideTribes\}<\/p>\s*<a id="wk-outside-tribes-cta" href=\{`\$\{langPrefix\}\/initiatives`\}/, 'fora das tribos leva às iniciativas');
  assert.equal(keyIn(DICT('pt-BR'), 'wk.outsideTribes'), 'Você atua fora das tribos.');
  assert.equal(keyIn(DICT('pt-BR'), 'wk.outsideTribesCta'), 'Ver iniciativas');
  for (const l of LANGS) for (const k of ['wk.outsideTribes', 'wk.outsideTribesCta']) assert.ok(keyIn(DICT(l), k), `${l}: ${k}`);
});

test('#3166 A10: /interview-booking oferece agendar só à entrevista pendente', () => {
  const raw = stripHtmlComments(maskJs(read('src/pages/interview-booking/[token].astro')));
  const m = /const bookingState: [^=]+=\s*([\s\S]*?);/.exec(raw);
  assert.ok(m, 'o estado da página sai do status da candidatura');
  // eslint-disable-next-line no-new-func
  const state = (appStatus) => new Function('appStatus', `return (${m[1]});`)(appStatus);
  assert.equal(state('interview_pending'), 'book');
  assert.equal(state(null), 'book', 'sem status lido, a CTA de hoje');
  assert.equal(state('interview_scheduled'), 'scheduled');
  for (const st of ['interview_noshow', 'interview_done', 'rejected', 'withdrawn', 'approved', 'submitted']) assert.equal(state(st), 'closed', st);
  assert.match(raw, /const appStatus: string \| null = payload\?\.application_status \?\? null;/, 'o status vem do RPC');
  const s = raw.replace(/\s+/g, ' ');
  const closed = /\) : bookingState === 'closed' \? \( (<div id="booking-closed"[\s\S]*?) \) : bookingState === 'scheduled' \? \( (<div id="booking-scheduled"[\s\S]*?) \) : noBookingUrl \? \(/.exec(s);
  assert.ok(closed, 'fechado e agendado vêm antes da tela de agendar');
  assert.match(closed[1], /t\('interview\.booking\.closedTitle', lang\)/);
  assert.doesNotMatch(closed[1], /calendarBaseUrl/, 'fechado não tem a agenda');
  assert.match(closed[2], /t\('interview\.booking\.scheduledTitle', lang\)/);
  assert.doesNotMatch(closed[2], /bg-blue-600/, 'agendado não tem o botão principal de agendar');
  assert.equal(keyIn(DICT('pt-BR'), 'interview.booking.scheduledTitle'), 'Sua entrevista já está agendada.');
  assert.equal(keyIn(DICT('pt-BR'), 'interview.booking.closedTitle'), 'Este link não serve mais para agendar.');
  for (const l of LANGS) for (const k of ['interview.booking.scheduledTitle', 'interview.booking.closedTitle']) assert.ok(keyIn(DICT(l), k), `${l}: ${k}`);
});
