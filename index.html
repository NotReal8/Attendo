// js/pages/profile.js
function profile(container) {
  if (!currentUser) { container.innerHTML = '<div class="page"><p>Not signed in.</p></div>'; return; }

  container.innerHTML = `
    <div class="page">
      <div class="page-header"><div class="page-title">Profile</div></div>
      <div class="profile-form">
        <div class="profile-row"><label>Username</label>
          <input type="text" id="pf-name" value="${currentUser.name}" /></div>
        <div class="profile-row"><label>Organization</label>
          <input type="text" id="pf-org"  value="${currentUser.org}"  /></div>
        <div class="profile-row"><label>Role</label>
          <select id="pf-role">
            <option value="Teacher" ${currentUser.role==='Teacher'?'selected':''}>Teacher</option>
            <option value="HR"      ${currentUser.role==='HR'     ?'selected':''}>HR / Admin</option>
          </select></div>
        <div class="profile-row"><label>Device / Source</label>
          <input type="text" value="${currentUser.docId}" disabled /></div>
        <button class="btn-save" onclick="profileSave()">Save Changes</button>
        <div id="pf-feedback" class="profile-feedback hidden"></div>
      </div>
    </div>`;

  console.log('[profile] loaded for', currentUser.docId);
}

async function profileSave() {
  const name = document.getElementById('pf-name')?.value.trim();
  const org  = document.getElementById('pf-org')?.value.trim();
  const role = document.getElementById('pf-role')?.value;
  const fb   = document.getElementById('pf-feedback');

  if (!name || !org) { _pfFeedback('Name and Org are required.', true); return; }

  try {
    // Update users/ doc
    await db.collection('users').doc(currentUser.docId).set({
      account_name: name,
      org_id:       org,
      account_role: role,
      last_seen:    firebase.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Update org accounts
    await db.collection('organizations').doc(currentUser.org)
      .collection('accounts').doc(currentUser.docId).set({
        account_name: name,
        org_id:       org,
        role,
        last_seen:    firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    // Update session
    currentUser.name = name;
    currentUser.org  = org;
    currentUser.role = role;
    sessionStorage.setItem('gift_user', JSON.stringify(currentUser));
    document.getElementById('topbar-user').textContent = name;

    console.log('[profile] saved', { name, org, role });
    _pfFeedback('Saved ✓', false);
  } catch (e) {
    console.error('[profile] save error', e);
    _pfFeedback('Error: ' + e.message, true);
  }
}

function _pfFeedback(msg, isErr) {
  const el = document.getElementById('pf-feedback');
  if (!el) return;
  el.textContent = msg;
  el.className = 'profile-feedback' + (isErr ? ' err' : '');
  el.classList.remove('hidden');
  setTimeout(() => el.classList.add('hidden'), 3000);
}
