// #36 / GATE-F08 (F10): lo que cambió en main.ts entre el Backend del E2E
// (a45ab83) y el integrado (ba51c70/e027938). La guarda del cuerpo de respaldos
// pasó a registrarse DESPUÉS de helmet y CORS, así que su 415 debe llevar sus
// cabeceras, y un origen no permitido no las recibe. Complementa a
// tool/f08_bkp/api_preflight.cjs (que no se modifica). Imprime sólo códigos
// HTTP y comprobaciones sí/no: ningún token, contraseña ni id.
//   node api_headers_check.cjs <url-api> <origen-permitido>
//   (F03_FARMER_D_EMAIL/PASSWORD en el entorno: credential.sh run D ...)
const crypto = require('node:crypto');

const [api, allowed] = process.argv.slice(2);
const results = [];
const check = (label, ok) => {
  results.push(ok);
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label}`);
};

async function call(method, route, headers = {}, body) {
  const response = await fetch(`${api}${route}`, { method, headers, body, redirect: 'manual' });
  const bytes = Buffer.from(await response.arrayBuffer());
  return { status: response.status, headers: response.headers, text: bytes.toString('utf8') };
}

async function main() {
  const env = process.env;
  if (!api || !allowed || !env.F03_FARMER_D_EMAIL || !env.F03_FARMER_D_PASSWORD) {
    throw new Error('uso: credential.sh run D node api_headers_check.cjs <url-api> <origen-permitido>');
  }
  const login = await call('POST', '/api/v1/auth/v2/login', { 'Content-Type': 'application/json' },
    JSON.stringify({ email: env.F03_FARMER_D_EMAIL, password: env.F03_FARMER_D_PASSWORD, refreshTransport: 'BODY' }));
  if (login.status !== 200) throw new Error(`login HTTP ${login.status}`);
  const token = JSON.parse(login.text).accessToken;
  const reg = await call('POST', '/api/v1/auth/clients',
    { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    JSON.stringify({ clientId: crypto.randomUUID() }));
  const bind = await call('POST', '/api/v1/auth/v2/session/client',
    { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    JSON.stringify({ registrationId: JSON.parse(reg.text).registrationId }));
  if (bind.status !== 201 && bind.status !== 200) throw new Error(`bind HTTP ${bind.status}`);

  const marker = `F10-HDR-${crypto.randomUUID()}`;
  const guarded = (origin) => call('POST', '/api/v1/me/backups',
    { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Origin: origin }, `{"x":"${marker}"}`);

  const ok = await guarded(allowed);
  check(`415 de la guarda con origen permitido: HTTP ${ok.status}, cuerpo cerrado sin eco`,
    ok.status === 415 && ok.text === JSON.stringify({ errorCode: 'UNSUPPORTED_MEDIA_TYPE' }));
  check('ese 415 lleva Access-Control-Allow-Origin del origen permitido (CORS antes de la guarda)',
    ok.headers.get('access-control-allow-origin') === allowed);
  check('ese 415 lleva las cabeceras de helmet (X-Content-Type-Options: nosniff)',
    ok.headers.get('x-content-type-options') === 'nosniff');

  const foreign = await guarded('https://otro-origen.invalid');
  check(`origen no permitido: HTTP ${foreign.status} y sin Access-Control-Allow-Origin`,
    foreign.status === 415 && foreign.headers.get('access-control-allow-origin') === null);

  const preflight = await call('OPTIONS', '/api/v1/me/backups', {
    Origin: allowed,
    'Access-Control-Request-Method': 'POST',
    'Access-Control-Request-Headers': 'authorization,content-type,x-content-sha256',
  });
  check(`preflight CORS: HTTP ${preflight.status} con el origen permitido`,
    (preflight.status === 204 || preflight.status === 200) &&
      preflight.headers.get('access-control-allow-origin') === allowed);

  const logout = await call('POST', '/api/v1/auth/v2/logout', { 'Content-Type': 'application/json' },
    JSON.stringify({ refreshToken: JSON.parse(login.text).refreshToken }));
  console.log(`logout de la sesión de comprobación: HTTP ${logout.status}`);

  const failed = results.filter((passed) => !passed).length;
  console.log(failed === 0 ? 'Cabeceras de la guarda: todo PASS' : `Cabeceras de la guarda: ${failed} FAIL`);
  process.exitCode = failed === 0 ? 0 : 1;
}

main().catch((error) => {
  console.error(`api_headers_check: ${error.message}`);
  process.exitCode = 1;
});
