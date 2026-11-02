// The shape of a WhatsApp group invite the platform accepts. It is the same pattern the reader
// get_community_group_link (#740) applies before serving an invite, and the reader serves nothing else:
// an invite saved in another shape would hide the group card from everyone, with no error anywhere.
// So the settings screen refuses it before writing.
export const WHATSAPP_GROUP_INVITE_RE = /^https:\/\/chat\.whatsapp\.com\/[A-Za-z0-9]{10,}(\?[A-Za-z0-9_=&-]*)?$/;

export function isWhatsAppGroupInvite(url: string): boolean {
  return WHATSAPP_GROUP_INVITE_RE.test(url);
}
