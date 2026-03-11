export function getTribeCatalogSummary(
  tribes: any[],
  isSuperadmin: boolean,
  isActiveFn: (tribe: any) => boolean
): string {
  const active = tribes.filter((tribe: any) => isActiveFn(tribe)).length;
  const inactive = tribes.length - active;
  return isSuperadmin
    ? `${active} ativas · ${inactive} inativas`
    : `${active} ativas no catálogo`;
}

export function buildAdminTribeFilterHtml(params: {
  tribes: any[];
  allLabel: string;
  noneLabel: string;
  buildLabel: (tribe: any) => string;
  escapeHtml: (value: unknown) => string;
}): string {
  const { tribes, allLabel, noneLabel, buildLabel, escapeHtml } = params;
  const dynamicOptions = tribes
    .map(
      (tribe: any) =>
        `<option value="${tribe.id}">${String(tribe.id).padStart(2, '0')} — ${escapeHtml(buildLabel(tribe))}</option>`
    )
    .join('');
  return `<option value="">${escapeHtml(allLabel)}</option>${dynamicOptions}<option value="none">${escapeHtml(noneLabel)}</option>`;
}
