/**
 * Contract: #2393, fatia 3 (ADR-0134, decisão D4 do GP em 02/11/2026) — token de candidatura de vaga piloto sem
 * o escopo de vídeo geral.
 *
 * Um trigger BEFORE INSERT OR UPDATE em onboarding_tokens tira 'video_screening' do token de candidatura cuja
 * vaga é 'line_pilot'. É o ponto único: o worker e as 3 funções que emitem token gravam todos nesta tabela.
 *
 * Camadas:
 *   S  estática:
 *      - a função do trigger: a condição (candidatura, escopo presente, vaga fora da avaliação geral) e o
 *        resultado (array_remove do escopo) no mesmo IF;
 *      - o trigger existe no estado FINAL das migrations (CREATE e DROP reproduzidos em ordem), BEFORE INSERT OR
 *        UPDATE OF scopes, source_id, source_type, FOR EACH ROW;
 *      - os 4 emissores conhecidos gravam em onboarding_tokens, que é a premissa de o trigger cobri-los;
 *      - nenhum cliente executa a função.
 * O efeito (o token sai com 2 escopos na vaga piloto e com 3 na geral) é a verificação do pacote.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const FN = '_token_de_candidatura_sem_video_no_piloto';
const TRG = 'trg_token_de_candidatura_sem_video_no_piloto';

function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

test('#2393f S: a função tira video_screening só do token de candidatura de vaga fora da avaliação geral', () => {
  const { corpo } = captura(FN);
  assert.match(corpo,
    /RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS \$function\$ BEGIN IF NEW\.source_type = 'pmi_application' AND 'video_screening' = ANY \(NEW\.scopes\) AND NOT public\._na_avaliacao_geral\(NEW\.source_id\) THEN NEW\.scopes := array_remove\(NEW\.scopes, 'video_screening'\); END IF; RETURN NEW; END; \$function\$/,
    'a condição ou o resultado do trigger mudou');
});

test('#2393f S: o trigger existe no estado final das migrations, antes de gravar, em INSERT e na troca de escopo ou origem', () => {
  let ultimo = null;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    const s = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')).replace(/\s+/g, ' ');
    const eventos = [];
    for (const m of s.matchAll(new RegExp(`CREATE (?:OR REPLACE )?TRIGGER ${TRG} ([^;]*);`, 'g'))) eventos.push({ i: m.index, def: m[1] });
    for (const m of s.matchAll(new RegExp(`DROP TRIGGER (?:IF EXISTS )?${TRG} ON public\\.onboarding_tokens;`, 'g'))) eventos.push({ i: m.index, def: null });
    for (const e of eventos.sort((a, b) => a.i - b.i)) ultimo = e.def;
  }
  assert.ok(ultimo, 'o trigger não existe no estado final das migrations');
  assert.equal(ultimo, `BEFORE INSERT OR UPDATE OF scopes, source_id, source_type ON public.onboarding_tokens FOR EACH ROW EXECUTE FUNCTION public.${FN}()`,
    'o trigger mudou de momento, de eventos ou de função');
});

test('#2393f S: os 4 emissores de token de candidatura gravam em onboarding_tokens', () => {
  const worker = maskJsComments(readFileSync(resolve(ROOT, 'cloudflare-workers/pmi-vep-sync/src/onboarding-token.ts'), 'utf8')).replace(/\s+/g, ' ');
  assert.match(worker, /\.from\('onboarding_tokens'\) \.insert\(/, 'o worker deixou de gravar direto em onboarding_tokens');
  for (const nome of ['dispatch_pending_welcomes', 'dispatch_consent_nudge', 'reissue_onboarding_link']) {
    const { corpo } = captura(nome);
    assert.match(corpo, /INSERT INTO public\.onboarding_tokens \(/, `${nome} deixou de gravar em onboarding_tokens`);
  }
});

function semGrantDepois(file, funcao, papeis) {
  const re = new RegExp(`GRANT[^;]*ON FUNCTION public\\.${funcao}\\b[^;]*\\b(${papeis})\\b`, 'i');
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= file)) {
    assert.doesNotMatch(maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')), re, `${f}: devolve ${funcao} a ${papeis}`);
  }
}

test('#2393f S: nenhum cliente executa a função do trigger', () => {
  const { file } = captura(FN);
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${FN}\\(\\) FROM PUBLIC, anon, authenticated;`), 'a função não é revogada dos clientes');
  semGrantDepois(file, FN, 'anon|PUBLIC|authenticated');
});
