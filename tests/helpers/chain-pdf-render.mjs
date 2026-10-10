/**
 * #2658 — renderiza o componente REAL do PDF da cadeia de ratificação (ChainPDFDocument.tsx) em
 * Node, com uma fixture 100% sintética, para o teste de fidelidade e para inspeção manual.
 *
 * Como o navegador faz: o componente resolve logo e fontes contra `window.location` e o react-pdf
 * as busca por fetch. Aqui um servidor HTTP local serve `public/` e `window.location` aponta para
 * ele, então o caminho exercitado é o mesmo da produção (URL absoluta + fetch), não um atalho por
 * caminho de disco.
 *
 * O .tsx é empacotado com esbuild (devDependency direta) para um .mjs dentro de node_modules/.cache,
 * de onde os imports de pacote (`@react-pdf/renderer`, `react`) resolvem normalmente.
 */
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { resolve, dirname, extname, normalize } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const PUBLIC = resolve(ROOT, 'public');
export const COMPONENT = resolve(ROOT, 'src/components/governance/ChainPDFDocument.tsx');

const TYPES = { '.ttf': 'font/ttf', '.png': 'image/png' };

function serveDir(dir) {
  return new Promise((ok) => {
    const server = createServer(async (req, res) => {
      const rel = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^([/\\])+/, '');
      const file = resolve(dir, rel);
      if (!file.startsWith(dir)) { res.writeHead(403).end(); return; }
      try {
        const body = await readFile(file);
        res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' }).end(body);
      } catch {
        res.writeHead(404).end();
      }
    });
    server.listen(0, '127.0.0.1', () => ok(server));
  });
}

// ---------------------------------------------------------------------------
// Fixture sintética. Nenhum texto vem de documento real.
// ---------------------------------------------------------------------------
export const SYMBOLS = ['≥', '→', '≠', '≈', '①', '②', '③', '✓'];
export const LONG_URL =
  'https://exemplo.invalid/repositorio/documentos/anexos/versao-sintetica/secao-quatro/item?formato=pdf&origem=teste&id=0123456789abcdef';
export const SIGNED_AT_UTC = '2026-03-13T16:15:00Z'; // 13:15 em Brasília (UTC-3)
export const EXPECTED_SIGNED = '13/03/2026, 13:15 (horário de Brasília)';

/** Célula longa: N frases, cada uma com um rótulo único, e a palavra-sentinela no FIM. */
export function longCell(tag, sentences) {
  const parts = [];
  for (let i = 1; i <= sentences; i += 1) {
    parts.push(`Frase ${tag}s${String(i).padStart(2, '0')} descreve um criterio sintetico com redacao propositalmente longa para ocupar varias linhas da celula.`);
  }
  parts.push(`fim${tag}sentinela`);
  return parts.join(' ');
}

// Linhas da tabela: [rótulo, frases]. A r3c2 sozinha é mais alta que uma página A4.
export const CELLS = [
  ['r1c1', 6], ['r1c2', 14], ['r1c3', 4],
  ['r2c1', 3], ['r2c2', 22], ['r2c3', 9],
  ['r3c1', 2], ['r3c2', 60], ['r3c3', 5],
  ['r4c1', 8], ['r4c2', 12], ['r4c3', 3],
];

export function fixtureData() {
  const rows = [0, 1, 2, 3].map((r) => {
    const cells = CELLS.slice(r * 3, r * 3 + 3).map(([tag, n]) => `<td>${longCell(tag, n)}</td>`);
    if (r === 1) cells[2] = `<td>Link do anexo: ${LONG_URL} ${longCell('r2c3', 9)}</td>`;
    return `<tr>${cells.join('')}</tr>`;
  });
  const html = [
    '<h2>1. Secao sintetica de simbolos</h2>',
    '<p>Quorum ≥75% dos votos; fluxo A → B; valor ≠ zero; custo ≈ 10; etapas ① ② ③; conferido ✓ e ✅.</p>',
    `<p>Endereco longo no corpo do texto: ${LONG_URL} fimcorposentinela</p>`,
    '<h2>2. Tabela sintetica longa</h2>',
    '<table><thead><tr><th>Coluna A</th><th>Coluna B</th><th>Coluna C</th></tr></thead>',
    `<tbody>${rows.join('')}</tbody></table>`,
    '<p>Paragrafo depois da tabela fimtabelasentinela.</p>',
  ].join('');
  const signer = (i) => ({
    signoff_id: `00000000-0000-4000-8000-00000000000${i}`,
    signer_id: `00000000-0000-4000-8000-00000000001${i}`,
    signer_name: `Signatario Sintetico ${i}`,
    signer_chapter: 'Capitulo Exemplo',
    signer_role: 'papel_exemplo',
    signoff_type: 'approval',
    signed_at: SIGNED_AT_UTC,
    signature_hash_short: 'abcdef012345',
    sections_verified_count: 2,
    notification_read_at: SIGNED_AT_UTC,
    notification_read_evidence: true,
    ue_consent_recorded: false,
  });
  return {
    chain_id: '11111111-2222-4333-8444-555555555555',
    chain_status: 'active',
    chain_opened_at: '2026-03-01T12:00:00Z',
    chain_approved_at: SIGNED_AT_UTC,
    chain_closed_at: null,
    document: { id: 'd0c00000-0000-4000-8000-000000000000', title: 'Documento Sintetico de Teste', doc_type: 'policy', status: 'active' },
    version: {
      id: 'e0e00000-0000-4000-8000-000000000000', number: 1, label: 'v1.0', content_html: html,
      locked_at: '2026-03-01T12:00:00Z', published_at: '2026-03-01T12:00:00Z',
    },
    submitter: { id: 's', name: 'Submissor Sintetico', email: 'x@exemplo.invalid', chapter: 'Capitulo Exemplo', role: 'papel_exemplo' },
    gates: [{ kind: 'curator', order: 1, threshold: 1, label: 'Gate sintetico', signers: [signer(1), signer(2)] }],
    generated_at: SIGNED_AT_UTC,
  };
}

/**
 * Renderiza a fixture e devolve { official, draft } como Buffers.
 * `componentPath` permite renderizar uma cópia MUTADA do componente (teste de mutação).
 */
export async function renderChainPdf({ componentPath = COMPONENT } = {}) {
  const esbuild = await import('esbuild');
  const outDir = resolve(ROOT, 'node_modules/.cache/2658-chain-pdf');
  await mkdir(outDir, { recursive: true });
  const outfile = resolve(outDir, `ChainPDFDocument-${process.pid}-${Date.now()}.mjs`);
  await esbuild.build({
    entryPoints: [componentPath],
    bundle: true,
    format: 'esm',
    platform: 'node',
    jsx: 'automatic',
    external: ['@react-pdf/renderer', 'react', 'react/jsx-runtime'],
    outfile,
    logLevel: 'silent',
  });
  const server = await serveDir(PUBLIC);
  const hadWindow = 'window' in globalThis;
  const prevWindow = globalThis.window;
  try {
    globalThis.window = { location: { href: `http://127.0.0.1:${server.address().port}/` } };
    const mod = await import(pathToFileURL(outfile).href);
    const { renderToBuffer } = await import('@react-pdf/renderer');
    const React = (await import('react')).default;
    const data = fixtureData();
    const official = await renderToBuffer(React.createElement(mod.default, { data, mode: 'official' }));
    const draft = await renderToBuffer(React.createElement(mod.default, { data, mode: 'draft' }));
    return { official, draft };
  } finally {
    if (hadWindow) globalThis.window = prevWindow; else delete globalThis.window;
    server.close();
  }
}
