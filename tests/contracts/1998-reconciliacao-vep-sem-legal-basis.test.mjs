/**
 * #1998 — a reconciliação VEP↔plataforma para de usar `legal_basis` como prova de vínculo.
 *
 * O PM olhou /admin/vep-reconciliation em 25/08 e viu a lista "Ativo no VEP sem contrato de
 * voluntário ativo" acusando gente que TEM engajamento ativo. As três CTEs do lado plataforma
 * de `get_vep_role_cohort_reconciliation` filtravam `e.legal_basis = 'contract'`. `legal_basis`
 * é a base legal LGPD Art. 7 do engajamento, não um estado de fluxo — e como a coluna tem
 * DEFAULT 'consent', ela funcionava na prática como proxy de "foi criado por
 * approve_selection_application". Medido 26/08: 5 de 5 linhas da lista eram falso positivo.
 *
 * O guard é derivado da CAPTURA VIGENTE (a última migration que define a função), não de um
 * nome de arquivo fixo: uma migration nova que redefina a função passa a ser o alvo automatica-
 * mente, em vez de o guard seguir afirmando texto que a produção não executa mais.
 *
 * Três garantias:
 *   (A) o predicado estreito não volta, e as duas correções que ele obriga continuam de pé;
 *   (B) o guard MORDE — a asserção é reexecutada contra o corpo com o filtro reinjetado e tem
 *       de reprovar (injeção que erra o alvo dá verde e seria lida como "a asserção não pega");
 *   (C) o corpo vivo é o corpo capturado, com mensagens separadas para DDL-lag e para regressão.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { loadLatestCaptures, normalizeBody } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const FN = 'get_vep_role_cohort_reconciliation';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/** Localiza a captura VIGENTE da função e devolve { file, body, bodyHash }. */
function capturaVigente() {
  const { latest } = loadLatestCaptures(MIGRATIONS);
  const entry = [...latest.entries()].find(([k]) => k.startsWith(`${FN}@`));
  assert.ok(entry, `nenhuma migration captura ${FN} — o guard ficaria vazio, não verde`);
  const [, meta] = entry;
  const sql = readFileSync(join(MIGRATIONS, meta.file), 'utf8');
  const start = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${FN}(`);
  assert.ok(start >= 0, `bloco de ${FN} não encontrado em ${meta.file}`);
  const marker = '$function$';
  const bodyStart = sql.indexOf(`AS ${marker}`, start) + `AS ${marker}`.length;
  const bodyEnd = sql.indexOf(`${marker};`, bodyStart);
  assert.ok(bodyEnd > bodyStart, `terminador ${marker}; não encontrado em ${meta.file}`);
  return { file: meta.file, body: sql.slice(bodyStart, bodyEnd), bodyHash: meta.bodyHash };
}

const conta = (haystack, needle) => haystack.split(needle).length - 1;

/**
 * A asserção central, isolada para poder ser reexecutada contra um corpo ADULTERADO.
 * Devolve a lista de violações (vazia = corpo saudável).
 */
function violacoes(body) {
  const v = [];
  if (conta(body, 'legal_basis') !== 0) {
    v.push('legal_basis voltou ao corpo: o lado plataforma não pode filtrar base legal LGPD');
  }
  const predicado = conta(body, "WHERE e.kind = 'volunteer' AND e.status = 'active'");
  if (predicado !== 3) {
    v.push(`esperava 3 predicados de volunteer ativo sem legal_basis, achei ${predicado}`);
  }
  const desempate = conta(body, '(e.selection_application_id IS NOT NULL) DESC');
  if (desempate !== 2) {
    v.push(
      `esperava 2 desempates por selection_application_id no DISTINCT ON, achei ${desempate}. ` +
      'Sem eles, largar o filtro faz a matriz eleger a linha sem FK e as pessoas sem coorte ' +
      'no lado plataforma saltam de 2 para 45 (medido 26/08).'
    );
  }
  const fallback = conta(body, "COALESCE(sc.cycle_code, va.cycle_code, 'no_cycle')");
  if (fallback !== 2) {
    v.push(
      `esperava 2 coortes com fallback por chave, achei ${fallback}. Sem ele as pessoas ` +
      'corrigidas caem em no_cycle, ou seja, a correção troca falso positivo numa lista por ' +
      'linha fora de lugar na matriz.'
    );
  }
  const lateral = conta(body, 'vc.cycle_code');
  if (lateral !== 2) v.push(`esperava 2 laterais va trazendo vc.cycle_code, achei ${lateral}`);
  return v;
}

// ── (A) o predicado estreito não volta ────────────────────────────────────────
test('#1998 static: a captura vigente não filtra legal_basis no lado plataforma', () => {
  const { file, body } = capturaVigente();
  const v = violacoes(body);
  assert.deepEqual(v, [], `captura ${file}:\n - ${v.join('\n - ')}`);
});

test('#1998 static: o lado VEP fica INTOCADO (controle negativo da varredura)', () => {
  const { file, body } = capturaVigente();
  // As duas CTEs `vep` derivam a coorte da candidatura pelo alias `c`, e NÃO devem ganhar
  // fallback nenhum: se a varredura tivesse pego demais, este número mudaria.
  assert.equal(
    conta(body, "COALESCE(c.cycle_code, 'no_cycle') AS cohort"), 2,
    `${file}: o lado VEP tem de manter as 2 coortes diretas — a correção é só do lado plataforma`
  );
  // E os portões que a #1838 instalou continuam de pé.
  assert.match(body, /can_by_member\(v_caller_id, 'view_internal_analytics'\)/, 'gate analytics');
  assert.match(body, /is_selection_committee_member\(v_caller_id, NULL\)/, 'gate do comitê');
  assert.match(body, /selection_coi_recused/, 'recusa por conflito de interesse');
});

// ── (B) o guard MORDE ─────────────────────────────────────────────────────────
test('#1998 static: a asserção reprova o corpo com o filtro reinjetado', () => {
  const { body } = capturaVigente();
  assert.deepEqual(violacoes(body), [], 'pré-condição: o corpo real está saudável');

  const adulterado = body.split("WHERE e.kind = 'volunteer' AND e.status = 'active'")
    .join("WHERE e.kind = 'volunteer' AND e.legal_basis = 'contract' AND e.status = 'active'");
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');

  const v = violacoes(adulterado);
  assert.ok(v.length > 0, 'a asserção tem de reprovar o corpo adulterado, senão ela não pega nada');
  assert.ok(v.some((m) => m.includes('legal_basis voltou')),
    `a violação nomeada tem de ser a do legal_basis, e veio: ${JSON.stringify(v)}`);
});

// ── (C) vivo == capturado ─────────────────────────────────────────────────────
test('#1998 db: o corpo vivo é o corpo capturado', { skip: dbGated ? false : skipMsg }, async () => {
  const { file, body, bodyHash } = capturaVigente();
  assert.equal(createHash('md5').update(normalizeBody(body)).digest('hex'), bodyHash,
    'sanidade: o md5 recomputado tem de bater com o do parser');

  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_list_public_function_bodies`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
    },
    body: '{}',
  });
  assert.equal(res.status, 200, `_audit_list_public_function_bodies respondeu ${res.status}`);
  const rows = await res.json();
  const live = rows.find((r) => r.proname === FN);
  assert.ok(live, `${FN} não existe no inventário vivo`);

  // Duas causas, duas mensagens deliberadamente diferentes: uma manda LANDAR o .sql, a outra
  // manda olhar o que mudou no corpo. Trocar as duas empurra para o conserto errado.
  if (live.body_md5 !== bodyHash) {
    const lag = live.prosrc_len !== body.length;
    assert.fail(
      lag
        ? `DDL-lag: o corpo vivo de ${FN} (${live.prosrc_len} bytes) difere da captura ` +
          `${file} (${body.length} bytes). Alguma DDL foi aplicada sem o .sql correspondente — ` +
          'landar/rebasear a migration que falta, NÃO editar este teste.'
        : `${FN} divergiu da captura ${file} com o MESMO tamanho (${body.length} bytes): ` +
          'alguém trocou o corpo vivo por outro de mesmo comprimento. Comparar prosrc com a captura.'
    );
  }
});
