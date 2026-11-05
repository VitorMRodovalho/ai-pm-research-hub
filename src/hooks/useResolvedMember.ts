import { useEffect, useState } from 'react';
import { onMemberResolved, type MemberResolution } from '../lib/member-ready';

/**
 * #2973: o membro como o Nav o resolveu, para ilhas que chamam RPC autenticada.
 *
 * `ready` fica falso enquanto o Nav não leu a sessão; `memberId` é o id do membro (null sem sessão ou sem cadastro)
 * e muda quando o membro troca. A ilha faz a primeira chamada quando `memberId` existe, e de novo quando ele muda.
 * Chamar antes não é questão de chave: com sessão guardada, o supabase-js espera a sessão e manda o token dela. O
 * defeito é a ilha decidir, e mostrar erro ou vazio, antes de saber se há sessão e membro.
 *
 * #2974 (E1): `capabilitiesFailed` diz que get_caller_capabilities falhou quando o membro chegou. Com ele, a ilha
 * pode separar "não foi possível carregar" de "sua conta não tem acesso".
 */
export function useResolvedMember(): { ready: boolean; memberId: string | null; capabilitiesFailed: boolean } {
  const [resolution, setResolution] = useState<MemberResolution | null>(null);
  useEffect(() => onMemberResolved(setResolution), []);
  const memberId = resolution?.kind === 'member' ? String(resolution.member?.id ?? '') || null : null;
  const capabilitiesFailed = resolution?.kind === 'member' && resolution.capabilitiesFailed === true;
  return { ready: resolution !== null, memberId, capabilitiesFailed };
}
