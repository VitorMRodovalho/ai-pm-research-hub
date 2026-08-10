/**
 * Contract: #1710 (passo 2) — a elegibilidade da grade fala a mesma lingua da coorte do selo.
 *
 * Decisao do PM em 10/08/2026, sobre duas perguntas de REGRA:
 *   1. sponsor e chapter_liaison fora do tier operacional NAO sao cobrados de presenca em geral;
 *   2. gestor sem tribo propria NAO e elegivel a reuniao de tribo.
 *
 * Por que isto e pre-requisito do selo automatico. `seal_event_attendance` grava present=false
 * para a coorte dele e carimba `roster_sealed_at`; a grade, com o carimbo preenchido, resolve
 * "sem linha" no ramo ELSE como 'absent'. Se a coorte da grade for MAIOR que a do selo, selar
 * acusa quem o selo nunca alcanca, SEM nenhum registro — a acusacao inferida que o #1657
 * removeu, voltando pela porta do selo. Medido em 10/08, antes deste ajuste: selar os 53 eventos
 * do ciclo produziria 121 linhas reais (53 pessoas) e 133 celulas 'absent' sem linha (16 pessoas).
 *
 * Duas mudancas que se sustentam UMA NA OUTRA, e por isso sao um contrato so:
 *   (a) o gate de TIER restringe a elegibilidade;
 *   (b) 'na' passa a exigir AUSENCIA DE REGISTRO.
 * Sem (b), (a) apagaria da tela 5 presencas reais e zeraria a coorte historica do #156: 0 de 34
 * ex-membros estao no tier, mas 29 tem presenca registrada.
 *
 * ⚠️ O predicado e o TIER (`v_member_operational_tiers`), NUNCA `operational_role`: 2
 * chapter_liaison ESTAO no tier. Sao vocabularios diferentes de autoridade, e trocar um pelo
 * outro reintroduz o defeito com o teste verde.
 *
 * Camadas: A estatica sobre a captura DERIVADA (com a inversa de cada afirmacao), A' md5 do
 * corpo vivo, B varredura do front com controle positivo, C a fonte do predicado existe no vivo
 * (uma camada estatica nao percebe uma view renomeada).
 *
 * Migration: 20260810153301_1710_elegibilidade_da_grade_fala_a_lingua_do_selo.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import {
  loadLatestCaptures, parseMigration, normalizeBody, md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');
const CHAVE = 'get_attendance_grid@p_tribe_id integer, p_event_type text';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

function capturaMaisRecente() {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const cap = latest.get(CHAVE);
  assert.ok(cap, `sem captura de migration para ${CHAVE}`);
  const blocos = parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8'));
  const bloco = blocos.find(b => `${b.name}@${b.args}` === CHAVE);
  assert.ok(bloco, `${cap.file} nao contem o bloco de ${CHAVE}`);
  return { file: cap.file, bodyHash: cap.bodyHash, body: bloco.body };
}

/** Comentarios fora: um guard que le o texto cru casa a propria explicacao (#1586b). */
const achatado = (s) => s.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');

// ── A ────────────────────────────────────────────────────────────────────────────────────

test('#1710 A: a elegibilidade e gateada pelo TIER, e nao pelo operational_role', () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);

  assert.match(
    codigo,
    /WHEN NOT EXISTS \(SELECT 1 FROM public\.v_member_operational_tiers vt WHERE vt\.member_id = m\.id AND vt\.operational_tier IN \('researcher', 'tribe_leader', 'manager'\)\) THEN false/i,
    `${file}: sem o gate de tier, a grade volta a cobrar presenca de quem o selo nao alcanca`,
  );
  // A INVERSA que importa: trocar o tier por operational_role deixaria 2 chapter_liaison de fora
  // indevidamente. Um gate por papel na posicao do gate de tier e regressao, nao equivalencia.
  assert.doesNotMatch(
    codigo,
    /WHEN NOT \(?m\.operational_role IN \([^)]*\)\)? THEN false/i,
    `${file}: o gate de elegibilidade nao pode ser por operational_role`,
  );
});

test('#1710 A: o gestor deixou de ser elegivel a TODA reuniao de tribo', () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);

  assert.match(
    codigo,
    /WHEN ge\.type = 'tribo' AND \(m\.tribe_id = ge\.tribe_id OR \(p_tribe_id IS NOT NULL AND ge\.tribe_id = p_tribe_id\)\) THEN true/i,
    `${file}: o ramo 'tribo' tem de exigir tribo propria (ou o escopo explicito da chamada)`,
  );
  assert.doesNotMatch(
    codigo,
    /ge\.type = 'tribo' AND \([^)]*m\.operational_role IN \('manager', 'deputy_manager'\)/i,
    `${file}: o ramo que dava ao gestor elegibilidade em toda tribo voltou (eram 93 celulas)`,
  );
});

test("#1710 A: 'na' exige AUSENCIA DE REGISTRO, senao a restricao apaga presenca real", () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);

  assert.match(
    codigo,
    /WHEN NOT el\.is_eligible AND a\.id IS NULL THEN 'na'/i,
    `${file}: 'na' incondicional engole o registro de quem compareceu sem ser elegivel`,
  );
  // A INVERSA: a forma antiga nao pode coexistir. Ela vem ANTES no CASE e venceria.
  assert.doesNotMatch(
    codigo,
    /WHEN NOT el\.is_eligible THEN 'na'/i,
    `${file}: a forma incondicional de 'na' voltou`,
  );
});

test('#1710 A: o ramo ELSE que infere falta so existe sob evento SELADO', () => {
  const { body, file } = capturaMaisRecente();
  const codigo = achatado(body);
  // O contrato do #1657 e a razao de todo este ajuste existir: sem evento selado, nunca falta.
  assert.match(codigo, /WHEN ge\.roster_sealed_at IS NULL THEN 'unrecorded' ELSE 'absent' END/i,
    `${file}: o par unrecorded/absent do #1657 foi alterado; re-medir antes de seguir`);
});

// ── A' ───────────────────────────────────────────────────────────────────────────────────

test("#1710 A': o corpo VIVO == a captura mais recente", {
  skip: dbGated ? false : skipMsg,
}, async () => {
  const { bodyHash, file } = capturaMaisRecente();
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/_audit_function_source`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
    body: JSON.stringify({ p_proname: 'get_attendance_grid' }),
  });
  assert.ok(res.ok, `_audit_function_source devia responder 2xx (veio ${res.status})`);
  const linhas = await res.json();
  assert.equal(linhas.length, 1, 'esperado exatamente 1 get_attendance_grid em pg_proc');
  assert.equal(md5(normalizeBody(linhas[0].prosrc)), bodyHash,
    `corpo vivo divergente de ${file}: a mudanca esta so num dos dois lados`);
});

// ── B ────────────────────────────────────────────────────────────────────────────────────

const GRID_TAB = resolve(ROOT, 'src/components/attendance/AttendanceGridTab.tsx');

test('#1710 B: quem nao tem celula elegivel nao e exibido como 0%', () => {
  const src = readFileSync(GRID_TAB, 'utf8');
  // controle POSITIVO: sem estes simbolos o scanner nao esta olhando o arquivo certo (#1636).
  assert.match(src, /const formatRate = /, 'controle positivo: formatRate sumiu do arquivo');
  assert.match(src, /const temTaxa = \(eligibleCount: number\) => eligibleCount > 0;/,
    'o predicado de "tem taxa" tem de ser eligible_count, nao o proprio percentual');

  // nenhuma renderizacao crua do percentual: 0% para quem nao e cobrado le como "nao foi a nada".
  assert.doesNotMatch(src, /\{r\.rate\.toFixed\(1\)\}%/,
    'sobrou renderizacao crua de r.rate; use formatRate(r.rate, r.eligibleCount)');
  assert.doesNotMatch(src, /\{Math\.round\(v\)\}%/,
    'sobrou a celula antiga da coluna de taxa, que ignora eligible_count');
});

test('#1710 B: a media dos KPIs corre so sobre quem TEM taxa', () => {
  const src = readFileSync(GRID_TAB, 'utf8');
  assert.match(src, /const filteredKPIs = useMemo\(/, 'controle positivo: filteredKPIs sumiu');
  const memo = src.slice(src.indexOf('const filteredKPIs = useMemo('));
  const corpo = memo.slice(0, memo.indexOf('}, [filteredRows]);'));
  assert.match(corpo, /filter\(\(m\) => temTaxa\(m\.eligibleCount\)\)/,
    'a media incluiria os zeros de quem nao tem celula elegivel, puxando o KPI para baixo');
});

test('#1710 B: o CSV nao exporta zero falso', () => {
  const src = readFileSync(GRID_TAB, 'utf8');
  assert.match(src, /temTaxa\(r\.eligibleCount\) \? `\$\{r\.rate\.toFixed\(1\)\}` : ''/,
    'o CSV precisa de celula VAZIA para quem nao tem taxa; um 0 vira media falsa na planilha');
});

// ── C ────────────────────────────────────────────────────────────────────────────────────

test('#1710 C: a fonte do predicado existe e responde no vivo', {
  skip: dbGated ? false : skipMsg,
}, async () => {
  // Uma camada estatica nao percebe uma view renomeada ou removida: a RPC so falharia em runtime,
  // para o chamador autenticado que o service_role nao consegue simular.
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/v_member_operational_tiers?select=member_id,operational_tier&limit=5`,
    { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } },
  );
  assert.ok(res.ok, `v_member_operational_tiers devia responder 2xx (veio ${res.status})`);
  const linhas = await res.json();
  assert.ok(linhas.length > 0, 'v_member_operational_tiers vazia: o gate de tier reprovaria TODO MUNDO');
  for (const l of linhas) {
    assert.ok(typeof l.operational_tier === 'string' && l.operational_tier.length > 0,
      'operational_tier tem de vir preenchido; NULL nao casa o IN e derruba a elegibilidade');
  }
});
