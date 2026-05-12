/* ── GIFT Dashboard — style.css ──────────────────────────── */

/* ── CSS Variables ──────────────────────────────────────── */
:root {
  --bg:          #080808;
  --bg2:         #0f0f0f;
  --bg3:         #141414;
  --card:        #111111;
  --card-border: #1e1e1e;
  --accent:      #e8e8e8;
  --accent-dim:  #1a1a1a;
  --text-p:      #e8e8e8;
  --text-s:      #6a6a6a;
  --text-m:      #3a3a3a;
  --present:     #3ddc84;
  --absent:      #ff4444;
  --warn:        #ffb74d;
  --danger:      #ff4444;
  --info:        #4fc3f7;
  --mono:        'Share Tech Mono', monospace;
  --display:     'Syne', sans-serif;
  --sidebar-w:   240px;
  --topbar-h:    52px;
  --radius:      8px;
  --transition:  0.2s ease;
}

/* ── Reset ──────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
html { font-size: 14px; }
body {
  background: var(--bg);
  color: var(--text-p);
  font-family: var(--display);
  min-height: 100vh;
  overflow-x: hidden;
}
a { color: inherit; text-decoration: none; }
button { cursor: pointer; border: none; background: none; font-family: inherit; }
input, select, textarea {
  font-family: var(--mono);
  font-size: 13px;
  background: var(--bg2);
  border: 1px solid var(--card-border);
  color: var(--text-p);
  border-radius: var(--radius);
  padding: 9px 12px;
  outline: none;
  width: 100%;
  transition: border-color var(--transition);
}
input:focus, select:focus, textarea:focus { border-color: #3a3a3a; }
select option { background: var(--bg2); }

/* ── Utility ─────────────────────────────────────────────── */
.hidden { display: none !important; }

/* ── Auth Overlay ────────────────────────────────────────── */
.auth-overlay {
  position: fixed;
  inset: 0;
  background: var(--bg);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  animation: fadeIn 0.3s ease;
}
.auth-box {
  background: var(--card);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 40px 36px;
  width: 100%;
  max-width: 400px;
  animation: slideUp 0.35s ease;
}
.auth-logo {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 28px;
  justify-content: center;
}
.auth-logo-img { width: 32px; height: 32px; }
.auth-logo-text {
  font-family: var(--display);
  font-size: 22px;
  font-weight: 800;
  letter-spacing: 4px;
  color: var(--text-p);
}
.auth-box h2 {
  font-family: var(--display);
  font-size: 18px;
  font-weight: 700;
  margin-bottom: 6px;
  color: var(--text-p);
}
.auth-sub {
  font-size: 12px;
  color: var(--text-s);
  margin-bottom: 24px;
  font-family: var(--mono);
}
.field { margin-bottom: 14px; }
.field label {
  display: block;
  font-size: 11px;
  color: var(--text-s);
  margin-bottom: 5px;
  font-weight: 600;
  letter-spacing: 0.5px;
  text-transform: uppercase;
  font-family: var(--mono);
}
.pw-wrap { position: relative; }
.pw-wrap input { padding-right: 40px; }
.pw-toggle {
  position: absolute;
  right: 10px;
  top: 50%;
  transform: translateY(-50%);
  font-size: 14px;
  color: var(--text-s);
  background: none;
  border: none;
  cursor: pointer;
}
.btn-primary {
  width: 100%;
  padding: 11px;
  background: var(--text-p);
  color: var(--bg);
  border-radius: var(--radius);
  font-family: var(--display);
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 1px;
  margin-top: 8px;
  transition: opacity var(--transition);
}
.btn-primary:hover { opacity: 0.88; }
.btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }
.auth-switch {
  font-size: 12px;
  color: var(--text-s);
  text-align: center;
  margin-top: 14px;
  font-family: var(--mono);
}
.auth-switch a { color: var(--text-p); text-decoration: underline; }
.auth-error {
  background: rgba(255,68,68,0.08);
  border: 1px solid rgba(255,68,68,0.2);
  border-radius: var(--radius);
  padding: 8px 12px;
  font-size: 12px;
  color: var(--absent);
  margin-bottom: 8px;
  font-family: var(--mono);
}

/* ── App Shell ───────────────────────────────────────────── */
.app {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
}

/* ── Top Bar ─────────────────────────────────────────────── */
.topbar {
  position: fixed;
  top: 0; left: 0; right: 0;
  height: var(--topbar-h);
  background: var(--bg);
  border-bottom: 1px solid var(--card-border);
  display: flex;
  align-items: center;
  padding: 0 16px;
  z-index: 100;
  gap: 12px;
}
.menu-btn {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 6px;
  border-radius: 6px;
  transition: background var(--transition);
  flex-shrink: 0;
}
.menu-btn:hover { background: var(--accent-dim); }
.menu-btn span {
  display: block;
  width: 18px;
  height: 1.5px;
  background: var(--text-p);
  border-radius: 2px;
}
.topbar-title {
  font-family: var(--display);
  font-size: 15px;
  font-weight: 800;
  letter-spacing: 3px;
  text-transform: uppercase;
  flex: 1;
  text-align: center;
}
.topbar-right {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}
.topbar-user {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--text-s);
}
.status-dot {
  width: 7px; height: 7px;
  border-radius: 50%;
  background: var(--present);
  box-shadow: 0 0 6px var(--present);
  animation: pulse 2s infinite;
}
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

/* ── Sidebar ─────────────────────────────────────────────── */
.sidebar {
  position: fixed;
  top: 0; left: 0; bottom: 0;
  width: var(--sidebar-w);
  background: var(--bg2);
  border-right: 1px solid var(--card-border);
  z-index: 200;
  display: flex;
  flex-direction: column;
  transform: translateX(-100%);
  transition: transform 0.25s ease;
}
.sidebar.open { transform: translateX(0); }
.sidebar-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 16px;
  border-bottom: 1px solid var(--card-border);
  height: var(--topbar-h);
}
.sidebar-logo { width: 22px; height: 22px; }
.sidebar-brand {
  font-family: var(--display);
  font-size: 14px;
  font-weight: 800;
  letter-spacing: 3px;
  flex: 1;
}
.sidebar-close {
  color: var(--text-s);
  font-size: 14px;
  padding: 4px;
  border-radius: 4px;
}
.sidebar-close:hover { color: var(--text-p); background: var(--accent-dim); }
.sidebar-nav {
  flex: 1;
  padding: 10px 8px;
  overflow-y: auto;
}
.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border-radius: var(--radius);
  color: var(--text-s);
  font-size: 13px;
  font-weight: 600;
  transition: background var(--transition), color var(--transition);
  margin-bottom: 2px;
}
.nav-item:hover { background: var(--accent-dim); color: var(--text-p); }
.nav-item.active { background: var(--accent-dim); color: var(--text-p); }
.nav-icon { font-size: 12px; width: 18px; text-align: center; }
.sidebar-footer {
  padding: 12px;
  border-top: 1px solid var(--card-border);
}
.btn-signout {
  width: 100%;
  padding: 9px;
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
  color: var(--text-s);
  font-family: var(--mono);
  font-size: 12px;
  transition: all var(--transition);
}
.btn-signout:hover { border-color: var(--absent); color: var(--absent); }

/* Sidebar overlay backdrop */
.sidebar-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.5);
  z-index: 150;
  display: none;
}
.sidebar-backdrop.visible { display: block; }

/* ── Page Container ──────────────────────────────────────── */
.page-container {
  margin-top: var(--topbar-h);
  padding: 24px;
  min-height: calc(100vh - var(--topbar-h));
}

/* ── Page Sections ───────────────────────────────────────── */
.page { animation: fadeIn 0.2s ease; }
.page-header {
  margin-bottom: 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 10px;
}
.page-title {
  font-family: var(--display);
  font-size: 20px;
  font-weight: 800;
  letter-spacing: 1px;
}
.page-sub {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--text-s);
  margin-top: 3px;
}

/* ── Cards ───────────────────────────────────────────────── */
.card {
  background: var(--card);
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
  padding: 18px;
}
.card-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 1.5px;
  text-transform: uppercase;
  color: var(--text-s);
  margin-bottom: 12px;
  font-family: var(--mono);
}

/* ── Stat Grid ───────────────────────────────────────────── */
.stat-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 12px;
  margin-bottom: 24px;
}
.stat-card {
  background: var(--card);
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
  padding: 16px;
}
.stat-value {
  font-family: var(--mono);
  font-size: 28px;
  font-weight: 400;
  color: var(--text-p);
  line-height: 1;
}
.stat-label {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--text-s);
  margin-top: 6px;
  text-transform: uppercase;
  letter-spacing: 0.8px;
}

/* ── Audit Boxes ─────────────────────────────────────────── */
.audit-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
  gap: 16px;
}
.audit-box {
  background: var(--bg2);
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
  display: flex;
  flex-direction: column;
  height: 340px;
}
.audit-box-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 14px;
  border-bottom: 1px solid var(--card-border);
  flex-shrink: 0;
  gap: 8px;
}
.audit-box-name {
  font-family: var(--mono);
  font-size: 12px;
  font-weight: 400;
  color: var(--text-p);
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.audit-box-meta {
  font-size: 10px;
  color: var(--text-s);
  font-family: var(--mono);
  white-space: nowrap;
}
.audit-dot {
  width: 6px; height: 6px;
  border-radius: 50%;
  background: var(--present);
  flex-shrink: 0;
}
.audit-dot.offline { background: var(--text-m); box-shadow: none; animation: none; }
.audit-raw-toggle {
  font-size: 10px;
  font-family: var(--mono);
  color: var(--text-s);
  border: 1px solid var(--card-border);
  border-radius: 4px;
  padding: 2px 7px;
  transition: all var(--transition);
}
.audit-raw-toggle:hover { color: var(--text-p); border-color: #3a3a3a; }
.audit-raw-toggle.active { color: var(--warn); border-color: rgba(255,183,77,0.3); }
.audit-log {
  flex: 1;
  overflow-y: auto;
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-family: var(--mono);
  font-size: 10.5px;
  scroll-behavior: smooth;
}
.log-line { line-height: 1.5; word-break: break-all; }
.log-line.err { color: var(--absent); }
.log-line.ok  { color: var(--present); }
.log-line.warn{ color: var(--warn); }
.log-line.info{ color: var(--info); }
.log-line.dim { color: var(--text-m); }
.log-line.normal { color: var(--text-s); }
.audit-empty {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--mono);
  font-size: 11px;
  color: var(--text-m);
}
.audit-filter-bar {
  display: flex;
  gap: 8px;
  margin-bottom: 16px;
  flex-wrap: wrap;
  align-items: center;
}
.audit-filter-bar input {
  width: 200px;
  font-size: 12px;
  padding: 7px 10px;
}
.audit-loading {
  text-align: center;
  padding: 60px;
  font-family: var(--mono);
  font-size: 12px;
  color: var(--text-s);
}

/* ── Attendance Table ────────────────────────────────────── */
.att-controls {
  display: flex;
  gap: 10px;
  margin-bottom: 18px;
  flex-wrap: wrap;
  align-items: center;
}
.att-controls select { width: auto; min-width: 180px; }
.att-controls input  { width: 200px; }
.att-table-wrap {
  overflow-x: auto;
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
}
table {
  width: 100%;
  border-collapse: collapse;
  font-family: var(--mono);
  font-size: 12px;
}
thead { background: var(--bg2); }
th {
  padding: 10px 14px;
  text-align: left;
  color: var(--text-s);
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.8px;
  border-bottom: 1px solid var(--card-border);
  font-weight: 400;
}
td {
  padding: 9px 14px;
  border-bottom: 1px solid #111;
  color: var(--text-p);
  font-size: 12px;
}
tr:last-child td { border-bottom: none; }
tr:hover td { background: rgba(255,255,255,0.02); }
.badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 20px;
  font-size: 10px;
  font-weight: 400;
  font-family: var(--mono);
}
.badge.present { background: rgba(61,220,132,0.1); color: var(--present); border: 1px solid rgba(61,220,132,0.2); }
.badge.absent  { background: rgba(255,68,68,0.1);  color: var(--absent);  border: 1px solid rgba(255,68,68,0.2); }

/* ── Teacher Roster ──────────────────────────────────────── */
.roster-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 12px;
}
.roster-card {
  background: var(--card);
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
  padding: 16px;
  display: flex;
  align-items: center;
  gap: 14px;
}
.roster-avatar {
  width: 40px; height: 40px;
  border-radius: 50%;
  background: var(--accent-dim);
  border: 1px solid var(--card-border);
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--display);
  font-size: 16px;
  font-weight: 800;
  color: var(--text-p);
  flex-shrink: 0;
}
.roster-info { flex: 1; min-width: 0; }
.roster-name {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-p);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.roster-meta {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--text-s);
  margin-top: 3px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.roster-role {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--text-m);
  border: 1px solid var(--card-border);
  border-radius: 4px;
  padding: 2px 7px;
  white-space: nowrap;
}

/* ── Kill Switch ─────────────────────────────────────────── */
.kill-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 14px;
}
.kill-card {
  background: var(--card);
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
  padding: 18px;
}
.kill-card.danger { border-color: rgba(255,68,68,0.25); }
.kill-label {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--text-s);
  text-transform: uppercase;
  letter-spacing: 0.8px;
  margin-bottom: 14px;
}
.toggle-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.toggle-desc { font-size: 13px; color: var(--text-p); font-weight: 600; }
.toggle-sub  { font-family: var(--mono); font-size: 10px; color: var(--text-s); margin-top: 2px; }
.toggle-switch {
  position: relative;
  width: 44px; height: 24px;
  flex-shrink: 0;
}
.toggle-switch input { opacity: 0; width: 0; height: 0; }
.toggle-track {
  position: absolute;
  inset: 0;
  background: var(--bg2);
  border: 1px solid var(--card-border);
  border-radius: 24px;
  cursor: pointer;
  transition: background var(--transition);
}
.toggle-track::after {
  content: '';
  position: absolute;
  left: 3px; top: 3px;
  width: 16px; height: 16px;
  border-radius: 50%;
  background: var(--text-m);
  transition: transform var(--transition), background var(--transition);
}
.toggle-switch input:checked + .toggle-track { background: rgba(61,220,132,0.15); border-color: rgba(61,220,132,0.3); }
.toggle-switch input:checked + .toggle-track::after { transform: translateX(20px); background: var(--present); }
.kill-input-row {
  margin-top: 14px;
  display: flex;
  gap: 8px;
}
.kill-input-row input { flex: 1; }
.btn-sm {
  padding: 8px 14px;
  background: var(--accent-dim);
  border: 1px solid var(--card-border);
  border-radius: var(--radius);
  color: var(--text-p);
  font-family: var(--mono);
  font-size: 11px;
  white-space: nowrap;
  transition: all var(--transition);
  flex-shrink: 0;
}
.btn-sm:hover { border-color: #3a3a3a; }
.btn-sm.danger:hover { border-color: rgba(255,68,68,0.4); color: var(--absent); }
.kill-list {
  margin-top: 12px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-height: 160px;
  overflow-y: auto;
}
.kill-tag {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: var(--bg2);
  border: 1px solid var(--card-border);
  border-radius: 4px;
  padding: 6px 10px;
  font-family: var(--mono);
  font-size: 11px;
}
.kill-tag span { color: var(--text-s); }
.kill-tag button { color: var(--absent); font-size: 13px; }
.kill-msg-box textarea {
  height: 70px;
  resize: none;
  font-size: 12px;
  margin-top: 10px;
}

/* ── Profile ─────────────────────────────────────────────── */
.profile-form { max-width: 480px; }
.profile-row { margin-bottom: 16px; }
.profile-row label {
  display: block;
  font-family: var(--mono);
  font-size: 10px;
  color: var(--text-s);
  text-transform: uppercase;
  letter-spacing: 0.8px;
  margin-bottom: 5px;
}
.btn-save {
  padding: 10px 24px;
  background: var(--text-p);
  color: var(--bg);
  border-radius: var(--radius);
  font-family: var(--display);
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 1px;
  margin-top: 8px;
  transition: opacity var(--transition);
}
.btn-save:hover { opacity: 0.85; }
.profile-feedback {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--present);
  margin-top: 10px;
}
.profile-feedback.err { color: var(--absent); }

/* ── Placeholder / Empty States ──────────────────────────── */
.placeholder-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 60vh;
  text-align: center;
  gap: 12px;
}
.placeholder-icon {
  font-size: 48px;
  opacity: 0.15;
  line-height: 1;
}
.placeholder-title {
  font-family: var(--display);
  font-size: 22px;
  font-weight: 800;
  letter-spacing: 2px;
  color: var(--text-s);
}
.placeholder-sub {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--text-m);
  max-width: 360px;
}

/* ── Home page ───────────────────────────────────────────── */
.home-tagline {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--text-s);
  letter-spacing: 2px;
  text-transform: uppercase;
  margin-bottom: 4px;
}
.home-splash {
  font-family: var(--display);
  font-size: 32px;
  font-weight: 800;
  line-height: 1.15;
  margin-bottom: 8px;
}
.home-desc {
  font-family: var(--mono);
  font-size: 12px;
  color: var(--text-s);
  max-width: 500px;
  margin-bottom: 32px;
  line-height: 1.7;
}
.divider {
  border: none;
  border-top: 1px solid var(--card-border);
  margin: 24px 0;
}

/* ── Scrollbars ──────────────────────────────────────────── */
::-webkit-scrollbar { width: 4px; height: 4px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--card-border); border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: #2e2e2e; }

/* ── Animations ──────────────────────────────────────────── */
@keyframes fadeIn  { from { opacity: 0; } to { opacity: 1; } }
@keyframes slideUp { from { opacity: 0; transform: translateY(16px); } to { opacity: 1; transform: translateY(0); } }

/* ── Loading spinner ─────────────────────────────────────── */
.spinner {
  width: 20px; height: 20px;
  border: 2px solid var(--card-border);
  border-top-color: var(--text-s);
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
  display: inline-block;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── Responsive ──────────────────────────────────────────── */
@media (max-width: 600px) {
  .page-container { padding: 14px; }
  .audit-grid { grid-template-columns: 1fr; }
  .home-splash { font-size: 22px; }
}
