#!/usr/bin/env node
// Creates the Supabase credential in n8n so the "Store AI Outputs (Supabase)" node works.
const http = require('http');

function req(opts, body) {
  return new Promise((res, rej) => {
    const b = body ? JSON.stringify(body) : null;
    if (b) {
      opts.headers = opts.headers || {};
      opts.headers['Content-Type'] = 'application/json';
      opts.headers['Content-Length'] = Buffer.byteLength(b);
    }
    const r = http.request(opts, resp => {
      let d = '';
      resp.on('data', c => d += c);
      resp.on('end', () => res({ s: resp.statusCode, h: resp.headers, b: d }));
    });
    r.on('error', rej);
    if (b) r.write(b);
    r.end();
  });
}

async function main() {
  const BASE = { hostname: 'localhost', port: 5678 };

  // Login
  const lr = await req({ ...BASE, path: '/rest/login', method: 'POST' }, {
    emailOrLdapLoginId: 'admin@studyshare.local',
    password: 'Admin@StudyShare2024!'
  });
  if (lr.s !== 200) { console.error('Login failed:', lr.s, lr.b.substring(0, 200)); process.exit(1); }
  const cookies = (lr.h['set-cookie'] || []).map(c => c.split(';')[0]).join('; ');
  console.log('✅ Logged in');

  const hdrs = { Cookie: cookies };

  // Check if credential already exists
  const listCr = await req({ ...BASE, path: '/rest/credentials', method: 'GET', headers: hdrs });
  const existing = JSON.parse(listCr.b).data || [];
  const alreadyExists = existing.find(c => c.name === 'Supabase (StudyShare)');
  if (alreadyExists) {
    console.log('✅ Credential "Supabase (StudyShare)" already exists (id:', alreadyExists.id + ')');
    return;
  }

  // Create Supabase credential
  const cr = await req({ ...BASE, path: '/rest/credentials', method: 'POST', headers: hdrs }, {
    name: 'Supabase (StudyShare)',
    type: 'supabaseApi',
    data: {
      host: 'https://iayuwsvguwfqjgjsvjiy.supabase.co',
      serviceRole: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlheXV3c3ZndXdmcWpnanN2aml5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NjA1MTkxMSwiZXhwIjoyMDgxNjI3OTExfQ.Zur3Mu-IeVOb3hkd1XkEn3IQRy_yXULqdJVs8zsVzZI'
    }
  });
  console.log('Create credential status:', cr.s);
  if (cr.s === 200 || cr.s === 201) {
    const cd = JSON.parse(cr.b);
    console.log('✅ Created credential id:', cd.data && cd.data.id, 'name:', cd.data && cd.data.name);
  } else {
    console.error('❌ Failed:', cr.b.substring(0, 400));
  }
}

main().catch(console.error);
