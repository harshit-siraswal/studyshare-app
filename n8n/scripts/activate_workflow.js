#!/usr/bin/env node
// n8n complete setup + workflow activation
const http = require('http');

function request(options, bodyObj = null) {
  return new Promise((resolve, reject) => {
    const body = bodyObj ? JSON.stringify(bodyObj) : null;
    if (body) {
      options.headers = options.headers || {};
      options.headers['Content-Type'] = 'application/json';
      options.headers['Content-Length'] = Buffer.byteLength(body);
    }
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

function parseSetCookies(headers) {
  const cookies = headers['set-cookie'];
  if (!cookies) return '';
  return (Array.isArray(cookies) ? cookies : [cookies]).map(c => c.split(';')[0]).join('; ');
}

const BASE = { hostname: 'localhost', port: 5678 };

async function main() {
  // Try first-time owner setup
  console.log('=== Setting up owner account ===');
  const setupRes = await request({
    ...BASE, path: '/rest/owner/setup', method: 'POST',
  }, {
    email: 'admin@studyshare.local',
    firstName: 'Admin', lastName: 'StudyShare',
    password: '75bd2cf5e5fd9a5020b718ec39e8e6dfa95a'
  });
  console.log('Setup status:', setupRes.status, setupRes.body.substring(0, 300));

  let cookieStr = parseSetCookies(setupRes.headers);

  // If setup returned user, try to use the session cookie
  if (setupRes.status !== 200 && setupRes.status !== 201) {
    // Maybe already set up, try login
    console.log('\n=== Trying login ===');
    const loginRes = await request({
      ...BASE, path: '/rest/login', method: 'POST',
    }, {
      emailOrLdapLoginId: 'admin@studyshare.local',
      password: '75bd2cf5e5fd9a5020b718ec39e8e6dfa95a'
    });
    console.log('Login status:', loginRes.status, loginRes.body.substring(0, 200));
    cookieStr = parseSetCookies(loginRes.headers);
  }

  if (!cookieStr) {
    console.error('Could not get session cookie');
    process.exit(1);
  }
  console.log('Session cookie obtained');

  // List workflows
  console.log('\n=== Listing workflows ===');
  const listRes = await request({
    ...BASE, path: '/rest/workflows', method: 'GET',
    headers: { Cookie: cookieStr }
  });
  console.log('List status:', listRes.status);
  
  if (listRes.status !== 200) {
    console.error('Cannot list workflows:', listRes.body.substring(0, 200));
    process.exit(1);
  }

  const data = JSON.parse(listRes.body);
  const wfs = data.data || [];
  console.log('Found', wfs.length, 'workflows');
  wfs.forEach(w => console.log(' -', w.id, w.name, 'active:', w.active));

  const pdfWf = wfs.find(w => w.name && w.name.includes('PDF'));
  if (!pdfWf) {
    console.error('PDF Pipeline workflow not found — import may have failed');
    process.exit(1);
  }

  if (pdfWf.active) {
    console.log('\nWorkflow', pdfWf.id, 'is already ACTIVE');
    return;
  }

  console.log('\n=== Activating workflow', pdfWf.id, '===');
  const activateRes = await request({
    ...BASE, path: `/rest/workflows/${pdfWf.id}/activate`, method: 'POST',
    headers: { Cookie: cookieStr }
  });
  console.log('Activate status:', activateRes.status);
  console.log('Response:', activateRes.body.substring(0, 300));

  if (activateRes.status === 200) {
    console.log('\n✅ Workflow activated successfully!');
  } else {
    console.error('\n❌ Activation failed');
  }
}

main().catch(console.error);
