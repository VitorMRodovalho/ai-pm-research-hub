// tests/contracts/2806-push-envio-cron.test.mjs
/**
 * #2806, envio do push: prende a migration que agenda a EF send-push e a lista de hosts de servico de push.
 *
 *   1. o job chama a EF send-push com a service_role_key do vault, e SO quando ha aviso imediato sem marca de push;
 *   2. a lista de hosts nasce com os quatro servicos, e o nome da chave e o mesmo que a EF le (um nome trocado de um
 *      lado deixaria a EF sem lista, e ela recusaria enviar: falha silenciosa no sentido seguro, mas silenciosa).
 *
 * O arquivo recebe a versao no apply, por isso o guard o acha pelo sufixo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const DIR = resolve(process.cwd(), 'supabase/migrations');
const FILES = readdirSync(DIR).filter((f) => f.endsWith('_2806_push_envio_cron.sql'));
const SQL = FILES.length === 1
  ? readFileSync(resolve(DIR, FILES[0]), 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
  : '';
const EF = readFileSync(resolve(process.cwd(), 'supabase/functions/send-push/index.ts'), 'utf8');

test('#2806 cron: exatamente uma migration do agendamento', () => {
  assert.equal(FILES.length, 1, `esperado 1 arquivo *_2806_push_envio_cron.sql, achei ${FILES.length}`);
});

test('#2806 cron: chama send-push com a chave do vault e so com aviso imediato pendente', () => {
  assert.match(SQL, /SELECT cron\.unschedule\('send-push'\)\nWHERE EXISTS \(SELECT 1 FROM cron\.job WHERE jobname = 'send-push'\);\n\nSELECT cron\.schedule\(\n  'send-push',/);
  assert.match(SQL, /SELECT cron\.schedule\(\s+'send-push',\s+'\* \* \* \* \*',\s+\$cron\$\s+SELECT net\.http_post\(\s+url := 'https:\/\/ldrfrvwhxsmgaabwmaik\.supabase\.co\/functions\/v1\/send-push',[\s\S]*?'Authorization', 'Bearer ' \|\| \(SELECT decrypted_secret FROM vault\.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1\)\s+\),\s+timeout_milliseconds := 30000\s+\)\s+WHERE EXISTS \(\s+SELECT 1 FROM public\.notifications n\s+WHERE n\.delivery_mode = 'transactional_immediate' AND n\.push_dispatched_at IS NULL\s+\);\s+\$cron\$\s+\);/);
});

test('#2806 cron: a lista de hosts tem os quatro servicos e a chave e a que a EF le', () => {
  const m = SQL.match(/\('push_service_hosts', '(\[[^']*\])'::jsonb,/);
  assert.ok(m, 'insert de push_service_hosts ausente');
  assert.deepEqual(JSON.parse(m[1]).sort(), ['fcm.googleapis.com', 'notify.windows.com', 'push.apple.com', 'updates.push.services.mozilla.com']);
  assert.match(EF, /\.from\('platform_settings'\)\.select\('value'\)\.eq\('key', 'push_service_hosts'\)/);
});
