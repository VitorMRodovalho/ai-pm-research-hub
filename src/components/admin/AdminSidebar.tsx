import { useState, useEffect, useCallback } from 'react';
import {
  LayoutDashboard, Users, UserPlus, Activity,
  PenSquare, BookOpen, CheckCircle, Megaphone,
  BarChart3, Briefcase, FileText, Building, FileBarChart, GitCompare,
  Mail, Leaf, Rocket, Settings, Shield, Handshake, HelpCircle,
  ChevronLeft, ChevronRight, X,
  MonitorPlay, ClipboardList,
  Library, SearchCheck, Tag,
} from 'lucide-react';
import { hasPermission as checkPermission } from '../../lib/permissions';

/* ────────────────────────── Icon map ────────────────────────── */
const ICONS: Record<string, React.FC<{ size?: number }>> = {
  LayoutDashboard, Users, UserPlus, Activity,
  PenSquare, BookOpen, CheckCircle, Megaphone,
  BarChart3, Briefcase, FileText, Building, FileBarChart, GitCompare,
  Mail, Leaf, Rocket, Settings, Shield, Handshake, HelpCircle,
  MonitorPlay, ClipboardList,
  Library, SearchCheck, Tag,
};

/* ────────────────────────── Sidebar data ────────────────────── */
interface SidebarItem {
  href: string;
  label: Record<string, string>;
  icon: string;
  permission?: string;
}

interface SidebarSection {
  id: string;
  emoji: string;
  label: Record<string, string>;
  items: SidebarItem[];
}

const SECTIONS: SidebarSection[] = [
  {
    id: 'overview', emoji: '📊',
    label: { 'pt-BR': 'Visão Geral', 'en-US': 'Overview', 'es-LATAM': 'Visión General' },
    items: [
      { href: '/admin', label: { 'pt-BR': 'Dashboard', 'en-US': 'Dashboard', 'es-LATAM': 'Dashboard' }, icon: 'LayoutDashboard', permission: 'admin.access' },
    ],
  },
  {
    id: 'people', emoji: '👥',
    label: { 'pt-BR': 'Pessoas', 'en-US': 'People', 'es-LATAM': 'Personas' },
    items: [
      { href: '/admin/members', label: { 'pt-BR': 'Membros', 'en-US': 'Members', 'es-LATAM': 'Miembros' }, icon: 'Users', permission: 'admin.access' },
      { href: '/admin/tribes', label: { 'pt-BR': 'Tribos', 'en-US': 'Tribes', 'es-LATAM': 'Tribus' }, icon: 'Users', permission: 'admin.access' },
      { href: '/admin/selection', label: { 'pt-BR': 'Processo Seletivo', 'en-US': 'Selection Process', 'es-LATAM': 'Proceso Selectivo' }, icon: 'UserPlus', permission: 'admin.members.manage' },
      { href: '/admin/adoption', label: { 'pt-BR': 'Adoção', 'en-US': 'Adoption', 'es-LATAM': 'Adopción' }, icon: 'Activity', permission: 'admin.analytics' },
    ],
  },
  {
    id: 'content', emoji: '📋',
    label: { 'pt-BR': 'Conteúdo', 'en-US': 'Content', 'es-LATAM': 'Contenido' },
    items: [
      { href: '/admin/blog', label: { 'pt-BR': 'Blog', 'en-US': 'Blog', 'es-LATAM': 'Blog' }, icon: 'PenSquare', permission: 'admin.blog' },
      { href: '/admin/publications', label: { 'pt-BR': 'Publicações', 'en-US': 'Publications', 'es-LATAM': 'Publicaciones' }, icon: 'BookOpen', permission: 'admin.publications' },
      { href: '/admin/curatorship', label: { 'pt-BR': 'Curadoria', 'en-US': 'Curatorship', 'es-LATAM': 'Curaduría' }, icon: 'CheckCircle', permission: 'admin.curation' },
      { href: '/admin/comms-ops', label: { 'pt-BR': 'Comunicação', 'en-US': 'Communications', 'es-LATAM': 'Comunicación' }, icon: 'Megaphone', permission: 'admin.campaigns' },
      { href: '/admin/webinars', label: { 'pt-BR': 'Webinars', 'en-US': 'Webinars', 'es-LATAM': 'Webinars' }, icon: 'MonitorPlay', permission: 'admin.access' },
      { href: '/admin/knowledge', label: { 'pt-BR': 'Biblioteca de Recursos', 'en-US': 'Resource Library', 'es-LATAM': 'Biblioteca de Recursos' }, icon: 'Library', permission: 'admin.access' },
    ],
  },
  {
    id: 'reports', emoji: '📈',
    label: { 'pt-BR': 'Relatórios', 'en-US': 'Reports', 'es-LATAM': 'Informes' },
    items: [
      { href: '/admin/analytics', label: { 'pt-BR': 'Analytics', 'en-US': 'Analytics', 'es-LATAM': 'Analytics' }, icon: 'BarChart3', permission: 'admin.analytics' },
      { href: '/admin/portfolio', label: { 'pt-BR': 'Portfólio Executivo', 'en-US': 'Executive Portfolio', 'es-LATAM': 'Portafolio Ejecutivo' }, icon: 'Briefcase', permission: 'admin.portfolio' },
      { href: '/admin/cycle-report', label: { 'pt-BR': 'Relatório do Ciclo', 'en-US': 'Cycle Report', 'es-LATAM': 'Informe del Ciclo' }, icon: 'FileText', permission: 'admin.analytics' },
      { href: '/admin/chapter-report', label: { 'pt-BR': 'Relatório por Capítulo', 'en-US': 'Chapter Report', 'es-LATAM': 'Informe por Capítulo' }, icon: 'Building', permission: 'admin.analytics.chapter' },
      { href: '/admin/report', label: { 'pt-BR': 'Relatório Executivo', 'en-US': 'Executive Report', 'es-LATAM': 'Informe Ejecutivo' }, icon: 'FileBarChart', permission: 'admin.analytics' },
      { href: '/admin/tribe-comparison', label: { 'pt-BR': 'Comparativo de Tribos', 'en-US': 'Tribe Comparison', 'es-LATAM': 'Comparativo de Tribus' }, icon: 'GitCompare', permission: 'admin.access' },
    ],
  },
  {
    id: 'operations', emoji: '⚙️',
    label: { 'pt-BR': 'Operações', 'en-US': 'Operations', 'es-LATAM': 'Operaciones' },
    items: [
      { href: '/admin/campaigns', label: { 'pt-BR': 'Campanhas', 'en-US': 'Campaigns', 'es-LATAM': 'Campañas' }, icon: 'Mail', permission: 'admin.campaigns' },
      { href: '/admin/sustainability', label: { 'pt-BR': 'Sustentabilidade', 'en-US': 'Sustainability', 'es-LATAM': 'Sostenibilidad' }, icon: 'Leaf', permission: 'admin.sustainability' },
      { href: '/admin/pilots', label: { 'pt-BR': 'Pilotos', 'en-US': 'Pilots', 'es-LATAM': 'Pilotos' }, icon: 'Rocket', permission: 'admin.portfolio' },
      { href: '/admin/settings', label: { 'pt-BR': 'Configurações', 'en-US': 'Settings', 'es-LATAM': 'Configuraciones' }, icon: 'Settings', permission: 'system.global_config' },
      { href: '/admin/audit-log', label: { 'pt-BR': 'Registro de Auditoria', 'en-US': 'Audit Log', 'es-LATAM': 'Registro de Auditoría' }, icon: 'ClipboardList', permission: 'system.global_config' },
      { href: '/admin/data-health', label: { 'pt-BR': 'Data Health', 'en-US': 'Data Health', 'es-LATAM': 'Data Health' }, icon: 'SearchCheck', permission: 'system.global_config' },
      { href: '/admin/tags', label: { 'pt-BR': 'Tags', 'en-US': 'Tags', 'es-LATAM': 'Tags' }, icon: 'Tag', permission: 'admin.access' },
      { href: '/admin/governance-v2', label: { 'pt-BR': 'Governança', 'en-US': 'Governance', 'es-LATAM': 'Gobernanza' }, icon: 'Shield', permission: 'admin.access' },
      { href: '/admin/partnerships', label: { 'pt-BR': 'Parcerias', 'en-US': 'Partnerships', 'es-LATAM': 'Alianzas' }, icon: 'Handshake', permission: 'admin.access' },
      { href: '/help', label: { 'pt-BR': 'Ajuda / Guia', 'en-US': 'Help / Guide', 'es-LATAM': 'Ayuda / Guía' }, icon: 'HelpCircle', permission: 'workspace.access' },
    ],
  },
];

/* ────────────────────────── Props ────────────────────────────── */
interface Props {
  currentPath: string;
  locale: string;
}

const SIDEBAR_KEY = 'hub_admin_sidebar_collapsed';

/* ────────────────────────── Component ───────────────────────── */
export default function AdminSidebar({ currentPath, locale }: Props) {
  const [collapsed, setCollapsed] = useState(() => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem(SIDEBAR_KEY) === 'true';
    }
    return false;
  });
  const [mobileOpen, setMobileOpen] = useState(false);
  const [visiblePerms, setVisiblePerms] = useState<Set<string>>(new Set());

  // Persist collapsed state
  useEffect(() => {
    localStorage.setItem(SIDEBAR_KEY, String(collapsed));
  }, [collapsed]);

  // Listen for member data to resolve permissions
  useEffect(() => {
    function resolvePerms() {
      const member = (window as any).navGetMember?.();
      if (!member) return;
      const perms = new Set<string>();
      SECTIONS.forEach(s => s.items.forEach(item => {
        if (!item.permission || checkPermission(member, item.permission as any)) {
          perms.add(item.permission || '');
        }
      }));
      setVisiblePerms(perms);
    }

    // Try immediately
    resolvePerms();

    // Re-check when member loads
    const onMember = () => setTimeout(resolvePerms, 50);
    window.addEventListener('nav:member', onMember);
    window.addEventListener('simulation:changed', onMember);
    // Fallback
    const t = setTimeout(resolvePerms, 800);
    return () => {
      window.removeEventListener('nav:member', onMember);
      window.removeEventListener('simulation:changed', onMember);
      clearTimeout(t);
    };
  }, []);

  // Mobile toggle from external hamburger
  useEffect(() => {
    const handler = () => setMobileOpen(true);
    window.addEventListener('admin:sidebar:toggle', handler);
    return () => window.removeEventListener('admin:sidebar:toggle', handler);
  }, []);

  // Close on Escape
  useEffect(() => {
    if (!mobileOpen) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setMobileOpen(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [mobileOpen]);

  const isActive = useCallback((href: string) => {
    if (href === '/admin') return currentPath === '/admin' || currentPath === '/admin/';
    return currentPath.startsWith(href);
  }, [currentPath]);

  const loc = locale || 'pt-BR';

  const renderNav = (isMobile: boolean) => (
    <nav className="flex flex-col h-full">
      {/* Header */}
      <div className={`flex items-center ${collapsed && !isMobile ? 'justify-center' : 'justify-between'} px-4 py-3 border-b border-[var(--border-default)]`}>
        {(!collapsed || isMobile) && (
          <span className="text-sm font-bold text-[var(--text-primary)] truncate">Admin</span>
        )}
        {isMobile ? (
          <button onClick={() => setMobileOpen(false)} className="p-1 rounded hover:bg-[var(--surface-hover)] text-[var(--text-muted)] bg-transparent border-0 cursor-pointer">
            <X size={18} />
          </button>
        ) : (
          <button
            onClick={() => setCollapsed(c => !c)}
            className="p-1 rounded hover:bg-[var(--surface-hover)] text-[var(--text-muted)] bg-transparent border-0 cursor-pointer"
            title={collapsed ? 'Expandir menu' : 'Recolher menu'}
          >
            {collapsed ? <ChevronRight size={16} /> : <ChevronLeft size={16} />}
          </button>
        )}
      </div>

      {/* Sections */}
      <div className="flex-1 overflow-y-auto py-2">
        {SECTIONS.map(section => {
          const visibleItems = section.items.filter(item =>
            !item.permission || visiblePerms.has(item.permission)
          );
          if (visibleItems.length === 0) return null;

          return (
            <div key={section.id} className="mb-1">
              {(!collapsed || isMobile) && (
                <div className="text-[.65rem] font-bold uppercase tracking-wider text-[var(--text-muted)] px-4 pt-3 pb-1 flex items-center gap-1.5">
                  <span>{section.emoji}</span>
                  <span>{section.label[loc] || section.label['pt-BR']}</span>
                </div>
              )}
              {collapsed && !isMobile && (
                <div className="flex justify-center py-1.5 text-xs">{section.emoji}</div>
              )}
              {visibleItems.map(item => {
                const Icon = ICONS[item.icon];
                const active = isActive(item.href);
                const label = item.label[loc] || item.label['pt-BR'];
                return (
                  <a
                    key={item.href}
                    href={item.href}
                    onClick={() => isMobile && setMobileOpen(false)}
                    title={collapsed && !isMobile ? label : undefined}
                    className={`flex items-center gap-2.5 mx-2 px-2.5 py-[7px] rounded-lg text-[13px] no-underline transition-colors ${
                      active
                        ? 'bg-teal-600/15 text-teal-500 font-semibold'
                        : 'text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)]'
                    } ${collapsed && !isMobile ? 'justify-center' : ''}`}
                  >
                    {Icon && <Icon size={16} />}
                    {(!collapsed || isMobile) && <span className="truncate">{label}</span>}
                  </a>
                );
              })}
            </div>
          );
        })}
      </div>
    </nav>
  );

  return (
    <>
      {/* Desktop sidebar */}
      <aside
        className={`hidden lg:flex flex-col flex-shrink-0 border-r border-[var(--border-default)] bg-[var(--surface-card)] transition-[width] duration-200 overflow-hidden ${
          collapsed ? 'w-16' : 'w-60'
        }`}
        style={{ minHeight: 'calc(100vh - 64px)' }}
      >
        {renderNav(false)}
      </aside>

      {/* Mobile drawer backdrop */}
      {mobileOpen && (
        <div
          className="lg:hidden fixed inset-0 bg-black/40 z-[90]"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Mobile drawer */}
      <aside
        className={`lg:hidden fixed top-0 left-0 h-full w-64 bg-[var(--surface-card)] border-r border-[var(--border-default)] z-[91] transition-transform duration-200 ${
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        {renderNav(true)}
      </aside>
    </>
  );
}
