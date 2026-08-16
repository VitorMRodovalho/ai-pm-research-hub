// tests/contracts/1809-literal-de-estado-na-metade-compartilhada.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json
// (SEDIMENT-186.C / #1109) — an unwired contract file is silently skipped.
/**
 * #1809 — a METADE COMPARTILHADA da classe do #1805.
 *
 * O #1805 fechou as colunas de estado cujo NOME tem dono unico em public, e deixou declaradamente
 * aberta a outra metade: `status` existe em ~50 tabelas, cada uma com seu dominio. Ele registrou
 * que fechar essa metade exigia resolver alias POR CONSULTA, nao por regex. E o que foi feito:
 * para cada funcao, quais relacoes que possuem aquela coluna o corpo referencia. Exatamente uma =
 * o literal so pode ser daquela tabela.
 *
 * Medido em 16/08/2026: 409 funcoes comparam `status` a literal, 159 com alias resolvivel. A rede
 * ampliada para todas as colunas de nome compartilhado deu 20 pares em 11 funcoes, e a LEITURA do
 * corpo separou 6 falsos positivos dos defeitos reais.
 *
 * O achado maior nao e literal morto, e um dominio que nunca mudou:
 *
 *   `visitor_leads` nasceu (20260319100033) com CHECK inline, que o Postgres nomeia
 *   `visitor_leads_status_check` automaticamente. A ARM-1 (20260516890000) tentou trocar o dominio
 *   com ADD CONSTRAINT usando ESSE MESMO nome: bateu `duplicate_object`, e o proprio handler
 *   `WHEN duplicate_object THEN NULL` — escrito para dar idempotencia — engoliu a MUDANCA.
 *   Migration verde, dominio parado. Resultado, provado em transacao abortada:
 *   `promote_lead_to_application` e `dismiss_visitor_lead` falhavam em TODA chamada, e
 *   `auto_promote_eligible_leads_for_cycle` falhava por lead dentro do `EXCEPTION WHEN OTHERS`,
 *   desfazendo junto a candidatura recem-inserida. Zero eventos `visitor_lead.*` no audit log.
 *
 * DUAS ARMADILHAS DE RESOLUCAO, fechadas por construcao no ratchet:
 *   (a) gatilho — `NEW.`/`OLD.` nao citam a tabela no texto, entao a tabela do trigger entra por
 *       `pg_trigger`. Sem isso, tres gatilhos resolviam para a tabela VIZINHA.
 *   (b) schema nao-`public` entra em `rels` de proposito: e o que torna `cron.job_run_details` um
 *       segundo dono e derruba a funcao para ambigua, em vez de resolve-la errado.
 *   O preco e ser conservador: funcao que referencia duas relacoes com a coluna sai da cobertura.
 *
 * Linha de base do ratchet: ZERO. Nao ha excecao a manter.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ler = f => readFileSync(resolve(process.cwd(), 'supabase/migrations', f), 'utf8');
const MIG_A = ler('20260816143638_1809_literais_de_estado_alinhados_ao_dominio.sql');
const MIG_B = ler('20260816143735_1809_ratchet_da_classe_compartilhada_e_aposentadoria.sql');

/**
 * So o SQL EXECUTAVEL. Os comentarios CITAM os literais removidos — e obrigatorio que citem, senao
 * a migration nao explica o que corrigiu — e o COMMENT ON do ratchet cita ate o exemplo do trigger.
 * Guard que le prosa acusa a propria documentacao (licao do #1801/#1805): prosa sai antes do assert.
 */
const soSql = m => m
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

const SQL_A = soSql(MIG_A);
const SQL_B = soSql(MIG_B);

const conta = (sql, s) => (sql.split(s).length - 1);

test('#1809 mig: o dominio de visitor_leads e trocado com DROP + ADD, nao com ADD isolado', () => {
  // ADD sozinho com o nome que ja existe bate duplicate_object — foi exatamente assim que a ARM-1
  // silenciou. O DROP e o que faz a troca acontecer.
  assert.match(SQL_A, /ALTER TABLE public\.visitor_leads DROP CONSTRAINT IF EXISTS visitor_leads_status_check;/);
  assert.match(SQL_A, /CHECK \(status IS NULL OR status IN \('new','contacted','promoted','dismissed'\)\)/);
  // e o dominio velho, que as 3 RPCs nunca conseguiram satisfazer, nao pode voltar
  assert.doesNotMatch(SQL_A, /'new','contacted','converted','archived'/);
});

test('#1809 mig: os badges da tribo saem de members.credly_badges, nao de certificates', () => {
  // certificates.type e participation/completion/contribution/excellence/volunteer_agreement/
  // institutional_declaration/ip_ratification/alumni_recognition. trail/cpmai/cert_pmi_senior nunca
  // existiram ali; a fonte real e o jsonb que a EF verify-credly escreve.
  assert.equal(conta(SQL_A, "b.value->>'category' = 'trail'"), 3);
  assert.match(SQL_A, /jsonb_array_elements\(COALESCE\(m\.credly_badges, '\[\]'::jsonb\)\)/);
  assert.doesNotMatch(SQL_A, /c\.type = 'trail'/, 'certificates nao e a fonte dos badges');
  assert.doesNotMatch(SQL_A, /type = 'cpmai'/, "'cpmai' nao existe no dominio de certificates.type");
  // a categoria escrita pela EF e 'cert_cpmai', nao 'cpmai'
  assert.match(SQL_A, /b\.value->>'category' = 'cert_cpmai'/);
});

test('#1809 mig: os filtros de list_initiative_engagements alcancam o dominio de engagements', () => {
  // withdraw_from_initiative grava 'offboarded'; 'revoked' e vocabulario das COLUNAS
  // (revoked_at/revoked_by/revoke_reason), nao do dominio de status.
  assert.match(SQL_A, /\(p_status_filter = 'revoked' AND e\.status = 'offboarded'\)/);
  assert.match(SQL_A, /\(p_status_filter = 'onboarding' AND e\.status = 'pending'\)/);
  assert.doesNotMatch(SQL_A, /e\.status = 'revoked'/);
  assert.doesNotMatch(SQL_A, /e\.status = 'onboarding'/);
  // os NOMES dos filtros sao contrato publico da tool MCP e ficam como estao
  assert.match(SQL_A, /p_status_filter NOT IN \('active', 'all', 'revoked', 'onboarding'\)/);
});

test('#1809 mig: o contador morto de convites saiu', () => {
  // initiative_invitations admite pending/accepted/declined/expired/revoked. 'canceled' nao existe.
  assert.doesNotMatch(SQL_A, /'canceled'/);
  assert.match(SQL_A, /'revoked', count\(\*\) FILTER \(WHERE status='revoked'\)/, 'revoked segue contado');
});

test('#1809 mig: o comite alcanca quem avalia, pelo padrao que o catalogo ja fixou', () => {
  // selection_committee.role e evaluator/lead/observer. Com 'member' morto o predicado valia
  // role='lead' sozinho — e nao ha lead algum em ciclo em andamento.
  assert.equal(conta(SQL_A, "role IN ('lead','evaluator')"), 2);
  assert.doesNotMatch(SQL_A, /role IN \('lead','member'\)/);
});

test('#1809 mig: os predicados mortos de analytics passam a casar', () => {
  // board_items.curation_status: draft/peer_review/leader_review/curation_pending/published
  assert.equal(conta(SQL_A, "curation_status = 'published'"), 3);
  assert.doesNotMatch(SQL_A, /curation_status = 'approved'/);
  // events.type e em portugues
  assert.match(SQL_A, /WHERE type = 'geral'/);
  assert.doesNotMatch(SQL_A, /type = 'general'/);
  // board_lifecycle_events.action
  assert.match(SQL_A, /ble\.action = 'submitted_for_curation'/);
  assert.doesNotMatch(SQL_A, /action = 'submission'/);
});

test('#1809 mig: o gatilho de entrevista perde o literal morto SEM perder cobertura', () => {
  // 'interview' nunca casou, mas NAO era fail-open: 'entrevista' cobre o caso real (143 linhas).
  assert.match(SQL_A, /IF NEW\.type IN \('entrevista', '1on1', 'parceria'\) THEN/);
  assert.doesNotMatch(SQL_A, /'entrevista', 'interview'/);
});

test('#1809 mig: o literal morto do ranking sai nas DUAS ocorrencias, e so ele', () => {
  // 'merged' esta num NOT IN: efeito ZERO. Por isso vai em migration separada da parte 1.
  assert.equal(conta(SQL_B, "NOT IN ('withdrawn','rejected','cancelled')"), 2);
  assert.doesNotMatch(SQL_B, /'merged'/);
  // os outros literais do mesmo predicado nao podem ter sido tocados junto
  assert.match(SQL_B, /la\.status IN \('approved','converted'\)/);
});

test('#1809 mig: a RPC de retencao morta foi aposentada', () => {
  // citava notifications.read (e is_read), data_anomaly_log.status (a tabela nao tem) e
  // selection_applications.applied_at (e application_date). Sem chamador e fora de cron.
  assert.match(SQL_B, /DROP FUNCTION IF EXISTS public\.admin_run_retention_cleanup\(\);/);
});

test('#1809 mig: o ratchet resolve alias por CONSULTA e fecha as duas armadilhas', () => {
  assert.match(SQL_B, /CREATE OR REPLACE FUNCTION public\._audit_shared_state_literal_domain\(\)/);
  // a metade oposta a do #1805: nome com MAIS de um dono
  assert.match(SQL_B, /GROUP BY a\.attname\s*\n\s*HAVING count\(\*\) > 1/);
  // (a) a tabela do gatilho entra por pg_trigger — NEW./OLD. nao a citam no texto
  assert.match(SQL_B, /JOIN pg_trigger t ON t\.tgfoid = f\.oid/);
  // (b) schema nao-public entra, para virar AMBIGUIDADE em vez de resolucao errada
  assert.match(SQL_B, /WHERE n\.nspname NOT IN \('pg_catalog', 'information_schema'\)/);
  // resolucao = exatamente um dono referenciado
  assert.match(SQL_B, /HAVING count\(DISTINCT reloid\) = 1/);
  // \y (fronteira de palavra), nunca \b, que no ARE do Postgres e BACKSPACE (licao do #1801)
  assert.doesNotMatch(SQL_B, /regexp_matches\([^)]*\\b/, 'no ARE do Postgres \\b e BACKSPACE');
  // quantificador limitado: o Postgres recusa contagem acima de 255
  assert.match(SQL_B, /\{0,250\}/);
});

test('#1809 mig: a auditoria nasce fechada (CREATE FUNCTION concede a PUBLIC)', () => {
  assert.match(SQL_B, /REVOKE ALL ON FUNCTION public\._audit_shared_state_literal_domain\(\) FROM PUBLIC, anon, authenticated/i);
  assert.match(SQL_B, /GRANT EXECUTE ON FUNCTION public\._audit_shared_state_literal_domain\(\) TO service_role/i);
});

// ─── portao de DB ────────────────────────────────────────────────────────────────────────────────

const dbGated = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test('#1809 DB: RATCHET — nenhum literal fora do dominio na metade compartilhada (base ZERO)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_shared_state_literal_domain');
  assert.ifError(error);
  assert.ok(Array.isArray(data) && data.length > 0, 'o auditor precisa devolver linhas (senao o guard esta cego)');

  const violam = data.filter(r => r.fora_do_dominio);
  assert.deepEqual(
    violam.map(r => `${r.funcao}(${r.args}): ${r.tabela_resolvida}.${r.coluna} = '${r.literal}'`), [],
    'literal comparado contra uma coluna cujo CHECK nao o admite. O ramo nunca casa e nao levanta ' +
    'erro — quando o literal esta numa ESCRITA, a chamada inteira falha. Confira o dominio com ' +
    'pg_get_constraintdef antes de escrever o literal.',
  );
});

test('#1809 DB: o ratchet tem alcance real (nao esta olhando para meia duzia de linhas)', { skip: dbGated ? false : skipMsg }, async () => {
  const { data, error } = await sb().rpc('_audit_shared_state_literal_domain');
  assert.ifError(error);
  const colunas = new Set(data.map(r => r.coluna));
  const funcoes = new Set(data.map(r => r.funcao));
  // medido em 16/08/2026: 562 pares, 20 colunas, 268 funcoes, 48 tabelas. Piso folgado.
  assert.ok(colunas.size >= 15, `cobertura caiu para ${colunas.size} colunas (esperado >= 15)`);
  assert.ok(funcoes.size >= 200, `cobertura caiu para ${funcoes.size} funcoes (esperado >= 200)`);
  // `status` precisa estar coberta: e a coluna que o #1805 deixou declaradamente de fora
  assert.ok(colunas.has('status'), 'status saiu da cobertura — e o motivo desta issue existir');
});

test('#1809 DB: o dominio VIVO de visitor_leads admite o que as RPCs escrevem', { skip: dbGated ? false : skipMsg }, async () => {
  // O auditor le pg_constraint do banco, entao ele mesmo e a prova de que o CHECK vivo mudou:
  // se a ARM-1 voltasse a ser engolida, estes pares reapareceriam com fora_do_dominio = true.
  const { data, error } = await sb().rpc('_audit_shared_state_literal_domain');
  assert.ifError(error);

  const paresDeLead = data.filter(r =>
    r.tabela_resolvida === 'public.visitor_leads' && ['dismissed', 'promoted'].includes(r.literal));

  assert.ok(paresDeLead.length >= 2,
    `esperava ver 'dismissed' e 'promoted' examinados sobre visitor_leads, vi ${paresDeLead.length} par(es)`);
  assert.deepEqual(
    paresDeLead.filter(r => r.fora_do_dominio).map(r => `${r.funcao}: ${r.literal}`), [],
    'o CHECK vivo de visitor_leads voltou a nao admitir os estados terminais que as RPCs escrevem — ' +
    'promote_lead_to_application e dismiss_visitor_lead falham em toda chamada quando isso acontece',
  );
});

test('#1809 DB: admin_run_retention_cleanup nao existe mais', { skip: dbGated ? false : skipMsg }, async () => {
  const { error } = await sb().rpc('admin_run_retention_cleanup');
  assert.ok(error, 'a RPC aposentada nao pode continuar chamavel');
  assert.match(
    `${error.message} ${error.code ?? ''}`, /(PGRST202|not find|does not exist|schema cache)/i,
    `esperava "funcao nao encontrada", veio: ${error.message}`,
  );
});
