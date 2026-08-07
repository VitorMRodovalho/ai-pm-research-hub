// tests/contracts/1591-comite-de-selecao-alcanca-o-admin.test.mjs
//
// #1591 — o comitê de seleção não alcançava a tela que ele opera.
//
// Medido em 07/08/2026 sobre um avaliador real do ciclo aberto:
//
//   camada       linguagem                              ele passa?
//   domínio      selection_committee.role='evaluator'      SIM
//   menu         designations + minTier                    não (designations vazio)
//   dados        can() -> view_internal_analytics          não
//
// A plataforma SABIA quem era do comitê e não deixava nem o menu aparecer nem a RPC responder.
// Mesma família do #1590, com o sinal invertido: lá 56 de 89 viam o que não podiam; aqui quem
// pode não via.
//
// O QUE ESTE ARQUIVO PROTEGE, e por que cada peça importa:
//
//   1. Menu e dados juntos. Abrir só o menu faria a página carregar e a RPC negar — lê como bug
//      para o usuário e como acesso concedido para quem audita.
//   2. As DUAS implementações do menu. `getItemAccessibility` (servidor) e `getItemAccessClient`
//      (Nav.astro, cliente) decidem a mesma coisa em runtimes diferentes. Um eixo em só uma
//      produz menu que aparece de um lado e some do outro.
//   3. Escopo de ciclo. A porta roda antes de o ciclo ser resolvido, então pergunta "é de algum
//      comitê vivo?". Sem a segunda checagem, ser do comitê do ciclo atual abriria o PII de
//      candidato de TODOS os ciclos passados.
//
// ⚠️ O que este arquivo NÃO faz: exercer `get_selection_dashboard` como o avaliador. A RPC
// resolve por `auth.uid()` e o `service_role` não tem linha em `members`, então a chamada daqui
// devolve 'Unauthorized' por um motivo que não é o que se quer medir. O predicado de autoridade,
// que é o coração da mudança, É exercido por chamada abaixo.
//
// Camada A (estática): nav config, as duas implementações, a migration.
// Camada B (DB-aware, PULA sem credenciais): predicado vivo + corpos vivos.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const NAV = 'src/lib/navigation.config.ts';
const NAV_CLIENT = 'src/components/nav/Nav.astro';
const MIGRATION = 'supabase/migrations/20260807000700_1591_comite_de_selecao_alcanca_o_admin.sql';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const navSrc = read(NAV);
const clientSrc = read(NAV_CLIENT);
const migSrc = read(MIGRATION).replace(/^\s*--.*$/gm, '');

describe('#1591 A — o eixo existe e é declarado na rota certa', () => {
  it('a rota de seleção declara o eixo do comitê', () => {
    const bloco = navSrc.match(/\{\s*key:\s*'admin-selection'[\s\S]*?\}/)?.[0] ?? '';
    assert.ok(bloco, 'entrada admin-selection não encontrada');
    assert.match(bloco, /allowedSelectionCommittee:\s*true/);
    assert.match(bloco, /lgpdSensitive:\s*true/, 'a tela expõe PII de candidato');
    // sponsor não pode sair: o eixo novo SOMA, não substitui a leitura institucional.
    assert.match(bloco, /allowedDesignations:\s*\['sponsor'\]/);
  });

  it('AS DUAS implementações do menu conhecem o eixo', () => {
    // O defeito clássico é consertar a gêmea morta. Aqui as duas estão vivas: uma decide no
    // servidor, a outra no cliente, sobre o MESMO item de nav.
    assert.match(navSrc, /item\.allowedSelectionCommittee === true && onSelectionCommittee === true/,
      'servidor: getItemAccessibility não considera o eixo');
    assert.match(clientSrc, /item\.allowedSelectionCommittee === true[\s\S]{0,120}selection_committee_active === true/,
      'cliente: getItemAccessClient não considera o eixo');
  });

  it('o eixo só conta quando a ENTRADA o declara', () => {
    // Sem esta condição, um perfil "sou do comitê" abriria qualquer rota — chave-mestra.
    for (const [src, nome] of [[navSrc, 'servidor'], [clientSrc, 'cliente']]) {
      // `\s*` porque a conjunção pode estar quebrada em duas linhas — foi o que aconteceu no
      // cliente, e um padrão preso a uma linha só teria reprovado código correto.
      assert.ok(
        /allowedSelectionCommittee === true\s*&&/.test(src),
        `${nome}: o eixo abriria rota que não o declarou`,
      );
    }
  });
});

describe('#1591 A — a migration', () => {
  it('existe e cria o predicado', () => {
    assert.ok(read(MIGRATION), `migration esperada em ${MIGRATION}`);
    assert.match(migSrc, /CREATE OR REPLACE FUNCTION public\.is_selection_committee_member\s*\(/);
  });

  it('o predicado é fechado para anon e authenticated', () => {
    // `FROM PUBLIC` sozinho não fecha nada — anon/authenticated têm GRANT próprio.
    assert.match(migSrc, /REVOKE ALL ON FUNCTION public\.is_selection_committee_member\(uuid, uuid\) FROM PUBLIC, anon, authenticated/);
  });

  it('a porta do dashboard confere o CICLO, não só "é de algum comitê"', () => {
    // É a asserção que separa "abrir a tela" de "abrir o histórico inteiro de candidatos".
    assert.match(migSrc, /v_via_committee AND NOT public\.is_selection_committee_member\(v_caller_id, v_cycle_id\)/);
  });

  it('a recusa por conflito de interesse continua de pé', () => {
    assert.match(migSrc, /selection_coi_recused/, 'ADR-0109 não pode sair junto');
  });

  it('o payload do nav expõe a flag DERIVADA, não uma coluna espelho', () => {
    assert.match(migSrc, /public\.is_selection_committee_member\(m\.id\) AS selection_committee_active/,
      'um espelho mantido à mão envelhece e passa a conceder o que já acabou');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SUPABASE_SRK);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } }) : null;

describe('#1591 B — o predicado VIVO responde certo', () => {
  it('quem está no comitê do ciclo vivo dá true; quem não está, false', { skip: dbGated ? false : skipMsg }, async () => {
    // Alvo por PREDICADO, nunca por id: pega quem está no comitê de um ciclo vivo.
    const { data: cycles, error: e0 } = await sb
      .from('selection_cycles').select('id, status, phase');
    assert.ifError(e0);
    const vivo = (cycles ?? []).find((c) => c.status === 'open' || c.phase === 'evaluating');
    if (!vivo) {
      console.log('[1591] nenhum ciclo vivo — asserção não exercida');
      return;
    }
    const { data: comite, error: e1 } = await sb
      .from('selection_committee').select('member_id').eq('cycle_id', vivo.id).limit(1);
    assert.ifError(e1);
    if (!comite?.length) {
      console.log('[1591] comitê vazio no ciclo vivo — asserção não exercida');
      return;
    }
    const membroDoComite = comite[0].member_id;

    const { data: simVivo, error: e2 } = await sb.rpc('is_selection_committee_member', {
      p_member_id: membroDoComite, p_cycle_id: null,
    });
    assert.ifError(e2);
    assert.equal(simVivo, true, 'membro do comitê do ciclo vivo tem de dar true');

    const { data: simCiclo, error: e3 } = await sb.rpc('is_selection_committee_member', {
      p_member_id: membroDoComite, p_cycle_id: vivo.id,
    });
    assert.ifError(e3);
    assert.equal(simCiclo, true, 'e true também para o ciclo específico dele');

    // Alguém que NÃO está no comitê: o predicado não pode conceder.
    const { data: fora, error: e4 } = await sb
      .from('members').select('id').eq('is_active', true).limit(60);
    assert.ifError(e4);
    const { data: todoComite, error: e5 } = await sb.from('selection_committee').select('member_id');
    assert.ifError(e5);
    const idsComite = new Set((todoComite ?? []).map((r) => r.member_id));
    const naoComite = (fora ?? []).map((m) => m.id).find((id) => !idsComite.has(id));
    assert.ok(naoComite, 'sem alguém fora do comitê, a asserção negativa não é exercida');

    const { data: nao, error: e6 } = await sb.rpc('is_selection_committee_member', {
      p_member_id: naoComite, p_cycle_id: null,
    });
    assert.ifError(e6);
    assert.equal(nao, false, 'quem não é do comitê NÃO pode dar true — seria a chave-mestra');
  });

  it('um ciclo em que a pessoa NÃO está no comitê dá false', { skip: dbGated ? false : skipMsg }, async () => {
    // É o escopo por ciclo: sem ele, o comitê de hoje leria o PII de todos os ciclos passados.
    const { data: linhas, error } = await sb.from('selection_committee').select('member_id, cycle_id');
    assert.ifError(error);
    const { data: cycles, error: e1 } = await sb.from('selection_cycles').select('id');
    assert.ifError(e1);

    const porMembro = new Map();
    for (const l of linhas ?? []) {
      if (!porMembro.has(l.member_id)) porMembro.set(l.member_id, new Set());
      porMembro.get(l.member_id).add(l.cycle_id);
    }
    let alvo = null;
    for (const [member, seus] of porMembro) {
      const outro = (cycles ?? []).map((c) => c.id).find((id) => !seus.has(id));
      if (outro) { alvo = { member, outro }; break; }
    }
    if (!alvo) {
      console.log('[1591] todo membro do comitê está em todos os ciclos — asserção não exercida');
      return;
    }
    const { data, error: e2 } = await sb.rpc('is_selection_committee_member', {
      p_member_id: alvo.member, p_cycle_id: alvo.outro,
    });
    assert.ifError(e2);
    assert.equal(data, false, 'o escopo por ciclo não está segurando');
  });
});

describe('#1591 B — os corpos VIVOS carregam a mudança', () => {
  for (const [fn, marca, oque] of [
    ['get_selection_dashboard', /v_via_committee/, 'a porta do dashboard'],
    ['get_member_by_auth', /selection_committee_active/, 'a flag do nav'],
  ]) {
    it(`${fn}: ${oque} está em produção`, { skip: dbGated ? false : skipMsg }, async () => {
      const { data, error } = await sb.rpc('_audit_function_source', { p_proname: fn });
      assert.ifError(error);
      assert.ok(data?.length > 0, `${fn} não existe no banco`);
      assert.match(data[0].prosrc, marca, `${fn}: a mudança não está viva`);
    });
  }

  it('get_selection_dashboard mantém a checagem de ciclo no corpo VIVO', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: 'get_selection_dashboard' });
    assert.ifError(error);
    assert.match(
      data[0].prosrc,
      /v_via_committee AND NOT public\.is_selection_committee_member\(v_caller_id, v_cycle_id\)/,
      'sem isto, o comitê do ciclo vivo lê o PII de todos os ciclos',
    );
  });
});
