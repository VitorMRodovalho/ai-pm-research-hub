/**
 * Regras de copy de rede social do Núcleo IA & GP — REPRESENTAÇÃO ÚNICA.
 *
 * Por que este arquivo existe (#1495): as regras nasceram dentro de
 * `scripts/lint-social-copy.mjs`, o que as deixava valendo só para quem lembrasse de
 * rodar o script à mão. Quem agenda por `comms_post action='schedule'` passava direto.
 * Um helper de defesa sem consumidor não defende nada (mesma classe do #1485).
 *
 * Agora moram aqui, e há DOIS consumidores: o CLI (`scripts/lint-social-copy.mjs`) e o
 * caminho de agendamento do `nucleo-mcp`. Nenhum dos dois redeclara regra — quem quiser
 * mudar a régua muda neste arquivo e os dois lados mudam juntos.
 *
 * `.mjs` de propósito: precisa ser importável por Deno (bundle da EF) e por Node (CLI e
 * testes) sem flag nem transpile. Precedente no repo: `nucleo-mcp/governance-html.mjs`.
 *
 * As regras NÃO são preferência de estilo. Saíram do diff entre o que a plataforma
 * publicou em 27/07/2026 e o que o time de comms deixou no ar: no LinkedIn cortaram 25%
 * do texto, no Instagram não mexeram em nada estrutural.
 */

export const LIMITES = { instagram: 2200, linkedin: 3000 };

export const REGRAS = [
  {
    id: "linkedin-sem-hashtag",
    canal: "linkedin",
    nivel: "erro",
    testa: (t) => (t.match(/(^|\s)#[\p{L}\d_]+/gu) || []).length > 0,
    msg: "hashtag no LinkedIn. O time removeu as 7 que foram publicadas; no LinkedIn o padrão é sem hashtag.",
  },
  {
    id: "linkedin-sem-boilerplate",
    canal: "linkedin",
    nivel: "erro",
    testa: (t) => /é uma iniciativa dos cap[íi]tulos do PMI no Brasil/i.test(t),
    msg: "parágrafo institucional do Núcleo no LinkedIn. O time corta: quem lê já está no perfil da página.",
  },
  {
    id: "linkedin-cta-sem-emoji",
    canal: "linkedin",
    nivel: "erro",
    testa: (t) => /[\u{1F300}-\u{1FAFF}\u{2700}-\u{27BF}\u{FE0F}]\s*(Inscri[çc][ãa]o|Link)/u.test(t),
    msg: 'rótulo do CTA com emoji no LinkedIn. O padrão que ficou no ar é "Link do evento:" sem emoji.',
  },
  {
    id: "linkedin-sem-fuso-redundante",
    canal: "linkedin",
    nivel: "aviso",
    testa: (t) => /\(hor[áa]rio de Bras[íi]lia\)/i.test(t),
    msg: '"(horário de Brasília)" foi cortado no LinkedIn. Data e hora secas.',
  },
  {
    id: "linkedin-sem-linha-de-formato",
    canal: "linkedin",
    nivel: "aviso",
    testa: (t) => /Online, gratuito, aberto ao p[úu]blico/i.test(t),
    msg: "linha de formato (online/gratuito/gravação) foi cortada no LinkedIn.",
  },
  {
    id: "instagram-link-nao-clicavel",
    canal: "instagram",
    nivel: "erro",
    testa: (t) => /https?:\/\//.test(t),
    msg: "URL na legenda do Instagram. Lá o link não é clicável: usar 'Inscrição no link da bio'.",
  },
  {
    id: "instagram-precisa-hashtag",
    canal: "instagram",
    nivel: "aviso",
    testa: (t) => (t.match(/(^|\s)#[\p{L}\d_]+/gu) || []).length === 0,
    msg: "nenhuma hashtag no Instagram. Lá elas ficam, ao contrário do LinkedIn.",
  },
  {
    id: "sem-em-dash",
    canal: "ambos",
    nivel: "erro",
    testa: (t) => /[—–]/.test(t),
    msg: "em-dash ou en-dash. Regra do PMO: usar hífen ou reescrever.",
  },
  {
    id: "dominio-institucional",
    canal: "ambos",
    nivel: "erro",
    testa: (t) => /nucleoia\.vitormr\.dev/.test(t),
    msg: "domínio pessoal em peça pública. Usar nucleoia.pmigo.org.br.",
  },
  {
    id: "sem-promessa-de-pdu",
    canal: "ambos",
    nivel: "erro",
    testa: (t) => /\bPDUs?\b/i.test(t) || /evento oficial do PMI|chancelad/i.test(t),
    msg: "promessa de PDU ou selo oficial do PMI. O guia de marca proíbe.",
  },
  {
    id: "quebra-no-meio-da-frase",
    canal: "ambos",
    nivel: "erro",
    testa: (t) => t.split("\n").some((l) => /^[a-zà-ú]/.test(l.trim()) && l.trim().length > 0),
    msg: "linha começando em minúscula: sinal de quebra de 74 colunas herdada do markdown. Desdobrar os parágrafos.",
  },
];

/**
 * Aplica as regras do canal a um texto.
 * @returns {{erros: Array<{id:string,msg:string}>, avisos: Array<{id:string,msg:string}>}}
 */
export function lintCopy(texto, canal) {
  const erros = [];
  const avisos = [];
  if (typeof texto !== "string" || !texto.length) return { erros, avisos };

  for (const r of REGRAS) {
    if (r.canal !== "ambos" && r.canal !== canal) continue;
    if (!r.testa(texto)) continue;
    (r.nivel === "erro" ? erros : avisos).push({ id: r.id, msg: r.msg });
  }

  const limite = LIMITES[canal];
  if (limite && texto.length > limite) {
    erros.push({
      id: "limite-de-caracteres",
      msg: `${texto.length} caracteres, acima do limite de ${limite} do canal.`,
    });
  }
  return { erros, avisos };
}

/**
 * Extrai a copy de um payload de publisher. Cada canal batiza o campo de um jeito, e
 * peça sem texto (um STORIES, por exemplo) devolve null de propósito: não há o que lintar,
 * e inventar aviso em peça muda seria ruído que ensina a ignorar o aviso.
 */
export function textoDoPayload(payload) {
  if (!payload || typeof payload !== "object") return null;
  const t = payload.text ?? payload.caption ?? null;
  return typeof t === "string" && t.length ? t : null;
}

/** Uma linha por achado, no formato que vai para `warnings` do envelope semântico. */
export function avisosDeCopy(canal, payload) {
  const texto = textoDoPayload(payload);
  if (!texto) return [];
  const { erros, avisos } = lintCopy(texto, canal);
  return [...erros, ...avisos].map(
    (a) => `copy ${canal} [${a.id}]: ${a.msg}`,
  );
}
