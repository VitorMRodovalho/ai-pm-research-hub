/**
 * ChainAuditReportPDF — IP-4 Chunk 3
 *
 * Relatório de auditoria para Conselho Fiscal PMI-GO.
 * Diferença vs ChainPDFDocument (oficial):
 *   - Foco em evidence trail + timeline + admin_audit_log
 *   - Não inclui content_html (é complementar ao PDF oficial)
 *   - Inclui hashes completos, sections_verified detalhadas, actor trail
 */
import { Document, Page, Text, View, StyleSheet } from '@react-pdf/renderer';

const styles = StyleSheet.create({
  page: { padding: 40, fontSize: 10, fontFamily: 'Helvetica', color: '#1a1a1a' },
  headerBar: { borderBottom: '2px solid #7c2d12', paddingBottom: 8, marginBottom: 16 },
  orgName: { fontSize: 11, fontWeight: 'bold', color: '#7c2d12' },
  orgTag: { fontSize: 9, color: '#6c757d', marginTop: 2 },
  reportTitle: { fontSize: 18, fontWeight: 'bold', marginTop: 16, marginBottom: 4, color: '#7c2d12' },
  reportSubtitle: { fontSize: 11, color: '#6c757d', marginBottom: 12 },
  sectionTitle: { fontSize: 13, fontWeight: 'bold', marginTop: 16, marginBottom: 8, color: '#7c2d12', borderBottom: '1px solid #fed7aa', paddingBottom: 3 },
  metaGrid: { marginBottom: 10 },
  metaRow: { flexDirection: 'row', marginBottom: 3 },
  metaLabel: { fontSize: 9, fontWeight: 'bold', color: '#6c757d', width: 130 },
  metaValue: { fontSize: 9, color: '#1a1a1a', flex: 1 },
  integrityBox: { backgroundColor: '#fff7ed', padding: 8, borderLeft: '3px solid #f59e0b', marginBottom: 10 },
  integrityRow: { flexDirection: 'row', fontSize: 9, marginBottom: 2 },
  timelineEvent: { marginBottom: 8, padding: 6, backgroundColor: '#f8f9fa', borderLeft: '2px solid #7c2d12' },
  eventKind: { fontSize: 9, fontWeight: 'bold', color: '#7c2d12', marginBottom: 2 },
  eventTimestamp: { fontSize: 8, color: '#6c757d' },
  eventData: { fontSize: 9, color: '#495057', marginTop: 2 },
  signoffBlock: { marginBottom: 10, padding: 8, border: '1px solid #dee2e6', borderRadius: 3 },
  signoffHeader: { fontSize: 10, fontWeight: 'bold', marginBottom: 4 },
  signoffKV: { flexDirection: 'row', marginBottom: 2 },
  signoffLabel: { fontSize: 8, fontWeight: 'bold', color: '#6c757d', width: 120 },
  signoffValue: { fontSize: 8, color: '#1a1a1a', flex: 1 },
  hashText: { fontSize: 7, fontFamily: 'Courier', color: '#495057', flexWrap: 'wrap' },
  evidenceBadge: { fontSize: 8, color: '#10b981', marginTop: 2 },
  auditEntry: { marginBottom: 4, padding: 4, backgroundColor: '#fafafa', fontSize: 8 },
  footer: { marginTop: 20, paddingTop: 10, borderTop: '1px solid #dee2e6' },
  footerText: { fontSize: 8, color: '#6c757d', marginBottom: 2 },
  disclaimer: { fontSize: 8, color: '#991b1b', fontStyle: 'italic', marginTop: 8 },
});

type Actor = { id: string; name?: string; chapter?: string; role?: string };

type TimelineEvent = {
  kind: string;
  at: string;
  data: any;
};

type Signoff = {
  signoff_id: string;
  gate_kind: string;
  signoff_type: string;
  signer: {
    id: string; name: string; email?: string; chapter?: string; role?: string;
    pmi_id?: string; designations?: string[];
  };
  signed_at: string;
  signature_hash: string;
  signature_hash_short: string;
  sections_verified: any;
  sections_verified_count: number;
  comment_body?: string;
  content_snapshot: any;
  referenced_policy_version_id?: string;
};

type AuditEntry = {
  log_id: string;
  timestamp: string;
  actor?: Actor;
  action: string;
  target_type: string;
  target_id: string;
  metadata?: any;
};

export type AuditReportData = {
  chain_id: string;
  chain_status: string;
  chain_opened_at: string;
  chain_approved_at: string | null;
  chain_closed_at: string | null;
  chain_notes?: string;
  gates_config: Array<{ kind: string; order: number; threshold: string | number }>;
  document: { id: string; title: string; doc_type: string; status: string };
  version: { id: string; number: number; label: string; locked_at: string; published_at: string };
  submitter: { id: string; name: string; email: string; chapter: string; role: string };
  timeline: TimelineEvent[];
  signoffs: Signoff[];
  audit_log_entries: AuditEntry[];
  integrity_summary: {
    total_signoffs: number;
    with_hash: number;
    with_snapshot: number;
    with_policy_version_ref: number;
    with_notification_read_evidence: number;
    with_sections_verified: number;
  };
  generated_at: string;
  generated_by: { id: string; name: string };
};

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

const EVENT_LABELS: Record<string, string> = {
  version_authored: 'Versão criada (draft)',
  version_locked: 'Versão lacrada',
  chain_opened: 'Cadeia aberta (status: review)',
  signoff_recorded: 'Signoff registrado',
  chain_approved: 'Cadeia aprovada (todos gates satisfeitos)',
  chain_closed: 'Cadeia encerrada',
};

const GATE_LABELS: Record<string, string> = {
  curator: 'Curadoria',
  leader_awareness: 'Ciência das lideranças',
  submitter_acceptance: 'Aceite do GP',
  chapter_witness: 'Testemunho de capítulo',
  president_go: 'Presidência PMI-GO',
  president_others: 'Presidências outros capítulos',
  volunteers_in_role_active: 'Ratificação voluntários em função',
  member_ratification: 'Ratificação membros',
  external_signer: 'Signatário externo',
};

export default function ChainAuditReportPDF({ data }: { data: AuditReportData }) {
  const totalGates = data.gates_config.length;
  const satisfiedGates = data.gates_config.filter((g) => {
    const gateSignoffs = data.signoffs.filter((s) => s.gate_kind === g.kind && s.signoff_type !== 'reject');
    if (g.threshold === 0 || g.threshold === '0') return gateSignoffs.length >= 1;
    if (g.threshold === 'all' || g.threshold === '"all"') return false; // dinâmico não calcula no snapshot
    return gateSignoffs.length >= Number(g.threshold);
  }).length;

  return (
    <Document
      title={`Relatório de Auditoria — ${data.document.title} ${data.version.label}`}
      author={data.generated_by.name}
      subject={`Auditoria Conselho Fiscal PMI-GO — cadeia ${data.chain_id}`}
      creator="Núcleo IA & GP — plataforma nucleoia.vitormr.dev"
    >
      {/* PAGE 1 — Cover + Executive Summary */}
      <Page size="A4" style={styles.page}>
        <View style={styles.headerBar}>
          <Text style={styles.orgName}>Núcleo de Estudos e Pesquisa em IA & Gestão de Projetos</Text>
          <Text style={styles.orgTag}>PMI Brasil–Goiás Chapter · Relatório de Auditoria para Conselho Fiscal</Text>
        </View>

        <Text style={styles.reportTitle}>Relatório de Auditoria — Cadeia de Ratificação</Text>
        <Text style={styles.reportSubtitle}>
          Documento: {data.document.title} · Versão {data.version.label}
        </Text>

        <View style={styles.metaGrid}>
          <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>Chain ID</Text>
            <Text style={[styles.metaValue, { fontFamily: 'Courier', fontSize: 8 }]}>{data.chain_id}</Text>
          </View>
          <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>Version ID</Text>
            <Text style={[styles.metaValue, { fontFamily: 'Courier', fontSize: 8 }]}>{data.version.id}</Text>
          </View>
          <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>Status atual</Text>
            <Text style={styles.metaValue}>{data.chain_status}</Text>
          </View>
          <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>Aberta em</Text>
            <Text style={styles.metaValue}>{fmtDate(data.chain_opened_at)}</Text>
          </View>
          <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>Aprovada em</Text>
            <Text style={styles.metaValue}>{fmtDate(data.chain_approved_at)}</Text>
          </View>
          <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>Submetida por</Text>
            <Text style={styles.metaValue}>{data.submitter.name} ({data.submitter.role} · {data.submitter.chapter})</Text>
          </View>
          <View style={styles.metaRow}>
            <Text style={styles.metaLabel}>Relatório gerado</Text>
            <Text style={styles.metaValue}>{fmtDate(data.generated_at)} por {data.generated_by.name}</Text>
          </View>
        </View>

        <Text style={styles.sectionTitle}>Sumário de Integridade</Text>
        <View style={styles.integrityBox}>
          <View style={styles.integrityRow}>
            <Text style={{ fontWeight: 'bold', width: 220 }}>Total de signoffs registrados:</Text>
            <Text>{data.integrity_summary.total_signoffs}</Text>
          </View>
          <View style={styles.integrityRow}>
            <Text style={{ fontWeight: 'bold', width: 220 }}>Signoffs com hash SHA-256:</Text>
            <Text>{data.integrity_summary.with_hash} / {data.integrity_summary.total_signoffs}</Text>
          </View>
          <View style={styles.integrityRow}>
            <Text style={{ fontWeight: 'bold', width: 220 }}>Signoffs com content_snapshot:</Text>
            <Text>{data.integrity_summary.with_snapshot} / {data.integrity_summary.total_signoffs}</Text>
          </View>
          <View style={styles.integrityRow}>
            <Text style={{ fontWeight: 'bold', width: 220 }}>Signoffs c/ ref policy version (RF-III):</Text>
            <Text>{data.integrity_summary.with_policy_version_ref} / {data.integrity_summary.total_signoffs}</Text>
          </View>
          <View style={styles.integrityRow}>
            <Text style={{ fontWeight: 'bold', width: 220 }}>Signoffs c/ evidência de leitura (RF-V):</Text>
            <Text>{data.integrity_summary.with_notification_read_evidence} / {data.integrity_summary.total_signoffs}</Text>
          </View>
          <View style={styles.integrityRow}>
            <Text style={{ fontWeight: 'bold', width: 220 }}>Signoffs c/ seções verificadas:</Text>
            <Text>{data.integrity_summary.with_sections_verified} / {data.integrity_summary.total_signoffs}</Text>
          </View>
          <View style={styles.integrityRow}>
            <Text style={{ fontWeight: 'bold', width: 220 }}>Gates configurados:</Text>
            <Text>{totalGates} ({satisfiedGates} satisfeitos na geração)</Text>
          </View>
        </View>

        <Text style={styles.disclaimer}>
          Este relatório é uma representação digital consolidada da cadeia para auditoria externa. Hashes SHA-256 são calculados no momento da assinatura e armazenados imutavelmente. A versão autoritativa permanece na base de dados Supabase. Recomputação de integridade pode ser feita comparando `signature_hash` armazenado vs hash recomputado a partir do `content_snapshot`.
        </Text>
      </Page>

      {/* PAGE 2+ — Timeline */}
      <Page size="A4" style={styles.page}>
        <View style={styles.headerBar}>
          <Text style={styles.orgName}>Timeline Cronológica</Text>
          <Text style={styles.orgTag}>Cadeia {data.chain_id}</Text>
        </View>

        {data.timeline.length === 0 ? (
          <Text style={{ fontSize: 9, color: '#6c757d', fontStyle: 'italic' }}>Nenhum evento registrado.</Text>
        ) : (
          data.timeline.map((ev, i) => (
            <View key={i} style={styles.timelineEvent} wrap={false}>
              <Text style={styles.eventKind}>#{i + 1} · {EVENT_LABELS[ev.kind] || ev.kind}</Text>
              <Text style={styles.eventTimestamp}>{fmtDate(ev.at)}</Text>
              {ev.data?.actor?.name && (
                <Text style={styles.eventData}>
                  Ator: {ev.data.actor.name}
                  {ev.data.actor.chapter ? ` (${ev.data.actor.chapter})` : ''}
                  {ev.data.actor.role ? ` · ${ev.data.actor.role}` : ''}
                </Text>
              )}
              {ev.data?.gate_kind && (
                <Text style={styles.eventData}>
                  Gate: {GATE_LABELS[ev.data.gate_kind] || ev.data.gate_kind}
                  {' · '}Tipo: {ev.data.signoff_type}
                  {ev.data.hash_short ? ` · hash ${ev.data.hash_short}` : ''}
                </Text>
              )}
              {ev.data?.gates_count && (
                <Text style={styles.eventData}>Gates configurados na abertura: {ev.data.gates_count}</Text>
              )}
              {ev.data?.version_label && ev.kind !== 'signoff_recorded' && (
                <Text style={styles.eventData}>Versão: {ev.data.version_label}</Text>
              )}
            </View>
          ))
        )}
      </Page>

      {/* PAGE 3+ — Signoffs detalhados */}
      <Page size="A4" style={styles.page}>
        <View style={styles.headerBar}>
          <Text style={styles.orgName}>Signoffs — Detalhamento Individual</Text>
          <Text style={styles.orgTag}>Evidence trail completo</Text>
        </View>

        {data.signoffs.length === 0 ? (
          <Text style={{ fontSize: 9, color: '#6c757d', fontStyle: 'italic' }}>Nenhum signoff registrado até a geração deste relatório.</Text>
        ) : (
          data.signoffs.map((s, i) => {
            const snapshot = s.content_snapshot || {};
            return (
              <View key={s.signoff_id} style={styles.signoffBlock} wrap={false}>
                <Text style={styles.signoffHeader}>
                  Signoff #{i + 1} · {GATE_LABELS[s.gate_kind] || s.gate_kind} · {s.signoff_type}
                </Text>
                <View style={styles.signoffKV}>
                  <Text style={styles.signoffLabel}>Signer</Text>
                  <Text style={styles.signoffValue}>
                    {s.signer.name} ({s.signer.role} · {s.signer.chapter})
                    {s.signer.pmi_id ? ` · PMI ${s.signer.pmi_id}` : ''}
                  </Text>
                </View>
                <View style={styles.signoffKV}>
                  <Text style={styles.signoffLabel}>Assinado em</Text>
                  <Text style={styles.signoffValue}>{fmtDate(s.signed_at)}</Text>
                </View>
                <View style={styles.signoffKV}>
                  <Text style={styles.signoffLabel}>Signature Hash</Text>
                  <Text style={[styles.signoffValue, styles.hashText]}>{s.signature_hash}</Text>
                </View>
                {s.signer.designations && s.signer.designations.length > 0 && (
                  <View style={styles.signoffKV}>
                    <Text style={styles.signoffLabel}>Designations</Text>
                    <Text style={styles.signoffValue}>{s.signer.designations.join(', ')}</Text>
                  </View>
                )}
                {snapshot.notification_read_at && (
                  <>
                    <View style={styles.signoffKV}>
                      <Text style={styles.signoffLabel}>Notif recebida em</Text>
                      <Text style={styles.signoffValue}>{fmtDate(snapshot.notification_created_at)}</Text>
                    </View>
                    <View style={styles.signoffKV}>
                      <Text style={styles.signoffLabel}>Notif lida em</Text>
                      <Text style={styles.signoffValue}>{fmtDate(snapshot.notification_read_at)}</Text>
                    </View>
                    <Text style={styles.evidenceBadge}>✓ Evidência de ato concludente (CC Art. 111)</Text>
                  </>
                )}
                {snapshot.referenced_policy_version_label && (
                  <View style={styles.signoffKV}>
                    <Text style={styles.signoffLabel}>Política ref</Text>
                    <Text style={styles.signoffValue}>{snapshot.referenced_policy_version_label}</Text>
                  </View>
                )}
                {snapshot.ue_consent_recorded && (
                  <Text style={styles.evidenceBadge}>✓ Consentimento UE Art. 49(1)(a) GDPR registrado</Text>
                )}
                {s.sections_verified_count > 0 && (
                  <View style={styles.signoffKV}>
                    <Text style={styles.signoffLabel}>Seções verificadas</Text>
                    <Text style={styles.signoffValue}>{s.sections_verified_count} seção(ões)</Text>
                  </View>
                )}
                {s.comment_body && (
                  <View style={styles.signoffKV}>
                    <Text style={styles.signoffLabel}>Comentário</Text>
                    <Text style={[styles.signoffValue, { fontStyle: 'italic' }]}>"{s.comment_body}"</Text>
                  </View>
                )}
              </View>
            );
          })
        )}
      </Page>

      {/* PAGE N — admin_audit_log */}
      <Page size="A4" style={styles.page}>
        <View style={styles.headerBar}>
          <Text style={styles.orgName}>Log de Auditoria Administrativa</Text>
          <Text style={styles.orgTag}>admin_audit_log correlacionado</Text>
        </View>

        {data.audit_log_entries.length === 0 ? (
          <Text style={{ fontSize: 9, color: '#6c757d', fontStyle: 'italic' }}>Nenhuma entrada correlacionada.</Text>
        ) : (
          data.audit_log_entries.map((e) => (
            <View key={e.log_id} style={styles.auditEntry} wrap={false}>
              <Text style={{ fontWeight: 'bold', fontSize: 8 }}>{e.action} ({e.target_type})</Text>
              <Text style={{ fontSize: 7, color: '#6c757d' }}>{fmtDate(e.timestamp)}</Text>
              {e.actor?.name && <Text style={{ fontSize: 7 }}>Ator: {e.actor.name}</Text>}
              {e.metadata && Object.keys(e.metadata).length > 0 && (
                <Text style={{ fontSize: 7, fontFamily: 'Courier', color: '#495057', marginTop: 1 }}>
                  {JSON.stringify(e.metadata).substring(0, 200)}
                  {JSON.stringify(e.metadata).length > 200 ? '…' : ''}
                </Text>
              )}
            </View>
          ))
        )}

        <View style={styles.footer}>
          <Text style={styles.footerText}>
            Relatório gerado em {fmtDate(data.generated_at)} por {data.generated_by.name}
          </Text>
          <Text style={styles.footerText}>
            Plataforma: nucleoia.vitormr.dev · Auditoria: Conselho Fiscal PMI Brasil–Goiás Chapter
          </Text>
          <Text style={{ fontSize: 7, fontFamily: 'Courier', color: '#495057', marginTop: 4 }}>
            chain_id: {data.chain_id}
          </Text>
        </View>
      </Page>
    </Document>
  );
}
