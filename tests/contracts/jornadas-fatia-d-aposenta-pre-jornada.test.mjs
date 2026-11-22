/**
 * Jornadas, fatia D: a pré-jornada gamificada sai (decisão do GP em 20/11/2026).
 *
 * Ela morreu quando a FK onboarding_progress.step_key -> onboarding_steps (#2245) passou a impedir as chaves dela
 * (create_account, setup_credly, explore_platform, read_blog, start_pmi_certs). Ficaram três leitores e um semeador
 * que nunca faziam nada, e uma ilha no /workspace que chamava três RPCs a cada visita para devolver null.
 *
 * O guard afirma:
 *   D1. check_pre_onboarding_auto_steps fica só com o ramo de perfil e devolve a mesma forma;
 *   D2. get_candidate_onboarding_progress não devolve mais o agregado pre_onboarding nem xp e phase por etapa;
 *   D3. a migration remove as duas funções mortas e não apaga dado;
 *   D4. nenhuma função vigente chama as removidas, e nenhuma migration posterior as recria;
 *   D5. nenhum arquivo do front, das EFs ou dos scripts cita o que saiu;
 *   D6. emulação do #785 sobre a migration.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join, sep } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const ALL = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
const migFiles = ALL.filter((f) => f.endsWith('_jornadas_d_aposenta_pre_jornada.sql'));
const RAW = migFiles.length === 1 ? readFileSync(join(MIG_DIR, migFiles[0]), 'utf8') : '';
const MIG = maskLineComments(RAW);
const cap = (n) => maskLineComments(latestFunctionCapture(ROOT, n).block);

const MORTAS = ['create_account', 'setup_credly', 'explore_platform', 'read_blog', 'start_pmi_certs'];
const REMOVIDAS = ['get_pre_onboarding_leaderboard', 'seed_pre_onboarding_steps'];

test('D0. a migration existe e é uma só', () => {
  assert.equal(migFiles.length, 1, `uma migration *_jornadas_d_aposenta_pre_jornada.sql (achadas: ${migFiles.length})`);
});

test('D1. a checagem fica só com o ramo de perfil e devolve a mesma forma', () => {
  const b = cap('check_pre_onboarding_auto_steps');
  assert.equal(latestFunctionCapture(ROOT, 'check_pre_onboarding_auto_steps').file?.split('/').pop(), migFiles[0],
    'a captura vigente é a da fatia D');
  for (const k of MORTAS) assert.doesNotMatch(b, new RegExp(`'${k}'`), `o ramo ${k} voltou`);
  assert.doesNotMatch(b, /member_activity_sessions/, 'a checagem voltou a ler a navegação do membro');
  assert.match(b, /SELECT id INTO v_member FROM members WHERE id = p_member_id;\s+IF v_member\.id IS NULL THEN\s+RETURN json_build_object\('error', 'Member not found'\);/);
  const blk = b.slice(b.indexOf("op.step_key = 'complete_profile'"), b.lastIndexOf('RETURN json_build_object('));
  assert.match(blk, /op\.step_key = 'complete_profile' AND op\.status IN \('pending', 'overdue'\)\s+AND v_profile_complete\s+AND EXISTS \(SELECT 1 FROM onboarding_steps s\s+WHERE s\.id = 'complete_profile'\s+AND public\.onboarding_step_applies\(s\.applies_to_role, public\._onboarding_journey_role\(p_member_id\)\)\);/,
    'o ramo de perfil perdeu a regra da fatia C');
  assert.equal((b.match(/\bUPDATE onboarding_progress\b/g) || []).length, 1, 'a checagem escreve só a etapa de perfil');
  assert.match(b, /RETURN json_build_object\(\s+'auto_completed', v_completed,\s+'member_id', p_member_id,\s+'profile_complete', v_profile_complete\s+\);\s+END;/,
    'o retorno mudou de forma');
});

test('D2. o progresso do candidato não devolve mais a pré-jornada', () => {
  const b = cap('get_candidate_onboarding_progress');
  assert.equal(latestFunctionCapture(ROOT, 'get_candidate_onboarding_progress').file?.split('/').pop(), migFiles[0],
    'a captura vigente é a da fatia D');
  assert.doesNotMatch(b, /'pre_onboarding'/, 'o agregado pre_onboarding voltou');
  assert.doesNotMatch(b, /metadata->>'(phase|xp)'/, 'xp ou phase por etapa voltou');
  for (const k of MORTAS) assert.doesNotMatch(b, new RegExp(`WHEN '${k}'`), `a ordenação morta de ${k} voltou`);
  assert.match(b, /'sla_deadline', op\.sla_deadline\s+\) ORDER BY\s+CASE op\.step_key\s+WHEN 'complete_profile' THEN 2\s+WHEN 'code_of_conduct' THEN 7/,
    'cada etapa devolve até o prazo, e a ordem das etapas vivas não muda');
  assert.match(b, /\), '\[\]'::json\),\s+'onboarding', json_build_object\(\s+'total',/, 'o agregado onboarding segue logo depois das etapas');
  assert.match(b, /v_member_role := public\._onboarding_journey_role\(v_mid\);/, 'o recorte pelo papel da jornada (#3156) continua');
});

test('D3. a migration remove as duas funções mortas e não apaga dado', () => {
  assert.match(MIG, /^DROP FUNCTION public\.get_pre_onboarding_leaderboard\(\);$/m);
  assert.match(MIG, /^DROP FUNCTION public\.seed_pre_onboarding_steps\(uuid, uuid\);$/m);
  assert.doesNotMatch(MIG, /IF EXISTS/i, 'DROP sem IF EXISTS: se a função não estiver lá, o pacote está errado e deve falhar');
  assert.doesNotMatch(MIG, /\bDELETE\b|\bTRUNCATE\b|\bDROP\s+(TABLE|COLUMN)\b|ALTER\s+TABLE/i, 'a fatia D não apaga nem altera dado');
  assert.doesNotMatch(MIG, /gamification_points/, 'o ledger de XP não é tocado');
  assert.equal((MIG.match(/CREATE OR REPLACE FUNCTION/g) || []).length, 2);
  assert.match(MIG, /NOTIFY pgrst, 'reload schema';\s*$/);
});

test('D4. nenhuma função vigente chama as removidas, e nenhuma migration posterior as recria', () => {
  const iD = ALL.indexOf(migFiles[0]);
  assert.ok(iD >= 0);
  for (const n of REMOVIDAS) {
    const recria = ALL.slice(iD + 1).filter((f) => new RegExp(`FUNCTION\\s+(public\\.)?${n}\\(`).test(readFileSync(join(MIG_DIR, f), 'utf8')));
    assert.deepEqual(recria, [], `${n} foi recriada depois da fatia D`);
  }
  // Candidatas: toda função que, em alguma captura da história, chamou uma das removidas. A captura vigente decide.
  const CHAMA = new RegExp(`\\b(${REMOVIDAS.join('|')})\\s*\\(`);
  const nomes = new Set();
  for (const f of ALL) {
    const sql = maskLineComments(readFileSync(join(MIG_DIR, f), 'utf8'));
    if (!CHAMA.test(sql)) continue;
    const heads = [...sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?(\w+)\s*\(/gi)];
    heads.forEach((m, i) => {
      const bloco = sql.slice(m.index, i + 1 < heads.length ? heads[i + 1].index : sql.length);
      const corpo = (bloco.match(/AS\s+(\$\w*\$)([\s\S]*?)\1/) || [])[2] || '';
      if (CHAMA.test(corpo)) nomes.add(m[1]);
    });
  }
  // Medido em 21/11: nenhuma função da história chamou as duas. O controle mostra que o detector sabe dizer sim.
  const sim = maskLineComments('AS $function$\nBEGIN\n  PERFORM public.seed_pre_onboarding_steps(v_app, v_mid);\nEND;\n$function$');
  const nao = maskLineComments('AS $function$\nBEGIN\n  -- quem chamaria seed_pre_onboarding_steps(), sem chamador\nEND;\n$function$');
  assert.ok(CHAMA.test((sim.match(/AS\s+(\$\w*\$)([\s\S]*?)\1/) || [])[2] || ''), 'o detector não reconhece uma chamada');
  assert.ok(!CHAMA.test((nao.match(/AS\s+(\$\w*\$)([\s\S]*?)\1/) || [])[2] || ''), 'o detector acusa um comentário');
  const chamadores = [];
  for (const n of [...nomes].filter((x) => !REMOVIDAS.includes(x)).sort()) {
    const body = cap(n);
    for (const r of REMOVIDAS) if (new RegExp(`\\b${r}\\s*\\(`).test(body)) chamadores.push(`${n} -> ${r}`);
  }
  assert.deepEqual(chamadores, [], 'função vigente chama o que a fatia D removeu');
});

test('D5. nenhum arquivo do front, das EFs ou dos scripts cita o que saiu', () => {
  const walk = (d) => readdirSync(resolve(ROOT, d), { recursive: true })
    .map((f) => `${d}/${String(f).split(sep).join('/')}`)
    .filter((f) => /\.(tsx?|astro|mjs|js|json)$/.test(f));
  const files = [...walk('src'), ...walk('supabase/functions'), ...walk('scripts')];
  assert.ok(files.length > 300, `só ${files.length} arquivos: a varredura não está olhando o repositório`);
  const ALVO = /PreOnboardingChecklist|get_pre_onboarding_leaderboard|seed_pre_onboarding_steps|phase\s*===\s*'pre_onboarding'|\.pre_onboarding\b/;
  const achados = files.filter((f) => ALVO.test(maskJsComments(readFileSync(resolve(ROOT, f), 'utf8'))));
  assert.deepEqual(achados, [], 'ainda há quem leia a pré-jornada');
});

test('D6. emulação do #785: nenhuma SECDEF da migration seria acusada', () => {
  const fns = [...RAW.matchAll(/CREATE (?:OR REPLACE )?FUNCTION public\.(\w+)\(([^)]*)\)[\s\S]*?AS \$(\w*)\$([\s\S]*?)\$\3\$/g)];
  assert.equal(fns.length, 2, `esperava 2 funções, achei ${fns.length}`);
  for (const [hdr, name, , , body] of fns) {
    const secdef = /SECURITY DEFINER/.test(hdr);
    const reads = /(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)/.test(body)
      || /\bevents\b/.test(body) || /\binitiatives\b/.test(body);
    const writer = /(INSERT |UPDATE |DELETE )/.test(body.toUpperCase());
    const revokedAuth = new RegExp(`REVOKE[^;]*FUNCTION public\\.${name}\\([^;]*FROM[^;]*authenticated`).test(RAW);
    const gated = /rls_can_see_(initiative|board|item)|confidential/.test(body);
    if (secdef && reads && !writer && !revokedAuth) assert.ok(gated, `${name} seria acusada pelo #785`);
  }
});
