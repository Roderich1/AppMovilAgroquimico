// OE3 (2026-11-03): sesiones remanentes contra la API REAL del Central desechable
// (http://127.0.0.1:3320, sin túnel). Un cliente con guion reproduce las llamadas
// de la app (login BODY, auth/clients, session/client, me, refresh, push). Los
// tokens viven sólo en memoria; se imprimen códigos HTTP, estados y fechas, nunca
// tokens, contraseñas, correos ni ids completos.
//   node tool/oe3/sessions_check.cjs <Back/> <ids.json>
const { execFileSync } = require("node:child_process");
const { randomUUID, randomBytes } = require("node:crypto");
const path = require("node:path");

const [backDir, idsFile] = process.argv.slice(2);
const ids = require(path.resolve(idsFile));
const bcrypt = require(path.resolve(backDir, "node_modules", "bcrypt"));
const API = "http://127.0.0.1:3320/api/v1";

const sql = (query) =>
  execFileSync("docker", ["exec", "-i", "agro_oe3_pg", "psql", "-U", "postgres", "-d", ids.database, "-At", "-F", "|"], {
    input: query,
    encoding: "utf8",
  }).trim();
const short = (id) => (id ? String(id).slice(0, 8) : "-");
const log = (step, text) => console.log(`${new Date().toISOString()} ${step}: ${text}`);

async function call(method, route, { token, body } = {}) {
  for (;;) {
    const r = await callOnce(method, route, { token, body });
    if (r.status !== 429) return r;
    // Límites de la API (20/min y 5/min en login): se espera y se repite.
    await new Promise((done) => setTimeout(done, 1000 * (Number(r.retryAfter) || 30)));
  }
}

async function callOnce(method, route, { token, body } = {}) {
  const response = await fetch(`${API}${route}`, {
    method,
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try {
    json = await response.json();
  } catch {
    // sin cuerpo JSON
  }
  return { status: response.status, json, retryAfter: response.headers.get("retry-after") };
}

function oneTimePassword(email) {
  const password = randomBytes(18).toString("base64url");
  const hash = bcrypt.hashSync(password, 10);
  const updated = sql(`UPDATE "User" SET "passwordHash" = '${hash}' WHERE email = '${email}';`);
  if (updated !== "UPDATE 1") throw new Error("no se pudo asignar la contraseña");
  return password;
}

async function login(email) {
  const r = await call("POST", "/auth/v2/login", {
    body: { email, password: oneTimePassword(email), refreshTransport: "BODY" },
  });
  if (r.status !== 200) throw new Error(`login ${r.status}`);
  return { access: r.json.accessToken, refresh: r.json.refreshToken, sessionId: r.json.context.session.id };
}

const sessionRow = (id) =>
  sql(`SELECT status || ' vinculada=' || ("clientRegistrationId" IS NOT NULL) || ' expira=' || to_char("expiresAt", 'YYYY-MM-DD"T"HH24:MI"Z"') || ' creada=' || to_char("createdAt", 'YYYY-MM-DD"T"HH24:MI"Z"') FROM "AuthSession" WHERE id = '${id}';`);
const refreshRows = (id) =>
  sql(`SELECT 'tokens=' || count(*) || ' vigentes=' || count(*) FILTER (WHERE "revokedAt" IS NULL AND "consumedAt" IS NULL) FROM "RefreshToken" WHERE "sessionId" = '${id}';`);

async function refresh(state) {
  const r = await call("POST", "/auth/v2/refresh", { body: { refreshToken: state.refresh } });
  if (r.status === 200) {
    state.access = r.json.accessToken;
    state.refresh = r.json.refreshToken;
  }
  return r.status;
}

async function admin(route, body) {
  const a = await login(ids.adminEmail);
  const r = await call(route.method, route.path, { token: a.access, body });
  await call("POST", "/auth/v2/logout", { body: { refreshToken: a.refresh } });
  return r.status;
}

function envelope() {
  const campaign = sql(`SELECT id FROM "AgriculturalCampaign" WHERE "tenantId" = '${ids.tenant}' AND status = 'ABIERTA' AND "isActive" LIMIT 1;`);
  const product = sql(`SELECT id FROM "Product" WHERE "tenantId" = '${ids.tenant}' AND "isActive" AND unit = 'L' LIMIT 1;`);
  return {
    contractVersion: 1,
    operationId: randomUUID(),
    projectionType: "DECLARED_NEED",
    action: "PUBLISH",
    causal: { predecessorOperationId: null, reconciliationReference: null },
    payload: { campaign_ref: campaign, product_ref: product, base_unit: "ML", quantity_base: "1000" },
  };
}

(async () => {
  const email = ids.farmerEmail;
  const clientId = randomUUID();

  // 1. Instalación con sesión S1 vinculada.
  const s1 = await login(email);
  const reg = await call("POST", "/auth/clients", { token: s1.access, body: { clientId } });
  const registrationId = reg.json?.registrationId;
  const b1 = await call("POST", "/auth/v2/session/client", { token: s1.access, body: { registrationId } });
  log("1 S1", `login 200, clients ${reg.status}, bind ${b1.status}; S1 ${short(s1.sessionId)} ${sessionRow(s1.sessionId)}`);

  // 2. Reautenticación en la MISMA instalación (lo que hace la app): S2 sobre el mismo registro.
  const s2 = await login(email);
  const b2 = await call("POST", "/auth/v2/session/client", { token: s2.access, body: { registrationId } });
  log("2 S2", `login 200, bind ${b2.status} (mismo registro); sin logout de S1`);
  log("2 S1 tras reautenticar", `estado ${sessionRow(s1.sessionId)}; ${refreshRows(s1.sessionId)}`);
  log("2 S1 access anterior", `GET me ${(await call("GET", "/auth/v2/me", { token: s1.access })).status}`);
  const s1Pre = { ...s1 };
  log("2 S1 refresh anterior", `POST refresh ${await refresh(s1)}`);
  log("2 S1 push con el access rotado", `POST push ${(await call("POST", "/sync/v1/push", { token: s1.access, body: envelope() })).status}`);

  // 3. Desactivación de la cuenta.
  log("3 desactivar", `PATCH users/{id}/deactivate ${await admin({ method: "PATCH", path: `/users/${sql(`SELECT id FROM "User" WHERE email='${email}';`)}/deactivate` })}`);
  log("3 S2 access", `GET me ${(await call("GET", "/auth/v2/me", { token: s2.access })).status}`);
  log("3 S2 push", `POST push ${(await call("POST", "/sync/v1/push", { token: s2.access, body: envelope() })).status}`);
  const s2Pre = { ...s2 };
  log("3 S2 refresh", `POST refresh ${await refresh(s2)}`);
  log("3 S2 tras el 401", `estado ${sessionRow(s2.sessionId)}; ${refreshRows(s2.sessionId)}`);
  log("3 login durante la inactividad", `${(await call("POST", "/auth/v2/login", { body: { email, password: "x".repeat(12), refreshTransport: "BODY" } })).status} (contraseña cualquiera; el login real también se rechaza por inactividad)`);

  // 4. Reactivación: ¿revive la sesión anterior?
  log("4 reactivar", `PATCH users/{id} isActive=true ${await admin({ method: "PATCH", path: `/users/${sql(`SELECT id FROM "User" WHERE email='${email}';`)}` }, { isActive: true })}`);
  log("4 S2 access de antes", `GET me ${(await call("GET", "/auth/v2/me", { token: s2Pre.access })).status}`);
  log("4 S2 refresh de antes", `POST refresh ${await refresh(s2)}; estado ${sessionRow(s2.sessionId)}`);

  // 5. Sesión creada antes de un vínculo interrumpido: login + clients, sin bind.
  const s3 = await login(email);
  const reg3 = await call("POST", "/auth/clients", { token: s3.access, body: { clientId } });
  log("5 S3 sin vínculo", `clients ${reg3.status} (mismo clientId: mismo registro=${reg3.json?.registrationId === registrationId}); estado ${sessionRow(s3.sessionId)}`);
  log("5 S3 access", `GET me ${(await call("GET", "/auth/v2/me", { token: s3.access })).status}`);
  log("5 S3 push", `POST push ${(await call("POST", "/sync/v1/push", { token: s3.access, body: envelope() })).status}`);
  log("5 S3 references", `GET references ${(await call("GET", "/sync/v1/references", { token: s3.access })).status}`);
  log("5 S3 refresh", `POST refresh ${await refresh(s3)}; estado ${sessionRow(s3.sessionId)}`);
  log("5 TTL", "JWT_REFRESH_EXPIRES_IN=7d y JWT_EXPIRES_IN=15m en oe3_supervisor.sh");

  // Limpieza: cierre explícito de las sesiones abiertas por el guion.
  const codes = [];
  for (const s of [s1, s2, s3]) codes.push((await call("POST", "/auth/v2/logout", { body: { refreshToken: s.refresh } })).status);
  log("limpieza", `logout ${codes.join(",")}; S1 ${sessionRow(s1.sessionId)}; S2 ${sessionRow(s2.sessionId)}; S3 ${sessionRow(s3.sessionId)}`);
  void s1Pre;
})().catch((error) => {
  console.error(`ERROR ${error.message}`);
  process.exit(1);
});
