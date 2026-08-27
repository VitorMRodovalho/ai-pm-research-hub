// tests/contracts/2024-hora-do-termo-nao-depende-de-onde-renderizou.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2024 — a hora impressa no termo não pode depender de ONDE o PDF foi renderizado.
 *
 * SINTOMA: `toLocaleString` sem `timeZone` usa o fuso do ambiente. Medido no mesmo termo, mesmo
 * dado no banco: produção (Worker, UTC) imprimia `19:43:04`; uma máquina em `America/New_York`
 * imprimia `15:43:04`. E nenhuma das duas dizia qual fuso era.
 *
 * Pior que a hora, a DATA vira: `2026-08-25T01:00:00Z` é 25/08 em UTC e 24/08 em São Paulo — o que
 * muda a datação "Goiânia, DD de mês de AAAA" do próprio instrumento. O termo é contrato com
 * cláusula de PI e assinatura fundamentada na Lei nº 14.063/2020 Art. 4º §I, com o fundamento
 * impresso no PDF: o horário é elemento do conjunto probatório.
 *
 * DECISÃO DO PM (27/08): o fuso é `America/Sao_Paulo`, o PDF declara o deslocamento, e documentos
 * já emitidos NÃO são re-renderizados por isto (ficam congelados em storage).
 *
 * ⚠️ O QUE ESTE ARQUIVO AFIRMA é o COMPORTAMENTO, não o texto: renderiza o mesmo termo em quatro
 * fusos, em processos separados, e exige saída IDÊNTICA. Um guard que só procurasse a string
 * `timeZone` ficaria verde com a opção presente e no lugar errado.
 *
 * Cross-ref: #2024, #2022 (foi o backfill dela que expôs isto), #2023 (se o PDF for por e-mail às
 * partes, a hora impressa vira o registro que fica com elas), #2025 (o hook de resolução que
 * permite importar `src/lib/**` fora do build).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';

const ROOT = process.cwd();
const PDF = resolve(ROOT, 'src/lib/certificates/pdf.ts');
const src = readFileSync(PDF, 'utf8');

// 2026-08-25T01:00:00Z é 25/08 em UTC e 24/08 em São Paulo. Escolhido de propósito: um instante
// no meio do dia passaria mesmo com o defeito presente.
const SIGNED_AT = '2026-08-25T01:00:00Z';
const FUSOS = ['UTC', 'America/Sao_Paulo', 'America/New_York', 'Asia/Tokyo'];

function renderIn(tz) {
  const dir = mkdtempSync(join(tmpdir(), 'cert-tz-'));
  const script = join(dir, 'r.mjs');
  writeFileSync(script, `
import { buildVolunteerAgreementHTML } from ${JSON.stringify(PDF)};
const html = buildVolunteerAgreementHTML({
  member_name: 'FULANO DE TAL',
  verification_code: 'TERM-GUARD-2024',
  signed_at: ${JSON.stringify(SIGNED_AT)},
  counter_signed_at: ${JSON.stringify(SIGNED_AT)},
  counter_signed_by_name: 'DIRETORIA DE VOLUNTARIADO',
  template_html_body: '<p>Clausula unica.</p>',
});
// CONTROLE: a MESMA data formatada SEM fuso fixado, no mesmo processo. Se este valor não variar
// entre os fusos, o arnês não está exercendo nada e o teste passaria por vacuidade.
const semFuso = new Date(${JSON.stringify(SIGNED_AT)}).toLocaleString('pt-BR');
process.stdout.write(JSON.stringify({ html, semFuso }));
`);
  const out = execFileSync(process.execPath, [
    '--experimental-strip-types', '--import', resolve(ROOT, 'scripts/lib/register-ts-resolve.mjs'), script,
  ], { env: { ...process.env, TZ: tz }, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return JSON.parse(out);
}

test('#2024: o termo renderizado é IDÊNTICO em qualquer fuso', () => {
  const saidas = FUSOS.map((tz) => ({ tz, ...renderIn(tz) }));

  // CONTROLE POSITIVO primeiro: o arnês precisa CONSEGUIR ver variação de fuso. Sem isto, quatro
  // saídas iguais podem significar "consertado" ou "os quatro processos rodaram no mesmo fuso".
  const controles = new Set(saidas.map((s) => s.semFuso));
  assert.ok(controles.size > 1,
    `o arnês não exerceu fuso nenhum: a data sem fuso fixado deu o mesmo valor nos ${FUSOS.length} processos ` +
    `(${[...controles].join(' | ')})`);

  const base = saidas[0];
  for (const s of saidas.slice(1)) {
    assert.equal(s.html, base.html,
      `o termo renderizado em ${s.tz} difere do renderizado em ${base.tz} — a hora impressa ainda ` +
      `depende de onde o PDF foi gerado`);
  }
});

test('#2024: o carimbo DECLARA o deslocamento, e usa o fuso do documento', () => {
  const { html } = renderIn('Asia/Tokyo');
  const datas = html.match(/Data: [^<]*/g) || [];
  assert.ok(datas.length >= 2, `esperava os dois carimbos de assinatura, achei ${datas.length}`);
  for (const d of datas) {
    assert.match(d, /GMT[+-]\d/,
      `carimbo sem deslocamento declarado (${d}) — fora do contexto de quem gerou, não é interpretável`);
  }
  // O instante é 25/08 em UTC. No fuso do documento é 24/08, e é isso que o PDF tem de dizer,
  // mesmo tendo sido renderizado em Tóquio.
  assert.ok(datas.every((d) => d.includes('24/08/2026')),
    `a data virou: ${datas.join(' | ')} — esperado 24/08/2026 no fuso do documento`);
});

test('#2024 estático: nenhuma data do documento é formatada sem fuso explícito', () => {
  // O guard olha o CORPO das funções de formatação, não o arquivo inteiro: o que não pode existir
  // é formatação de data do documento sem `timeZone` no mesmo objeto de opções.
  const semFuso = [];
  const re = /\.toLocale(?:Date|Time)?String\(\s*([^)]*)\)/gs;
  let m;
  while ((m = re.exec(src)) !== null) {
    if (!/timeZone/.test(m[1])) semFuso.push(m[0].replace(/\s+/g, ' ').slice(0, 90));
  }
  assert.deepEqual(semFuso, [],
    `formatação de data sem timeZone em pdf.ts:\n  ${semFuso.join('\n  ')}`);

  // E nenhuma data do documento pode sair de `new Date()` — isso é a hora da RENDERIZAÇÃO, que
  // muda sozinha a cada re-render. Era o defeito do rodapé.
  assert.doesNotMatch(src, /new Date\(\)\.toLocale/,
    'data de renderização impressa no documento: um re-render mudaria o texto sozinho');
});

test('#2024: o aviso de fuso saiu do cabeçalho do script de backfill', () => {
  const bf = readFileSync(resolve(ROOT, 'scripts/backfill-cert-pdfs.ts'), 'utf8');
  assert.doesNotMatch(bf, /FUSO HOR[ÁA]RIO/i,
    'o aviso era a mitigação enquanto o defeito existia; com o fuso fixado ele vira ruído');
});
