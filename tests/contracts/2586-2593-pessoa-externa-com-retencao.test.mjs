/**
 * #2586 + #2593, fatia A: temas de comunicação e o caminho único de pessoa externa por e-mail, com prazo de
 * guarda e varredura diária (decisões do GP de 09/10/2026).
 *
 * Hermético: lê a migration. Cada asserção amarra a condição ao resultado no bloco que decide; comentários
 * mascarados. O ponto mais sensível é a varredura: ela anonimiza dado e apaga pessoa, então o guard prende
 * cada exclusão (membro, candidatura viva, vínculo vigente) e exige que o ensaio e a execução usem o MESMO
 * predicado, para o número do ensaio ser o número que a execução vai tocar.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const migs = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => /^\d{14}_2586_2593_temas_e_pessoa_externa_com_retencao\.sql$/.test(f));
const MIG = maskLineComments(readFileSync(resolve(ROOT, 'supabase/migrations', migs[0] ?? 'x'), 'utf8'));

function fnBody(name) {
  const start = MIG.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(start >= 0, `a migration precisa definir ${name}`);
  const open = MIG.indexOf('$function$', start);
  return MIG.slice(open, MIG.indexOf('$function$;', open + 10));
}
const norm = (s) => s.replace(/\s+/g, ' ').trim();

test('uma migration só', () => assert.equal(migs.length, 1));

test('upsert: acha por e-mail principal ou secundário, com o membro primeiro', () => {
  const body = fnBody('_external_person_upsert');
  assert.match(body, /WHERE lower\(p\.email\) = v_email\s+OR EXISTS \(SELECT 1 FROM unnest\(p\.secondary_emails\) se WHERE lower\(se\) = v_email\)\s+ORDER BY \(p\.legacy_member_id IS NOT NULL\) DESC, \(p\.auth_id IS NOT NULL\) DESC/);
});

test('upsert: pessoa nova nasce pending COM a marca de origem; protegida não ganha vínculo de prazo', () => {
  const body = fnBody('_external_person_upsert');
  assert.match(body, /INSERT INTO public\.persons \(name, email, consent_status, consent_version\)\s+VALUES \([^;]*'pending', 'external-contact'\)/);
  assert.match(body, /\(p\.legacy_member_id IS NOT NULL OR p\.auth_id IS NOT NULL OR p\.pmi_id IS NOT NULL\s+OR EXISTS \(SELECT 1 FROM public\.members m WHERE m\.person_id = p\.id\)\)\s+INTO v_id, v_protected/);
  assert.match(body, /IF NOT v_protected THEN\s+INSERT INTO public\.person_external_links/);
  assert.match(body, /PERFORM pg_advisory_xact_lock\(hashtext\('external_person:' \|\| v_email\)\);/);
  assert.match(body, /SET retention_until = GREATEST\(public\.person_external_links\.retention_until, EXCLUDED\.retention_until\)/);
});

const SWEEP = () => fnBody('_external_contact_retention_sweep');

test('varredura: corte de 1 ano', () => {
  assert.match(SWEEP(), /v_cutoff\s+timestamptz := now\(\) - interval '1 year';/);
});

const PROTECTED = /WITH protected AS \(\s+SELECT lower\(p\.email\) AS e FROM public\.persons p\s+WHERE p\.legacy_member_id IS NOT NULL OR p\.auth_id IS NOT NULL\s+UNION SELECT lower\(se\) FROM public\.persons p, unnest\(p\.secondary_emails\) se\s+WHERE p\.legacy_member_id IS NOT NULL OR p\.auth_id IS NOT NULL\s+UNION SELECT lower\(m\.email\) FROM public\.members m\s+UNION SELECT lower\(se\) FROM public\.members m, unnest\(m\.secondary_emails\) se\s+UNION SELECT lower\(a\.email\) FROM public\.selection_applications a WHERE a\.anonymized_at IS NULL\s+\)/g;

test('varredura: e-mail de membro (members e persons) e de candidatura viva fica protegido, nos dois ramos', () => {
  assert.equal((SWEEP().match(PROTECTED) || []).length, 2);
  assert.match(
    SWEEP(),
    /UPDATE public\.campaign_recipients cr\s+SET external_email = NULL, external_name = NULL, error_message = NULL, last_user_agent = NULL, person_id = NULL\s+WHERE cr\.member_id IS NULL AND cr\.external_email IS NOT NULL AND cr\.created_at < v_cutoff\s+AND NOT EXISTS \(SELECT 1 FROM protected pr WHERE pr\.e = lower\(cr\.external_email\)\);/,
  );
  // cada envio vence pela própria data: vínculo vigente de outro uso não renova envio antigo
  assert.doesNotMatch(SWEEP(), /l\.person_id = cr\.person_id/);
});

test('varredura: o ensaio conta exatamente o que a execução anonimiza (mesma CTE, mesmo predicado)', () => {
  const body = SWEEP();
  // recorta cada ramo de (a): do "IF p_dry_run THEN WITH" ao "ELSE", e do "ELSE WITH" ao GET DIAGNOSTICS
  const start = body.search(/IF p_dry_run THEN\s+WITH protected AS/);
  const mid = body.indexOf('ELSE', start);
  const end = body.indexOf('GET DIAGNOSTICS v_recipients', mid);
  assert.ok(start >= 0 && mid > start && end > mid, 'os dois ramos de (a) precisam existir');
  const dryBranch = body.slice(start, mid);
  const runBranch = body.slice(mid, end);
  const cte = (t) => norm(t.slice(t.indexOf('WITH protected AS'), t.search(/\)\s+(SELECT count|UPDATE public\.campaign_recipients)/) + 1));
  const where = (t) => norm((t.match(/(WHERE cr\.member_id[\s\S]*?);/) || ['', ''])[1]);
  assert.equal(cte(dryBranch), cte(runBranch));
  assert.ok(where(dryBranch).length > 0);
  assert.equal(where(dryBranch), where(runBranch));
});

test('varredura: só apaga a pessoa CRIADA pelo caminho externo, por estado, sem nenhum laço (inclusive os de CASCADE)', () => {
  assert.match(
    SWEEP(),
    /WHERE p\.consent_version = 'external-contact'\s+AND p\.auth_id IS NULL AND p\.legacy_member_id IS NULL AND p\.pmi_id IS NULL\s+AND NOT EXISTS \(SELECT 1 FROM public\.person_external_links l\s+WHERE l\.person_id = p\.id AND l\.retention_until >= current_date\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.members m WHERE m\.person_id = p\.id\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.engagements en\s+WHERE en\.person_id = p\.id OR en\.granted_by = p\.id OR en\.revoked_by = p\.id\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.event_guest_certificates g WHERE g\.person_id = p\.id\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.initiative_member_progress imp WHERE imp\.person_id = p\.id\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.member_chapter_affiliations mca WHERE mca\.person_id = p\.id\)\s+AND NOT EXISTS \(SELECT 1 FROM public\.drive_membership_grants dmg WHERE dmg\.grantee_person_id = p\.id\)/,
  );
  assert.match(SWEEP(), /AND NOT EXISTS \(SELECT 1 FROM public\.drive_membership_grants dmg WHERE dmg\.grantee_person_id = p\.id\)\s+AND NOT EXISTS \(SELECT 1 FROM competition\.registrations cr2 WHERE cr2\.person_id = p\.id\)\s+LOOP/);
  assert.doesNotMatch(SWEEP(), /v_expired/);
  assert.match(SWEEP(), /EXCEPTION WHEN foreign_key_violation THEN\s+v_skipped := v_skipped \|\| r\.id;/);
});

test('varredura: nome do convidado externo na agenda some 1 ano depois da reunião; coapresentador membro não', () => {
  assert.match(
    SWEEP(),
    /UPDATE public\.event_agenda_blocks b SET guest_name = v_guest_name\s+FROM public\.events e\s+WHERE e\.id = b\.event_id\s+AND b\.external_guest AND b\.guest_name IS NOT NULL AND b\.guest_name <> v_guest_name\s+AND e\.date < current_date - interval '1 year';/,
  );
});

test('pós-condição: controle positivo e negativo em subtransação desfeita', () => {
  assert.match(MIG, /RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'controle-2586-desfazer';\s+EXCEPTION WHEN raise_exception THEN\s+IF SQLERRM <> 'controle-2586-desfazer' THEN RAISE; END IF;/);
  assert.match(MIG, /IF NOT \(v_ctrl->'person_ids'\) \? v_ctrl_new::text THEN\s+RAISE EXCEPTION/);
  assert.match(MIG, /IF \(v_ctrl->'person_ids'\) \? v_ctrl_old::text THEN\s+RAISE EXCEPTION/);
});

test('varredura: o ensaio não escreve; a execução deixa trilha', () => {
  const body = SWEEP();
  assert.match(body, /IF NOT p_dry_run AND \(v_recipients \+ v_links \+ v_guests \+ cardinality\(v_deleted\) \+ cardinality\(v_skipped\)\) > 0 THEN\s+INSERT INTO public\.admin_audit_log/);
  assert.match(body, /IF p_dry_run THEN\s+v_deleted := v_deleted \|\| r\.id;\s+ELSE\s+BEGIN\s+DELETE FROM public\.persons/);
});

test('executor registrado: o nome do job é o executor das duas políticas', () => {
  assert.match(MIG, /SELECT cron\.schedule\('external-contact-retention-daily',/);
  assert.match(MIG, /SELECT v\.table_name, v\.retention_days, v\.cleanup_type, v\.description, true, 'external-contact-retention-daily'/);
  assert.match(MIG, /\('campaign_recipients', 365, 'anonymize',/);
  assert.match(MIG, /\('person_external_links', 365, 'delete',/);
});

test('temas: 11, com plataforma; leitura só por membro; os 55 templates recebem tema', () => {
  const seed = MIG.match(/INSERT INTO public\.campaign_themes \(slug, label_i18n, sort_order\) VALUES([\s\S]*?)ON CONFLICT/);
  assert.ok(seed);
  const slugs = [...seed[1].matchAll(/\('([a-z]+)',/g)].map((m) => m[1]).sort();
  assert.deepEqual(slugs, ['certificados', 'comunicacao', 'conta', 'curadoria', 'eventos', 'filiacao', 'governanca', 'iniciativas', 'onboarding', 'plataforma', 'selecao']);
  assert.match(MIG, /CREATE POLICY campaign_themes_read_authenticated ON public\.campaign_themes FOR SELECT TO authenticated USING \(public\.rls_is_member\(\)\);/);
  const themed = [...MIG.matchAll(/UPDATE public\.campaign_templates SET theme = '([a-z]+)'\s+WHERE theme IS NULL AND slug IN \(([\s\S]*?)\);/g)]
    .flatMap((m) => [...m[2].matchAll(/'([^']+)'/g)].map((x) => x[1]));
  assert.equal(themed.length, 55);
  assert.equal(new Set(themed).size, 55, 'cada template recebe um tema só');
  assert.match(MIG, /SELECT count\(\*\) INTO v_n FROM public\.campaign_templates WHERE theme IS NULL;\s+IF v_n <> 0 THEN RAISE EXCEPTION/);
});

test('category não muda de valor: cinco funções e a tela leem os valores atuais', () => {
  assert.doesNotMatch(MIG, /SET\s+category\s*=/);
  assert.doesNotMatch(MIG, /campaign_templates[^;]*DROP CONSTRAINT[^;]*category/);
});

test('ORGANIZER e reply-to na caixa institucional, como configuração', () => {
  assert.match(MIG, /\('campaign_default_reply_to', to_jsonb\('nucleoia@pmigo\.org\.br'::text\),/);
  assert.match(MIG, /\('agenda_invite_organizer_email', to_jsonb\('nucleoia@pmigo\.org\.br'::text\),/);
});

test('vínculos e funções internas fora do alcance de anon e authenticated', () => {
  assert.match(MIG, /CREATE POLICY rpc_only_deny_all ON public\.person_external_links FOR ALL USING \(false\);/);
  for (const sig of ['_external_person_upsert\\(text, text, text, uuid, date\\)', '_external_contact_retention_sweep\\(boolean\\)', '_external_contact_retention_cron\\(\\)']) {
    assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon, authenticated;`));
  }
});
