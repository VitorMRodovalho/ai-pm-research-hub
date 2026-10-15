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
