import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = readFileSync(resolve(ROOT, 'src/pages/reunioes-gerais.astro'), 'utf8');
const ISLAND = readFileSync(resolve(ROOT, 'src/components/agenda/AgendaVivaReservationIsland.tsx'), 'utf8');
const PUBLIC_ISLAND = readFileSync(resolve(ROOT, 'src/components/agenda/AgendaVivaPublic.tsx'), 'utf8');

/**
 * #1545 (superfície real) — `/reunioes-gerais` renderizava as duas ilhas SEM a prop de janela, e o
 * default de `get_geral_agenda_viva` é 'upcoming'. Consequência: a ÚLTIMA REUNIÃO REALIZADA sumia
 * justamente da rota de protagonismo, junto com o bloco que o dono ainda precisava corrigir — o
 * sintoma "clico em Editar e não abre nada" era um botão que não existia.
 *
 * A home (WeeklyScheduleSection) sempre pediu 'both'. Esta rota era a que não pedia.
 *
 * O guard afirma o COMPORTAMENTO (a rota enxerga reunião passada), não a grafia de uma chamada —
 * ver a lição do #1513/#963/#1546 sobre guard que trava refatoração legítima.
 */

test('#1545 /reunioes-gerais pede a janela que inclui a última reunião realizada', () => {
  const publicTag = PAGE.match(/<AgendaVivaPublic[^>]*\/>/)?.[0];
  assert.ok(publicTag, 'a página deve renderizar AgendaVivaPublic');
  assert.match(
    publicTag, /range=(["'{])both/,
    'AgendaVivaPublic sem range="both" volta ao default upcoming e esconde a última realizada',
  );

  const islandTag = PAGE.match(/<AgendaVivaReservationIsland[^>]*\/>/)?.[0];
  assert.ok(islandTag, 'a página deve renderizar AgendaVivaReservationIsland');
  assert.match(
    islandTag, /range=(["'{])both/,
    'a ilha de reserva também precisa da janela: sem ela o dono não alcança o próprio bloco passado ' +
    'e o botão Editar simplesmente não existe (#1545)',
  );
});

test('#1545 a ilha de reserva repassa a janela para a RPC', () => {
  assert.match(
    ISLAND, /get_geral_agenda_viva['"],\s*\{[^}]*p_window:\s*range/,
    'a ilha precisa mandar p_window; a prop sem repasse é decorativa e o default upcoming volta calado',
  );
  // A prop não pode se chamar `window`: a ilha usa o global para addEventListener e toast.
  assert.doesNotMatch(
    ISLAND, /function AgendaVivaReservationIsland\(\{[^}]*\bwindow\s*[,=}]/,
    'a prop de janela não pode se chamar `window` — sombrearia o global que a ilha usa',
  );
});

test('#1545 reunião passada não oferece reservar nem apagar, só corrigir o próprio bloco', () => {
  assert.match(
    ISLAND, /if \(ev\.is_past && !myBlock\) return null/,
    'card de reunião passada sem bloco meu não tem conteúdo válido — não renderizar',
  );
  assert.match(
    ISLAND, /!ev\.is_past && allowed && draft/,
    'o formulário de NOVA reserva não pode aparecer em reunião passada: o servidor recusa com ' +
    'reservation_window_closed, então o botão seria uma promessa falsa',
  );
  assert.match(
    ISLAND, /\{!ev\.is_past && \([\s\S]{0,400}cancelReserveCta/,
    'apagar um bloco que já aconteceu destrói o registro dele — o botão some em reunião passada',
  );
  // O Editar continua existindo em reunião passada — é o ponto inteiro do fix.
  const editBtn = ISLAND.match(/onClick=\{\(\) => startEdit\(myBlock\)\}/);
  assert.ok(editBtn, 'o botão Editar do dono deve continuar existindo, inclusive em reunião passada');
});

test('#1545 AgendaVivaPublic continua aceitando as duas janelas', () => {
  assert.match(
    PUBLIC_ISLAND, /range\s*=\s*['"]upcoming['"]/,
    'o default seguro continua upcoming — quem não pede janela passada não recebe',
  );
  assert.match(
    PUBLIC_ISLAND, /p_window:\s*range/,
    'a prop precisa chegar à RPC',
  );
});

test('#1545 a chave i18n do rótulo de reunião passada tem paridade nos 3 dicionários', () => {
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = readFileSync(resolve(ROOT, `src/i18n/${dict}.ts`), 'utf8');
    assert.ok(
      src.includes("'comp.agendaViva.pastMeeting'"),
      `${dict}.ts não tem comp.agendaViva.pastMeeting`,
    );
  }
});
