#!/usr/bin/env node
/**
 * Auditoria dos dois gaps que deixam entregáveis das tribos fora da visão
 * do /admin/portfolio:
 *
 *   A. `missing_flag`     — o card é reconhecidamente um entregável (título/tags
 *                           batem com uma das 7 tags de tipo), mas está sem
 *                           `board_items.is_portfolio_item`, logo
 *                           `get_portfolio_dashboard()` não o enxerga.
 *   B. `missing_type_tag` — o card está marcado como item de portfólio, mas sem
 *                           nenhuma tag de tipo (tier=system, domain=board_item),
 *                           então o filtro "Todos os Tipos" do dashboard e o
 *                           bloco `by_type` não o classificam.
 *
 * Toda a lógica vive na RPC `audit_portfolio_flag_tag_gaps()` (migration
 * 20260820215416) — este script é só transporte + formatação, para que o número
 * do relatório e o número que o admin vê nunca divirjam.
 *
 * Uso:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/audit-portfolio-flags-tags.mjs
 *
 * Flags:
 *   --all         inclui iniciativas não-tribo (workgroups, comitês, congressos)
 *   --cycle=N     ciclo que o dashboard consulta (default 3)
 *   --json        imprime o payload cru da RPC
 *   --out=FILE    grava markdown em FILE além de imprimir
 *
 * Saída não-zero apenas em erro de execução: gap encontrado é informação para
 * decisão do GP/líder, não falha de build.
 */
import { writeFileSync } from 'node:fs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const args = process.argv.slice(2);
const hasFlag = (name) => args.includes(`--${name}`);
const getOpt = (name, fallback) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};

const includeNonTribe = hasFlag('all');
const dashboardCycle = Number(getOpt('cycle', '3'));
const asJson = hasFlag('json');
const outFile = getOpt('out', null);

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios.');
  process.exit(1);
}
if (!Number.isInteger(dashboardCycle)) {
  console.error(`--cycle precisa ser inteiro (recebido: ${getOpt('cycle', '3')})`);
  process.exit(1);
}

async function fetchAudit() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/audit_portfolio_flag_tag_gaps`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({
      p_include_non_tribe: includeNonTribe,
      p_dashboard_cycle: dashboardCycle,
    }),
  });
  if (!res.ok) {
    throw new Error(`audit_portfolio_flag_tag_gaps falhou: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

const CONF_ORDER = { alta: 0, media: 1, revisar: 1, baixa: 2 };

/**
 * Escapa um valor para caber numa célula de tabela markdown.
 * A barra invertida sai primeiro: inverter a ordem faria o `\\` inserido pelo
 * escape do pipe ser reescapado, e um título com `\\|` continuaria quebrando a
 * linha. Quebras de linha viram espaço porque encerrariam a linha da tabela.
 * Títulos de card são texto livre digitado pelos líderes — trate como hostil.
 */
const mdCell = (v) =>
  v == null || v === ''
    ? '—'
    : String(v).replace(/\\/g, '\\\\').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');

function tribeLabel(row) {
  return row.tribe_id != null ? `T${row.tribe_id}` : (row.initiative_kind || '—');
}

function renderMarkdown(audit) {
  const s = audit.summary || {};
  const lines = [];
  lines.push(`# Auditoria de flag/tag de portfólio`);
  lines.push('');
  lines.push(`- Gerado em: \`${audit.generated_at}\``);
  lines.push(`- Escopo: \`${audit.scope}\` · ciclo do dashboard: \`${audit.dashboard_cycle}\``);
  lines.push('');
  lines.push('| Métrica | Valor |');
  lines.push('| --- | ---: |');
  lines.push(`| Cards no escopo (não arquivados) | ${s.cards_in_scope ?? 0} |`);
  lines.push(`| Já marcados como item de portfólio | ${s.flagged ?? 0} |`);
  lines.push(`| **Gap A** — entregável sem flag | ${s.missing_flag ?? 0} |`);
  lines.push(`| ↳ dos quais com data-base ou entrega registrada (confiança alta) | ${s.missing_flag_alta ?? 0} |`);
  lines.push(`| **Gap B** — item de portfólio sem tag de tipo | ${s.missing_type_tag ?? 0} |`);
  lines.push(`| Flagged fora do ciclo consultado pelo dashboard | ${s.flagged_outside_dashboard_cycle ?? 0} |`);
  lines.push('');

  const byInit = audit.by_initiative || [];
  if (byInit.length) {
    lines.push('## Por iniciativa');
    lines.push('');
    lines.push('| Tribo | Iniciativa | Cards | Com flag | Gap A | Gap B |');
    lines.push('| --- | --- | ---: | ---: | ---: | ---: |');
    for (const b of byInit) {
      lines.push(`| ${b.tribe_id != null ? `T${b.tribe_id}` : '—'} | ${mdCell(b.initiative_title)} | ${b.cards} | ${b.flagged} | ${b.missing_flag} | ${b.missing_type_tag} |`);
    }
    lines.push('');
  }

  const rows = audit.rows || [];
  for (const [kind, title] of [
    ['missing_flag', 'Gap A — entregáveis sem flag de portfólio'],
    ['missing_type_tag', 'Gap B — itens de portfólio sem tag de tipo'],
  ]) {
    const subset = rows
      .filter((r) => r.gap_kind === kind)
      .sort((a, b) =>
        (CONF_ORDER[a.confidence] ?? 9) - (CONF_ORDER[b.confidence] ?? 9) ||
        (a.tribe_id ?? 999) - (b.tribe_id ?? 999) ||
        a.title.localeCompare(b.title));
    lines.push(`## ${title} (${subset.length})`);
    lines.push('');
    if (!subset.length) {
      lines.push('_Nenhum._');
      lines.push('');
      continue;
    }
    lines.push('| Conf. | Tribo | Card | Status | Base | Prev. | Entregue | Tipo sugerido |');
    lines.push('| --- | --- | --- | --- | --- | --- | --- | --- |');
    for (const r of subset) {
      lines.push(`| ${mdCell(r.confidence)} | ${mdCell(tribeLabel(r))} | ${mdCell(r.title)} | ${mdCell(r.status)} | ${mdCell(r.baseline_date)} | ${mdCell(r.forecast_date)} | ${mdCell(r.actual_completion_date)} | ${mdCell(r.suggested_type)} |`);
    }
    lines.push('');
  }

  lines.push('---');
  lines.push('');
  lines.push('`suggested_type` é heurística consultiva (`portfolio_suggest_item_type`), não verdade:');
  lines.push('a tipificação do entregável é decisão do líder da tribo. Nada é aplicado automaticamente.');
  return lines.join('\n');
}

const audit = await fetchAudit();

if (asJson) {
  console.log(JSON.stringify(audit, null, 2));
} else {
  const md = renderMarkdown(audit);
  console.log(md);
  if (outFile) {
    writeFileSync(outFile, `${md}\n`, 'utf8');
    console.error(`\n[ok] markdown gravado em ${outFile}`);
  }
}
