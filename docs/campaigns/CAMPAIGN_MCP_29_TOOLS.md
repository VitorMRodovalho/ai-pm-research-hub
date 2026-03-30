# Campanha: MCP 29 Tools + Novo Dominio

**Audiencia:** Todos os membros ativos do Ciclo 3 (pesquisadores, lideres, curadores)
**CC:** GP (Vitor Maia Rodovalho)
**Data:** 2026-03-31

---

## Subject (PT)

Nucleo IA — Nova plataforma, 29 ferramentas MCP e como conectar seu assistente de IA

---

## Body HTML (PT)

```html
<div style="font-family: 'Segoe UI', Tahoma, sans-serif; max-width: 640px; margin: 0 auto; color: #1a1a2e;">

  <div style="background: linear-gradient(135deg, #003865, #0d9488); padding: 32px 24px; border-radius: 16px 16px 0 0; text-align: center;">
    <h1 style="color: #fff; font-size: 22px; margin: 0;">Nucleo de IA &amp; GP</h1>
    <p style="color: #b2dfdb; font-size: 14px; margin: 8px 0 0;">Plataforma atualizada &middot; 29 ferramentas MCP &middot; Novo endereco</p>
  </div>

  <div style="background: #fff; padding: 28px 24px; border: 1px solid #e5e7eb; border-top: none;">

    <p style="font-size: 15px; line-height: 1.6;">
      Ola, <strong>{member.name}</strong>!
    </p>

    <p style="font-size: 15px; line-height: 1.6;">
      Temos novidades importantes sobre a plataforma do Nucleo. Nas ultimas sessoes de desenvolvimento, realizamos uma serie de melhorias que impactam diretamente a sua experiencia como membro.
    </p>

    <!-- NOVO ENDERECO -->
    <div style="background: #f0fdf4; border-left: 4px solid #0d9488; padding: 16px 20px; border-radius: 0 8px 8px 0; margin: 20px 0;">
      <h2 style="font-size: 16px; color: #003865; margin: 0 0 8px;">Novo endereco da plataforma</h2>
      <p style="font-size: 14px; margin: 0; line-height: 1.5;">
        A plataforma agora esta em: <a href="https://nucleoia.vitormr.dev" style="color: #0d9488; font-weight: bold;">nucleoia.vitormr.dev</a><br/>
        <span style="color: #6b7280; font-size: 13px;">O endereco anterior (<code>platform.ai-pm-research-hub.workers.dev</code>) continua funcionando &mdash; ele redireciona automaticamente para o novo. Nenhuma acao necessaria da sua parte.</span>
      </p>
    </div>

    <!-- MCP -->
    <div style="background: #eff6ff; border-left: 4px solid #003865; padding: 16px 20px; border-radius: 0 8px 8px 0; margin: 20px 0;">
      <h2 style="font-size: 16px; color: #003865; margin: 0 0 8px;">29 ferramentas MCP &mdash; conecte seu assistente de IA</h2>
      <p style="font-size: 14px; margin: 0; line-height: 1.5;">
        O servidor MCP (Model Context Protocol) do Nucleo agora conta com <strong>29 ferramentas</strong> que permitem que voce consulte e gerencie dados da plataforma diretamente pelo seu assistente de IA favorito &mdash; Claude, ChatGPT, Cursor ou VS Code.
      </p>
      <p style="font-size: 14px; margin: 12px 0 0; line-height: 1.5;">
        <strong>Como conectar:</strong> Acesse o <a href="https://nucleoia.vitormr.dev/mcp" style="color: #003865;">guia de configuracao</a> ou va direto nas configuracoes do seu assistente e adicione a URL: <code style="background: #dbeafe; padding: 2px 6px; border-radius: 4px;">https://nucleoia.vitormr.dev/mcp</code>
      </p>
    </div>

    <!-- POR PERFIL -->
    <h2 style="font-size: 16px; color: #003865; margin: 24px 0 12px;">O que voce pode fazer, por perfil</h2>

    <h3 style="font-size: 14px; color: #0d9488; margin: 16px 0 6px;">Pesquisador</h3>
    <ul style="font-size: 13px; line-height: 1.7; padding-left: 20px; color: #374151;">
      <li><strong>get_my_profile</strong> &mdash; Ver seu perfil, papel, tribo, XP e badges</li>
      <li><strong>get_my_xp_and_ranking</strong> &mdash; Seu XP detalhado e posicao no ranking</li>
      <li><strong>get_my_attendance_history</strong> &mdash; Historico pessoal de presenca</li>
      <li><strong>get_my_certificates</strong> &mdash; Certificacoes, badges e trilhas</li>
      <li><strong>get_my_board_status</strong> &mdash; Cards do board da sua tribo</li>
      <li><strong>get_my_notifications</strong> &mdash; Notificacoes pendentes</li>
      <li><strong>get_upcoming_events</strong> &mdash; Eventos dos proximos 7 dias</li>
      <li><strong>search_hub_resources</strong> &mdash; Buscar na biblioteca de recursos (330+ itens)</li>
      <li><strong>search_board_cards</strong> &mdash; Busca textual em cards do board</li>
      <li><strong>get_hub_announcements</strong> &mdash; Anuncios ativos da plataforma</li>
    </ul>

    <h3 style="font-size: 14px; color: #0d9488; margin: 16px 0 6px;">Lider de Tribo</h3>
    <p style="font-size: 13px; color: #374151; margin: 0 0 4px;">Tudo do pesquisador, mais:</p>
    <ul style="font-size: 13px; line-height: 1.7; padding-left: 20px; color: #374151;">
      <li><strong>get_tribe_dashboard</strong> &mdash; Dashboard completo da tribo (membros, cards, metricas)</li>
      <li><strong>get_my_tribe_members</strong> &mdash; Lista de membros ativos da tribo</li>
      <li><strong>get_my_tribe_attendance</strong> &mdash; Grade de presenca da tribo</li>
      <li><strong>get_meeting_notes</strong> &mdash; Atas de reuniao recentes</li>
      <li><strong>list_tribe_webinars</strong> &mdash; Webinars da tribo/capitulo</li>
      <li><strong>create_board_card</strong> &mdash; Criar card no board</li>
      <li><strong>update_card_status</strong> &mdash; Mover card entre colunas</li>
      <li><strong>create_meeting_notes</strong> &mdash; Criar ata de reuniao</li>
      <li><strong>register_attendance</strong> &mdash; Registrar presenca</li>
      <li><strong>create_tribe_event</strong> &mdash; Criar evento/reuniao</li>
      <li><strong>send_notification_to_tribe</strong> &mdash; Notificar todos da tribo</li>
    </ul>

    <h3 style="font-size: 14px; color: #0d9488; margin: 16px 0 6px;">GP / Administracao / Curador</h3>
    <p style="font-size: 13px; color: #374151; margin: 0 0 4px;">Tudo anterior, mais ferramentas executivas:</p>
    <ul style="font-size: 13px; line-height: 1.7; padding-left: 20px; color: #374151;">
      <li><strong>get_portfolio_overview</strong> &mdash; Visao executiva de todos os boards</li>
      <li><strong>get_adoption_metrics</strong> &mdash; Metricas de adocao do MCP</li>
      <li><strong>get_operational_alerts</strong> &mdash; Alertas de inatividade, atraso, drift</li>
      <li><strong>get_cycle_report</strong> &mdash; Relatorio completo do ciclo</li>
      <li><strong>get_annual_kpis</strong> &mdash; KPIs anuais (metas vs realizado)</li>
      <li><strong>get_chapter_kpis</strong> &mdash; KPIs por capitulo</li>
      <li><strong>get_attendance_ranking</strong> &mdash; Ranking de presenca global</li>
      <li><strong>get_comms_pending_webinars</strong> &mdash; Webinars pendentes de comunicacao</li>
    </ul>

    <!-- NOTA IMPORTANTE -->
    <div style="background: #fef3c7; border-left: 4px solid #f59e0b; padding: 16px 20px; border-radius: 0 8px 8px 0; margin: 20px 0;">
      <h3 style="font-size: 14px; color: #92400e; margin: 0 0 6px;">Nota sobre atualizacoes futuras</h3>
      <p style="font-size: 13px; color: #78350f; margin: 0; line-height: 1.5;">
        A cada sprint, novas ferramentas e melhorias serao adicionadas ao MCP. Para acessar ferramentas novas, basta <strong>desconectar e reconectar</strong> o servidor MCP no seu assistente de IA (ex: Claude &rarr; Settings &rarr; Connected Apps &rarr; nucleo-ia &rarr; Disconnect &rarr; Reconnect). Isso <strong>nao afeta</strong> quem ja esta conectado &mdash; as ferramentas anteriores continuam funcionando normalmente.
      </p>
    </div>

    <!-- STACK TECNICA -->
    <p style="font-size: 13px; color: #6b7280; line-height: 1.5; margin-top: 24px;">
      <strong>Stack atual:</strong> Astro 6.1 &middot; TypeScript 6 &middot; React 19 &middot; Tailwind 4 &middot; Supabase &middot; Cloudflare Workers &middot; MCP SDK 1.28 &middot; 19 Edge Functions &middot; 779 testes automatizados &middot; Custo mensal: $0
    </p>

    <div style="text-align: center; margin: 28px 0 8px;">
      <a href="https://nucleoia.vitormr.dev" style="display: inline-block; background: #003865; color: #fff; padding: 12px 28px; border-radius: 8px; text-decoration: none; font-weight: bold; font-size: 14px;">Acessar a Plataforma</a>
    </div>

    <div style="text-align: center; margin: 8px 0 0;">
      <a href="https://nucleoia.vitormr.dev/mcp" style="display: inline-block; background: #0d9488; color: #fff; padding: 10px 24px; border-radius: 8px; text-decoration: none; font-weight: bold; font-size: 13px;">Guia de Configuracao MCP</a>
    </div>

  </div>

  <div style="background: #f9fafb; padding: 16px 24px; border-radius: 0 0 16px 16px; border: 1px solid #e5e7eb; border-top: none; text-align: center;">
    <p style="font-size: 12px; color: #9ca3af; margin: 0;">
      Nucleo de Estudos e Pesquisa em IA &amp; GP &mdash; PMI-GO &middot; PMI-CE &middot; PMI-DF &middot; PMI-MG &middot; PMI-RS<br/>
      <a href="{unsubscribe_url}" style="color: #9ca3af;">Descadastrar</a>
    </p>
  </div>

</div>
```

---

## Body Text (PT)

```
Ola, {member.name}!

Temos novidades importantes sobre a plataforma do Nucleo de IA & GP.

NOVO ENDERECO
A plataforma agora esta em: https://nucleoia.vitormr.dev
O endereco anterior continua funcionando (redireciona automaticamente).

29 FERRAMENTAS MCP
O servidor MCP agora conta com 29 ferramentas que permitem consultar e gerenciar dados da plataforma pelo seu assistente de IA (Claude, ChatGPT, Cursor, VS Code).

Como conectar: adicione a URL https://nucleoia.vitormr.dev/mcp nas configuracoes do seu assistente.
Guia completo: https://nucleoia.vitormr.dev/mcp

FERRAMENTAS POR PERFIL

Pesquisador: get_my_profile, get_my_xp_and_ranking, get_my_attendance_history, get_my_certificates, get_my_board_status, get_my_notifications, get_upcoming_events, search_hub_resources, search_board_cards, get_hub_announcements

Lider de Tribo (tudo acima +): get_tribe_dashboard, get_my_tribe_members, get_my_tribe_attendance, get_meeting_notes, list_tribe_webinars, create_board_card, update_card_status, create_meeting_notes, register_attendance, create_tribe_event, send_notification_to_tribe

GP/Admin/Curador (tudo acima +): get_portfolio_overview, get_adoption_metrics, get_operational_alerts, get_cycle_report, get_annual_kpis, get_chapter_kpis, get_attendance_ranking, get_comms_pending_webinars

NOTA: Novas ferramentas serao adicionadas a cada sprint. Para acessar as novas, basta desconectar e reconectar o MCP no seu assistente. As anteriores continuam funcionando normalmente.

Acesse: https://nucleoia.vitormr.dev
Guia MCP: https://nucleoia.vitormr.dev/mcp
```

---

## Instrucoes de envio

1. Acesse `/admin/campaigns` na plataforma
2. Crie um novo template com o subject e body acima
3. Crie um send com audiencia: "Todos os membros ativos do Ciclo 3"
4. Preview antes de enviar
5. Disparar

Variaveis disponiveis no template:
- `{member.name}` — nome do membro
- `{member.tribe}` — nome da tribo
- `{member.chapter}` — capitulo PMI
- `{platform.url}` — https://nucleoia.vitormr.dev
- `{unsubscribe_url}` — link de descadastro
