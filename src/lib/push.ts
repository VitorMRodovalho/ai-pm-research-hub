// #2806: push web no navegador (inscrever, cancelar, sincronizar) e onde ele vale.
//
// So no host SEO canonico (SEO_CANONICAL_HOST): o service worker e a inscricao ficam presos a origem, e o login e
// por endereco, entao um so endereco instalavel evita o mesmo aparelho inscrito duas vezes. O banco confere de novo:
// register_push_subscription so aceita a origem do cabecalho Origin que esta em push_allowed_origins.
import { SEO_CANONICAL_HOST } from './canonical';
import { rpcChecked } from './rpc-checked';

// applicationServerKey: chave PUBLICA VAPID, publica por definicao. A privada mora so no segredo da EF send-push.
export const VAPID_PUBLIC_KEY = 'BNThVoLn0OQbKZsd6mr2AkQV_g74qoU_G3o8YTL6TjBjAy1lD25JHiP2yJb67sQPv8I1W_8vnKAvRK5lG5-DrzM';

type RpcClient = {
  rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
};

export type PushSupport = 'ok' | 'other-host' | 'ios-not-installed' | 'unsupported' | 'denied';

export function pushSupport(w: Window): PushSupport {
  if (w.location.host !== SEO_CANONICAL_HOST) return 'other-host';
  const nav = w.navigator as Navigator & { standalone?: boolean };
  // iPhone e iPad so tem push no app adicionado a Tela de Inicio (documentacao da Apple, lida em 28/10/2026).
  const isIos = /iPad|iPhone|iPod/.test(nav.userAgent) || (nav.platform === 'MacIntel' && nav.maxTouchPoints > 1);
  const installed = w.matchMedia?.('(display-mode: standalone)').matches === true || nav.standalone === true;
  if (isIos && !installed) return 'ios-not-installed';
  if (!('serviceWorker' in nav) || !('PushManager' in w) || !('Notification' in w)) return 'unsupported';
  if (Notification.permission === 'denied') return 'denied';
  return 'ok';
}

function b64urlToBuffer(s: string): ArrayBuffer {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

export function registerServiceWorker(): Promise<ServiceWorkerRegistration> {
  return navigator.serviceWorker.register('/sw.js', { scope: '/' });
}

// Lanca na falha de rede e na recusa do banco (origem fora da lista, membro inativo).
export async function saveSubscription(sb: RpcClient, sub: PushSubscription): Promise<void> {
  const keys = sub.toJSON().keys ?? {};
  await rpcChecked(sb, 'register_push_subscription', {
    p_endpoint: sub.endpoint,
    p_p256dh: keys.p256dh ?? '',
    p_auth: keys.auth ?? '',
    // o banco confere este valor contra o cabecalho Origin que o navegador manda, e grava o do cabecalho
    p_origin: location.origin,
    p_user_agent: navigator.userAgent.slice(0, 512),
  });
}

// Chamar direto do clique, com o registro do service worker ja pronto: o Safari so aceita subscribe() que
// nasce de um gesto do usuario.
export async function enablePush(sb: RpcClient, reg: ServiceWorkerRegistration): Promise<void> {
  const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64urlToBuffer(VAPID_PUBLIC_KEY) });
  try {
    await saveSubscription(sb, sub);
  } catch (err) {
    // sem o registro no banco, a inscricao do navegador nao serve para nada: desfaz para o estado ficar coerente
    await sub.unsubscribe().catch(() => undefined);
    throw err;
  }
}

export async function disablePush(sb: RpcClient, reg: ServiceWorkerRegistration): Promise<void> {
  const sub = await reg.pushManager.getSubscription();
  if (!sub) return;
  try {
    await rpcChecked(sb, 'unregister_push_subscription', { p_endpoint: sub.endpoint });
  } finally {
    // cancela no navegador mesmo se o banco falhar: o endpoint morto vira 410 no proximo envio e a EF apaga a linha
    await sub.unsubscribe();
  }
}

// Ao sair da conta, este aparelho para de receber o push dela: num navegador compartilhado, quem entrar depois nao
// ve os avisos de quem saiu. Roda ANTES do signOut (a funcao do banco precisa da sessao), em melhor esforco e com
// teto de 3 s para nunca prender o logout.
export async function unregisterThisDevice(sb: RpcClient): Promise<void> {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;
  const work = (async () => {
    const reg = await navigator.serviceWorker.getRegistration('/');
    if (reg) await disablePush(sb, reg);
  })().catch(() => undefined);
  await Promise.race([work, new Promise((resolve) => setTimeout(resolve, 3000))]);
}

// Apaga a inscricao de push de TODOS os aparelhos do membro e cancela a deste navegador. Usado antes do signOut
// global (a funcao do banco precisa da sessao). Lanca na falha e no teto de 5 s, para a tela poder avisar.
export async function unregisterAllDevices(sb: RpcClient): Promise<void> {
  const work = (async () => {
    await rpcChecked(sb, 'unregister_all_my_push_subscriptions');
    if (typeof navigator !== 'undefined' && 'serviceWorker' in navigator) {
      const reg = await navigator.serviceWorker.getRegistration('/');
      const sub = await reg?.pushManager.getSubscription();
      await sub?.unsubscribe().catch(() => undefined);
    }
  })();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error('timeout')), 5000);
  });
  try {
    await Promise.race([work, timeout]);
  } finally {
    clearTimeout(timer);
  }
}
