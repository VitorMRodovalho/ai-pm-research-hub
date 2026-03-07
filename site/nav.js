/**
 * nav.js — Componente de nav compartilhado
 * Inclua DEPOIS do script do Supabase e da definição de `sb`
 * Uso: <script src="/nav.js"></script>
 */
(function() {

// ── CSS ──────────────────────────────────────────────────────
const CSS = `
.snav{position:sticky;top:0;z-index:200;background:rgba(0,59,92,.97);
  backdrop-filter:blur(12px);border-bottom:2px solid #FF610F;
  padding:0 1.5rem;display:flex;align-items:center;
  justify-content:space-between;height:56px;font-family:inherit}
.snav-brand{color:#fff;font-weight:700;font-size:.9rem;text-decoration:none}
.snav-brand b{color:#FF610F}
.snav-links{display:flex;gap:.15rem;align-items:center}
.snav-links a{color:rgba(255,255,255,.7);text-decoration:none;font-size:.73rem;
  font-weight:500;padding:.35rem .55rem;border-radius:6px;transition:.15s;white-space:nowrap}
.snav-links a:hover{color:#fff;background:rgba(255,255,255,.1)}
.snav-links a.snav-active{color:#fff;background:rgba(255,255,255,.1)}
.snav-presence{background:rgba(190,32,39,.2)!important;border:1px solid rgba(190,32,39,.4);
  color:#fff!important;font-weight:600!important}
.snav-admin{background:rgba(79,23,168,.2)!important;border:1px solid rgba(79,23,168,.4);
  color:#fff!important;font-weight:600!important}
.snav-auth{display:flex;align-items:center;gap:.4rem;flex-shrink:0}
.snav-login-btn{padding:.35rem .9rem;border-radius:8px;background:rgba(255,255,255,.12);
  border:1px solid rgba(255,255,255,.25);color:#fff;font-size:.78rem;font-weight:600;
  cursor:pointer;font-family:inherit;transition:.15s}
.snav-login-btn:hover{background:rgba(255,255,255,.2)}
.snav-user-btn{background:none;border:none;cursor:pointer;display:flex;align-items:center;
  gap:.4rem;padding:.2rem .4rem;border-radius:8px;transition:.15s}
.snav-user-btn:hover{background:rgba(255,255,255,.1)}
.snav-av{width:30px;height:30px;border-radius:50%;object-fit:cover;flex-shrink:0}
.snav-av-init{width:30px;height:30px;border-radius:50%;background:var(--pmi-teal,#00799E);
  display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700;font-size:.65rem;flex-shrink:0}
.snav-name{color:#fff;font-size:.8rem;font-weight:600}
.snav-rbadge{font-size:.6rem;font-weight:700;padding:.12rem .4rem;border-radius:5px;
  text-transform:uppercase;letter-spacing:.04em}
.snav-chevron{color:rgba(255,255,255,.4);font-size:.6rem}

/* Drawer */
.snav-overlay{display:none;position:fixed;inset:0;z-index:500}
.snav-overlay.open{display:block}
.snav-drawer{position:fixed;top:60px;right:1rem;z-index:501;background:#fff;
  border-radius:16px;box-shadow:0 8px 40px rgba(0,0,0,.2);padding:1.1rem;
  min-width:230px;border:1px solid #E2E8F0;
  transform:translateY(-8px) scale(.97);opacity:0;pointer-events:none;transition:.18s}
.snav-drawer.open{transform:none;opacity:1;pointer-events:all}
.snav-dav{width:46px;height:46px;border-radius:50%;object-fit:cover;flex-shrink:0}
.snav-dav-init{width:46px;height:46px;border-radius:50%;
  background:var(--pmi-teal,#00799E);display:flex;align-items:center;
  justify-content:center;color:#fff;font-weight:700;font-size:.8rem}
.snav-dname{font-weight:700;font-size:.88rem;color:#1a1a2e}
.snav-dbadge{font-size:.62rem;font-weight:700;padding:.12rem .45rem;
  border-radius:5px;display:inline-block;margin-top:.2rem}
.snav-demail{font-size:.67rem;color:#64748B;margin-top:.1rem;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:160px}
.snav-dhr{border:none;border-top:1px solid #F1F5F9;margin:.65rem 0}
.snav-ditem{display:flex;align-items:center;gap:.5rem;width:100%;
  padding:.38rem .5rem;border-radius:8px;font-size:.78rem;font-weight:600;
  text-decoration:none;color:#1a1a2e;border:none;background:none;
  cursor:pointer;text-align:left;transition:.12s;font-family:inherit}
.snav-ditem:hover{background:#F8FAFC}
.snav-ditem.admin-item{color:#4F17A8}.snav-ditem.admin-item:hover{background:#F5F3FF}
.snav-ditem.danger-item{color:#BE2027}.snav-ditem.danger-item:hover{background:#FFF1F1}
@media(max-width:900px){.snav-links{display:none}}
`;

const ROLE_LABELS = {
  manager:'Gerente', tribe_leader:'Líder de Tribo', researcher:'Pesquisador',
  ambassador:'Embaixador', curator:'Curador', sponsor:'Patrocinador',
  founder:'Fundador', facilitator:'Facilitador', communicator:'Multiplicador', guest:'Visitante'
};
const ROLE_COLORS = {
  manager:'#FF610F', tribe_leader:'#4F17A8', researcher:'#EC4899',
  ambassador:'#10B981', curator:'#D97706', sponsor:'#BE2027',
  founder:'#7C3AED', facilitator:'#EC4899', communicator:'#EC4899'
};

const NAV_LINKS = [
  {href:'/#agenda',     label:'Pauta'},
  {href:'/#quadrants',  label:'Quadrantes'},
  {href:'/#tribes',     label:'Tribos'},
  {href:'/#kpis',       label:'KPIs'},
  {href:'/#breakout',   label:'Networking'},
  {href:'/#rules',      label:'Regras'},
  {href:'/#trail',      label:'Trilha IA'},
  {href:'/#team',       label:'Time'},
  {href:'/#vision',     label:'Visão'},
  {href:'/#resources',  label:'Recursos'},
];

// Inject CSS
const style = document.createElement('style');
style.textContent = CSS;
document.head.appendChild(style);

// Build nav HTML
function buildNav(member, user) {
  const cur = location.pathname;
  const links = NAV_LINKS.map(l =>
    `<a href="${l.href}">${l.label}</a>`
  ).join('') +
  `<a href="/attendance" class="snav-presence ${cur==='/attendance'?'snav-active':''}">⏱ Presença</a>`;

  const isAdmin = member?.is_superadmin === true;
  const adminLink = isAdmin
    ? `<a href="/admin" class="snav-admin ${cur==='/admin'?'snav-active':''}">⚙️ Admin</a>` : '';

  let authHtml;
  if (member && member.role !== 'guest') {
    const name  = member.name || 'Usuário';
    const first = name.split(' ')[0];
    const initials = name.split(' ').map(w=>w[0]).join('').substring(0,2).toUpperCase();
    const pic   = user?.user_metadata?.avatar_url;
    const r     = member.role || 'guest';
    const color = ROLE_COLORS[r] || '#64748B';
    const rlabel = ROLE_LABELS[r] || r;
    const avEl  = pic
      ? `<img class="snav-av" src="${pic}" onerror="this.style.display='none'">`
      : `<div class="snav-av-init">${initials}</div>`;
    authHtml = `
      <button class="snav-user-btn" onclick="snavTogglePD()" id="snav-user-btn">
        ${avEl}
        <span class="snav-name">${first}</span>
        <span class="snav-rbadge" style="background:${color}22;color:${color}">${rlabel}</span>
        <span class="snav-chevron">▾</span>
      </button>`;
    buildDrawer(member, user, isAdmin);
  } else {
    authHtml = `<button class="snav-login-btn" onclick="snavOpenLogin()">Entrar</button>`;
  }

  const nav = document.createElement('nav');
  nav.className = 'snav';
  nav.id = 'shared-nav';
  nav.innerHTML = `
    <a href="/" class="snav-brand">Núcleo <b>IA & GP</b> — Ciclo 03</a>
    <div class="snav-links">${links}${adminLink}</div>
    <div class="snav-auth" id="snav-auth">${authHtml}</div>`;

  // Insert at top of body
  document.body.insertBefore(nav, document.body.firstChild);
}

function buildDrawer(member, user, isAdmin) {
  // Remove existing drawer
  document.getElementById('snav-overlay')?.remove();
  document.getElementById('snav-drawer')?.remove();

  const name = member?.name || 'Usuário';
  const initials = name.split(' ').map(w=>w[0]).join('').substring(0,2).toUpperCase();
  const pic  = user?.user_metadata?.avatar_url;
  const r    = member?.role || 'guest';
  const color = ROLE_COLORS[r] || '#64748B';
  const av   = pic
    ? `<img class="snav-dav" src="${pic}" onerror="this.style.display='none'">`
    : `<div class="snav-dav-init">${initials}</div>`;

  const overlay = document.createElement('div');
  overlay.className = 'snav-overlay'; overlay.id = 'snav-overlay';
  overlay.onclick = () => snavClosePD();

  const drawer = document.createElement('div');
  drawer.className = 'snav-drawer'; drawer.id = 'snav-drawer';
  drawer.innerHTML = `
    <div style="display:flex;align-items:center;gap:.65rem;margin-bottom:.3rem">
      ${av}
      <div style="min-width:0">
        <div class="snav-dname">${name}</div>
        <span class="snav-dbadge" style="background:${color}22;color:${color}">${ROLE_LABELS[r]||r}</span>
        <div class="snav-demail">${member?.email||''}</div>
      </div>
    </div>
    <hr class="snav-dhr">
    <a class="snav-ditem" href="/admin#profile">👤 Meu Perfil</a>
    <a class="snav-ditem" href="/attendance">⏱ Presenças & Horas</a>
    ${isAdmin ? '<hr class="snav-dhr"><a class="snav-ditem admin-item" href="/admin">⚙️ Painel Admin</a>' : ''}
    <hr class="snav-dhr">
    <button class="snav-ditem danger-item" onclick="snavLogout()">↩ Sair</button>`;

  document.body.appendChild(overlay);
  document.body.appendChild(drawer);
}

// Global functions (called from HTML onclick)
window.snavTogglePD = function() {
  const d = document.getElementById('snav-drawer');
  const o = document.getElementById('snav-overlay');
  if (!d) return;
  const on = !d.classList.contains('open');
  d.classList.toggle('open', on);
  o.classList.toggle('open', on);
};
window.snavClosePD = function() {
  document.getElementById('snav-drawer')?.classList.remove('open');
  document.getElementById('snav-overlay')?.classList.remove('open');
};
window.snavLogout = async function() {
  await window._snavSb?.auth.signOut();
  location.href = '/';
};
window.snavOpenLogin = function() {
  // Try page-specific openAuth, else redirect
  if (typeof window.openAuth === 'function') window.openAuth();
  else location.href = '/?login=1';
};

// ── INIT ─────────────────────────────────────────────────────
// Called by pages after Supabase is ready
window.snavInit = async function(sbInstance) {
  window._snavSb = sbInstance;

  // Remove any existing nav built by the page itself
  document.getElementById('shared-nav')?.remove();

  async function tryLoad(session) {
    if (!session) { buildNav(null, null); return; }
    try {
      const { data: member } = await sbInstance.rpc('get_member_by_auth');
      buildNav(member, session.user);
      // Notify page that member is ready
      window.dispatchEvent(new CustomEvent('snav:member', { detail: member }));
    } catch(e) {
      buildNav(null, null);
    }
  }

  const { data: { session } } = await sbInstance.auth.getSession();
  await tryLoad(session);

  sbInstance.auth.onAuthStateChange(async (event, session) => {
    if (event === 'SIGNED_IN')  { await tryLoad(session); }
    if (event === 'SIGNED_OUT') { buildNav(null, null); }
  });
};

})();
