import { useEffect, useState } from 'react';
import { onMemberResolved, type MemberResolution } from '../lib/member-ready';

/**
 * #2973: o membro como o Nav o resolveu, para ilhas que chamam RPC autenticada.
 *
 * `ready` fica falso enquanto o Nav não leu a sessão; `memberId` é o id do membro (null sem sessão ou sem cadastro)
 * e muda quando o membro troca. A ilha faz a primeira chamada quando `memberId` existe, e de novo quando ele muda:
 * chamar antes sai com a chave anônima, e a RPC sem EXECUTE para anon responde 401.
 */
export function useResolvedMember(): { ready: boolean; memberId: string | null } {
  const [resolution, setResolution] = useState<MemberResolution | null>(null);
  useEffect(() => onMemberResolved(setResolution), []);
  const memberId = resolution?.kind === 'member' ? String(resolution.member?.id ?? '') || null : null;
  return { ready: resolution !== null, memberId };
}
