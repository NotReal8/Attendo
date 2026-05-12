// js/pages/killswitch.js
// Reads/writes config/kill_switch in Firestore — same doc the mobile app listens to

function killswitch(container) {
  container.innerHTML = `
    <div class="page">
      <div class="page-header">
        <div><div class="page-title">Kill Switch</div>
          <div class="page-sub">Remote control over app access · writes to config/kill_switch</div></div>
      </div>
      <div class="kill-grid">

        <!-- Global toggle -->
        <div class="kill-card danger">
          <div class="kill-label">Global App Access</div>
          <div class="toggle-row">
            <div>
              <div class="toggle-desc">All Devices Active</div>
              <div class="toggle-sub">Turn off to kill every device immediately</div>
            </div>
            <label class="toggle-switch">
              <input type="checkbox" id="ks-global" onchange="ksSetGlobal(this.checked)" checked />
              <span class="toggle-track"></span>
            </label>
          </div>
        </div>

        <!-- Kill message -->
        <div class="kill-card">
          <div class="kill-label">Kill Message</div>
          <div style="font-size:12px;color:var(--text-s)">Shown on device when killed</div>
          <div class="kill-msg-box">
            <textarea id="ks-msg" placeholder="This app has been disabled by the administrator."></textarea>
          </div>
          <div style="margin-top:8px">
            <button class="btn-sm" onclick="ksSaveMsg()">Save Message</button>
          </div>
        </div>

        <!-- Kill by device -->
        <div class="kill-card">
          <div class="kill-label">Kill by Device ID</div>
          <div class="kill-input-row">
            <input id="ks-dev-input" placeholder="Device ID (android.id)" />
            <button class="btn-sm danger" onclick="ksAddDevice()">Kill</button>
          </div>
          <div class="kill-list" id="ks-dev-list"></div>
        </div>

        <!-- Kill by account -->
        <div class="kill-card">
          <div class="kill-label">Kill by Account Name</div>
          <div class="kill-input-row">
            <input id="ks-acc-input" placeholder="Account name" />
            <button class="btn-sm danger" onclick="ksAddAccount()">Kill</button>
          </div>
          <div class="kill-list" id="ks-acc-list"></div>
        </div>

      </div>
      <div id="ks-status" style="margin-top:16px;font-family:var(--mono);font-size:11px;color:var(--text-s)"></div>
    </div>`;

  // Load current state
  const unsub = db.collection('config').doc('kill_switch').onSnapshot(snap => {
    const data = snap.exists ? snap.data() : {};
    console.log('[killswitch] snapshot', data);

    const globalEl = document.getElementById('ks-global');
    const msgEl    = document.getElementById('ks-msg');
    if (globalEl) globalEl.checked = data.active !== false;
    if (msgEl && data.message) msgEl.value = data.message;

    // Render device list
    _ksRenderList('ks-dev-list', data.killed_devices || [], 'device');
    _ksRenderList('ks-acc-list', data.killed_accounts || [], 'account');

    const statusEl = document.getElementById('ks-status');
    if (statusEl) statusEl.textContent = 'Last updated: ' + (data.updated_at?.toDate?.()?.toLocaleString() || '—');
  }, e => console.error('[killswitch]', e));

  registerUnsub(unsub);
}

function _ksRenderList(elId, items, type) {
  const el = document.getElementById(elId);
  if (!el) return;
  el.innerHTML = items.length === 0
    ? '<div style="font-family:var(--mono);font-size:11px;color:var(--text-m)">None killed.</div>'
    : items.map(v => `
        <div class="kill-tag">
          <span>${v}</span>
          <button onclick="ksRemove('${type}','${v}')" title="Revive">✕</button>
        </div>`).join('');
}

async function _ksUpdate(patch) {
  patch.updated_at = firebase.firestore.FieldValue.serverTimestamp();
  await db.collection('config').doc('kill_switch').set(patch, { merge: true });
  console.log('[killswitch] updated', patch);
}

async function ksSetGlobal(checked) {
  console.log('[killswitch] global toggle =>', checked);
  await _ksUpdate({ active: checked });
}

async function ksSaveMsg() {
  const msg = document.getElementById('ks-msg')?.value.trim();
  if (!msg) return;
  await _ksUpdate({ message: msg });
}

async function ksAddDevice() {
  const val = document.getElementById('ks-dev-input')?.value.trim();
  if (!val) return;
  await _ksUpdate({ killed_devices: firebase.firestore.FieldValue.arrayUnion(val) });
  document.getElementById('ks-dev-input').value = '';
}

async function ksAddAccount() {
  const val = document.getElementById('ks-acc-input')?.value.trim();
  if (!val) return;
  await _ksUpdate({ killed_accounts: firebase.firestore.FieldValue.arrayUnion(val) });
  document.getElementById('ks-acc-input').value = '';
}

async function ksRemove(type, val) {
  const field = type === 'device' ? 'killed_devices' : 'killed_accounts';
  await _ksUpdate({ [field]: firebase.firestore.FieldValue.arrayRemove(val) });
}
