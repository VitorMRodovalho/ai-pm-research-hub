// tests/contracts/1590-gate-da-pagina-fala-a-lingua-do-servidor.test.mjs
//
// #1590 (onda A) — a tela recusava quem o servidor autorizava.
//
// Medido em 12/08/2026 sobre `/admin/selection`, ciclo `cycle4-2026` aberto:
//
//   superficie                                    predicado                                  passam
//   drawer global (navigation.config.ts:164)      tier>=admin U sponsor U comite               11
//   get_selection_dashboard (a RPC)               view_internal_analytics U comite do ciclo    11
//   a pagina (canAccessAdminRoute)                tier>=admin                                   2
//
// As 9 pessoas no meio (1 avaliador, 4 observadores do ciclo vivo, 4 sponsors) viam a entrada no
// menu, a RPC as autorizava, e a pagina mostrava `#sel-denied` ANTES de a RPC ser chamada. Prova
// comportamental daquele dia, em transacao abortada atuando como o avaliador: get_selection_dashboard()
// devolveu payload de 3 chaves e ZERO erro.
//
// O #1591 (07/08) ensinou o eixo de comite ao drawer, a gemea cliente em Nav.astro e as RPCs.
// `src/lib/admin/route-access.ts` (extraido de `constants.ts` nesta onda) era o unico dos quatro
// consumidores que nao conhecia nem esse eixo nem o V4 de capacidades.
//
// POR QUE ESTE ARQUIVO IMPORTA O MODULO EM VEZ DE LER O TEXTO DELE:
// um guard de regex sobre a fonte fica verde com o mapa presente e o `canAccessAdminRoute`
// ignorando o mapa. Aqui o predicado e EXERCIDO. A extracao para `route-access.ts` existe para
// tornar isso possivel: `constants.ts` arrasta i18n e dados de tribo.
//
// AS DUAS DIRECOES SAO OBRIGATORIAS. Um guard que so afirma "o avaliador entra" fica verde se o
// gate for removido inteiro.

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import {
  canAccessAdminRoute,
  hasSelectionCommitteeAccess,
} from '../../src/lib/admin/route-access.ts';
import { setCapabilities, clearCapabilities } from '../../src/lib/permissions.ts';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

// Perfis reais medidos em 12/08/2026 (nomes fora daqui de proposito — o repo e publico).
const FERNANDO = { operational_role: 'tribe_leader', designations: [], is_superadmin: false, selection_committee_role: 'evaluator' };
const OBSERVADOR = { operational_role: 'chapter_liaison', designations: ['chapter_board'], is_superadmin: false, selection_committee_role: 'observer' };
const GP = { operational_role: 'manager', designations: ['co_gp'], is_superadmin: true, selection_committee_role: 'evaluator' };
const PESQUISADOR = { operational_role: 'researcher', designations: [], is_superadmin: false, selection_committee_role: null };
const LIDER_SEM_COMITE = { operational_role: 'tribe_leader', designations: [], is_superadmin: false, selection_committee_role: null };

describe('#1590 A — o eixo de comite abre a rota de selecao', () => {
  it('avaliador de comite sem tier admin ENTRA', () => {
    assert.equal(canAccessAdminRoute(FERNANDO, 'admin_selection'), true,
      'era exatamente o caso relatado: tribe_leader, designations vazio, evaluator do ciclo vivo');
  });

  it('observador de comite ENTRA (observar o processo e o papel dele)', () => {
    assert.equal(canAccessAdminRoute(OBSERVADOR, 'admin_selection'), true);
  });

  it('GP continua entrando', () => {
    assert.equal(canAccessAdminRoute(GP, 'admin_selection'), true);
  });

  // A INVERSA. Sem estas, remover o gate inteiro deixaria o arquivo verde.
  it('quem nao e do comite nem tem tier CONTINUA RECUSADO', () => {
    assert.equal(canAccessAdminRoute(PESQUISADOR, 'admin_selection'), false);
    assert.equal(canAccessAdminRoute(LIDER_SEM_COMITE, 'admin_selection'), false,
      'ser tribe_leader nao pode virar porta: sao 8 lideres, e o comite tem 3 avaliadores');
  });

  it('sem membro nao entra ninguem', () => {
    assert.equal(canAccessAdminRoute(null, 'admin_selection'), false);
    assert.equal(canAccessAdminRoute(undefined, 'admin_selection'), false);
  });

  it('o eixo NAO vaza para outras rotas', () => {
    // O mapa e por rota justamente para isto: comite nao e credencial de admin em geral.
    for (const rota of ['admin_settings', 'admin_member_edit', 'admin_comms', 'admin_webinars']) {
      assert.equal(canAccessAdminRoute(FERNANDO, rota), false,
        `${rota} nao declara o eixo e nao pode abrir para o comite`);
    }
  });

  it('papel solto no perfil nao abre rota que nao declara o eixo', () => {
    assert.equal(hasSelectionCommitteeAccess(FERNANDO, undefined), false);
    assert.equal(hasSelectionCommitteeAccess(FERNANDO, 'any'), true);
    assert.equal(hasSelectionCommitteeAccess(OBSERVADOR, 'evaluator'), false,
      "'evaluator' e mais estrito que 'any' — observador nao pontua (#1591 2a parte)");
  });
});

describe('#1590 B — a pagina espelha o publico do DRAWER, e nao o predicado mais largo da RPC', () => {
  after(() => clearCapabilities());

  // Sponsor e a leitura institucional (presidente do capitulo anfitriao). Ja estava declarada no
  // drawer desde a Wave 1; faltava no gate da pagina, e por isso 4 sponsors viam o link e batiam
  // em `#sel-denied`.
  const SPONSOR = { operational_role: 'sponsor', designations: ['sponsor', 'chapter_board'], is_superadmin: false, selection_committee_role: null };

  it('sponsor entra pela DESIGNACAO, sem depender de capacidade carregada', () => {
    clearCapabilities();
    assert.equal(canAccessAdminRoute(SPONSOR, 'admin_selection'), true);
  });

  // A DECISAO QUE ESTE BLOCO FIXA, e o motivo dela.
  //
  // A primeira versao da correcao espelhava o predicado da RPC (`view_internal_analytics` OU
  // comite). Medido em 12/08/2026: zerava a coorte de 9 e criava 6 no sentido inverso — 6
  // `chapter_liaison` de capitulo entrariam numa rota `lgpdSensitive` (PII de candidato) por uma
  // porta que o menu nunca ofereceu a eles. O servidor autorizar nao e a plataforma oferecer.
  //
  // Se alguem reintroduzir o eixo de capacidade sem decisao do PM, ESTE teste fica vermelho.
  it('chapter_liaison com view_internal_analytics NAO entra por capacidade', () => {
    const LIAISON = { operational_role: 'chapter_liaison', designations: ['chapter_liaison'], is_superadmin: false, selection_committee_role: null };
    setCapabilities({
      caller_id: null, person_id: null, is_superadmin: false,
      org_actions: ['view_internal_analytics'], initiative_actions: {}, tribe_actions: {},
    });
    assert.equal(canAccessAdminRoute(LIAISON, 'admin_selection'), false,
      'a RPC autorizaria; a TELA nao oferece. Estender aos 6 do capitulo e decisao do PM.');
  });

  it('nenhuma capacidade org abre a rota sozinha', () => {
    for (const acao of ['manage_comms', 'view_internal_analytics', 'view_chapter_dashboards', 'manage_platform']) {
      setCapabilities({
        caller_id: null, person_id: null, is_superadmin: false,
        org_actions: [acao], initiative_actions: {}, tribe_actions: {},
      });
      assert.equal(canAccessAdminRoute(PESQUISADOR, 'admin_selection'), false, `${acao} nao pode abrir`);
    }
  });
});

describe('#1590 C — a tela esconde a escrita que o servidor recusa', () => {
  const PAGINA = read('src/pages/admin/selection.astro');

  it('o modo de leitura e CSS global, nao varredura JS', () => {
    // A tela reinjeta quase tudo por innerHTML. Uma varredura teria de correr a cada render, e o
    // render que esquecesse de chama-la mostraria o botao. CSS vale para o que nem existe ainda.
    assert.match(PAGINA, /<style is:global>/,
      'CSS com escopo do Astro nao alcanca no que entra por innerHTML');
    assert.match(PAGINA, /body:not\(\[data-sel-can-manage-platform="1"\]\)\s*\[data-sel-requires~="manage_platform"\]/);
    assert.match(PAGINA, /body:not\(\[data-sel-can-manage-member="1"\]\)\s*\[data-sel-requires~="manage_member"\]/);
    assert.match(PAGINA, /body:not\(\[data-sel-can-schedule-interview="1"\]\)\s*\[data-sel-requires~="schedule_interview"\]/);
  });

  it('as superficies de escrita declaram o que exigem', () => {
    for (const [ancora, eixo] of [
      ['data-sel-tab="import"', 'manage_member'],           // import_vep_applications
      ['data-sel-tab="committee"', 'manage_member'],        // manage_selection_committee
      ['id="save-contact-btn"', 'manage_member'],           // update_application_contact
      ['id="recalc-rankings-btn"', 'manage_platform'],      // recalculate_cycle_rankings
      ['id="start-screening-btn"', 'manage_platform'],      // admin_update_application
      ['id="bulk-actions"', 'manage_platform'],             // admin_update_application em lote
      ['id="manual-agendar-section"', 'schedule_interview'],// schedule_interview
    ]) {
      const linha = PAGINA.split('\n').find(l => l.includes(ancora)) ?? '';
      assert.ok(linha, `ancora ausente: ${ancora}`);
      assert.match(linha, new RegExp(`data-sel-requires="[^"]*${eixo}`),
        `${ancora} escreve via RPC que exige ${eixo} e precisa declarar o eixo`);
    }
  });

  it('agendar tem eixo PROPRIO, nao manage_platform reaproveitado', () => {
    // schedule_interview aceita role='lead' no comite OU manage_platform. Colapsar no segundo
    // esconderia o botao de um lead que pode agendar de verdade: falso negativo no lugar do falso
    // positivo, que e trocar um defeito por outro.
    assert.match(PAGINA, /const isCommitteeLead = \(m\?\.selection_committee_role \?\? null\) === 'lead'/);
    assert.match(PAGINA, /set\('data-sel-can-schedule-interview', canManagePlatform \|\| isCommitteeLead\)/);
  });

  it('o modo de escrita e publicado ANTES de o painel aparecer', () => {
    // Ordem invertida faz o botao piscar para quem nao pode usa-lo.
    const gate = PAGINA.match(/function applyGate\(m: any\) \{[\s\S]*?\n  \}/)?.[0] ?? '';
    assert.ok(gate, 'applyGate nao encontrado');
    assert.ok(gate.indexOf('applyWriteMode(m)') < gate.indexOf('showPanel()'),
      'applyWriteMode tem de rodar antes de showPanel');
  });

  it('a ausencia do atributo ESCONDE (fail-closed)', () => {
    // Se applyGate nao rodar, o body fica sem os atributos e o CSS esconde tudo. O inverso
    // (atributo que esconde) mostraria toda a escrita num boot com erro.
    assert.doesNotMatch(PAGINA, /body\[data-sel-cannot-/,
      'o modelo e "sem atributo = escondido"; um atributo de negacao inverteria a falha');
  });

  it('o aviso de leitura existe nos 3 dicionarios', () => {
    for (const [lang, path] of Object.entries({
      'pt-BR': 'src/i18n/pt-BR.ts', 'en-US': 'src/i18n/en-US.ts', 'es-LATAM': 'src/i18n/es-LATAM.ts',
    })) {
      assert.match(read(path), /'admin\.selection\.readonlyNote':/, `${lang}: chave ausente`);
    }
    // E some para quem escreve, senao o GP le "voce esta em modo de leitura" com os botoes na tela.
    assert.match(PAGINA, /data-sel-only-without="manage_platform"/);
    assert.match(PAGINA, /body\[data-sel-can-manage-platform="1"\]\s*\[data-sel-only-without~="manage_platform"\]/);
  });
});

describe('#1590 D — o menu lateral parou de discordar da pagina', () => {
  const SIDEBAR = read('src/components/admin/AdminSidebar.tsx');

  it('a entrada de Selecao consulta a rota, alem da permissao V3', () => {
    const linha = SIDEBAR.split('\n').find(l => l.includes("href: '/admin/selection'")) ?? '';
    assert.ok(linha, 'entrada de selecao ausente');
    assert.match(linha, /routeKey: 'admin_selection'/);
    assert.match(linha, /permission: 'admin\.members\.manage'/,
      'o eixo novo SOMA — tirar a permissao V3 mudaria quem ja via');
  });

  it('o filtro de visibilidade aplica o OR', () => {
    assert.match(SIDEBAR, /visibleRoutes\.has\(item\.routeKey\)/);
    assert.match(SIDEBAR, /canAccessAdminRoute\(member, item\.routeKey\)/);
  });
});
