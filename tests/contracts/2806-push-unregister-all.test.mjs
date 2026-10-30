// tests/contracts/2806-push-unregister-all.test.mjs
/**
 * #2806: "desconectar clientes MCP" (signOut global) tambem apaga o push de TODOS os aparelhos do membro.
 *
 *   1. unregister_all_my_push_subscriptions apaga so as inscricoes do proprio membro (auth.uid()), recusa sem
 *      identidade e nao executa para anon;
 *   2. o perfil chama a funcao ANTES do signOut global (ela precisa da sessao), e a falha avisa em vez de sumir;
 *   3. o aviso de falha existe nos tres dicionarios.
 *
 * O arquivo da migration recebe a versao no apply, por isso o guard o acha pelo sufixo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const R = (p) => resolve(process.cwd(), p);
const FILES = readdirSync(R('supabase/migrations')).filter((f) => f.endsWith('_2806_push_unregister_all.sql'));
const SQL = FILES.length === 1
  ? readFileSync(R(`supabase/migrations/${FILES[0]}`), 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
  : '';
const PUSH = maskJsComments(readFileSync(R('src/lib/push.ts'), 'utf8'));
const PROFILE = maskJsComments(readFileSync(R('src/pages/profile.astro'), 'utf8'));

test('#2806 unregister_all: exatamente uma migration', () => {
  assert.equal(FILES.length, 1, `esperado 1 arquivo *_2806_push_unregister_all.sql, achei ${FILES.length}`);
});

test('#2806 unregister_all: apaga so as inscricoes do proprio membro, e nada para anon', () => {
  assert.match(SQL, /SELECT m\.id INTO v_member_id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\);\s+IF v_member_id IS NULL THEN\s+RAISE EXCEPTION 'Not authenticated'[^;]*;\s+END IF;\s+DELETE FROM public\.push_subscriptions s WHERE s\.member_id = v_member_id;/);
  assert.equal(SQL.split('DELETE FROM public.push_subscriptions').length - 1, 1, 'um unico DELETE, o do proprio membro');
  assert.match(SQL, /SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\.unregister_all_my_push_subscriptions\(\) FROM PUBLIC, anon;/);
  assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.unregister_all_my_push_subscriptions\(\) TO authenticated;/);
});

test('#2806 unregister_all: o perfil apaga o push de todos os aparelhos antes do signOut global', () => {
  assert.match(PUSH, /export async function unregisterAllDevices\(sb: RpcClient\)[\s\S]*?await rpcChecked\(sb, 'unregister_all_my_push_subscriptions'\);/);
  assert.match(PROFILE, /import \{ unregisterAllDevices \} from '\.\.\/lib\/push';/);
  assert.match(PROFILE, /try \{\s+await unregisterAllDevices\(sb\);\s+\} catch \{\s+\(window as any\)\.toast\?\.\(PROFILE_I18N\.toastPushUnregisterAllError[^;]*;\s+\}\s+const \{ error \} = await sb\.auth\.signOut\(\{ scope: 'global' \}\);/);
  // e nenhum signOut antes: a funcao do banco precisa da sessao
  const start = PROFILE.indexOf('async function disconnectMcpClients()');
  assert.ok(start > 0, 'disconnectMcpClients ausente');
  const body = PROFILE.slice(start, PROFILE.indexOf('\n  }\n', start));
  assert.equal(body.split('sb.auth.signOut(').length - 1, 1, 'um unico signOut em disconnectMcpClients');
  assert.ok(body.indexOf('await unregisterAllDevices(sb)') < body.indexOf('sb.auth.signOut('), 'o signOut veio antes de apagar o push');
});

test('#2806 unregister_all: o aviso de falha existe nos tres dicionarios', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(R(`src/i18n/${lang}.ts`), 'utf8');
    assert.match(dict, /\n {2}'profile\.toastPushUnregisterAllError': '[^']+',\n/, lang);
  }
  assert.match(PROFILE, /toastPushUnregisterAllError: t\('profile\.toastPushUnregisterAllError', lang\),/);
});
