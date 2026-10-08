/**
 * #2580 frente 2, regra 3 (decisoes do GP de 08/10/2026, D1 a D3 da PR D): o mesmo tipo de aviso para a mesma pessoa
 * em ate 7 dias vira item do resumo semanal, nao e-mail novo.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. o gatilho so mexe em aviso imediato, e so nos tipos informativos da lista (tipo novo nasce fora da regra);
 *   B. tipos com prazo (ratificacao de PI, curadoria, wiki) e urgentes ficam fora (D2 opcao B);
 *   C. so rebaixa quem recebe o resumo semanal, com o mesmo filtro do gerador do resumo;
 *   D. a repeticao exige outro item (D3: lembrete do mesmo item segue imediato), em 7 dias, contra um envio imediato;
 *   E. o gatilho e BEFORE INSERT por linha e a funcao nao e executavel por anon nem authenticated.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const DIR = resolve(ROOT, 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2580_repeticao_vai_para_o_resumo\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
const FN = maskLineComments(latestFunctionCapture(ROOT, '_notification_repeat_to_digest').block);
const LIST = (FN.match(/IF NEW\.type NOT IN \(([\s\S]*?)\) THEN RETURN NEW; END IF;/) || ['', ''])[1];
const TYPES = [...LIST.matchAll(/'([a-z_0-9]+)'/g)].map((m) => m[1]);

test('a migration existe', () => {
  assert.equal(files.length, 1, `esperava 1 migration, achei ${files.length}`);
});

test('A. so aviso imediato, e so os tipos informativos da lista', () => {
  assert.match(FN, /BEGIN\s+IF NEW\.delivery_mode IS DISTINCT FROM 'transactional_immediate' THEN RETURN NEW; END IF;/);
  assert.deepEqual(TYPES, [
    'engagement_welcome',
    'engagement_added',
    'member_offboarded',
    'card_comment_mention',
    'certificate_issued',
    'webinar_status_completed',
    'governance_cr_approved',
    'project_charter_approved',
  ]);
});

test('B. tipos com prazo e urgentes ficam fora', () => {
  for (const t of TYPES) {
    assert.doesNotMatch(t, /^(ip_ratification_|curation_|wiki_)/, `${t} tem prazo e nao pode ir para o resumo`);
  }
  assert.match(FN, /IF public\._is_urgent_email_type\(NEW\.type\) THEN RETURN NEW; END IF;/);
});

test('C. so rebaixa quem recebe o resumo semanal', () => {
  assert.match(FN, /IF NOT EXISTS \(\s+SELECT 1 FROM public\.members m\s+WHERE m\.id = NEW\.recipient_id\s+AND m\.is_active = true\s+AND m\.notify_weekly_digest = true\s+AND m\.notify_delivery_mode_pref IN \('weekly_digest', 'custom_per_type'\)\s+\) THEN RETURN NEW; END IF;/);
  const gen = maskLineComments(latestFunctionCapture(ROOT, 'generate_weekly_member_digest_cron').block);
  assert.match(gen, /WHERE is_active = true\s+AND notify_weekly_digest = true\s+AND notify_delivery_mode_pref IN \('weekly_digest', 'custom_per_type'\)/,
    'o filtro do gerador do resumo mudou; alinhe o gatilho');
});

test('D. repeticao de OUTRO item em 7 dias contra um envio imediato vira resumo', () => {
  assert.match(FN, /IF EXISTS \(\s+SELECT 1 FROM public\.notifications p\s+WHERE p\.recipient_id = NEW\.recipient_id\s+AND p\.type = NEW\.type\s+AND p\.delivery_mode = 'transactional_immediate'\s+AND p\.created_at >= now\(\) - interval '7 days'\s+AND p\.source_id IS DISTINCT FROM NEW\.source_id\s+\) THEN\s+NEW\.delivery_mode := 'digest_weekly';\s+END IF;/);
});

test('E. BEFORE INSERT por linha e funcao fechada', () => {
  assert.match(SQL, /CREATE TRIGGER trg_notification_repeat_to_digest\s+BEFORE INSERT ON public\.notifications\s+FOR EACH ROW EXECUTE FUNCTION public\._notification_repeat_to_digest\(\);/);
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\._notification_repeat_to_digest\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(FN, /SECURITY DEFINER\s+SET search_path TO ''/);
});
