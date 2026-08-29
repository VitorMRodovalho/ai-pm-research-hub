// tests/contracts/2062c-ferramentas-da-iniciativa-vem-de-config.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2062 passo C — a ferramenta de trabalho aparece onde a pessoa trabalha.
 *
 * SINTOMA (PM, 29/08): *"não vejo dentro do hub acesso fácil a este link, que é de gestão e
 * ferramenta de trabalho deles"*.
 *
 * Medido: `/admin/comms` vivia em UM lugar só, a gaveta de navegação, seção `admin`. E como o item
 * é `lgpdSensitive`, para quem não passa no portão ele não aparece desabilitado — ele SOME. Quem
 * não tinha acesso não tinha nem sinal de que a ferramenta existia.
 *
 * ⚠️ CONFIG, NÃO CÓDIGO. A lista sai de `initiatives.metadata.tools`, o mesmo padrão do
 * `metadata.whatsapp_url` que a página já usava. Iniciativa nova com ferramenta nova não pede
 * deploy, pede uma linha de metadata (ADR-0009). Um `if (initiativeId === '9ea82b09…')` seria o
 * conserto plausível e errado.
 *
 * ⚠️ O RECORTE É "É DA INICIATIVA", NÃO "TEM A DESIGNAÇÃO". Medido em 29/08:
 * `get_caller_capabilities()` devolve `caller_id, person_id, org_actions, is_superadmin,
 * tribe_actions, initiative_actions` — e NÃO devolve `designations`. Filtrar por designação no
 * cliente exigiria uma chamada nova. Mostrar a quem é do time é o recorte honesto: o destino
 * mantém o portão dele, e o #2062 é quem vai alinhar autoridade e vínculo.
 *
 * Cross-ref: #2062 (passo B, a autoridade), ADR-0009 (config, não código), ADR-0105.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const PAGE = readFileSync(resolve(ROOT, 'src/pages/initiative/[id].astro'), 'utf8');
const LANGS = ['pt-BR', 'en-US', 'es-LATAM'];

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#2062C: a lista de ferramentas vem de metadata, e não de id hardcoded', () => {
  assert.match(PAGE, /initData\?\.initiative\?\.metadata\?\.tools/,
    'a página precisa ler as ferramentas do metadata da iniciativa');
  // O conserto plausível e errado: pendurar a ferramenta num id de iniciativa.
  assert.doesNotMatch(PAGE, /9ea82b09/,
    'id de iniciativa hardcoded na página: ferramenta nova passaria a exigir deploy');
});

test('#2062C: o bloco só aparece para quem é da iniciativa', () => {
  assert.match(PAGE, /get_initiative_members/,
    'sem checar o roster, o link apareceria para qualquer visitante da página');
  assert.match(PAGE, /__nucleoCapabilities\?\.caller_id/,
    'a comparação precisa ser contra o caller resolvido, não contra um id do cliente');
  assert.match(PAGE, /souDoTime/, 'a condição de pertencimento precisa gatear a renderização');
});

test('#2062C: o rótulo é i18n nos TRÊS dicionários', () => {
  for (const lang of LANGS) {
    const src = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    assert.match(src, /'initiative\.toolsSection':/, `${lang}: falta initiative.toolsSection`);
  }
  assert.match(PAGE, /toolsSection: t\('initiative\.toolsSection', lang\)/,
    'a chave existe no dicionário mas a página não a lê');
});

test('#2062C vivo: a iniciativa de comunicação declara as ferramentas',
  { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb
    .from('initiatives').select('id, title, metadata')
    .eq('id', '9ea82b09-55c6-4cc3-ab7f-178518d0ab47').single();
  assert.ok(!error, error?.message);

  const tools = data?.metadata?.tools;
  assert.ok(Array.isArray(tools) && tools.length > 0,
    'o Hub de Comunicação não declara ferramenta nenhuma — o bloco não renderiza');
  assert.ok(tools.some((t) => t.href === '/admin/comms'),
    'a ferramenta que motivou o passo C não está declarada');

  for (const t of tools) {
    assert.ok(t.href, 'ferramenta sem href');
    for (const idioma of ['pt', 'en', 'es']) {
      assert.ok(t.label_i18n?.[idioma], `ferramenta ${t.href} sem rótulo em ${idioma}`);
    }
  }

  // CONTROLE POSITIVO: o teste acima passaria por vacuidade se `tools` viesse vazio e o
  // `Array.isArray` fosse a única asserção. Este controle mostra que a leitura enxerga o metadata
  // que já existia antes desta mudança.
  assert.ok(data?.metadata?.whatsapp_url,
    'o metadata veio sem o whatsapp_url que já existia — a leitura não está enxergando');
});
