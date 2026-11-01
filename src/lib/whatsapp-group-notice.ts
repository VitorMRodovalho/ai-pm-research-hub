// The notice shown next to every WhatsApp group invite the platform serves: the onboarding and general groups
// (get_community_group_link, #740) and the tribe groups (get_tribe_group_link). Whoever joins a WhatsApp group
// shows their phone number to its members, so the person reads that before following the link, not after.
//
// One source for the five places that render an invite (pre-onboarding card, general group card, Term success
// screen, tribe page, tribe dashboard), so the wording cannot drift between them. Plain text: callers that build
// HTML strings escape it like any other value.

const PHONE_VISIBLE = {
  'pt-BR': 'Ao entrar, seu número fica visível aos participantes.',
  'en-US': "When you join, your phone number is visible to the group's members.",
  'es-LATAM': 'Al entrar, su número queda visible para los participantes.',
} as const;

// Accepts the platform's language tags ('pt-BR', 'en-US', 'es-LATAM') and the short codes some pages use
// ('pt', 'en', 'es'); anything else falls back to Portuguese, like the rest of the site.
export function phoneVisibleNotice(lang: string | null | undefined): string {
  const l = (lang || '').toLowerCase();
  if (l.startsWith('en')) return PHONE_VISIBLE['en-US'];
  if (l.startsWith('es')) return PHONE_VISIBLE['es-LATAM'];
  return PHONE_VISIBLE['pt-BR'];
}
