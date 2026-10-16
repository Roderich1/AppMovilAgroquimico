// F08-BKP: comprobación previa de /api/v1/me/backups contra la API COMPILADA
// del ensayo (node dist/main.js, NODE_ENV=production, helmet y parsers de
// main.ts), sin teléfono. Usa sesiones Auth V2 reales ligadas a un registro de
// cliente, como la app. Imprime sólo códigos HTTP y comprobaciones sí/no:
// ningún token, contraseña, id ni hash.
//   node api_preflight.cjs <url-api>   (F03_* de secrets.sh en el entorno)
//   node api_preflight.cjs <url-api> --expect-closed
//       API arrancada con NODE_ENV=production y SIN BACKUP_PRODUCTION_ADMISSION:
//       los respaldos deben responder 503 aunque la sesión sea válida.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const api = process.argv[2];
const results = [];
const check = (label, ok) => {
  results.push(ok);
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label}`);
};

async function call(method, route, { token, json, body, headers = {} } = {}) {
  const init = { method, headers: { ...headers }, redirect: 'manual' };
  if (token) init.headers.Authorization = `Bearer ${token}`;
  if (json !== undefined) {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(json);
  } else if (body !== undefined) {
    init.body = body;
  }
  const response = await fetch(`${api}${route}`, init);
  const bytes = Buffer.from(await response.arrayBuffer());
  let parsed = null;
  try {
    parsed = JSON.parse(bytes.toString('utf8'));
  } catch {
    // binario
  }
  return { status: response.status, headers: response.headers, bytes, json: parsed };
}

/** Sesión móvil: login V2 + registro de cliente + sesión ligada. */
async function mobileSession(email, password) {
  const login = await call('POST', '/api/v1/auth/v2/login', {
    json: { email, password, refreshTransport: 'BODY' },
  });
  if (login.status !== 200) throw new Error(`login HTTP ${login.status}`);
  const token = login.json.accessToken;
  const reg = await call('POST', '/api/v1/auth/clients', {
    token,
    json: { clientId: crypto.randomUUID() },
  });
  const bind = await call('POST', '/api/v1/auth/v2/session/client', {
    token,
    json: { registrationId: reg.json.registrationId },
  });
  if (bind.status !== 201 && bind.status !== 200) throw new Error(`bind HTTP ${bind.status}`);
  return token;
}

const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const upload = (token, bytes, digest = sha(bytes)) =>
  call('POST', '/api/v1/me/backups', {
    token,
    body: bytes,
    headers: {
      'Content-Type': 'application/octet-stream',
      'X-Content-SHA256': digest,
      'X-Backup-Format-Version': '1',
      'X-Backup-Schema-Version': '9',
    },
  });

async function main() {
  const env = process.env;
  for (const name of ['F03_FARMER_D_EMAIL', 'F03_FARMER_D_PASSWORD', 'F03_FARMER_E2_EMAIL',
    'F03_FARMER_E2_PASSWORD', 'F03_ADMIN_EMAIL', 'F03_ADMIN_PASSWORD', 'BACKUP_STORAGE_DIR']) {
    if (!env[name] && name !== 'BACKUP_STORAGE_DIR') throw new Error(`falta ${name} en el entorno (export tras source config.sh)`);
  }
  const owner = await mobileSession(env.F03_FARMER_D_EMAIL, env.F03_FARMER_D_PASSWORD);
  if (process.argv[3] === '--expect-closed') {
    const list = await call('GET', '/api/v1/me/backups', { token: owner });
    const put = await upload(owner, crypto.randomBytes(1024));
    check(
      `producción sin admisión: lista HTTP ${list.status}, subida HTTP ${put.status}`,
      list.status === 503 && put.status === 503 &&
        list.json?.errorCode === 'BACKUP_STORAGE_UNAVAILABLE',
    );
    const failed = results.filter((ok) => !ok).length;
    console.log(failed === 0 ? 'Producción cerrada: PASS' : 'Producción cerrada: FAIL');
    process.exitCode = failed === 0 ? 0 : 1;
    return;
  }
  const other = await mobileSession(env.F03_FARMER_E2_EMAIL, env.F03_FARMER_E2_PASSWORD);
  const admin = await mobileSession(env.F03_ADMIN_EMAIL, env.F03_ADMIN_PASSWORD);

  const initial = await call('GET', '/api/v1/me/backups', { token: owner });
  check(`lista inicial del titular: HTTP ${initial.status}`, initial.status === 200);
  const before = initial.json.backups.length;

  const bytes = crypto.randomBytes(256 * 1024);
  const created = await upload(owner, bytes);
  check(`subida: HTTP ${created.status}, SHA-256 confirmado`, created.status === 201 && created.json.sha256 === sha(bytes));
  const id = created.json.id;

  const listed = await call('GET', '/api/v1/me/backups', { token: owner });
  check('la copia aparece en la lista del titular', listed.json.backups.length === before + 1);

  const served = await call('GET', `/api/v1/me/backups/${id}/content`, { token: owner });
  check(
    `descarga: HTTP ${served.status}, bytes y cabecera SHA-256 iguales`,
    served.status === 200 && sha(served.bytes) === sha(bytes) && served.headers.get('x-content-sha256') === sha(bytes),
  );

  const foreign = await call('GET', `/api/v1/me/backups/${id}/content`, { token: other });
  const missing = await call('GET', `/api/v1/me/backups/${crypto.randomUUID()}/content`, { token: owner });
  check(
    `otro agricultor: HTTP ${foreign.status}, igual que una copia inexistente`,
    foreign.status === 404 && foreign.bytes.equals(missing.bytes),
  );
  const otherList = await call('GET', '/api/v1/me/backups', { token: other });
  check('otro agricultor no ve la copia en su lista', !otherList.json.backups.some((b) => b.id === id));

  const adminList = await call('GET', '/api/v1/me/backups', { token: admin });
  check(`Administrador: HTTP ${adminList.status}`, adminList.status === 403);

  // main.ts: ningún parser compartido lee el cuerpo de un respaldo.
  const marker = `F08-PARSER-${crypto.randomUUID()}`;
  for (const type of ['application/json', 'application/x-www-form-urlencoded']) {
    const parsed = await call('POST', '/api/v1/me/backups', {
      token: owner,
      body: `{"x":"${marker}`,
      headers: { 'Content-Type': type },
    });
    check(
      `cuerpo ${type}: HTTP ${parsed.status}, 415 cerrado sin eco`,
      parsed.status === 415 &&
        parsed.bytes.toString('utf8') === JSON.stringify({ errorCode: 'UNSUPPORTED_MEDIA_TYPE' }),
    );
  }

  const mismatch = await upload(owner, crypto.randomBytes(1024), 'a'.repeat(64));
  check(`SHA-256 incorrecto: HTTP ${mismatch.status}`, mismatch.status === 422);

  const removed = await call('DELETE', `/api/v1/me/backups/${id}`, { token: owner });
  const gone = await call('GET', `/api/v1/me/backups/${id}/content`, { token: owner });
  check(`eliminación: HTTP ${removed.status}; después HTTP ${gone.status}`, removed.status === 204 && gone.status === 404);

  const storage = env.BACKUP_STORAGE_DIR;
  const objects = fs.readdirSync(path.join(storage, 'objects'));
  const staging = fs.readdirSync(path.join(storage, 'staging'));
  const after = await call('GET', '/api/v1/me/backups', { token: owner });
  check(
    `almacenamiento: ${objects.length} objeto(s) para ${after.json.backups.length} copia(s) disponibles; staging vacío`,
    objects.length === after.json.backups.length && staging.length === 0,
  );

  const failed = results.filter((ok) => !ok).length;
  console.log(failed === 0 ? 'Comprobación previa: todo PASS' : `Comprobación previa: ${failed} FAIL`);
  process.exitCode = failed === 0 ? 0 : 1;
}

main().catch((error) => {
  console.error(`api_preflight: ${error.message}`);
  process.exitCode = 1;
});
