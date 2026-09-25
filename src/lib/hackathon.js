// #2485: destino da rota de entrada /hackathon (e /en/hackathon, /es/hackathon).
//
// O site do hackathon mora fora da plataforma. As tres paginas e o smoke de rotas leem daqui,
// entao trocar o destino e trocar SO este valor.
//
// 302 de proposito: nenhum navegador guarda o destino, entao uma troca vale na hora. Reavaliar 301
// depois de 04/10, com o edital publicado e o destino estavel.
export const HACKATHON_URL = 'https://hackathon.nucleoia.org/';
export const HACKATHON_REDIRECT_STATUS = 302;
