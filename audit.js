// js/pages/attendance.js
// Reads from the 'attendance' Firestore collection.
// Mobile app does NOT write here directly — it writes to SQLite on device.
// To sync, the mobile app's TransferService exports JSON; you import via Settings.
// Alternatively, attendance_service.dart can be extended to mirror to Firestore.
// This page reads whatever is in Firestore attendance/.

function attendance(container) {
  container.innerHTML = `
    <div class="page">
      <div class="page-header">
        <div><div class="page-title">Attendance Records</div>
          <div class="page-sub">Synced from mobile devices via Firestore</div></div>
      </div>
      <div class="att-controls">
        <select id="att-date-sel" onchange="attLoadRecords()"><option value="">All Dates</option></select>
        <select id="att-org-sel"  onchange="attLoadRecords()"><option value="">All Orgs</option></select>
        <input  id="att-search"   placeholder="Search student…" oninput="attApplyFilter()" />
        <span style="font-family:var(--mono);font-size:11px;color:var(--text-s)" id="att-count"></span>
      </div>
      <div class="stat-grid" style="margin-bottom:16px">
        <div class="stat-card"><div class="stat-value" id="att-present">—</div><div class="stat-label">Present</div></div>
        <div class="stat-card"><div class="stat-value" id="att-absent">—</div><div class="stat-label">Absent</div></div>
        <div class="stat-card"><div class="stat-value" id="att-rate">—</div><div class="stat-label">Rate</div></div>
        <div class="stat-card"><div class="stat-value" id="att-total">—</div><div class="stat-label">Total Records</div></div>
      </div>
      <div class="att-table-wrap">
        <table>
          <thead><tr>
            <th>Student</th><th>Date</th><th>Session</th><th>Org</th><th>Status</th>
          </tr></thead>
          <tbody id="att-body"><tr><td colspan="5" style="color:var(--text-s);text-align:center;padding:32px">Loading…</td></tr></tbody>
        </table>
      </div>
    </div>`;

  window._attAllRows = [];

  // Fetch attendance from Firestore
  // Expected schema: { session_date, session_label, student_name, status, org_id, device_id }
  const unsub = db.collection('attendance')
    .orderBy('session_date', 'desc')
    .limit(2000)
    .onSnapshot(snap => {
      const rows = [];
      const dates = new Set(), orgs = new Set();

      snap.forEach(doc => {
        const d = doc.data();
        rows.push({ id: doc.id, ...d });
        if (d.session_date) dates.add(d.session_date);
        if (d.org_id)       orgs.add(d.org_id);
      });

      window._attAllRows = rows;

      // Populate date selector
      const dateSel = document.getElementById('att-date-sel');
      const orgSel  = document.getElementById('att-org-sel');
      if (!dateSel) return;

      const prevDate = dateSel.value, prevOrg = orgSel.value;
      dateSel.innerHTML = '<option value="">All Dates</option>' +
        [...dates].sort().reverse().map(d => `<option value="${d}">${d}</option>`).join('');
      orgSel.innerHTML  = '<option value="">All Orgs</option>' +
        [...orgs].sort().map(o => `<option value="${o}">${o}</option>`).join('');

      dateSel.value = prevDate;
      orgSel.value  = prevOrg;

      attApplyFilter();
    }, e => {
      console.error('[attendance]', e);
      const body = document.getElementById('att-body');
      if (body) body.innerHTML = `<tr><td colspan="5" style="color:var(--absent)">Error: ${e.message}</td></tr>`;
    });

  registerUnsub(unsub);
}

function attLoadRecords() { attApplyFilter(); }

function attApplyFilter() {
  const rows   = window._attAllRows || [];
  const date   = document.getElementById('att-date-sel')?.value || '';
  const org    = document.getElementById('att-org-sel')?.value  || '';
  const search = (document.getElementById('att-search')?.value  || '').toLowerCase();

  const filtered = rows.filter(r =>
    (!date   || r.session_date  === date) &&
    (!org    || r.org_id        === org)  &&
    (!search || (r.student_name || '').toLowerCase().includes(search))
  );

  const present = filtered.filter(r => r.status === 'present').length;
  const absent  = filtered.filter(r => r.status === 'absent').length;
  const total   = filtered.length;
  const rate    = total ? Math.round(present / total * 100) + '%' : '—';

  const setEl = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  setEl('att-present', present);
  setEl('att-absent',  absent);
  setEl('att-rate',    rate);
  setEl('att-total',   total);
  setEl('att-count',   total + ' records');

  const body = document.getElementById('att-body');
  if (!body) return;

  if (!filtered.length) {
    body.innerHTML = '<tr><td colspan="5" style="color:var(--text-s);text-align:center;padding:32px">No records found.</td></tr>';
    return;
  }

  body.innerHTML = filtered.slice(0, 500).map(r => `
    <tr>
      <td>${r.student_name || '—'}</td>
      <td>${r.session_date || '—'}</td>
      <td>${r.session_label || '—'}</td>
      <td>${r.org_id || '—'}</td>
      <td><span class="badge ${r.status}">${r.status || '—'}</span></td>
    </tr>`).join('');

  if (filtered.length > 500) {
    body.innerHTML += `<tr><td colspan="5" style="color:var(--text-s);text-align:center;padding:10px;font-family:var(--mono);font-size:11px">Showing 500 of ${filtered.length}</td></tr>`;
  }
}
