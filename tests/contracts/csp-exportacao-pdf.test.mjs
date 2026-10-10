/**
 * Exportação de PDF dos documentos de governança: a CSP permite o que o @react-pdf/renderer usa.
 *
 * Medido em 09/10/2026 no console do navegador, em /admin/governance/documents/<id>/export-pdf:
 * o motor de layout (WebAssembly) é carregado por fetch de uma URL `data:`, bloqueada pelo
 * connect-src, e o PNG do logo é decodificado num worker criado de `blob:`, bloqueado porque não
 * havia worker-src e a CSP caía no script-src. A exportação falhava.
 *
 * Afirma, nas DUAS fontes da CSP (src/lib/securityHeaders.ts, que o SSR envia, e public/_headers,
 * que os assets estáticos enviam), a diretiva junto com o valor: connect-src com `data:` e
 * worker-src com `blob:`. E que `data:` não entrou em script-src nem em worker-src.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Lido como texto (o balde contracts roda sem --experimental-strip-types): junta as strings do CSP.
const SRC = readFileSync(resolve(process.cwd(), 'src/lib/securityHeaders.ts'), 'utf8');
const bloco = SRC.match(/export const CSP =([\s\S]*?);\n/)?.[1] ?? '';
const CSP = [...bloco.matchAll(/"([^"]*)"/g)].map((m) => m[1]).join('');
const HEADERS = readFileSync(resolve(process.cwd(), 'public/_headers'), 'utf8');
const cspHeaders = HEADERS.match(/Content-Security-Policy:\s*([^\n]+)/)?.[1] ?? '';

function diretiva(csp, nome) {
  return csp.split(';').map((s) => s.trim()).find((s) => s.startsWith(nome + ' ')) ?? '';
}

for (const [fonte, csp] of [['securityHeaders.ts', CSP], ['public/_headers', cspHeaders]]) {
  test(`exportação de PDF: ${fonte} libera data: no connect-src e blob: no worker-src`, () => {
    assert.ok(csp.length > 0, `CSP vazia em ${fonte}`);
    assert.match(diretiva(csp, 'connect-src'), /(^|\s)data:(\s|$)/, 'connect-src sem data: (WebAssembly do react-pdf)');
    assert.match(diretiva(csp, 'worker-src'), /^worker-src 'self' blob:$/, 'worker-src ausente ou sem blob: (decodificação do PNG)');
    assert.doesNotMatch(diretiva(csp, 'script-src'), /(^|\s)data:(\s|$)/, 'data: não pode entrar em script-src');
  });
}
