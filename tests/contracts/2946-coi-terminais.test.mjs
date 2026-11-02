/**
 * Contract: #2946 (decisão do GP em 02/11/2026) — `selection_coi_recused` alinhado à ADR-0109 §3.
 *
 * O impedimento por conflito de interesse vale para quem tem candidatura NÃO terminal no ciclo. A ADR-0109 §3
 * diz que a candidatura aprovada deixa de fazer de alguém "candidato no ciclo"; o helper tratava como terminais
 * só rejected, withdrawn e cancelled, e assim quem já foi aprovado seguia impedido. Terminais agora: rejected,
 * withdrawn, cancelled, approved e converted. Os outros status do domínio seguem recusando (a decisão cobre só
 * approved e converted).
 *
 * Camadas:
 *   S  estática, na captura vigente do helper:
 *      - o conjunto de terminais, comparado como CONJUNTO, dentro do EXISTS que decide (candidatura do ciclo,
 *        casada por e-mail), e não solto no corpo;
 *      - o resto do helper igual: isenção de manage_platform, casamento por members.email e member_emails,
 *        LANGUAGE sql, STABLE, SECURITY DEFINER, search_path;
 *      - nenhum cliente executa o helper.
 *   L  viva: anon recebe 42501 no helper.
 * O efeito (quem deixa de ser recusado e quem continua) é a verificação do pacote, com candidatura sintética.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const HELPER = 'selection_coi_recused';
const TERMINAIS = ['approved', 'cancelled', 'converted', 'rejected', 'withdrawn'];

function captura() {
  const cap = latestFunctionCapture(ROOT, HELPER);
  assert.ok(cap, 'nenhuma migration cria o helper');
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

// O EXISTS que decide: candidatura do ciclo, fora dos terminais, casada por e-mail com o caller.
const RE_EXISTS = /AND EXISTS \( SELECT 1 FROM public\.selection_applications sa JOIN public\.members m ON m\.id = p_caller_id WHERE sa\.cycle_id = p_cycle_id AND sa\.status NOT IN \(([^)]*)\) AND sa\.email IS NOT NULL AND \( lower\(sa\.email\) = lower\(m\.email\) OR EXISTS \( SELECT 1 FROM public\.member_emails me WHERE me\.member_id = m\.id AND lower\(me\.email\) = lower\(sa\.email\) \) \) \);/;

test('#2946 S: os terminais da recusa são exatamente rejected, withdrawn, cancelled, approved e converted, no EXISTS que decide', () => {
  const { corpo } = captura();
  const m = corpo.match(RE_EXISTS);
  assert.ok(m, 'o EXISTS que decide a recusa não está na forma esperada');
  const lista = m[1].split(',').map((s) => s.trim().replace(/^'|'$/g, '')).sort();
  assert.deepEqual(lista, TERMINAIS, 'o conjunto de status terminais da recusa mudou');
  assert.equal((corpo.match(/sa\.status NOT IN \(/g) || []).length, 1, 'o helper tem outra lista de status');
});

test('#2946 S: o resto do helper não muda (isenção da gestão, atributos e o EXISTS como único critério)', () => {
  const { corpo } = captura();
  assert.match(corpo,
    /CREATE OR REPLACE FUNCTION public\.selection_coi_recused\(p_caller_id uuid, p_cycle_id uuid\) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS \$function\$ SELECT p_cycle_id IS NOT NULL AND p_caller_id IS NOT NULL AND NOT public\.can_by_member\(p_caller_id, 'manage_platform'\) AND EXISTS \(/,
    'a assinatura, os atributos ou a isenção de manage_platform mudaram');
});

function semGrantDepois(file, funcao, papeis) {
  const re = new RegExp(`GRANT[^;]*ON FUNCTION public\\.${funcao}\\b[^;]*\\b(${papeis})\\b`, 'i');
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= file)) {
    assert.doesNotMatch(maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')), re, `${f}: devolve ${funcao} a ${papeis}`);
  }
}

test('#2946 S: nenhum cliente executa o helper, e o service_role segue com EXECUTE', () => {
  const { file } = captura();
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  for (const papel of ['PUBLIC', 'anon', 'authenticated']) {
    assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.selection_coi_recused\\(uuid, uuid\\) FROM ${papel};`), `a migration não revoga ${papel}`);
  }
  assert.match(sql, /GRANT EXECUTE ON FUNCTION public\.selection_coi_recused\(uuid, uuid\) TO service_role;/, 'a migration não concede ao service_role');
  semGrantDepois(file, HELPER, 'anon|PUBLIC|authenticated');
});

// ─── L: vivo ──────────────────────────────────────────────────────────────────────

const URL_BASE = process.env.PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

test('#2946 L: anon recebe 42501 no helper (e não 404, que seria a função ausente)',
  { skip: URL_BASE && KEY && ANON ? false : 'sem credencial de banco' }, async () => {
    const zero = '00000000-0000-0000-0000-000000000000';
    const r = await dbFetch(`${URL_BASE}/rest/v1/rpc/${HELPER}`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_caller_id: zero, p_cycle_id: zero }),
    });
    const texto = await r.text();
    assert.ok([401, 403].includes(r.status), `anon recebeu ${r.status}: ${texto.slice(0, 160)}`);
    assert.match(texto, /"code":"42501"/, `a recusa a anon não é falta de permissão: ${texto.slice(0, 160)}`);
  });
