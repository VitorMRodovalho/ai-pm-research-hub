import { useState, useEffect, useCallback } from 'react';
import {
  LayoutDashboard, Users, UserPlus, Activity,
  PenSquare, BookOpen, CheckCircle, Megaphone,
  BarChart3, Briefcase, FileText, Building, FileBarChart, GitCompare,
  Mail, Leaf, Rocket, Settings, Shield, Handshake, HelpCircle,
  ChevronLeft, ChevronRight, X,
  MonitorPlay, ClipboardList,
  Library, SearchCheck, Tag, FileCheck, Trophy, HardDrive, Shapes, SlidersHorizontal, CalendarDays, ArrowLeftRight, HeartPulse, CalendarClock,
} from 'lucide-react';
import { ADMIN_SIDEBAR_SECTIONS as SECTIONS, isAdminSidebarItemVisible } from '../../lib/navigation.config';

/* ────────────────────────── Icon map ────────────────────────── */
const ICONS: Record<string, React.FC<{ size?: number }>> = {
  LayoutDashboard, Users, UserPlus, Activity,
  PenSquare, BookOpen, CheckCircle, Megaphone,
  BarChart3, Briefcase, FileText, Building, FileBarChart, GitCompare,
  Mail, Leaf, Rocket, Settings, Shield, Handshake, HelpCircle,
  MonitorPlay, ClipboardList,
  Library, SearchCheck, Tag, FileCheck, Trophy, HardDrive, Shapes, SlidersHorizontal, CalendarDays, ArrowLeftRight, HeartPulse, CalendarClock,
};

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
  const [visibleHrefs, setVisibleHrefs] = useState<Set<string>>(new Set());

  // Persist collapsed state
  useEffect(() => {
    localStorage.setItem(SIDEBAR_KEY, String(collapsed));
  }, [collapsed]);

  // Listen for member data to resolve permissions
  useEffect(() => {
    function resolvePerms() {
      const member = (window as any).navGetMember?.();
      if (!member) return;
      const hrefs = new Set<string>();
      SECTIONS.forEach(s => s.items.forEach(item => {
        if (isAdminSidebarItemVisible(member, item)) hrefs.add(item.href);
      }));
      setVisibleHrefs(hrefs);
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
            isAdminSidebarItemVisible(null, item) || visibleHrefs.has(item.href));
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
                    href={loc !== 'pt-BR' ? `${item.href}${item.href.includes('?') ? '&' : '?'}lang=${loc}` : item.href}
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
