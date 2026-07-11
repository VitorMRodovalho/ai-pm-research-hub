/**
 * Shared certificate PDF generator.
 * Used by /gamification (member view) and /admin/certificates (chapter board view).
 */

import { CANONICAL_HOST, CERT_VERIFY_HOST } from "../canonical";
import { PMIGO_LOGO_DATA_URI } from "./pmigo-logo";
import { applyResidencyConditionals } from "./conditional-clauses";
import {
  NUCLEO_LOGO_DATA_URI,
  PMIGO_HOST_DATA_URI,
  NIA_FACE_DATA_URI,
  CHAPTERS_STRIP_DATA_URI,
} from "./cert-assets";

/**
 * Recognition (Ciclo 3 redesign) — the landscape, print-friendly certificate for
 * champions (excellence) and cycle-conclusion (participation). Design sign-off with
 * Vitor 2026-07-03 (docs/certificates-proposal/): A4 landscape, light ground, NIA as
 * a medallion seal, PMI-GO host + 15-chapter strip, dual GP signatures ("do Núcleo"),
 * verify URL on the chapter host. Data mapping is intentionally centralized in
 * `buildRecognitionHTML` so issuance can drive it via title (ribbon) + description
 * (pill / team) with zero DB migration.
 */
const RECOGNITION_TYPES = new Set(["excellence", "participation", "contribution", "event_participation"]);

/** Certificate types that render with the landscape recognition template. */
export function isRecognitionCert(type: string | undefined): boolean {
  return !!type && RECOGNITION_TYPES.has(type);
}

/** Page orientation for a cert type (drives @page + puppeteer/playwright pdf opts across all 3 renderers). */
export function certOrientation(type: string | undefined): "portrait" | "landscape" {
  return isRecognitionCert(type) ? "landscape" : "portrait";
}

/**
 * #1047 — Guard predicate evaluated in the headless page after `setContent` and
 * BEFORE `page.pdf()`, in BOTH renderers (scripts/backfill-cert-pdfs.ts via
 * playwright `waitForFunction`, and src/pages/api/internal/cert-pdf-render/[id].ts
 * via CF puppeteer `waitForFunction`). It resolves truthy only when every <img> on
 * the page has actually decoded (`complete && naturalWidth > 0`). If an image fails
 * (the issuer signature is still a remote signed-URL fetch; the logo is now a data
 * URI and always decodes), `waitForFunction` rejects on timeout → the render throws
 * → the cert keeps `pdf_url NULL` and stays recoverable via backfill, instead of
 * freezing a silently-defective PDF (`networkidle`/`networkidle0` do not fail on a
 * broken image). A page with no images returns true immediately (`[].every` ⇒ true),
 * so typographic certificates are unaffected. Exported so both renderers share ONE
 * source of truth and the contract test can assert on it.
 */
export const IMAGES_LOADED_PREDICATE =
  "Array.from(document.images).every(function(i){return i.complete && i.naturalWidth > 0;})";

export interface CertificateData {
  id?: string; // #648: cert id — fallback key for the frozen-PDF lookup when verification_code is absent
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
  // #1098 event guest certs (event_guest_certificates): the counter-signer member id,
  // passed directly because the certificates-table lookup inside hydrateCertData
  // cannot resolve a guest cert; and the event title for the {event} body placeholder.
  counter_signed_by?: string;
  event_title?: string;
  // Recognition certs (Ciclo 3 redesign): the co-manager counter-signature image.
  // Resolved by hydrateCertData from certificates.counter_signed_by — the image is
  // the record of a real counter-sign act, never a decorative default.
  co_signature_url?: string;
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
  // #1153 Direção 1: the approved chain-version HTML body (document_versions.content_html),
  // snapshotted immutably at signing into content_snapshot.html_body. When present, the signed
  // instrument renders from this single source of truth instead of the legacy clauseN slots.
  template_html_body?: string;
  template_version?: string; // #648: version label of the PINNED template, for the footer
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
    event_participation: 'Certificamos que',
    bodyEventParticipation: 'participou do {event}, promovido pelo Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos, iniciativa colaborativa entre capítulos do PMI no Brasil.',
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
    recoSubtitle: 'DE RECONHECIMENTO',
    hostLabel: 'CAPÍTULO-SEDE',
    fedLine: 'iniciativa colaborativa entre os capítulos do PMI no Brasil, sediada no PMI Goiás',
    chaptersLabel: 'CAPÍTULOS PMI DO BRASIL · INICIATIVA COLABORATIVA',
    teamLabel: 'TIME RECONHECIDO',
    lifetime: 'Reconhecimento vitalício',
    roleGestor: 'Gestor do Núcleo',
    roleCoGestor: 'Co-Gestor do Núcleo',
    verifyCode: 'Código de verificação',
    issuedOn: 'Emitido em',
    verifyAt: 'Verifique em',
    bodyExcellenceLifetime: 'recebeu o reconhecimento de Excelência (Hall da Lenda) pela trajetória acumulada de contribuições ao Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos ao longo dos ciclos.',
    bodyConclusion: 'participou como pesquisador(a) voluntário(a) do Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gerenciamento de Projetos e concluiu o ciclo de pesquisa, contribuindo com as iniciativas colaborativas entre os capítulos do PMI no Brasil.',
  },
  'en-US': {
    participation: 'This certifies that',
    contribution: 'This certifies that',
    completion: 'This certifies that',
    excellence: 'This certifies that',
    volunteer_agreement: 'This declares that',
    event_participation: 'This certifies that',
    bodyEventParticipation: 'attended {event}, hosted by the AI & PM Study and Research Hub, a collaborative initiative among PMI chapters in Brazil.',
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
    recoSubtitle: 'OF RECOGNITION',
    hostLabel: 'HOST CHAPTER',
    fedLine: 'a collaborative initiative among PMI chapters in Brazil, hosted by PMI Goiás',
    chaptersLabel: 'PMI CHAPTERS OF BRAZIL · COLLABORATIVE INITIATIVE',
    teamLabel: 'RECOGNIZED TEAM',
    lifetime: 'Lifetime recognition',
    roleGestor: 'Núcleo Manager',
    roleCoGestor: 'Núcleo Co-Manager',
    verifyCode: 'Verification code',
    issuedOn: 'Issued on',
    verifyAt: 'Verify at',
    bodyExcellenceLifetime: 'received the Excellence recognition (Hall of Legends) for the accumulated trajectory of contributions to the AI & PM Study and Research Hub across cycles.',
    bodyConclusion: 'served as a volunteer researcher at the AI & PM Study and Research Hub and completed the research cycle, contributing to the collaborative initiatives among PMI chapters in Brazil.',
  },
  'es-LATAM': {
    participation: 'Se certifica que',
    contribution: 'Se certifica que',
    completion: 'Se certifica que',
    excellence: 'Se certifica que',
    volunteer_agreement: 'Se declara que',
    event_participation: 'Se certifica que',
    bodyEventParticipation: 'participó en {event}, promovido por el Hub de Estudios e Investigación en Inteligencia Artificial y Gestión de Proyectos, una iniciativa colaborativa entre capítulos del PMI en Brasil.',
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
    recoSubtitle: 'DE RECONOCIMIENTO',
    hostLabel: 'CAPÍTULO SEDE',
    fedLine: 'iniciativa colaborativa entre los capítulos del PMI en Brasil, con sede en PMI Goiás',
    chaptersLabel: 'CAPÍTULOS PMI DE BRASIL · INICIATIVA COLABORATIVA',
    teamLabel: 'EQUIPO RECONOCIDO',
    lifetime: 'Reconocimiento vitalicio',
    roleGestor: 'Gestor del Núcleo',
    roleCoGestor: 'Co-Gestor del Núcleo',
    verifyCode: 'Código de verificación',
    issuedOn: 'Emitido el',
    verifyAt: 'Verifique en',
    bodyExcellenceLifetime: 'recibió el reconocimiento de Excelencia (Salón de la Leyenda) por la trayectoria acumulada de contribuciones al Núcleo de Estudios e Investigación en IA y Gestión de Proyectos a lo largo de los ciclos.',
    bodyConclusion: 'participó como investigador(a) voluntario(a) del Núcleo de Estudios e Investigación en IA y Gestión de Proyectos y concluyó el ciclo de investigación, contribuyendo con las iniciativas colaborativas entre los capítulos del PMI en Brasil.',
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
  // #1153 Direção 1: prefer the approved chain-version HTML body (single source of truth,
  // frozen at signing). When present, the signed instrument renders from it instead of the
  // legacy clauseN slots.
  const approvedBody = (typeof certData.template_html_body === 'string' && certData.template_html_body.trim())
    ? certData.template_html_body.trim() : '';
  const hasApprovedBody = approvedBody.length > 0;
  // #648 — fail LOUD instead of silently rendering blank clauses. A signed term must never
  // re-render without its agreed text. hydrateCertData resolves the body from the immutable
  // per-cert snapshot (the approved HTML body #1153, or the legacy clause slots #648). If
  // NEITHER resolves, the document cannot be faithfully reconstructed, so we refuse rather
  // than emit a blank legal instrument (the download path serves the frozen PDF first).
  if (!hasApprovedBody && (!c || typeof c !== 'object' || Array.isArray(c) || !(c as any).clause1)) {
    throw new Error(
      `volunteer_agreement_template_unavailable: missing clause snapshot for cert ` +
      `${certData.verification_code || '(unknown)'} — refusing to render a blank signed term (#648)`
    );
  }
  // Defensive {chapterName} resolution (the RPC already resolves it at snapshot time; this
  // covers any legacy/edge body). Mirrors the SQL: short parenthetical form of the legal name.
  const chapterInline = (() => {
    const cn = certData.chapter_name || 'PMI Goiás';
    const m = cn.match(/\(([^)]+)\)\s*$/);
    return m ? m[1] : cn;
  })();
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

  // Header with PMI-GO logo (same reference as the example PDF).
  const logoBlock = `
    <div style="margin-bottom:20px">
      <img src="${PMIGO_LOGO_DATA_URI}" alt="PMI Goiás" style="height:52px;width:auto;display:block" />
    </div>`;
  // The legacy slot path keeps its own chrome title; the Direção 1 approved body carries its
  // own document title (<h2>Termo de Adesão…</h2>), so the chrome h1 is dropped there to avoid
  // a duplicate heading.
  const titleH1 = hasApprovedBody ? '' : `
    <h1 style="text-align:center;font-size:18px;font-weight:bold;color:#000;margin:20px 0 28px;letter-spacing:0.5px;line-height:1.3">
      TERMO DE COMPROMISSO DE<br/>VOLUNTÁRIO COM O PMI GOIÁS
    </h1>`;
  const headerBlock = `${logoBlock}${titleH1}`;

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

  // #1153 Direção 1: the legal body is the approved chain-version HTML (single source of
  // truth), rendered as-is (governance content is admin-authored and chain-approved). The
  // legacy slot path (already-signed certs whose snapshot has clauseN but no html_body) keeps
  // its "Termos da Adesão" heading + <ol> so #648 immutability is preserved verbatim.
  // #1156 (F3 de #1153): Clause 14 (Transferência Internacional de Dados) is CONDITIONAL per
  // the .docx V2 — it applies only to volunteers resident in the EEA/EEE or the UK. Render-time
  // decision on the frozen body: a non-EEE/UK volunteer's instrument omits it; the immutable
  // snapshot keeps the full superset. Derived from the (snapshotted) member_country, so it is
  // stable across re-renders. No-op for BR/legacy bodies without the clause.
  const scopedBody = applyResidencyConditionals(approvedBody, certData.member_country);
  const legalSection = hasApprovedBody
    ? `<div class="gov-approved-body" style="font-size:11px;line-height:1.6;text-align:justify">${scopedBody.replace(/\{chapterName\}/g, chapterInline)}</div>`
    : `<h3 style="font-weight:bold;color:#000;font-size:13px;margin:18px 0 10px">Termos da Adesão do Programa de Voluntariado:</h3>

    <ol style="list-style:none;padding:0;margin:0">${clausesHtml}</ol>`;

  const signedDate = certData.signed_at ? formatLongDate(certData.signed_at) : formatLongDate(new Date().toISOString());
  const counterSignedDate = certData.counter_signed_at ? formatLongDate(certData.counter_signed_at) : null;

  // Digital signature stamp (equivalent to gov.br style in the reference)
  const digitalSignatureStamp = `
    <div style="display:inline-block;background:#f5f5f5;border:1px solid #ccc;padding:10px 14px;font-size:9px;color:#444;margin:12px 0;font-family:Arial,sans-serif">
      <div style="font-weight:bold;color:#1a365d;margin-bottom:2px">🔏 Documento assinado digitalmente</div>
      <div><b>${(certData.member_name || '').toUpperCase()}</b></div>
      <div>Data: ${certData.signed_at ? new Date(certData.signed_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'medium' }) : '—'}</div>
      <div>Código: ${certData.verification_code || '—'}</div>
      <div style="color:#1a5490">Verifique em ${CANONICAL_HOST}/verify/${certData.verification_code || ''}</div>
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
        <img src="${PMIGO_LOGO_DATA_URI}" alt="PMI Goiás" style="height:44px;width:auto;display:block" />
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
      <b>Termo de Adesão ao Serviço Voluntário com o ${chapterInline}</b> que fazem entre si a <b>${certData.chapter_name || 'Seção Goiânia, Goiás – Brasil do Project Management Institute (PMI Goiás)'}</b>, inscrito no CNPJ/MF sob o nº ${certData.chapter_cnpj || '06.065.645/0001-99'} e:
    </p>

    ${memberDataBlock}

    <p style="font-size:11px;line-height:1.6;text-align:justify;margin-bottom:10px">
      Doravante denominado <b>VOLUNTÁRIO</b>, com o objetivo de colaborar como voluntário ao PMI Goiás, nos projetos e processos do Capítulo${certData.function_role ? `, atuando como <b>${translateRole(certData.function_role)}</b>` : ''}.
    </p>

    <p style="font-size:11px;line-height:1.6;text-align:justify;margin-bottom:14px">
      <b>Período de atuação:</b> ${formatPeriod(certData.period_start, certData.period_end)}
    </p>

    ${legalSection}

    ${signatureBlock}

    <div style="text-align:center;margin-top:28px;font-size:9px;color:#999">
      <div>Código: ${certData.verification_code || '—'} · Template: ${certData.template_version || 'R3-C3'}</div>
      <div style="margin-top:2px">Iniciativa colaborativa entre capítulos PMI Brasil</div>
    </div>
  </div>
  ${annexBlock}`;
}

/** Short badge label inside the NIA medallion seal, derived from the ribbon (title). */
function recoSealLabel(title: string | undefined): string {
  const t = (title || '').toUpperCase();
  if (/VITAL|LENDA|LIFETIME/.test(t)) return 'LENDA';
  if (/TRIBO|TRIBE|EQUIPO/.test(t)) return 'TRIBO';
  if (/CONCLUS/.test(t)) return 'CONCLUSÃO';
  if (/AFTERSHOW|EVENTO|EVENT|COMMUNITY DAY/.test(t)) return 'EVENTO';
  const m = t.match(/CICLO\s*(\d+)/);
  if (m) return 'CICLO ' + m[1];
  return 'NÚCLEO';
}

/** dd/mm/yyyy (issuance date printed on the recognition cert). */
function formatShortDate(date: string | undefined): string {
  const dt = date
    ? new Date(String(date).length === 10 ? String(date) + 'T12:00:00' : date)
    : new Date();
  if (isNaN(dt.getTime())) return '';
  return `${dt.getDate().toString().padStart(2, '0')}/${(dt.getMonth() + 1)
    .toString().padStart(2, '0')}/${dt.getFullYear()}`;
}

/**
 * Landscape, print-friendly RECOGNITION certificate (Ciclo 3 redesign).
 * DATA MAPPING (centralized here so issuance drives it with no DB migration):
 *   - title       → the category ribbon headline (e.g. "TOP 5 DO CICLO 3 · RANKING INDIVIDUAL")
 *   - description  → line 1 = the highlight pill ("1º lugar · … · 547 pontos");
 *                    remaining lines = the recognized team (tribe certs)
 *   - type         → body text (bodyExcellence / bodyParticipation) via the i18n dict
 *   - seal label   → derived from the title (recoSealLabel)
 *   - verify host  → CERT_VERIFY_HOST (chapter-institutional domain)
 * Signatories are the two fixed Núcleo leads (Gestor + Co-Gestor). All strings i18n'd.
 */
export function buildRecognitionHTML(certData: CertificateData): string {
  const lang = certData.language || 'pt-BR';
  const tpl = TEMPLATES[lang] || TEMPLATES['pt-BR'];
  const type = certData.type || 'excellence';

  const ribbon = certData.title || tpl.title;
  const certifyThat = tpl[type] || tpl.participation;
  const isLifetime = /VITAL|LENDA/.test((certData.title || '').toUpperCase());
  // Category-specific body (matches the approved mockup): cycle conclusion and lifetime
  // champions get their own sentence; everyone else uses the type's default body.
  const bodyDefault = tpl['body' + type.charAt(0).toUpperCase() + type.slice(1)] || tpl.bodyExcellence;
  const bodyText = (
    type === 'event_participation' ? (tpl.bodyEventParticipation || tpl.bodyParticipation) :
    type === 'participation' ? tpl.bodyConclusion :
    isLifetime ? tpl.bodyExcellenceLifetime :
    bodyDefault
  ).replace('{role}', certData.function_role || '')
   .replace('{event}', certData.event_title || certData.title || '');

  // description convention: line 1 = highlight/pill; remaining lines = recognized team
  const lines = (certData.description || '').split('\n').map(s => s.trim()).filter(Boolean);
  const pill = lines[0] || '';
  const team = lines.slice(1).join(' · ');

  const sealLabel = recoSealLabel(certData.title);
  const period = formatPeriod(certData.period_start, certData.period_end);
  const metaLine = period !== '—' ? period : (isLifetime ? tpl.lifetime : '');

  const code = certData.verification_code || '';
  const issued = formatShortDate(certData.signed_at || (certData as any).issued_at);
  const verifyLine = `${tpl.verifyCode}: ${code || '—'} · ${tpl.issuedOn} ${issued} · ${tpl.verifyAt} ${CERT_VERIFY_HOST}/verify/${code}`;

  const pillHtml = pill ? `<div class="rc-pill">${pill}</div>` : '';
  const teamHtml = team ? `<div class="rc-teamlabel">${tpl.teamLabel}</div><div class="rc-team">${team}</div>` : '';
  const metaHtml = metaLine ? `<div class="rc-meta">${metaLine}</div>` : '';
  // Dual handwriting images (approved mockup): issuer (GP) + counter-signer (Co-GP).
  // Absent URL degrades to the plain line+name — never a broken <img> (the #1047
  // render guard would otherwise hold the PDF hostage on a dead src).
  const gpSigImg = certData.signature_url ? `<img class="rc-sigimg" src="${certData.signature_url}" alt="" />` : '';
  const coGpSigImg = certData.co_signature_url ? `<img class="rc-sigimg" src="${certData.co_signature_url}" alt="" />` : '';

  const css = `
    .rc-page{position:relative;width:297mm;height:210mm;background:#FCFBF9;box-sizing:border-box;padding:14mm 18mm;overflow:hidden;page-break-after:always;font-family:Georgia,'Times New Roman','Liberation Serif',serif;color:#25313f}
    .rc-frame{position:absolute;inset:8mm;border:1.4px solid #461DA3}
    .rc-frame::after{content:"";position:absolute;inset:1.3mm;border:0.6px solid #b9a24e}
    .rc-wm{position:absolute;width:110mm;left:50%;top:50%;transform:translate(-50%,-50%);opacity:0.028;filter:grayscale(1)}
    .rc-head{position:relative;display:flex;justify-content:space-between;align-items:flex-start;z-index:2}
    .rc-nlogo{height:20mm;width:auto}
    .rc-hostwrap{text-align:center}
    .rc-eyebrow{font-family:Arial,Helvetica,sans-serif;font-size:7pt;letter-spacing:2.5px;color:#7a6a3e;margin-bottom:2mm}
    .rc-host{height:13mm;width:auto}
    .rc-fed{position:relative;z-index:2;text-align:center;margin-top:1mm;font-size:8.5pt;color:#6b7480;font-style:italic}
    .rc-body{position:relative;z-index:2;text-align:center;margin-top:3mm}
    .rc-ribbon{display:inline-block;background:#fff;border:1.2px solid #b9a24e;color:#1a365d;font-family:Arial,Helvetica,sans-serif;font-weight:700;font-size:9.5pt;letter-spacing:1.5px;padding:2mm 7mm;border-radius:1mm}
    .rc-title{font-size:30pt;font-weight:700;color:#1a365d;letter-spacing:9px;margin:5mm 0 0}
    .rc-subtitle{font-family:Arial,Helvetica,sans-serif;font-size:9.5pt;letter-spacing:6px;color:#8792a0;margin-top:1mm}
    .rc-que{font-size:12.5pt;font-style:italic;color:#6b7480;margin-top:5mm}
    .rc-name{font-size:27pt;font-weight:700;color:#1a365d;margin-top:2mm}
    .rc-pill{display:inline-block;margin-top:4mm;background:#F6F2FB;border:1.2px solid #461DA3;color:#2c2150;font-family:Arial,Helvetica,sans-serif;font-weight:700;font-size:11pt;padding:2.2mm 7mm;border-radius:6mm}
    .rc-text{max-width:172mm;margin:5mm auto 0;font-size:12.5pt;line-height:1.7;color:#3a4654}
    .rc-teamlabel{font-family:Arial,Helvetica,sans-serif;font-size:8pt;letter-spacing:3px;color:#8792a0;margin-top:4mm}
    .rc-team{font-size:11.5pt;color:#2c3644;margin-top:1mm}
    .rc-meta{font-size:10pt;color:#8792a0;margin-top:4mm}
    .rc-seal{position:absolute;right:22mm;top:43%;transform:translateY(-50%);z-index:2;width:34mm;text-align:center}
    .rc-medal{width:30mm;height:30mm;margin:0 auto;border-radius:50%;overflow:hidden;background:radial-gradient(circle at 50% 38%,#fdfaf0,#f0e6c6);border:1.6px solid #b0892e;box-shadow:0 0 0 1.1mm #FCFBF9,0 0 0 1.5mm #d9c98f;display:flex;align-items:flex-end;justify-content:center}
    .rc-nia{width:24mm;height:auto;margin-bottom:0.5mm}
    .rc-ribbon2{display:inline-block;margin-top:2.4mm;background:#1a365d;color:#f3e6c4;font-family:Arial,Helvetica,sans-serif;font-size:7.5pt;font-weight:700;letter-spacing:1.5px;padding:1.3mm 4.5mm;border-radius:1mm}
    .rc-bottom{position:absolute;left:0;right:0;bottom:11mm;text-align:center;z-index:2}
    .rc-signs{display:flex;justify-content:center;gap:44mm}
    .rc-sig{text-align:center;width:70mm}
    .rc-sigimg{display:block;max-height:12mm;max-width:50mm;margin:0 auto 0.6mm}
    .rc-sigline{border-top:1px solid #4a5563;width:62mm;margin:0 auto 1.5mm}
    .rc-signame{font-size:11.5pt;font-weight:700;color:#1a365d}
    .rc-sigrole{font-family:Arial,Helvetica,sans-serif;font-size:8.5pt;color:#7a8390}
    .rc-chapband{margin-top:6mm}
    .rc-chaplabel{font-family:Arial,Helvetica,sans-serif;font-size:6.5pt;letter-spacing:2.5px;color:#9aa2ac;margin-bottom:2mm}
    .rc-chapstrip{height:9mm;width:auto;max-width:250mm}
    .rc-verify{font-family:Arial,Helvetica,sans-serif;font-size:8pt;color:#8792a0;margin-top:4mm}
    .rc-disc{font-family:Arial,Helvetica,sans-serif;font-size:7pt;color:#b3bac3;margin-top:1mm}
  `;

  return `<style>${css}</style>
  <div class="rc-page">
    <div class="rc-frame"></div>
    <img class="rc-wm" src="${NUCLEO_LOGO_DATA_URI}" alt="" />
    <header class="rc-head">
      <img class="rc-nlogo" src="${NUCLEO_LOGO_DATA_URI}" alt="Núcleo IA & GP" />
      <div class="rc-hostwrap"><div class="rc-eyebrow">${tpl.hostLabel}</div><img class="rc-host" src="${PMIGO_HOST_DATA_URI}" alt="PMI Goiás" /></div>
    </header>
    <div class="rc-fed">${tpl.fedLine}</div>
    <div class="rc-body">
      <div class="rc-ribbon">★ ${ribbon}</div>
      <h1 class="rc-title">${tpl.title}</h1>
      <div class="rc-subtitle">${tpl.recoSubtitle}</div>
      <div class="rc-que">${certifyThat}</div>
      <div class="rc-name">${certData.member_name || ''}</div>
      ${pillHtml}
      <p class="rc-text">${bodyText}</p>
      ${teamHtml}
      ${metaHtml}
    </div>
    <div class="rc-seal"><div class="rc-medal"><img class="rc-nia" src="${NIA_FACE_DATA_URI}" alt="NIA" /></div><div class="rc-ribbon2">${sealLabel}</div></div>
    <div class="rc-bottom">
      <div class="rc-signs">
        <div class="rc-sig">${gpSigImg}<div class="rc-sigline"></div><div class="rc-signame">Vitor Maia Rodovalho, PMP</div><div class="rc-sigrole">${tpl.roleGestor}</div></div>
        <div class="rc-sig">${coGpSigImg}<div class="rc-sigline"></div><div class="rc-signame">Fabricio R. C. Costa</div><div class="rc-sigrole">${tpl.roleCoGestor}</div></div>
      </div>
      <div class="rc-chapband"><div class="rc-chaplabel">${tpl.chaptersLabel}</div><img class="rc-chapstrip" src="${CHAPTERS_STRIP_DATA_URI}" alt="" /></div>
      <div class="rc-verify">${verifyLine}</div>
      <div class="rc-disc">${tpl.disclaimer}</div>
    </div>
  </div>`;
}

/**
 * Generate HTML for a single certificate (one A4 page).
 * Returns HTML string that can be inserted into a new window.
 * Delegates to buildVolunteerAgreementHTML for type=volunteer_agreement,
 * and to buildRecognitionHTML (landscape) for the Ciclo 3 recognition types.
 */
export function buildCertificateHTML(certData: CertificateData): string {
  // Delegate to full legal template for volunteer_agreements
  if (certData.type === 'volunteer_agreement') {
    return buildVolunteerAgreementHTML(certData);
  }
  // Delegate to the landscape recognition template (champions + cycle conclusion)
  if (isRecognitionCert(certData.type)) {
    return buildRecognitionHTML(certData);
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
    ? `<img src="${certData.signature_url}" style="max-width:180px;max-height:60px;margin-bottom:4px">`
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
/**
 * Resolve a member's handwriting signature to a short-TTL SIGNED URL — #753 P1:
 * member-signatures is a PRIVATE bucket; the stored value (a public-URL string
 * carrying the path, or a bare path) must become self-authorizing because the
 * <img> fetch is anonymous in both the client browser-print and the server-side
 * puppeteer networkidle0 render. The path is resolved via the gated
 * get_signer_signature_url RPC (signer-scoped, #1052 — signature_url was removed
 * from public_members because its storage path embeds the member's email), then signed.
 */
async function resolveMemberSignatureUrl(sb: any, memberId: string): Promise<string | undefined> {
  try {
    const { data: raw } = await sb.rpc('get_signer_signature_url', { p_signer_id: memberId });
    const sig = raw as string | undefined;
    if (!sig) return undefined;
    const after = sig.split('/member-signatures/')[1];
    const sigPath = after ? decodeURIComponent(after.split('?')[0]) : sig.replace(/^\/+/, '');
    const { data: signed } = await sb.storage.from('member-signatures').createSignedUrl(sigPath, 600);
    return signed?.signedUrl || undefined;
  } catch {
    return undefined;
  }
}

export async function hydrateCertData(certData: CertificateData, sb: any): Promise<CertificateData> {
  // Identity backfill — the CLIENT print path (certificates.astro blob view) passes a
  // thin payload (member_name: '', no issued_by), so the browser render used to drop
  // the member name AND the issuer signature while the server renders carried both
  // (owner report 2026-07-03). One consolidated cert-row fetch feeds member name,
  // issuer signature and the counter-signer, so every renderer shows the SAME cert.
  let certRow: { member_id?: string; issued_by?: string; counter_signed_by?: string } | null = null;
  const needsRow = !certData.member_name || !certData.issued_by || (isRecognitionCert(certData.type) && !certData.co_signature_url);
  if (sb && needsRow && (certData.verification_code || certData.id)) {
    try {
      const keyCol = certData.verification_code ? 'verification_code' : 'id';
      const { data: row } = await sb
        .from('certificates')
        .select('member_id, issued_by, counter_signed_by')
        .eq(keyCol, keyCol === 'verification_code' ? certData.verification_code : certData.id)
        .maybeSingle();
      certRow = row || null;
      if (certRow?.issued_by && !certData.issued_by) certData.issued_by = certRow.issued_by;
      if (certRow?.member_id && !certData.member_name) {
        const { data: m } = await sb.from('public_members').select('name').eq('id', certRow.member_id).single();
        if (m?.name) certData.member_name = m.name;
      }
    } catch {}
  }

  // Issuer signature (GP) — see resolveMemberSignatureUrl.
  if (certData.issued_by && !certData.signature_url && sb) {
    certData.signature_url = await resolveMemberSignatureUrl(sb, certData.issued_by);
  }

  // Recognition certs (Ciclo 3 mockup): dual signatures. The co-image belongs to the
  // member who ACTUALLY counter-signed (certificates.counter_signed_by) — resolved only
  // when that act exists; an un-counter-signed cert renders the plain line + name.
  if (isRecognitionCert(certData.type) && !certData.co_signature_url && sb) {
    // Member certs keep resolving ONLY from the DB row (the image is the record of a
    // real counter-sign act); the direct-field fallback exists solely for guest certs,
    // which have no certificates row for the lookup above to find.
    const coSigner = certRow?.counter_signed_by
      || (certData.type === 'event_participation' ? certData.counter_signed_by : undefined);
    if (coSigner) {
      certData.co_signature_url = await resolveMemberSignatureUrl(sb, coSigner);
    }
  }

  // For volunteer_agreement: load full legal template + extra fields
  if (certData.type === 'volunteer_agreement' && sb) {
    try {
      // Fetch full certificate row with content_snapshot
      if (certData.verification_code) {
        const { data: fullCert } = await sb
          .from('certificates')
          .select('content_snapshot, signature_hash, issued_at, counter_signed_at, counter_signed_by, member_id, source, template_id')
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

          // #648 — IMMUTABILITY: resolve the clause body as PINNED at signing, NEVER the
          // live `status='active'` template (which is null while the term is on HOLD →
          // blank clauses, and would retroactively rewrite signed terms after any
          // revision). Order of precedence:
          //   (1) the clause snapshot stored on the cert at signing (content_snapshot.clauses);
          //   (2) the exact template version pinned on the cert (template_id), regardless
          //       of its current lifecycle status.
          // If neither resolves, template_content stays undefined and
          // buildVolunteerAgreementHTML throws rather than emit a blank instrument.
          certData.template_version = certData.template_version || snap.body_version_label || snap.template_version;
          // #1153 Direção 1: the frozen approved HTML body is the single source of truth for
          // the signed instrument. Resolved from the immutable snapshot only (never a live
          // template query — that would reintroduce the #648 drift the guard forbids).
          certData.template_html_body = certData.template_html_body || snap.html_body;
          const snapClauses = snap.clauses;
          if (snapClauses && typeof snapClauses === 'object' && !Array.isArray(snapClauses) && snapClauses.clause1) {
            certData.template_content = snapClauses;
          } else if (fullCert.template_id) {
            const { data: tpl } = await sb
              .from('governance_documents')
              .select('content, version, title')
              .eq('id', fullCert.template_id)
              .maybeSingle();
            if (tpl?.content) {
              certData.template_content = typeof tpl.content === 'string' ? JSON.parse(tpl.content) : tpl.content;
              certData.template_version = certData.template_version || tpl.version;
            }
          }
        }
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
function buildPrintDocument(title: string, innerHtml: string, orientation: 'portrait' | 'landscape' = 'portrait'): string {
  // Recognition certs are full-bleed A4 landscape (@page margin:0); the .rc-page div
  // owns its own 297x210mm sizing so the portrait `.cert-page` print overrides below
  // (width auto / padding 0) must NOT touch it — they are class-scoped to .cert-page.
  const pageRule = orientation === 'landscape'
    ? '@page{size:A4 landscape;margin:0}'
    : '@page{size:A4 portrait;margin:15mm 12mm 18mm 12mm}';
  return `<!DOCTYPE html><html lang="pt-BR"><head>
    <meta charset="UTF-8">
    <title>${title}</title>
    <style>
      ${pageRule}
      @media print{
        html,body{margin:0 !important;padding:0 !important;background:#fff !important;-webkit-print-color-adjust:exact;print-color-adjust:exact}
        .cert-page{box-shadow:none !important;margin:0 !important;width:auto !important;min-height:auto !important;padding:0 !important;max-width:none !important}
        .screen-only{display:none !important}
        @page{margin-header:0;margin-footer:0}
      }
      @media screen{
        body{margin:0;display:flex;flex-direction:column;align-items:center;background:#e5e7eb;padding:20px 0;font-family:Georgia,serif}
        .cert-page{box-shadow:0 4px 16px rgba(0,0,0,0.15);margin-bottom:20px}
        .rc-page{box-shadow:0 4px 16px rgba(0,0,0,0.15);margin-bottom:20px}
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
  // #648 Camada 3 — for a SIGNED volunteer agreement, serve the FROZEN immutable PDF
  // (rendered at signing time into the private 'certificates' bucket) instead of
  // rebuilding it live. This is the byte-exact legal artifact; the rebuild below is the
  // immutable fallback (now resolves clauses from the per-cert snapshot, never the live
  // 'active' template). Falls through to rebuild if no frozen PDF / storage denies.
  if (sb && certData.type === 'volunteer_agreement' && (certData.verification_code || (certData as any).id)) {
    try {
      let q = sb.from('certificates').select('pdf_url');
      q = certData.verification_code
        ? q.eq('verification_code', certData.verification_code)
        : q.eq('id', (certData as any).id);
      const { data: row } = await q.maybeSingle();
      if (row?.pdf_url) {
        const { data: signed } = await sb.storage.from('certificates').createSignedUrl(row.pdf_url, 300);
        if (signed?.signedUrl) { window.open(signed.signedUrl, '_blank'); return; }
      }
    } catch (e) {
      console.warn('[pdf] frozen volunteer-agreement serve failed; falling back to rebuild', e);
    }
  }

  if (sb) await hydrateCertData(certData, sb);

  const html = buildCertificateHTML(certData);
  const title = `${certData.verification_code || 'Certificate'} — ${certData.member_name}`;
  const fullDoc = buildPrintDocument(title, html, certOrientation(certData.type));

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

  // #648 — buildCertificateHTML now throws for a volunteer agreement whose clause
  // snapshot is unavailable (rather than emitting a blank instrument). In a bulk run,
  // skip such a cert instead of failing the whole batch.
  const allHtml = hydrated.map(cd => {
    try { return buildCertificateHTML(cd); }
    catch (e) { console.warn('[pdf] skipping cert in bulk render', (cd as any)?.verification_code, e); return ''; }
  }).join('');
  const title = `Certificados em lote (${hydrated.length})`;
  // A print document has ONE @page orientation. When every cert in the batch is a
  // recognition cert, render the batch landscape; otherwise keep portrait (mixed
  // batches fall back to portrait — the admin champions batch is all-excellence).
  const landscape = hydrated.length > 0 && hydrated.every(cd => isRecognitionCert(cd.type));
  const fullDoc = buildPrintDocument(title, allHtml, landscape ? 'landscape' : 'portrait');

  const blob = new Blob([fullDoc], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const w = window.open(url, '_blank');
  if (!w) { URL.revokeObjectURL(url); return; }

  w.addEventListener('load', () => {
    setTimeout(() => w.print(), 500);
  }, { once: true });
  setTimeout(() => URL.revokeObjectURL(url), 120000);
}
