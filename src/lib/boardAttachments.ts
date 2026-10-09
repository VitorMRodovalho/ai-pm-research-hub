// #2449: anexo enviado pelo card vive no bucket PRIVADO `board-attachments`. A URL gravada vinha de
// getPublicUrl, que não serve arquivo de bucket privado (400 medido em 24/09/2026; a curadoria via
// "Bucket not found" em 08/10/2026), então o anexo só abre por link assinado, gerado para quem a policy
// do bucket deixa ler: quem vê o card. O caminho sai do próprio anexo (campo `path`, ou a URL antiga).
//
// Compartilhado entre o card (CardDetail) e a tela da curadoria (CuratorshipBoardIsland): as duas
// mostram o mesmo anexo, e uma cópia em cada lugar foi exatamente o que deixou a curadoria com o link cru.
export const ATTACH_BUCKET = 'board-attachments';

export const storagePathOf = (att: { url?: string; path?: string }): string | null => {
  if (att.path) return att.path;
  const url = att.url || '';
  const m = url.match(/\/storage\/v1\/object\/(?:public|sign)\/board-attachments\/([^?#]+)/);
  if (m) return decodeURIComponent(m[1]);
  // getPublicUrl sem retorno gravava o próprio caminho
  return /^[0-9a-f-]{36}\/[0-9a-f-]{36}\//i.test(url) ? url : null;
};
