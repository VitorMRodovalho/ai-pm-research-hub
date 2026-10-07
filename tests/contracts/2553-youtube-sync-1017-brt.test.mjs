/**
 * #2553: o sync do YouTube roda também às 10:17 BRT (decisão do GP em 07/10/2026).
 *
 * As pílulas saem no YouTube por volta das 09:55 BRT. O job diário (06:00 UTC, 03:00 BRT) só trazia o vídeo no dia
 * seguinte, e sem o vídeo ingerido o episódio do /podcast fica sem o link. É uma rodada a mais por dia, não uma por
 * hora, porque a busca da API do YouTube custa 100 unidades por chamada.
 *
 * O QUE ESTE GUARD AFIRMA, sobre a migration que agenda o job (offline, só lê o arquivo):
 *   A. o job sync-comms-youtube-1017-brt roda uma vez por dia, às 13:17 UTC;
 *   B. a chamada vai para a EF sync-comms-metrics e pede só o canal youtube;
 *   C. a autenticação é a do job diário: header x-sync-secret com o segredo sync_comms_secret do vault.
 *      A chave de serviço não entra no comando agendado.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => f.endsWith('_2553_youtube_sync_1017_brt.sql'));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
// O bloco que decide: a chamada ao cron.schedule deste job, do nome até o fim do corpo $cron$.
const BLOCO = (SQL.match(/cron\.schedule\(\s*'sync-comms-youtube-1017-brt'[\s\S]*?\$cron\$[\s\S]*?\$cron\$/) || [''])[0];

test('A: uma migration só, e o job roda uma vez por dia às 13:17 UTC', () => {
  assert.equal(files.length, 1, `uma migration *_2553_youtube_sync_1017_brt.sql (achadas: ${files.length})`);
  assert.ok(BLOCO, 'o cron.schedule do job sync-comms-youtube-1017-brt');
  assert.match(BLOCO, /cron\.schedule\(\s*'sync-comms-youtube-1017-brt',\s*'17 13 \* \* \*'/);
});

test('B: a chamada vai para a sync-comms-metrics e pede só o canal youtube', () => {
  assert.match(BLOCO, /net\.http_post\(\s*url := 'https:\/\/[a-z0-9]+\.supabase\.co\/functions\/v1\/sync-comms-metrics'/);
  assert.match(BLOCO, /body := '\{"channels": \["youtube"\],[^']*\}'::jsonb/);
});

test('C: autentica como o job diário, sem a chave de serviço no comando', () => {
  assert.match(
    BLOCO,
    /'x-sync-secret',\s*\(SELECT decrypted_secret FROM vault\.decrypted_secrets WHERE name = 'sync_comms_secret' LIMIT 1\)/,
  );
  assert.doesNotMatch(BLOCO, /service_role/i, 'a chave de serviço fica fora do comando agendado');
  assert.doesNotMatch(BLOCO, /'Authorization'/, 'sem header Authorization: o caminho é o x-sync-secret');
});
