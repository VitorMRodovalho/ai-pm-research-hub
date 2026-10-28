// #2806: service worker do push web. So mostra o aviso e abre o caminho dele.
//
// NAO tem handler de fetch e nao usa a Cache API: nada passa por aqui, nem pagina, nem RPC, nem /rest ou
// /functions, e nada da sessao fica guardado. O app instalado le tudo da rede como o site no navegador.
//
// O push chega cifrado pela Edge Function send-push com { title, url, tag }. O Safari revoga a permissao de quem
// recebe push e nao mostra nada, entao todo push vira uma notificacao.

const FALLBACK_TITLE = 'Núcleo IA & GP';
const FALLBACK_PATH = '/notifications';

// So caminho do proprio site: nada de outra origem, de //host ou de esquema.
function safePath(u) {
  return typeof u === 'string' && u.startsWith('/') && !u.startsWith('//') && !u.includes('\\') ? u : FALLBACK_PATH;
}

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = {};
  }
  const title = typeof data.title === 'string' && data.title.trim() ? data.title : FALLBACK_TITLE;
  event.waitUntil(
    self.registration.showNotification(title, {
      tag: typeof data.tag === 'string' ? data.tag : undefined,
      icon: '/icons/app-192.png',
      data: { url: safePath(data.url) },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(safePath(event.notification.data && event.notification.data.url), self.location.origin).href;
  event.waitUntil(
    (async () => {
      const open = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of open) {
        if (client.url === target && 'focus' in client) return client.focus();
      }
      return self.clients.openWindow(target);
    })(),
  );
});
