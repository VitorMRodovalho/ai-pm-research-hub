// ─── Admin route authority ───
//
// Extraído de `src/lib/admin/constants.ts` no #1590. Não é reorganização estética: `constants.ts`
// também carrega rótulos, cores e helpers de avatar, e por isso arrasta `../../data/tribes` e a
// árvore de i18n. Um contrato que quisesse EXERCER o predicado tinha de importar tudo isso, e
// acabava virando teste de regex sobre o texto do arquivo — que é a família de guard decorativo
// que este repositório já pagou várias vezes. Aqui a única dependência é `../permissions.ts`.
//
// `constants.ts` reexporta tudo o que está abaixo, então nenhum call site precisou mudar.
//
// ⚠️ Este módulo é ESPELHO, nunca fronteira. Quem decide é RLS mais o corpo das SECURITY DEFINER
// (ADR-0106). Toda entrada nos mapas abaixo tem de ter o predicado do servidor do lado, porque o
// defeito que originou o arquivo não foi falta de gate: foi gate de TELA discordando do gate de
// DADOS, nas duas direções (#1590: 56 de 89 viam o que não podiam; #1591: quem podia não via).

export type AccessTier = 'superadmin' | 'admin' | 'leader' | 'observer' | 'member' | 'visitor';
export type AdminRouteKey =
  | 'admin_panel' | 'admin_analytics' | 'admin_comms' | 'admin_webinars' | 'admin_curatorship'
  | 'admin_member_edit' | 'admin_manage_actions' | 'admin_selection' | 'admin_settings';

export const ANALYTICS_READONLY_DESIGNATIONS = ['sponsor', 'chapter_liaison', 'curator'] as const;

const TIER_RANK: Record<AccessTier, number> = {
  visitor: 0,
  member: 1,
  observer: 2,
  leader: 3,
  admin: 4,
  superadmin: 5,
};

const ROUTE_MIN_TIER: Record<AdminRouteKey, AccessTier> = {
  admin_panel: 'observer',
  admin_analytics: 'admin',
  admin_comms: 'admin',
  admin_webinars: 'admin',
  admin_curatorship: 'observer',
  admin_member_edit: 'superadmin',
  admin_manage_actions: 'admin',
  admin_selection: 'admin',
  admin_settings: 'superadmin',
};

const ROUTE_ALLOWED_DESIGNATIONS: Partial<Record<AdminRouteKey, readonly string[]>> = {
  admin_analytics: ANALYTICS_READONLY_DESIGNATIONS,
  admin_comms: ['comms_leader', 'comms_member'],
  // #1590: `sponsor` é a leitura institucional (presidente do capítulo anfitrião). Já estava
  // declarada no drawer desde a Wave 1 (`navigation.config.ts:164`); faltava aqui, e por isso 4
  // sponsors viam o link e batiam em `#sel-denied`.
  admin_selection: ['sponsor'],
};

const ROUTE_ALLOWED_OPERATIONAL_ROLES: Partial<Record<AdminRouteKey, readonly string[]>> = {
  // chapter_liaison (#670) + institutional_auditor (FU-3/ADR-0111): read-only roles that reach the
  // aggregate analytics route without admin-tier. Both gate to PII-free aggregate data server-side.
  admin_analytics: ['chapter_liaison', 'institutional_auditor'],
};

// #1590 / #1591 follow-up — os dois eixos que este predicado não conhecia.
//
// O #1591 ensinou o eixo de comitê ao drawer (`navigation.config.ts:201`), à gêmea cliente em
// `Nav.astro:383` e às RPCs. `canAccessAdminRoute` ficou de fora, e é ELE que a página executa.
// Medido em 12/08/2026 sobre `/admin/selection`: 11 pessoas viam a entrada no menu, a RPC
// autorizava as 11, e 2 passavam aqui. As outras 9 (1 avaliador, 4 observadores do ciclo vivo e
// 4 sponsors) batiam em `#sel-denied` ANTES de a RPC que as autorizaria ser chamada.
//
// Os mapas são POR ROTA de propósito: um eixo global mudaria o gate de ~40 telas de uma vez.
const ROUTE_ALLOWED_SELECTION_COMMITTEE: Partial<Record<AdminRouteKey, 'any' | 'evaluator'>> = {
  // 'any' inclui observador: ele acompanha o processo. Quem separa observar de avaliar é o
  // servidor (`submit_evaluation` recusa observer com mensagem própria) mais o modo somente
  // leitura da página; a ROTA trata os dois papéis igual, como o drawer já faz.
  admin_selection: 'any',
};

// ⚠️ NÃO existe eixo de capacidade V4 nesta rota, e a ausência é MEDIDA, não esquecimento.
//
// A primeira versão desta correção espelhava o predicado da RPC
// (`can_by_member('view_internal_analytics')` OU comitê), que é a leitura mais literal de "a tela
// concorda com o servidor". Medido em 12/08/2026: isso zerava a coorte de 9, e criava 6 no sentido
// inverso — 6 `chapter_liaison` de capítulo passariam a entrar numa rota `lgpdSensitive` (PII de
// candidato) por uma porta que o menu nunca ofereceu a eles.
//
// O servidor autorizar não é o mesmo que a plataforma oferecer: quem tem `view_internal_analytics`
// sempre pôde chamar a RPC, mas a tela é onde o dado vira exposição de fato. Então a página espelha
// o PÚBLICO DECLARADO NO DRAWER (tier ∪ sponsor ∪ comitê), que é o mesmo público das 11 pessoas
// medidas, e fica mais estreita que a RPC de propósito.
//
// Estender aos 6 do capítulo é decisão do PM sobre quem vê PII de candidato, não default de código.

export function getAccessTier(isSuperadmin: boolean, opRole: string, desigs: string[]): string {
  if (isSuperadmin) return 'superadmin';
  if (opRole === 'manager') return 'admin';
  if (opRole === 'deputy_manager') return 'admin';
  if (desigs.includes('co_gp')) return 'admin';
  if (opRole === 'tribe_leader') return 'leader';
  if (desigs.includes('sponsor') || desigs.includes('curator') || desigs.includes('chapter_liaison')) return 'observer';
  // institutional_auditor (FU-3/ADR-0111): KPIs-agregados tier — reaches admin_analytics via the
  // route oprole allowlist; never admin-tier write surfaces.
  if (opRole === 'institutional_auditor') return 'observer';
  if (['researcher', 'facilitator', 'communicator'].includes(opRole)) return 'member';
  if (desigs.length > 0) return 'member';
  return 'visitor';
}

export function resolveTierFromMember(member: any): AccessTier {
  if (!member) return 'visitor';
  const opRole = member.operational_role || 'guest';
  const desigs: string[] = member.designations || [];
  return getAccessTier(!!member.is_superadmin, opRole, desigs) as AccessTier;
}

export function hasMinimumTier(current: AccessTier, required: AccessTier): boolean {
  return TIER_RANK[current] >= TIER_RANK[required];
}

export function hasAnyDesignation(member: any, allowed: readonly string[] = []): boolean {
  const desigs: string[] = Array.isArray(member?.designations) ? member.designations : [];
  return allowed.some((designation) => desigs.includes(designation));
}

// #1591: o papel no comitê só abre a rota que DECLARA o eixo — um papel solto no perfil não abre
// nada. Mesma regra da gêmea em `navigation.config.ts:201`.
export function hasSelectionCommitteeAccess(member: any, required?: 'any' | 'evaluator'): boolean {
  if (!required) return false;
  const role = member?.selection_committee_role ?? null;
  if (!role) return false;
  return required === 'any' ? true : role === required;
}

export function canAccessAdminRoute(member: any, route: AdminRouteKey): boolean {
  if (!member) return false;
  const tier = resolveTierFromMember(member);
  if (hasMinimumTier(tier, ROUTE_MIN_TIER[route])) return true;
  const opRole = String(member.operational_role || '');
  const hasAllowedOperationalRole = (ROUTE_ALLOWED_OPERATIONAL_ROLES[route] || []).includes(opRole);
  return hasAnyDesignation(member, ROUTE_ALLOWED_DESIGNATIONS[route])
    || hasAllowedOperationalRole
    || hasSelectionCommitteeAccess(member, ROUTE_ALLOWED_SELECTION_COMMITTEE[route]);
}

export function canReadInternalAnalytics(member: any): boolean {
  return canAccessAdminRoute(member, 'admin_analytics');
}

export function canManageAdminActions(member: any): boolean {
  return canAccessAdminRoute(member, 'admin_manage_actions');
}

export function isAnalyticsReadonlyAudience(member: any): boolean {
  return canReadInternalAnalytics(member) && !canManageAdminActions(member);
}

export function getTier(m: any): string {
  return resolveTierFromMember(m);
}
