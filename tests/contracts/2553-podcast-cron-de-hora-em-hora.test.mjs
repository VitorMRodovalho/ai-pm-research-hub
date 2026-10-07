/**
 * #2553: o podcast sincroniza de hora em hora (decisão do GP, 06/10/2026, Decisão 2, opção A).
 *
 * O job diário (06:00 UTC) deixaria cada episódio novo até um dia fora de /podcast. Este job roda a EF
 * sync-comms-metrics só para o canal spotify, que lê o RSS público, sem cota e sem token.
 *
 * O QUE ESTE GUARD AFIRMA, sobre a migration que agenda o job (offline, só lê o arquivo):
 *   A. o job sync-comms-podcast-hourly roda no minuto 17 de cada hora;
 *   B. a chamada vai para a EF sync-comms-metrics e pede só o canal spotify;
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
const files = readdirSync(DIR).filter((f) => f.endsWith('_2553_podcast_sync_de_hora_em_hora.sql'));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
// O bloco que decide: a chamada ao cron.schedule deste job, do nome até o fim do corpo $cron$.
const BLOCO = (SQL.match(/cron\.schedule\(\s*'sync-comms-podcast-hourly'[\s\S]*?\$cron\$[\s\S]*?\$cron\$/) || [''])[0];

test('A: uma migration só, e o job roda no minuto 17 de cada hora', () => {
  assert.equal(files.length, 1, `uma migration *_2553_podcast_sync_de_hora_em_hora.sql (achadas: ${files.length})`);
  assert.ok(BLOCO, 'o cron.schedule do job sync-comms-podcast-hourly');
  assert.match(BLOCO, /cron\.schedule\(\s*'sync-comms-podcast-hourly',\s*'17 \* \* \* \*'/);
});

test('B: a chamada vai para a sync-comms-metrics e pede só o canal spotify', () => {
  assert.match(BLOCO, /net\.http_post\(\s*url := 'https:\/\/[a-z0-9]+\.supabase\.co\/functions\/v1\/sync-comms-metrics'/);
  assert.match(BLOCO, /body := '\{"channels": \["spotify"\],[^']*\}'::jsonb/);
});

test('C: autentica como o job diário, sem a chave de serviço no comando', () => {
  assert.match(
    BLOCO,
    /'x-sync-secret',\s*\(SELECT decrypted_secret FROM vault\.decrypted_secrets WHERE name = 'sync_comms_secret' LIMIT 1\)/,
  );
  assert.doesNotMatch(BLOCO, /service_role/i, 'a chave de serviço fica fora do comando agendado');
  assert.doesNotMatch(BLOCO, /'Authorization'/, 'sem header Authorization: o caminho é o x-sync-secret');
});
