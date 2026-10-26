import { canExploreTribes } from './access';

/**
 * Pertencimento (GP 26/10/2026): um link que leva a página de membro aparece só para quem essa página abre.
 *
 * É o padrão de sessão que o Nav já publica, sem nada novo: `navGetMember()` para a sessão já resolvida e o evento
 * `nav:member`, que dispara ao resolver a sessão e de novo no logout (detail null). O visitante nunca o recebe, então
 * o link nasce com `hidden` no HTML e assim fica. O predicado é `canExploreTribes`, o mesmo portão de /tribe/[id] e
 * de /equipe: o link aparece exatamente para quem a página de destino deixa entrar.
 */
export function showForMembers(selector: string): void {
  const sync = (member: unknown) => {
    const ok = canExploreTribes(member);
    document.querySelectorAll<HTMLElement>(selector).forEach((el) => {
      el.hidden = !ok;
    });
  };
  sync((window as any).navGetMember?.() ?? null);
  window.addEventListener('nav:member', ((e: CustomEvent) => sync(e.detail)) as EventListener);
}
