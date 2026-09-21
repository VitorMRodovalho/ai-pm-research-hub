// tests/contracts/2400-board-por-iniciativa-nao-e-arbitrario.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2400 — o board devolvido por iniciativa era arbitrário.
 *
 * O DEFEITO: cinco pontos do `nucleo-mcp` faziam
 * `from("project_boards").eq("initiative_id", X).limit(1)` SEM `order()` e SEM filtrar
 * `is_active`. Sem `ORDER BY`, o Postgres não promete qual linha volta, e um board APOSENTADO
 * podia ser entregue como se fosse o corrente.
 *
 * ALCANCE, medido em 21/09/2026: 38 iniciativas, 33 com board, 32 com exatamente UM board ativo
 * (esses não mudam), ZERO com mais de um ativo (a ordem não decide nada hoje; existe para quando
 * decidir) e UMA com zero ativos, que passa a devolver vazio em vez do board aposentado.
 *
 * ⚠️ A issue falava em QUATRO pontos. São CINCO, contados pelo padrão e não à mão. É por isso que
 * o scanner abaixo deriva a lista do CÓDIGO em vez de nomear arquivos: uma lista à mão herda o
 * erro de quem a escreveu.
 *
 * A DECISÃO, ratificada pelo dono em 21/09 (kit `decision-records-kit`): "ativo primeiro, e entre
 * ativos o mais recente". Quando a iniciativa só tem board inativo, devolver VAZIO explicitamente.
 *
 * Cross-ref: #2400, #2395 (o select que pedia coluna inexistente no mesmo caminho), #1932.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();

/** Toda linha que elege UM board a partir de uma iniciativa, varrida do código. */
function pontosDeEscolhaDeBoard() {
  const alvos = [];
  const varrer = (dir) => {
    if (!existsSync(dir)) return;
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (e.name === 'node_modules' || e.name === 'dist' || e.name.startsWith('.')) continue;
      const p = join(dir, e.name);
      if (e.isDirectory()) varrer(p);
      else if (/\.(ts|tsx|mjs|astro)$/.test(e.name)) alvos.push(p);
    }
  };
  for (const d of ['supabase/functions', 'src', 'scripts']) varrer(resolve(ROOT, d));

  const pontos = [];
  for (const p of alvos) {
    if (p.endsWith('database.gen.ts')) continue;
    const src = readFileSync(p, 'utf8');
    if (!src.includes('project_boards')) continue;
    for (const [i, linha] of src.split('\n').entries()) {
      if (!linha.includes('"project_boards"')) continue;
      if (!/\.eq\("initiative_id"/.test(linha)) continue;
      if (!/\.limit\(1\)/.test(linha)) continue;
      pontos.push({ arquivo: p.replace(ROOT + '/', ''), linha: i + 1, texto: linha.trim() });
    }
  }
  return pontos;
}

/**
 * Violações do desenho. Lista vazia = saudável. Serve aos pontos REAIS e aos adulterados, que é o
 * que torna a injeção significativa: uma mutação que só confirma que a string mudou não prova que
 * o guard reprova.
 */
function violacoes(pontos) {
  const v = [];
  for (const p of pontos) {
    const onde = `${p.arquivo}:${p.linha}`;
    if (!/\.eq\("is_active", true\)/.test(p.texto)) {
      v.push(`${onde}: elege um board sem filtrar is_active, e pode entregar um board APOSENTADO como se fosse o corrente`);
    }
    if (!/\.order\("created_at", \{ ascending: false \}\)/.test(p.texto)) {
      v.push(`${onde}: usa limit(1) sem order(), entao a escolha do board e ARBITRARIA e pode variar entre execucoes`);
    }
  }
  return v;
}

test('#2400: todo ponto que elege UM board por iniciativa filtra is_active e ordena', () => {
  const pontos = pontosDeEscolhaDeBoard();

  // CONTROLE POSITIVO: um scanner que não acha nada passaria por vacuidade, que é o modo de falha
  // que este repo já pagou. Medido em 21/09/2026: 5 pontos casam a pré-condição.
  assert.ok(pontos.length >= 5,
    `o scanner achou ${pontos.length} ponto(s): se caiu, o padrão deixou de casar e o guard virou ` +
    'decorativo. Conserte o scanner, não a asserção.');

  assert.deepEqual(violacoes(pontos), []);
});

test('#2400: reprova o ponto que volta a escolher sem filtrar is_active', () => {
  const pontos = pontosDeEscolhaDeBoard();
  const adulterados = pontos.map((p, i) =>
    i === 0 ? { ...p, texto: p.texto.replace('.eq("is_active", true)', '') } : p);
  assert.notEqual(adulterados[0].texto, pontos[0].texto, 'a injeção precisa mesmo alterar a linha');
  const v = violacoes(adulterados);
  assert.ok(v.some((m) => m.includes('sem filtrar is_active')),
    `esperava a violação do is_active, e veio: ${JSON.stringify(v)}`);
});

test('#2400: reprova o ponto que volta a usar limit(1) sem order()', () => {
  const pontos = pontosDeEscolhaDeBoard();
  const adulterados = pontos.map((p, i) =>
    i === 0 ? { ...p, texto: p.texto.replace('.order("created_at", { ascending: false })', '') } : p);
  assert.notEqual(adulterados[0].texto, pontos[0].texto, 'a injeção precisa mesmo alterar a linha');
  const v = violacoes(adulterados);
  assert.ok(v.some((m) => m.includes('sem order()')),
    `esperava a violação da ordem, e veio: ${JSON.stringify(v)}`);
});
