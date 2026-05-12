// js/pages/home.js
function home(container) {
  container.innerHTML = `
    <div class="page">
      <div class="home-tagline">Facial Recognition Attendance Software</div>
      <div class="home-splash">GIFT<br>Dashboard</div>
      <div class="home-desc">
        Real-time oversight of attendance sessions, audit logs, and device health.<br>
        Use the sidebar to navigate sections.
      </div>
      <hr class="divider" />
      <div class="stat-grid" id="home-stats">
        <div class="stat-card"><div class="stat-value" id="hs-teachers">—</div><div class="stat-label">Teachers Online</div></div>
        <div class="stat-card"><div class="stat-value" id="hs-orgs">—</div><div class="stat-label">Organizations</div></div>
        <div class="stat-card"><div class="stat-value" id="hs-sessions">—</div><div class="stat-label">Total Att. Sessions</div></div>
        <div class="stat-card"><div class="stat-value" id="hs-devices">—</div><div class="stat-label">Registered Devices</div></div>
      </div>
      <hr class="divider" />
      <div class="card-title">Recent Pings</div>
      <div id="home-pings" style="font-family:var(--mono);font-size:11px;color:var(--text-s);">Loading…</div>
    </div>`;

  // Stats from users collection
  db.collection('users').get().then(snap => {
    document.getElementById('hs-devices').textContent = snap.size;
    const orgs = new Set();
    snap.forEach(d => { if (d.data().org_id) orgs.add(d.data().org_id); });
    document.getElementById('hs-orgs').textContent = orgs.size;
  }).catch(e => console.error('[home] users', e));

  // Count pings as proxy for sessions
  db.collection('pings').get().then(snap => {
    document.getElementById('hs-sessions').textContent = snap.size;
  }).catch(e => console.error('[home] pings', e));

  // Active teachers (last_seen within 7 days)
  const cutoff = new Date(Date.now() - 7 * 864e5);
  db.collection('users').where('last_seen', '>', cutoff).get().then(snap => {
    document.getElementById('hs-teachers').textContent = snap.size;
  }).catch(() => document.getElementById('hs-teachers').textContent = '—');

  // Recent pings live
  const unsub = db.collection('pings').orderBy('timestamp','desc').limit(10)
    .onSnapshot(snap => {
      const el = document.getElementById('home-pings');
      if (!el) return;
      if (snap.empty) { el.textContent = 'No pings yet.'; return; }
      el.innerHTML = snap.docs.map(d => {
        const data = d.data();
        const ts   = data.timestamp?.toDate?.()?.toLocaleString() || '—';
        return `<div style="padding:4px 0;border-bottom:1px solid var(--card-border)">
          <span style="color:var(--text-p)">${data.account_name || '?'}</span>
          <span style="color:var(--text-m)"> · ${data.org_id || ''} · ${data.device_model || ''} · </span>
          <span style="color:var(--text-m)">${ts}</span>
        </div>`;
      }).join('');
    }, e => console.error('[home] pings live', e));

  registerUnsub(unsub);
}
