// Pertencimento, parte 2 (GP 26/10/2026): a liderança de cada linha e os rostos de "Quem faz", só com o consentimento
// da Cláusula 11 do Termo de Adesão, filtrado por pessoa, com revogação no perfil.
//
// O guard afirma, na captura vigente de cada função e no código que a home e o perfil entregam (comentários mascarados):
//   A. uma regra, numa função: vale a decisão explícita mais recente no ledger (linha ativa = sim; só linhas revogadas
//      = não); sem decisão, o termo vigente com a frase da Cláusula 11; o termo vigente é o issued sem revoked_at mais
//      recente; a frase mora numa função só; a liberação de comunicação segue com o predicado de #729;
//   B. os ajudantes não executam para PUBLIC, anon nem authenticated;
//   C. a foto só com o nome opaco, no host e no bucket do projeto, e as duas leitoras só saem por esse filtro;
//   D. get_public_line_leaders: quatro colunas, só com consentimento, a janela e o portão da home, vídeo só de leader;
//   E. get_public_team_faces: os grupos e os predicados da home, só com consentimento e foto opaca, até 8, e os pontos
//      focais só como nome de capítulo;
//   F. as escritas são as de #570: autorizar é grant_image_voice_consent, sem redefinição; revogar é
//      revoke_image_voice_consent, redefinida com o ramo da linha nascida revogada para quem consente pelo termo, nunca
//      apagando; get_my_image_consent lê pela regra e entrega o texto da cláusula; a pós-condição exerce o perfil numa
//      subtransação desfeita, com resíduo zero;
//   G. #965: as leitoras não escrevem nem chamam http, e a lista daquele teste não muda;
//   H. a home: liderança e rostos só pelas leitoras, imagem com largura, altura, lazy e async, "+N" pela contagem da
//      home, pontos focais sem rosto, e o filtro opaco repetido no servidor da página;
//   I. o perfil: o interruptor lê get_my_image_consent; quem assinou antes da cláusula vê o texto dela (por textContent)
//      e autoriza ali, com displayed_version; ligar chama grant_image_voice_consent e desligar, revoke_image_voice_consent;
//   J. /privacy, registro da decisão e dicionários: a passagem nos 3 idiomas, a emenda sem nome, as chaves nos 3;
//   K. (banco) como anon, as duas leitoras respondem só com as chaves nomeadas, e os ajudantes recusam;
//   L. os leitores da home, EXERCIDOS com fetch simulado (hermético): foto de nome com e-mail vira "sem foto", chave a
//      mais não passa, até 8 rostos, pontos focais sem rosto, vídeo de fora do YouTube cai, e a imagem sai sempre do
//      host do projeto, nunca do host que veio na resposta.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { after } from 'node:test';
import { buildSync } from 'esbuild';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const norm = (s) => s.replace(/\s+/g, ' ').trim();
const maskAstro = (src) => maskJsComments(src).replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const value = (dict, key) => dict.match(new RegExp(`^  '${esc(key)}': '((?:[^'\\\\]|\\\\.)*)',$`, 'm'))?.[1];
const DICTS = { 'pt-BR': read('src/i18n/pt-BR.ts'), 'en-US': read('src/i18n/en-US.ts'), 'es-LATAM': read('src/i18n/es-LATAM.ts') };
const PHRASE = 'autoriza o uso de sua imagem e de sua voz';
const EM_DASH = '\u2014';

/** A captura vigente de uma função, com o corpo normalizado e sem comentários de linha. */
function cap(name) {
  const c = latestFunctionCapture(ROOT, name);
  return { ...c, n: norm(maskLineComments(c.body)), head: norm(maskLineComments(c.block.slice(0, c.block.search(/\sAS \$/)))) };
}
const HAS = cap('_member_has_image_consent');
const TERM = cap('_member_current_term');
const CLAUSE = cap('_member_term_has_image_clause');
const CLAUSE_TEXT = cap('_current_term_image_clause');
const PHOTO = cap('_public_member_photo_url');
const LEADERS = cap('get_public_line_leaders');
const FACES = cap('get_public_team_faces');
const REVOKE = cap('revoke_image_voice_consent');
const GRANT = cap('grant_image_voice_consent');
const GET = cap('get_my_image_consent');
const HOME = cap('get_public_home_team');
const FILE = maskLineComments(read(`supabase/migrations/${HAS.file}`));

const GROUPS = ['management', 'line_leaders', 'initiative_leaders', 'curators', 'hub_members', 'chapter_focal_points', 'researchers'];
/** O bloco de um grupo na home: de 'grupo', ( até o próximo grupo (ou o fim do objeto). */
function homeBlock(key) {
  const start = HOME.n.indexOf(`'${key}', (`);
  assert.ok(start >= 0, `get_public_home_team sem o grupo ${key}`);
  const next = GROUPS.map((g) => HOME.n.indexOf(`'${g}', (`, start + 1)).filter((i) => i > start);
  const end = next.length ? Math.min(...next) : HOME.n.indexOf(');', start);
  return HOME.n.slice(start, end).trim().replace(/,$/, '');
}
/** Pares origem|predicado de um trecho: FROM <origem> <apelido> WHERE <predicado>, até UNION ALL ou o fecho. */
const wherePairs = (text) => [...text.matchAll(/FROM ([\w.]+) (\w+) WHERE (.+?)(?= UNION ALL | \) c \)| \)$|$)/g)]
  .map((m) => `${m[1]} ${m[2]} | ${m[3]}`).sort();
/** O SELECT de um CTE: name AS ( SELECT ... ) seguido de vírgula ou do SELECT final. */
const cte = (body, name) => body.match(new RegExp(`${name} AS \\( (SELECT [\\s\\S]*?) \\)(?:,| SELECT )`))?.[1] ?? '';
const LEDGER = "SELECT 1 FROM public.consent_records cr WHERE cr.member_id = p_member_id AND cr.policy_type = 'image_voice_publicity'";

describe('pertencimento parte 2: consentimento da Cláusula 11', () => {
  it('A1: uma regra: a decisão mais recente do ledger vale; sem decisão, o termo vigente com a cláusula', () => {
    assert.equal(HAS.n, `SELECT p_member_id IS NOT NULL AND coalesce( CASE WHEN EXISTS ( ${LEDGER} AND cr.revoked_at IS NULL) THEN true WHEN EXISTS ( ${LEDGER}) THEN false END, public._member_term_has_image_clause(p_member_id));`);
    assert.equal(TERM.n, "SELECT c.id FROM public.certificates c WHERE c.member_id = p_member_id AND c.type = 'volunteer_agreement' AND c.status = 'issued' AND c.revoked_at IS NULL ORDER BY c.issued_at DESC, c.id DESC LIMIT 1;");
    assert.equal(CLAUSE.n, `SELECT coalesce(( SELECT strpos(coalesce(c.content_snapshot->>'html_body', ''), '${PHRASE}') > 0 FROM public.certificates c WHERE c.id = public._member_current_term(p_member_id) ), false);`);
  });

  it('A2: a frase da cláusula mora numa função só, e a migration confere que o termo ativo a tem uma vez', () => {
    const bodies = [HAS, TERM, CLAUSE, CLAUSE_TEXT, PHOTO, LEADERS, FACES, REVOKE, GET].filter((c) => c.n.includes(PHRASE));
    assert.deepEqual(bodies.map((c) => c.file + ':' + c.head.slice(0, 60)), [CLAUSE.file + ':' + CLAUSE.head.slice(0, 60)]);
    const pre = norm(FILE.slice(FILE.indexOf('DO $precondition$'), FILE.indexOf('$precondition$;')));
    assert.match(pre, new RegExp(`WHERE gd\\.doc_type = 'volunteer_term_template' AND gd\\.status = 'active' ORDER BY gd\\.created_at DESC LIMIT 1\\), '${esc(PHRASE)}', 'g'\\)\\) <> 1 THEN RAISE EXCEPTION`));
  });

  it('A3: a liberação de comunicação segue com o predicado de #729, e a pós-condição confere que as duas concordam', () => {
    // "há linha revogada e não há linha ativa" lá é o ramo "só linhas revogadas" daqui, porque autorizar só grava linha
    // nova sem linha ativa e revogar fecha a ativa; a pós-condição confere isso ao vivo nas duas sondas
    const comms = norm(maskLineComments(latestFunctionCapture(ROOT, 'get_member_comms_card').body)).replace(/\s+\)/g, ')');
    assert.match(comms, /ELSIF EXISTS \( SELECT 1 FROM public\.consent_records cr WHERE cr\.member_id = v_member_id AND cr\.policy_type = 'image_voice_publicity' AND cr\.revoked_at IS NOT NULL\) AND NOT EXISTS \( SELECT 1 FROM public\.consent_records cr WHERE cr\.member_id = v_member_id AND cr\.policy_type = 'image_voice_publicity' AND cr\.revoked_at IS NULL\) THEN v_clear := false; v_reason := 'image_consent_revoked';/);
    const post = norm(FILE.slice(FILE.indexOf('DO $postcondition$'))).replace(/\s+\)/g, ')');
    assert.match(post, /v_comms_consistent := \(SELECT bool_and\( \(NOT public\._member_has_image_consent\(s\.id\)\) = \( EXISTS \(/);
    assert.match(post, /OR NOT v_comms_consistent THEN RAISE EXCEPTION/);
  });

  it('B: os ajudantes não executam para PUBLIC, anon nem authenticated', () => {
    for (const sig of ['_member_current_term(uuid)', '_member_term_has_image_clause(uuid)', '_member_has_image_consent(uuid)', '_current_term_image_clause()', '_public_member_photo_url(text)']) {
      assert.match(FILE, new RegExp(`REVOKE ALL ON FUNCTION public\\.${esc(sig)} FROM PUBLIC, anon, authenticated;`), sig);
      assert.doesNotMatch(FILE, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${esc(sig)} TO [^;]*\\b(anon|authenticated|PUBLIC)\\b`), sig);
    }
    for (const c of [HAS, TERM, CLAUSE, CLAUSE_TEXT, PHOTO]) assert.doesNotMatch(c.head, /SECURITY DEFINER/, c.head);
  });

  it('C: a foto só com o nome opaco, no host e no bucket do projeto, e as leitoras só saem por esse filtro', () => {
    assert.equal(PHOTO.n, "SELECT CASE WHEN p_url ~ '^https://ldrfrvwhxsmgaabwmaik\\.supabase\\.co/storage/v1/object/public/member-photos/avatars/[0-9a-f]{32}\\.(jpg|png)(\\?t=[0-9]{1,16})?$' THEN p_url END;");
    assert.match(LEADERS.n, /^WITH .* SELECT t\.id, d\.name, public\._public_member_photo_url\(d\.photo_url\), CASE /);
    assert.equal((LEADERS.n.match(/photo_url/g) ?? []).length, 3, 'get_public_line_leaders cita photo_url fora do filtro');
    assert.match(FACES.n, /SELECT r\.team_group, r\.who, r\.name, public\._public_member_photo_url\(r\.photo_url\) AS photo_url FROM resolved r WHERE public\._member_has_image_consent\(r\.member_id\) \) x WHERE x\.photo_url IS NOT NULL AND coalesce\(x\.name, ''\) <> ''/);
    assert.match(FACES.n, /jsonb_build_object\('name', f\.name, 'photo_url', f\.photo_url\) ORDER BY f\.rn\) FROM faces f WHERE f\.team_group = g\.team_group AND f\.rn <= 8 \), '\[\]'::jsonb\)\)/);
  });

  it('D1: get_public_line_leaders: quatro colunas, SECURITY DEFINER, EXECUTE para anon sem PUBLIC', () => {
    assert.equal(LEADERS.head, "CREATE OR REPLACE FUNCTION public.get_public_line_leaders() RETURNS TABLE(tribe_id integer, leader_name text, photo_url text, video_url text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'");
    assert.match(FILE, /REVOKE ALL ON FUNCTION public\.get_public_line_leaders\(\) FROM PUBLIC;\s*GRANT EXECUTE ON FUNCTION public\.get_public_line_leaders\(\) TO anon, authenticated, service_role;/);
  });

  it('D2: só com consentimento, de quem lidera AGORA linha ativa, e o vídeo só do pitch de leader no YouTube', () => {
    assert.match(LEADERS.n, / WHERE public\._member_has_image_consent\(d\.id\) AND coalesce\(d\.name, ''\) <> '' ORDER BY t\.id, \(l\.role = 'leader'\) DESC, d\.name;$/);
    assert.match(LEADERS.n, /CASE WHEN l\.role = 'leader' AND t\.video_url ~ '\^https:\/\/\(www\\\.\)\?\(youtube\\\.com\/watch\\\?v=\|youtu\\\.be\/\)\[A-Za-z0-9_-\]\{11\}\$' THEN t\.video_url END FROM leaders l/);
    assert.match(LEADERS.n, /JOIN public\.tribes t ON t\.id = l\.legacy_tribe_id AND t\.is_active = true/);
    assert.match(LEADERS.n, /WHERE mm\.person_id = l\.person_id AND mm\.is_active = true AND mm\.current_cycle_active = true ORDER BY mm\.id LIMIT 1 \) d ON true/);
    // a janela de vigência e o portão de confidencial são os da home, e o papel é o do grupo de lideranças de linha
    const tail = (s) => s.slice(s.indexOf(' FROM public.engagements e'));
    assert.equal(tail(cte(LEADERS.n, 'live_engagements')), tail(cte(HOME.n, 'live_engagements')));
    assert.ok(tail(cte(HOME.n, 'live_engagements')).includes('e.end_date IS NULL OR e.end_date >= CURRENT_DATE'), 'janela da home não lida');
    const want = wherePairs(homeBlock('line_leaders')).map((p) => p.split(' | ')[1]);
    assert.equal(want.length, 1);
    assert.match(LEADERS.n, new RegExp(`FROM live_engagements le WHERE ${esc(want[0])} ORDER BY le\\.legacy_tribe_id`));
  });

  it('E1: get_public_team_faces: os grupos e os predicados da home, e os CTEs dela', () => {
    assert.equal(FACES.head, "CREATE OR REPLACE FUNCTION public.get_public_team_faces() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'");
    assert.match(FILE, /REVOKE ALL ON FUNCTION public\.get_public_team_faces\(\) FROM PUBLIC;\s*GRANT EXECUTE ON FUNCTION public\.get_public_team_faces\(\) TO anon, authenticated, service_role;/);
    assert.equal(cte(FACES.n, 'active_members'), cte(HOME.n, 'active_members'));
    assert.ok(cte(HOME.n, 'active_members'), 'CTE active_members da home não lido');
    const tail = (s) => s.slice(s.indexOf(' FROM public.engagements e'));
    assert.equal(tail(cte(FACES.n, 'live_engagements')), tail(cte(HOME.n, 'live_engagements')));
    const start = FACES.n.indexOf('roster AS ( ');
    const end = FACES.n.indexOf(' ), focal AS (', start);
    assert.ok(start >= 0 && end > start, 'CTE roster não encontrado');
    const byGroup = new Map();
    for (const branch of FACES.n.slice(start + 'roster AS ( '.length, end).split(' UNION ALL ')) {
      const g = branch.match(/^SELECT '([a-z_]+)'/)?.[1];
      assert.ok(g, `ramo sem grupo: ${branch.slice(0, 60)}`);
      byGroup.set(g, [...(byGroup.get(g) ?? []), branch.replace(/^.*? FROM /, 'FROM ')]);
    }
    assert.deepEqual([...byGroup.keys()].sort(), GROUPS.filter((g) => g !== 'chapter_focal_points').sort());
    for (const [g, mine] of byGroup) {
      if (g === 'researchers') {
        assert.match(homeBlock(g), /FROM public\.v_operational_members\)$/, 'a home mudou a fonte dos pesquisadores');
        assert.deepEqual(mine, ['FROM public.v_operational_members om']);
        continue;
      }
      const want = wherePairs(homeBlock(g));
      assert.ok(want.length > 0, `predicado da home não lido para ${g}`);
      assert.deepEqual(mine.flatMap(wherePairs), want, `${g}: o predicado dos rostos não é o da home`);
    }
    // pontos focais: o predicado da home, e só o nome do capítulo sai
    assert.deepEqual(wherePairs(cte(FACES.n, 'focal')), wherePairs(homeBlock('chapter_focal_points')));
    assert.match(FACES.n, /'focal_point_chapters', \( SELECT coalesce\(jsonb_agg\(DISTINCT mm\.chapter ORDER BY mm\.chapter\), '\[\]'::jsonb\) FROM focal f JOIN public\.members mm ON mm\.id = f\.who WHERE coalesce\(mm\.chapter, ''\) <> '' \)/);
  });

  it('E2: rosto só com consentimento e foto opaca, de membro ativo, até 8 por grupo, numa ordem que gira por dia', () => {
    assert.match(FACES.n, /WHERE \(mm\.id = r\.member_id OR \(r\.member_id IS NULL AND mm\.person_id = r\.person_id\)\) AND mm\.is_active = true AND mm\.current_cycle_active = true ORDER BY mm\.id LIMIT 1 \) d ON true/);
    assert.match(FACES.n, /row_number\(\) OVER \(PARTITION BY x\.team_group ORDER BY md5\(x\.who::text \|\| CURRENT_DATE::text\)\) AS rn/);
    assert.match(FACES.n, /FROM unnest\(ARRAY\['management', 'line_leaders', 'initiative_leaders', 'curators', 'hub_members', 'researchers'\]\) AS g\(team_group\)/);
    assert.doesNotMatch(FACES.n, /linkedin|email|phone|pmi_id|auth_id|'id',/i);
  });

  it('F1: revogar: o corpo de #570 mais o ramo da linha nascida revogada, só sem decisão anterior; nunca apaga', () => {
    assert.equal(REVOKE.file, HAS.file, 'revoke_image_voice_consent não é redefinida por esta migration');
    assert.equal(REVOKE.head, "CREATE OR REPLACE FUNCTION public.revoke_image_voice_consent(p_reason text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'");
    const gate = REVOKE.n.match(/BEGIN SELECT id INTO v_member_id FROM public\.members WHERE auth_id = auth\.uid\(\); IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;/);
    assert.ok(gate && gate.index < REVOKE.n.indexOf('consent_records'), 'portão ausente ou depois do ledger');
    // o que #570 já fazia: fecha a linha ativa
    assert.match(REVOKE.n, /UPDATE public\.consent_records SET revoked_at = now\(\), revocation_reason = v_reason WHERE member_id = v_member_id AND policy_type = 'image_voice_publicity' AND revoked_at IS NULL RETURNING id, revoked_at INTO v_revoked_id, v_revoked_at;/);
    // sem linha ativa: com decisão anterior, nada a gravar; sem nenhuma decisão, a linha nasce revogada
    const branch = REVOKE.n.slice(REVOKE.n.indexOf('IF v_revoked_id IS NULL THEN'), REVOKE.n.indexOf('INSERT INTO public.admin_audit_log'));
    assert.match(branch, /^IF v_revoked_id IS NULL THEN IF EXISTS \(SELECT 1 FROM public\.consent_records cr WHERE cr\.member_id = v_member_id AND cr\.policy_type = 'image_voice_publicity'\) THEN RETURN jsonb_build_object\('success', true, 'no_active_consent', true, 'is_active', false\); END IF;/);
    assert.match(branch, /INSERT INTO public\.consent_records \( member_id, policy_type, policy_version, policy_document_id, accepted_at, channel, revoked_at, revocation_reason, evidence, organization_id \) VALUES \( v_member_id, 'image_voice_publicity', coalesce\('termo:' \|\| v_term\.body_version_id, 'unversioned'\), \(SELECT gd\.id FROM public\.governance_documents gd WHERE gd\.id::text = v_term\.template_id\), coalesce\(v_term\.issued_at, now\(\)\), 'platform_action', now\(\), v_reason,/);
    assert.equal((REVOKE.n.match(/INSERT INTO public\.consent_records/g) ?? []).length, 1);
    assert.doesNotMatch(REVOKE.n, /\bDELETE\b/i);
    assert.match(FILE, /REVOKE ALL ON FUNCTION public\.revoke_image_voice_consent\(text\) FROM PUBLIC;\s*REVOKE ALL ON FUNCTION public\.revoke_image_voice_consent\(text\) FROM anon;\s*GRANT EXECUTE ON FUNCTION public\.revoke_image_voice_consent\(text\) TO authenticated, service_role;/);
    // a redefinição parte do corpo vivo medido (a captura de #570)
    const pre = norm(FILE.slice(FILE.indexOf('DO $precondition$'), FILE.indexOf('$precondition$;')));
    assert.match(pre, /WHERE p\.oid = 'public\.revoke_image_voice_consent\(text\)'::regprocedure\) IS DISTINCT FROM '00dc696134ac416332e62ea4229503bd' THEN RAISE EXCEPTION/);
  });

  it('F2: autorizar é a função de #570, sem cópia; e esta migration não tem outro caminho de escrita no ledger', () => {
    assert.ok(!GRANT.file.startsWith('2999'), 'grant_image_voice_consent foi redefinida aqui');
    assert.match(GRANT.n, /IF FOUND THEN RETURN jsonb_build_object\( 'success', true, 'already_active', true,/, 'autorizar deixou de ser idempotente');
    assert.match(GRANT.n, /v_version := COALESCE\(NULLIF\(p_evidence ->> 'displayed_version', ''\), v_doc_version, 'unversioned'\);/);
    assert.equal((FILE.match(/INSERT INTO public\.consent_records/g) ?? []).length, 1, 'outra escrita no ledger além da revogação');
    assert.doesNotMatch(FILE, /UPDATE public\.consent_records[\s\S]*UPDATE public\.consent_records/, 'mais de uma atualização do ledger');
    assert.doesNotMatch(FILE, /set_my_image_consent|FUNCTION public\.grant_image_voice_consent/);
  });

  it('F3: get_my_image_consent lê pela regra e entrega o texto da cláusula da versão ativa, ou nada', () => {
    assert.match(GET.n, /BEGIN SELECT m\.id INTO v_member_id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\); IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;/);
    assert.match(GET.n, /RETURN jsonb_build_object\( 'active', public\._member_has_image_consent\(v_member_id\), 'term_signed', public\._member_current_term\(v_member_id\) IS NOT NULL, 'term_has_clause', public\._member_term_has_image_clause\(v_member_id\), 'clause', public\._current_term_image_clause\(\) \);/);
    assert.match(FILE, /REVOKE ALL ON FUNCTION public\.get_my_image_consent\(\) FROM PUBLIC, anon;\s*GRANT EXECUTE ON FUNCTION public\.get_my_image_consent\(\) TO authenticated, service_role;/);
    // o texto: do caput até antes do § 3º, da versão ativa; três parágrafos na forma esperada, ou NULL
    assert.match(CLAUSE_TEXT.n, /strpos\(dv\.content_html, '<p><strong>Cláusula 11\.<\/strong>'\) AS s FROM public\.governance_documents gd JOIN public\.document_versions dv ON dv\.id = gd\.current_version_id WHERE gd\.doc_type = 'volunteer_term_template' AND gd\.status = 'active'/);
    assert.match(CLAUSE_TEXT.n, /CASE WHEN v\.s > 0 AND strpos\(substr\(v\.html, v\.s\), '<p><strong>§ 3º<\/strong>'\) > 0 THEN substr\(v\.html, v\.s, strpos\(substr\(v\.html, v\.s\), '<p><strong>§ 3º<\/strong>'\) - 1\) END AS block/);
    assert.match(CLAUSE_TEXT.n, /SELECT CASE WHEN jsonb_array_length\(p\.list\) = 3 AND p\.list->>0 LIKE 'Cláusula 11\. %' AND p\.list->>1 LIKE '§ 1º %' AND p\.list->>2 LIKE '§ 2º %' THEN jsonb_build_object\( 'paragraphs', p\.list, 'version', 'termo-v' \|\| p\.version_number \|\| ':cl11:' \|\| left\(md5\(p\.list::text\), 8\)\) END FROM paras p;$/);
  });

  it('F4: a pós-condição exerce o perfil numa subtransação desfeita, nos dois sentidos, com resíduo zero', () => {
    const post = norm(FILE.slice(FILE.indexOf('DO $postcondition$')));
    assert.match(post, /PERFORM public\.grant_image_voice_consent\(jsonb_build_object\('displayed_version', \(v_clause->>'version'\) \|\| ':pt-BR'\)\);/);
    assert.match(post, /IF v_steps IS DISTINCT FROM \(ARRAY\['antes:inicio=false', 'antes:autoriza=true'\] \|\| CASE WHEN v_old_line IS NOT NULL THEN ARRAY\['antes:linha=1'\] ELSE '\{\}'::text\[\] END \|\| ARRAY\['antes:revoga=false', 'antes:reautoriza=true', 'antes:linhas_no_ledger=2', 'clausula:inicio=true', 'clausula:revoga=false', 'clausula:linha=0'\]\) OR NOT v_comms_consistent THEN RAISE EXCEPTION/);
    assert.match(post, /RAISE EXCEPTION USING ERRCODE = 'ZC011', MESSAGE = 'desfaz a sonda'; EXCEPTION WHEN SQLSTATE 'ZC011' THEN NULL; END;/);
    assert.match(post, /IF EXISTS \(SELECT 1 FROM public\.consent_records cr WHERE cr\.member_id IN \(v_old, v_new\) AND cr\.policy_type = 'image_voice_publicity'\) OR EXISTS \(SELECT 1 FROM public\.admin_audit_log a WHERE a\.target_id IN \(v_old, v_new\) AND a\.action IN \('image_voice_consent_granted', 'image_voice_consent_revoked'\) AND a\.created_at >= now\(\)\) OR public\._member_has_image_consent\(v_old\) OR NOT public\._member_has_image_consent\(v_new\) THEN RAISE EXCEPTION 'clausula 11: a sonda deixou rastro';/);
    // as sondas começam sem nenhuma decisão no ledger: o termo decide o ponto de partida
    assert.equal((post.match(/AND NOT EXISTS \(SELECT 1 FROM public\.consent_records cr WHERE cr\.member_id = m\.id AND cr\.policy_type = 'image_voice_publicity'\)/g) ?? []).length, 2);
  });

  it('G: #965: as leitoras não escrevem nem chamam http, e a lista daquele teste não muda', () => {
    for (const c of [LEADERS, FACES]) {
      assert.doesNotMatch(c.body, /\b(insert|update|delete)\b/i, `${c.head.slice(27, 60)}: termo de escrita no corpo (entra na varredura do #965)`);
      assert.ok(!c.body.includes('http_post'));
    }
    const allow = read('tests/contracts/965-secdef-public-grant-drift.test.mjs');
    for (const n of ['get_public_line_leaders', 'get_public_team_faces', 'get_my_image_consent', 'revoke_image_voice_consent']) assert.ok(!allow.includes(n), n);
    // as funções do perfil saem da varredura pelo auth.uid() no corpo
    for (const c of [REVOKE, GET]) assert.ok(c.body.includes('auth.uid()'));
  });
});

describe('pertencimento parte 2: o que a home e o perfil entregam', () => {
  const DATA = maskJsComments(read('src/lib/publicHomeData.ts'));
  const LINES = maskAstro(read('src/components/sections/ResearchLinesSection.astro'));
  const TEAM = maskAstro(read('src/components/sections/TeamSummarySection.astro'));
  const PROFILE = maskAstro(read('src/pages/profile.astro'));

  it('H1: o servidor da página repete o filtro opaco e serve a rendição pequena no host do projeto', () => {
    assert.match(DATA, /export const FACE_PX = 40;\nconst OPAQUE_PHOTO_RE = \/\\\/storage\\\/v1\\\/object\\\/public\\\/member-photos\\\/\(avatars\\\/\[0-9a-f\]\{32\}\\\.\(\?:jpg\|png\)\)\(\?:\\\?t=\(\\d\{1,16\}\)\)\?\$\/;/);
    assert.match(DATA, /const m = typeof url === 'string' \? url\.match\(OPAQUE_PHOTO_RE\) : null;\s+if \(!m\) return null;\s+const size = FACE_PX \* 2;\s+return `\$\{import\.meta\.env\.PUBLIC_SUPABASE_URL\}\/storage\/v1\/render\/image\/public\/member-photos\/\$\{m\[1\]\}`/);
    assert.match(DATA, /const rows = await rpc<unknown\[\]>\('get_public_line_leaders'\);[\s\S]*?photo: facePhotoSrc\(r\.photo_url\),/);
    assert.match(DATA, /const data = await rpc<Record<string, any>>\('get_public_team_faces'\);[\s\S]*?if \(key === 'chapter_focal_points'\) continue;[\s\S]*?\.filter\(\(f\): f is TeamFace => f\.name !== '' && f\.photo !== null\)\s+\.slice\(0, FACES_PER_GROUP\);/);
    assert.match(DATA, /export const FACES_PER_GROUP = 8;/);
  });

  it('H2: a linha mostra a foto e o nome no resumo, e a imagem tem largura, altura, lazy e async', () => {
    const summary = LINES.slice(LINES.indexOf('<summary'), LINES.indexOf('</summary>'));
    assert.match(summary, /\{leaders\.length > 0 && \(\s+<span class="[^"]*" data-line-leaders>[\s\S]*?\{leaders\.map\(\(p\) => \(\s+<span[^>]*>\s+\{p\.photo && <img src=\{p\.photo\} alt="" width=\{FACE_PX\} height=\{FACE_PX\} loading="lazy" decoding="async" [^>]*\/>\}\s+<b[^>]*>\{p\.name\}<\/b>/);
    assert.match(LINES, /const leaders = leadersByLine\.get\(l\.id\) \?\? \[\];\s+const pitch = leaders\.find\(\(p\) => p\.video\)\?\.video \?\? null;/);
    assert.match(LINES, /\{pitch && \(\s+<a href=\{pitch\} target="_blank" rel="noopener" data-line-video/);
    assert.doesNotMatch(LINES, /<iframe|autoplay/i);
  });

  it('H3: "Quem faz": até 8 rostos de quem consentiu, "+N" pela contagem da home, pontos focais pelo capítulo', () => {
    assert.match(TEAM, /const \[team, faces, trail, wall\] = await Promise\.all\(\[loadHomeTeam\(\), loadTeamFaces\(\), loadTrailSummary\(\), loadCpmaiWall\(\)\]\);/);
    assert.match(TEAM, /if \(tile\.id === 'chapter_focal_points'\) \{ tile\.chapters = faces\.focalChapters; continue; \}\s+const shown = faces\.faces\[tile\.id as keyof typeof faces\.faces\] \?\? \[\];\s+tile\.faces = shown;\s+tile\.more = Math\.max\(0, team\[tile\.id as keyof typeof team\] - shown\.length\);/);
    assert.match(TEAM, /\{tile\.faces\.map\(\(f\) => \(\s+<li><img src=\{f\.photo\} alt=\{f\.name\} title=\{f\.name\} width=\{FACE_PX\} height=\{FACE_PX\} loading="lazy" decoding="async" /);
    assert.match(TEAM, /\{\(tile\.more \?\? 0\) > 0 && \(\s+<li[^>]*data-team-more[^>]*>\+\{tile\.more\}<\/li>/);
    assert.match(TEAM, /\{tile\.chapters && tile\.chapters\.length > 0 && \(\s+<p[^>]*data-team-chapters>\{t\('homeV2\.team\.focalChapters', lang\)\.replace\('\{list\}', tile\.chapters\.join\(', '\)\)\}<\/p>/);
    assert.doesNotMatch(TEAM, /linkedin|e-?mail|phone|whatsapp|navGetSb|\.rpc\(|\.from\(/i);
  });

  it('I: o perfil: quem tem a cláusula vê o consentimento e revoga; quem assinou antes lê o texto e autoriza', () => {
    assert.match(PROFILE, /<div id="self-image-consent-clause" class="hidden [^"]*"><\/div>\s+<label[^>]*id="self-image-consent-row">\s+<input type="checkbox" id="self-image-consent" class="mt-0\.5" disabled>\s+<span[^>]*><span id="self-image-consent-label">\$\{PROFILE_I18N\.imageConsentLabel\}<\/span> <span[^>]*>\$\{PROFILE_I18N\.imageConsentHint\}<\/span><\/span>/);
    assert.match(PROFILE, /loadNotifPrefs\(\);\s+loadLinkedProviders\(\);\s+loadImageConsent\(\);/);
    const fn = PROFILE.slice(PROFILE.indexOf('async function loadImageConsent()'), PROFILE.indexOf("document.addEventListener('change', async (e) => {", PROFILE.indexOf('async function loadImageConsent()')));
    assert.match(fn, /const \{ data, error \} = await sb\.rpc\('get_my_image_consent'\);\s+if \(error \|\| !data\) return;\s+const withTerm = data\.term_has_clause === true;/);
    // sem a cláusula no termo, só autoriza quem tem o texto na tela; o estado vem do banco
    assert.match(fn, /const canGrant = withTerm \|\| \(paragraphs\.length === 3 && imageClauseVersion !== ''\);\s+box\.checked = data\.active === true;\s+box\.disabled = !\(data\.active === true \|\| canGrant\);/);
    assert.match(fn, /label\.textContent = withTerm \? PROFILE_I18N\.imageConsentLabel : PROFILE_I18N\.imageConsentGrantLabel;/);
    assert.match(fn, /clauseBox\.classList\.toggle\('hidden', withTerm\);\s+if \(!withTerm\) \{[\s\S]*?lead\.textContent = PROFILE_I18N\.imageConsentClauseLead;[\s\S]*?for \(const text of paragraphs\.length === 3 \? paragraphs : \[PROFILE_I18N\.imageConsentUnavailable\]\) \{\s+const para = document\.createElement\('p'\);\s+para\.textContent = text;[\s\S]*?optional\.textContent = PROFILE_I18N\.imageConsentOptional;/);
    assert.doesNotMatch(fn, /innerHTML|volunteer-agreement/, 'o texto da cláusula entra como texto, e o re-aceite não passa mais pelo termo');
    assert.match(PROFILE, /if \(target\.id !== 'self-image-consent'\) return;\s+const active = !!target\.checked;[\s\S]*?if \(active\) await rpcChecked\(sb, 'grant_image_voice_consent', \{ p_evidence: \{ displayed_version: `\$\{imageClauseVersion \|\| 'termo-sem-texto'\}:\$\{lang\}` \} \}\);\s+else await rpcChecked\(sb, 'revoke_image_voice_consent', \{ p_reason: 'perfil: Cláusula 11' \}\);/);
    assert.doesNotMatch(PROFILE, /set_my_image_consent/);
  });

  it('J1: a /privacy tem a passagem na seção 4, nos 3 idiomas, com base, revogação no perfil e saída no mesmo dia', () => {
    assert.match(read('src/pages/privacy.astro'), /<li>\{t\('privacy\.s4\.cpmaiWall', lang\)\}<\/li>\s+<li>\{t\('privacy\.s4\.lineLeaders', lang\)\}<\/li>/);
    const must = {
      'pt-BR': [/^Card de cada linha de pesquisa e seção "Quem faz"/, /Cláusula 11 do Termo de Adesão/, /para quem assinou uma versão anterior, ao autorizar no perfil\./, /consentimento \(art\. 7º, I, da LGPD\), revogável a qualquer momento no perfil/, /saem dessas superfícies no mesmo dia\./, /só pelo nome do capítulo\.$/],
      'en-US': [/^Card of each research line and the team section/, /Clause 11 of the Volunteer Service Agreement/, /for those who signed an earlier version, by authorizing it in the profile\./, /consent \(LGPD art\. 7, I\), revocable at any time in the profile/, /leave these surfaces the same day\./, /only by the chapter name\.$/],
      'es-LATAM': [/^Tarjeta de cada línea de investigación y sección "Quién lo hace"/, /Cláusula 11 del Término de Adhesión/, /para quien firmó una versión anterior, al autorizarlo en el perfil\./, /consentimiento \(art\. 7, I, de la LGPD\), revocable en cualquier momento en el perfil/, /salen de esas superficies el mismo día\./, /solo por el nombre del capítulo\.$/],
    };
    for (const [lang, res] of Object.entries(must)) {
      const text = value(DICTS[lang], 'privacy.s4.lineLeaders') ?? '';
      assert.ok(text, `${lang}: passagem ausente`);
      for (const re of res) assert.match(text, re, `${lang}: ${re}`);
      assert.doesNotMatch(text, /legítimo interesse|legitimate interest|interés legítimo/i, `${lang}: a base não é mais o legítimo interesse`);
      assert.ok(!text.includes(EM_DASH), `${lang}: travessão longo`);
    }
  });

  it('J2: o registro da decisão ganha a emenda, sem nome de pessoa', () => {
    const rec = read('docs/council/decisions/2026-10-04-2553-vitrine-onze-decisoes.md');
    const em = rec.slice(rec.indexOf('### Emenda 3 (2026-10-26)'));
    assert.ok(rec.includes('### Emenda 3 (2026-10-26)'), 'emenda ausente');
    assert.match(em, /consentimento da Clausula 11 do Termo de Adesao/);
    assert.match(em, /\*\*D3 da home v2\*\*[\s\S]*?emendada\.[\s\S]*?os demais, so na contagem/);
    assert.match(em, /O caminho do legitimo interesse continua valendo para nome sem imagem/);
    assert.match(em, /Caminho A:\s+quem assinou versao anterior da o consentimento no perfil[\s\S]*?o termo nao e reemitido\./);
    assert.doesNotMatch(em, /volunteer-agreement|reemissao do termo pela gestao/);
    // os nomes que a /privacy publica (encarregado e substituto) não entram aqui: lidos da página, não escritos no teste
    const privacy = read('src/pages/privacy.astro');
    const names = [...privacy.matchAll(/\{t\('privacy\.s1\.dpo(?:Substitute)?', lang\)\}: ([^<]+)<\/li>/g)].map((m) => m[1].trim());
    assert.equal(names.length, 2, 'nomes do encarregado não lidos da /privacy');
    for (const n of names) for (const part of n.split(/\s+/).filter((w) => w.length > 3)) assert.ok(!em.includes(part), 'a emenda cita o nome de uma pessoa');
    assert.ok(!em.includes(EM_DASH), 'travessão longo na emenda');
  });

  it('J3: as chaves novas existem nos 3 dicionários, sem travessão longo', () => {
    const keys = ['homeV2.lines.ledBy', 'homeV2.lines.pitchVideo', 'homeV2.team.facesAria', 'homeV2.team.moreAria', 'homeV2.team.focalChapters',
      'profile.imageConsentLabel', 'profile.imageConsentHint', 'profile.imageConsentGrantLabel', 'profile.imageConsentClauseLead',
      'profile.imageConsentOptional', 'profile.imageConsentUnavailable',
      'profile.imageConsentOn', 'profile.imageConsentOff', 'profile.imageConsentError', 'privacy.s4.lineLeaders', 'homeV2.team.subtitle'];
    for (const [lang, dict] of Object.entries(DICTS)) {
      for (const k of keys) {
        const v = value(dict, k);
        assert.ok(v, `${lang}: ${k} ausente`);
        assert.ok(!v.includes(EM_DASH), `${lang}: ${k} com travessão longo`);
      }
      assert.match(value(dict, 'homeV2.team.moreAria'), /\{n\}/);
      assert.match(value(dict, 'homeV2.team.focalChapters'), /\{list\}/);
      for (const gone of ['profile.imageConsentNeedsTerm', 'profile.imageConsentNoTerm']) assert.equal(value(dict, gone), undefined, `${lang}: ${gone} sobrou`);
    }
    // o aviso de opcional, sem efeito na participação e revogável aqui, nas 3 línguas
    const optional = { 'pt-BR': /^A autorização é opcional, não muda nada na sua participação e pode ser revogada aqui, a qualquer momento\.$/,
      'en-US': /^The authorization is optional, changes nothing in your participation and can be revoked here at any time\.$/,
      'es-LATAM': /^La autorización es opcional, no cambia nada en su participación y puede revocarse aquí en cualquier momento\.$/ };
    for (const [lang, re] of Object.entries(optional)) assert.match(value(DICTS[lang], 'profile.imageConsentOptional'), re, lang);
  });
});

// ── L: os leitores, exercidos com fetch simulado ────────────────────────────────────────────────────────────────
const TMP = mkdtempSync(join(tmpdir(), 'clausula-11-'));
after(() => rmSync(TMP, { recursive: true, force: true }));
const requireHere = createRequire(import.meta.url);
const STUB = 'https://stub.invalid';
const LOADER = join(TMP, 'loader.cjs');
buildSync({
  stdin: { contents: "export { loadLineLeaders, loadTeamFaces, facePhotoSrc } from './src/lib/publicHomeData.ts';", resolveDir: ROOT, loader: 'ts', sourcefile: 'entry.ts' },
  bundle: true, platform: 'node', format: 'cjs', outfile: LOADER, logLevel: 'silent',
  define: { 'import.meta.env': JSON.stringify({ PUBLIC_SUPABASE_URL: STUB, PUBLIC_SUPABASE_ANON_KEY: 'anon-stub' }) },
});
const fresh = () => { delete requireHere.cache[LOADER]; return requireHere(LOADER); };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
async function withFetch(fake, fn) {
  const real = globalThis.fetch;
  globalThis.fetch = async (input, init) => fake(String(input?.url ?? input), init);
  try { return await fn(fresh()); } finally { globalThis.fetch = real; }
}
const HEX = '0123456789abcdef0123456789abcdef';
const OBJ = 'https://elsewhere.example/storage/v1/object/public/member-photos';
const RENDER = `${STUB}/storage/v1/render/image/public/member-photos/avatars/${HEX}.jpg?width=80&height=80&resize=cover&quality=70`;

describe('pertencimento parte 2: os leitores da home, exercidos', () => {
  it('L1: a liderança: só nome, foto opaca e vídeo do YouTube; e-mail no nome do objeto e link de fora caem', async () => {
    const rows = [
      { tribe_id: 4, leader_name: ' Pessoa A ', photo_url: `${OBJ}/avatars/${HEX}.jpg?t=17`, video_url: 'https://www.youtube.com/watch?v=AAAAAAAAAAA', email: 'oculto' },
      { tribe_id: 6, leader_name: 'Pessoa B', photo_url: `${OBJ}/avatars/pessoa_b_example_org.jpg`, video_url: 'https://evil.example/watch?v=AAAAAAAAAAA' },
      { tribe_id: 'x', leader_name: 'Pessoa C' },
      { tribe_id: 7, leader_name: '' },
    ];
    const byLine = await withFetch(() => json(rows), (m) => m.loadLineLeaders());
    assert.deepEqual([...byLine.keys()], [4, 6]);
    assert.deepEqual(byLine.get(4), [{ name: 'Pessoa A', photo: `${RENDER}&t=17`, video: 'https://www.youtube.com/watch?v=AAAAAAAAAAA' }]);
    assert.deepEqual(byLine.get(6), [{ name: 'Pessoa B', photo: null, video: null }]);
    const down = await withFetch(() => json({ code: 'PGRST202' }, 404), (m) => m.loadLineLeaders());
    assert.equal(down.size, 0, 'leitura que falha devolve linhas sem liderança, não erro');
  });

  it('L2: os rostos: até 8 por grupo, só com foto opaca e nome, pontos focais só como capítulo', async () => {
    const face = (i, photo = `${OBJ}/avatars/${HEX}.jpg`) => ({ name: `Pessoa ${i}`, photo_url: photo, id: `id-${i}` });
    const body = {
      faces: {
        researchers: [face(0, `${OBJ}/avatars/pessoa_0_example_org.jpg`), ...Array.from({ length: 10 }, (_, i) => face(i + 1)), { name: '', photo_url: `${OBJ}/avatars/${HEX}.jpg` }],
        management: [],
        chapter_focal_points: [face(99)],
      },
      focal_point_chapters: ['PMI-GO', 3, '', 'PMI-DF'],
    };
    const out = await withFetch(() => json(body), (m) => m.loadTeamFaces());
    assert.equal(out.faces.researchers.length, 8);
    assert.deepEqual(out.faces.researchers[0], { name: 'Pessoa 1', photo: RENDER });
    assert.ok(out.faces.researchers.every((f) => Object.keys(f).sort().join() === 'name,photo' && f.photo.startsWith(`${STUB}/`)));
    assert.equal(out.faces.chapter_focal_points, undefined, 'ponto focal ganhou rosto');
    assert.deepEqual(out.faces.management, []);
    assert.deepEqual(out.focalChapters, ['PMI-GO', 'PMI-DF']);
    const down = await withFetch(() => { throw new TypeError('fetch failed'); }, (m) => m.loadTeamFaces());
    assert.deepEqual(Object.values(down.faces).flat(), []);
    assert.deepEqual(down.focalChapters, []);
  });

  it('L3: a foto sai do host do projeto e só do objeto de nome opaco', () => {
    const { facePhotoSrc } = fresh();
    assert.equal(facePhotoSrc(`${OBJ}/avatars/${HEX}.png`), RENDER.replace('.jpg', '.png'));
    for (const bad of [`${OBJ}/avatars/${HEX}.gif`, `${OBJ}/avatars/${HEX.slice(1)}.jpg`, `${OBJ}/avatars/pessoa_example_org.jpg`,
      `${OBJ.replace('member-photos', 'outro')}/avatars/${HEX}.jpg`, `${OBJ}/avatars/${HEX}.jpg?t=1&x=2`, null, 42]) {
      assert.equal(facePhotoSrc(bad), null, String(bad));
    }
  });
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
describe('pertencimento parte 2, banco', { skip: !(URL && ANON) && 'Supabase URL + anon key required' }, () => {
  it('K: como anon, as leitoras respondem só com as chaves nomeadas, e o ajudante recusa', async () => {
    const sb = createClient(URL, ANON, { auth: { persistSession: false } });
    const home = await sb.rpc('get_public_home_team');
    assert.equal(home.error, null, 'controle: anon deveria ler get_public_home_team');
    const leaders = await sb.rpc('get_public_line_leaders');
    assert.equal(leaders.error, null, `anon deveria ler get_public_line_leaders: ${leaders.error?.code}`);
    for (const row of leaders.data) assert.deepEqual(Object.keys(row).sort(), ['leader_name', 'photo_url', 'tribe_id', 'video_url']);
    const faces = await sb.rpc('get_public_team_faces');
    assert.equal(faces.error, null, `anon deveria ler get_public_team_faces: ${faces.error?.code}`);
    assert.deepEqual(Object.keys(faces.data).sort(), ['faces', 'focal_point_chapters']);
    for (const [g, list] of Object.entries(faces.data.faces)) {
      assert.ok(list.length <= 8 && list.length <= home.data[g], `${g}: rostos demais`);
      for (const f of list) assert.deepEqual(Object.keys(f).sort(), ['name', 'photo_url']);
    }
    const helper = await sb.rpc('_member_has_image_consent', { p_member_id: '00000000-0000-4000-8000-000000000000' });
    assert.ok(helper.error, 'anon executou o ajudante de consentimento');
  });
});
