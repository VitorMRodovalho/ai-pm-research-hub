/**
 * #2586, fatia B: envio avulso de corpo livre pelo admin e histórico de comunicação por pessoa.
 *
 * Hermético: lê a migration, a EF send-campaign e as telas. Cada asserção amarra a condição ao resultado no bloco
 * que decide; comentários mascarados. O que mais importa aqui: só a gestão envia; um destinatário só; e-mail de
 * membro vira o membro; e-mail de fora vira pessoa externa com prazo; o corpo nunca entra cru no HTML; o aviso de
 * privacidade só vai ao externo; a mensagem respeita o descadastro.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const migs = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => /^\d{14}_2586_envio_avulso_e_historico_por_pessoa\.sql$/.test(f));
const MIG = maskLineComments(read(`supabase/migrations/${migs[0] ?? 'x'}`));
const EF = maskJsComments(read('supabase/functions/send-campaign/index.ts'));

function fnBody(name) {
  const start = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(start >= 0, `a migration precisa definir ${name}`);
  const open = MIG.indexOf('$function$', start);
  return MIG.slice(open, MIG.indexOf('$function$;', open + 10));
}
const SEND = () => fnBody('admin_send_one_off_message');

test('uma migration só', () => assert.equal(migs.length, 1));

test('só a gestão envia (manage_platform), antes de qualquer escrita', () => {
  const body = SEND();
  assert.match(body, /IF v_caller IS NULL OR NOT public\.can_by_member\(v_caller, 'manage_platform'\) THEN\s+RAISE EXCEPTION 'Forbidden/);
  assert.ok(body.indexOf("'manage_platform'") < body.indexOf('INSERT INTO public.campaign_sends'));
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.admin_send_one_off_message\([^)]*\) FROM PUBLIC, anon;/);
});

test('exatamente um destinatário; tema ativo da taxonomia; limites de assunto e corpo', () => {
  const body = SEND();
  assert.match(body, /IF \(\(p_member_id IS NOT NULL\)::int \+ \(p_application_id IS NOT NULL\)::int \+ \(NULLIF\(btrim\(p_email\), ''\) IS NOT NULL\)::int\) <> 1 THEN\s+RAISE EXCEPTION/);
  assert.match(body, /IF NOT EXISTS \(SELECT 1 FROM public\.campaign_themes t WHERE t\.slug = p_theme AND t\.is_active\) THEN\s+RAISE EXCEPTION/);
  assert.match(body, /IF length\(btrim\(coalesce\(p_subject, ''\)\)\) NOT BETWEEN 1 AND 200 THEN\s+RAISE EXCEPTION/);
  assert.match(body, /IF length\(btrim\(coalesce\(p_body, ''\)\)\) NOT BETWEEN 1 AND 10000 THEN\s+RAISE EXCEPTION/);
});

test('limite diário por quem envia, lido da configuração', () => {
  const body = SEND();
  assert.match(body, /WHERE s\.key = 'campaign_one_off_daily_limit_per_sender'/);
  assert.match(body, /IF v_sent_today >= v_limit THEN\s+RAISE EXCEPTION/);
});

test('e-mail de membro vira o membro; de fora vira pessoa externa com envio + 1 ano; domínio reservado é recusado', () => {
  const body = SEND();
  assert.match(body, /IF v_email !~ '[^']+' OR v_email ~\* c_reserved_domain THEN\s+RAISE EXCEPTION/);
  assert.match(body, /IF v_member_id IS NOT NULL THEN\s+v_email := NULL;\s+v_kind := 'member';\s+ELSIF v_kind = 'external' THEN\s+v_person_id := public\._external_person_upsert\(v_email, v_name, 'campaign_one_off', v_send_id, current_date \+ 365\);/);
});

test('sem segunda aprovação, com quem enviou registrado; marca de corpo livre no envio', () => {
  assert.match(
    SEND(),
    /VALUES \(v_send_id, v_template_id, v_caller, v_caller, now\(\),\s+jsonb_build_object\('type', 'transactional', 'one_off', true, 'freeform', true,\s+'source', 'admin_one_off'/,
  );
});

test('a resposta não devolve nome nem e-mail resolvido (o upsert não verifica identidade)', () => {
  const ret = SEND().match(/RETURN jsonb_build_object\(([^;]*)\);/);
  assert.ok(ret);
  assert.doesNotMatch(ret[1], /v_email|v_name|v_person_id/);
});

test('histórico: manage_member ou manage_platform; sem corpo da mensagem', () => {
  const body = fnBody('get_member_communications');
  assert.match(body, /IF v_caller IS NULL OR NOT \(public\.can_by_member\(v_caller, 'manage_member'\)\s+OR public\.can_by_member\(v_caller, 'manage_platform'\)\) THEN\s+RAISE EXCEPTION/);
  assert.doesNotMatch(body, /'body'|body_html|body_text/);
  assert.match(body, /WHERE cr\.member_id = p_member_id/);
});

// O template tem "<!--EXTERNO-->" dentro de string SQL; o mascarador de comentário (que não conhece string) apagaria
// a linha a partir do "--", então esta asserção lê o arquivo CRU.
const RAW = read(`supabase/migrations/${migs[0] ?? 'x'}`);

test('template: corpo por {{content_html}}/{{content_text}} e o aviso (dpo e descadastro) só dentro do bloco externo', () => {
  for (const lang of ['pt', 'en', 'es']) {
    const html = RAW.match(new RegExp(`'${lang}', '(\\{\\{content_html\\}\\}[^']*)'`));
    assert.ok(html, `HTML ${lang}`);
    const [before, block] = html[1].split('<!--EXTERNO-->');
    assert.ok(block && block.includes('<!--/EXTERNO-->'), `bloco externo ${lang}`);
    assert.doesNotMatch(before, /dpo@|unsubscribe_url/, `aviso fora do bloco em ${lang}`);
    assert.match(block, /dpo@pmigo\.org\.br[\s\S]*|\{unsubscribe_url\}/);
    assert.match(block, /\{unsubscribe_url\}/);
    assert.match(block, /dpo@pmigo\.org\.br/);
    const text = RAW.match(new RegExp(`'${lang}', E'(\\{\\{content_text\\}\\}[^']*)'`));
    assert.ok(text, `texto ${lang}`);
    assert.match(text[1], /\[\[EXTERNO\]\][\s\S]*dpo@pmigo\.org\.br[\s\S]*\[\[\/EXTERNO\]\]/);
  }
});

test('EF: corpo livre passa pela renderização pura e NÃO pelo laço de variáveis cruas', () => {
  assert.match(EF, /if \(isFreeform\) \{[\s\S]*?const rendered = renderFreeform\(\{[\s\S]*?isExternal: !r\.member_id,/);
  assert.match(EF, /const oneOffVars = \(isFreeform \? \{\} : \(send\.audience_filter\?\.variables \?\? \{\}\)\) as Record<string, unknown>/);
});

test('EF: reply-to do tema ou do padrão vai no payload', () => {
  assert.match(EF, /const replyTo = resolveReplyTo\(themeRow\?\.reply_to, /);
  assert.match(EF, /\.\.\.\(replyTo \? \{ reply_to: replyTo \} : \{\}\),/);
});

test('EF: a mensagem de corpo livre respeita o descadastro', () => {
  assert.match(EF, /suppressedAmong\(sb, pendingRows\.map\(addressOf\), !isOneOff \|\| isFreeform\)/);
});

test('telas chamam as RPCs com portão', () => {
  assert.match(maskJsComments(read('src/components/admin/campaigns/OneOffMessageIsland.tsx')), /sb\.rpc\('admin_send_one_off_message', \{/);
  assert.match(maskJsComments(read('src/components/admin/members/MemberCommunicationsPanel.tsx')), /sb\.rpc\('get_member_communications', \{ p_member_id: memberId \}\)/);
});
