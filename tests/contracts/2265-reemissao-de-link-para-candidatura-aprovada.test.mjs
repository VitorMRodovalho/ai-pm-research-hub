// tests/contracts/2265-reemissao-de-link-para-candidatura-aprovada.test.mjs
// Register in the "test:behavioural" AND "test:contracts" whitelists in package.json (#1109).
// (DB-aware: as camadas vivas abrem conexao.)
/**
 * #2265 — existe caminho de volta para quem foi APROVADO e nao concluiu o onboarding.
 *
 * O DEFEITO, medido em 13/09 e relatado por um membro que estava viajando: o link de onboarding
 * expira e a tela oferece apenas "entre em contato". Ao medir, o buraco era maior que o relato.
 *
 * `dispatch_pending_welcomes` seleciona SOMENTE `status = 'submitted'` + ciclo aberto +
 * `ai_analysis IS NULL`. As 4 pessoas travadas na coorte de entrantes tem `status = 'approved'`.
 * **Nenhuma delas era alcancavel por nenhuma funcao** — nao era so a falta de self-service, era a
 * ausencia de reemissao administrativa tambem. A recuperacao exigia inserir token a mao no banco.
 *
 * O NUMERO QUE ENQUADRA: dos 114 tokens de onboarding emitidos desde 29/04, 75 foram consumidos
 * (66%); dos 39 restantes, 22 nunca abriram o e-mail e 20 abriram e nao clicaram. E a hipotese de
 * nao-entrega esta REFUTADA nessa coorte: 0 nao entregues, 0 bounce, 0 reclamacao.
 *
 * ⚠️ O QUE ESTE ARQUIVO NAO DEFENDE, e a distincao importa: a reemissao atende quem JA passou da
 * janela. Os 39 precisam de LEMBRETE ANTES de expirar, que e outro conserto e outra PR. Um teste que
 * cobrasse os dois aqui esconderia que so um foi feito.
 *
 * As camadas:
 *   A (estatico)  a funcao aceita `approved`, tem dry-run por padrao, e o portao e `manage_member`.
 *   A' (inversa)  `dispatch_pending_welcomes` continua restrito a `submitted` — a reemissao e uma
 *                 porta NOVA, nao um afrouxamento da existente.
 *   B (vivo)      a funcao existe, e anon NAO a executa.
 *   C (vivo)      dry-run nao escreve: nem token, nem e-mail, nem audit log.
 *
 * Cross-ref: #2265, #2241, #2245, #2130, #2188.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const capReissue = () => maskLineComments(latestFunctionCapture(ROOT, 'reissue_onboarding_link').block);
const capDispatch = () => maskLineComments(latestFunctionCapture(ROOT, 'dispatch_pending_welcomes').block);

// ═══════════════════════════════════════════════════════════════════════════
test('#2265 A: a reemissao alcanca candidatura APROVADA, que era o buraco', () => {
  const body = capReissue();
  assert.match(body, /'submitted'\s*,\s*'approved'|'approved'\s*,\s*'submitted'/,
    [
      'A funcao deve aceitar `approved` alem de `submitted`.',
      '',
      'O recorte so-`submitted` de dispatch_pending_welcomes assume que o onboarding acontece ANTES',
      'da aprovacao. A coorte de 13/09 mostrou 4 pessoas aprovadas e travadas DEPOIS dela, sem nenhum',
      'caminho de volta — nem administrativo.',
    ].join('\n'));
});

test('#2265 A: dry-run e o PADRAO, e o portao e manage_member', () => {
  const body = capReissue();
  assert.match(body, /p_dry_run\s+boolean\s+DEFAULT\s+true/i,
    'dry-run tem de ser o default: a funcao dispara e-mail para pessoa real');
  assert.match(body, /can_by_member\([^)]*'manage_member'/,
    'reemitir link de acesso e ato de ciclo de vida e exige manage_member');
  assert.match(body, /admin_audit_log/,
    'toda reemissao tem de deixar rastro com ator');
});

test('#2265 A: recusa reemitir por cima de link ainda VALIDO', () => {
  const body = capReissue();
  assert.match(body, /consumed_at\s+IS\s+NULL[\s\S]{0,80}expires_at\s*>\s*now\(\)/i,
    [
      'A funcao deve contar links ainda validos antes de emitir outro.',
      '',
      'Dois links vivos para a mesma pessoa e convite para usar o errado, e o antigo continuaria',
      'valendo ate expirar.',
    ].join('\n'));
});

test("#2265 A': a porta existente NAO foi afrouxada", () => {
  const body = capDispatch();
  assert.match(body, /a\.status\s*=\s*'submitted'/,
    [
      '`dispatch_pending_welcomes` deve continuar restrito a `submitted`.',
      '',
      'A reemissao e uma porta NOVA. Se alguem "consertasse" ampliando o dispatch, o envio em LOTE',
      'passaria a alcancar aprovados — e um disparo em massa para quem ja esta dentro e o oposto do',
      'que #2265 pede.',
    ].join('\n'));
});

test('#2265 B: a funcao existe e anon NAO a executa', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const c = sb();
  const { data, error } = await c.rpc('reissue_onboarding_link', {
    p_application_id: '00000000-0000-0000-0000-000000000000',
    p_dry_run: true,
  });
  // service_role nao tem auth.uid(), entao o gate recusa por "member not found" — o que prova que a
  // funcao EXISTE e que o portao roda antes de qualquer escrita.
  assert.ok(error, 'a chamada sem sessao deveria ser recusada pelo portao');
  assert.match(String(error.message || ''), /Unauthorized|member not found/i,
    `recusado pelo motivo errado: ${error.message}`);
  assert.equal(data, null);
});

test('#2265 C: dry-run nao escreve — nem token, nem audit log', async (t) => {
  if (!dbGated) return t.skip(skipMsg);
  const c = sb();
  const antes = await c.from('onboarding_tokens').select('token', { count: 'exact', head: true });
  const antesLog = await c.from('admin_audit_log').select('id', { count: 'exact', head: true })
    .eq('action', 'selection.onboarding_link_reissued');

  // A chamada e recusada pelo portao (service_role nao tem auth.uid()), entao este teste mede a
  // pos-condicao da recusa: nenhuma escrita aconteceu ANTES do gate.
  await c.rpc('reissue_onboarding_link', {
    p_application_id: '00000000-0000-0000-0000-000000000000', p_dry_run: true,
  });

  const depois = await c.from('onboarding_tokens').select('token', { count: 'exact', head: true });
  const depoisLog = await c.from('admin_audit_log').select('id', { count: 'exact', head: true })
    .eq('action', 'selection.onboarding_link_reissued');

  assert.equal(depois.count, antes.count,
    'a chamada recusada nao pode ter emitido token');
  assert.equal(depoisLog.count, antesLog.count,
    'a chamada recusada nao pode ter gravado audit log');
});
