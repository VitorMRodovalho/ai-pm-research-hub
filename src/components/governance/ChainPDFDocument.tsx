/**
 * ChainPDFDocument — IP-4 Chunk 2 (revisado p93c)
 *
 * Renderiza uma approval_chain como PDF via @react-pdf/renderer.
 *
 * Modos:
 *   - 'official' (default): página de assinaturas + audit footer.
 *     Use quando chain.status='active' (versão oficial) OU para imprimir
 *     status atual da revisão com evidências parciais.
 *   - 'draft': sem página de assinaturas, com watermark "RASCUNHO" em
 *     cada página. Para revisores baixarem leitura offline antes de assinar.
 *
 * Parser HTML (p93c):
 *   - Suporta H2/H3/H4, P, LI, BLOCKQUOTE
 *   - Inline: STRONG/B (bold), EM/I (italic), A (link com URL preservado),
 *     BR (newline)
 *   - Blockquote envolve parágrafos com border-left + indent
 *   - Glossário <li><strong>Termo.</strong> definição</li> renderiza com
 *     termo em bold via Text spans
 */
import { Document, Page, Text, View, StyleSheet, Font } from '@react-pdf/renderer';

// Disable react-pdf default hyphenation (hyphen library) — em docs jurídicos
// PT-BR queremos palavras inteiras: "Propriedade Intelectual" não "Pro-priedade".
// Callback retorna array com 1 elemento = 0 split points = sem hifenização.
Font.registerHyphenationCallback((word) => [word]);

const styles = StyleSheet.create({
  page: { padding: 40, fontSize: 10, fontFamily: 'Helvetica', color: '#1a1a1a' },
  draftBanner: {
    backgroundColor: '#fef3c7',
    borderTop: '2px solid #f59e0b',
    borderBottom: '2px solid #f59e0b',
    paddingTop: 5,
    paddingBottom: 5,
    paddingLeft: 8,
    paddingRight: 8,
    marginBottom: 12,
  },
  draftBannerText: {
    fontSize: 10,
    fontWeight: 'bold',
    color: '#92400e',
    textAlign: 'center',
  },
  headerBar: { borderBottom: '2px solid #003B5C', paddingBottom: 8, marginBottom: 16 },
  orgName: { fontSize: 11, fontWeight: 'bold', color: '#003B5C' },
  orgTag: { fontSize: 9, color: '#6c757d', marginTop: 2 },
  docTitle: { fontSize: 18, fontWeight: 'bold', marginTop: 20, marginBottom: 6, color: '#003B5C' },
  docMeta: { fontSize: 10, color: '#495057', marginBottom: 4 },
  statusBadge: { padding: 4, backgroundColor: '#fef3c7', color: '#92400e', fontSize: 9, fontWeight: 'bold', borderRadius: 3, alignSelf: 'flex-start' },
  sectionTitle: { fontSize: 13, fontWeight: 'bold', marginTop: 16, marginBottom: 8, color: '#003B5C' },
  paragraph: { fontSize: 10, marginBottom: 6, lineHeight: 1.4, textAlign: 'justify' },
  h2: { fontSize: 14, fontWeight: 'bold', marginTop: 16, marginBottom: 8, color: '#003B5C' },
  h3: { fontSize: 12, fontWeight: 'bold', marginTop: 12, marginBottom: 6, color: '#003B5C' },
  h4: { fontSize: 11, fontWeight: 'bold', marginTop: 10, marginBottom: 5 },
  listItem: { fontSize: 10, marginBottom: 4, marginLeft: 12, lineHeight: 1.4 },
  blockquoteWrapper: {
    borderLeft: '3px solid #6c757d',
    backgroundColor: '#f8f9fa',
    paddingTop: 6,
    paddingBottom: 6,
    paddingLeft: 12,
    paddingRight: 8,
    marginTop: 6,
    marginBottom: 8,
  },
  link: { color: '#0066cc', textDecoration: 'underline' },
  linkUrl: { fontSize: 8, color: '#6c757d' },
  gateBlock: { marginBottom: 10, padding: 8, borderLeft: '3px solid #003B5C', backgroundColor: '#f8f9fa' },
  gateHeader: { fontSize: 11, fontWeight: 'bold', marginBottom: 4 },
  gateMeta: { fontSize: 9, color: '#6c757d', marginBottom: 6 },
  signerRow: { flexDirection: 'row', marginBottom: 2, fontSize: 9 },
  signerCol: { flexGrow: 1 },
  signerName: { fontWeight: 'bold', fontSize: 9 },
  signerDetail: { fontSize: 8, color: '#495057' },
  evidenceBadge: { fontSize: 8, color: '#10b981', marginTop: 1 },
  noSigners: { fontSize: 9, color: '#a0a0a0', fontStyle: 'italic' },
  footer: { marginTop: 20, paddingTop: 10, borderTop: '1px solid #dee2e6' },
  footerText: { fontSize: 8, color: '#6c757d', marginBottom: 2 },
  hashBlock: { fontSize: 7, fontFamily: 'Courier', color: '#495057', marginTop: 4 },
});

export type ChainData = {
  chain_id: string;
  chain_status: string;
  chain_opened_at: string;
  chain_approved_at: string | null;
  chain_closed_at: string | null;
  chain_notes?: string;
  document: {
    id: string;
    title: string;
    doc_type: string;
    status: string;
    description?: string;
  };
  version: {
    id: string;
    number: number;
    label: string;
    content_html: string;
    locked_at: string;
    published_at: string;
    notes?: string;
  };
  submitter: {
    id: string;
    name: string;
    email: string;
    chapter: string;
    role: string;
  };
  gates: Array<{
    kind: string;
    order: number;
    threshold: string | number;
    label: string;
    signers: Array<{
      signoff_id: string;
      signer_id: string;
      signer_name: string;
      signer_chapter: string;
      signer_role: string;
      signoff_type: string;
      signed_at: string;
      signature_hash_short: string;
      comment_body?: string;
      sections_verified_count: number;
      notification_read_at?: string;
      notification_read_evidence: boolean;
      referenced_policy_version_label?: string;
      ue_consent_recorded: boolean;
    }>;
  }>;
  policy_at_pdf_generation?: {
    document_id: string;
    version_label: string;
    locked_at: string;
  };
  generated_at: string;
};

// ============================================================================
// HTML parser p93c — inline styling (strong/em/a) + blockquote framing
// ============================================================================

type Segment = { text: string; bold?: boolean; italic?: boolean; href?: string };
type Node = {
  type: 'h2' | 'h3' | 'h4' | 'p' | 'li';
  segments: Segment[];
  inQuote: boolean;
};

function decodeEntities(text: string): string {
  return text
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

// Substitui caracteres fora da encoding WinAnsi (Helvetica padrão) por
// equivalentes Latin-1 ou ASCII. Necessário para arrows (→), emoji e dingbats
// que aparecem nos docs governance mas não renderizam na fonte default do
// @react-pdf/renderer. Mantém en/em-dash, smart quotes, bullet, ellipsis e
// midpoint (todos em WinAnsi 0x80-0x9F).
function sanitizeText(text: string): string {
  return text
    .replace(/→/g, '›')                                    // U+2192 → U+203A (single right angle, em WinAnsi)
    .replace(/←/g, '‹')                                    // U+2190 → U+2039
    .replace(/↔/g, '<->')                                  // U+2194 sem espaços — source provê spacing
    .replace(/⇒/g, '›')                                    // U+21D2
    .replace(/⇐/g, '‹')                                    // U+21D0
    .replace(/[↑↓↕]/g, '|')                                // arrows verticais
    .replace(/✓/g, '[OK]')                                 // U+2713 checkmark
    .replace(/[✗✕]/g, '[X]')                              // U+2717/U+2715 cross
    .replace(/[\uD83C-\uDBFF][\uDC00-\uDFFF]/g, '')        // emoji surrogate pairs (📝 ⚠️ etc.)
    .replace(/\s{2,}/g, ' ');                              // collapse any double spaces criados pelos replaces
}

function mergeAdjacent(segments: Segment[]): Segment[] {
  const result: Segment[] = [];
  for (const seg of segments) {
    if (!seg.text) continue;
    const last = result[result.length - 1];
    if (last && last.bold === seg.bold && last.italic === seg.italic && last.href === seg.href) {
      last.text += seg.text;
    } else {
      result.push({ ...seg });
    }
  }
  return result;
}

function parseInlineSegments(html: string): Segment[] {
  // Pre-process:
  // 1. Strip nested block tags (p/div/span/section/article) preservando conteúdo —
  //    fix §4.5.4 royalties onde <li><p>(a) text</p></li> vazava "p>(a)/p>" para o output.
  // 2. <br> → newline
  let normalized = html
    .replace(/<\/(p|div|span|section|article)\s*>/gi, ' ')
    .replace(/<(p|div|span|section|article)[^>]*>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n');
  const segments: Segment[] = [];
  // Stack-based: track current bold/italic/href as we encounter open/close tags
  const stack: { bold?: boolean; italic?: boolean; href?: string }[] = [{}];
  const tokenRegex = /<(\/?)(strong|b|em|i|a)([^>]*)>|([^<]+)/gi;
  let m: RegExpExecArray | null;
  while ((m = tokenRegex.exec(normalized)) !== null) {
    if (m[4] !== undefined) {
      const decoded = decodeEntities(m[4]);
      const top = stack[stack.length - 1];
      segments.push({ text: decoded, ...top });
    } else {
      const isClose = m[1] === '/';
      const tag = m[2].toLowerCase();
      if (isClose) {
        if (stack.length > 1) stack.pop();
      } else {
        const prev = stack[stack.length - 1];
        const next: Segment = { text: '', ...prev };
        if (tag === 'strong' || tag === 'b') next.bold = true;
        if (tag === 'em' || tag === 'i') next.italic = true;
        if (tag === 'a') {
          const hrefMatch = m[3].match(/href=["']([^"']+)["']/i);
          if (hrefMatch) next.href = hrefMatch[1];
        }
        const { text: _ignored, ...frame } = next;
        stack.push(frame);
      }
    }
  }
  // Apply char sanitization to each segment text (after merging) — converts
  // arrows (→ → ›), emoji (📝 → ''), checkmarks (✓ → [OK]) etc. para Helvetica WinAnsi.
  return mergeAdjacent(segments)
    .map((s) => ({ ...s, text: sanitizeText(s.text) }))
    .filter((s) => s.text.length > 0);
}

function parseHtml(html: string): Node[] {
  if (!html) return [];
  const normalized = html.replace(/[\r\n\t]+/g, ' ').replace(/\s{2,}/g, ' ').trim();
  // Find blockquote ranges first
  const quoteRanges: Array<[number, number]> = [];
  const bqRegex = /<blockquote[^>]*>([\s\S]*?)<\/blockquote>/gi;
  let bqm: RegExpExecArray | null;
  while ((bqm = bqRegex.exec(normalized)) !== null) {
    quoteRanges.push([bqm.index, bqm.index + bqm[0].length]);
  }
  function isInQuote(idx: number): boolean {
    return quoteRanges.some(([s, e]) => idx >= s && idx < e);
  }
  // Extract h2/h3/h4/p/li blocks
  const nodes: Node[] = [];
  const blockRegex = /<(h[234]|p|li)[^>]*>([\s\S]*?)<\/\1>/gi;
  let match: RegExpExecArray | null;
  while ((match = blockRegex.exec(normalized)) !== null) {
    const tag = match[1].toLowerCase();
    const inner = match[2];
    const segments = parseInlineSegments(inner);
    if (segments.length > 0 && segments.some((s) => s.text.trim().length > 0)) {
      nodes.push({
        type: tag as Node['type'],
        segments,
        inQuote: isInQuote(match.index),
      });
    }
  }
  return nodes;
}

// ============================================================================
// Render helpers
// ============================================================================

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function thresholdLabel(t: string | number): string {
  if (t === 'all' || t === '"all"') return 'todos';
  if (t === 0 || t === '0') return 'informativo';
  return `${t} assinatura${String(t) === '1' ? '' : 's'}`;
}

function renderSegments(segments: Segment[]) {
  return segments.map((s, j) => {
    const inline: any = {};
    if (s.bold) inline.fontWeight = 'bold';
    if (s.italic) inline.fontStyle = 'italic';
    if (s.href) {
      inline.color = '#0066cc';
      inline.textDecoration = 'underline';
    }
    const showUrl = s.href && s.text && s.href !== s.text && !s.text.includes(s.href);
    return (
      <Text key={j} style={inline}>
        {s.text}
        {showUrl ? <Text style={styles.linkUrl}> ({s.href})</Text> : null}
      </Text>
    );
  });
}

function renderNode(n: Node, key: string | number) {
  const baseStyle =
    n.type === 'h2' ? styles.h2 :
    n.type === 'h3' ? styles.h3 :
    n.type === 'h4' ? styles.h4 :
    n.type === 'li' ? styles.listItem :
    styles.paragraph;

  if (n.type === 'li') {
    return (
      <Text key={key} style={baseStyle}>
        <Text>• </Text>
        {renderSegments(n.segments)}
      </Text>
    );
  }
  return (
    <Text key={key} style={baseStyle}>
      {renderSegments(n.segments)}
    </Text>
  );
}

// Group consecutive inQuote nodes under a single Wrapper view
function renderContent(nodes: Node[]) {
  const out: React.ReactElement[] = [];
  let i = 0;
  while (i < nodes.length) {
    const n = nodes[i];
    if (n.inQuote) {
      const group: Node[] = [];
      while (i < nodes.length && nodes[i].inQuote) {
        group.push(nodes[i]);
        i++;
      }
      out.push(
        <View key={`bq-${i}`} style={styles.blockquoteWrapper} wrap={false}>
          {group.map((g, j) => renderNode(g, `bq-${i}-${j}`))}
        </View>,
      );
    } else {
      out.push(renderNode(n, `n-${i}`));
      i++;
    }
  }
  return out;
}

// ============================================================================
// Main component
// ============================================================================

export default function ChainPDFDocument({
  data,
  mode = 'official',
}: {
  data: ChainData;
  mode?: 'official' | 'draft';
}) {
  const nodes = parseHtml(data.version.content_html);
  const isDraft = mode === 'draft';

  return (
    <Document
      title={`${data.document.title} ${data.version.label}${isDraft ? ' (DRAFT)' : ''}`}
      author={data.submitter.name}
      subject={`Cadeia de ratificação ${data.chain_id}${isDraft ? ' — rascunho para revisão' : ''}`}
      creator="Núcleo IA & GP — plataforma nucleoia.vitormr.dev"
    >
      {/* PAGE 1 — Header + metadata */}
      <Page size="A4" style={styles.page}>
        {isDraft && (
          <View style={styles.draftBanner} fixed>
            <Text style={styles.draftBannerText}>
              RASCUNHO — REVISÃO INTERNA · NÃO É VERSÃO OFICIAL
            </Text>
          </View>
        )}
        <View style={styles.headerBar}>
          <Text style={styles.orgName}>Núcleo de Estudos e Pesquisa em IA & Gestão de Projetos</Text>
          <Text style={styles.orgTag}>PMI Brasil–Goiás Chapter · nucleoia.vitormr.dev</Text>
        </View>

        <Text style={styles.docTitle}>{data.document.title}</Text>
        <Text style={styles.docMeta}>Versão {data.version.label} · tipo {data.document.doc_type}</Text>
        <Text style={styles.docMeta}>Lacrada em {fmtDate(data.version.locked_at)}</Text>

        <View style={{ marginTop: 8, marginBottom: 12 }}>
          <Text style={styles.statusBadge}>Status da cadeia: {data.chain_status}</Text>
        </View>

        <Text style={styles.sectionTitle}>Submissão</Text>
        <Text style={styles.paragraph}>
          Submetida por <Text style={{ fontWeight: 'bold' }}>{data.submitter.name}</Text> ({data.submitter.role} · {data.submitter.chapter}) em {fmtDate(data.chain_opened_at)}.
        </Text>
        {data.chain_approved_at && (
          <Text style={styles.paragraph}>
            Cadeia aprovada em <Text style={{ fontWeight: 'bold' }}>{fmtDate(data.chain_approved_at)}</Text>.
          </Text>
        )}
        {data.chain_notes && (
          <>
            <Text style={styles.sectionTitle}>Notas de alteração</Text>
            <Text style={styles.paragraph}>{data.chain_notes}</Text>
          </>
        )}
        {data.policy_at_pdf_generation && (
          <>
            <Text style={styles.sectionTitle}>Política de Governança de Propriedade Intelectual vigente</Text>
            <Text style={styles.paragraph}>
              Versão {data.policy_at_pdf_generation.version_label} (lacrada {fmtDate(data.policy_at_pdf_generation.locked_at)}). Este documento integra a Política por remissão dinâmica (CC Art. 111 e 429).
            </Text>
          </>
        )}
        {isDraft && (
          <View style={{ marginTop: 16, padding: 8, backgroundColor: '#fef3c7', borderLeft: '3px solid #f59e0b' }}>
            <Text style={{ fontSize: 9, color: '#92400e', lineHeight: 1.4 }}>
              Este PDF é um rascunho gerado para leitura offline pelo revisor. A página de assinaturas
              foi omitida intencionalmente — a versão autoritativa com hashes SHA-256 e evidência de
              cada gate permanece na plataforma. Para gerar o PDF oficial pós-aprovação, utilize a
              opção "PDF oficial" em /admin/governance/documents/{data.chain_id}.
            </Text>
          </View>
        )}
      </Page>

      {/* PAGE 2+ — Document content */}
      <Page size="A4" style={styles.page}>
        {isDraft && (
          <View style={styles.draftBanner} fixed>
            <Text style={styles.draftBannerText}>
              RASCUNHO — REVISÃO INTERNA · NÃO É VERSÃO OFICIAL
            </Text>
          </View>
        )}
        <View style={styles.headerBar}>
          <Text style={styles.orgName}>{data.document.title} — {data.version.label}</Text>
          <Text style={styles.orgTag}>Conteúdo lacrado</Text>
        </View>

        {nodes.length === 0 ? (
          <Text style={styles.paragraph}>(Conteúdo indisponível — verificar plataforma.)</Text>
        ) : (
          renderContent(nodes)
        )}
      </Page>

      {/* PAGE N — Signatures (only in official mode) */}
      {!isDraft && (
        <Page size="A4" style={styles.page}>
          <View style={styles.headerBar}>
            <Text style={styles.orgName}>Assinaturas e evidências</Text>
            <Text style={styles.orgTag}>Cadeia {data.chain_id}</Text>
          </View>

          {data.gates.map((gate) => (
            <View key={gate.kind} style={styles.gateBlock} wrap={false}>
              <Text style={styles.gateHeader}>
                Gate {gate.order} · {gate.label}
              </Text>
              <Text style={styles.gateMeta}>
                Requer: {thresholdLabel(gate.threshold)} · Assinados: {gate.signers.length}
              </Text>
              {gate.signers.length === 0 ? (
                <Text style={styles.noSigners}>Nenhuma assinatura registrada até a geração deste PDF.</Text>
              ) : (
                gate.signers.map((s) => (
                  <View key={s.signoff_id} style={{ marginBottom: 6, paddingBottom: 4, borderBottom: '1px dotted #dee2e6' }}>
                    <View style={styles.signerRow}>
                      <View style={styles.signerCol}>
                        <Text style={styles.signerName}>{s.signer_name}</Text>
                        <Text style={styles.signerDetail}>
                          {s.signer_role} · {s.signer_chapter} · {s.signoff_type}
                        </Text>
                      </View>
                      <View style={{ width: 140 }}>
                        <Text style={styles.signerDetail}>{fmtDate(s.signed_at)}</Text>
                        <Text style={styles.hashBlock}>hash: {s.signature_hash_short}</Text>
                      </View>
                    </View>
                    {s.notification_read_evidence && (
                      <Text style={styles.evidenceBadge}>
                        ✓ Notificação lida em {fmtDate(s.notification_read_at || '')} (ato concludente CC Art. 111)
                      </Text>
                    )}
                    {s.referenced_policy_version_label && (
                      <Text style={styles.signerDetail}>
                        Política referenciada: {s.referenced_policy_version_label}
                      </Text>
                    )}
                    {s.ue_consent_recorded && (
                      <Text style={styles.evidenceBadge}>✓ Consentimento UE Art. 49(1)(a) GDPR registrado</Text>
                    )}
                    {s.sections_verified_count > 0 && (
                      <Text style={styles.signerDetail}>Seções verificadas: {s.sections_verified_count}</Text>
                    )}
                    {s.comment_body && (
                      <Text style={[styles.signerDetail, { fontStyle: 'italic', marginTop: 2 }]}>
                        "{s.comment_body}"
                      </Text>
                    )}
                  </View>
                ))
              )}
            </View>
          ))}

          <View style={styles.footer}>
            <Text style={styles.footerText}>
              Gerado em {fmtDate(data.generated_at)} pela plataforma nucleoia.vitormr.dev
            </Text>
            <Text style={styles.footerText}>
              Este documento é uma representação digital da cadeia de ratificação. A versão autoritativa permanece na base de dados Supabase com hashes SHA-256 individuais por assinatura.
            </Text>
            <Text style={styles.hashBlock}>chain_id: {data.chain_id}</Text>
            <Text style={styles.hashBlock}>version_id: {data.version.id}</Text>
          </View>
        </Page>
      )}

      {/* DRAFT mode: minimal audit footer page */}
      {isDraft && (
        <Page size="A4" style={styles.page}>
          <View style={styles.draftBanner} fixed>
            <Text style={styles.draftBannerText}>
              RASCUNHO — REVISÃO INTERNA · NÃO É VERSÃO OFICIAL
            </Text>
          </View>
          <View style={styles.headerBar}>
            <Text style={styles.orgName}>Identificação do rascunho</Text>
            <Text style={styles.orgTag}>Para audit trail offline</Text>
          </View>
          <Text style={styles.paragraph}>
            Este rascunho refere-se à versão lacrada <Text style={{ fontWeight: 'bold' }}>{data.version.label}</Text> do
            documento <Text style={{ fontWeight: 'bold' }}>{data.document.title}</Text>.
          </Text>
          <Text style={styles.paragraph}>
            Para validar a integridade do conteúdo após a leitura offline, comparar este texto com a
            versão lacrada disponível em <Text style={{ fontFamily: 'Courier', fontSize: 9 }}>nucleoia.vitormr.dev/admin/governance/documents/{data.chain_id}</Text>.
            Os hashes oficiais de assinatura, evidência de notificação e timestamps de cada gate serão
            incluídos no PDF oficial gerado após o fechamento da cadeia.
          </Text>
          <View style={styles.footer}>
            <Text style={styles.footerText}>Rascunho gerado em {fmtDate(data.generated_at)}</Text>
            <Text style={styles.hashBlock}>chain_id: {data.chain_id}</Text>
            <Text style={styles.hashBlock}>version_id: {data.version.id}</Text>
            <Text style={styles.hashBlock}>doc_type: {data.document.doc_type}</Text>
          </View>
        </Page>
      )}
    </Document>
  );
}
