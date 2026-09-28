// #2485: rota de entrada /hackathon (e /en/hackathon, /es/hackathon).
//
// O destino mora em src/lib/canonical.ts, onde vive todo literal de host de src/ (guard
// canonical-host-centralization). Aqui ficam o status e a montagem do destino.
//
// #2511: 302 FIXO, por decisão do GP em 28/09/2026. O endereço curto vai para material impresso e
// precisa poder apontar para a próxima edição, e um 301 fica guardado no navegador de cada visitante,
// sem como desfazer do nosso lado. Isso anula o "reavaliar 301 depois de 04/10" da #2485.
import { HACKATHON_URL } from './canonical.ts';

export { HACKATHON_URL };
export const HACKATHON_REDIRECT_STATUS = 302;

/**
 * #2511: /hackathon/<resto>?<q> vai para o mesmo <resto>?<q> no site do hackathon. O resto entra
 * segmento a segmento, codificado, no CAMINHO de uma URL cujo host já está fixo: nenhum valor
 * (`//outro.host`, `\`, `..`) consegue trocar o destino.
 */
export function hackathonTarget(rest, search) {
  const url = new URL(HACKATHON_URL);
  const segs = String(rest ?? '').split('/').filter((s) => s && s !== '.' && s !== '..');
  url.pathname = '/' + segs.map(encodeURIComponent).join('/');
  url.search = typeof search === 'string' ? search : '';
  return url.toString();
}
