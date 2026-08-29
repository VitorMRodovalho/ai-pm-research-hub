// tests/contracts/1962-uma-porta-so-para-entrar-na-tribo.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1962 — uma porta só para entrar (e sair) de tribo.
 *
 * Havia DUAS, com garantias diferentes, lendo prazos DIFERENTES em tabelas diferentes:
 *
 *   | | `request_tribe_assignment` | `select_tribe` |
 *   | prazo | `platform_settings` (2026-09-15) | `home_schedule` (2026-07-18, vencido) |
 *   | barra quem já tem tribo | sim | NÃO |
 *   | escreve | pedido → revisão do líder | direto, sem revisão |
 *   | repetir | recusa | `ON CONFLICT DO UPDATE` = TROCA a tribo |
 *   | EXECUTE | `authenticated` | **PUBLIC, anon**, authenticated |
 *
 * ⚠️ O `EXECUTE` para `anon` não estava na issue. Apareceu ao medir os grants, e é a armadilha de
 * `CREATE FUNCTION` nascer aberta: justamente a função que lia o prazo vencido e trocava a tribo em
 * silêncio era a que qualquer um podia chamar.
 *
 * DECISÃO DO PM (28/08): opção A — aposentar o caminho sem revisão. A razão não é a data: a revisão
 * do líder é o ATO DATÁVEL de que o #1948 depende para saber quando a pessoa entrou. O caminho sem
 * revisão não produz esse carimbo.
 *
 * Aposentar não custou UI: o front já tinha migrado no #1247 (ADR-0123).
 *
 * Cross-ref: #1962, #1247 (a retirada na UI), #1256 (`withdraw_from_initiative`, o caminho de
 * saída), #1948 (que depende do ato datável da revisão).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const SEL = latestFunctionCapture(ROOT, 'select_tribe');
const DES = latestFunctionCapture(ROOT, 'deselect_tribe');

test('#1962 estático: as duas legadas RECUSAM, nomeando o caminho canônico', () => {
  assert.ok(SEL && DES, 'select_tribe/deselect_tribe não foram capturadas');
  for (const [nome, cap, canonico] of [
    ['select_tribe', SEL, /request_tribe_assignment/],
    ['deselect_tribe', DES, /withdraw_from_initiative/],
  ]) {
    assert.match(cap.body, /RAISE\s+EXCEPTION/i, `${nome}: precisa recusar, não seguir funcionando`);
    assert.match(cap.body, canonico,
      `${nome}: a recusa tem de NOMEAR o caminho certo — erro de permissão sozinho não ensina nada`);
    // O que a função fazia não pode sobreviver dentro dela.
    assert.doesNotMatch(cap.body, /ON CONFLICT[\s\S]{0,40}DO UPDATE/i,
      `${nome}: a escrita legada continua no corpo`);
    assert.doesNotMatch(cap.body, /home_schedule/,
      `${nome}: ainda lê o prazo paralelo que motivou a aposentadoria`);
  }
});

test('#1962 estático: o REVOKE acompanha a recusa', () => {
  // Só recusar no corpo deixaria a porta aberta para quem tem EXECUTE; só revogar daria um erro de
  // permissão que não explica. As duas coisas juntas, ou o conserto é meio.
  const src = readFileSync(resolve(ROOT, 'supabase/migrations', SEL.file), 'utf8');
  assert.match(src, /REVOKE ALL ON FUNCTION public\.select_tribe\(integer\) FROM PUBLIC, anon, authenticated/,
    'select_tribe precisa perder o EXECUTE de PUBLIC/anon/authenticated');
  assert.match(src, /REVOKE ALL ON FUNCTION public\.deselect_tribe\(\) FROM PUBLIC, anon, authenticated/,
    'deselect_tribe idem');
});

test('#1962 vivo: o caminho CANÔNICO continua de pé', { skip: dbGated ? false : skipMsg }, async () => {
  // Controle na outra direção: aposentar a porta errada não pode ter fechado a certa. Sem isto, um
  // "as duas legadas recusam" seria compatível com ter quebrado a entrada em tribo inteira.
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
  assert.ok(!error, error?.message);
  // O campo e `proname`, nao `function_name`. Ler o campo errado devolve `undefined` para TODAS
  // as 1226 linhas, o Set fica com tamanho 1 e o `has()` responde false sempre — um guard que
  // sempre reprova, ou sempre passa, conforme o sentido da assercao. Medido em 28/08.
  const nomes = new Set((data ?? []).map((r) => r.proname));
  assert.ok(nomes.has('request_tribe_assignment'), 'a porta de entrada canônica sumiu');
  assert.ok(nomes.has('withdraw_from_initiative'), 'a porta de saída canônica sumiu');
});

test('#1962 vivo: o front não voltou a chamar as legadas', () => {
  // O #1247 já tinha migrado a UI. Se alguém reintroduzir a chamada, o REVOKE faz o botão falhar
  // em produção — e é melhor descobrir aqui.
  const alvos = [
    'src/components/tribe/TribeRequestBlock.tsx',
    'src/components/sections/TribesSection.astro',
  ];
  for (const f of alvos) {
    const src = readFileSync(resolve(ROOT, f), 'utf8');
    assert.doesNotMatch(src, /\.rpc\(\s*['"]select_tribe['"]/,
      `${f}: voltou a chamar select_tribe, que agora recusa`);
    assert.doesNotMatch(src, /\.rpc\(\s*['"]deselect_tribe['"]/,
      `${f}: voltou a chamar deselect_tribe, que agora recusa`);
  }
});
