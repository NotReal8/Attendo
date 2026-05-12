// js/pages/teacher-roster.js
function teacherRoster(container) {
  container.innerHTML = `
    <div class="page">
      <div class="page-header">
        <div><div class="page-title">Teacher Roster</div>
          <div class="page-sub">All accounts registered via the mobile app or web dashboard</div></div>
      </div>
      <div id="tr-grid" class="roster-grid" style="margin-top:8px">
        <div style="font-family:var(--mono);font-size:12px;color:var(--text-s)">Loading…</div>
      </div>
    </div>`;

  const unsub = db.collection('users').orderBy('last_seen','desc')
    .onSnapshot(snap => {
      const grid = document.getElementById('tr-grid');
      if (!grid) return;
      if (snap.empty) { grid.innerHTML = '<div style="font-family:var(--mono);font-size:12px;color:var(--text-s)">No teachers registered yet.</div>'; return; }

      grid.innerHTML = snap.docs.map(doc => {
        const d    = doc.data();
        const name = d.account_name || '?';
        const init = name.charAt(0).toUpperCase();
        const ts   = d.last_seen?.toDate?.()?.toLocaleDateString() || '—';
        return `
          <div class="roster-card">
            <div class="roster-avatar">${init}</div>
            <div class="roster-info">
              <div class="roster-name">${name}</div>
              <div class="roster-meta">${d.org_id || '—'} · ${d.device_brand || ''} ${d.device_model || ''}</div>
              <div class="roster-meta">Last seen: ${ts}</div>
            </div>
            <div class="roster-role">${d.account_role || d.role || '—'}</div>
          </div>`;
      }).join('');
    }, e => {
      const grid = document.getElementById('tr-grid');
      if (grid) grid.innerHTML = `<div style="color:var(--absent);font-family:var(--mono);font-size:12px">Error: ${e.message}</div>`;
    });

  registerUnsub(unsub);
}

// js/pages/student-roster.js — placeholder
function studentRoster(container) {
  container.innerHTML = `
    <div class="page">
      <div class="page-header"><div class="page-title">Student Roster</div></div>
      <div class="placeholder-hero">
        <div class="placeholder-icon">◽</div>
        <div class="placeholder-title">Coming Soon</div>
        <div class="placeholder-sub">Student roster sync will be added in a future update.</div>
      </div>
    </div>`;
}

// js/pages/settings.js — placeholder
function settings(container) {
  container.innerHTML = `
    <div class="page">
      <div class="page-header"><div class="page-title">Settings</div></div>
      <div class="placeholder-hero">
        <div class="placeholder-icon">⊕</div>
        <div class="placeholder-title">Coming Soon</div>
        <div class="placeholder-sub">Settings will be added in a future update.</div>
      </div>
    </div>`;
}
