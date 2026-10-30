// tests/contracts/2854-grant-explicito-em-objeto-novo.test.mjs
//
// #2854 — toda tabela, view e sequência NOVA em `public` declara, na própria migration, o que cada
// papel da Data API recebe: `anon`, `authenticated` e `service_role`, um por um.
//
// Por quê: a partir de 30/10/2026 o Supabase revoga o default de `public` para objeto novo
// (changelog 45329: `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ... ON TABLES`
// e `... ON SEQUENCES`). Tabela que confie no default nasce sem GRANT e o PostgREST responde 42501,
// inclusive ao `service_role` das Edge Functions e do worker. O padrão que mais aparece nas migrations
// de ago–out/2026 é exatamente o que deixa de funcionar: `REVOKE ALL ... FROM anon, authenticated` e
// nada sobre o `service_role`, que até ontem recebia tudo pelo default.
//
// Vale para migration com versão POSTERIOR a `DESDE`, a cabeça da main quando o guard entrou. As
// anteriores nasceram com o default antigo e mantêm o que têm; não se reescreve migration aplicada.
//
// Como passar: depois do CREATE, um `GRANT ... ON public.<obj> TO <papel>` ou um
// `REVOKE ALL ON public.<obj> FROM <papel>` para cada um dos três. O REVOKE é a forma de declarar
// "este papel não recebe nada" (leitura só por função SECURITY DEFINER, por exemplo). GRANT dentro de
// DO, de corpo de função, de string ou de comentário não conta: ele não roda quando a migration roda.
//
// O analisador está em tests/helpers/new-relation-grants.mjs.

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyzeMigration, undeclaredRoles } from '../helpers/new-relation-grants.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS = join(__dirname, '../../supabase/migrations');

// Cabeça da main em 30/10/2026, antes do guard. Mover este marco para a frente isenta migration nova
// da regra; só faz sentido se a regra deixar de valer.
const DESDE = '20261030181305';

/** Pendências de cada migration do diretório com versão > DESDE. */
function scan(dir) {
  const files = readdirSync(dir)
    .filter((f) => /^\d{14}_.+\.sql$/.test(f) && f.slice(0, 14) > DESDE)
    .sort();
  const findings = [];
  let objects = 0;
  for (const f of files) {
    const sql = readFileSync(join(dir, f), 'utf8');
    objects += analyzeMigration(sql).created.length;
    for (const x of undeclaredRoles(sql)) findings.push(`${f}: ${x.kind} public.${x.name} sem declaração para ${x.missing.join(', ')}`);
  }
  return { files, objects, findings };
}

test('#2854: o marco DESDE é uma migration que existe no diretório', () => {
  const nomes = readdirSync(MIGRATIONS).filter((f) => f.startsWith(`${DESDE}_`));
  assert.equal(nomes.length, 1, `nenhuma migration ${DESDE}_*.sql: o marco não aponta para o histórico real`);
});

test('#2854: toda migration posterior ao marco declara os três papéis em cada objeto novo de public', (t) => {
  const { files, objects, findings } = scan(MIGRATIONS);
  t.diagnostic(`${files.length} migration(s) depois de ${DESDE}, ${objects} objeto(s) novo(s) em public`);
  assert.deepEqual(
    findings,
    [],
    'Declare, depois do CREATE, GRANT ou REVOKE para anon, authenticated e service_role (ver o cabeçalho deste arquivo):\n' +
      findings.join('\n'),
  );
});

// ── o instrumento diz NÃO em migration real ──────────────────────────────────────────────────────
// Duas migrations históricas (imutáveis): uma no padrão que a regra existe para pegar, outra que já
// declarava tudo, inclusive a sequência implícita de um bigserial.

test('#2854: controle real — push_subscriptions (28/10) deixava o service_role no default', () => {
  const sql = readFileSync(join(MIGRATIONS, '20261028144246_2806_push_subscriptions.sql'), 'utf8');
  assert.deepEqual(undeclaredRoles(sql), [{ kind: 'table', name: 'push_subscriptions', missing: ['service_role'] }]);
});

test('#2854: controle real — audit_event_collapse_backup declarava tabela e sequência do bigserial', () => {
  const sql = readFileSync(join(MIGRATIONS, '20260805000494_1536_collapse_cross_series_duplicate_attendance.sql'), 'utf8');
  const { created } = analyzeMigration(sql);
  assert.deepEqual(
    created.map((c) => `${c.kind}:${c.name}`),
    ['table:audit_event_collapse_backup', 'sequence:audit_event_collapse_backup_id_seq'],
  );
  assert.deepEqual(undeclaredRoles(sql), []);
});

// ── mutações sobre uma migration que passa ───────────────────────────────────────────────────────

const OK = `
CREATE TABLE IF NOT EXISTS public.coisa (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL
);
ALTER TABLE public.coisa ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.coisa FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.coisa TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.coisa TO service_role;
`;

test('#2854: controle sem mutação passa', () => {
  assert.deepEqual(undeclaredRoles(OK), []);
});

const MUTACOES = [
  {
    nome: 'sem a linha do service_role',
    sql: OK.replace(/^GRANT SELECT, INSERT.*$/m, ''),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'REVOKE só de anon e authenticated (o padrão de ago–out/2026)',
    sql: OK.replace(/^GRANT .*$/gm, '').replace('FROM PUBLIC, anon;', 'FROM PUBLIC, anon, authenticated;'),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'GRANT antes do CREATE',
    sql: 'GRANT ALL ON public.coisa TO anon, authenticated, service_role;\n' + OK.replace(/^(REVOKE|GRANT) .*$/gm, ''),
    espera: [{ kind: 'table', name: 'coisa', missing: ['anon', 'authenticated', 'service_role'] }],
  },
  {
    nome: 'GRANT só num comentário, depois de um ponto e vírgula',
    sql: OK.replace('GRANT SELECT, INSERT', '-- nota; GRANT SELECT, INSERT'),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'GRANT só num comentário de bloco, depois de um ponto e vírgula',
    sql: OK.replace(/^(GRANT SELECT, INSERT.*)$/m, '/* nota; $1 */'),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'GRANT só dentro de um DO, depois de outro comando do corpo',
    sql: OK.replace(/^(GRANT SELECT, INSERT.*)$/m, (linha) => `DO $$ BEGIN PERFORM 1; ${linha} END $$;`),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'GRANT só dentro de uma string (COMMENT ON), depois de um ponto e vírgula',
    sql: OK.replace(/^(GRANT SELECT, INSERT.*);$/m, "COMMENT ON TABLE public.coisa IS 'nota; $1; fim';"),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'GRANT em OUTRA tabela',
    sql: OK.replace('ON TABLE public.coisa TO service_role', 'ON TABLE public.outra TO service_role'),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'GRANT por ALL TABLES IN SCHEMA (não nomeia o objeto)',
    sql: OK.replace('ON TABLE public.coisa TO service_role', 'ON ALL TABLES IN SCHEMA public TO service_role'),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'REVOKE GRANT OPTION FOR (não declara o privilégio)',
    sql: OK.replace('REVOKE ALL ON TABLE public.coisa FROM PUBLIC, anon;', 'REVOKE GRANT OPTION FOR ALL ON TABLE public.coisa FROM anon;'),
    espera: [{ kind: 'table', name: 'coisa', missing: ['anon'] }],
  },
  {
    nome: 'CREATE TABLE sem esquema cai em public',
    sql: OK.replace('CREATE TABLE IF NOT EXISTS public.coisa', 'CREATE TABLE coisa').replace(/^GRANT SELECT, INSERT.*$/m, ''),
    espera: [{ kind: 'table', name: 'coisa', missing: ['service_role'] }],
  },
  {
    nome: 'coluna serial sem GRANT na sequência implícita',
    sql: OK.replace('id uuid PRIMARY KEY DEFAULT gen_random_uuid()', 'id bigserial PRIMARY KEY'),
    espera: [{ kind: 'sequence', name: 'coisa_id_seq', missing: ['anon', 'authenticated', 'service_role'] }],
  },
  {
    nome: 'CREATE SEQUENCE à parte sem GRANT',
    sql: OK + 'CREATE SEQUENCE IF NOT EXISTS public.coisa_numero_seq;\n',
    espera: [{ kind: 'sequence', name: 'coisa_numero_seq', missing: ['anon', 'authenticated', 'service_role'] }],
  },
  {
    nome: 'CREATE VIEW sem GRANT',
    sql: OK + 'CREATE OR REPLACE VIEW public.v_coisa WITH (security_invoker = true) AS SELECT id FROM public.coisa;\n',
    espera: [{ kind: 'view', name: 'v_coisa', missing: ['anon', 'authenticated', 'service_role'] }],
  },
  {
    nome: 'CREATE MATERIALIZED VIEW sem GRANT',
    sql: OK + 'CREATE MATERIALIZED VIEW public.mv_coisa AS SELECT id FROM public.coisa;\n',
    espera: [{ kind: 'materialized view', name: 'mv_coisa', missing: ['anon', 'authenticated', 'service_role'] }],
  },
];

for (const { nome, sql, espera } of MUTACOES) {
  test(`#2854: mutação reprova — ${nome}`, () => {
    assert.notEqual(sql, OK, 'a mutação não mudou o texto');
    assert.deepEqual(undeclaredRoles(sql), espera);
  });
}

// ── o que NÃO é objeto novo de public ────────────────────────────────────────────────────────────

test('#2854: tabela temporária e tabela de outro esquema ficam fora', () => {
  const sql = `
CREATE TEMP TABLE _scratch (id int);
CREATE TABLE IF NOT EXISTS private.segredo (id uuid);
CREATE TABLE "z_archive"."velha" (id uuid);
CREATE INDEX IF NOT EXISTS idx_x ON public.coisa (id);
CREATE OR REPLACE FUNCTION public.f() RETURNS void LANGUAGE sql AS $$ CREATE TABLE public.dentro (id int) $$;
`;
  assert.deepEqual(analyzeMigration(sql).created, []);
});

test('#2854: GRANT com várias tabelas, coluna, aspas e WITH GRANT OPTION declara cada uma', () => {
  const sql = `
CREATE TABLE public.a (id int, x text);
CREATE TABLE public."b" (id int);
REVOKE ALL ON public.a, public."b" FROM anon, "authenticated" CASCADE;
GRANT SELECT (id, x) ON public.a TO service_role WITH GRANT OPTION;
GRANT ALL ON TABLE "public"."b" TO service_role;
`;
  assert.deepEqual(undeclaredRoles(sql), []);
});

// ── o filtro de diretório, exercido sobre arquivos de verdade ────────────────────────────────────

test('#2854: o recorte por versão lê arquivo depois do marco e ignora o marco e nome fora do padrão', () => {
  const dir = mkdtempSync(join(tmpdir(), 'g2854-'));
  try {
    const sem = 'CREATE TABLE public.t (id int);\n';
    writeFileSync(join(dir, `${DESDE}_no_marco.sql`), sem);
    writeFileSync(join(dir, 'notas.sql'), sem);
    writeFileSync(join(dir, '20991231000000_depois.sql'), sem);
    const r = scan(dir);
    assert.deepEqual(r.files, ['20991231000000_depois.sql']);
    assert.equal(r.findings.length, 1);
    assert.match(r.findings[0], /^20991231000000_depois\.sql: table public\.t sem declaração para anon, authenticated, service_role$/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  assert.equal(existsSync(dir), false);
});
