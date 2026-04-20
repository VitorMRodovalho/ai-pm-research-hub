/**
 * ChainPDFDocument — IP-4 Chunk 2
 *
 * Renderiza uma approval_chain completa como PDF oficial via @react-pdf/renderer.
 * Layout:
 *   - Page 1: header Núcleo + doc metadata + submitter
 *   - Page 2+: content_html do doc (parser básico HTML→react-pdf Text)
 *   - Page N-1: tabela de assinaturas por gate com evidence trail
 *   - Page N: footer auditoria (chain_id, hash, policy_version, generated_at)
 *
 * Content HTML parser: stripe básico + detecção de H2/H3/P/STRONG/EM/UL/OL/LI/BR.
 * Formatação pixel-perfect não é objetivo; legibilidade + completude sim.
 */
import { Document, Page, Text, View, StyleSheet, Font } from '@react-pdf/renderer';

const styles = StyleSheet.create({
  page: { padding: 40, fontSize: 10, fontFamily: 'Helvetica', color: '#1a1a1a' },
  headerBar: { borderBottom: '2px solid #003B5C', paddingBottom: 8, marginBottom: 16 },
  orgName: { fontSize: 11, fontWeight: 'bold', color: '#003B5C' },
  orgTag: { fontSize: 9, color: '#6c757d', marginTop: 2 },
  docTitle: { fontSize: 18, fontWeight: 'bold', marginTop: 20, marginBottom: 6, color: '#003B5C' },
  docMeta: { fontSize: 10, color: '#495057', marginBottom: 4 },
  statusBadge: { padding: 4, backgroundColor: '#fef3c7', color: '#92400e', fontSize: 9, fontWeight: 'bold', borderRadius: 3, alignSelf: 'flex-start' },
  sectionTitle: { fontSize: 13, fontWeight: 'bold', marginTop: 16, marginBottom: 8, color: '#003B5C' },
  paragraph: { fontSize: 10, marginBottom: 6, lineHeight: 1.4, textAlign: 'justify' },
  h2: { fontSize: 13, fontWeight: 'bold', marginTop: 14, marginBottom: 6, color: '#003B5C' },
  h3: { fontSize: 11, fontWeight: 'bold', marginTop: 10, marginBottom: 5 },
  h4: { fontSize: 10, fontWeight: 'bold', marginTop: 8, marginBottom: 4 },
  listItem: { fontSize: 10, marginBottom: 4, marginLeft: 12, lineHeight: 1.4 },
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

// Parser HTML básico para react-pdf. Suporta H2/H3/H4/P/STRONG/EM/UL/OL/LI/BR.
// Tags não-suportadas são stripadas mantendo texto dentro.
function parseHtml(html: string): Array<{ type: 'h2' | 'h3' | 'h4' | 'p' | 'li'; text: string }> {
  if (!html) return [];
  // Normalize: remove \n/\r, compact spaces
  const normalized = html.replace(/\s+/g, ' ').trim();
  const nodes: Array<{ type: 'h2' | 'h3' | 'h4' | 'p' | 'li'; text: string }> = [];

  // Split by block tags preservando conteúdo
  const blockRegex = /<(h[234]|p|li)[^>]*>([\s\S]*?)<\/\1>/gi;
  let match;
  while ((match = blockRegex.exec(normalized)) !== null) {
    const tag = match[1].toLowerCase();
    const inner = match[2];
    // Strip inline tags preservando bold/italic como markers (renderização simples: strong = bold via style)
    const clean = inner
      .replace(/<strong[^>]*>(.*?)<\/strong>/gi, '$1')
      .replace(/<b[^>]*>(.*?)<\/b>/gi, '$1')
      .replace(/<em[^>]*>(.*?)<\/em>/gi, '$1')
      .replace(/<i[^>]*>(.*?)<\/i>/gi, '$1')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .trim();
    if (clean) {
      nodes.push({ type: tag as any, text: clean });
    }
  }
  return nodes;
}

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

export default function ChainPDFDocument({ data }: { data: ChainData }) {
  const nodes = parseHtml(data.version.content_html);

  return (
    <Document
      title={`${data.document.title} ${data.version.label}`}
      author={data.submitter.name}
      subject={`Cadeia de ratificação ${data.chain_id}`}
      creator="Núcleo IA & GP — plataforma nucleoia.vitormr.dev"
    >
      {/* PAGE 1 — Header + metadata */}
      <Page size="A4" style={styles.page}>
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
            <Text style={styles.sectionTitle}>Política de Publicação e PI vigente</Text>
            <Text style={styles.paragraph}>
              Versão {data.policy_at_pdf_generation.version_label} (lacrada {fmtDate(data.policy_at_pdf_generation.locked_at)}). Este documento integra a Política por remissão dinâmica (CC Art. 111 e 429).
            </Text>
          </>
        )}
      </Page>

      {/* PAGE 2+ — Document content */}
      <Page size="A4" style={styles.page}>
        <View style={styles.headerBar}>
          <Text style={styles.orgName}>{data.document.title} — {data.version.label}</Text>
          <Text style={styles.orgTag}>Conteúdo lacrado</Text>
        </View>

        {nodes.length === 0 ? (
          <Text style={styles.paragraph}>(Conteúdo indisponível — verificar plataforma.)</Text>
        ) : (
          nodes.map((n, i) => {
            if (n.type === 'h2') return <Text key={i} style={styles.h2}>{n.text}</Text>;
            if (n.type === 'h3') return <Text key={i} style={styles.h3}>{n.text}</Text>;
            if (n.type === 'h4') return <Text key={i} style={styles.h4}>{n.text}</Text>;
            if (n.type === 'li') return <Text key={i} style={styles.listItem}>• {n.text}</Text>;
            return <Text key={i} style={styles.paragraph}>{n.text}</Text>;
          })
        )}
      </Page>

      {/* PAGE N — Signatures */}
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
    </Document>
  );
}
