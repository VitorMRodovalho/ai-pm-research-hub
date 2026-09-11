import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

/**
 * #1536 — gate de presença SOBREPOSTA no mesmo slot.
 *
 * A varredura que já existia procurava evento duplicado por `(título, data)` e era cega para a classe que
 * mais dói: duas séries recorrentes com títulos DIFERENTES gerando o mesmo encontro, no mesmo dia e horário,
 * com as mesmas pessoas marcadas presentes nas duas. Cada presença gera sua linha de ponto, então a pessoa
 * pontua em dobro por uma noite só e o ranking ordena por total inflado. Foi por isso que a limpeza do #1528
 * saiu incompleta.
 *
 * O sinal certo é a presença, não o título: uma pessoa não pode estar em dois encontros ao mesmo tempo, então
 * presença sobreposta no mesmo slot é contradição física. Título é texto livre, editável, e o audit de 30/07
 * mostrou que vinha de um default errado da própria UI — o pior discriminador possível.
 *
 * ⚠️ MAS sobreposição sozinha NÃO é prova. Em 19/03/2026 há um par REAL: uma `lideranca`/`leadership` de 30
 * min ("pré-Geral") imediatamente antes de uma `geral`/`all`, e as 8 pessoas que constam nas duas
 * participaram das duas de verdade. Um gate que só olhasse sobreposição nasceria com falso-positivo e seria
 * desligado na primeira semana. Daí os DOIS baldes:
 *
 *   BALDE 1 — mesmo `type` E mesma `audience_level`: contradição sem leitura alternativa. Falha SEMPRE.
 *             Medido em 30/07/2026, depois do colapso da migration ...494: ZERO. O gate nasce em zero, sem
 *             allowlist e sem dívida herdada.
 *   BALDE 2 — `type` ou `audience_level` diferentes: pode ser legítimo (o "pré-Geral") ou pode ser duplicata.
 *             Exige decisão humana, então falha a menos que o par esteja na allowlist datada abaixo. Assim um
 *             par ambíguo NOVO aparece em vez de ser tolerado para sempre.
 *
 * Não vira constraint de banco de propósito: a unicidade correta de evento ainda não existe (#1528 — a chave
 * que se propôs recusaria reunião legítima, porque `events.initiative_id` é um balde grosso). Detectar é
 * seguro; barrar não é.
 */

const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = URL && KEY ? createClient(URL, KEY, { auth: { persistSession: false } }) : null;

/**
 * Pares de eventos que se sobrepõem por motivo LEGÍTIMO, revisados um a um por humano. Chave = os dois
 * `events.id` em ordem, que são estáveis (o título não é: ele foi reescrito em 30/07).
 */
const PARES_REVISADOS_LEGITIMOS = [
  {
    // 19/03/2026 19:00 — bate-papo GP + líderes de 30 min ANTES da geral. Os 8 que constam nos dois
    // participaram dos dois encontros. Revisado em 30/07/2026 durante o colapso do #1536.
    a: '7861a200-d7ae-4440-bac3-71faf3b02e46',
    b: 'b8713f93-4113-4cb2-b862-4b6efff66604',
    motivo: 'pré-Geral de liderança seguida da Reunião Geral — encontros distintos, presença dupla real',
  },
];

const SEM_INICIATIVA = '00000000-0000-0000-0000-000000000000';

/**
 * Lê uma tabela inteira em páginas, com ordem estável. Ler sem paginar é como o #1526 nasceu: o corte do
 * PostgREST devolveu 50 de 87 e a agregação inteira ficou errada em silêncio.
 *
 * A parada é a **página curta**, não um `count` tirado antes. A primeira versão deste helper afirmava
 * `linhas.length === count` e quebrou em CI com "vieram 632 de 624": a suíte roda contra a produção viva, e
 * entre a contagem e a última página alguém inseriu eventos. Comparar com um retrato de outro instante
 * transforma escrita concorrente legítima em falha de gate — e um gate que grita por motivo errado é
 * desligado, que é o pior desfecho possível. Página curta é auto-terminante e imune a isso: enquanto vier
 * página cheia, há mais para buscar.
 *
 * A ordenação por `id` mantém o offset estável e o `Map` absorve a linha que aparece duas vezes quando uma
 * inserção empurra a janela — sem isso, a defesa contra leitura curta viraria fonte de duplicata.
 */
async function lerTudo(tabela, colunas) {
  const PAGINA = 1000;
  const MAX_PAGINAS = 100; // trava de laço: 100k linhas é ordem de grandeza acima do domínio
  const porId = new Map();
  let pagina = 0;

  for (; pagina < MAX_PAGINAS; pagina++) {
    const inicio = pagina * PAGINA;
    const { data, error } = await sb
      .from(tabela)
      .select(colunas)
      .order('id', { ascending: true })
      .range(inicio, inicio + PAGINA - 1);
    assert.equal(error, null, `leitura de ${tabela} falhou: ${error?.message}`);
    for (const linha of data) porId.set(linha.id, linha);
    if (data.length < PAGINA) break; // página curta = fim real, não corte do servidor
  }

  assert.ok(
    pagina < MAX_PAGINAS,
    `${tabela}: ${MAX_PAGINAS} páginas sem chegar ao fim — leitura provavelmente em laço, veredito não confiável`,
  );
  return [...porId.values()];
}

/**
 * Monta os pares sobrepostos a partir de listas já lidas. PURA de propósito: sem ela não há como
 * injetar um par com dupla presença REAL e provar que o gate ainda reprova, e um gate que ninguém
 * consegue exercer com defeito conhecido é decoração.
 *
 * ⚠️ `presencas` tem de conter APENAS linhas com `present = true`. Ver a nota em medirSobreposicoes().
 */
function montarPares(eventos, presencas) {
  const membrosPorEvento = new Map();
  for (const p of presencas) {
    if (!p.event_id || !p.member_id) continue;
    if (!membrosPorEvento.has(p.event_id)) membrosPorEvento.set(p.event_id, new Set());
    membrosPorEvento.get(p.event_id).add(p.member_id);
  }

  // Só eventos COM presença registrada podem se sobrepor por presença.
  const comPresenca = eventos.filter((e) => membrosPorEvento.get(e.id)?.size > 0);

  const porSlot = new Map();
  for (const e of comPresenca) {
    const slot = `${e.date}|${e.time_start}|${e.initiative_id ?? SEM_INICIATIVA}`;
    if (!porSlot.has(slot)) porSlot.set(slot, []);
    porSlot.get(slot).push(e);
  }

  const pares = [];
  for (const doSlot of porSlot.values()) {
    if (doSlot.length < 2) continue;
    const ordenados = [...doSlot].sort((x, y) => (x.id < y.id ? -1 : 1));
    for (let i = 0; i < ordenados.length; i++) {
      for (let j = i + 1; j < ordenados.length; j++) {
        const a = ordenados[i];
        const b = ordenados[j];
        const ma = membrosPorEvento.get(a.id);
        const mb = membrosPorEvento.get(b.id);
        const overlap = [...ma].filter((m) => mb.has(m)).length;
        if (overlap === 0) continue;
        pares.push({
          a, b, overlap,
          mesmoTipoEAudiencia: a.type === b.type && a.audience_level === b.audience_level,
          rotulo: `${a.date} ${a.time_start} — "${a.title}" (${a.type}/${a.audience_level}) × ` +
            `"${b.title}" (${b.type}/${b.audience_level}), ${overlap} pessoa(s) nos dois`,
        });
      }
    }
  }
  return pares;
}

/**
 * Lê o vivo e delega o cálculo. Não julga: só mede.
 *
 * O filtro `present = true` é o coração deste gate, e ele faltava até 11/09/2026.
 *
 * O predicado lia `attendance` inteira e contava QUALQUER linha como "pessoa nos dois", inclusive
 * FALTA. Isso inverte o sinal que o teste diz medir: a justificativa escrita lá em cima é "uma
 * pessoa não pode estar em dois encontros ao mesmo tempo" e "cada presença gera sua linha de ponto,
 * então isso é XP em dobro". Uma falta é o oposto disso e não gera ponto nenhum.
 *
 * O comentário logo abaixo já dizia "COM presença registrada" desde o início. Era o código que
 * discordava do comentário, e o comentário estava certo.
 *
 * Como apareceu: o cron `attendance-seal-window-daily` (40 11 * * *) sela FALTAS em lote. Em 09 e
 * 10/09/2026 ele escreveu 25 linhas, todas `present = false`, e empurrou o gate para vermelho na
 * `main` sem ninguém ter escrito nada à mão. Medido no momento do conserto: os 3 pares que
 * reprovavam tinham ZERO pessoas presentes nos dois lados, e o único par com dupla presença real
 * (19/03, 6 pessoas) estava isento por tipo/audiência diferentes. O gate reprovava exatamente onde
 * não havia defeito e passava onde havia presença dupla de verdade.
 */
async function medirSobreposicoes() {
  const eventos = await lerTudo('events', 'id, date, time_start, title, type, audience_level, initiative_id');
  // `id` entra porque é a chave do Map de deduplicação em lerTudo(), não porque o cálculo precise dele.
  const linhas = await lerTudo('attendance', 'id, event_id, member_id, present');
  return montarPares(eventos, linhas.filter((p) => p.present === true));
}

test('#1536 nenhum par sobreposto com MESMO tipo e MESMA audiência', { skip: !sb }, async () => {
  const pares = await medirSobreposicoes();
  const violacoes = pares.filter((p) => p.mesmoTipoEAudiencia);

  assert.deepEqual(
    violacoes.map((p) => p.rotulo),
    [],
    'mesma reunião registrada duas vezes no mesmo slot: cada presença gera ponto, então isso é XP em dobro ' +
      'e ranking inflado. Colapsar para o keeper ANTES de apagar qualquer linha, e nunca reduzir presença de ' +
      'quem compareceu (mérito de trabalho concluído é imutável).',
  );
});

test('#1536 todo par ambíguo já foi revisado por humano', { skip: !sb }, async () => {
  const pares = await medirSobreposicoes();
  const ambiguos = pares.filter((p) => !p.mesmoTipoEAudiencia);

  const naoRevisados = ambiguos.filter(
    (p) => !PARES_REVISADOS_LEGITIMOS.some((r) => r.a === p.a.id && r.b === p.b.id),
  );

  assert.deepEqual(
    naoRevisados.map((p) => p.rotulo),
    [],
    'par sobreposto com tipo/audiência DIFERENTES apareceu sem revisão. Pode ser legítimo (uma reunião de ' +
      'liderança logo antes da geral, por exemplo) ou pode ser duplicata. Decidir e, se legítimo, registrar ' +
      'em PARES_REVISADOS_LEGITIMOS com o motivo — não relaxar o teste.',
  );
});

test('#1536 a allowlist não guarda par que deixou de existir', { skip: !sb }, async () => {
  // Allowlist que sobrevive ao próprio caso vira ruído e, pior, esconde o dia em que o par voltar por outro
  // motivo. Se o par foi resolvido, a entrada sai.
  const pares = await medirSobreposicoes();
  const vivos = new Set(pares.map((p) => `${p.a.id}|${p.b.id}`));
  const obsoletas = PARES_REVISADOS_LEGITIMOS.filter((r) => !vivos.has(`${r.a}|${r.b}`));

  assert.deepEqual(
    obsoletas.map((r) => `${r.a} × ${r.b} — ${r.motivo}`),
    [],
    'entrada da allowlist não corresponde a nenhum par sobreposto vivo: remover do array',
  );
});

/**
 * CONTROLE do filtro de `present`, com fixture sintética.
 *
 * Mexer num gate para ele parar de reprovar é o padrão perigoso da casa. Sem este teste não há como
 * distinguir "afinei o sinal" de "ceguei o portão": as duas mudanças deixam a suíte verde.
 *
 * Roda SEM Supabase de propósito. O controle de um gate que só existe contra o banco vivo some
 * exatamente nos ambientes onde o gate mais precisa ser confiável.
 */
const SLOT = { date: '2026-01-15', time_start: '19:00:00', initiative_id: 'ini-1' };
const evA = { ...SLOT, id: 'ev-a', title: 'Reunião A', type: 'tribo', audience_level: 'tribe' };
const evB = { ...SLOT, id: 'ev-b', title: 'Reunião B', type: 'tribo', audience_level: 'tribe' };

/** Reproduz a composição de produção: filtra `present` e só então monta os pares. */
const comoEmProducao = (linhas) => montarPares([evA, evB], linhas.filter((p) => p.present === true));

test('#1536 controle: dupla presença REAL continua reprovando', () => {
  const pares = comoEmProducao([
    { id: 'p1', event_id: 'ev-a', member_id: 'm1', present: true },
    { id: 'p2', event_id: 'ev-b', member_id: 'm1', present: true },
  ]);

  assert.equal(pares.length, 1, 'o par com a MESMA pessoa presente nos dois tem de ser detectado');
  assert.equal(pares[0].overlap, 1);
  assert.equal(pares[0].mesmoTipoEAudiencia, true, 'mesmo type e audience_level cai no balde que falha SEMPRE');
});

test('#1536 controle: FALTA dos dois lados não é sobreposição', () => {
  const pares = comoEmProducao([
    { id: 'p1', event_id: 'ev-a', member_id: 'm1', present: false },
    { id: 'p2', event_id: 'ev-b', member_id: 'm1', present: false },
  ]);

  assert.deepEqual(pares, [], 'quem faltou nos dois não esteve em lugar nenhum, e não pontuou em dobro');
});

test('#1536 controle: presente em um e ausente no outro não é sobreposição', () => {
  const pares = comoEmProducao([
    { id: 'p1', event_id: 'ev-a', member_id: 'm1', present: true },
    { id: 'p2', event_id: 'ev-b', member_id: 'm1', present: false },
  ]);

  assert.deepEqual(pares, [], 'estar em UM encontro é o comportamento correto, não contradição física');
});

test('#1536 controle: o filtro não engole a pessoa que de fato esteve nos dois', () => {
  // Mistura: m1 pontuou em dobro (defeito real), m2 faltou nos dois (ruído do cron de selagem).
  // O gate tem de ver m1 e ignorar m2, senão o ruído afoga o sinal ou o filtro leva o sinal junto.
  const pares = comoEmProducao([
    { id: 'p1', event_id: 'ev-a', member_id: 'm1', present: true },
    { id: 'p2', event_id: 'ev-b', member_id: 'm1', present: true },
    { id: 'p3', event_id: 'ev-a', member_id: 'm2', present: false },
    { id: 'p4', event_id: 'ev-b', member_id: 'm2', present: false },
  ]);

  assert.equal(pares.length, 1);
  assert.equal(pares[0].overlap, 1, 'conta m1 e só m1: a falta de m2 não infla nem cancela o achado');
});
