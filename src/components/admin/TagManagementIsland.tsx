import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface Tag {
  id: string;
  name: string;
  label_pt: string;
  color: string;
  tier: string;
  domain: string;
  description: string | null;
  event_count: number;
  board_item_count: number;
}

const TIER_LABELS_PT: Record<string, string> = { system: 'Sistema', administrative: 'Admin', semantic: 'Semântica' };
const DOMAIN_LABELS_PT: Record<string, string> = { event: 'Evento', board_item: 'Board', all: 'Todos' };

export default function TagManagementIsland() {
  const t = usePageI18n();
  const [tags, setTags] = useState<Tag[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({ name: '', label_pt: '', color: '#6B7280', tier: 'semantic', domain: 'all', description: '' });
  const [saving, setSaving] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const toast = useCallback((msg: string, type = '') => (window as any).toast?.(msg, type), []);

  const fetchTags = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const { data, error } = await sb.rpc('get_tags');
    if (!error && data) setTags(data);
    else if (error) toast(t('comp.tagMgmt.errorLoad', 'Erro ao carregar tags: ') + error.message, 'error');
    setLoading(false);
  }, [getSb, toast]);

  useEffect(() => {
    const boot = () => { if (getSb()) fetchTags(); else setTimeout(boot, 300); };
    boot();
    window.addEventListener('nav:member', () => fetchTags());
  }, [getSb, fetchTags]);

  const handleCreate = async () => {
    const sb = getSb();
    if (!sb || !form.name.trim() || !form.label_pt.trim()) { toast(t('comp.tagMgmt.fillNameLabel', 'Preencha nome e label'), 'error'); return; }
    setSaving(true);
    const { error } = await sb.rpc('create_tag', {
      p_name: form.name.trim(),
      p_label_pt: form.label_pt.trim(),
      p_color: form.color,
      p_tier: form.tier,
      p_domain: form.domain,
      p_description: form.description.trim() || null,
    });
    if (error) { toast(error.message || t('comp.tagMgmt.errorCreate', 'Erro ao criar tag'), 'error'); setSaving(false); return; }
    toast(t('comp.tagMgmt.tagCreated', 'Tag criada!'), 'success');
    setShowCreate(false);
    setForm({ name: '', label_pt: '', color: '#6B7280', tier: 'semantic', domain: 'all', description: '' });
    setSaving(false);
    fetchTags();
  };

  const handleDelete = async (tagId: string, tagName: string) => {
    if (!confirm(`${t('comp.tagMgmt.confirmDeletePre', 'Excluir tag')} "${tagName}"? ${t('comp.tagMgmt.confirmDeletePost', 'Esta ação não pode ser desfeita.')}`)) return;
    const sb = getSb();
    if (!sb) return;
    const { error } = await sb.rpc('delete_tag', { p_tag_id: tagId });
    if (error) { toast(error.message || t('comp.tagMgmt.errorDelete', 'Erro ao excluir tag'), 'error'); return; }
    toast(t('comp.tagMgmt.tagDeleted', 'Tag excluída'), 'success');
    fetchTags();
  };

  if (loading && tags.length === 0) {
    return <div className="text-center py-8 text-[var(--text-muted)] text-sm animate-pulse">{t('comp.tagMgmt.loading', 'Carregando tags...')}</div>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-lg font-extrabold text-navy">{t('comp.tagMgmt.title', 'Gerenciamento de Tags')}</h2>
          <p className="text-xs text-[var(--text-secondary)]">{t('comp.tagMgmt.subtitle', 'Tags unificadas para eventos e itens de board. Tags de sistema não podem ser editadas.')}</p>
        </div>
        <button onClick={() => setShowCreate(true)}
          className="px-3 py-2 rounded-lg bg-navy text-white text-xs font-semibold hover:opacity-90 cursor-pointer border-0">
          {t('comp.tagMgmt.newTag', '+ Nova Tag')}
        </button>
      </div>

      {/* Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {tags.length === 0 && (
          <p className="text-xs text-[var(--text-muted)] col-span-full text-center py-6">{t('comp.tagMgmt.noTags', 'Nenhuma tag encontrada.')}</p>
        )}
        {tags.map(tag => (
          <div key={tag.id} className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-4 flex flex-col gap-2">
            <div className="flex items-center gap-2">
              <span className="w-3.5 h-3.5 rounded-full flex-shrink-0" style={{ background: tag.color }} />
              <span className="text-sm font-bold text-navy flex-1">{tag.label_pt || tag.name}</span>
              {tag.tier !== 'system' && (
                <button onClick={() => handleDelete(tag.id, tag.label_pt || tag.name)}
                  className="text-red-500 text-[11px] font-semibold hover:underline cursor-pointer bg-transparent border-0">
                  {t('comp.tagMgmt.delete', 'Excluir')}
                </button>
              )}
            </div>
            <div className="text-[11px] text-[var(--text-muted)]">{tag.name}</div>
            <div className="flex gap-1.5 flex-wrap">
              <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-[var(--surface-section-cool)] text-[var(--text-secondary)]">
                {t(`comp.tagMgmt.tier_${tag.tier}`, TIER_LABELS_PT[tag.tier] || tag.tier)}
              </span>
              <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-[var(--surface-section-cool)] text-[var(--text-secondary)]">
                {t(`comp.tagMgmt.domain_${tag.domain}`, DOMAIN_LABELS_PT[tag.domain] || tag.domain)}
              </span>
              {tag.event_count > 0 && (
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-50 text-blue-700">{tag.event_count} {t('comp.tagMgmt.events', 'eventos')}</span>
              )}
              {tag.board_item_count > 0 && (
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-green-50 text-green-700">{tag.board_item_count} {t('comp.tagMgmt.items', 'itens')}</span>
              )}
            </div>
            {tag.description && <div className="text-[11px] text-[var(--text-secondary)]">{tag.description}</div>}
          </div>
        ))}
      </div>

      {/* Create Modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setShowCreate(false)}>
          <div className="bg-[var(--surface-card)] rounded-2xl shadow-xl w-full max-w-md mx-4 p-5" onClick={e => e.stopPropagation()}>
            <h3 className="text-sm font-bold text-navy mb-3">{t('comp.tagMgmt.createTitle', 'Criar Nova Tag')}</h3>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.tagMgmt.nameSlug', 'Nome (slug) *')}</label>
                <input type="text" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                  placeholder="ex: workshop_event" className="w-full border border-[var(--border-default)] rounded-lg px-3 py-2 text-xs bg-[var(--surface-card)] text-[var(--text-primary)]" />
              </div>
              <div>
                <label className="text-[11px] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.tagMgmt.labelPt', 'Label (pt-BR) *')}</label>
                <input type="text" value={form.label_pt} onChange={e => setForm(f => ({ ...f, label_pt: e.target.value }))}
                  placeholder="ex: Workshop" className="w-full border border-[var(--border-default)] rounded-lg px-3 py-2 text-xs bg-[var(--surface-card)] text-[var(--text-primary)]" />
              </div>
              <div className="grid grid-cols-3 gap-2">
                <div>
                  <label className="text-[11px] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.tagMgmt.color', 'Cor')}</label>
                  <input type="color" value={form.color} onChange={e => setForm(f => ({ ...f, color: e.target.value }))}
                    className="w-full h-8 rounded border border-[var(--border-default)] cursor-pointer" />
                </div>
                <div>
                  <label className="text-[11px] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.tagMgmt.tierLabel', 'Tier')}</label>
                  <select value={form.tier} onChange={e => setForm(f => ({ ...f, tier: e.target.value }))}
                    className="w-full border border-[var(--border-default)] rounded-lg px-2 py-1.5 text-xs bg-[var(--surface-card)] text-[var(--text-primary)]">
                    <option value="semantic">{t('comp.tagMgmt.tier_semantic', 'Semântica')}</option>
                    <option value="administrative">{t('comp.tagMgmt.tier_administrative', 'Admin')}</option>
                  </select>
                </div>
                <div>
                  <label className="text-[11px] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.tagMgmt.domainLabel', 'Domínio')}</label>
                  <select value={form.domain} onChange={e => setForm(f => ({ ...f, domain: e.target.value }))}
                    className="w-full border border-[var(--border-default)] rounded-lg px-2 py-1.5 text-xs bg-[var(--surface-card)] text-[var(--text-primary)]">
                    <option value="all">{t('comp.tagMgmt.domain_all', 'Todos')}</option>
                    <option value="event">{t('comp.tagMgmt.domain_event', 'Evento')}</option>
                    <option value="board_item">{t('comp.tagMgmt.domain_board_item', 'Board')}</option>
                  </select>
                </div>
              </div>
              <div>
                <label className="text-[11px] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.tagMgmt.description', 'Descrição')}</label>
                <input type="text" value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))}
                  placeholder={t('comp.tagMgmt.descriptionPlaceholder', 'Descrição opcional')} className="w-full border border-[var(--border-default)] rounded-lg px-3 py-2 text-xs bg-[var(--surface-card)] text-[var(--text-primary)]" />
              </div>
            </div>
            <div className="flex gap-2 justify-end mt-4">
              <button onClick={() => setShowCreate(false)}
                className="px-3 py-2 rounded-lg border border-[var(--border-default)] text-xs font-semibold cursor-pointer bg-transparent text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]">
                {t('comp.tagMgmt.cancel', 'Cancelar')}
              </button>
              <button onClick={handleCreate} disabled={saving}
                className="px-3 py-2 rounded-lg bg-navy text-white text-xs font-semibold hover:opacity-90 cursor-pointer border-0 disabled:opacity-50">
                {saving ? '...' : t('comp.tagMgmt.createBtn', 'Criar Tag')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
