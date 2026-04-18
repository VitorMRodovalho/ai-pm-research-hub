import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface HubResource {
  id: string;
  asset_type: string;
  title: string;
  description: string | null;
  url: string | null;
  initiative_id: string | null;
  is_active: boolean;
  created_at: string;
}

const TYPE_ICONS: Record<string, string> = { course: '📖', reference: '📎', webinar: '🎥', other: '📁' };
const TYPE_OPTIONS_PT = [
  { value: 'course', label: 'Curso' },
  { value: 'reference', label: 'Referência' },
  { value: 'webinar', label: 'Webinar' },
  { value: 'other', label: 'Outro' },
];

export default function KnowledgeIsland() {
  const t = usePageI18n();
  const [items, setItems] = useState<HubResource[]>([]);
  const [loading, setLoading] = useState(true);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState({ title: '', description: '', url: '', asset_type: 'course', tribe_id: '' });
  const [saving, setSaving] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const getMember = useCallback(() => (window as any).navGetMember?.(), []);
  const toast = useCallback((msg: string, type = '') => (window as any).toast?.(msg, type), []);

  const fetchItems = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const { data, error } = await sb.from('hub_resources')
      .select('id, asset_type, title, description, url, initiative_id, is_active, created_at')
      .order('created_at', { ascending: false })
      .limit(50);
    if (!error && data) setItems(data);
    setLoading(false);
  }, [getSb]);

  useEffect(() => {
    const boot = () => { if (getSb()) fetchItems(); else setTimeout(boot, 300); };
    boot();
    window.addEventListener('nav:member', () => fetchItems());
  }, [getSb, fetchItems]);

  const resetForm = () => {
    setForm({ title: '', description: '', url: '', asset_type: 'course', tribe_id: '' });
    setEditId(null);
  };

  const handleSave = async () => {
    const sb = getSb();
    if (!sb || !form.title.trim()) { toast(t('comp.knowledge.fillTitle', 'Preencha o título'), 'error'); return; }
    setSaving(true);
    const tribeInt = form.tribe_id ? parseInt(form.tribe_id, 10) : null;
    let initiativeId: string | null = null;
    if (tribeInt !== null) {
      const { data: init } = await sb.from('initiatives')
        .select('id').eq('legacy_tribe_id', tribeInt).limit(1).maybeSingle();
      initiativeId = init?.id || null;
    }
    const payload = {
      asset_type: form.asset_type,
      title: form.title.trim(),
      description: form.description.trim() || null,
      url: form.url.trim() || null,
      initiative_id: initiativeId,
      author_id: getMember()?.id || null,
    };
    if (editId) {
      const { error } = await sb.from('hub_resources').update(payload).eq('id', editId);
      if (error) { toast(t('comp.knowledge.error', 'Erro: ') + error.message, 'error'); setSaving(false); return; }
      toast(t('comp.knowledge.resourceUpdated', 'Recurso atualizado'), 'success');
    } else {
      const { error } = await sb.from('hub_resources').insert(payload);
      if (error) { toast(t('comp.knowledge.error', 'Erro: ') + error.message, 'error'); setSaving(false); return; }
      toast(t('comp.knowledge.resourceCreated', 'Recurso criado'), 'success');
    }
    resetForm();
    setSaving(false);
    fetchItems();
  };

  const handleEdit = async (id: string) => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.from('hub_resources').select('id, title, description, url, asset_type, initiative_id').eq('id', id).single();
    if (!data) return;
    let tribeIdStr = '';
    if (data.initiative_id) {
      const { data: init } = await sb.from('initiatives')
        .select('legacy_tribe_id').eq('id', data.initiative_id).limit(1).maybeSingle();
      if (init?.legacy_tribe_id) tribeIdStr = String(init.legacy_tribe_id);
    }
    setForm({
      title: data.title || '',
      description: data.description || '',
      url: data.url || '',
      asset_type: data.asset_type || 'course',
      tribe_id: tribeIdStr,
    });
    setEditId(id);
  };

  const handleToggle = async (id: string, active: boolean) => {
    const sb = getSb();
    if (!sb) return;
    const { error } = await sb.from('hub_resources').update({ is_active: active }).eq('id', id);
    if (error) { toast(t('comp.knowledge.error', 'Erro: ') + error.message, 'error'); return; }
    toast(active ? t('comp.knowledge.resourceActivated', 'Recurso ativado') : t('comp.knowledge.resourceDeactivated', 'Recurso desativado'), 'success');
    fetchItems();
  };

  if (loading && items.length === 0) {
    return <div className="text-center py-8 text-[var(--text-muted)] text-sm animate-pulse">{t('comp.knowledge.loading', 'Carregando recursos...')}</div>;
  }

  return (
    <div className="space-y-6">
      {/* Form */}
      <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-5">
        <h3 className="text-sm font-bold text-navy mb-3">📚 {editId ? t('comp.knowledge.editResource', 'Editar Recurso') : t('comp.knowledge.newResource', 'Novo Recurso')}</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className="text-[.68rem] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.knowledge.titleLabel', 'Título *')}</label>
            <input type="text" value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
              placeholder={t('comp.knowledge.titlePlaceholder', 'Nome do recurso')} className="w-full px-3 py-2 border border-[var(--border-default)] rounded-lg text-[.78rem] bg-[var(--surface-card)] text-[var(--text-primary)]" />
          </div>
          <div>
            <label className="text-[.68rem] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.knowledge.type', 'Tipo')}</label>
            <select value={form.asset_type} onChange={e => setForm(f => ({ ...f, asset_type: e.target.value }))}
              className="w-full px-3 py-2 border border-[var(--border-default)] rounded-lg text-[.78rem] bg-[var(--surface-card)] text-[var(--text-primary)]">
              {TYPE_OPTIONS_PT.map(o => <option key={o.value} value={o.value}>{t(`comp.knowledge.type_${o.value}`, o.label)}</option>)}
            </select>
          </div>
          <div className="sm:col-span-2">
            <label className="text-[.68rem] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.knowledge.description', 'Descrição')}</label>
            <input type="text" value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))}
              placeholder={t('comp.knowledge.descriptionPlaceholder', 'Descrição breve')} className="w-full px-3 py-2 border border-[var(--border-default)] rounded-lg text-[.78rem] bg-[var(--surface-card)] text-[var(--text-primary)]" />
          </div>
          <div>
            <label className="text-[.68rem] font-semibold text-[var(--text-secondary)] block mb-1">URL</label>
            <input type="url" value={form.url} onChange={e => setForm(f => ({ ...f, url: e.target.value }))}
              placeholder="https://..." className="w-full px-3 py-2 border border-[var(--border-default)] rounded-lg text-[.78rem] bg-[var(--surface-card)] text-[var(--text-primary)]" />
          </div>
          <div>
            <label className="text-[.68rem] font-semibold text-[var(--text-secondary)] block mb-1">{t('comp.knowledge.tribe', 'Tribo')}</label>
            <select value={form.tribe_id} onChange={e => setForm(f => ({ ...f, tribe_id: e.target.value }))}
              className="w-full px-3 py-2 border border-[var(--border-default)] rounded-lg text-[.78rem] bg-[var(--surface-card)] text-[var(--text-primary)]">
              <option value="">{t('comp.knowledge.allTribes', 'Todas')}</option>
              {[1,2,3,4,5,6,7,8].map(n => <option key={n} value={String(n)}>{t('comp.knowledge.tribeN', 'Tribo')} {n}</option>)}
            </select>
          </div>
        </div>
        <div className="flex gap-2 mt-4">
          <button onClick={handleSave} disabled={saving}
            className="px-4 py-2 rounded-lg bg-navy text-white text-xs font-semibold hover:opacity-90 cursor-pointer border-0 disabled:opacity-50">
            {saving ? '...' : editId ? t('comp.knowledge.save', 'Salvar') : t('comp.knowledge.add', '+ Adicionar')}
          </button>
          {editId && (
            <button onClick={resetForm}
              className="px-4 py-2 rounded-lg border border-[var(--border-default)] text-xs font-semibold text-[var(--text-secondary)] cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]">
              {t('comp.knowledge.cancel', 'Cancelar')}
            </button>
          )}
        </div>
      </div>

      {/* List */}
      <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] overflow-hidden">
        <div className="px-5 py-3 border-b border-[var(--border-default)]">
          <span className="text-sm font-bold text-navy">{t('comp.knowledge.resources', 'Recursos')} ({items.length})</span>
        </div>
        <div className="divide-y divide-[var(--border-subtle)]">
          {items.length === 0 && (
            <p className="text-center py-6 text-[var(--text-muted)] text-xs">{t('comp.knowledge.noResources', 'Nenhum recurso cadastrado.')}</p>
          )}
          {items.map(a => (
            <div key={a.id} className="flex items-center gap-2 px-5 py-2.5">
              <span className="flex-shrink-0">{TYPE_ICONS[a.asset_type] || '📁'}</span>
              <div className="flex-1 min-w-0">
                <div className="text-[.78rem] font-semibold truncate text-[var(--text-primary)]">{a.title}</div>
                {a.description && <div className="text-[.65rem] text-[var(--text-muted)] truncate">{a.description}</div>}
              </div>
              <span className={`text-[.58rem] font-bold px-1.5 py-0.5 rounded-full ${a.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-[var(--surface-section-cool)] text-[var(--text-muted)]'}`}>
                {a.is_active ? t('comp.knowledge.active', 'Ativo') : t('comp.knowledge.inactive', 'Inativo')}
              </span>
              <span className="text-[.6rem] text-[var(--text-muted)] flex-shrink-0">
                {new Date(a.created_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })}
              </span>
              <button onClick={() => handleEdit(a.id)}
                className="text-[.6rem] px-2 py-0.5 rounded bg-[var(--surface-base)] text-[var(--text-secondary)] hover:bg-navy hover:text-white border-0 cursor-pointer transition-all">
                ✏️
              </button>
              <button onClick={() => handleToggle(a.id, !a.is_active)}
                className={`text-[.6rem] px-2 py-0.5 rounded border-0 cursor-pointer transition-all ${a.is_active ? 'bg-red-50 text-red-600 hover:bg-red-100' : 'bg-emerald-50 text-emerald-700 hover:bg-emerald-100'}`}>
                {a.is_active ? t('comp.knowledge.deactivate', 'Desativar') : t('comp.knowledge.activate', 'Ativar')}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
