export function initials(name: string | null | undefined): string {
  if (!name || typeof name !== 'string') return '?';
  return name.split(' ').map((word) => word[0]).filter(Boolean).join('').substring(0, 2).toUpperCase() || '?';
}

export function safeName(member: any): string {
  return member?.name || 'Membro sem nome';
}

export function normalizeDigits(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value).replace(/\D/g, '');
}
