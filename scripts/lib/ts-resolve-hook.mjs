/**
 * Hook de resolução para rodar scripts `.ts` do repo direto no Node.
 *
 * POR QUE ISTO EXISTE. O Node 22.18+/24 já faz type-stripping sozinho, então um `.ts` roda sem
 * transpilar. O que ele NÃO faz é resolver import relativo SEM extensão: `from "../canonical"`
 * é válido para o TypeScript e para o Vite (que o Astro usa), e é `ERR_MODULE_NOT_FOUND` no
 * ESM do Node, que exige o caminho literal.
 *
 * Foi o que quebrou `scripts/backfill-cert-pdfs.ts`: ele importa `src/lib/certificates/pdf.ts`,
 * que importa `"../canonical"`. O script era a ferramenta pensada para re-renderizar PDF de
 * certificado e estava inutilizável — descoberto em 27/08/2026, quando 47 termos precisaram de
 * backfill e o caminho praticável acabou sendo `net.http_post` contra o endpoint interno.
 *
 * A ALTERNATIVA REJEITADA era pôr `.ts` nos imports de `src/lib/**`. Aquilo é código que VAI
 * para produção pelo build do Astro; mudar a forma dos imports lá para satisfazer um script de
 * manutenção troca um problema de ferramenta por risco no artefato publicado. O hook fica
 * contido no lado do script e não toca em nada que o build enxerga.
 *
 * Só age em specifier RELATIVO e sem extensão reconhecida, e só depois de o resolvedor padrão
 * ter falhado — então não sequestra resolução de pacote nem mascara import realmente quebrado.
 */
const SEM_EXTENSAO = /\.[mc]?[jt]sx?$/;

export async function resolve(specifier, context, nextResolve) {
  const relativo = specifier.startsWith('./') || specifier.startsWith('../');
  if (!relativo || SEM_EXTENSAO.test(specifier)) {
    return nextResolve(specifier, context);
  }

  try {
    return await nextResolve(specifier, context);
  } catch (err) {
    if (err?.code !== 'ERR_MODULE_NOT_FOUND') throw err;
    for (const candidato of [`${specifier}.ts`, `${specifier}.tsx`, `${specifier}/index.ts`]) {
      try {
        return await nextResolve(candidato, context);
      } catch (e) {
        if (e?.code !== 'ERR_MODULE_NOT_FOUND') throw e;
      }
    }
    throw err;
  }
}
