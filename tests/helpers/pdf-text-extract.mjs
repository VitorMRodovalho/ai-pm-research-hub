/**
 * #2658 — extrator de texto MÍNIMO para os PDFs que o @react-pdf/renderer gera, sem dependência
 * nova (só `node:zlib`). Existe para o teste de fidelidade rodar no CI, onde não há pdftotext.
 *
 * Cobre exatamente o que o pdfkit do react-pdf escreve, não PDF arbitrário:
 *   - objetos `N 0 obj ... endobj` sem object streams, streams com /FlateDecode;
 *   - fonte Type0 (TrueType embutida) com /ToUnicode (bfchar e bfrange, inclusive a forma em array);
 *   - fonte padrão (Helvetica/Courier, sem ToUnicode): bytes lidos como WinAnsi. É o caminho que a
 *     mutação "volta para Helvetica" exercita, e por isso precisa existir: sem ele um PDF com fonte
 *     padrão sairia vazio e o teste reprovaria por motivo errado;
 *   - operadores Tf, Tj, TJ (strings hex e literais).
 *
 * Cada operador de exibição (um trecho de linha) vira uma linha da saída. Quem afirma sobre o texto
 * deve normalizar espaços, porque a quebra de linha do layout cai entre quaisquer duas palavras.
 */
import { inflateSync } from 'node:zlib';

// WinAnsi 0x80–0x9F (o resto coincide com Latin-1).
const WIN_ANSI_HIGH = {
  0x80: '€', 0x82: '‚', 0x83: 'ƒ', 0x84: '„', 0x85: '…', 0x86: '†',
  0x87: '‡', 0x88: 'ˆ', 0x89: '‰', 0x8a: 'Š', 0x8b: '‹', 0x8c: 'Œ',
  0x8e: 'Ž', 0x91: '‘', 0x92: '’', 0x93: '“', 0x94: '”', 0x95: '•',
  0x96: '–', 0x97: '—', 0x98: '˜', 0x99: '™', 0x9a: 'š', 0x9b: '›',
  0x9c: 'œ', 0x9e: 'ž', 0x9f: 'Ÿ',
};
const winAnsi = (b) => WIN_ANSI_HIGH[b] ?? String.fromCharCode(b);

function hexToUnicode(rawHex) {
  // Ligaduras chegam como vários códigos num só item, separados por espaço: <0066 006c> = "fl".
  const hex = rawHex.replace(/\s+/g, '');
  let out = '';
  for (let i = 0; i + 4 <= hex.length; i += 4) out += String.fromCharCode(parseInt(hex.slice(i, i + 4), 16));
  return out;
}

function parseObjects(pdf) {
  const s = pdf.toString('latin1');
  const objects = new Map();
  const re = /(\d+) 0 obj\b/g;
  let m;
  while ((m = re.exec(s)) !== null) {
    const start = m.index + m[0].length;
    const end = s.indexOf('endobj', start);
    if (end === -1) break;
    const body = s.slice(start, end);
    const streamAt = body.indexOf('stream');
    let dict = body;
    let stream = null;
    if (streamAt !== -1 && /^stream\r?\n/.test(body.slice(streamAt))) {
      dict = body.slice(0, streamAt);
      let dataStart = streamAt + 'stream'.length;
      if (body[dataStart] === '\r') dataStart += 1;
      if (body[dataStart] === '\n') dataStart += 1;
      const dataEnd = body.lastIndexOf('endstream');
      let raw = Buffer.from(body.slice(dataStart, dataEnd), 'latin1');
      if (/\/FlateDecode/.test(dict)) {
        try { raw = inflateSync(raw); } catch { raw = inflateSync(raw.subarray(0, raw.length - 1)); }
      }
      stream = raw;
    }
    objects.set(Number(m[1]), { dict, stream });
    re.lastIndex = end;
  }
  return objects;
}

function parseToUnicode(cmap) {
  const map = new Map();
  const text = cmap.toString('latin1');
  for (const block of text.matchAll(/beginbfchar([\s\S]*?)endbfchar/g)) {
    for (const p of block[1].matchAll(/<([0-9a-fA-F]+)>\s*<([0-9a-fA-F\s]+)>/g)) {
      map.set(parseInt(p[1], 16), hexToUnicode(p[2]));
    }
  }
  for (const block of text.matchAll(/beginbfrange([\s\S]*?)endbfrange/g)) {
    const re = /<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*(\[[^\]]*\]|<[0-9a-fA-F]+>)/g;
    let p;
    while ((p = re.exec(block[1])) !== null) {
      const lo = parseInt(p[1], 16);
      const hi = parseInt(p[2], 16);
      if (p[3].startsWith('[')) {
        const items = [...p[3].matchAll(/<([0-9a-fA-F\s]+)>/g)].map((x) => hexToUnicode(x[1]));
        for (let c = lo; c <= hi && c - lo < items.length; c += 1) map.set(c, items[c - lo]);
      } else {
        const base = p[3].slice(1, -1);
        const first = parseInt(base, 16);
        for (let c = lo; c <= hi; c += 1) map.set(c, String.fromCharCode(first + (c - lo)));
      }
    }
  }
  return map;
}

/** Fontes do documento: nome de recurso (/F1…) → como decodificar e o que é. */
export function pdfFonts(pdf) {
  const objects = parseObjects(pdf);
  const byObj = new Map();
  for (const [num, { dict }] of objects) {
    if (!/\/Type\s*\/Font\b/.test(dict)) continue;
    const baseFont = (dict.match(/\/BaseFont\s*\/([^\s/<>\[\]]+)/) || [])[1] || '';
    const subtype = (dict.match(/\/Subtype\s*\/(\w+)/) || [])[1] || '';
    const tu = dict.match(/\/ToUnicode\s+(\d+)\s+0\s+R/);
    const toUnicode = tu && objects.get(Number(tu[1]))?.stream
      ? parseToUnicode(objects.get(Number(tu[1])).stream)
      : null;
    // Larguras por CID (fonte Type0): /W da descendente, para medir onde cada trecho TERMINA.
    const widths = new Map();
    const desc = dict.match(/\/DescendantFonts\s*\[\s*(\d+)\s+0\s+R/);
    const descDict = desc ? objects.get(Number(desc[1]))?.dict || '' : '';
    const w = descDict.match(/\/W\s*\[([\s\S]*)\]/);
    if (w) {
      const re = /(\d+)\s*\[([^\]]*)\]|(\d+)\s+(\d+)\s+([\d.]+)/g;
      let x;
      while ((x = re.exec(w[1])) !== null) {
        if (x[1] !== undefined) {
          x[2].trim().split(/\s+/).forEach((v, k) => widths.set(Number(x[1]) + k, Number(v)));
        } else {
          for (let c = Number(x[3]); c <= Number(x[4]); c += 1) widths.set(c, Number(x[5]));
        }
      }
    }
    const dw = Number((descDict.match(/\/DW\s+([\d.]+)/) || [])[1] || 1000);
    byObj.set(num, { baseFont, subtype, toUnicode, widths, dw });
  }
  const byName = new Map();
  for (const { dict } of objects.values()) {
    for (const fontDict of dict.matchAll(/\/Font\s*<<([\s\S]*?)>>/g)) {
      for (const ref of fontDict[1].matchAll(/\/([^\s/]+)\s+(\d+)\s+0\s+R/g)) {
        const f = byObj.get(Number(ref[2]));
        if (f) byName.set(ref[1], f);
      }
    }
  }
  const embedded = [...objects.values()].some(({ dict }) => /\/FontFile2\s+\d+\s+0\s+R/.test(dict));
  return { byName, all: [...byObj.values()], embedded };
}

function decodeString(bytes, font) {
  if (font?.subtype === 'Type0') {
    let out = '';
    for (let i = 0; i + 1 < bytes.length; i += 2) {
      const code = (bytes[i] << 8) | bytes[i + 1];
      out += font.toUnicode?.get(code) ?? '�';
    }
    return out;
  }
  return [...bytes].map(winAnsi).join('');
}

function literalBytes(lit) {
  const out = [];
  for (let i = 0; i < lit.length; i += 1) {
    const ch = lit[i];
    if (ch !== '\\') { out.push(ch.charCodeAt(0) & 0xff); continue; }
    const n = lit[++i];
    const esc = { n: 10, r: 13, t: 9, b: 8, f: 12, '(': 40, ')': 41, '\\': 92 }[n];
    if (esc !== undefined) out.push(esc);
    else if (/[0-7]/.test(n)) {
      let oct = n;
      while (oct.length < 3 && /[0-7]/.test(lit[i + 1])) oct += lit[++i];
      out.push(parseInt(oct, 8));
    }
  }
  return out;
}

// Tokenizador de content stream: números, nomes, strings hex/literais, arrays e operadores.
function* tokenize(content) {
  const n = content.length;
  let i = 0;
  while (i < n) {
    const c = content[i];
    if (/\s/.test(c)) { i += 1; continue; }
    if (c === '%') { while (i < n && content[i] !== '\n') i += 1; continue; }
    if (c === '[' || c === ']') { yield { t: c }; i += 1; continue; }
    if (c === '<' && content[i + 1] === '<') { yield { t: 'op', v: '<<' }; i += 2; continue; }
    if (c === '>' && content[i + 1] === '>') { yield { t: 'op', v: '>>' }; i += 2; continue; }
    if (c === '<') {
      const end = content.indexOf('>', i);
      yield { t: 'str', v: Buffer.from(content.slice(i + 1, end).replace(/\s+/g, ''), 'hex') };
      i = end + 1; continue;
    }
    if (c === '(') {
      let depth = 1; let j = i + 1; let lit = '';
      while (j < n && depth > 0) {
        const ch = content[j];
        if (ch === '\\') { lit += ch + content[j + 1]; j += 2; continue; }
        if (ch === '(') depth += 1;
        if (ch === ')' && --depth === 0) break;
        lit += ch; j += 1;
      }
      yield { t: 'str', v: Buffer.from(literalBytes(lit)) };
      i = j + 1; continue;
    }
    const m = /^[^\s\[\]()<>/%]+|^\/[^\s\[\]()<>/%]*/.exec(content.slice(i, i + 256));
    const word = m[0];
    i += word.length;
    if (word[0] === '/') yield { t: 'name', v: word.slice(1) };
    else if (/^[+-]?(\d+\.?\d*|\.\d+)$/.test(word)) yield { t: 'num', v: Number(word) };
    else yield { t: 'op', v: word };
  }
}

const mul = (m, n) => [
  m[0] * n[0] + m[1] * n[2], m[0] * n[1] + m[1] * n[3],
  m[2] * n[0] + m[3] * n[2], m[2] * n[1] + m[3] * n[3],
  m[4] * n[0] + m[5] * n[2] + n[4], m[4] * n[1] + m[5] * n[3] + n[5],
];

/**
 * Texto do PDF, um trecho exibido por linha, na ordem dos content streams.
 *
 * Por padrão DESCARTA o trecho cuja origem cai FORA da página (MediaBox). É o que um leitor de PDF
 * faz ao mostrar a página, e é exatamente o modo de falha do #2658: uma linha de tabela atômica
 * mais alta que o espaço restante é desenhada além da borda inferior, e o texto continua no
 * content stream sem aparecer em página nenhuma. Sem esse corte, o extrator certificaria como
 * presente o conteúdo que o leitor perdeu. `{ clip: false }` devolve tudo, para diagnóstico.
 */
export function extractPdfText(pdf, { clip = true } = {}) {
  return extractPdfRuns(pdf)
    .filter((r) => !clip || r.inside)
    .map((r) => r.text)
    .join('\n');
}

/**
 * Cada trecho exibido, com onde começa (x0, y) e onde TERMINA (x1) no espaço da página, e se a
 * origem cai dentro da página. x1 só é exato para fonte Type0 (larguras do /W); para fonte padrão
 * fica igual a x0, porque o teste só afirma largura sobre a fonte embutida.
 */
export function extractPdfRuns(pdf) {
  const { byName } = pdfFonts(pdf);
  const objects = parseObjects(pdf);
  let box = [0, 0, 595.28, 841.89];
  for (const { dict } of objects.values()) {
    const mb = /\/Type\s*\/Page\b[\s\S]*?\/MediaBox\s*\[([^\]]+)\]/.exec(dict)
      || (/\/Type\s*\/Page\b/.test(dict) && /\/MediaBox\s*\[([^\]]+)\]/.exec(dict));
    if (mb) { box = mb[1].trim().split(/\s+/).map(Number); break; }
  }
  const inside = (x, y) => x >= box[0] - 1 && x <= box[2] + 1 && y >= box[1] - 1 && y <= box[3] + 1;
  const runs = [];
  for (const { dict, stream } of objects.values()) {
    if (!stream || /\/FontFile2|\/Subtype\s*\/Image|\/Length1/.test(dict)) continue;
    const content = stream.toString('latin1');
    if (!/\bBT\b/.test(content)) continue;
    let ctm = [1, 0, 0, 1, 0, 0];
    const stack = [];
    let tm = [1, 0, 0, 1, 0, 0];
    let font = null;
    let fontSize = 0;
    let operands = [];
    let array = null;
    for (const tok of tokenize(content)) {
      if (tok.t === '[') { array = []; continue; }
      if (tok.t === ']') { operands.push({ t: 'arr', v: array }); array = null; continue; }
      if (array) { array.push(tok); continue; }
      if (tok.t !== 'op') { operands.push(tok); continue; }
      const nums = operands.filter((o) => o.t === 'num').map((o) => o.v);
      switch (tok.v) {
        case 'q': stack.push(ctm); break;
        case 'Q': ctm = stack.pop() || [1, 0, 0, 1, 0, 0]; break;
        case 'cm': if (nums.length === 6) ctm = mul(nums, ctm); break;
        case 'BT': tm = [1, 0, 0, 1, 0, 0]; break;
        case 'Tm': if (nums.length === 6) tm = nums; break;
        case 'Td': case 'TD': if (nums.length === 2) tm = mul([1, 0, 0, 1, nums[0], nums[1]], tm); break;
        case 'Tf': {
          const name = operands.find((o) => o.t === 'name');
          font = name ? byName.get(name.v) || null : null;
          fontSize = nums[nums.length - 1] || 0;
          break;
        }
        case 'Tj': case 'TJ': case "'": case '"': {
          const strs = [];
          // [caractere, avanço] por glifo e por ajuste do TJ, para descontar o espaço final:
          // o espaço que fecha a linha é desenhado além da margem e não é texto visível.
          const steps = [];
          const add = (bytes) => {
            strs.push(bytes);
            if (font?.subtype !== 'Type0') return;
            for (let k = 0; k + 1 < bytes.length; k += 2) {
              const cid = (bytes[k] << 8) | bytes[k + 1];
              steps.push([font.toUnicode?.get(cid) ?? '', font.widths.get(cid) ?? font.dw]);
            }
          };
          for (const o of operands) {
            if (o.t === 'str') add(o.v);
            if (o.t === 'arr') for (const a of o.v) { if (a.t === 'str') add(a.v); if (a.t === 'num') steps.push(['', -a.v]); }
          }
          while (steps.length && /^\s*$/.test(steps[steps.length - 1][0])) steps.pop();
          const advance = steps.reduce((acc, [, w]) => acc + w, 0); // 1/1000 do corpo
          const start = mul(tm, ctm);
          const end = font?.subtype === 'Type0' ? mul([1, 0, 0, 1, (advance / 1000) * fontSize, 0], start) : start;
          runs.push({
            text: strs.map((b) => decodeString([...b], font)).join(''),
            x0: start[4], x1: end[4], y: start[5],
            inside: inside(start[4], start[5]),
            box,
          });
          break;
        }
        default: break;
      }
      operands = [];
    }
  }
  return runs;
}
