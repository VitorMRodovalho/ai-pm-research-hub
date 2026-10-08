/**
 * #2130 E-a (decisoes do GP de 08/10/2026): o link de descadastro das campanhas funciona e o descadastro vale por endereco.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. a pagina so registra no POST; o GET mostra o botao (leitor automatico de link nao descadastra ninguem);
 *   B. o POST de um clique (RFC 8058) e reconhecido, chega a RPC como one_click e recebe 200 quando registra;
 *   C. o e-mail leva List-Unsubscribe-Post junto do List-Unsubscribe, e o link leva o token e o idioma;
 *   D. a RPC: token desconhecido nao faz nada, o endereco entra na lista uma vez, as campanhas ainda nao entregues do
 *      mesmo endereco ficam marcadas e o avulso transacional nao, e a resposta nao devolve o endereco;
 *   E. admin_send_campaign pula endereco descadastrado, de membro e de contato externo;
 *   F. a tabela e o auxiliar ficam fechados; so a RPC por token abre para anon;
 *   G. /en/ e /es/ redirecionam com o idioma.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2130_descadastro_pelo_link\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const PAGE = readFileSync(resolve(ROOT, 'src/pages/unsubscribe.astro'), 'utf8').replace(/^\s*\/\/.*$/gm, '');
const EF = readFileSync(resolve(ROOT, 'supabase/functions/send-campaign/index.ts'), 'utf8').replace(/^\s*\/\/.*$/gm, '');
const RPC = maskLineComments(latestFunctionCapture(ROOT, 'campaign_unsubscribe').block);
const SEND = maskLineComments(latestFunctionCapture(ROOT, 'admin_send_campaign').block);

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration, achei ${files.length}`);
});

test('A. so o POST registra', () => {
  const post = (PAGE.match(/if \(Astro\.request\.method === 'POST'\) \{([\s\S]*?)\n\}\n/) || ['', ''])[1];
  assert.match(post, /sb\.rpc\('campaign_unsubscribe'/, 'a chamada da RPC tem de estar dentro do ramo do POST');
  assert.equal((PAGE.match(/rpc\(/g) || []).length, 1, 'a RPC so pode ser chamada uma vez, no POST');
  assert.match(PAGE, /let state: [^=]+= tokenOk \? 'confirm' : 'invalid';/);
  assert.match(PAGE, /\{state === 'confirm' && \([\s\S]*?<form method="POST" action=\{formAction\}>/);
});

test('B. o POST de um clique chega como one_click e recebe 200', () => {
  assert.match(PAGE, /oneClick = form\.get\('List-Unsubscribe'\) === 'One-Click';/);
  assert.match(PAGE, /rpc\('campaign_unsubscribe', \{ p_token: token, p_one_click: oneClick \}\)/);
  assert.match(PAGE, /if \(oneClick\) \{\s+const ok = state === 'done' \|\| state === 'already';\s+return new Response\(ok \? 'ok' : state, \{\s+status: ok \? 200 :/);
});

test('C. o e-mail oferece o descadastro de um clique, com token e idioma', () => {
  assert.match(EF, /headers: \{ 'List-Unsubscribe': `<\$\{unsubUrl\}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' \}/);
  assert.match(EF, /const unsubUrl = `\$\{platformUrl\}\/unsubscribe\?token=\$\{r\.unsubscribe_token\}&lang=\$\{unsubLang\}`/);
});

test('D. a RPC registra uma vez, marca so campanha pendente do endereco e nao devolve o endereco', () => {
  assert.match(RPC, /IF v_id IS NULL THEN RETURN jsonb_build_object\('ok', false, 'reason', 'invalid_token'\); END IF;/);
  assert.match(RPC, /INSERT INTO public\.email_unsubscribes \(email, source, campaign_recipient_id\)\s+VALUES \(v_email, CASE WHEN p_one_click THEN 'one_click' ELSE 'link' END, v_id\)\s+ON CONFLICT \(email\) DO NOTHING;\s+v_new := FOUND;/);
  assert.match(RPC, /SET unsubscribed = true\s+WHERE cr\.unsubscribed IS DISTINCT FROM true\s+AND \(\s+cr\.id = v_id\s+OR \(\s+cr\.delivered IS DISTINCT FROM true\s+AND EXISTS \(\s+SELECT 1 FROM public\.campaign_sends cs\s+WHERE cs\.id = cr\.send_id AND COALESCE\(cs\.audience_filter->>'one_off', 'false'\) <> 'true'\s+\)\s+AND lower\(btrim\(COALESCE\(\(SELECT m\.email FROM public\.members m WHERE m\.id = cr\.member_id\), cr\.external_email\)\)\) = v_email/);
  assert.match(RPC, /RETURN jsonb_build_object\('ok', true, 'already', NOT v_new\);\s+END;/);
  assert.doesNotMatch(RPC, /jsonb_build_object\([^)]*v_email/, 'a resposta e anonima: nao pode levar o endereco');
});

test('E. a audiencia pula endereco descadastrado, de membro e de contato externo', () => {
  assert.match(SEND, /AND NOT public\._campaign_email_unsubscribed\(m\.email\)\s+LOOP\s+INSERT INTO public\.campaign_recipients \(send_id, member_id, language\)/);
  assert.match(SEND, /IF public\._campaign_email_unsubscribed\(v_ext_email\) THEN\s+v_skipped_unsubscribed := v_skipped_unsubscribed \+ 1;\s+CONTINUE;\s+END IF;\s+INSERT INTO public\.campaign_recipients \(send_id, external_email, external_name, language\)/);
  const helper = maskLineComments(latestFunctionCapture(ROOT, '_campaign_email_unsubscribed').block);
  assert.match(helper, /SELECT EXISTS \(SELECT 1 FROM public\.email_unsubscribes u WHERE u\.email = lower\(btrim\(p_email\)\)\)\s+OR EXISTS \(\s+SELECT 1 FROM public\.campaign_recipients cr\s+LEFT JOIN public\.members m ON m\.id = cr\.member_id\s+WHERE cr\.unsubscribed = true\s+AND lower\(btrim\(COALESCE\(m\.email, cr\.external_email\)\)\) = lower\(btrim\(p_email\)\)/);
});

test('F. tabela e auxiliar fechados; so a RPC por token abre para anon', () => {
  assert.match(SQL, /ALTER TABLE public\.email_unsubscribes ENABLE ROW LEVEL SECURITY;\s+REVOKE ALL ON TABLE public\.email_unsubscribes FROM anon, authenticated;/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\._campaign_email_unsubscribed\(text\) FROM PUBLIC, anon, authenticated;/);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.campaign_unsubscribe\(uuid, boolean\) TO anon, authenticated, service_role;/);
  assert.match(RPC, /SECURITY DEFINER\s+SET search_path TO ''/);
});

test('G. /en/ e /es/ redirecionam com o idioma', () => {
  for (const [dir, code] of [['en', 'en-US'], ['es', 'es-LATAM']]) {
    const p = resolve(ROOT, `src/pages/${dir}/unsubscribe.astro`);
    assert.ok(existsSync(p), `${p} nao existe`);
    const s = readFileSync(p, 'utf8');
    assert.match(s, new RegExp(`params\\.set\\('lang', '${code}'\\);\\s+return Astro\\.redirect\\(\`/unsubscribe\\?\\$\\{params\\.toString\\(\\)\\}\`\\);`));
  }
});
