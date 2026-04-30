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
  // Volunteer agreement specific
  member_email?: string;
  member_pmi_id?: string;
  member_chapter?: string;
  member_phone?: string;
  member_address?: string;
  member_city?: string;
  member_state?: string;
  member_country?: string;
  member_birth_date?: string;
  member_contact?: string;
  signed_at?: string;
  counter_signed_at?: string;
  counter_signed_by_name?: string;
  template_content?: any; // full template from governance_documents
  chapter_cnpj?: string;
  chapter_name?: string;
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
    footer: 'Iniciativa colaborativa entre capítulos PMI Brasil',
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
    footer: 'A collaborative initiative among PMI Brazil chapters',
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
    footer: 'Iniciativa colaborativa entre capítulos PMI Brasil',
    contributions: 'Contribuciones principales:',
    disclaimer: 'PMI®, PMBOK®, PMP® y PMI-CPMAI™ son marcas registradas de PMI, Inc.',
  },
};

/**
 * Format phone number respecting country prefixes.
 * - BR cell: +55 (11) 98765-4321 (13 digits with 55 prefix)
 * - BR landline: +55 (11) 3456-7890 (12 digits)
 * - US: +1 (267) 874-8329 (11 digits starting with 1)
 * - Already formatted (contains parenthesis or hyphen): return as-is
 */
function formatPhone(phone: string | undefined): string {
  if (!phone) return '—';
  // If already has formatting (parens or hyphens), return as-is
  if (/[()\-]/.test(phone)) return phone;
  const clean = phone.replace(/\D/g, '');
  // US/CA: 1 + area(3) + exchange(3) + number(4) = 11 digits starting with 1
  if (clean.length === 11 && clean.startsWith('1')) {
    return `+1 (${clean.slice(1, 4)}) ${clean.slice(4, 7)}-${clean.slice(7)}`;
  }
  // BR cell with country code: +55 + DDD(2) + 9 + 4-4 = 13 digits starting with 55
  if (clean.length === 13 && clean.startsWith('55')) {
    return `+55 (${clean.slice(2, 4)}) ${clean.slice(4, 9)}-${clean.slice(9)}`;
  }
  // BR landline with country code: +55 + DDD(2) + 4-4 = 12 digits starting with 55
  if (clean.length === 12 && clean.startsWith('55')) {
    return `+55 (${clean.slice(2, 4)}) ${clean.slice(4, 8)}-${clean.slice(8)}`;
  }
  // BR cell without country code: DDD(2) + 9 + 4-4 = 11 digits
  if (clean.length === 11) {
    return `(${clean.slice(0, 2)}) ${clean.slice(2, 7)}-${clean.slice(7)}`;
  }
  // BR landline without country code: DDD(2) + 4-4 = 10 digits
  if (clean.length === 10) {
    return `(${clean.slice(0, 2)}) ${clean.slice(2, 6)}-${clean.slice(6)}`;
  }
  return phone;
}

/**
 * Translate operational_role to Portuguese display name
 */
function translateRole(role: string | undefined): string {
  if (!role) return '';
  const map: Record<string, string> = {
    manager: 'Gerente de Projeto',
    deputy_manager: 'Gerente Adjunto',
    tribe_leader: 'Líder de Tribo',
    researcher: 'Pesquisador(a)',
    sponsor: 'Patrocinador',
    chapter_liaison: 'Ponto Focal de Capítulo',
    observer: 'Observador(a)',
    alumni: 'Alumni',
  };
  return map[role] || role.replace(/_/g, ' ');
}

/**
 * Expand US state codes and country abbreviations to full names
 */
function expandState(state: string | undefined): string {
  if (!state) return '';
  const map: Record<string, string> = {
    // BR — keep as-is (usually already "Goiás", "MG", "SP")
    GO: 'Goiás',
    // US
    VA: 'Virgínia',
    NC: 'Carolina do Norte',
    CA: 'Califórnia',
    FL: 'Flórida',
    NY: 'Nova York',
    TX: 'Texas',
    MA: 'Massachusetts',
    WA: 'Washington',
    OR: 'Oregon',
  };
  return map[state] || state;
}
function expandCountry(country: string | undefined): string {
  if (!country) return '';
  const map: Record<string, string> = {
    'United States': 'Estados Unidos',
    'USA': 'Estados Unidos',
    'US': 'Estados Unidos',
    'Brasil': 'Brasil',
    'Brazil': 'Brasil',
    'BR': 'Brasil',
  };
  return map[country] || country;
}

/**
 * Format birth date as dd/mm (no year — privacy-respecting)
 */
function formatBirthDate(date: string | undefined): string {
  if (!date) return '—';
  const clean = String(date).slice(0, 10);
  const parts = clean.split('-');
  if (parts.length === 3) return `${parts[2]}/${parts[1]}`;
  return '—';
}

/**
 * Format a date in the "long" Portuguese style: "09 de abril de 2026"
 */
function formatLongDate(date: string | undefined): string {
  if (!date) return '—';
  const clean = String(date).slice(0, 10);
  const dt = clean.length === 10 ? new Date(clean + 'T12:00:00') : new Date(date);
  if (isNaN(dt.getTime())) return String(date);
  const months = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
  return `${dt.getDate().toString().padStart(2,'0')} de ${months[dt.getMonth()]} de ${dt.getFullYear()}`;
}

/**
 * Format period in Brazilian format: "20/01/2026 a 19/12/2026"
 */
function formatPeriod(start: string | undefined, end: string | undefined): string {
  if (!start || !end) return '—';
  const fmt = (d: string) => {
    const clean = d.slice(0, 10);
    const parts = clean.split('-');
    return parts.length === 3 ? `${parts[2]}/${parts[1]}/${parts[0]}` : clean;
  };
  return `${fmt(start)} a ${fmt(end)}`;
}

/**
 * Render the FULL legal volunteer agreement (multi-page A4).
 * Uses the actual template stored in governance_documents.
 * Matches the reference PDF format from PMI-GO (with logo, complete member data,
 * digital signature stamp, and FHC note in annex).
 */
export function buildVolunteerAgreementHTML(certData: CertificateData): string {
  const c = certData.template_content || {};
  const SUB_KEYS: Record<string, string[]> = {
    clause1: ['clause1a', 'clause1b', 'clause1c'],
    clause2: ['clause2_1', 'clause2_2', 'clause2_3', 'clause2_4', 'clause2_5'],
    clause7: ['clause7a'],
    clause9: ['clause9a', 'clause9b', 'clause9c', 'clause9d', 'clause9e', 'clause9f', 'clause9note'],
  };
  const MAIN = ['clause1','clause2','clause3','clause4','clause5','clause6','clause7','clause8','clause9','clause10','clause11','clause12'];

  const locationLine = [certData.member_city, expandState(certData.member_state), expandCountry(certData.member_country)].filter(Boolean).join('/') || '—';
  const addressLine = certData.member_address || '—';
  const phoneLine = formatPhone(certData.member_phone);
  const birthLine = formatBirthDate(certData.member_birth_date);

  // Header with PMI-GO logo (same reference as the example PDF)
  const headerBlock = `
    <div style="margin-bottom:20px">
      <img src="https://nucleoia.vitormr.dev/assets/logos/pmigo.png" alt="PMI Goiás" style="height:52px;width:auto;display:block" crossorigin="anonymous" />
    </div>
    <h1 style="text-align:center;font-size:18px;font-weight:bold;color:#000;margin:20px 0 28px;letter-spacing:0.5px;line-height:1.3">
      TERMO DE COMPROMISSO DE<br/>VOLUNTÁRIO COM O PMI GOIÁS
    </h1>`;

  const memberDataBlock = `
    <div style="font-size:11px;line-height:1.8;margin:8px 0 14px 20px">
      <div><b>PMI ID:</b> ${certData.member_pmi_id || '—'}</div>
      <div><b>Nome:</b> ${certData.member_name || '—'}</div>
      <div><b>Endereço:</b> ${addressLine}</div>
      <div><b>Cidade/Estado:</b> ${locationLine}</div>
      <div><b>Contato:</b> ${phoneLine}. <b>Data de Aniversário</b> <span style="font-size:9px">(dd/mm)</span>: ${birthLine}</div>
      <div><b>E-mail:</b> ${certData.member_email || '—'}</div>
    </div>`;

  const clausesHtml = MAIN.map((key, i) => {
    const text = c[key] || '';
    const subs = SUB_KEYS[key];
    const subsHtml = subs ? `<ol style="margin-top:6px;margin-left:28px;list-style:none;padding:0">${subs.map(subKey => {
      let subText = c[subKey] || '';
      const letter = subKey.slice(-1);
      const isNote = subKey.endsWith('note');
      const isNumbered = /_\d+$/.test(subKey);
      // Some templates already include "Parágrafo único:" in the text — avoid duplicating
      if (isNote) {
        subText = subText.replace(/^Parágrafo\s+único:?\s*/i, '');
      }
      const prefix = isNote ? '<b>Parágrafo único:</b> ' : isNumbered ? '' : `<b style="color:#333">${letter}.</b> `;
      return `<li style="font-size:10.5px;margin-top:6px;${isNote ? 'font-style:italic;color:#555' : ''}">
        ${prefix}${subText}
      </li>`;
    }).join('')}</ol>` : '';
    return `<li style="margin-bottom:12px;font-size:11px;line-height:1.5;text-align:justify">
      <b style="color:#333">${i + 1}.</b> ${text}${subsHtml}
    </li>`;
  }).join('');

  const signedDate = certData.signed_at ? formatLongDate(certData.signed_at) : formatLongDate(new Date().toISOString());
  const counterSignedDate = certData.counter_signed_at ? formatLongDate(certData.counter_signed_at) : null;

  // Digital signature stamp (equivalent to gov.br style in the reference)
  const digitalSignatureStamp = `
    <div style="display:inline-block;background:#f5f5f5;border:1px solid #ccc;padding:10px 14px;font-size:9px;color:#444;margin:12px 0;font-family:Arial,sans-serif">
      <div style="font-weight:bold;color:#1a365d;margin-bottom:2px">🔏 Documento assinado digitalmente</div>
      <div><b>${(certData.member_name || '').toUpperCase()}</b></div>
      <div>Data: ${certData.signed_at ? new Date(certData.signed_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'medium' }) : '—'}</div>
      <div>Código: ${certData.verification_code || '—'}</div>
      <div style="color:#1a5490">Verifique em nucleoia.vitormr.dev/verify/${certData.verification_code || ''}</div>
      <div style="font-size:7px;color:#888;margin-top:3px">Fundamento: Lei nº 14.063/2020 Art. 4º §I (assinatura eletrônica simples)</div>
    </div>`;

  const counterSignatureStamp = certData.counter_signed_at ? `
    <div style="display:inline-block;background:#e6f4ea;border:1px solid #34a853;padding:10px 14px;font-size:9px;color:#1e4620;margin:12px 0;font-family:Arial,sans-serif">
      <div style="font-weight:bold;color:#1a5490;margin-bottom:2px">✓ Contra-assinatura institucional</div>
      <div><b>${(certData.counter_signed_by_name || '').toUpperCase()}</b></div>
      <div>Data: ${new Date(certData.counter_signed_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'medium' })}</div>
      <div>Diretor do PMI Goiás</div>
    </div>` : `
    <div style="display:inline-block;background:#fff3cd;border:1px dashed #dca400;padding:10px 14px;font-size:9px;color:#6b4f00;margin:12px 0;font-family:Arial,sans-serif">
      <div style="font-weight:bold;margin-bottom:2px">⏳ Pendente contra-assinatura</div>
      <div>Aguardando assinatura do Diretor do PMI Goiás</div>
    </div>`;

  // Source indicator based on certificate origin
  const certSource = (certData as any).source || 'platform';
  const govbrPdf = (certData as any).govbr_pdf || (certData as any).signed_via === 'docusign' ? ((certData as any).govbr_pdf || '') : '';
  const govbrSigner = (certData as any).govbr_institutional_signer || '';
  const sourceIndicator = certSource === 'docusign_import'
    ? `<div style="display:inline-block;background:#e8f0fe;border:1px solid #4285f4;padding:6px 12px;font-size:8px;color:#1a56db;margin:8px 0;font-family:Arial,sans-serif;border-radius:4px">
        <div style="font-weight:bold;margin-bottom:1px">📋 Migrado do gov.br — Assinatura eletronica avancada</div>
        ${govbrSigner ? `<div>Signatario institucional: ${govbrSigner}</div>` : ''}
        <div>Assinatura original em ${certData.signed_at ? new Date(certData.signed_at).toLocaleDateString('pt-BR') : '—'}</div>
       </div>`
    : certSource === 'admin_attestation'
    ? `<div style="display:inline-block;background:#fef3cd;border:1px solid #dca400;padding:6px 12px;font-size:8px;color:#6b4f00;margin:8px 0;font-family:Arial,sans-serif;border-radius:4px">
        <div style="font-weight:bold;margin-bottom:1px">📝 Atestado administrativo</div>
        <div>Vinculo original verificado pelo Gerente de Projeto</div>
       </div>`
    : (certData as any).govbr_pdf
    ? `<div style="display:inline-block;background:#e8f0fe;border:1px solid #4285f4;padding:6px 12px;font-size:8px;color:#1a56db;margin:8px 0;font-family:Arial,sans-serif;border-radius:4px">
        <div style="font-weight:bold;margin-bottom:1px">🖥️ Assinado via plataforma — Contra-assinatura gov.br verificada</div>
        ${govbrSigner ? `<div>Signatario institucional: ${govbrSigner}</div>` : ''}
       </div>`
    : `<div style="display:inline-block;background:#f0fdf4;border:1px solid #86efac;padding:6px 12px;font-size:8px;color:#166534;margin:8px 0;font-family:Arial,sans-serif;border-radius:4px">
        <div style="font-weight:bold">🖥️ Assinado digitalmente via plataforma</div>
       </div>`;

  const signatureBlock = `
    <div style="margin-top:28px">
      <p style="font-size:11px;margin-bottom:16px">Goiânia/GO, ${signedDate}.</p>

      ${sourceIndicator}

      ${digitalSignatureStamp}

      <div style="margin-top:6px;padding-top:4px">
        <div style="font-size:11px;color:#333">Assinatura do Voluntário</div>
      </div>

      <div style="margin-top:32px">
        ${counterSignatureStamp}
      </div>

      <div style="margin-top:6px;padding-top:4px">
        <div style="font-size:11px;color:#333">Assinatura do Diretor do PMI Goiás</div>
      </div>
    </div>`;

  const annexBlock = `
    <div class="cert-page" style="padding:32px 40px;background:#fff;box-sizing:border-box;page-break-before:always;font-family:Georgia,serif;color:#333;min-height:842px;width:595px">
      <div style="margin-bottom:20px">
        <img src="https://nucleoia.vitormr.dev/assets/logos/pmigo.png" alt="PMI Goiás" style="height:44px;width:auto;display:block" crossorigin="anonymous" />
      </div>
      <h2 style="font-weight:bold;color:#000;font-size:16px;margin:24px 0 14px">ANEXO - LEI DO SERVIÇO VOLUNTÁRIO</h2>
      <p style="font-size:11px;color:#333;margin-bottom:4px"><b>Lei nº 9.608, de 18 de fevereiro de 1998</b></p>
      <p style="font-size:11px;color:#666;margin-bottom:20px">Dispõe sobre o serviço voluntário e dá outras providências.</p>
      <div style="font-size:11px;line-height:1.6;text-align:justify">
        <p style="margin-bottom:12px;margin-left:20px"><b>Art. 1º</b> Considera-se serviço voluntário, para fins desta Lei, a atividade não remunerada, prestada por pessoa física a entidade pública de qualquer natureza, ou a Instituição privada de fins não lucrativos, que tenha objetivos cívicos, culturais, educacionais, científicos, recreativos ou de assistência social, inclusive mutualidade.</p>
        <p style="margin-left:28px;font-style:italic;margin-bottom:12px">Parágrafo único. O serviço voluntário não gera vínculo empregatício, nem obrigação de natureza trabalhista, previdenciária ou afim.</p>
        <p style="margin-bottom:12px;margin-left:20px"><b>Art. 2º</b> O serviço voluntário será exercido mediante a celebração de Termo de Adesão entre a entidade, pública ou privada, e o prestador do serviço voluntário, dele devendo constar o objeto e as condições de seu exercício.</p>
        <p style="margin-bottom:12px;margin-left:20px"><b>Art. 3º</b> O prestador de serviço voluntário poderá ser ressarcido pelas despesas que comprovadamente realizar no desempenho das atividades voluntárias.</p>
        <p style="margin-left:28px;font-style:italic;margin-bottom:12px">Parágrafo único. As despesas a serem ressarcidas deverão estar expressamente autorizadas pela entidade a que for prestado o serviço voluntário.</p>
        <p style="margin-bottom:12px;margin-left:20px"><b>Art. 4º</b> Esta Lei entra em vigor na data de sua publicação.</p>
        <p style="margin-bottom:12px;margin-left:20px"><b>Art. 5º</b> Revogam-se as disposições em contrário.</p>
        <p style="margin-top:24px;font-size:10px;font-style:italic;color:#666;text-align:center;font-weight:bold">(Lei assinada pelo Presidente da República Fernando Henrique Cardoso, em Brasília, no dia 18 de fevereiro de 1998)</p>
      </div>
    </div>`;

  return `<div class="cert-page" style="width:595px;min-height:842px;padding:32px 40px;background:#fff;box-sizing:border-box;page-break-after:always;font-family:Georgia,serif;color:#333">
    ${headerBlock}

    <p style="font-size:11px;line-height:1.6;text-align:justify;margin-bottom:10px">
      <b>Termo de Compromisso de Voluntário com o ${certData.chapter_name || 'PMI Goiás'}</b> que fazem entre si a <b>${certData.chapter_name || 'Seção Goiânia, Goiás – Brasil do Project Management Institute (PMI Goiás)'}</b>, inscrito no CNPJ/MF sob o nº ${certData.chapter_cnpj || '06.065.645/0001-99'} e:
    </p>

    ${memberDataBlock}

    <p style="font-size:11px;line-height:1.6;text-align:justify;margin-bottom:10px">
      Doravante denominado <b>VOLUNTÁRIO</b>, com o objetivo de colaborar como voluntário ao PMI Goiás, nos projetos e processos do Capítulo${certData.function_role ? `, atuando como <b>${translateRole(certData.function_role)}</b>` : ''}.
    </p>

    <p style="font-size:11px;line-height:1.6;text-align:justify;margin-bottom:14px">
      <b>Período de atuação:</b> ${formatPeriod(certData.period_start, certData.period_end)}
    </p>

    <h3 style="font-weight:bold;color:#000;font-size:13px;margin:18px 0 10px">Termos da Adesão do Programa de Voluntariado:</h3>

    <ol style="list-style:none;padding:0;margin:0">${clausesHtml}</ol>

    ${signatureBlock}

    <div style="text-align:center;margin-top:28px;font-size:9px;color:#999">
      <div>Código: ${certData.verification_code || '—'} · Template: R3-C3</div>
      <div style="margin-top:2px">Iniciativa colaborativa entre capítulos PMI Brasil</div>
    </div>
  </div>
  ${annexBlock}`;
}

/**
 * Generate HTML for a single certificate (one A4 page).
 * Returns HTML string that can be inserted into a new window.
 * Delegates to buildVolunteerAgreementHTML for type=volunteer_agreement.
 */
export function buildCertificateHTML(certData: CertificateData): string {
  // Delegate to full legal template for volunteer_agreements
  if (certData.type === 'volunteer_agreement') {
    return buildVolunteerAgreementHTML(certData);
  }
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

  return `<div class="cert-page" style="width:595px;min-height:842px;padding:48px 40px;border:3px double #1a365d;position:relative;background:#fff;box-sizing:border-box;page-break-after:always">
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
 * Hydrate a CertificateData with data needed to render PDF.
 * For volunteer_agreement: fetches template_content from governance_documents
 * and member/counter_signer details from certificates + members tables.
 */
export async function hydrateCertData(certData: CertificateData, sb: any): Promise<CertificateData> {
  // Issuer signature
  if (certData.issued_by && !certData.signature_url && sb) {
    try {
      const { data: issuer } = await sb.from('public_members').select('signature_url').eq('id', certData.issued_by).single();
      if (issuer?.signature_url) certData.signature_url = issuer.signature_url;
    } catch {}
  }

  // For volunteer_agreement: load full legal template + extra fields
  if (certData.type === 'volunteer_agreement' && sb) {
    try {
      // Fetch full certificate row with content_snapshot
      if (certData.verification_code) {
        const { data: fullCert } = await sb
          .from('certificates')
          .select('content_snapshot, signature_hash, issued_at, counter_signed_at, counter_signed_by, member_id, source')
          .eq('verification_code', certData.verification_code)
          .maybeSingle();
        if (fullCert) {
          const snap = fullCert.content_snapshot || {};
          certData.member_email = certData.member_email || snap.member_email;
          certData.member_pmi_id = certData.member_pmi_id || snap.member_pmi_id;
          certData.member_chapter = certData.member_chapter || snap.member_chapter;
          certData.member_phone = certData.member_phone || snap.member_phone;
          certData.member_address = certData.member_address || snap.member_address;
          certData.member_city = certData.member_city || snap.member_city;
          certData.member_state = certData.member_state || snap.member_state;
          certData.member_country = certData.member_country || snap.member_country;
          certData.member_birth_date = certData.member_birth_date || snap.member_birth_date;
          certData.chapter_cnpj = certData.chapter_cnpj || snap.chapter_cnpj;
          certData.chapter_name = certData.chapter_name || snap.chapter_name;
          certData.signed_at = certData.signed_at || snap.signed_at || fullCert.issued_at;
          certData.counter_signed_at = certData.counter_signed_at || fullCert.counter_signed_at;
          (certData as any).source = (certData as any).source || fullCert.source;
          (certData as any).govbr_pdf = snap.govbr_pdf || null;
          (certData as any).govbr_institutional_signer = snap.govbr_institutional_signer || null;
          (certData as any).signed_via = snap.signed_via || null;

          // Resolve counter_signer name
          if (fullCert.counter_signed_by) {
            try {
              const { data: cs } = await sb.from('public_members').select('name').eq('id', fullCert.counter_signed_by).single();
              if (cs?.name) certData.counter_signed_by_name = cs.name;
            } catch {}
          }
        }
      }

      // Fetch active template
      const { data: tpl } = await sb
        .from('governance_documents')
        .select('content, version, title')
        .eq('doc_type', 'volunteer_term_template')
        .eq('status', 'active')
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (tpl) {
        certData.template_content = typeof tpl.content === 'string' ? JSON.parse(tpl.content) : tpl.content;
      }
    } catch (e) {
      console.warn('[pdf] failed to hydrate volunteer_agreement data:', e);
    }
  }

  return certData;
}

/**
 * Build the full HTML document wrapped with print CSS.
 * Uses a Blob URL so the browser shows the document title instead of "about:blank" in the print footer.
 */
function buildPrintDocument(title: string, innerHtml: string): string {
  return `<!DOCTYPE html><html lang="pt-BR"><head>
    <meta charset="UTF-8">
    <title>${title}</title>
    <style>
      @page{size:A4 portrait;margin:15mm 12mm 18mm 12mm}
      @media print{
        html,body{margin:0 !important;padding:0 !important;background:#fff !important;-webkit-print-color-adjust:exact;print-color-adjust:exact}
        .cert-page{box-shadow:none !important;margin:0 !important;width:auto !important;min-height:auto !important;padding:0 !important;max-width:none !important}
        .screen-only{display:none !important}
        @page{margin-header:0;margin-footer:0}
      }
      @media screen{
        body{margin:0;display:flex;flex-direction:column;align-items:center;background:#e5e7eb;padding:20px 0;font-family:Georgia,serif}
        .cert-page{box-shadow:0 4px 16px rgba(0,0,0,0.15);margin-bottom:20px}
        .screen-only{display:block;max-width:595px;width:100%;margin:0 auto 16px;padding:12px 16px;background:#fef3c7;border:1px solid #f59e0b;border-radius:8px;color:#78350f;font-family:-apple-system,system-ui,sans-serif;font-size:12px;line-height:1.5;box-shadow:0 2px 8px rgba(0,0,0,0.08)}
        .screen-only strong{color:#451a03}
        .screen-only kbd{background:#fff;border:1px solid #ccc;border-radius:3px;padding:1px 5px;font-family:monospace;font-size:11px}
      }
    </style>
  </head><body>
    <div class="screen-only">
      <strong>💡 Dica para gerar PDF limpo</strong><br>
      No diálogo de impressão, clique em <strong>"Mais configurações"</strong> e <strong>DESMARQUE</strong> a opção <strong>"Cabeçalhos e rodapés"</strong> antes de salvar como PDF — isso remove a URL <kbd>blob:…</kbd> e a data automática que o navegador adiciona.
    </div>
    ${innerHtml}
  </body></html>`;
}

/**
 * Open a new window with a single certificate PDF (ready to print).
 * Automatically hydrates template data for volunteer_agreements.
 * Uses Blob URL (instead of document.write) so the print header shows the document title
 * instead of "about:blank".
 */
export async function downloadCertificatePDF(certData: CertificateData, sb?: any): Promise<void> {
  if (sb) await hydrateCertData(certData, sb);

  const html = buildCertificateHTML(certData);
  const title = `${certData.verification_code || 'Certificate'} — ${certData.member_name}`;
  const fullDoc = buildPrintDocument(title, html);

  // Use Blob URL instead of about:blank for a cleaner print header
  const blob = new Blob([fullDoc], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const w = window.open(url, '_blank');
  if (!w) { URL.revokeObjectURL(url); return; }

  // Wait for content to load, then auto-open print dialog after 1.5s
  // (gives user time to see the instruction banner about "headers and footers")
  w.addEventListener('load', () => {
    setTimeout(() => w.print(), 1500);
  }, { once: true });
  // Cleanup blob after user closes the print dialog
  setTimeout(() => URL.revokeObjectURL(url), 120000);
}

/**
 * Open a new window with MULTIPLE certificates (one per page, ready to print).
 * Hydrates each cert (loads template for volunteer_agreements).
 * Used by bulk download in admin/certificates.
 */
export async function downloadBulkCertificatesPDF(certDataList: CertificateData[], sb?: any): Promise<void> {
  if (!certDataList.length) return;

  // Hydrate all in parallel (loads template once per volunteer_agreement)
  const hydrated = sb
    ? await Promise.all(certDataList.map(c => hydrateCertData({ ...c }, sb)))
    : certDataList;

  const allHtml = hydrated.map(buildCertificateHTML).join('');
  const title = `Certificados em lote (${hydrated.length})`;
  const fullDoc = buildPrintDocument(title, allHtml);

  const blob = new Blob([fullDoc], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const w = window.open(url, '_blank');
  if (!w) { URL.revokeObjectURL(url); return; }

  w.addEventListener('load', () => {
    setTimeout(() => w.print(), 500);
  }, { once: true });
  setTimeout(() => URL.revokeObjectURL(url), 120000);
}
