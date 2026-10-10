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
/** Escapa todo metacaractere de regex (inclusive a barra invertida) para casar o texto literal. */
const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
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

test('e-mail estrito (sem "<", vírgula ou aspas) e domínio reservado recusado', () => {
  assert.match(SEND(), /IF length\(v_email\) > 254 OR v_email !~ '\^\[a-z0-9\._%\+-\]\+@\[a-z0-9-\]\+\(\\\.\[a-z0-9-\]\+\)\+\$' OR v_email ~\* c_reserved_domain THEN\s+RAISE EXCEPTION/);
});

test('e-mail de membro vira o membro sem apagar o nome digitado; de fora vira pessoa externa com envio + 1 ano', () => {
  const body = SEND();
  // variáveis próprias: SELECT INTO sem linha zeraria v_name
  assert.match(body, /SELECT m\.id, m\.name, lower\(btrim\(m\.email\)\) INTO v_m_id, v_m_name, v_m_email\s+FROM public\.members m/);
  assert.match(body, /IF v_m_id IS NOT NULL THEN\s+v_member_id := v_m_id;\s+v_name := v_m_name;\s+v_email := NULL;\s+v_kind := 'member';\s+ELSIF v_kind = 'external' THEN\s+v_person_id := public\._external_person_upsert\(v_email, v_name, 'campaign_one_off', v_send_id, current_date \+ 365\);/);
  assert.match(body, /v_name := NULLIF\(left\(btrim\(regexp_replace\(coalesce\(p_name, ''\), '\[\[:cntrl:\]\]', '', 'g'\)\), 120\), ''\);/);
});

test('endereço suprimido é recusado antes de existir envio (descadastro conta só para externo)', () => {
  const body = SEND();
  assert.match(body, /IF cardinality\(public\.email_suppressed_among\(ARRAY\[COALESCE\(v_email, v_m_email\)\], v_member_id IS NULL\)\) > 0 THEN\s+RAISE EXCEPTION 'Recipient address is suppressed'/);
  assert.ok(body.indexOf('email_suppressed_among') < body.indexOf('INSERT INTO public.campaign_sends'));
});

test('limite por endereço externo, somando quem envia, e trava por quem envia', () => {
  const body = SEND();
  assert.match(body, /IF v_ext_day >= COALESCE\(\(v_ext_limits->>'per_day'\)::int, 1\)\s+OR v_ext_month >= COALESCE\(\(v_ext_limits->>'per_30_days'\)::int, 3\) THEN\s+RAISE EXCEPTION 'Per-address limit/);
  assert.match(body, /PERFORM pg_advisory_xact_lock\(hashtext\('one_off_sender:' \|\| v_caller::text\)\);/);
  assert.ok(body.indexOf('pg_advisory_xact_lock') < body.indexOf('INTO v_sent_today'));
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
  assert.match(body, /v_platform := v_caller IS NOT NULL AND public\.can_by_member\(v_caller, 'manage_platform'\);\s+IF v_caller IS NULL OR NOT \(public\.can_by_member\(v_caller, 'manage_member'\) OR v_platform\) THEN\s+RAISE EXCEPTION/);
  assert.doesNotMatch(body, /'body'|body_html|body_text/);
  // o assunto digitado pela gestão só para quem tem manage_platform
  assert.match(body, /THEN CASE WHEN v_platform THEN cs\.audience_filter->'variables'->>'subject' END/);
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

test('EF: o corpo livre a externo respeita o descadastro; a membro, só a supressão', () => {
  assert.match(EF, /const freeformToExternal = isFreeform && recipients\.some\(\(r\) => !r\.member_id\)/);
  assert.match(EF, /suppressedAmong\(sb, pendingRows\.map\(addressOf\), !isOneOff \|\| freeformToExternal\)/);
});

test('EF: no corpo livre, valor de {member.name} e afins entra escapado no HTML', () => {
  assert.match(EF, /html = html\.split\(k\)\.join\(isFreeform \? escapeHtml\(v\) : v\)/);
});

test('telas chamam as RPCs com portão', () => {
  assert.match(maskJsComments(read('src/components/admin/campaigns/OneOffMessageIsland.tsx')), /sb\.rpc\('admin_send_one_off_message', \{/);
  assert.match(maskJsComments(read('src/components/admin/members/MemberCommunicationsPanel.tsx')), /sb\.rpc\('get_member_communications', \{ p_member_id: memberId \}\)/);
});

test('#2586 política v2.3: a página declara a pessoa não membro (finalidade e retenção) e a lista de descadastro', () => {
  const page = read('src/pages/privacy.astro');
  assert.match(page, /const S3_ROWS = \[1,2,3,4,5,6,7,8,9,10,11,12,13\] as const;/);
  assert.match(page, /const S6_ROWS = \[1,2,3,4,5,6,7,8,9,10,11,12,13,14\] as const;/);
  const keys = ['s3.row13.purpose', 's3.row13.data', 's3.row13.basis',
    's6ret.row10.data', 's6ret.row10.retention', 's6ret.row10.after',
    's6ret.row14.data', 's6ret.row14.retention', 's6ret.row14.after'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${lang}.ts`);
    assert.match(dict, /'privacy\.version': 'v2\.3'/, `${lang} sem v2.3`);
    for (const k of keys) assert.match(dict, new RegExp(`'privacy\\.${reEsc(k)}': '[^']+`), `${lang} sem ${k}`);
    // decisão do GP (10/10): a linha 10 (convidados) passa a declarar o que a varredura executa, 1 ano e
    // anonimização; a promessa antiga de 30 dias não tinha executor e não pode voltar
    assert.match(dict, /'privacy\.s6ret\.row10\.retention': '1 (ano|year|año)/, `${lang}: prazo da pessoa não membro`);
    assert.ok(!/'privacy\.s6ret\.row10\.retention': '30 /.test(dict), `${lang}: voltou a promessa de 30 dias`);
    assert.ok(!/'privacy\.s6ret\.row15\./.test(dict), `${lang}: sobrou a linha 15`);
  }
});
