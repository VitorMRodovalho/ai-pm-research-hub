/// <reference types="https://esm.sh/@supabase/functions-js@2.116.0/src/edge-runtime.d.ts" />
import { COMMS_ORIGIN } from '../_shared/comms-host.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { isServiceRoleToken } from '../_shared/service-auth.ts'

// #2273 — send-portal-account-setup
//
// A SEGUNDA VIA de acesso do portal do token. O caminho primário é o OAuth que a pessoa já
// consegue usar sozinha (88% das contas nascem dele: google 107, linkedin_oidc 31, azure 7,
// contra 23 de OTP). Esta função existe para quem NÃO tem Google/LinkedIn no endereço do
// cadastro, e é despachada por `request_portal_account_setup` via pg_net.
//
// Ela vive numa Edge Function por um motivo único e não-negociável: só a Admin API cria sessão
// de auth. O Postgres não consegue emitir um link que vire login, então a metade que gera o link
// tem de estar aqui. Todo o resto da decisão (quem é a pessoa, qual o endereço) continua no
// servidor, e é RE-RESOLVIDO aqui do zero.
//
// ⚠️ O PAYLOAD TRAZ SÓ O TOKEN DO PORTAL, de propósito. Se ele carregasse o e-mail, o
// destinatário teria sido escolhido fora do servidor — e a armadilha da seção 4 do handoff de
// 14/09 voltaria pela porta da frente: o reconhecimento liga conta nova a membro pelo e-mail
// PRIMÁRIO DO MEMBRO, e um acesso criado em outro endereço nasce ghost. Por isso a resolução é
// refeita aqui, e o endereço nunca atravessa a fronteira em nenhum sentido.
//
// #2427 — SEGUNDA ENTRADA: `{ member_id }`, despachada por `admin_send_member_access` para quem
// nasceu FORA do funil (criado pelo GP na tela ou por SQL), e que por isso não tem token de
// portal. Mesma regra: o payload traz só o id, e tudo é re-resolvido aqui. A diferença é a
// AUTORIZAÇÃO: o token do portal é a prova de que o pedido veio da pessoa; aqui a prova é uma
// linha `member.access_invite_requested` recente no audit, que só a RPC (com `manage_member`)
// escreve. Sem ela a EF recusa, então uma chamada service_role solta não dispara convite.
//
// ⚠️ E o e-mail NÃO volta no retorno, nem em log. `pg_net` guarda a resposta em
// `net._http_response`, e um endereço ecoado ali seria PII num lugar que ninguém audita —
// a mesma razão pela qual `send-account-claim` devolve só `{ ok: true }`.

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })

const PLATFORM = `${COMMS_ORIGIN}`
// A sessão abre no cockpit, que é para onde `/onboarding` redireciona (302) e onde o Nav roda
// `get_member_by_auth` — o first_link que liga a conta ao membro. É o passo que fecha a jornada.
const REDIRECT_TO = `${PLATFORM}/workspace`
// O link do Supabase Auth vale 1h por padrão; o texto do e-mail precisa dizer o mesmo número.
const EXPIRES_IN_MINUTES = 60
// #2427: o pedido do GP autoriza UM envio, e só por pouco tempo. O pg_net despacha em segundos;
// uma janela larga deixaria um pedido antigo servir de autorização para um envio tardio.
const REQUEST_WINDOW_MINUTES = 10

type Sb = ReturnType<typeof createClient<any, 'public', any>>

/** O endereço: o PRIMÁRIO do membro, com `members.email` como fallback. */
async function primaryEmailOf(sb: Sb, member: { id: string; email: string | null }) {
  const { data: primaryRow } = await sb
    .from('member_emails')
    .select('email')
    .eq('member_id', member.id)
    .eq('is_primary', true)
    .maybeSingle()
  return (primaryRow?.email ?? member.email ?? '').toString().trim()
}

/**
 * O link. MEDIDO ponta a ponta em 14/09 contra uma fixture em domínio reservado: `generateLink`
 * com `type: 'magiclink'` para um endereço que NÃO existia em auth.users devolveu link e CRIOU a
 * identidade (`link_kind: magiclink`, `auth.users` +1). O fallback para `invite` fica como rede,
 * não como caminho esperado: ele salva se uma versão futura do GoTrue voltar a recusar magiclink
 * para endereço desconhecido. Enumerar auth.users para decidir o tipo não é opção — o PostgREST
 * não expõe o schema `auth`.
 */
async function actionLinkFor(sb: Sb, email: string): Promise<{ link: string | null; kind: string; error?: string }> {
  const magic = await sb.auth.admin.generateLink({
    type: 'magiclink',
    email,
    options: { redirectTo: REDIRECT_TO },
  })
  if (magic.data?.properties?.action_link) return { link: magic.data.properties.action_link, kind: 'magiclink' }
  const invite = await sb.auth.admin.generateLink({
    type: 'invite',
    email,
    options: { redirectTo: REDIRECT_TO },
  })
  if (invite.error) return { link: null, kind: 'invite', error: invite.error.message }
  return { link: invite.data?.properties?.action_link ?? null, kind: 'invite' }
}

/** #2427 — convite para membro criado fora do funil. Autorizado pelo pedido recente no audit. */
async function handleMemberInvite(sb: Sb, memberId: string) {
  const { data: member, error: mmErr } = await sb
    .from('members')
    .select('id, name, email, auth_id, is_active, member_status')
    .eq('id', memberId)
    .maybeSingle()
  if (mmErr) return json({ error: 'Member lookup failed', detail: mmErr.message }, 500)
  if (!member) return json({ error: 'Member row missing', skipped: true }, 200)
  if (member.is_active !== true || member.member_status !== 'active') {
    return json({ error: 'Member inactive', skipped: true }, 200)
  }
  if (member.auth_id) return json({ ok: true, skipped: 'already_linked' }, 200)

  // A autorização: um pedido da RPC nos últimos minutos, e nenhum envio depois dele. O segundo
  // termo faz o pedido valer UMA vez: um reenvio do mesmo payload não gera um segundo e-mail.
  const since = new Date(Date.now() - REQUEST_WINDOW_MINUTES * 60_000).toISOString()
  const { data: reqRow, error: rErr } = await sb
    .from('admin_audit_log')
    .select('id, created_at')
    .eq('action', 'member.access_invite_requested')
    .eq('target_id', member.id)
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (rErr) return json({ error: 'Request lookup failed', detail: rErr.message }, 500)
  if (!reqRow) return json({ error: 'No recent request', skipped: true }, 200)

  const { count: sentAfter, error: sErr } = await sb
    .from('admin_audit_log')
    .select('id', { count: 'exact', head: true })
    .eq('action', 'member.access_invite_sent')
    .eq('target_id', member.id)
    .gt('created_at', reqRow.created_at)
  if (sErr) return json({ error: 'Sent lookup failed', detail: sErr.message }, 500)
  if ((sentAfter ?? 0) > 0) return json({ ok: true, skipped: 'already_sent_for_request' }, 200)

  const email = await primaryEmailOf(sb, member)
  if (!email) return json({ error: 'No email to send to', skipped: true }, 200)

  const { link, kind, error: linkErr } = await actionLinkFor(sb, email)
  if (linkErr) return json({ error: 'generateLink failed', detail: linkErr }, 502)
  if (!link) return json({ error: 'No action link produced' }, 502)

  const firstName = (member.name ?? '').toString().split(/\s+/)[0] || 'voluntário(a)'
  const { error: sendErr } = await sb.rpc('campaign_send_one_off', {
    p_template_slug: 'member_access_invite',
    p_to_email: email,
    p_variables: {
      first_name: firstName,
      access_url: link,
      platform_url: PLATFORM,
      expires_in_minutes: EXPIRES_IN_MINUTES,
    },
    p_metadata: {
      source: 'send-portal-account-setup',
      member_id: member.id,
      link_kind: kind,
      issue: 2427,
    },
  })
  if (sendErr) return json({ error: 'Dispatch failed', detail: sendErr.message }, 502)

  await sb.from('admin_audit_log').insert({
    actor_id: member.id,
    action: 'member.access_invite_sent',
    target_type: 'member',
    target_id: member.id,
    changes: { link_kind: kind, request_audit_id: reqRow.id },
    metadata: { source: 'send-portal-account-setup', issue: 2427 },
  })

  return json({ ok: true, link_kind: kind })
}

Deno.serve(async (req) => {
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const srk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    if (!url || !srk) return json({ error: 'Missing supabase env' }, 500)

    // Service-role gate (#738): env-key exato, senão PostgREST verifica a assinatura do JWT.
    // Aceita o `service_role_key` do vault que o pg_net despacha; recusa token forjado.
    const ah = req.headers.get('Authorization') ?? ''
    const tk = ah.replace(/^Bearer\s+/i, '').trim()
    if (!tk) return json({ error: 'No token' }, 401)
    if (!(await isServiceRoleToken(url, tk))) {
      return json({ error: 'Forbidden: service_role required' }, 403)
    }

    const body = await req.json().catch(() => ({}))
    const sb = createClient<any, 'public', any>(url, srk, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const memberIdParam = (body?.member_id ?? '').toString()
    if (memberIdParam) {
      if (!/^[0-9a-f-]{36}$/i.test(memberIdParam)) return json({ error: 'Bad member_id' }, 400)
      return await handleMemberInvite(sb, memberIdParam)
    }

    const portalToken = (body?.portal_token ?? '').toString()
    if (!portalToken || portalToken.length < 16) {
      return json({ error: 'Missing or short portal_token' }, 400)
    }

    // ── 1. Revalida o token do portal. Sem consumir: `access_count` mede o clique no e-mail,
    //       e um pedido de acesso não é um clique. Somar os dois apagaria esse sinal.
    const { data: tokenRow, error: tErr } = await sb
      .from('onboarding_tokens')
      .select('source_id, source_type, expires_at')
      .eq('token', portalToken)
      .eq('source_type', 'pmi_application')
      .maybeSingle()

    if (tErr) return json({ error: 'Token lookup failed', detail: tErr.message }, 500)
    if (!tokenRow) return json({ error: 'Token not found', skipped: true }, 200)
    if (new Date(tokenRow.expires_at).getTime() < Date.now()) {
      return json({ error: 'Token expired', skipped: true }, 200)
    }

    // ── 2. A candidatura, que precisa estar aprovada.
    const { data: app, error: aErr } = await sb
      .from('selection_applications')
      .select('id, applicant_name, status')
      .eq('id', tokenRow.source_id)
      .maybeSingle()

    if (aErr) return json({ error: 'Application lookup failed', detail: aErr.message }, 500)
    if (!app) return json({ error: 'Application not found', skipped: true }, 200)
    if (app.status !== 'approved') return json({ error: 'Not approved', skipped: true }, 200)

    // ── 3. O membro, pelo MESMO resolvedor que a RPC usa (engagement, depois e-mail). Chamar a
    //       função em vez de reescrever a consulta é o que impede as duas metades de divergirem —
    //       e é a metade que diverge em silêncio que manda o e-mail para o endereço errado.
    const { data: memberId, error: mErr } = await sb
      .rpc('_portal_member_for_application', { p_application_id: app.id })
    if (mErr) return json({ error: 'Member resolution failed', detail: mErr.message }, 500)
    if (!memberId) return json({ error: 'No member for application', skipped: true }, 200)

    const { data: member, error: mmErr } = await sb
      .from('members')
      .select('id, name, email, auth_id')
      .eq('id', memberId)
      .maybeSingle()
    if (mmErr) return json({ error: 'Member lookup failed', detail: mmErr.message }, 500)
    if (!member) return json({ error: 'Member row missing', skipped: true }, 200)

    // Já tem acesso: mandar link de criação convidaria a nascer uma SEGUNDA identidade.
    if (member.auth_id) return json({ ok: true, skipped: 'already_linked' }, 200)

    // ── 4. O endereço: o PRIMÁRIO do membro, com `members.email` como fallback. Nunca
    //       `selection_applications.email`, que é o que envelhece sozinho.
    const email = await primaryEmailOf(sb, member)
    if (!email) return json({ error: 'No email to send to', skipped: true }, 200)

    // ── 5. O link (ver `actionLinkFor`).
    const firstName = (member.name ?? app.applicant_name ?? '').toString().split(/\s+/)[0] || 'voluntário(a)'
    const { link: actionLink, kind: linkKind, error: linkErr } = await actionLinkFor(sb, email)
    if (linkErr) return json({ error: 'generateLink failed', detail: linkErr }, 502)
    if (!actionLink) return json({ error: 'No action link produced' }, 502)

    // ── 6. A entrega sai pelo caminho central (`campaign_send_one_off`), e não por um fetch
    //       direto ao Resend, para herdar supressão, idempotência e métrica — que é exatamente o
    //       que fez o reenvio de 14/09 ser `email.delivered` em 3 segundos.
    const { error: sendErr } = await sb.rpc('campaign_send_one_off', {
      p_template_slug: 'portal_account_setup',
      p_to_email: email,
      p_variables: {
        first_name: firstName,
        access_url: actionLink,
        expires_in_minutes: EXPIRES_IN_MINUTES,
      },
      p_metadata: {
        source: 'send-portal-account-setup',
        application_id: app.id,
        member_id: member.id,
        link_kind: linkKind,
        issue: 2273,
      },
    })
    if (sendErr) return json({ error: 'Dispatch failed', detail: sendErr.message }, 502)

    await sb.from('admin_audit_log').insert({
      actor_id: member.id,
      action: 'portal.account_setup_sent',
      target_type: 'selection_application',
      target_id: app.id,
      // Sem o endereço: `link_kind` já diz se a identidade foi criada agora ou se já existia,
      // que é o que um auditor precisa saber.
      changes: { member_id: member.id, link_kind: linkKind },
      metadata: { source: 'send-portal-account-setup', issue: 2273 },
    })

    // Nunca ecoa o endereço: a resposta do pg_net fica em `net._http_response`.
    return json({ ok: true, link_kind: linkKind })
  } catch (err) {
    // O erro fica no log da EF e NAO no corpo: a mensagem de um erro do Auth ou do Postgres
    // carrega o endereco (`duplicate key ... (email)=(...)`), e o corpo desta resposta vai para
    // `net._http_response`, exatamente o lugar que o comentario do topo diz nunca alcancar.
    // Ver #2302 (js/stack-trace-exposure) e o comentario de PII no inicio do arquivo.
    console.error('[send-portal-account-setup] unhandled', err)
    return json({ error: 'Unhandled' }, 500)
  }
})
