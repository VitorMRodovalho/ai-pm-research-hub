/**
 * Shared certificate PDF generator.
 * Used by /gamification (member view) and /admin/certificates (chapter board view).
 */

export interface CertificateData {
  member_name: string;
  type: string;
  title?: string;
  period_start?: string;
  period_end?: string;
  function_role?: string;
  language?: string;
  verification_code?: string;
  description?: string;
  issued_by?: string;
  signature_url?: string;
}

const TEMPLATES: Record<string, Record<string, string>> = {
  'pt-BR': {
    participation: 'Certificamos que',
    contribution: 'Certificamos que',
    completion: 'Certificamos que',
    excellence: 'Certificamos que',
    volunteer_agreement: 'Declaramos que',
    bodyParticipation: 'participou como pesquisador(a) voluntário(a) do Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos, uma iniciativa colaborativa entre capítulos do PMI no Brasil.',
    bodyContribution: 'contribuiu como voluntário(a) do Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos, desempenhando a função de {role}.',
    bodyCompletion: 'concluiu a Trilha PMI de Inteligência Artificial, demonstrando domínio nos fundamentos de IA aplicada ao Gerenciamento de Projetos.',
    bodyExcellence: 'recebeu reconhecimento de Excelência por contribuição excepcional ao Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos.',
    bodyVolunteer_agreement: 'assinou o Termo de Compromisso de Voluntário do Núcleo de Estudos e Pesquisa em IA & GP, comprometendo-se com as atividades e responsabilidades do programa de voluntariado do PMI Goiás.',
    title: 'CERTIFICADO',
    titleTerm: 'TERMO DE VOLUNTARIADO',
    period: 'Período: {start} a {end}',
    footer: 'Iniciativa colaborativa entre PMI-GO, PMI-CE, PMI-DF, PMI-MG e PMI-RS',
    contributions: 'Principais contribuições:',
    disclaimer: 'PMI®, PMBOK®, PMP® e PMI-CPMAI™ são marcas registradas do PMI, Inc.',
  },
  'en-US': {
    participation: 'This certifies that',
    contribution: 'This certifies that',
    completion: 'This certifies that',
    excellence: 'This certifies that',
    volunteer_agreement: 'This declares that',
    bodyParticipation: 'served as a volunteer researcher at the AI & PM Study and Research Hub, a collaborative initiative among PMI chapters in Brazil.',
    bodyContribution: 'contributed as a volunteer to the AI & PM Study and Research Hub, serving as {role}.',
    bodyCompletion: 'completed the PMI AI Trail, demonstrating proficiency in AI fundamentals applied to Project Management.',
    bodyExcellence: 'received the Excellence Award for outstanding contribution to the AI & PM Study and Research Hub.',
    bodyVolunteer_agreement: 'signed the Volunteer Commitment Agreement of the AI & PM Research Hub, committing to the activities and responsibilities of PMI Goiás volunteer program.',
    title: 'CERTIFICATE',
    titleTerm: 'VOLUNTEER AGREEMENT',
    period: 'Period: {start} to {end}',
    footer: 'A collaborative initiative among PMI-GO, PMI-CE, PMI-DF, PMI-MG and PMI-RS',
    contributions: 'Key contributions:',
    disclaimer: 'PMI®, PMBOK®, PMP® and PMI-CPMAI™ are registered marks of PMI, Inc.',
  },
  'es-LATAM': {
    participation: 'Se certifica que',
    contribution: 'Se certifica que',
    completion: 'Se certifica que',
    excellence: 'Se certifica que',
    volunteer_agreement: 'Se declara que',
    bodyParticipation: 'participó como investigador(a) voluntario(a) del Hub de Estudios e Investigación en Inteligencia Artificial y Gestión de Proyectos, una iniciativa colaborativa entre capítulos del PMI en Brasil.',
    bodyContribution: 'contribuyó como voluntario(a) del Hub de Estudios e Investigación en IA y Gestión de Proyectos, desempeñando la función de {role}.',
    bodyCompletion: 'completó la Ruta PMI de Inteligencia Artificial, demostrando dominio en los fundamentos de IA aplicada a la Gestión de Proyectos.',
    bodyExcellence: 'recibió el reconocimiento de Excelencia por contribución excepcional al Hub de Estudios e Investigación en IA y Gestión de Proyectos.',
    bodyVolunteer_agreement: 'firmó el Acuerdo de Compromiso de Voluntariado del Hub de Estudios e Investigación en IA & GP.',
    title: 'CERTIFICADO',
    titleTerm: 'ACUERDO DE VOLUNTARIADO',
    period: 'Período: {start} a {end}',
    footer: 'Iniciativa colaborativa entre PMI-GO, PMI-CE, PMI-DF, PMI-MG y PMI-RS',
    contributions: 'Contribuciones principales:',
    disclaimer: 'PMI®, PMBOK®, PMP® y PMI-CPMAI™ son marcas registradas de PMI, Inc.',
  },
};

/**
 * Generate HTML for a single certificate (one A4 page).
 * Returns HTML string that can be inserted into a new window.
 */
export function buildCertificateHTML(certData: CertificateData): string {
  const lang = certData.language || 'pt-BR';
  const tpl = TEMPLATES[lang] || TEMPLATES['pt-BR'];
  const type = certData.type || 'participation';
  const isVolunteerAgreement = type === 'volunteer_agreement';
  const displayTitle = isVolunteerAgreement ? tpl.titleTerm : tpl.title;
  const bodyKey = 'body' + type.charAt(0).toUpperCase() + type.slice(1);
  const bodyText = (tpl[bodyKey] || tpl.bodyParticipation).replace('{role}', certData.function_role || '');
  const period = certData.period_start && certData.period_end
    ? tpl.period.replace('{start}', certData.period_start).replace('{end}', certData.period_end)
    : '';
  const descSection = certData.description
    ? `<div style="margin:24px auto;max-width:420px;text-align:left"><div style="font-size:11px;font-weight:bold;color:#555;margin-bottom:6px">${tpl.contributions}</div><div style="font-size:12px;color:#666;line-height:1.6">${certData.description.replace(/\n/g, '<br>')}</div></div>`
    : '';
  const sigImg = certData.signature_url
    ? `<img src="${certData.signature_url}" style="max-width:180px;max-height:60px;margin-bottom:4px" crossorigin="anonymous">`
    : '';

  return `<div style="width:595px;min-height:842px;padding:48px 40px;border:3px double #1a365d;position:relative;background:#fff;box-sizing:border-box;page-break-after:always">
    <div style="position:absolute;top:14px;left:14px;right:14px;bottom:14px;border:1px solid #cbd5e0;pointer-events:none"></div>
    <div style="text-align:center;margin-bottom:20px"><div style="font-size:13px;color:#666;letter-spacing:2px;text-transform:uppercase">Núcleo de Estudos e Pesquisa em IA & GP</div><div style="font-size:9px;color:#999;margin-top:3px">The AI & PM Study and Research Hub</div></div>
    <div style="text-align:center;font-size:11px;color:#bbb;margin-bottom:20px">─── ✦ ───</div>
    <div style="text-align:center;margin-bottom:28px"><div style="font-size:26px;font-weight:bold;color:#1a365d;letter-spacing:3px">${displayTitle}</div></div>
    <div style="text-align:center;font-size:15px;color:#555;margin-bottom:8px">${tpl[type] || tpl.participation}</div>
    <div style="text-align:center;font-size:22px;font-weight:bold;color:#1a365d;margin-bottom:12px">${certData.member_name}</div>
    <div style="text-align:center;font-size:14px;line-height:1.7;color:#444;max-width:440px;margin:0 auto">${bodyText}</div>
    ${descSection}
    ${period ? `<div style="text-align:center;font-size:12px;color:#666;margin-top:20px">${period}</div>` : ''}
    <div style="text-align:center;margin-top:40px">${sigImg}<div style="border-top:1px solid #333;width:220px;margin:0 auto;padding-top:4px;font-size:11px;color:#333">Vitor Maia Rodovalho, PMP</div><div style="font-size:10px;color:#666">Gestor do Projeto</div></div>
    <div style="text-align:center;margin-top:24px;font-size:10px;color:#999"><div>Código: ${certData.verification_code || ''}</div><div>${new Date().toLocaleDateString()}</div></div>
    <div style="text-align:center;margin-top:16px;font-size:10px;color:#aaa">${tpl.footer}</div>
    <div style="text-align:center;margin-top:8px;font-size:8px;color:#ccc">${tpl.disclaimer}</div>
  </div>`;
}

/**
 * Open a new window with a single certificate PDF (ready to print).
 */
export async function downloadCertificatePDF(certData: CertificateData, sb?: any): Promise<void> {
  // Fetch issuer signature if available
  if (certData.issued_by && !certData.signature_url && sb) {
    try {
      const { data: issuer } = await sb.from('public_members').select('signature_url').eq('id', certData.issued_by).single();
      if (issuer?.signature_url) certData.signature_url = issuer.signature_url;
    } catch {}
  }

  const w = window.open('', '_blank');
  if (!w) return;

  const html = buildCertificateHTML(certData);
  w.document.write(`<html><head><title>${certData.verification_code || 'Certificate'} — ${certData.member_name}</title><style>@page{size:A4 portrait;margin:0}body{margin:0;display:flex;justify-content:center;align-items:center;min-height:100vh;background:#fff;font-family:Georgia,serif}</style></head><body>${html}</body></html>`);
  w.document.close();
  setTimeout(() => w.print(), 500);
}

/**
 * Open a new window with MULTIPLE certificates (one per page, ready to print).
 * Used by bulk download in admin/certificates.
 */
export function downloadBulkCertificatesPDF(certDataList: CertificateData[]): void {
  if (!certDataList.length) return;
  const w = window.open('', '_blank');
  if (!w) return;

  const allHtml = certDataList.map(buildCertificateHTML).join('');
  w.document.write(`<html><head><title>Certificados em lote (${certDataList.length})</title><style>@page{size:A4 portrait;margin:0}body{margin:0;background:#fff;font-family:Georgia,serif}@media print{body{background:#fff}}</style></head><body>${allHtml}</body></html>`);
  w.document.close();
  setTimeout(() => w.print(), 800);
}
