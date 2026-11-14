// webinar_audience_snapshots (GP, 14/11/2026): o público dos webinars vindo do Airmeet entra no banco SÓ como
// agregado. O bruto, com nome, e-mail e presença por pessoa de terceiros, fica no Drive restrito do Núcleo.
// Este guard trava as duas metades da decisão no arquivo que cria a tabela: nenhuma coluna de dado pessoal, e
// anon sem acesso (authenticated só lê). Comentários são mascarados antes de medir.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIG_DIR = resolve(process.cwd(), 'supabase/migrations');
const stripComments = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

function creator() {
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  const file = files.find((f) => /CREATE TABLE public\.webinar_audience_snapshots\b/.test(readFileSync(join(MIG_DIR, f), 'utf8')));
  assert.ok(file, 'uma migration cria public.webinar_audience_snapshots');
  const code = stripComments(readFileSync(join(MIG_DIR, file), 'utf8'));
  const body = code.split(/CREATE TABLE public\.webinar_audience_snapshots\s*\(/)[1].split(/\n\);/)[0];
  return { file, code, body };
}

test('webinar_audience_snapshots não tem coluna de dado pessoal', () => {
  const { file, body } = creator();
  const cols = body.split('\n').map((l) => l.trim()).filter((l) => /^[a-z_]+\s/.test(l) && !/^UNIQUE\b/i.test(l))
    .map((l) => l.split(/\s+/)[0]);
  assert.ok(cols.includes('registrations') && cols.includes('attendees'), `${file}: as colunas de agregado existem`);
  const pessoais = cols.filter((c) => /e_?mail|name|nome|phone|telefone|city|cidade|cpf|participant|attendee_id|person/i.test(c));
  assert.deepEqual(pessoais, [], `${file}: nenhuma coluna de dado pessoal (achadas: ${pessoais.join(', ')})`);
});

test('webinar_audience_snapshots: RLS ligada, anon sem acesso, authenticated só lê', () => {
  const { file, code } = creator();
  assert.match(code, /ALTER TABLE public\.webinar_audience_snapshots ENABLE ROW LEVEL SECURITY;/, `${file}: RLS ligada`);
  assert.match(code, /REVOKE ALL ON public\.webinar_audience_snapshots FROM PUBLIC, anon, authenticated;/,
    `${file}: revoga tudo de anon e authenticated antes de conceder`);
  assert.doesNotMatch(code, /GRANT [^;]* ON public\.webinar_audience_snapshots TO [^;]*\banon\b/, `${file}: anon não recebe GRANT`);
  assert.match(code, /GRANT SELECT ON public\.webinar_audience_snapshots TO authenticated;/, `${file}: authenticated só SELECT`);
  assert.doesNotMatch(code, /GRANT (?:INSERT|UPDATE|DELETE|ALL)[^;]* ON public\.webinar_audience_snapshots TO [^;]*\bauthenticated\b/,
    `${file}: authenticated não escreve`);
  assert.match(code, /CREATE POLICY \w+ ON public\.webinar_audience_snapshots\s+FOR SELECT TO authenticated/,
    `${file}: a única política é de leitura`);
});

test('webinar_audience_snapshots: a política vigente só deixa membro ler', () => {
  // A última migration que define o USING da política é a que vale no banco.
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  const re = /(?:CREATE|ALTER) POLICY was_select_authenticated ON public\.webinar_audience_snapshots[\s\S]*?USING\s*\(([\s\S]*?)\);/;
  const defs = files.map((f) => ({ f, m: stripComments(readFileSync(join(MIG_DIR, f), 'utf8')).match(re) })).filter((x) => x.m);
  assert.ok(defs.length >= 1, 'alguma migration define o USING da política');
  const { f, m } = defs[defs.length - 1];
  assert.match(m[1], /^\(SELECT public\.rls_is_member\(\)\)$/, `${f}: USING tem de ser só rls_is_member() (achado: ${m[1]})`);
});
