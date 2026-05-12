// js/app.js
const pages = { home, audit, attendance, teacherRoster, studentRoster, killswitch, profile, settings };
const pageMap = {
  'home': home, 'audit': audit, 'attendance': attendance,
  'teacher-roster': teacherRoster, 'student-roster': studentRoster,
  'killswitch': killswitch, 'profile': profile, 'settings': settings
};

let activeUnsubs = []; // Firestore listeners to tear down on nav

function navigateTo(pageKey, linkEl) {
  // Unsubscribe active listeners
  activeUnsubs.forEach(u => { try { u(); } catch(_) {} });
  activeUnsubs = [];

  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
  if (linkEl) linkEl.classList.add('active');

  const container = document.getElementById('page-container');
  container.innerHTML = '';

  const fn = pageMap[pageKey];
  if (fn) fn(container);

  // Close sidebar on mobile
  if (window.innerWidth < 768) closeSidebar();
}

function toggleSidebar() {
  const sb = document.getElementById('sidebar');
  sb.classList.toggle('open');
  let bd = document.getElementById('sidebar-backdrop');
  if (!bd) {
    bd = document.createElement('div');
    bd.id = 'sidebar-backdrop';
    bd.className = 'sidebar-backdrop';
    bd.onclick = closeSidebar;
    document.body.appendChild(bd);
  }
  bd.classList.toggle('visible', sb.classList.contains('open'));
}

function closeSidebar() {
  document.getElementById('sidebar').classList.remove('open');
  const bd = document.getElementById('sidebar-backdrop');
  if (bd) bd.classList.remove('visible');
}

function registerUnsub(fn) { activeUnsubs.push(fn); }

// Boot
document.addEventListener('DOMContentLoaded', initAuth);
