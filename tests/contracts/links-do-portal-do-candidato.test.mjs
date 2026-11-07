/**
 * Os links do portal do candidato (/pmi-onboarding/<token>) saem de um host só, public._portal_origin().
 *
 * O CASO: três funções montavam o link em https://nucleoia.vitormr.dev e o lembrete do piloto em
 * https://nucleoia.pmigo.org.br, cada uma com o host cravado no corpo. Agora o host vem do helper, que
 * devolve https://nucleoia.org.
 *
 * O QUE ESTE GUARD AFIRMA, no estado final das migrations:
 *   - o helper devolve exatamente https://nucleoia.org, sem barra no fim, e nenhum cliente o executa;
 *   - em cada uma das quatro funções, o valor que vai ao e-mail como `onboarding_url`, dentro da chamada
 *     a campaign_send_one_off, é `public._portal_origin() || '/pmi-onboarding/' || <token>`. Quando o
 *     valor é uma variável, TODA atribuição dela tem essa forma;
 *   - nenhum dos quatro corpos crava um host do Núcleo.
 * Um includes('_portal_origin') solto ficaria verde com o link ainda cravado num dos ramos, por isso a
 * condição (o valor que chega ao e-mail) e o resultado (o helper) são casados juntos.
 *
 * O QUE ELE NÃO AFIRMA: o valor do secret ONBOARDING_BASE_URL do Worker pmi-vep-sync, que monta o link
 * do e-mail de boas-vindas da importação. Secret não se lê do repo.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const HELPER = '_portal_origin';

// Cada função que monta o link, com o nome do token no corpo e quantas vezes a variável do link é atribuída
// (0 = o valor vai direto, sem variável).
const MONTADORES = {
  dispatch_pending_welcomes: { token: 'v_token', atribuicoes: 1 },
  dispatch_consent_nudge: { token: 'v_token', atribuicoes: 2 },
  reissue_onboarding_link: { token: 'v_token', atribuicoes: 1 },
  _lembrete_do_portal_do_piloto_cron: { token: 'r.token', atribuicoes: 0 },
};

const normal = (s) => maskLineComments(s).replace(/\s+/g, ' ');

// O argumento que segue `ini`, até a vírgula ou o parêntese que fecha no nível 0.
function argumento(c, ini) {
  let nivel = 0;
  let aspas = false;
  for (let i = ini; i < c.length; i++) {
    const ch = c[i];
    if (ch === "'") aspas = !aspas;
    if (aspas) continue;
    if (ch === '(') nivel++;
    else if (ch === ')') { if (nivel === 0) return c.slice(ini, i).trim(); nivel--; }
    else if (ch === ',' && nivel === 0) return c.slice(ini, i).trim();
  }
  return null;
}

/**
 * Violações de uma função. Lista vazia = saudável. Recebe o corpo normalizado como dado, e é a mesma
 * função que julga o estado real em cada teste.
 */
export function violacoes(nome, c, { token, atribuicoes }) {
  const v = [];
  const link = `public.${HELPER}() || '/pmi-onboarding/' || ${token}`;
  if (/https?:\/\/nucleoia\./.test(c)) v.push(`${nome}: o corpo crava um host do Núcleo`);

  const chaves = [...c.matchAll(/'onboarding_url', /g)];
  if (chaves.length !== 1) {
    v.push(`${nome}: ${chaves.length} chaves onboarding_url, esperava 1`);
    return v;
  }
  const at = chaves[0].index;
  const envio = c.lastIndexOf('campaign_send_one_off(', at);
  if (envio === -1 || c.slice(envio, at).includes(';')) v.push(`${nome}: onboarding_url fora da chamada a campaign_send_one_off`);

  const valor = argumento(c, at + chaves[0][0].length);
  if (atribuicoes === 0) {
    if (valor !== link) v.push(`${nome}: o link enviado é "${valor}", não ${link}`);
    return v;
  }
  if (!/^[a-z_]+$/.test(valor ?? '')) {
    v.push(`${nome}: o link enviado é "${valor}", esperava uma variável`);
    return v;
  }
  const atribs = [...c.matchAll(new RegExp(`\\b${valor} := ([^;]*);`, 'g'))].map((m) => m[1].trim());
  if (atribs.length !== atribuicoes) v.push(`${nome}: ${valor} recebe ${atribs.length} atribuições, esperava ${atribuicoes}`);
  for (const a of atribs) if (a !== link) v.push(`${nome}: ${valor} := ${a}, não ${link}`);
  return v;
}

test('o helper devolve só https://nucleoia.org, e nenhum cliente o executa', () => {
  const cap = latestFunctionCapture(ROOT, HELPER);
  assert.match(normal(cap.block),
    /^CREATE OR REPLACE FUNCTION public\._portal_origin\(\) RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS \$function\$ SELECT 'https:\/\/nucleoia\.org'::text \$function\$;$/,
    'o helper mudou de valor, de tipo ou de forma');
  const sql = normal(readFileSync(join(MIGRATIONS, cap.file), 'utf8'));
  assert.match(sql, /REVOKE ALL ON FUNCTION public\._portal_origin\(\) FROM PUBLIC, anon, authenticated;/,
    'o helper não é revogado dos clientes');
  const grant = /GRANT[^;]*ON FUNCTION public\._portal_origin\b[^;]*\b(anon|PUBLIC|authenticated)\b/i;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= cap.file)) {
    assert.doesNotMatch(normal(readFileSync(join(MIGRATIONS, f), 'utf8')), grant, `${f}: devolve o helper a um cliente`);
  }
});

for (const [nome, regra] of Object.entries(MONTADORES)) {
  test(`${nome}: o link do portal que vai ao e-mail sai de public._portal_origin()`, () => {
    const c = normal(latestFunctionCapture(ROOT, nome).block);
    assert.deepEqual(violacoes(nome, c, regra), []);
  });
}
