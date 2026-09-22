// tests/contracts/2417-catalogo-de-vinculo-admite-o-que-a-ui-promete.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: este arquivo
// toca o banco, e o guard #1908 exige que DB-gated rode na faixa SERIALIZADA (#1509).
/**
 * O vinculo so alcanca a iniciativa se as DUAS fontes da verdade concordarem.
 *
 * O CASO (#2417): o par `observer x participant -> write_board` foi seedado na #2416 para um
 * workgroup concreto, o Hackathon de Impacto Social. O seed passou nas 4 etapas do
 * V4_AUTHORITY_MODEL.md:158 e mesmo assim ficou INALCANCAVEL, porque existe um SEGUNDO portao,
 * em serie e antes do primeiro, que o checklist nao olha:
 *
 *   portao 1 — `engagement_kinds.initiative_kinds_allowed`: este kind pode ser ATADO a esta
 *              especie de iniciativa? E o que `manage_initiative_engagement` valida.
 *   portao 2 — `engagement_kind_permissions`: o par (kind, role) concede a action? E o que o
 *              checklist de 4 etapas audita.
 *
 * Medido em 22/09/2026: `observer.initiative_kinds_allowed` nao continha `workgroup`, e NENHUM dos
 * 5 kinds externos continha. O checklist so pergunta pelo portao 2, entao um seed pode passar nas
 * 4 etapas e nunca alcancar uma linha.
 *
 * E HA DUAS FONTES DA VERDADE QUE DISCORDAM, o que e a causa raiz:
 *   - `initiative_kinds.allowed_engagement_kinds`  — lado-INICIATIVA, o que o dropdown do admin MOSTRA
 *   - `engagement_kinds.initiative_kinds_allowed`  — lado-KIND, o que a RPC VALIDA
 * Quando divergem, a UI oferece o que a RPC recusa. A migration 20260729000000 (p205/#169) ja
 * tinha escrito isso com todas as letras, para `congress`, e o defeito voltou em `workgroup`.
 *
 * A ASSERCAO E DERIVADA, NAO UMA LISTA DE NOMES. A funcao `divergencias()` cruza as duas tabelas
 * e devolve toda celula em que a UI promete e a RPC recusa. Uma especie de iniciativa nova amanha,
 * ou um kind novo, cai aqui sozinho sem ninguem lembrar de acrescenta-lo.
 *
 * CATRACA COM BASELINE NOMEADO: a divergencia existe em 10 celulas e o dono decidiu (22/09) alinhar
 * SO a celula do caso agora. As 9 restantes ficam em BASELINE_CONHECIDO, uma a uma, com o numero de
 * iniciativas vivas daquele tipo. Celula nova reprova; celula consertada reprova pedindo que o
 * baseline encolha. O baseline nunca cresce em silencio, que e o ponto cego de catraca nao-zero.
 *
 * Cross-ref: #2417, #2400, PR #2416, migration 20260729000000 (p205/#169), ADR-0131,
 *            V4_AUTHORITY_MODEL.md:158.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

/**
 * As 9 celulas que a decisao de 22/09 deixou DE PROPOSITO para a #2417 resolver uma a uma.
 * Cada linha carrega quantas iniciativas daquele tipo existiam quando o baseline foi medido:
 * sem isso, "9 divergencias" e um numero sem dono, e ninguem sabe qual delas custa alguma coisa.
 */
const BASELINE_CONHECIDO = [
  { iniciativa: 'book_club',      vinculo: 'guest',     iniciativas_vivas_em_22_09: 0 },
  { iniciativa: 'book_club',      vinculo: 'observer',  iniciativas_vivas_em_22_09: 0 },
  { iniciativa: 'book_club',      vinculo: 'volunteer', iniciativas_vivas_em_22_09: 0 },
  { iniciativa: 'committee',      vinculo: 'guest',     iniciativas_vivas_em_22_09: 2 },
  { iniciativa: 'committee',      vinculo: 'observer',  iniciativas_vivas_em_22_09: 2 },
  { iniciativa: 'research_tribe', vinculo: 'alumni',    iniciativas_vivas_em_22_09: 14 },
  { iniciativa: 'workgroup',      vinculo: 'guest',     iniciativas_vivas_em_22_09: 10 },
  { iniciativa: 'workshop',       vinculo: 'observer',  iniciativas_vivas_em_22_09: 0 },
  { iniciativa: 'workshop',       vinculo: 'volunteer', iniciativas_vivas_em_22_09: 0 },
];
const chave = (c) => `${c.iniciativa} x ${c.vinculo}`;
const BASELINE = new Set(BASELINE_CONHECIDO.map(chave));

/**
 * Celulas em que o lado-INICIATIVA promete um kind que o lado-KIND recusa.
 *
 * Recebe as duas tabelas como dado puro, de proposito: e a MESMA funcao que julga as linhas reais
 * e as adulteradas do teste de mutacao. Uma mutacao que so confirma que o dado mudou e parafrase.
 */
export function divergencias(initiativeKinds, engagementKinds) {
  const aceita = new Map(); // engagement kind -> Set(initiative kinds que ele aceita)
  for (const ek of engagementKinds) {
    aceita.set(ek.slug, new Set(ek.initiative_kinds_allowed || []));
  }
  const out = [];
  for (const ik of initiativeKinds) {
    for (const prometido of ik.allowed_engagement_kinds || []) {
      const aceitos = aceita.get(prometido);
      if (!aceitos || !aceitos.has(ik.slug)) {
        out.push({ iniciativa: ik.slug, vinculo: prometido });
      }
    }
  }
  return out;
}

async function lerCatalogo() {
  const c = sb();
  const [ini, eng] = await Promise.all([
    c.from('initiative_kinds').select('slug, allowed_engagement_kinds'),
    c.from('engagement_kinds').select('slug, initiative_kinds_allowed'),
  ]);
  assert.ifError(ini.error);
  assert.ifError(eng.error);
  return { initiativeKinds: ini.data, engagementKinds: eng.data };
}

test('#2417 — observer e ADMISSIVEL em workgroup, senao a #2416 nunca alcanca uma linha',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { initiativeKinds, engagementKinds } = await lerCatalogo();

    // A condicao e o resultado, amarrados: o lado-INICIATIVA promete observer em workgroup,
    // ENTAO o lado-KIND tem de aceitar. Afirmar so o segundo deixaria o guard verde num mundo
    // em que a promessa sumiu e o par virou letra morta por outro caminho.
    const workgroup = initiativeKinds.find((k) => k.slug === 'workgroup');
    assert.ok(workgroup, 'especie de iniciativa "workgroup" sumiu do catalogo');
    assert.ok(
      (workgroup.allowed_engagement_kinds || []).includes('observer'),
      'o lado-INICIATIVA parou de prometer observer em workgroup: o caso do Hackathon (#2400) mudou de forma',
    );

    const observer = engagementKinds.find((k) => k.slug === 'observer');
    assert.ok(observer, 'kind "observer" sumiu do catalogo');
    assert.ok(
      (observer.initiative_kinds_allowed || []).includes('workgroup'),
      'observer deixou de ser admissivel em workgroup: manage_initiative_engagement volta a recusar ' +
      'o par observer x participant no Hackathon, e o seed da #2416 fica inalcancavel (#2417)',
    );
  });

test('#2417 catraca — nenhuma divergencia NOVA entre as duas fontes da verdade',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { initiativeKinds, engagementKinds } = await lerCatalogo();

    // Controle positivo: o cruzamento precisa enxergar um catalogo de verdade. Com as tabelas
    // vazias a lista de divergencias tambem sai vazia, e o verde seria por vacuidade.
    const paresPrometidos = initiativeKinds.reduce(
      (n, ik) => n + (ik.allowed_engagement_kinds || []).length, 0);
    assert.ok(paresPrometidos >= 20,
      `controle positivo: o lado-iniciativa promete so ${paresPrometidos} pares; o cruzamento esta olhando um catalogo vazio`);

    const achadas = divergencias(initiativeKinds, engagementKinds);
    const novas = achadas.filter((c) => !BASELINE.has(chave(c)));
    assert.deepEqual(novas, [],
      'a UI passou a oferecer vinculo que a RPC recusa em celula NOVA — o admin vai ver o kind no ' +
      'dropdown e levar "Engagement kind not allowed for initiative kind" ao tentar salvar (#2417)');

    // A catraca tambem aperta: celula consertada tem de SAIR do baseline, senao o numero mente
    // para baixo e um dia ninguem sabe mais quais 9 eram.
    const vivas = new Set(achadas.map(chave));
    const jaConsertadas = [...BASELINE].filter((k) => !vivas.has(k));
    assert.deepEqual(jaConsertadas, [],
      'estas celulas nao divergem mais: tire do BASELINE_CONHECIDO para a catraca nao afrouxar (#2417)');
  });

test('#2417 mutacao — o detector reprova quando a divergencia volta, pela MESMA funcao', () => {
  // Alimenta o MESMO julgador com um catalogo adulterado. Sem isso, um `includes` verde nao
  // distingue "nao ha divergencia" de "o cruzamento nao esta medindo nada".
  const ini = [{ slug: 'workgroup', allowed_engagement_kinds: ['observer', 'workgroup_member'] }];

  const saudavel = [
    { slug: 'observer', initiative_kinds_allowed: ['research_tribe', 'workgroup'] },
    { slug: 'workgroup_member', initiative_kinds_allowed: ['workgroup'] },
  ];
  assert.deepEqual(divergencias(ini, saudavel), [],
    'controle sem mutacao: catalogo alinhado nao pode produzir divergencia');

  // Mutacao 1: o estado EXATO de antes do conserto — observer sem workgroup.
  const semWorkgroup = [
    { slug: 'observer', initiative_kinds_allowed: ['research_tribe'] },
    { slug: 'workgroup_member', initiative_kinds_allowed: ['workgroup'] },
  ];
  assert.deepEqual(divergencias(ini, semWorkgroup), [{ iniciativa: 'workgroup', vinculo: 'observer' }],
    'mutacao 1: o detector tem de achar a celula que bloqueou a #2416');

  // Mutacao 2: o kind inteiro some do lado-KIND (catalogo truncado, nao so a lista).
  const semOKind = [{ slug: 'workgroup_member', initiative_kinds_allowed: ['workgroup'] }];
  assert.deepEqual(divergencias(ini, semOKind), [{ iniciativa: 'workgroup', vinculo: 'observer' }],
    'mutacao 2: kind ausente no lado-KIND conta como recusa, nao como "sem opiniao"');
});
