// js/auth.js
let currentUser = null;

function togglePw(id, btn) {
  const el = document.getElementById(id);
  el.type = el.type === 'password' ? 'text' : 'password';
  btn.textContent = el.type === 'password' ? '👁' : '🙈';
}

function showRegister() {
  document.getElementById('signin-form').classList.add('hidden');
  document.getElementById('register-form').classList.remove('hidden');
  document.getElementById('auth-title').textContent = 'Create Account';
  document.getElementById('auth-sub').textContent = 'Register to access the dashboard.';
}

function showSignIn() {
  document.getElementById('register-form').classList.add('hidden');
  document.getElementById('signin-form').classList.remove('hidden');
  document.getElementById('auth-title').textContent = 'Sign In';
  document.getElementById('auth-sub').textContent = 'Enter your credentials to access the dashboard.';
}

function setAuthError(formPrefix, msg) {
  const el = document.getElementById(formPrefix + '-error');
  el.textContent = msg;
  el.classList.remove('hidden');
}

function clearAuthError(prefix) {
  const el = document.getElementById(prefix + '-error');
  if (el) { el.textContent = ''; el.classList.add('hidden'); }
}

async function handleRegister() {
  clearAuthError('reg');
  const org  = document.getElementById('reg-org').value.trim();
  const user = document.getElementById('reg-user').value.trim();
  const pass = document.getElementById('reg-pass').value.trim();
  const role = document.getElementById('reg-role').value;

  if (!org || !user || !pass) { setAuthError('reg', 'All fields required.'); return; }

  const btn = document.getElementById('reg-btn');
  btn.disabled = true; btn.textContent = 'Creating…';

  try {
    // Check if username already exists in this org
    const snap = await db.collection('organizations').doc(org)
      .collection('accounts').where('account_name', '==', user).get();

    if (!snap.empty) { setAuthError('reg', 'Username already exists in this org.'); return; }

    const docId = 'web_' + org + '_' + user.replace(/\s+/g, '_');
    await db.collection('organizations').doc(org).set({ name: org }, { merge: true });
    await db.collection('organizations').doc(org).collection('accounts').doc(docId).set({
      account_name: user,
      account_pass: pass,
      role,
      org_id:       org,
      device_id:    docId,
      device_model: 'web-dashboard',
      device_brand: 'web',
      last_seen:    firebase.firestore.FieldValue.serverTimestamp(),
      registered_web: true,
    });

    console.log('[Auth] registered', user, org);
    // Auto sign in
    currentUser = { name: user, org, role, docId };
    _enterApp();
  } catch (e) {
    console.error('[Auth] register error', e);
    setAuthError('reg', 'Error: ' + e.message);
  } finally {
    btn.disabled = false; btn.textContent = 'Create Account';
  }
}

async function handleSignIn() {
  clearAuthError('si');
  const org  = document.getElementById('si-org').value.trim();
  const user = document.getElementById('si-user').value.trim();
  const pass = document.getElementById('si-pass').value.trim();

  if (!org || !user || !pass) { setAuthError('si', 'All fields required.'); return; }

  const btn = document.getElementById('si-btn');
  btn.disabled = true; btn.textContent = 'Signing in…';

  try {
    const snap = await db.collection('organizations').doc(org)
      .collection('accounts')
      .where('account_name', '==', user)
      .where('account_pass', '==', pass)
      .get();

    if (snap.empty) { setAuthError('si', 'Invalid credentials.'); return; }

    const docData = snap.docs[0].data();
    const docId   = snap.docs[0].id;
    currentUser   = { name: user, org, role: docData.role || 'Teacher', docId };

    // Update last_seen
    await db.collection('organizations').doc(org).collection('accounts').doc(docId)
      .update({ last_seen: firebase.firestore.FieldValue.serverTimestamp() });

    console.log('[Auth] signed in', user, org);
    _enterApp();
  } catch (e) {
    console.error('[Auth] signin error', e);
    setAuthError('si', 'Error: ' + e.message);
  } finally {
    btn.disabled = false; btn.textContent = 'Enter Dashboard';
  }
}

function _enterApp() {
  document.getElementById('auth-overlay').classList.add('hidden');
  document.getElementById('app').classList.remove('hidden');
  document.getElementById('topbar-user').textContent = currentUser.name;
  sessionStorage.setItem('gift_user', JSON.stringify(currentUser));
  navigateTo('home', document.querySelector('.nav-item[data-page="home"]'));
}

function signOut() {
  currentUser = null;
  sessionStorage.removeItem('gift_user');
  document.getElementById('app').classList.add('hidden');
  document.getElementById('auth-overlay').classList.remove('hidden');
  document.getElementById('page-container').innerHTML = '';
  showSignIn();
  console.log('[Auth] signed out');
}

function initAuth() {
  // Restore session
  const saved = sessionStorage.getItem('gift_user');
  if (saved) {
    try {
      currentUser = JSON.parse(saved);
      _enterApp();
      return;
    } catch(_) {}
  }
  document.getElementById('auth-overlay').classList.remove('hidden');
}
