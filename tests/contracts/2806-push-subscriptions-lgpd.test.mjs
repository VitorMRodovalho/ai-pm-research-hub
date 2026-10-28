// tests/contracts/2806-push-subscriptions-lgpd.test.mjs
/**
 * #2806, fatia A: a inscricao de push web por aparelho e dado pessoal. Este guard prende quatro coisas:
 *
 *   1. ninguem alem do dono le a inscricao, e ninguem escreve nela sem passar pelas funcoes;
 *   2. a inscricao so nasce numa origem da lista (platform_settings), para membro ativo;
 *   3. o ciclo do art. 18 a alcanca nos tres caminhos: exportacao (sem as chaves), autoexclusao
 *      (delete_my_personal_data nao marca anonymized_at, entao o gatilho NAO a cobre) e anonimizacao
 *      ou desativacao (gatilho em members, SEM lista de colunas: is_active e derivado de member_status
 *      por um gatilho BEFORE, e gatilho com lista so ve as colunas do SET);
 *   4. a lista do proprio membro nao devolve endpoint nem chaves.
 *
 * Os arquivos das migrations recebem a versao no apply, por isso o guard os acha pelo sufixo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const DIR = resolve(process.cwd(), 'supabase/migrations');
const ALL = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
const FILES = ALL.filter((f) => f.endsWith('_2806_push_subscriptions.sql'));
const FIX = ALL.filter((f) => f.endsWith('_2806_push_purge_any_update.sql'));

// Prosa sai antes do assert: os comentarios explicam o desenho, e guard que le prosa acusa a propria
// documentacao (licao do #1801/#1805/#1809).
const masked = (f) => readFileSync(resolve(DIR, f), 'utf8')
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
const SQL = FILES.length === 1 ? masked(FILES[0]) : '';

function fnBody(name) {
  const head = `CREATE OR REPLACE FUNCTION public.${name}(`;
  assert.equal(SQL.split(head).length - 1, 1, `${name} deve ser definida uma vez na migration`);
  const start = SQL.indexOf(head);
  const end = SQL.indexOf('$function$;', start);
  assert.ok(end > start, `${name} sem fim de corpo`);
  return SQL.slice(start, end);
}

test('#2806: exatamente uma migration da fatia A', () => {
  assert.equal(FILES.length, 1, `esperado 1 arquivo *_2806_push_subscriptions.sql, achei ${FILES.length}`);
});

test('#2806: RLS ligado, nada para anon, e authenticated so le', () => {
  assert.match(SQL, /ALTER TABLE public\.push_subscriptions ENABLE ROW LEVEL SECURITY;\nREVOKE ALL ON public\.push_subscriptions FROM PUBLIC, anon, authenticated;\nGRANT SELECT ON public\.push_subscriptions TO authenticated;/);
  assert.doesNotMatch(SQL, /GRANT (?:ALL|INSERT|UPDATE|DELETE|TRUNCATE)[^;]*ON public\.push_subscriptions[^;]*TO [^;]*(?:anon|authenticated)/);
});

test('#2806: a leitura direta e so do dono', () => {
  assert.match(SQL, /CREATE POLICY push_subscriptions_select_own ON public\.push_subscriptions\s+FOR SELECT TO authenticated\s+USING \(member_id IN \(SELECT m\.id FROM public\.members m WHERE m\.auth_id = auth\.uid\(\)\)\);/);
});

test('#2806: inscrever exige membro ativo e a origem do CABECALHO na lista', () => {
  const b = fnBody('register_push_subscription');
  assert.match(b, /WHERE m\.auth_id = auth\.uid\(\) AND m\.is_active = true;\s+IF v_member_id IS NULL THEN\s+RAISE EXCEPTION 'Not authenticated'/);
  // o parametro vem do cliente: quem decide e o Origin que o PostgREST expoe, e o parametro tem de bater com ele
  assert.match(b, /v_hdr_origin := current_setting\('request\.headers', true\)::json ->> 'origin';\s+SELECT ps\.value INTO v_allowed FROM public\.platform_settings ps WHERE ps\.key = 'push_allowed_origins';\s+IF v_hdr_origin IS NULL OR v_allowed IS NULL OR NOT \(v_allowed \? v_hdr_origin\) OR p_origin IS DISTINCT FROM v_hdr_origin THEN\s+RAISE EXCEPTION 'Origin not allowed/);
  // e o que se grava e a origem verificada, nao a declarada
  assert.match(b, /VALUES \(v_member_id, p_endpoint, p_p256dh, p_auth, v_hdr_origin, left\(p_user_agent, 512\)\)/);
  assert.match(SQL, /\('push_allowed_origins', '\["https:\/\/nucleoia\.org"\]'::jsonb,/);
});

test('#2806: o estoque de notificacoes imediatas nasce marcado e nunca vai por push', () => {
  // amarrado ao ADD COLUMN: sem a marca, o envio veria o estoque inteiro como pendente
  assert.match(SQL, /ALTER TABLE public\.notifications ADD COLUMN IF NOT EXISTS push_dispatched_at timestamptz;\nUPDATE public\.notifications SET push_dispatched_at = created_at\nWHERE delivery_mode = 'transactional_immediate' AND push_dispatched_at IS NULL;/);
});

test('#2806: desinscrever so apaga a inscricao do proprio membro', () => {
  const b = fnBody('unregister_push_subscription');
  assert.match(b, /DELETE FROM public\.push_subscriptions s WHERE s\.endpoint = p_endpoint AND s\.member_id = v_member_id;/);
});

test('#2806: a lista do membro nao devolve endpoint nem chaves', () => {
  const b = fnBody('list_my_push_subscriptions');
  assert.match(b, /FROM public\.push_subscriptions s WHERE s\.member_id = v_member_id/);
  assert.doesNotMatch(b, /p256dh|auth_secret|'endpoint'/);
});

test('#2806: as funcoes nao executam para anon, e o gatilho nao executa para ninguem', () => {
  for (const sig of [
    'register_push_subscription\\(text, text, text, text, text\\)',
    'unregister_push_subscription\\(text\\)',
    'list_my_push_subscriptions\\(\\)',
  ]) {
    assert.match(SQL, new RegExp(`REVOKE ALL ON FUNCTION public\\.${sig} FROM PUBLIC, anon;`));
  }
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\._push_subscriptions_purge\(\) FROM PUBLIC, anon, authenticated;/);
});

test('#2806 art. 18: exportacao inclui a inscricao do titular, sem as chaves', () => {
  const b = fnBody('export_my_data');
  const start = b.indexOf("'push_subscriptions', COALESCE((");
  assert.ok(start > 0, 'bloco push_subscriptions ausente do export_my_data');
  const block = b.slice(start, b.indexOf("'[]'::jsonb),", start));
  assert.match(block, /FROM public\.push_subscriptions ps WHERE ps\.member_id = v_member_id\)/);
  assert.match(block, /'endpoint', ps\.endpoint/);
  assert.doesNotMatch(block, /p256dh|auth_secret|row_to_json/,
    'endpoint mais chaves e credencial de envio: a exportacao nao deve criar uma');
});

test('#2806 art. 18: autoexclusao apaga a inscricao e diz que apagou', () => {
  const b = fnBody('delete_my_personal_data');
  assert.match(b, /DELETE FROM public\.push_subscriptions WHERE member_id = v_caller\.id;\s+GET DIAGNOSTICS v_push_deleted = ROW_COUNT;\s+IF v_push_deleted > 0 THEN v_cleared := array_append\(v_cleared, 'push_subscriptions'\); END IF;/);
});

test('#2806 art. 18: anonimizar ou desativar o membro apaga as inscricoes dele', () => {
  const b = fnBody('_push_subscriptions_purge');
  assert.match(b, /DELETE FROM public\.push_subscriptions WHERE member_id = NEW\.id;\s+RETURN NEW;/);
});

test('#2806 art. 18: o gatilho vigente dispara em QUALQUER update de members e decide pelo valor final', () => {
  assert.equal(FIX.length, 1, `esperado 1 arquivo *_2806_push_purge_any_update.sql, achei ${FIX.length}`);
  // vale a ULTIMA migration que cria o gatilho: uma posterior com lista de colunas traria o defeito de volta
  const defs = ALL.filter((f) => readFileSync(resolve(DIR, f), 'utf8').includes('trg_push_subscriptions_purge')
    && /CREATE TRIGGER trg_push_subscriptions_purge\b/.test(masked(f)));
  assert.equal(defs.at(-1), FIX[0], `a definicao vigente do gatilho esta em ${defs.at(-1)}`);
  // sem UPDATE OF: com lista, um UPDATE so de member_status desativa (via gatilho BEFORE) sem disparar este
  assert.match(masked(FIX[0]), /DROP TRIGGER IF EXISTS trg_push_subscriptions_purge ON public\.members;\nCREATE TRIGGER trg_push_subscriptions_purge\s+AFTER UPDATE ON public\.members\s+FOR EACH ROW\s+WHEN \(\(OLD\.anonymized_at IS NULL AND NEW\.anonymized_at IS NOT NULL\)\s+OR \(OLD\.is_active IS TRUE AND NEW\.is_active IS NOT TRUE\)\)\s+EXECUTE FUNCTION public\._push_subscriptions_purge\(\);/);
});
