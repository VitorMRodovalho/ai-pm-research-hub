// #1513 — varredura de auth de chamador nas Edge Functions.
//
// O #1380 fechou UMA porta (`drive-create-subfolder`); o #1513 tratou a classe.
// Este guard cobre as 5 EFs gateadas na fase 2, mais o inventário completo da
// varredura, para que a classe não reabra uma EF de cada vez.
//
// Cada uma foi medida VIVA em 2026-07-28 antes de ser tocada — probe sem
// credencial contra produção, ou leitura do corpo deployado quando o probe teria
// efeito colateral. Nenhuma foi classificada por grep.
//
// Limite honesto: estas são asserções estáticas no source. Elas garantem que uma
// edição futura não derrube o gate; NÃO garantem que a versão no ar o carregue.
// Esse par só fecha com merge+deploy+probe na mesma sessão, registrado no PR.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (slug) => readFileSync(`supabase/functions/${slug}/index.ts`, "utf8");

// EFs gateadas nesta fase. `evidence` é como a abertura foi medida em produção.
const GATED = [
  {
    slug: "drive-list-folder-files",
    evidence: "POST sem credencial devolveu 400 'folder_id required' — chegou na validação de corpo sem passar por auth",
    // O gate precede a leitura do Vault e a chamada à Drive API. Esta EF usa a
    // service account (getServiceAccountKey), não o OAuth delegado das irmãs.
    before: ["getServiceAccountKey", "listDriveFolderFiles"],
  },
  {
    slug: "drive-upload-to-folder",
    evidence: "POST sem credencial devolveu 400 'folder_id required'",
    before: ["getOAuthCreds"],
  },
  {
    slug: "drive-discover-atas",
    evidence: "corpo local sem nenhum req.headers.get; não probeada porque um POST dispara varredura imediata",
    before: ["createClient"],
  },
  {
    slug: "sync-artia",
    evidence: "corpo DEPLOYADO (v51) grepado: req.headers.get aparece 0 vezes, verify_jwt=false",
    before: ["createClient"],
  },
  {
    slug: "get-comms-metrics",
    evidence: "probe com a anon key PÚBLICA devolveu HTTP 200 com métricas da organização — verify_jwt=true não basta",
    before: ["createClient"],
  },
];

for (const { slug, evidence, before } of GATED) {
  const src = read(slug);

  test(`#1513: ${slug} gateia em service-role — ${evidence}`, () => {
    assert.match(
      src,
      /import \{ isServiceRoleToken, bearerFrom \} from ['"]\.\.\/_shared\/service-auth\.ts['"]/,
      "deve importar os helpers compartilhados de caller-auth",
    );
    assert.match(src, /if \(!\(await isServiceRoleToken\(SUPABASE_URL, bearerFrom\(req\)\)\)\)/);
  });

  test(`#1513: ${slug} — o gate é awaited (Promise não-awaited é sempre truthy)`, () => {
    // A mutação que compila, deixa o gate visível e ainda assim libera todo
    // mundo é remover o `await`: `!Promise` é sempre false.
    const i = src.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))");
    assert.ok(i !== -1, "gate presente");
    assert.match(src.slice(Math.max(0, i - 40), i), /await\s*$/);
  });

  test(`#1513: ${slug} — devolve 401 unauthorized`, () => {
    const block = src.slice(src.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))")).slice(0, 320);
    assert.match(block, /status:\s*401/);
    assert.match(block, /['"]unauthorized['"]/);
  });

  test(`#1513: ${slug} — ordem fail-closed (gate antes de ${before.join(", ")})`, () => {
    const serve = src.indexOf("Deno.serve");
    const gate = src.indexOf("isServiceRoleToken(SUPABASE_URL, bearerFrom(req))");
    assert.ok(gate > serve, "gate dentro do handler");
    for (const sym of before) {
      const idx = src.indexOf(sym, serve);
      assert.ok(idx !== -1, `${sym} presente após o handler`);
      assert.ok(gate < idx, `gate deve preceder ${sym}`);
    }
  });
}

// ── Inventário: EFs que a varredura confirmou JÁ protegidas, por gate de
// segredo compartilhado escrito à mão. O grep original do #1513 não as
// reconheceu (procurava isServiceRoleToken/getUser/current_caller_role), e
// todas as 5 devolveram 401 em produção sem credencial. Este teste impede que
// alguém remova esses gates achando que a EF "nunca teve um".
const SECRET_GATED = [
  { slug: "ots-stamp", marker: /tokenMatches\(token, serviceRoleKey\) \|\| tokenMatches\(token, cronSecret\)/ },
  { slug: "ots-upgrade", marker: /tokenMatches\(token, serviceRoleKey\) \|\| tokenMatches\(token, cronSecret\)/ },
  { slug: "sync-comms-metrics", marker: /validSecrets/ },
  { slug: "sync-knowledge-insights", marker: /syncSecret/ },
  { slug: "sync-knowledge-youtube", marker: /syncSecret/ },
];

for (const { slug, marker } of SECRET_GATED) {
  test(`#1513: ${slug} mantém seu gate de segredo compartilhado (401 medido em prod)`, () => {
    const src = read(slug);
    assert.match(src, marker, "o gate de segredo compartilhado sumiu");
    assert.match(src, /req\.headers\.get\(['"]Authorization['"]\)/, "deve ler o header de entrada");
    // Fail-closed: segredo ausente/vazio nunca autoriza.
    assert.match(
      src,
      /!syncSecret|!validSecrets\.length|secret\.length === 0/,
      "gate deve ser fail-closed quando o segredo não está setado",
    );
  });
}

test("#1513: tokenMatches das EFs OTS compara em tempo constante e rejeita segredo vazio", () => {
  const src = read("ots-stamp");
  assert.match(src, /if \(secret\.length === 0 \|\| token\.length !== secret\.length\) return false/);
  assert.match(src, /timingSafeEqual/);
});
