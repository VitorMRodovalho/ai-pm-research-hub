/**
 * Contract: #2393, fatia A3 (ADR-0134) — o worker do VEP manda o e-mail do piloto quando a vaga é piloto.
 *
 * A M1 criou o template 'pmi_welcome_line_pilot' e a coluna vep_opportunities.video_invite_by. Este guard prende o
 * lado do worker: ele lê a trilha e a data da vaga, escolhe o template do piloto só quando a vaga é line_pilot E
 * tem a data, e passa toda variável que o template declara. Sem a data não há o que prometer, e fica o e-mail geral.
 * Camada S (estática), com a simetria worker × migration nas variáveis.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskJsComments, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const W = resolve(ROOT, 'cloudflare-workers/pmi-vep-sync/src');
const ler = (f) => maskJsComments(readFileSync(join(W, f), 'utf8')).replace(/\s+/g, ' ');

test('#2393m: o worker lê a trilha e a data da vaga e as passa ao e-mail', () => {
  assert.match(ler('db.ts'), /\.select\('opportunity_id, title, chapter_posted, role_default, essay_mapping, vep_url, is_active, evaluation_track, video_invite_by'\);/,
    'a leitura das vagas deixou de trazer a trilha ou a data');
  const idx = ler('index.ts');
  const call = idx.slice(idx.indexOf('await dispatchWelcome(db, env, {'), idx.indexOf('});', idx.indexOf('await dispatchWelcome(db, env, {')));
  assert.match(call, /evaluation_track: opp\.evaluation_track \?\? null, video_invite_by: opp\.video_invite_by \?\? null,/,
    'a chamada deixou de passar a trilha e a data DESTA vaga');
});

test('#2393m: o template do piloto sai só para vaga line_pilot com data; o resto recebe o geral', () => {
  const w = ler('welcome.ts');
  assert.match(w,
    /const pilot = opts\.evaluation_track === 'line_pilot' && Boolean\(opts\.video_invite_by\); const templateSlug = pilot \? 'pmi_welcome_line_pilot' : 'pmi_welcome_with_token';/,
    'a escolha do template mudou de condição ou de resultado');
  assert.match(w, /expires_in_days: ttlDays, \.\.\.\(pilot \? \{ video_invite_by: brDate\(opts\.video_invite_by as string\) \} : \{\}\) \};/, 'a data do convite deixou de ir só no piloto');
  assert.match(w, /p_template_slug: templateSlug,/, 'o envio ignora o template escolhido');
  assert.match(w, /export function brDate\(iso: string\): string \{ const m = \/\^\(\\d\{4\}\)-\(\\d\{2\}\)-\(\\d\{2\}\)\$\/\.exec\(iso\.trim\(\)\); return m \? `\$\{m\[3\]\}\/\$\{m\[2\]\}\/\$\{m\[1\]\}` : iso; \}/,
    'a data deixou de sair como DD/MM/AAAA');
});

test('#2393m: toda variável que o template do piloto declara, o worker passa', () => {
  const w = ler('welcome.ts');
  const bloco = w.slice(w.indexOf('const variables = {'), w.indexOf('};', w.indexOf('const variables = {')));
  const passadas = new Set([...bloco.matchAll(/\b([a-z_]+): /g)].map((m) => m[1]));
  let decl = null;
  for (const f of readdirSync(resolve(ROOT, 'supabase/migrations')).filter((x) => x.endsWith('.sql')).sort()) {
    const s = maskLineComments(readFileSync(resolve(ROOT, 'supabase/migrations', f), 'utf8'));
    const m = s.match(/'pmi_welcome_line_pilot',[\s\S]*?'(\{"first_name"[^']*\})'::jsonb/);
    if (m) decl = JSON.parse(m[1]);
  }
  assert.ok(decl, 'nenhuma migration cria o template do piloto');
  for (const v of Object.keys(decl)) assert.ok(passadas.has(v), `o template declara {{${v}}}, que o worker não passa`);
});
