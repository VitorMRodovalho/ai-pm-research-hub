// supabase/functions/_shared/comms-host.ts
// ─────────────────────────────────────────────────────────────────────────────
// SINGLE SOURCE OF TRUTH do host usado pelas Edge Functions.
//
// Existem DOIS hosts, e confundi-los tem custos opostos:
//
//   COMMS_ORIGIN    — o que vai em QUALQUER artefato que chega numa pessoa (e-mail,
//                     convite, template de campanha). Dominio institucional do PMI-GO.
//   PLATFORM_ORIGIN — o host canonico do deploy. Vale para CORS, OAuth, callback e
//                     qualquer lugar em que o navegador ou um provedor COMPARA a string.
//
// ⚠️ POR QUE NAO E UM SO: `COMMS_ORIGIN` responde 301 para `PLATFORM_ORIGIN`. Um 301 e
// otimo para um humano clicando e PESSIMO para uma comparacao exata. O header `Origin`
// que o navegador manda numa requisicao CORS carrega o host canonico, nunca o alias, entao
// trocar `ALLOWED_ORIGIN` por `COMMS_ORIGIN` quebraria o upload de video sem erro obvio.
// Mesma logica para redirect_uri de OAuth.
//
// Medido ao vivo em 2026-09-22, com controle negativo e com query string:
//
//   pmigo/initiative/<uuid>                      301 -> vitormr.dev/... -> final 200
//   pmigo/profile                                301 -> final 200
//   pmigo/claim?token=TOKEN_DE_TESTE_123         query PRESERVADA
//   pmigo/attendance?eventId=99&action=register  query PRESERVADA, com o `&`
//   CONTROLE −: pmigo/caminho-que-nao-existe-xyz 404  (a sonda sabe dizer nao)
//
// POR QUE ESTE ARQUIVO EXISTE, se `src/lib/canonical.ts` ja e o SSOT do host: as Edge
// Functions rodam em Deno e **nao podem** importar de `src/`. O proprio `canonical.ts` diz
// isso no item 7 do checklist de flip, e chamava o conserto de "follow-up, not a blocker".
// Era verdade enquanto todo destinatario era membro interno. Deixou de ser quando o primeiro
// convite EXTERNO passou a sair por estes templates (#2400/#2416): ali o envelope dizia
// `nucleoia@pmigo.org.br` e o botao levava para o dominio pessoal do dono.
//
// Guard: `tests/contracts/2421-links-de-comms-no-dominio-institucional.test.mjs`.
// Cross-ref: #2421, `src/lib/canonical.ts`, diretriz do dono de 2026-07-03.
// ─────────────────────────────────────────────────────────────────────────────

/** Host institucional. TUDO que chega numa pessoa aponta para ca. */
export const COMMS_ORIGIN = 'https://nucleoia.pmigo.org.br';

/** Host canonico do deploy. So para comparacao exata: CORS, OAuth, callback. */
export const PLATFORM_ORIGIN = 'https://nucleoia.vitormr.dev';

/**
 * Monta uma URL de comunicacao a partir de um caminho interno.
 * Aceita com ou sem barra inicial; recusa silenciosamente nada — se vier absoluto, devolve como veio.
 */
export function commsUrl(path: string): string {
  if (!path) return COMMS_ORIGIN;
  if (/^https?:\/\//i.test(path)) return path;
  return `${COMMS_ORIGIN}${path.startsWith('/') ? path : `/${path}`}`;
}
