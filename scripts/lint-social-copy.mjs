#!/usr/bin/env node
/**
 * Lint de copy de rede social do Núcleo IA & GP — interface de linha de comando.
 *
 * As REGRAS não moram mais aqui. Elas foram para
 * `supabase/functions/_shared/social-copy-rules.mjs` (#1495), porque enquanto viviam
 * dentro deste script só valiam para quem lembrasse de rodá-lo: quem agendava por
 * `comms_post action='schedule'` passava direto. Agora o mesmo módulo alimenta este CLI
 * e o caminho de agendamento do `nucleo-mcp`, então mudar a régua num lugar muda nos dois.
 *
 * As regras saíram do diff entre o que foi publicado automaticamente e o que o time de
 * comms deixou no ar no webinar da T6 (27/07/2026). No LinkedIn eles cortaram 25% do
 * texto; no Instagram mantiveram tudo.
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
import { lintCopy } from "../supabase/functions/_shared/social-copy-rules.mjs";

function canalDoNome(nome) {
  const n = nome.toLowerCase();
  if (n.includes("linkedin")) return "linkedin";
  if (n.includes("instagram") || n.includes("_ig") || n.includes("ig_")) return "instagram";
  return null;
}

function checar(texto, canal, rotulo) {
  const { erros, avisos } = lintCopy(texto, canal);
  console.log(`\n${rotulo}  [${canal}]  ${texto.length} chars`);
  if (!erros.length && !avisos.length) { console.log("  OK, nada a apontar."); return 0; }
  for (const e of erros) console.log(`  ERRO  ${e.id}: ${e.msg}`);
  for (const a of avisos) console.log(`  aviso ${a.id}: ${a.msg}`);
  return erros.length;
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
