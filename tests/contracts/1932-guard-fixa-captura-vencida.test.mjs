/**
 * Contract #1932 — o guard-do-guard: nenhum guard NOVO pode fixar uma migration vencida.
 *
 * CLASSE. Migration é história imutável. Um guard que fixa `supabase/migrations/<v>_*.sql` e
 * afirma propriedades sobre aquele texto prova "a propriedade valia na versão <v>". Quando uma
 * migration posterior redefine a mesma função, o arquivo fixado não muda e o guard segue VERDE
 * descrevendo um corpo que a produção não executa mais. **O modo de falha é não avisar:** se a
 * migration posterior tivesse AFROUXADO o portão, o guard teria ficado verde do mesmo jeito.
 *
 * INSTÂNCIA PROVADA. `568-consent-records-lgpd-read.test.mjs` afirma, com a mensagem "admin read
 * gated on view_pii", o portão `can_by_member(v_caller_id, 'view_pii')` de
 * `admin_list_member_consents`, lendo a migration de 05/08. A definição vigente (20260822120649)
 * usa `can_org_by_member`, que é o portão mais estrito. O guard nunca reprovou.
 *
 * GUARD. A dívida de hoje está congelada em `docs/audit/GUARD_PIN_STALENESS_BASELINE_1932.txt`.
 * Este teste reprova nos DOIS sentidos:
 *   - par (guard, função) novo fora da linha de base  → dívida nova, conserte o guard;
 *   - entrada da linha de base que já não está velha  → desculpa vencida, remova a linha.
 * O segundo sentido é o que faz a lista encolher em vez de virar depósito. É a mecânica de
 * allowlist validado do #1109 e do #938: nunca silenciar, sempre com denominador.
 *
 * ⚠️ PISO DE DENOMINADOR. As asserções finais existem porque a falha mais provável deste guard
 * não é ficar vermelho, é ficar VAZIO: basta a extração parar de casar (uma convenção de caminho
 * nova, um renomear de diretório) para o conjunto medido virar zero e o teste ficar verde para
 * sempre. `[] == []` é verde. Os pisos transformam esse esvaziamento em reprovação.
 *
 * NÃO diz que os 174 pares são 174 buracos. Diz que são 174 pontos sem contato com a definição
 * vigente; cada um só é buraco se a migration posterior mexeu justamente na propriedade afirmada.
 * Fixar continua certo para "esta migration entregou X"; é errado para afirmar invariante
 * corrente de segurança, LGPD ou autoridade.
 *
 * ⚠️ COBERTURA PARCIAL, MEDIDA — e escrita aqui porque um guard que se lê como completo sendo
 * parcial é a própria classe de defeito que ele existe para pegar. O par (guard, função) só é
 * visível quando o arquivo escreve o nome da função na forma `CREATE OR REPLACE FUNCTION
 * public.X`. Em 22/08, dos **334** arquivos que fixam migration, **201** escrevem ao menos um nome
 * nessa forma e **133 não escrevem nenhum** — afirmam sobre o texto fixado por outros caminhos
 * (match direto de trecho, contagem de policies, presença de GRANT). Esses são invisíveis aqui.
 *
 * E o ponto cego existe também POR FUNÇÃO dentro de arquivo visível: `export_my_data` estava
 * vencida no guard `568` (fixada em 05/08, vigente em 20260808000100) e o scanner não a via,
 * porque aquele arquivo afirma trechos do corpo sem nunca escrever o cabeçalho `CREATE OR REPLACE
 * FUNCTION public.export_my_data`. Só apareceu na revisão manual do lote de PII/LGPD.
 *
 * Offline (lê repo, não fala com banco). Refs #1932, #1910, #1931.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import {
  latestFunctionCapture,
  pairKey,
  parseBaseline,
  scanStalePins,
} from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const BASELINE_PATH = 'docs/audit/GUARD_PIN_STALENESS_BASELINE_1932.txt';

// Este arquivo cita caminhos de migration na documentação acima; se ele se varresse, entraria no
// próprio denominador.
const SELF = new Set(['tests/contracts/1932-guard-fixa-captura-vencida.test.mjs']);

const scan = scanStalePins(ROOT, SELF);
const baseline = parseBaseline(readFileSync(resolve(ROOT, BASELINE_PATH), 'utf8'));
const baselineSet = new Set(baseline);
const currentSet = new Set(scan.pairs.map((p) => pairKey(p.guard, p.fn)));

test('#1932: nenhum par (guard, função) NOVO fixa migration vencida', () => {
  const novos = scan.pairs.filter((p) => !baselineSet.has(pairKey(p.guard, p.fn)));

  const detalhe = novos
    .map((p) => `  ${p.guard}\n    afirma ${p.fn}, cuja definição mais nova está em ${p.newestFile}`)
    .join('\n');

  assert.equal(
    novos.length,
    0,
    `${novos.length} guard(s) passaram a afirmar sobre uma captura vencida:\n${detalhe}\n\n` +
      'Conserte o guard (leia a captura mais nova, ou afirme contra a definição vigente). ' +
      `Adicionar a linha em ${BASELINE_PATH} só é aceitável com justificativa escrita na PR: ` +
      'a lista existe para encolher.',
  );
});

test('#1932: a linha de base não guarda desculpa vencida', () => {
  const resolvidos = baseline.filter((k) => !currentSet.has(k));

  assert.equal(
    resolvidos.length,
    0,
    `${resolvidos.length} entrada(s) da linha de base já não estão desatualizadas — ` +
      `remova-as de ${BASELINE_PATH}:\n${resolvidos.map((k) => `  ${k}`).join('\n')}\n\n` +
      'Uma lista que só cresce mede o passado. Esta encolhe.',
  );
});

test('#1932: toda entrada da linha de base aponta para um guard que existe', () => {
  const guardsNoDisco = new Set(scan.pairs.map((p) => p.guard));
  // Um arquivo apagado some do scan e cairia no teste anterior como "resolvido", o que leria como
  // progresso. Separar as duas mensagens evita confundir guard consertado com guard removido.
  const orfas = baseline.filter((k) => {
    const guard = k.split('|')[0];
    if (guardsNoDisco.has(guard)) return false;
    try {
      readFileSync(resolve(ROOT, guard), 'utf8');
      return false;
    } catch {
      return true;
    }
  });

  assert.deepEqual(
    orfas,
    [],
    `linha de base cita guard(s) que não existem mais: ${orfas.join(', ')}. ` +
      'Se o guard foi removido de propósito, remova também a entrada.',
  );
});

test('#1932: o denominador não pode esvaziar (piso contra guard verde por vácuo)', () => {
  // Medidos em 22/08/2026: 294 arquivos fixam migration, 1701 migrations, 1269 funções no
  // catálogo. Os pisos ficam abaixo do medido com folga, para tolerarem remoção legítima sem
  // tolerarem colapso da extração.
  assert.ok(
    scan.filesPinning >= 200,
    `só ${scan.filesPinning} arquivos de teste fixam migration (piso 200). ` +
      'A extração provavelmente parou de casar; este guard estaria medindo o vazio.',
  );
  assert.ok(
    scan.migrationFileCount >= 1000,
    `só ${scan.migrationFileCount} migrations lidas (piso 1000) — diretório mudou de lugar?`,
  );
  assert.ok(
    scan.catalogSize >= 800,
    `só ${scan.catalogSize} funções no catálogo (piso 800) — o cabeçalho CREATE OR REPLACE ` +
      'deixou de casar?',
  );
  // O denominador que este guard REALMENTE enxerga (184 em 22/08). Sem piso próprio, a extração
  // de nomes podia colapsar sozinha: `filesPinning` seguiria em 294, nenhum par novo apareceria,
  // e os quatro testes acima ficariam verdes medindo quase nada.
  assert.ok(
    scan.filesAsserting >= 120,
    `só ${scan.filesAsserting} dos ${scan.filesPinning} arquivos que fixam migration escrevem um ` +
      'nome de função na forma reconhecida (piso 120). A extração de nomes provavelmente colapsou.',
  );
});

test('#1932: controle positivo sintético — a detecção funciona nos DOIS sentidos', () => {
  // O controle anterior era ancorado na instância provada (`568` / `admin_list_member_consents`).
  // Ela foi CONSERTADA no lote de PII/LGPD, e um controle que morre quando o defeito é corrigido
  // não é controle: mede dívida restante, não capacidade de detectar. Este roda sobre um fixture
  // sintético, então continua valendo mesmo que um dia não sobre dívida nenhuma no repo.
  const base = mkdtempSync(join(tmpdir(), 'g1932-'));
  try {
    const migs = join(base, 'migrations');
    const tests = join(base, 'tests');
    mkdirSync(migs);
    mkdirSync(tests);

    const corpo = (n) =>
      `CREATE OR REPLACE FUNCTION public.fixture_fn()\nRETURNS void LANGUAGE plpgsql AS $$\nBEGIN\n  -- v${n}\nEND;\n$$;\n`;
    writeFileSync(join(migs, '20260101000000_antiga.sql'), corpo(1));
    writeFileSync(join(migs, '20260202000000_nova.sql'), corpo(2));

    // (a) guard que fixa a ANTIGA e afirma a função: tem de ser detectado
    writeFileSync(
      join(tests, 'vencido.test.mjs'),
      `const M = 'supabase/migrations/20260101000000_antiga.sql';\n` +
        `assert.match(body, /CREATE OR REPLACE FUNCTION public\\.fixture_fn/);\n`,
    );
    let r = scanStalePins(base, new Set(), { testsDir: tests, migrationsDir: migs });
    assert.equal(r.pairs.length, 1, 'guard fixado na captura vencida tem de ser detectado');
    assert.equal(r.pairs[0].fn, 'fixture_fn');
    assert.equal(r.pairs[0].newestVersion, '20260202000000');

    // (b) o MESMO guard fixando a captura mais nova: não pode ser detectado (senão o guard acusa
    //     todo mundo e a linha de base vira ruído)
    writeFileSync(
      join(tests, 'vencido.test.mjs'),
      `const M = 'supabase/migrations/20260202000000_nova.sql';\n` +
        `assert.match(body, /CREATE OR REPLACE FUNCTION public\\.fixture_fn/);\n`,
    );
    r = scanStalePins(base, new Set(), { testsDir: tests, migrationsDir: migs });
    assert.equal(r.pairs.length, 0, 'guard que aponta para a captura vigente não é dívida');

    // (c) resolvido por `latestFunctionCapture`: também não é dívida, mesmo fixando a antiga
    writeFileSync(
      join(tests, 'vencido.test.mjs'),
      `const M = 'supabase/migrations/20260101000000_antiga.sql';\n` +
        `const cap = latestFunctionCapture(ROOT, 'fixture_fn');\n` +
        `assert.match(cap.block, /CREATE OR REPLACE FUNCTION public\\.fixture_fn/);\n`,
    );
    r = scanStalePins(base, new Set(), { testsDir: tests, migrationsDir: migs });
    assert.equal(r.pairs.length, 0, 'guard convertido para a captura vigente sai da dívida sozinho');
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test('#1932: latestFunctionCapture LANÇA em vez de devolver vazio', () => {
  // Vazio seria pior que erro: `doesNotMatch('', /vaza_hash/)` é verde para sempre, e é essa a
  // forma das afirmações de PII que passaram a depender deste helper.
  assert.throws(
    () => latestFunctionCapture(ROOT, 'funcao_que_nenhuma_migration_define'),
    /nenhuma migration define/,
  );
});
