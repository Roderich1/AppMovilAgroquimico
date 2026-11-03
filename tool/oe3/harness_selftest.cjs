// OE3 (2026-11-03): autoprueba de los modos de transporte controlado del observador
// contra la API REAL, con un cliente scriptado (no el teléfono). Pasa por el
// observador (127.0.0.1:3321) y prepara cada modo en <run>/requests.log.fault.
// Sólo imprime lo que registra el observador (estado, outcome/code, prefijo de id).
//   node tool/oe3/harness_selftest.cjs <Back/> <ids.json> <run/>
const { execFileSync } = require("node:child_process");
const { randomUUID, randomBytes } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const [backDir, idsFile, runDir] = process.argv.slice(2);
const ids = require(path.resolve(idsFile));
const bcrypt = require(path.resolve(backDir, "node_modules", "bcrypt"));
const OBS = "http://127.0.0.1:3321/api/v1";
const logFile = path.join(runDir, "requests.log");
const sql = (q) =>
  execFileSync("docker", ["exec", "-i", "agro_oe3_pg", "psql", "-U", "postgres", "-d", ids.database, "-At"], { input: q, encoding: "utf8" }).trim();

async function call(method, route, { token, body } = {}) {
  for (;;) {
    const r = await fetch(`${OBS}${route}`, {
      method,
      headers: { ...(body ? { "Content-Type": "application/json" } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (r.status !== 429 || route === "/sync/v1/push") {
      let json = null;
      try {
        json = await r.json();
      } catch {
        // sin JSON
      }
      return { status: r.status, json };
    }
    await new Promise((done) => setTimeout(done, 1000 * (Number(r.headers.get("retry-after")) || 30)));
  }
}

async function login(email) {
  const password = randomBytes(18).toString("base64url");
  sql(`UPDATE "User" SET "passwordHash" = '${bcrypt.hashSync(password, 10)}' WHERE email = '${email}';`);
  const r = await call("POST", "/auth/v2/login", { body: { email, password, refreshTransport: "BODY" } });
  if (r.status !== 200) throw new Error(`login ${r.status}`);
  return { access: r.json.accessToken, refresh: r.json.refreshToken };
}

const lastLog = () => fs.readFileSync(logFile, "utf8").trim().split("\n").pop().replace(/^\S+ /, "");
async function probe(name, mode, token, envelope) {
  if (mode) fs.writeFileSync(`${logFile}.fault`, `${mode}\n`);
  await call("POST", "/sync/v1/push", { token, body: envelope });
  console.log(`${name.padEnd(34)} ${lastLog()}`);
}

(async () => {
  const s = await login(ids.farmerEmail);
  const reg = await call("POST", "/auth/clients", { token: s.access, body: { clientId: randomUUID() } });
  await call("POST", "/auth/v2/session/client", { token: s.access, body: { registrationId: reg.json.registrationId } });
  const campaign = sql(`SELECT id FROM "AgriculturalCampaign" WHERE "tenantId"='${ids.tenant}' AND status='ABIERTA' AND "isActive" LIMIT 1;`);
  const product = sql(`SELECT id FROM "Product" WHERE "tenantId"='${ids.tenant}' AND "isActive" AND unit='L' ORDER BY name DESC LIMIT 1;`);
  const env = (action = "PUBLISH", predecessor = null, quantity = "2000") => ({
    contractVersion: 1,
    operationId: randomUUID(),
    projectionType: "DECLARED_NEED",
    action,
    causal: { predecessorOperationId: predecessor, reconciliationReference: null },
    payload: { campaign_ref: campaign, product_ref: product, base_unit: "ML", ...(action === "CANCEL" ? {} : { quantity_base: quantity }) },
  });
  const head = await call("GET", "/sync/v1/references", { token: s.access });
  void head;
  const first = env();
  await probe("base (sin modo)", null, s.access, first);
  await probe("C07 mutate reorder (replay)", "mutate reorder", s.access, first);
  await probe("C08 mutate quantity-plus-one", "mutate quantity-plus-one", s.access, first);
  await probe("C25 mutate version-2", "mutate version-2", s.access, env("SUPERSEDE", first.operationId));
  await probe("C26 mutate extra-payload", "mutate extra-payload", s.access, env("SUPERSEDE", first.operationId));
  await probe("C27 mutate unknown-predecessor", "mutate unknown-predecessor", s.access, env("SUPERSEDE", first.operationId));
  await probe("C21 mutate quantity-overflow", "mutate quantity-overflow", s.access, env("SUPERSEDE", first.operationId));
  await probe("C37 mutate quantity-text:01", "mutate quantity-text:01", s.access, env("SUPERSEDE", first.operationId));
  await probe("C09 concurrent 3", "concurrent 3", s.access, env("SUPERSEDE", first.operationId));
  await probe("C28 inject-ack (INYECTADA)", "inject-ack RETRYABLE DEPENDENCY_PENDING KEEP_FOR_RETRY", s.access, env("SUPERSEDE", first.operationId));
  await probe("C29 inject-status 503 (INYECTADA)", "inject-status 503 TEMPORARILY_UNAVAILABLE", s.access, env("SUPERSEDE", first.operationId));
  await probe("C29 burst 25 (429 real)", "burst 25", s.access, env("SUPERSEDE", first.operationId));
  fs.writeFileSync(`${logFile}.fault`, "get-unknown\n");
  await new Promise((done) => setTimeout(done, 61000));
  await call("GET", `/sync/v1/operations/${first.operationId}`, { token: s.access });
  console.log(`${"C32 get-unknown".padEnd(34)} ${lastLog()}`);
  const out = await call("POST", "/auth/v2/logout", { body: { refreshToken: s.refresh } });
  console.log(`limpieza: logout ${out.status}; fallo pendiente: ${fs.existsSync(`${logFile}.fault`)}`);
})().catch((error) => {
  console.error(`ERROR ${error.message}`);
  process.exit(1);
});
