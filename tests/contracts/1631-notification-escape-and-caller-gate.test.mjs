/**
 * #1631 Wave 0 — o sink de notificações e a porta que o alimenta.
 *
 * Dois defeitos medidos em 2026-08-06, um de cada lado do mesmo dado:
 *
 *   (a) SINK — `notifications.astro` tinha escape local cobrindo `& < >` e NÃO a aspa, e o
 *       interpolava dentro de valor de atributo (`data-notif-link="…"`). A aspa fecha o
 *       atributo e o resto do payload vira marcação. O clique ainda fazia
 *       `window.location.href = link` sem olhar o esquema, então `javascript:` EXECUTAVA —
 *       um buraco que nenhum escape resolve, porque ali o valor não é texto, é destino.
 *
 *   (b) FONTE — `create_notification` (3 sobrecargas SECURITY DEFINER, EXECUTE para
 *       `authenticated`) não tinha gate de autoridade do chamador: quem chamasse escolhia
 *       destinatário, título, corpo, `link` e o ator aparente.
 *
 * Por que os testes de (a) são POR PAYLOAD e com par de preservação: um escape que apaga
 * tudo passa em 100% dos testes de bloqueio. Cada vetor tem de sair inofensivo E cada
 * entrada legítima tem de sair intacta (round-trip). Grep de fonte provaria que o escape
 * está escrito, nunca que ele bloqueia — a classe do #1620 e do #1629.
 *
 * Por que o teste de (b) lê privilégio EFETIVO e não `proacl`: um texto de ACL vazio pode
 * significar "fechado" ou "herdando de PUBLIC". `_audit_function_execute_acl` responde a
 * pergunta certa (#1551).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { escapeHtml, safeNavigationUrl } from '../../src/lib/escape-html.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const read = (p) => readFileSync(join(__dirname, p), 'utf8');

const PAGE = read('../../src/pages/notifications.astro');
const MIGRATION = read('../../supabase/migrations/20260806000100_1631_wave0_create_notification_caller_gate.sql');

/** Comentário SQL citando um nome não é uma instrução. Esta migration NOMEIA o que fecha. */
const stripSqlComments = (s) => s.replace(/--[^\n]*/g, '');

/**
 * Idem no lado JS: a página EXPLICA no comentário qual era o atributo vulnerável, e um
 * guard ingênuo leria a explicação como o próprio defeito (este teste falhou exatamente
 * assim na primeira execução). Só descarta `//` em INÍCIO de linha, para não decapitar um
 * `https://` dentro de string.
 */
const stripJsComments = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[ \t]*\/\/[^\n]*$/gm, '');

const PAGE_CODE = stripJsComments(PAGE);

// ─────────────────────────────────────────────────────────────────────────
// (A) escapeHtml — por payload, com par de preservação
// ─────────────────────────────────────────────────────────────────────────

/** Desfaz o escape. `&amp;` por ÚLTIMO, senão `&amp;lt;` volta como `<`. */
function unescapeHtml(s) {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&');
}

const VETORES_TEXTO = [
  ['quebra de atributo com aspa dupla', 'x" onmouseover="alert(1)'],
  ['quebra de atributo com aspa simples', "x' onmouseover='alert(1)"],
  ['fecha a tag e abre script', '</span><script>alert(1)</script>'],
  ['img com onerror', '<img src=x onerror=alert(1)>'],
  ['aspa dupla sozinha fechando o valor', '"'],
  ['payload já entidade-escapado (dupla passagem)', '&quot;&gt;<svg onload=alert(1)>'],
  ['aspa dentro de href injetado', 'a" href="javascript:alert(1)'],
];

test('#1631 (A) escapeHtml: nenhum caractere estrutural sobrevive em NENHUM vetor', () => {
  // Invariante universal: iterar o conjunto. `assert.match` é existencial e um único
  // acerto esconderia os outros seis (lição do #1548).
  for (const [nome, payload] of VETORES_TEXTO) {
    const out = escapeHtml(payload);
    for (const ch of ['<', '>', '"', "'"]) {
      assert.ok(
        !out.includes(ch),
        `vetor "${nome}": caractere ${JSON.stringify(ch)} sobreviveu na saída ${JSON.stringify(out)}`,
      );
    }
  }
});

test('#1631 (A) escapeHtml: preservação — nada é apagado (round-trip)', () => {
  // Sem este par, um escape que devolve string vazia passaria no teste de cima.
  const LEGITIMOS = [
    'Reunião de tribo & café',
    'Card "Onboarding" movido para Doing',
    "O termo do Vitor' está pendente",
    'Ata 2026-08-06 <rascunho>',
    'Título simples sem nada especial',
    'Acentuação preservada: ção, ã, é, ü, 日本語, 🎉',
  ];
  for (const original of LEGITIMOS) {
    assert.equal(
      unescapeHtml(escapeHtml(original)),
      original,
      `entrada legítima alterada: ${JSON.stringify(original)}`,
    );
  }
});

test('#1631 (A) escapeHtml: ausência vira string vazia, não a palavra "null"', () => {
  assert.equal(escapeHtml(null), '');
  assert.equal(escapeHtml(undefined), '');
  assert.equal(escapeHtml(''), '');
  assert.equal(escapeHtml(0), '0', 'zero é valor, não ausência');
});

// ─────────────────────────────────────────────────────────────────────────
// (B) safeNavigationUrl — o destino do clique
// ─────────────────────────────────────────────────────────────────────────

const TAB = String.fromCharCode(9);
const NUL = String.fromCharCode(0);

const VETORES_URL = [
  ['javascript simples', 'javascript:alert(1)'],
  ['javascript maiúsculo', 'JaVaScRiPt:alert(1)'],
  ['javascript com espaço à frente', ' javascript:alert(1)'],
  ['javascript com TAB no meio do esquema', `java${TAB}script:alert(1)`],
  ['javascript com NUL no meio do esquema', `java${NUL}script:alert(1)`],
  ['data text/html', 'data:text/html,<script>alert(1)</script>'],
  ['data svg', 'data:image/svg+xml;base64,PHN2Zz48L3N2Zz4='],
  ['vbscript', 'vbscript:msgbox(1)'],
  ['protocol-relative disfarçado de caminho', '//evil.example/phish'],
  ['string vazia', ''],
  ['só espaços', '   '],
  ['relativo sem barra', 'admin/agenda-viva'],
];

test('#1631 (B) safeNavigationUrl: NENHUM vetor perigoso vira destino', () => {
  for (const [nome, payload] of VETORES_URL) {
    assert.equal(
      safeNavigationUrl(payload),
      null,
      `vetor "${nome}" (${JSON.stringify(payload)}) deveria ser recusado`,
    );
  }
  assert.equal(safeNavigationUrl(null), null);
  assert.equal(safeNavigationUrl(undefined), null);
});

test('#1631 (B) safeNavigationUrl: preservação — os 5757 links vivos continuam clicáveis', () => {
  // Formas medidas em 06/08/2026 na tabela `notifications`: 5752 caminhos internos,
  // 5 absolutos http(s), 562 NULL. Recusar qualquer uma delas seria trocar um XSS por
  // uma quebra de funcionalidade.
  const LEGITIMOS = [
    '/admin/agenda-viva',
    '/volunteer-agreement',
    '/tribe/5?tab=board',
    '/board#card-42',
    'https://nucleoia.vitormr.dev/tribe/5',
    'http://localhost:4321/admin',
  ];
  for (const url of LEGITIMOS) {
    assert.equal(safeNavigationUrl(url), url, `link legítimo recusado: ${url}`);
  }
});

// ─────────────────────────────────────────────────────────────────────────
// (C) O sink não pode voltar a ter escape próprio nem link em atributo
// ─────────────────────────────────────────────────────────────────────────

test('#1631 (C) notifications.astro consome o SSOT e não redefine escape local', () => {
  assert.ok(
    /import\s*\{[^}]*escapeHtml[^}]*\}\s*from\s*'\.\.\/lib\/escape-html'/.test(PAGE),
    'a página deve importar escapeHtml de src/lib/escape-html',
  );
  assert.ok(
    /import\s*\{[^}]*safeNavigationUrl[^}]*\}\s*from\s*'\.\.\/lib\/escape-html'/.test(PAGE),
    'a página deve importar safeNavigationUrl de src/lib/escape-html',
  );
  // A 54ª cópia local nasce assim: alguém precisa escapar, não acha o SSOT, escreve de novo.
  assert.ok(
    !/function\s+(escHtml|escapeHtml|escH|esc|escapeAttr|escOc|escapeHtmlSafe)\s*\(/.test(PAGE_CODE),
    'a página não pode redefinir uma cópia local de escape — usar o SSOT',
  );
});

test('#1631 (C) o link não volta para dentro de um atributo do DOM', () => {
  assert.ok(
    !/data-notif-link/.test(PAGE_CODE),
    'o destino do clique deve ser resolvido em memória (Map), não por atributo',
  );
  assert.ok(
    /linkById\.set\(String\(n\.id\), safeNavigationUrl\(n\.link\)\)/.test(PAGE_CODE),
    'o link tem de passar por safeNavigationUrl ANTES de virar destino',
  );
});

// ─────────────────────────────────────────────────────────────────────────
// (D) A migration fecha as TRÊS sobrecargas — não uma
// ─────────────────────────────────────────────────────────────────────────

const SOBRECARGAS = [
  'public.create_notification(uuid, text, text, text, text, text, uuid)',
  'public.create_notification(uuid, text, text, uuid, text, uuid)',
  'public.create_notification(uuid, text, text, uuid, text, uuid, text)',
];

test('#1631 (D) migration revoga EXECUTE nas 3 sobrecargas, de anon E authenticated', () => {
  const sql = stripSqlComments(MIGRATION);
  for (const assinatura of SOBRECARGAS) {
    const linha = sql
      .split('\n')
      .find((l) => l.includes('REVOKE EXECUTE') && l.includes(assinatura));
    assert.ok(linha, `sem REVOKE para a sobrecarga ${assinatura} — corrigir uma e deixar duas é a gêmea morta`);
    assert.ok(
      /FROM PUBLIC, anon, authenticated;/.test(linha),
      `REVOKE de ${assinatura} tem de alcançar PUBLIC, anon E authenticated (só FROM PUBLIC não fecha nada)`,
    );
  }
});

test('#1631 (D) as duas RPCs substitutas nascem negadas por padrão', () => {
  const sql = stripSqlComments(MIGRATION);
  for (const fn of [
    'public.notify_pending_volunteer_agreements(text)',
    'public.send_notification_to_tribe(text, text, text)',
  ]) {
    assert.ok(
      sql.includes(`REVOKE ALL ON FUNCTION ${fn} FROM PUBLIC, anon, authenticated;`),
      `${fn} tem de revogar antes de conceder`,
    );
    assert.ok(
      sql.includes(`GRANT EXECUTE ON FUNCTION ${fn} TO authenticated, service_role;`),
      `${fn} tem de conceder EXECUTE explicitamente`,
    );
  }
});

// ─────────────────────────────────────────────────────────────────────────
// (E) Guard vivo — privilégio EFETIVO, não texto de proacl
// ─────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SERVICE_KEY);
const skipMsg = 'SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#1631 (E) porta fechada no banco vivo, nas 3 sobrecargas', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_function_execute_acl', {
    p_names: ['create_notification', 'notify_pending_volunteer_agreements', 'send_notification_to_tribe'],
  });
  assert.equal(error, null, `probe de ACL falhou: ${error?.message}`);

  const overloads = data.filter((r) => r.proname === 'create_notification');
  assert.equal(overloads.length, 3, `esperadas 3 sobrecargas de create_notification, vieram ${overloads.length}`);
  for (const row of overloads) {
    assert.equal(row.anon_exec, false, `anon ainda executa create_notification(${row.identity_args})`);
    assert.equal(
      row.authenticated_exec,
      false,
      `authenticated ainda executa create_notification(${row.identity_args}) — a porta reabriu`,
    );
  }

  // E o outro sentido: fechar demais mataria o painel do termo e o broadcast do MCP.
  for (const nome of ['notify_pending_volunteer_agreements', 'send_notification_to_tribe']) {
    const row = data.find((r) => r.proname === nome);
    assert.ok(row, `${nome} não existe no banco — a RPC substituta sumiu`);
    assert.equal(row.authenticated_exec, true, `${nome} precisa ser chamável por authenticated`);
    assert.equal(row.anon_exec, false, `${nome} não pode ser chamável por anon`);
  }
});
