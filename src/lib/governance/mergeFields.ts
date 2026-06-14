export type GovernanceMergeContext = {
  member?: Record<string, any> | null;
  chain?: Record<string, any> | null;
  now?: Date;
};

export type GovernanceMergeResult = {
  html: string;
  unresolved: string[];
  applied: string[];
};

const GOVERNANCE_LEGAL_DOC_TYPES = new Set([
  'cooperation_agreement',
  'accession_term',
  'data_processing_agreement',
]);

const PLATFORM_VALUES: Record<string, string> = {
  gp_nucleo: 'Vitor Maia Rodovalho',
  presidente_pmigo: 'Ivan Lourenço',
};

function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatDatePtBR(date: Date): string {
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo',
  }).format(date);
}

function firstPresent(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  }
  return null;
}

export function shouldRenderGovernanceMergeFields(docType: string | null | undefined): boolean {
  return GOVERNANCE_LEGAL_DOC_TYPES.has(String(docType || ''));
}

export function extractGovernanceMergeFields(html: string): string[] {
  const fields = new Set<string>();
  const re = /\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g;
  let match: RegExpExecArray | null;
  while ((match = re.exec(html)) !== null) fields.add(match[1]);
  return [...fields].sort();
}

export function buildGovernanceMergeValues(context: GovernanceMergeContext): Record<string, string> {
  const member = context.member || {};
  const now = context.now || new Date();
  const today = formatDatePtBR(now);
  const city = firstPresent(member.city, member.address_city, member.profile_city);
  const chapter = firstPresent(member.chapter, member.chapter_name, member.organization_name);
  const name = firstPresent(member.name, member.full_name);
  const role = firstPresent(member.chapter_role, member.role_title, member.operational_role);
  const cnpj = firstPresent(member.chapter_cnpj, member.organization_cnpj, member.cnpj);

  const values: Record<string, string> = {
    ...PLATFORM_VALUES,
    data_assinatura: today,
    data_adesao: today,
    data_designacao: today,
  };

  if (city) values.cidade_assinatura = city;
  if (chapter) values.capitulo_aderente = chapter;
  if (name) {
    values.representante_aderente = name;
    values.presidente_aderente = name;
    values.chapter_witness_name = name;
    values.coordenador_curadoria = name;
  }
  if (role) {
    values.cargo_aderente = role;
    values.chapter_witness_role = role;
  }
  if (cnpj) values.cnpj_aderente = cnpj;
  if (member.email) values.email_aderente = String(member.email);

  return values;
}

export function renderGovernanceMergeFields(
  html: string,
  values: Record<string, string>
): GovernanceMergeResult {
  const applied = new Set<string>();
  const unresolved = new Set<string>();
  const rendered = html.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (raw, field) => {
    const value = values[field];
    if (typeof value === 'string' && value.trim()) {
      applied.add(field);
      return escapeHtml(value);
    }
    unresolved.add(field);
    return `<mark class="governance-merge-missing" data-merge-field="${escapeHtml(field)}">${escapeHtml(raw)}</mark>`;
  });

  return {
    html: rendered,
    applied: [...applied].sort(),
    unresolved: [...unresolved].sort(),
  };
}
