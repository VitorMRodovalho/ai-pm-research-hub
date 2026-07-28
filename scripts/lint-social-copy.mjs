#!/usr/bin/env node
/**
 * Lint de copy de rede social do Núcleo IA & GP.
 *
 * As regras NÃO são preferência de estilo: saíram do diff entre o que foi publicado
 * automaticamente e o que o time de comms deixou no ar no webinar da T6 (27/07/2026).
 * No LinkedIn eles cortaram 25% do texto; no Instagram mantiveram tudo. Este script
 * existe para o próximo post já sair no formato que eles aprovariam, em vez de depender
 * de alguém lembrar.
 *
 * Uso:
 *   node scripts/lint-social-copy.mjs texto.txt --canal=linkedin
 *   node scripts/lint-social-copy.mjs texto.txt --canal=instagram
 *   node scripts/lint-social-copy.mjs pasta/ --canal=auto   (deduz pelo nome do arquivo)
 *
 * Sai com código 1 se houver erro (nunca por aviso), para poder virar gate.
 */
import { readFileSync, statSync, readdirSync } from "node:fs";
import { join, basename } from "node:path";

const LIMITES = { instagram: 2200, linkedin: 3000 };

const REGRAS = [
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

function canalDoNome(nome) {
  const n = nome.toLowerCase();
  if (n.includes("linkedin")) return "linkedin";
  if (n.includes("instagram") || n.includes("_ig") || n.includes("ig_")) return "instagram";
  return null;
}

function checar(texto, canal, rotulo) {
  const achados = [];
  for (const r of REGRAS) {
    if (r.canal !== "ambos" && r.canal !== canal) continue;
    if (r.testa(texto)) achados.push(r);
  }
  const limite = LIMITES[canal];
  if (limite && texto.length > limite) {
    achados.push({ id: "limite-de-caracteres", nivel: "erro", msg: `${texto.length} caracteres, acima do limite de ${limite} do canal.` });
  }
  console.log(`\n${rotulo}  [${canal}]  ${texto.length} chars`);
  if (!achados.length) { console.log("  OK, nada a apontar."); return 0; }
  let erros = 0;
  for (const a of achados) {
    const tag = a.nivel === "erro" ? "ERRO " : "aviso";
    if (a.nivel === "erro") erros++;
    console.log(`  ${tag} ${a.id}: ${a.msg}`);
  }
  return erros;
}

const args = process.argv.slice(2);
const alvo = args.find((a) => !a.startsWith("--"));
const canalArg = (args.find((a) => a.startsWith("--canal=")) || "--canal=auto").split("=")[1];
if (!alvo) {
  console.error("uso: node scripts/lint-social-copy.mjs <arquivo|pasta> [--canal=linkedin|instagram|auto]");
  process.exit(2);
}

const arquivos = statSync(alvo).isDirectory()
  ? readdirSync(alvo).filter((f) => f.endsWith(".txt")).map((f) => join(alvo, f))
  : [alvo];

let totalErros = 0;
for (const f of arquivos) {
  const canal = canalArg === "auto" ? canalDoNome(basename(f)) : canalArg;
  if (!canal) { console.log(`\n${basename(f)}  [canal indefinido] pulado; passe --canal=`); continue; }
  totalErros += checar(readFileSync(f, "utf8"), canal, basename(f));
}
console.log(`\n${totalErros === 0 ? "PASSA" : `FALHA: ${totalErros} erro(s)`}`);
process.exit(totalErros === 0 ? 0 : 1);
