// tests/contracts/2024-script-de-backfill-de-certificado-executavel.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * `scripts/backfill-cert-pdfs.ts` tem de continuar EXECUTÁVEL.
 *
 * O DEFEITO (medido em 27/08/2026). O script é a ferramenta oficial para re-renderizar PDF de
 * certificado — tem `--force`, `--type`, `--cert`, `--dry-run`, `--guests`, tudo o que um
 * backfill precisa. E estava **inutilizável**: `node scripts/backfill-cert-pdfs.ts` morria em
 * `ERR_MODULE_NOT_FOUND` antes da primeira linha útil, porque ele importa
 * `src/lib/certificates/pdf.ts`, que importa `"../canonical"` sem extensão. O Node 22.18+/24 já
 * faz type-stripping, mas NÃO resolve import relativo sem extensão; o Vite (que o Astro usa)
 * resolve, e é por isso que a aplicação nunca reclamou.
 *
 * Quando 47 termos precisaram de backfill, o caminho praticável acabou sendo `net.http_post`
 * contra o endpoint interno — funcionou, mas é o contorno, não a ferramenta.
 *
 * A saída foi um hook de resolução do lado do SCRIPT (`scripts/lib/ts-resolve-hook.mjs`), e
 * **não** pôr `.ts` nos imports de `src/lib/**`: aquilo é código que vai para produção pelo
 * build do Astro, e mudar a forma dos imports lá para satisfazer uma ferramenta de manutenção
 * troca um problema de tooling por risco no artefato publicado.
 *
 * Este guard afirma as três metades: o hook existe, o atalho documentado existe, e — o que
 * realmente importa — a cadeia de import RESOLVE de verdade num processo Node.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const HOOK = resolve(ROOT, 'scripts/lib/ts-resolve-hook.mjs');
const REGISTER = resolve(ROOT, 'scripts/lib/register-ts-resolve.mjs');
const SCRIPT = resolve(ROOT, 'scripts/backfill-cert-pdfs.ts');
const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8'));

test('#2024: o hook de resolução e o registrador existem', () => {
  assert.ok(existsSync(HOOK), 'scripts/lib/ts-resolve-hook.mjs tem de existir');
  assert.ok(existsSync(REGISTER), 'scripts/lib/register-ts-resolve.mjs tem de existir');
  const hook = readFileSync(HOOK, 'utf8');
  // Só pode agir DEPOIS de o resolvedor padrão falhar, e só em specifier relativo — senão
  // sequestra resolução de pacote e mascara import genuinamente quebrado.
  assert.match(hook, /ERR_MODULE_NOT_FOUND/, 'o hook tem de só agir após falha do resolvedor padrão');
  assert.match(hook, /startsWith\('\.\/'\)/, 'o hook tem de se limitar a specifier relativo');
});

test('#2024: existe atalho npm, e ele carrega o hook', () => {
  const s = pkg.scripts?.['certs:backfill'];
  assert.ok(s, 'package.json precisa do script `certs:backfill`');
  assert.match(s, /--import \.\/scripts\/lib\/register-ts-resolve\.mjs/,
    'o atalho tem de registrar o hook — sem ele o script morre em ERR_MODULE_NOT_FOUND');
  assert.match(s, /scripts\/backfill-cert-pdfs\.ts/);
});

test('#2024: o script documenta a invocação correta e a armadilha de fuso', () => {
  const src = readFileSync(SCRIPT, 'utf8');
  assert.match(src, /npm run certs:backfill/, 'o cabeçalho tem de ensinar o atalho que funciona');
  // A armadilha que o conserto EXPÔS: com o script rodando, um backfill local reescreveria a
  // hora impressa em documento assinado, porque o template não fixa timeZone.
  assert.match(src, /FUSO HORÁRIO/, 'o cabeçalho tem de avisar sobre o fuso antes de alguém rodar em produção');
});

test('#2024: a cadeia de import RESOLVE de verdade (não é só texto no README)', () => {
  // O teste que pega a regressão real. Um `--help`/`--dry-run` completo exigiria credenciais e
  // Chromium; aqui basta provar que o módulo que quebrava resolve e exporta o que o script usa.
  const alvo = 'file://' + resolve(ROOT, 'src/lib/certificates/pdf.ts');
  const codigo = `
    const m = await import(${JSON.stringify(alvo)});
    if (typeof m.buildCertificateHTML !== 'function') throw new Error('buildCertificateHTML ausente');
    if (typeof m.hydrateCertData !== 'function') throw new Error('hydrateCertData ausente');
    console.log('RESOLVEU');
  `;
  const out = execFileSync(
    process.execPath,
    ['--import', './scripts/lib/register-ts-resolve.mjs', '--input-type=module', '-e', codigo],
    { cwd: ROOT, encoding: 'utf8', timeout: 60_000, stdio: ['ignore', 'pipe', 'pipe'] },
  );
  assert.match(out, /RESOLVEU/);
});

test('#2024: sem o hook a cadeia FALHA — prova de que o guard não é decorativo', () => {
  // Controle positivo. Se um dia o Node passar a resolver extensionless, este teste cai e o
  // hook vira dispensável — o que é informação, não defeito. Melhor descobrir por vermelho.
  const alvo = 'file://' + resolve(ROOT, 'src/lib/certificates/pdf.ts');
  const codigo = `await import(${JSON.stringify(alvo)}); console.log('RESOLVEU_SEM_HOOK');`;
  let falhou = false;
  try {
    execFileSync(process.execPath, ['--input-type=module', '-e', codigo],
      { cwd: ROOT, encoding: 'utf8', timeout: 60_000, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (err) {
    falhou = true;
    assert.match(String(err.stderr || ''), /ERR_MODULE_NOT_FOUND|Cannot find module/,
      'a falha sem o hook tem de ser de RESOLUÇÃO — se for outra, o cenário mudou');
  }
  assert.ok(falhou,
    'sem o hook a importação deveria falhar; se passou, o Node mudou e o hook virou dispensável — reavalie');
});
