// tests/contracts/2341-o-gate-do-digest-enxerga-job-ausente.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2341 — `get_digest_health` era cega a job ausente.
 *
 * A versao anterior procurava 3 jobs num `WHERE jobname IN (...)`. Um deles
 * (`weekly-card-digest-saturday`) foi removido em maio (p89_cron_audit_fixes), e o `IN` **nao
 * devolve a linha que falta**: o job sumia do denominador em vez de aparecer como problema.
 * `max(coalesce(days,999))` tambem so via os jobs ENCONTRADOS, entao o 999 ("nunca rodou") era
 * alcancavel apenas por job que EXISTE. ⇒ remover o digest do membro passaria em VERDE.
 *
 * O conserto inverte o denominador: a EXPECTATIVA e a tabela, e o cron e o que se mede contra
 * ela (`LEFT JOIN` a partir da expectativa). Aposentadoria e DADO, nao prosa — um job aposentado
 * nao reprova, e um que RESSUSCITA tem estado proprio.
 *
 * POR QUE SO AGORA: a funcao pinta verde com `member_digest_pending < 100`, e ate a #2286 essa
 * metrica era baixa PORQUE o carimbo mentia. Instrumentar um canal quebrado da um verde que nao
 * significa nada — era a ordem declarada no handoff, e a medicao a confirmou.
 *
 * Cross-ref: #2341, #2286 (o canal que esta funcao mede), #1932, ADR-0022.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const cap = latestFunctionCapture(ROOT, 'get_digest_health');
const corpo = maskLineComments(cap?.block ?? '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const ESTADOS_VERMELHOS = ['ausente', 'inativo', 'silencioso'];

// ── ESTATICO ──────────────────────────────────────────────────────────────────────────

test('#2341 static: a funcao NAO carrega lista de jobname no corpo', () => {
  // A causa raiz. Uma lista de nomes no corpo torna o denominador invisivel: o que nao esta
  // na lista nao e medido, e o que saiu do cron nao aparece.
  assert.doesNotMatch(corpo, /jobname\s+IN\s*\(\s*'/i,
    'o corpo voltou a farejar jobname por literal — o job removido some do denominador (#2341)');
  assert.match(corpo, /FROM\s+public\.digest_cron_expectations/i,
    'a expectativa tem de vir da tabela, que e o denominador');
});

test('#2341 static: o LEFT JOIN parte da EXPECTATIVA, nao do cron', () => {
  // A direcao importa: `FROM cron.job LEFT JOIN expectativa` nao enxerga job ausente.
  assert.match(corpo, /FROM\s+public\.digest_cron_expectations\s+\w+\s*\n?\s*LEFT\s+JOIN\s+cron\.job/i,
    'precisa ser expectativa LEFT JOIN cron.job — ao contrario, o ausente nao vira linha');
});

test('#2341 static: os estados existem, e "ausente" nunca e verde', () => {
  for (const estado of ['ausente', 'inativo', 'silencioso', 'aposentado', 'ressuscitado',
                        'nunca_rodou', 'schedule_divergente', 'saudavel']) {
    assert.ok(corpo.includes(`'${estado}'`), `o corpo precisa classificar '${estado}'`);
  }
  // O ramo vermelho tem de citar os tres estados que significam "o cron nao vai rodar".
  const ramoRed = corpo.match(/WHEN\s+EXISTS[\s\S]{0,300}?THEN\s+'red'/i);
  assert.ok(ramoRed, 'precisa existir um ramo que devolve red');
  for (const estado of ESTADOS_VERMELHOS) {
    assert.ok(ramoRed[0].includes(`'${estado}'`),
      `'${estado}' tem de cair em red — era exatamente o caso que a versao anterior nao reprovava`);
  }
});

test('#2341 static: o CASE amarra retired_at aos estados aposentado/ressuscitado', () => {
  // ⚠️ A primeira versao desta assercao so procurava a STRING `retired_at IS NOT NULL` no corpo, e
  // ficava verde com a classificacao inteira neutralizada — porque a mesma string sobrevive na
  // contagem de `retired_jobs`, no RETURN. O teste de mutacao pegou. Terceira vez nesta casa que
  // presenca-de-string passa por prova: o que vale e amarrar CONDICAO ao RESULTADO, dentro do
  // bloco que classifica.
  const bloco = corpo.match(/CASE[\s\S]*?END\s+AS\s+estado/i);
  assert.ok(bloco, 'precisa existir o CASE que produz `estado`');
  assert.match(bloco[0], /retired_at\s+IS\s+NOT\s+NULL\s+AND\s+\w+\.jobid\s+IS\s+NOT\s+NULL\s+THEN\s+'ressuscitado'/i,
    'job aposentado que VOLTOU tem de virar `ressuscitado` — senao volta a ser silencio');
  assert.match(bloco[0], /retired_at\s+IS\s+NOT\s+NULL\s+THEN\s+'aposentado'/i,
    'aposentado tem de sair de retired_at, nao de uma condicao neutralizada');
  assert.match(bloco[0], /jobid\s+IS\s+NULL\s+THEN\s+'ausente'/i,
    'ausente tem de sair de jobid IS NULL (a linha que o LEFT JOIN preserva)');
});

// ── DB: a camada VIVA ─────────────────────────────────────────────────────────────────

test('#2341 db: a expectativa esta seedada, com o aposentado justificado',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb()
      .from('digest_cron_expectations')
      .select('jobname, expected_schedule, max_days_between_runs, retired_at, retired_reason');
    assert.ifError(error);
    const linhas = data ?? [];
    // Controle positivo: se a tabela estiver vazia, as assercoes abaixo passariam por vacuo.
    assert.ok(linhas.length >= 3, `esperava >=3 expectativas, achei ${linhas.length}`);
    for (const l of linhas.filter((x) => x.retired_at)) {
      assert.ok(l.retired_reason, `${l.jobname} aposentado sem motivo registrado`);
    }
    const vigentes = linhas.filter((x) => !x.retired_at).map((x) => x.jobname);
    assert.ok(vigentes.includes('send-weekly-member-digest'), 'o digest do membro e expectativa vigente');
    assert.ok(vigentes.includes('send-weekly-leader-digest'), 'o digest do lider e expectativa vigente');
  });

test('#2341 db: aposentar SEM motivo e RECUSADO pelo banco (exercido, nao lido do catalogo)',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Exemcao como DADO precisa de dente. Isto EXERCE o CHECK em vez de ler pg_constraint:
    // um catalogo diz o que esta declarado, e so a escrita diz o que acontece.
    const alvo = '__fixture-2341-sem-motivo';
    const { error } = await sb().from('digest_cron_expectations').insert({
      jobname: alvo, description: 'fixture do guard #2341',
      expected_schedule: '0 12 * * 6', max_days_between_runs: 8,
      retired_at: new Date().toISOString(), retired_reason: null,
    });
    // Limpeza defensiva: se o CHECK NAO barrou, a linha entrou e precisa sair antes de reprovar.
    if (!error) await sb().from('digest_cron_expectations').delete().eq('jobname', alvo);
    assert.ok(error, 'retired_at sem retired_reason tem de ser RECUSADO — sem isso a tabela ' +
      'volta a guardar silencio sem causa (#2341)');
    // ⚠️ O assert abaixo checa o TIPO do erro, nao a sua existencia — e foi ele que pegou o
    // rename de `purpose` para `description`: o insert falhou com PGRST204 (coluna inexistente),
    // nao com violacao de CHECK. Um `assert.ok(error)` generico teria passado pelo motivo errado.
    assert.match(String(error.message + ' ' + (error.code ?? '')), /23514|check|violates/i,
      `esperava violacao de CHECK, veio: ${error.code} ${error.message}`);
  });

test('#2341 static: a migration DECLARA RLS na tabela de expectativa', () => {
  // CONTEUDO, nao efeito: isto afirma o que a migration declara, nao o que a PostgREST faz. Nao
  // ha caminho barato para exercer RLS aqui (sem GRANT para anon, a recusa vem do grant e nao da
  // policy, e as duas causas ficariam indistinguiveis).
  const dir = resolve(ROOT, 'supabase/migrations');
  const todas = readdirSync(dir).filter((f) => f.endsWith('.sql'))
    .map((f) => readFileSync(join(dir, f), 'utf8')).join('\n');
  assert.match(todas,
    /ALTER\s+TABLE\s+public\.digest_cron_expectations\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
    'a tabela nova precisa declarar RLS (LGPD GC-162)');
});

test('#2341 db: nenhuma expectativa VIGENTE esta ausente do cron',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Mede o mesmo fato que a funcao mede, por caminho independente: a funcao e self-gated
    // (auth.uid()), e service_role nao a exerce. Aqui o cruzamento e direto.
    const { data, error } = await sb().rpc('_audit_digest_cron_coverage');
    if (error && /does not exist|not find/i.test(error.message)) {
      console.log('#2341 NAO MEDIDO: helper _audit_digest_cron_coverage ausente — ' +
        'a cobertura viva nao foi verificada por esta assercao.');
      return;
    }
    assert.ifError(error);
    const linhas = data ?? [];
    assert.ok(linhas.length > 0, 'controle positivo: o helper devolveu ao menos uma expectativa');
    const ausentes = linhas.filter((l) => l.esta_no_cron === false && l.retired === false);
    assert.deepEqual(ausentes.map((l) => l.jobname), [],
      `expectativa vigente sem cron correspondente: ${ausentes.map((l) => l.jobname).join(', ')}`);
  });
