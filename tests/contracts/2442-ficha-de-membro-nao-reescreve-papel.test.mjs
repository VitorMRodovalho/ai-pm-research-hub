// tests/contracts/2442-ficha-de-membro-nao-reescreve-papel.test.mjs
// Estrutural (le so o arquivo da tela): registrar em "test:structural".
/**
 * A ficha de membro nao reescreve papel nem designacoes que o GP nao mudou.
 *
 * O CASO (#2442): o select "Papel principal" so conhece 9 papeis. Para `chapter_liaison`,
 * `deputy_manager` ou `guest`, o navegador selecionava a primeira opcao ("Gerente"), e o Salvar
 * enviava `manager` para `admin_update_member`, que grava com COALESCE. Medido em 24/09/2026:
 * 20 membros ativos nessa situacao. A grade de papeis, por sua vez, enviava so o que ela mostra,
 * e designacoes fora dela (`comms_team`, `co_gp`...) sumiam. E o botao de convite (#2427) nao
 * travava: dois cliques mandaram dois e-mails.
 *
 * As funcoes de decisao recebem texto puro: sao as MESMAS que julgam a tela real e a adulterada.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const PAGE = readFileSync('src/pages/admin/member/[id].astro', 'utf8');

export function regrasDaFicha(src) {
  const code = maskJsComments(src);
  const opcaoReal = code.search(/\$\{roleOutsideList \? `<option value="\$\{escapeAttr\(m\.operational_role\)\}" selected>/);
  const opcoesFixas = code.search(/Object\.entries\(ROLE_LABELS\)\.filter/);
  return {
    // o papel real entra como opcao SELECIONADA, antes das fixas
    papelForaDaListaVisivel: opcaoReal > 0 && opcoesFixas > opcaoReal,
    // "fora da lista" inclui guest, que as opcoes fixas filtram
    guestContaComoFora: /roleOutsideList = !!m\?\.operational_role\s*&& !Object\.keys\(ROLE_LABELS\)\.some\(\(k\) => k !== 'guest' && k === m\.operational_role\)/.test(code),
    papelSoSeMudou: /p_operational_role: split\.operationalRole === orig\.operational_role \? null : split\.operationalRole,/.test(code),
    designacoesSoSeMudaram: /p_designations: visibleChanged \? nextDesig : null,/.test(code),
    preservaInvisiveis: /nextDesig = \[\.\.\.origDesig\.filter\(\(d\) => !grid\.has\(d\)\), \.\.\.split\.designations\]/.test(code),
    conviteTravado: /if \(_inviteInFlight\) return false;\s*_inviteInFlight = true;[\s\S]{0,300}?try \{\s*return await sendAccessInviteOnce\(id\);\s*\} finally \{\s*_inviteInFlight = false;/.test(code),
  };
}

const TUDO = {
  papelForaDaListaVisivel: true, guestContaComoFora: true, papelSoSeMudou: true,
  designacoesSoSeMudaram: true, preservaInvisiveis: true, conviteTravado: true,
};

test('#2442: a ficha nao reescreve papel nem designacoes que o GP nao mudou', () => {
  assert.deepEqual(regrasDaFicha(PAGE), TUDO);
});

test('#2442 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const mut = (a, b) => {
    const m = PAGE.replace(a, b);
    assert.notEqual(m, PAGE, `mutacao nao aplicou: ${a}`);
    return regrasDaFicha(m);
  };
  // 1: opcao do papel real removida (volta a cair em "Gerente")
  assert.equal(mut('${roleOutsideList ? `<option', '${false ? `<option').papelForaDaListaVisivel, false);
  // 2: opcao do papel real sem `selected`
  assert.equal(mut('${escapeAttr(m.operational_role)}" selected>', '${escapeAttr(m.operational_role)}">').papelForaDaListaVisivel, false);
  // 3: guest deixa de contar como fora da lista
  assert.equal(mut("k !== 'guest' && k === m.operational_role", 'k === m.operational_role').guestContaComoFora, false);
  // 4: papel enviado sempre (o defeito original)
  assert.equal(mut('split.operationalRole === orig.operational_role ? null : split.operationalRole,', 'split.operationalRole,').papelSoSeMudou, false);
  // 5: designacoes enviadas sempre
  assert.equal(mut('visibleChanged ? nextDesig : null,', 'nextDesig,').designacoesSoSeMudaram, false);
  // 6: designacoes invisiveis descartadas
  assert.equal(mut('...origDesig.filter((d) => !grid.has(d)), ', '').preservaInvisiveis, false);
  // 7: trava do convite removida
  assert.equal(mut('if (_inviteInFlight) return false;', '').conviteTravado, false);
  // 8: trava nunca liberada (o botao morreria depois do primeiro uso)
  assert.equal(mut('} finally {\n      _inviteInFlight = false;', '} finally {\n      void 0;').conviteTravado, false);
  // 9: a regra so em comentario nao conta
  assert.equal(mut('if (_inviteInFlight) return false;', '// if (_inviteInFlight) return false;').conviteTravado, false);
});
