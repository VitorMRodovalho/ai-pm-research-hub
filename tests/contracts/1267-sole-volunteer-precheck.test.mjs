// #1267 (Tribe UX) — surface the sole-volunteer/leader safeguard BEFORE the leave form. Extends
// get_my_tribe_request_context (ADDITIVE) with `can_self_leave` on the has_tribe case, mirroring
// withdraw_from_initiative's remaining_of_kind guard, so the FE routes to the GP without making the
// researcher write a reason first. Static test over the migration + FE island; the body-drift gate
// (Phase C) covers live drift. See #1267.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIG = join(
  __dirname,
  '../../supabase/migrations/20260805000399_1267_sole_volunteer_precheck_context.sql',
);
const TSX = join(__dirname, '../../src/components/tribe/TribeRequestBlock.tsx');
const sql = readFileSync(MIG, 'utf8');
const tsx = readFileSync(TSX, 'utf8');

test('#1267: migration redefine get_my_tribe_request_context', () => {
  assert.match(
    sql,
    /CREATE OR REPLACE FUNCTION public\.get_my_tribe_request_context\(\)/,
    'a migration deve redefinir get_my_tribe_request_context',
  );
});

test('#1267: extensão é ADITIVA (mantém as chaves de #1256 intactas)', () => {
  for (const key of ['eligible', 'ineligible_reason', 'current_tribe_title', 'current_tribe_id', 'current_tribe_initiative_id', 'pending', 'tribes', 'deadline']) {
    assert.match(sql, new RegExp(`'${key}',`), `chave ${key} deve continuar no RETURN`);
  }
});

test('#1267: RETURN expõe can_self_leave', () => {
  assert.match(sql, /'can_self_leave', v_can_self_leave/, 'expõe can_self_leave no payload');
});

test('#1267: can_self_leave espelha o guard do withdraw (required kind + contagem do mesmo kind)', () => {
  // required_engagement_kinds de research_tribe, como no withdraw_from_initiative
  assert.match(sql, /required_engagement_kinds INTO v_kind_required/, 'lê required_engagement_kinds de research_tribe');
  assert.match(sql, /'volunteer' = ANY\(coalesce\(v_kind_required, ARRAY\[\]::text\[\]\)\)/, 'só bloqueia se volunteer for required kind');
  // conta ativos/onboarding do mesmo kind na MESMA initiative que o FE vai deixar
  assert.match(
    sql,
    /count\(\*\) INTO v_active_vol_count[\s\S]*?e\.initiative_id = v_current_tribe_initiative_id[\s\S]*?e\.kind = 'volunteer'[\s\S]*?e\.status IN \('active', 'onboarding'\)/,
    'conta voluntários ativos/onboarding da tribo-alvo',
  );
  assert.match(sql, /v_can_self_leave := v_active_vol_count > 1;/, 'sole volunteer (<=1) => can_self_leave=false');
});

test('#1267: can_self_leave só é computado quando há engagement ativo (initiative_id presente)', () => {
  assert.match(
    sql,
    /IF v_current_tribe_initiative_id IS NOT NULL THEN[\s\S]*?v_can_self_leave/,
    'o pré-check roda dentro do guard de initiative_id não-nulo',
  );
});

// --- FE island (TribeRequestBlock.tsx) ---

test('#1267: o FE lê can_self_leave do contexto', () => {
  assert.match(tsx, /can_self_leave\?: boolean \| null;/, 'a interface Context declara can_self_leave');
  assert.match(tsx, /const blockedSole = canLeave && ctx\.can_self_leave === false;/, 'deriva blockedSole com === false (undefined/null não bloqueia)');
});

test('#1267: quando bloqueado, o FE mostra a mensagem de rota ao GP no lugar do botão', () => {
  assert.match(
    tsx,
    /blockedSole \? \([\s\S]*?copy\.leaveBlockedSoleVolunteer[\s\S]*?\) : \(/,
    'branch blockedSole renderiza a mensagem de rota ao GP antes do formulário',
  );
});

test('#1267: o safeguard server-side (remaining_of_kind) segue como defesa em profundidade no leave()', () => {
  assert.match(
    tsx,
    /typeof data\.remaining_of_kind === 'number'[\s\S]*?setLeaveBlocked\(copy\.leaveBlockedSoleVolunteer\)/,
    'o handler de leave mantém o fallback do retorno remaining_of_kind',
  );
});
