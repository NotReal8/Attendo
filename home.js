// js/pages/audit.js

// Lines containing these substrings are shown in filtered mode
const AUDIT_SHOW_KEYWORDS = [
  'MATCH','enrolled','ERROR','❌','✅','session','FAIL','present','absent',
  'KILL','kill','RESET','START','STOP','initialized','ready','ping'
];

function _shouldShow(line) {
  return AUDIT_SHOW_KEYWORDS.some(k => line.includes(k));
}

function _lineClass(line) {
  if (line.includes('❌') || line.includes('ERROR') || line.includes('FAIL') || line.includes('💥')) return 'err';
  if (line.includes('✅') || line.includes('MATCH') || line.includes('present')) return 'ok';
  if (line.includes('⚠️') || line.includes('KILL') || line.includes('warn')) return 'warn';
  if (line.includes('[Beacon]') || line.includes('[Firebase]')) return 'info';
  return 'normal';
}

function _appendLine(logEl, text, raw) {
  if (!raw && !_shouldShow(text)) return;
  const d = document.createElement('div');
  d.className = 'log-line ' + _lineClass(text);
  d.textContent = text;
  logEl.appendChild(d);
  logEl.scrollTop = logEl.scrollHeight;
}

function audit(container) {
  container.innerHTML = `
    <div class="page">
      <div class="page-header">
        <div><div class="page-title">Audit Analytics</div>
          <div class="page-sub">Real-time logs per device · filtered by default</div></div>
      </div>
      <div class="audit-filter-bar">
        <input id="audit-search" placeholder="Filter by device / name…" oninput="auditFilter()" />
        <span style="font-family:var(--mono);font-size:11px;color:var(--text-s)" id="audit-count">Loading…</span>
      </div>
      <div id="audit-grid" class="audit-grid">
        <div class="audit-loading">Connecting to Firestore…</div>
      </div>
    </div>`;

  // Map: deviceId → { boxEl, logEl, rawMode, unsub }
  const boxes = {};

  function getOrCreateBox(deviceId, accountName) {
    if (boxes[deviceId]) return boxes[deviceId];

    const box = document.createElement('div');
    box.className = 'audit-box';
    box.dataset.name = accountName.toLowerCase();
    box.innerHTML = `
      <div class="audit-box-header">
        <div class="audit-dot" id="dot-${deviceId}"></div>
        <div class="audit-box-name">${accountName}</div>
        <div class="audit-box-meta" id="meta-${deviceId}"></div>
        <button class="audit-raw-toggle" id="raw-${deviceId}" onclick="auditToggleRaw('${deviceId}')">raw</button>
      </div>
      <div class="audit-log" id="log-${deviceId}"></div>`;

    const grid = document.getElementById('audit-grid');
    // Remove loading placeholder on first box
    const placeholder = grid.querySelector('.audit-loading');
    if (placeholder) placeholder.remove();

    grid.appendChild(box);
    boxes[deviceId] = { box, logEl: box.querySelector('.audit-log'), rawMode: false };
    return boxes[deviceId];
  }

  // Listen to all devices in users/ to build box list
  const unsubUsers = db.collection('users').onSnapshot(snap => {
    const countEl = document.getElementById('audit-count');
    if (countEl) countEl.textContent = snap.size + ' device(s)';

    snap.forEach(doc => {
      const data     = doc.data();
      const deviceId = doc.id;
      const name     = data.account_name || deviceId;
      getOrCreateBox(deviceId, name);

      // Update last-seen meta
      const metaEl = document.getElementById('meta-' + deviceId);
      if (metaEl && data.last_seen) {
        const d = data.last_seen.toDate?.();
        if (d) metaEl.textContent = d.toLocaleTimeString();
      }
    });

    // Attach log listeners for each device
    snap.forEach(doc => {
      const deviceId = doc.id;
      const entry    = boxes[deviceId];
      if (!entry || entry.unsub) return; // already listening

      const unsub = db.collection('logs').doc(deviceId).collection('sessions')
        .orderBy('flushed_at', 'desc').limit(8)
        .onSnapshot(sessSnap => {
          const logEl = document.getElementById('log-' + deviceId);
          if (!logEl) return;

          // Collect all lines from recent sessions, newest last
          const allLines = [];
          sessSnap.docs.slice().reverse().forEach(s => {
            const lines = s.data().lines || [];
            allLines.push(...lines);
          });

          // Re-render
          logEl.innerHTML = '';
          if (allLines.length === 0) {
            logEl.innerHTML = '<div class="audit-empty">No logs yet.</div>';
            return;
          }
          allLines.slice(-200).forEach(line => _appendLine(logEl, line, entry.rawMode));
          logEl.scrollTop = logEl.scrollHeight;

          // Pulse dot
          const dot = document.getElementById('dot-' + deviceId);
          if (dot) { dot.style.background = 'var(--present)'; dot.classList.remove('offline'); }
        }, err => {
          console.error('[audit] log listener', deviceId, err);
          const dot = document.getElementById('dot-' + deviceId);
          if (dot) dot.classList.add('offline');
        });

      entry.unsub = unsub;
      registerUnsub(unsub);
    });
  }, e => {
    console.error('[audit] users listener', e);
    const grid = document.getElementById('audit-grid');
    if (grid) grid.innerHTML = '<div class="audit-loading" style="color:var(--absent)">Failed to connect: ' + e.message + '</div>';
  });

  registerUnsub(unsubUsers);

  // Expose to global for toggle button
  window._auditBoxes = boxes;
}

function auditToggleRaw(deviceId) {
  const boxes = window._auditBoxes;
  if (!boxes || !boxes[deviceId]) return;
  const entry  = boxes[deviceId];
  entry.rawMode = !entry.rawMode;
  const btn = document.getElementById('raw-' + deviceId);
  if (btn) btn.classList.toggle('active', entry.rawMode);
  // Re-render log with new mode — trigger by forcing a re-read from DOM isn't ideal;
  // Firestore snapshot will re-fire on next update. For immediate effect, re-render:
  const logEl = document.getElementById('log-' + deviceId);
  if (!logEl) return;
  const lines = Array.from(logEl.querySelectorAll('.log-line')).map(el => el.textContent);
  logEl.innerHTML = '';
  lines.forEach(line => _appendLine(logEl, line, entry.rawMode));
}

function auditFilter() {
  const q = document.getElementById('audit-search').value.toLowerCase();
  document.querySelectorAll('.audit-box').forEach(box => {
    box.style.display = (!q || box.dataset.name.includes(q)) ? '' : 'none';
  });
}
