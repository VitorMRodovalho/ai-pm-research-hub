/**
 * #2973: a tela decide o acesso quando o Nav resolve o membro, sem prazo de tentativas.
 *
 * Antes, cada tela do admin consultava navGetMember() em laço e, depois de N tentativas (3 a 18 s), mostrava
 * "acesso restrito". Quem tinha a permissão e um get_member_by_auth lento via a tela negada. Aqui a espera não
 * tem prazo: enquanto o Nav não leu a sessão, nada é decidido; com sessão, quem decide é a permissão do membro.
 *
 * #2974 (E1): o estado 'member' diz também se get_caller_capabilities falhou. O Nav lê o membro e as capacidades
 * no mesmo Promise.all antes do nav:member, então, quando o membro chega, as capacidades já chegaram ou falharam.
 * É um campo do estado 'member', e não um estado à parte, para que quem lê `kind === 'member'` continue recebendo
 * o membro quando só as capacidades falharam.
 */

export type MemberResolution =
  | { kind: 'member'; member: any; capabilitiesFailed: boolean }
  | { kind: 'no-member' }
  | { kind: 'no-session' };

export interface NavWindow {
  addEventListener: (type: string, fn: () => void) => void;
  removeEventListener: (type: string, fn: () => void) => void;
  navGetMember?: () => any;
  navAuthState?: () => 'pending' | 'no-session' | 'resolved';
  navCapabilitiesFailed?: () => boolean;
}

/** O que o Nav sabe agora; null enquanto a sessão não foi lida (a tela continua carregando). */
export function readMemberResolution(win: NavWindow): MemberResolution | null {
  const member = win.navGetMember?.();
  if (member) return { kind: 'member', member, capabilitiesFailed: win.navCapabilitiesFailed?.() === true };
  const state = win.navAuthState?.();
  if (state === 'no-session') return { kind: 'no-session' };
  if (state === 'resolved') return { kind: 'no-member' };
  return null;
}

/** Chama cb com o estado atual, se já resolvido, e de novo a cada nav:member ou nav:no-session. */
export function onMemberResolved(cb: (r: MemberResolution) => void, win?: NavWindow): () => void {
  const w: NavWindow | null = win ?? (typeof window === 'undefined' ? null : (window as unknown as NavWindow));
  if (!w) return () => {};
  const check = () => {
    const r = readMemberResolution(w);
    if (r) cb(r);
  };
  w.addEventListener('nav:member', check);
  w.addEventListener('nav:no-session', check);
  check();
  return () => {
    w.removeEventListener('nav:member', check);
    w.removeEventListener('nav:no-session', check);
  };
}

export interface AdminGate {
  /** A permissão da tela. É a única coisa que leva a onDenied quando há sessão. */
  allow: (member: any) => boolean;
  onAllowed: (member: any) => void;
  onDenied: () => void;
  onNoSession: () => void;
  /**
   * #2974 (E1): allow(membro) deu falso e as capacidades não carregaram, então a recusa pode ser falsa. Sem
   * onLoadFailed, o portão chama onDenied, como antes.
   */
  onLoadFailed?: () => void;
}

/**
 * Portão de tela do admin. Sem sessão: onNoSession. Com sessão: onDenied se allow(membro) for falso (ou não houver
 * cadastro de membro), onAllowed uma vez só se for verdadeiro. Depois de liberar, para de ouvir: a tela já carregou.
 */
export function gateAdminPage(gate: AdminGate, win?: NavWindow): () => void {
  let done = false;
  let stop: () => void = () => {};
  stop = onMemberResolved((r) => {
    if (done) return;
    if (r.kind === 'no-session') {
      gate.onNoSession();
      return;
    }
    const member = r.kind === 'member' ? r.member : null;
    if (!member || !gate.allow(member)) {
      if (r.kind === 'member' && r.capabilitiesFailed && gate.onLoadFailed) {
        gate.onLoadFailed();
        return;
      }
      gate.onDenied();
      return;
    }
    done = true;
    stop();
    gate.onAllowed(member);
  }, win);
  if (done) stop();
  return () => stop();
}

/** O texto "entre para ver", que o AdminLayout põe na página nos 3 idiomas. */
export function adminSignInText(doc?: Pick<Document, 'getElementById'>): string {
  const d = doc ?? (typeof document === 'undefined' ? null : document);
  return d?.getElementById('admin-signin-to-view')?.textContent?.trim() || 'Sign in to view this page.';
}

/** #2974 (F1): o texto de falha ao carregar as capacidades, que o AdminLayout põe na página nos 3 idiomas. */
export function adminLoadFailedText(doc?: Pick<Document, 'getElementById'>): string {
  const d = doc ?? (typeof document === 'undefined' ? null : document);
  return d?.getElementById('admin-load-failed')?.textContent?.trim() || 'Could not load right now. Please try again.';
}
