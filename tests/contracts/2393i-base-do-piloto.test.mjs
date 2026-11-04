/**
 * Contract: #2393, M1 do alfa (ADR-0134) — a base do piloto da linha que o portal, o e-mail e Minhas vagas leem.
 *
 *   A2: a vaga tem a data prometida do convite do vídeo (vep_opportunities.video_invite_by), e
 *       consume_onboarding_token devolve a vaga ao portal, para ele mostrar o período no lugar do ciclo.
 *   A3 (R3): o token do portal da candidatura piloto vale 45 dias da emissão (ADR-0134 §8); um trigger cobre os
 *       novos e um UPDATE os já emitidos, com a MESMA condição.
 *   A3 (R4, C8): o e-mail de candidatura recebida diz "Recebemos sua candidatura à vaga ..." nas 3 línguas, e o
 *       piloto tem o seu, com os passos e a data do convite; toda variável usada está declarada.
 *   A4 (R2): get_opening_application não devolve ao líder o e-mail da candidatura piloto, nem o registra.
 *
 * Camada S (estática). O efeito é a verificação do pacote, num DO desfeito pela sentinela.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const TOKEN_FN = '_token_do_piloto_vale_o_processo';
const TOKEN_TRG = 'trg_token_do_piloto_vale_o_processo';
const ESCOPO = "t?\\.?scopes && ARRAY\\['profile_completion', 'consent_giving'\\]::text\\[\\]";

function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}
const todas = () => readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()
  .map((f) => ({ f, s: maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')).replace(/\s+/g, ' ') }));
const ultimaCom = (re) => { let u = null; for (const m of todas()) if (re.test(m.s)) u = m; return u; };

test('#2393i S: a vaga tem a data do convite do vídeo, e a da 76080 é configurada só na trilha piloto', () => {
  const m = ultimaCom(/ADD COLUMN IF NOT EXISTS video_invite_by date;/);
  assert.ok(m, 'a coluna video_invite_by não é criada');
  assert.match(m.s, /UPDATE public\.vep_opportunities SET video_invite_by = DATE '2026-11-20' WHERE opportunity_id = '76080' AND evaluation_track = 'line_pilot' AND video_invite_by IS NULL;/,
    'a data da 76080 deixou de depender da trilha ou passou a sobrescrever');
});

test('#2393i S: consume_onboarding_token devolve a vaga da candidatura, com período, trilha e data do convite', () => {
  const { corpo } = captura('consume_onboarding_token');
  assert.match(corpo,
    /'step_catalog', v_step_catalog, 'opening', \(SELECT jsonb_build_object\( 'opportunity_id', vo\.opportunity_id, 'title', vo\.title, 'start_date', vo\.start_date, 'end_date', vo\.end_date, 'evaluation_track', vo\.evaluation_track, 'video_invite_by', vo\.video_invite_by\) FROM public\.vep_opportunities vo WHERE vo\.opportunity_id = v_app\.vep_opportunity_id\), 'account_state',/,
    'a vaga saiu do payload, mudou de campos ou deixou de ser a da candidatura');
});

test('#2393i S: o token do portal da candidatura piloto ganha 45 dias na emissão', () => {
  const { corpo } = captura(TOKEN_FN);
  assert.match(corpo,
    new RegExp(`BEGIN IF NEW\\.source_type = 'pmi_application' AND NEW\\.${ESCOPO.replace('t?\\.?', '')} AND NOT public\\._na_avaliacao_geral\\(NEW\\.source_id\\) THEN NEW\\.expires_at := greatest\\(NEW\\.expires_at, now\\(\\) \\+ interval '45 days'\\); END IF; RETURN NEW; END;`),
    'a condição ou o prazo do token do piloto mudou');
});

test('#2393i S: o trigger do prazo existe no estado final, antes de gravar o token', () => {
  let ultimo = null;
  for (const { s } of todas()) {
    const eventos = [];
    for (const m of s.matchAll(new RegExp(`CREATE (?:OR REPLACE )?TRIGGER ${TOKEN_TRG} ([^;]*);`, 'g'))) eventos.push({ i: m.index, def: m[1] });
    for (const m of s.matchAll(new RegExp(`DROP TRIGGER (?:IF EXISTS )?${TOKEN_TRG} ON public\\.onboarding_tokens;`, 'g'))) eventos.push({ i: m.index, def: null });
    for (const e of eventos.sort((a, b) => a.i - b.i)) ultimo = e.def;
  }
  assert.equal(ultimo, `BEFORE INSERT ON public.onboarding_tokens FOR EACH ROW EXECUTE FUNCTION public.${TOKEN_FN}()`,
    'o trigger não existe no estado final ou mudou de momento ou de função');
});

test('#2393i S: os tokens já emitidos ganham o mesmo prazo, pela mesma condição do trigger', () => {
  const m = ultimaCom(/UPDATE public\.onboarding_tokens t SET expires_at = greatest\(/);
  assert.ok(m, 'os tokens já emitidos não são estendidos');
  assert.match(m.s,
    new RegExp(`UPDATE public\\.onboarding_tokens t SET expires_at = greatest\\(t\\.expires_at, t\\.issued_at \\+ interval '45 days'\\) WHERE t\\.source_type = 'pmi_application' AND ${ESCOPO.replace('t?\\.?', 't\\.')} AND NOT public\\._na_avaliacao_geral\\(t\\.source_id\\);`),
    'a extensão dos tokens já emitidos divergiu da condição do trigger');
});

test('#2393i S: nenhum cliente executa a função do prazo', () => {
  const { file } = captura(TOKEN_FN);
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${TOKEN_FN}\\(\\) FROM PUBLIC, anon, authenticated;`), 'a função não é revogada dos clientes');
  for (const { f, s } of todas().filter((x) => x.f >= file))
    assert.doesNotMatch(s, new RegExp(`GRANT[^;]*ON FUNCTION public\\.${TOKEN_FN}\\b[^;]*\\b(anon|PUBLIC|authenticated)\\b`, 'i'), `${f}: devolve a função a um cliente`);
});

// Os textos dos e-mails: extrai as 3 línguas de um jsonb_build_object('pt', '...', 'en', '...', 'es', '...').
function linguas(trecho) {
  const m = trecho.match(/^jsonb_build_object\('pt', '((?:[^']|'')*)', 'en', '((?:[^']|'')*)', 'es', '((?:[^']|'')*)'\)/);
  assert.ok(m, 'o texto não está nas 3 línguas');
  return { pt: m[1].replace(/''/g, "'"), en: m[2].replace(/''/g, "'"), es: m[3].replace(/''/g, "'") };
}
const variaveis = (txt) => [...txt.matchAll(/\{\{([a-z_]+)\}\}/g)].map((x) => x[1]);
const ASSUNTO = { pt: 'Recebemos sua candidatura à vaga {{role_label}}', en: 'We received your application for {{role_label}}', es: 'Recibimos su candidatura a la vacante {{role_label}}' };

test('#2393i S: o e-mail de candidatura recebida do fluxo geral diz "recebemos", nas 3 línguas, sem travessão', () => {
  const m = ultimaCom(/UPDATE public\.campaign_templates SET subject = jsonb_build_object\(/);
  assert.ok(m, 'o template geral não é atualizado');
  const bloco = m.s.slice(m.s.indexOf('UPDATE public.campaign_templates SET subject = '), m.s.indexOf("WHERE slug = 'pmi_welcome_with_token';"));
  assert.ok(bloco.length > 0, 'a atualização não é do template pmi_welcome_with_token');
  const corte = (chave) => bloco.slice(bloco.indexOf(`${chave} = `) + `${chave} = `.length);
  assert.deepEqual(linguas(corte('subject')), ASSUNTO, 'o assunto do e-mail geral não é o decidido (R4)');
  const DECLARADAS = ['chapter', 'first_name', 'role_label', 'onboarding_url', 'expires_in_days'];
  for (const chave of ['body_html', 'body_text']) {
    for (const [lang, txt] of Object.entries(linguas(corte(chave)))) {
      assert.doesNotMatch(txt, /—|Bem-vind|Welcome to|Bienvenid/, `${chave} ${lang}: travessão ou boas-vindas antes da aprovação`);
      for (const v of variaveis(txt)) assert.ok(DECLARADAS.includes(v), `${chave} ${lang}: {{${v}}} não é passada pelo worker`);
    }
  }
});

test('#2393i S: o e-mail do piloto tem os passos e a data do convite, e só usa variável declarada', () => {
  const m = ultimaCom(/INSERT INTO public\.campaign_templates \([^)]*\) SELECT 'Candidatura recebida, vaga piloto da linha', 'pmi_welcome_line_pilot',/);
  assert.ok(m, 'o template do piloto não é criado');
  const ini = m.s.indexOf("'pmi_welcome_line_pilot', ") + "'pmi_welcome_line_pilot', ".length;
  const resto = m.s.slice(ini);
  const assunto = linguas(resto);
  assert.deepEqual(assunto, ASSUNTO, 'o assunto do piloto diverge do geral (R4)');
  const decl = resto.match(/'(\{"first_name"[^']*\})'::jsonb WHERE NOT EXISTS \(SELECT 1 FROM public\.campaign_templates WHERE slug = 'pmi_welcome_line_pilot'\);/);
  assert.ok(decl, 'as variáveis do piloto não estão declaradas, ou o INSERT deixou de ser idempotente');
  const declaradas = Object.keys(JSON.parse(decl[1]));
  let pos = resto.indexOf("'), jsonb_build_object('pt'") + 4;
  for (const nome of ['body_html', 'body_text']) {
    const txts = linguas(resto.slice(pos));
    for (const [lang, txt] of Object.entries(txts)) {
      assert.ok(txt.includes('{{video_invite_by}}'), `${nome} ${lang}: sem a data do convite do vídeo`);
      assert.match(txt, /45/, `${nome} ${lang}: sem o prazo do resultado`);
      assert.doesNotMatch(txt, /—|Bem-vind|Welcome to|Bienvenid/, `${nome} ${lang}: travessão ou boas-vindas`);
      for (const v of variaveis(txt)) assert.ok(declaradas.includes(v), `${nome} ${lang}: {{${v}}} não declarada`);
    }
    pos = resto.indexOf("'), jsonb_build_object('pt'", pos) + 4;
  }
});

test('#2393i S: o líder não recebe nem registra o e-mail da candidatura piloto (R2)', () => {
  const { corpo } = captura('get_opening_application');
  assert.match(corpo,
    /PERFORM public\._log_opening_application_access\( v_app\.id, v_caller_id, CASE WHEN public\._na_avaliacao_geral\(v_app\.id\) THEN ARRAY\['email'\] ELSE ARRAY\[\]::text\[\] END \|\| ARRAY\['applicant_name', 'chapter',/,
    'o registro de acesso voltou a gravar o e-mail da candidatura piloto');
  const retorno = corpo.slice(corpo.indexOf('END) q ); RETURN jsonb_build_object('));
  assert.match(retorno, /'email', CASE WHEN public\._na_avaliacao_geral\(v_app\.id\) THEN v_app\.email END,/,
    'o e-mail da candidatura piloto voltou a sair para o líder');
  assert.doesNotMatch(retorno, /'email', v_app\.email,/, 'o e-mail sai sem a condição');
});
