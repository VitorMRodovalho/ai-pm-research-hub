#!/usr/bin/env node
/**
 * #1966 — ratchet da linha de base do CodeQL.
 *
 * `CodeQL` roda no repo, reporta e nao segura nada. Medido em 24/08/2026: 101 alertas
 * abertos, 55 ALTOS, o mais antigo de 08/03 — quase seis meses. A #1958 foi o primeiro
 * fechamento por conserto deliberado nesse canal, e ela so aconteceu porque alguem foi
 * olhar. Um check que avisa e nao segura vira ruido, e ninguem le ruido.
 *
 * Tornar o check required de uma vez travaria TODA PR (101 alertas abertos). Entao:
 * congela o passado numa lista e barra o NOVO. A lista so encolhe.
 *
 * CHAVE = `rule.id` + caminho. Nao o numero do alerta (muda quando fecha e reabre) e nao
 * a linha (muda a cada edicao acima dela). O que nao pode crescer e quantos achados
 * daquela regra existem naquele arquivo.
 *
 * Uso:
 *   node scripts/codeql-baseline-check.mjs            # compara e sai != 0 se piorou
 *   node scripts/codeql-baseline-check.mjs --write    # regrava a base (so para ENCOLHER)
 *
 * Precisa de GITHUB_TOKEN com `security-events: read` (ou `gh auth` local).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const BASE = resolve(ROOT, 'docs/audit/CODEQL_ALERT_BASELINE_1966.tsv');
const REPO = process.env.GITHUB_REPOSITORY || 'VitorMRodovalho/ai-pm-research-hub';
const TOKEN = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;

const REF = process.argv.find((a) => a.startsWith('--ref='))?.slice(6);
const qRef = REF ? `&ref=${encodeURIComponent(REF)}` : '';

async function api(path) {
  const res = await fetch(`https://api.github.com/repos/${REPO}/${path}`, {
    headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
  });
  if (!res.ok) throw new Error(`${path} -> HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return res.json();
}

/**
 * Zero alerta num ref e AMBIGUO: pode ser "limpo" ou "nunca analisado". Sem esta
 * pre-condicao o guard passaria por vacuidade em toda PR que o CodeQL ainda nao tocou —
 * que e exatamente o modo de falha que este arquivo existe para eliminar.
 */
async function exigeAnalise() {
  if (!REF) return;
  const a = await api(`code-scanning/analyses?ref=${encodeURIComponent(REF)}&per_page=1`);
  if (!Array.isArray(a) || a.length === 0) {
    console.error(`::error::nenhuma analise do CodeQL para \`${REF}\`. Zero alertas aqui nao significa limpo, significa NAO MEDIDO — e este guard nao passa sem medir.`);
    process.exit(1);
  }
}

/** Le TODAS as paginas. Sem isto a API devolve 23 de 101 e nada sinaliza truncamento. */
async function alertasAbertos() {
  const out = [];
  for (let page = 1; page <= 50; page++) {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/code-scanning/alerts?state=open&per_page=100&page=${page}${qRef}`,
      { headers: { Authorization: `Bearer ${TOKEN}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' } },
    );
    if (!res.ok) throw new Error(`code-scanning/alerts -> HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const lote = await res.json();
    out.push(...lote);
    if (lote.length < 100) return out;
  }
  throw new Error('mais de 50 paginas de alertas — recuse em vez de truncar em silencio');
}

function agrega(alertas) {
  const m = new Map();
  for (const a of alertas) {
    const k = `${a.rule.id}\t${a.most_recent_instance.location.path}`;
    const sev = a.rule.security_severity_level || a.rule.severity || '?';
    const e = m.get(k) ?? { n: 0, sev };
    e.n += 1;
    if (sev === 'high') e.sev = 'high';
    m.set(k, e);
  }
  return m;
}

function leBase() {
  const txt = readFileSync(BASE, 'utf8');
  const m = new Map();
  for (const l of txt.split('\n')) {
    if (!l || l.startsWith('#')) continue;
    const [n, sev, rule, path] = l.split('\t');
    m.set(`${rule}\t${path}`, { n: Number(n), sev });
  }
  const decl = Number(txt.match(/^# TOTAL_ABERTOS=(\d+)$/m)?.[1]);
  return { base: m, declarado: decl };
}

const { base, declarado } = leBase();
const somaBase = [...base.values()].reduce((s, v) => s + v.n, 0);
if (somaBase !== declarado) {
  console.error(`::error::a base declara TOTAL_ABERTOS=${declarado} mas as linhas somam ${somaBase}. Cabecalho e conteudo divergiram.`);
  process.exit(1);
}

if (!TOKEN) {
  console.error('::error::sem GITHUB_TOKEN com `security-events: read` — este guard NAO pode passar sem medir. Skip aqui seria verde por vacuidade.');
  process.exit(1);
}

await exigeAnalise();
const vivo = agrega(await alertasAbertos());
const somaVivo = [...vivo.values()].reduce((s, v) => s + v.n, 0);

const novas = [];
const cresceram = [];
for (const [k, v] of vivo) {
  const b = base.get(k);
  if (!b) novas.push({ k, ...v });
  else if (v.n > b.n) cresceram.push({ k, de: b.n, para: v.n, sev: v.sev });
}
const resolvidas = [...base.keys()].filter((k) => !vivo.has(k));
const encolheram = [...vivo].filter(([k, v]) => base.has(k) && v.n < base.get(k).n);

const fmt = (k) => { const [r, p] = k.split('\t'); return `${p} — ${r}`; };

console.log(`base: ${somaBase} alertas em ${base.size} chaves | vivo: ${somaVivo} em ${vivo.size} chaves`);
if (resolvidas.length || encolheram.length) {
  console.log(`\n✅ progresso — remova estas linhas da base (\`--write\` faz isso):`);
  for (const k of resolvidas) console.log(`   RESOLVIDA  ${fmt(k)}`);
  for (const [k, v] of encolheram) console.log(`   ENCOLHEU   ${fmt(k)}: ${base.get(k).n} -> ${v.n}`);
}

if (process.argv.includes('--write')) {
  if (novas.length || cresceram.length) {
    console.error('::error::--write so serve para ENCOLHER a base. Ha achado novo; conserte-o em vez de congelar.');
    process.exit(1);
  }
  const linhas = [...vivo].sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${v.n}\t${v.sev}\t${k}`);
  const alto = [...vivo.values()].filter((v) => v.sev === 'high').reduce((s, v) => s + v.n, 0);
  const cab = readFileSync(BASE, 'utf8').split('\n').filter((l) => l.startsWith('#'))
    .map((l) => l.replace(/^# TOTAL_ABERTOS=\d+$/, `# TOTAL_ABERTOS=${somaVivo}`)
                 .replace(/^# TOTAL_ALTOS=\d+$/, `# TOTAL_ALTOS=${alto}`)
                 .replace(/^# TOTAL_CHAVES=\d+$/, `# TOTAL_CHAVES=${vivo.size}`)).join('\n');
  writeFileSync(BASE, `${cab}\n${linhas.join('\n')}\n`);
  console.log(`\nbase regravada: ${somaVivo} alertas, ${alto} altos, ${vivo.size} chaves.`);
  process.exit(0);
}

if (novas.length || cresceram.length) {
  console.error(`\n::error::achado NOVO do CodeQL fora da linha de base (#1966). Conserte, nao congele.`);
  for (const n of novas) console.error(`   NOVA  [${n.sev}] ${fmt(n.k)}  (${n.n})`);
  for (const c of cresceram) console.error(`   CRESCEU [${c.sev}] ${fmt(c.k)}: ${c.de} -> ${c.para}`);
  console.error(`\nA base congela o passado (#1966) para que o NOVO possa reprovar sem travar a fila.`);
  console.error(`Se o achado for falso positivo, dismiss no GitHub com justificativa — nao acrescente aqui.`);
  process.exit(1);
}

console.log('\nnenhum achado novo fora da base.');
if (resolvidas.length || encolheram.length) {
  console.log('⚠️  ha progresso NAO refletido na base: rode `node scripts/codeql-baseline-check.mjs --write` e commite.');
}
