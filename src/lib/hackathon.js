// #2485: rota de entrada /hackathon (e /en/hackathon, /es/hackathon).
//
// O destino mora em src/lib/canonical.ts, onde vive todo literal de host de src/ (guard
// canonical-host-centralization). Aqui fica o status: 302 de proposito, porque nenhum navegador guarda
// o destino e uma troca vale na hora. Reavaliar 301 depois de 04/10, com o edital publicado.
export { HACKATHON_URL } from './canonical';
export const HACKATHON_REDIRECT_STATUS = 302;
