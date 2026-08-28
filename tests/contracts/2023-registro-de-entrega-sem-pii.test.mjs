// tests/contracts/2023-registro-de-entrega-sem-pii.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2023 — o registro de entrega da via assinada, e por que ele não guarda o e-mail de ninguém.
 *
 * O parecer jurídico (27/08) fez do registro um PRÉ-REQUISITO: nada dispara antes dele, porque hoje
 * não há registro nem de download (`downloaded_at` nulo em 100% dos 168 certificados, e a coluna
 * nunca é escrita) — a própria entrega não teria como ser provada.
 *
 * DUAS DECISÕES DE DESENHO que este arquivo protege:
 *
 *  (1) O registro vive em `admin_audit_log`, não numa tabela nova. O parecer pediu "log de
 *      auditoria, não notificação" pela RETENÇÃO: a política declara 5 anos ao audit log e só 6
 *      meses a notificações, e aqui o valor é probatório. Medido: `purge_expired_logs` apaga a linha
 *      INTEIRA aos 5 anos, então o que estiver em `changes` some junto.
 *
 *  (2) O endereço do titular entra como HASH COM SAL, nunca em claro. A convenção da casa está
 *      escrita no próprio código (`anonymize_premember_applications`): "audit (NO PII in the audit
 *      row: ids, anchors, counts only)". O hash prova QUAL endereço foi usado — recalcula-se e
 *      compara-se — sem guardar o contato numa tabela de 5 anos. Sal, e não sha256 cru, porque hash
 *      de e-mail sem sal é reversível por dicionário.
 *      Endereço INSTITUCIONAL entra em claro: caixa de papel não é dado pessoal.
 *
 * Cross-ref: #2023, #2022 (a entrega exige o artefato com as duas assinaturas), #2039 (a política
 * declara a finalidade e a retenção antes de o envio existir).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const WRITER = latestFunctionCapture(ROOT, 'log_certificate_delivery');
const READER = latestFunctionCapture(ROOT, 'get_certificate_delivery_log');

// Um e-mail em qualquer posição do registro. Serve de detector no teste vivo e de controle aqui.
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;

test('#2023 estático: o endereço pessoal vira HASH COM SAL, e o parâmetro não é gravado', () => {
  assert.ok(WRITER, 'log_certificate_delivery não foi capturada por nenhuma migration');
  const b = WRITER.body;
  assert.match(b, /sha256\s*\(\s*convert_to/, 'o endereço pessoal precisa ser hasheado');
  assert.match(b, /nucleo-ia-delivery-salt/,
    'sha256 SEM sal é reversível por dicionário para e-mail — o sal não é decoração');
  // O parâmetro do segredo NÃO pode aparecer dentro do jsonb que vai para a linha.
  const jsonb = b.slice(b.indexOf('jsonb_build_object'));
  assert.doesNotMatch(jsonb, /p_recipient_secret/,
    'o endereço pessoal foi para dentro da linha de auditoria — a convenção é "no PII in the audit row"');
  assert.match(jsonb, /recipient_hash/, 'a linha precisa carregar o hash, senão não prova nada');
});

test('#2023 estático: recusa registrar entrega de termo sem contra-assinatura', () => {
  // Registrar entrega de documento incompleto seria registrar a coisa errada COM APARÊNCIA de prova.
  assert.match(WRITER.body, /counter_signed_at\s+IS\s+NULL/i,
    'sem esta guarda o registro atesta a entrega de um PDF que ainda diz "pendente" (#2022)');
  assert.match(WRITER.body, /RAISE\s+EXCEPTION/i, 'a recusa tem de levantar, não retornar em silêncio');
});

test('#2023 estático: canal e tipo de destinatário são fechados, não texto livre', () => {
  const b = WRITER.body;
  assert.match(b, /p_channel\s+NOT\s+IN\s*\(\s*'email'\s*,\s*'drive'\s*\)/i, 'canal aberto vira lixo no log');
  assert.match(b, /p_recipient_kind\s+NOT\s+IN\s*\(\s*'volunteer'\s*,\s*'institutional'\s*\)/i,
    'tipo de destinatário aberto impede qualquer consulta confiável depois');
});

test('#2023 estático: a leitura NÃO devolve o hash do destinatário', () => {
  assert.ok(READER, 'get_certificate_delivery_log não foi capturada');
  const b = READER.body;
  // O hash existe para CONFERIR um endereço candidato, não para ser distribuído: devolvê-lo daria a
  // qualquer leitor um oráculo para testar endereços.
  assert.doesNotMatch(b, /'recipient_hash'\s*,/,
    'o hash do destinatário vazou na leitura — ele serve para conferir, não para distribuir');
  assert.match(b, /can_by_member\([^)]*'manage_member'/,
    'a leitura precisa de gate: a existência da entrega não é pública');
  assert.match(b, /not_authenticated/, 'anônimo tem de ser recusado explicitamente');
});

test('#2023 vivo: nenhum registro de entrega carrega e-mail de pessoa',
  { skip: dbGated ? false : skipMsg }, async () => {
  const s = sb();
  const { data: rows, error } = await s
    .from('admin_audit_log')
    .select('id, changes')
    .eq('action', 'certificate.delivered')
    .limit(2000);
  assert.ok(!error, error?.message);

  const vazamentos = (rows ?? []).filter((r) => {
    const c = r.changes || {};
    // O endereço INSTITUCIONAL é legítimo em claro; qualquer outro campo com e-mail não é.
    const { recipient_ref, ...resto } = c;
    if (c.recipient_kind === 'volunteer' && recipient_ref && EMAIL_RE.test(String(recipient_ref))) return true;
    return EMAIL_RE.test(JSON.stringify(resto));
  });
  assert.deepEqual(vazamentos.map((r) => r.id), [],
    `${vazamentos.length} registros de entrega carregam e-mail de pessoa numa tabela de 5 anos`);

  // CONTROLE POSITIVO: hoje a população pode ser 0, e um zero sobre conjunto vazio não prova nada.
  // Este controle mostra que o detector RECONHECE um vazamento quando ele existe.
  const sintetico = { recipient_kind: 'volunteer', recipient_ref: 'fulano@example.com' };
  const detecta = sintetico.recipient_kind === 'volunteer'
    && EMAIL_RE.test(String(sintetico.recipient_ref));
  assert.ok(detecta, 'o detector não reconhece um e-mail — o teste passaria por vacuidade');
});

test('#2023 estático: o contrato do hash é CONFERÍVEL (sal, normalização e codificação fixos)', () => {
  // A propriedade que dá valor probatório: quem tem um endereço candidato consegue provar (ou
  // refutar) que foi para lá, recalculando. Isso exige que sal, normalização e codificação sejam
  // ESTÁVEIS — mudar qualquer um invalida todo hash já gravado, em silêncio.
  //
  // A ida e volta foi exercitada contra produção num BEGIN/ROLLBACK ao entregar esta migration:
  // o hash gravado bateu com `sha256(lower(trim(addr)) || sal)` recalculado. Aqui o guard fixa as
  // TRÊS partes do contrato, que é o que pode mudar sem ninguém perceber.
  const b = WRITER.body;
  assert.match(b, /lower\(trim\(/, 'normalização: sem lower+trim, o mesmo endereço gera hashes diferentes');
  assert.match(b, /nucleo-ia-delivery-salt/, 'sal fixo');
  assert.match(b, /encode\(\s*sha256\([\s\S]{0,120}\)\s*,\s*'hex'\s*\)/,
    'codificação: hex — trocar para base64 invalidaria todo hash já gravado');

  // Controle: a mesma expressão em JS produz um hash de 64 hex a partir da forma normalizada.
  const esperado = createHash('sha256')
    .update('Fulano@Example.COM '.trim().toLowerCase() + 'nucleo-ia-delivery-salt', 'utf8').digest('hex');
  assert.match(esperado, /^[0-9a-f]{64}$/, 'o recálculo do lado de fora precisa ser reproduzível');
});
