/**
 * #2704 — RPC que recusa NO CORPO.
 *
 * Muitas funções do banco devolvem `{error}` ou `{success:false}` com HTTP 200. O supabase-js só
 * preenche `error` em falha de transporte ou do PostgREST, então a tela que testa só `error`
 * mostra sucesso numa recusa. Estes dois helpers tratam os dois canais como um só.
 *
 * Guard: tests/contracts/2704-rpc-erro-no-corpo.test.mjs.
 */

/** A recusa que veio no corpo, ou `null` se não houve. */
export function rpcBodyError(data: unknown): string | null {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  const d = data as Record<string, unknown>;
  if (d.error) return typeof d.error === 'string' ? d.error : JSON.stringify(d.error);
  if (d.success === false || d.ok === false) {
    const why = d.message ?? d.reason;
    return typeof why === 'string' && why ? why : 'action_failed';
  }
  return null;
}

/** Chama a RPC e LANÇA na falha de rede E na recusa do corpo. Devolve `data`. */
export async function rpcChecked<T = any>(sb: any, fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await sb.rpc(fn, args);
  if (error) throw error;
  const bodyError = rpcBodyError(data);
  if (bodyError) throw new Error(bodyError);
  return data as T;
}

/**
 * #3149: lança se o corpo recusou, com a `message` legível quando a função manda uma (a recusa de
 * `register_own_presence`, delegada por `mark_member_present`, traz o código em `error` e o texto em
 * `message`). Para quem já leu `error` do transporte e só precisa do canal do corpo.
 */
export function throwIfRefused(data: unknown): void {
  const why = rpcBodyError(data);
  if (!why) return;
  const msg = (data as Record<string, unknown>).message;
  throw new Error(typeof msg === 'string' && msg ? msg : why);
}
