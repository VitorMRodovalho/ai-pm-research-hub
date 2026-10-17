/**
 * #2701 — revogar certificado de verdade: função própria, auditada, com aviso ao membro.
 *
 * Medido em 16/10/2026: as 5 revogações que existiam foram gravadas direto no banco (1 sem auditoria), a tela não
 * tinha botão desde a #2702 e o MCP não revogava. Decisões do GP em 16/10: função + botão + MCP; portão
 * manage_member; aviso no sino com o motivo, sem e-mail. O Termo de Voluntariado continua pelo distrato.
 *
 * Os corpos SQL são lidos pela captura MAIS NOVA (#1932). Cada asserção amarra a condição ao resultado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const fn = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);
const migName = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('_2701_revogar_certificado.sql'));
const MIG = migName.length ? maskLineComments(read(`supabase/migrations/${migName[0]}`)) : '';
const GAM = maskJsComments(read('src/pages/gamification.astro'));
const MCP = maskJsComments(read('supabase/functions/nucleo-mcp/index.ts'));

test('#2701 há exatamente uma migration da revogação', () => {
  assert.equal(migName.length, 1, `esperava 1 migration *_2701_revogar_certificado.sql, achei ${migName.length}`);
});

test('#2701 a função decide antes de gravar: sessão, portão, motivo, tipo e status', () => {
  const f = fn('revoke_certificate');
  const antes = f.slice(0, f.indexOf('UPDATE public.certificates'));
  assert.ok(antes.length > 0, 'a função não grava em certificates');
  assert.match(antes, /IF v_caller_id IS NULL THEN\s+RETURN jsonb_build_object\('error', 'not_authenticated'\);/);
  assert.match(antes, /IF NOT public\.can_by_member\(v_caller_id, 'manage_member'\) THEN\s+RETURN jsonb_build_object\('error', 'not_authorized', 'required', 'manage_member'\);/);
  assert.match(antes, /IF v_reason = '' THEN\s+RETURN jsonb_build_object\('error', 'reason_required'\);/);
  assert.match(f, /v_reason\s+text := left\(btrim\(COALESCE\(p_reason, ''\)\), 500\);/);
  assert.match(antes, /IF v_cert\.type = 'volunteer_agreement' THEN\s+RETURN jsonb_build_object\('error', 'use_reject_for_agreement'\);/);
  assert.match(antes, /IF v_cert\.status IS DISTINCT FROM 'issued' THEN\s+RETURN jsonb_build_object\('error', 'not_revocable', 'status', v_cert\.status\);/);
});

test('#2701 a revogação grava os quatro campos, a auditoria e o aviso que não vira e-mail', () => {
  const f = fn('revoke_certificate');
  assert.match(f, /SET status = 'revoked', revoked_at = now\(\), revoked_by = v_caller_id,\s+revoked_reason = v_reason, updated_at = now\(\)\s+WHERE id = p_certificate_id;/);
  assert.match(f, /INSERT INTO public\.admin_audit_log \(actor_id, action, target_type, target_id, changes\)\s+VALUES \(v_caller_id, 'certificate_revoked', 'certificate', p_certificate_id,/);
  assert.match(f, /VALUES \(v_cert\.member_id, 'certificate_revoked',[\s\S]{0,500}?public\._delivery_mode_for\('certificate_revoked'\)\);/);
  assert.match(fn('_delivery_mode_for'), /WHEN 'certificate_revoked'\s+THEN 'suppress'/, 'sem esta linha o aviso cai no resumo semanal por e-mail');
  const cat = JSON.parse(read('docs/adr/ADR-0022-notification-types-catalog.json'));
  assert.equal(cat.types?.certificate_revoked?.delivery_mode, 'suppress');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\.revoke_certificate\(uuid, text\) FROM PUBLIC, anon;/);
});

test('#2701 a tela: botão só para quem revoga, motivo obrigatório, erro lido antes do sucesso', () => {
  assert.match(GAM, /\$\{c\.status === 'issued' && c\.type !== 'volunteer_agreement' && canFor\('manage_member'\) \? `<button[^`]*data-action="revoke-cert"/);
  const m = GAM.match(/case 'revoke-cert': \{([\s\S]*?)\n      \}/);
  assert.ok(m, "case 'revoke-cert' ausente");
  const b = m[1];
  assert.match(b, /if \(!reason \|\| !reason\.trim\(\)\) break;/);
  assert.match(b, /sb\.rpc\('revoke_certificate', \{ p_certificate_id: id, p_reason: reason\.trim\(\) \}\)/);
  assert.match(b, /if \(revErr \|\| rev\?\.error\) \{ toast\([^)]*'error'\); break; \}\s+toast\(I\.certStatusRevoked, 'success'\);/);
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.ok(read(`src/i18n/${loc}.ts`).includes("'gamification.cert.revokePrompt':"), `${loc} sem gamification.cert.revokePrompt`);
  }
});

test('#2701 o MCP revoga com motivo e só depois do confirm', () => {
  assert.match(MCP, /action: z\.enum\(\["issue", "update", "revoke", "verify", "list", "my", "timeline"\]\)/);
  assert.match(MCP, /if \(params\.action === "revoke" && \(!params\.reason \|\| !String\(params\.reason\)\.trim\(\)\)\) return invalid\(/);
  assert.match(MCP, /if \(\(params\.action === "issue" \|\| params\.action === "update" \|\| params\.action === "revoke"\) && params\.confirm !== true\) \{/);
  assert.match(MCP, /case "revoke":\s+\(\{ data, error \} = await sb\.rpc\("revoke_certificate", \{ p_certificate_id: params\.cert_id, p_reason: String\(params\.reason\)\.trim\(\) \}\)\);/);
});
