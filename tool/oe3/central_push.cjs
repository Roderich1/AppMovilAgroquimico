// OE3 (2026-11-03): «otra instalación» del mismo Agricultor, con guion, contra la API
// REAL (127.0.0.1:3320): login BODY, registro de cliente nuevo, vínculo y UN envío
// sync v1. Sirve para C12, C13 y C33, donde la otra rama no la produce el teléfono.
// Imprime sólo outcome/code y prefijos de 8; nunca tokens, contraseñas ni correos.
//   node tool/oe3/central_push.cjs <Back/> <ids.json> <PUBLISH|SUPERSEDE|CANCEL>
//        <predecesor|-> <cantidad_ml|-> <campaña central> <producto central> [reconciliación|-] [operationId|-]
const { execFileSync } = require("node:child_process");
const { randomUUID, randomBytes } = require("node:crypto");
const path = require("node:path");

const [backDir, idsFile, action, predecessor, quantity, campaignName, productName, reconciliation, givenId] = process.argv.slice(2);
const ids = require(path.resolve(idsFile));
const bcrypt = require(path.resolve(backDir, "node_modules", "bcrypt"));
const API = "http://127.0.0.1:3320/api/v1";
const sql = (q) =>
  execFileSync("docker", ["exec", "-i", "agro_oe3_pg", "psql", "-U", "postgres", "-d", ids.database, "-At"], { input: q, encoding: "utf8" }).trim();
const orNull = (v) => (v === undefined || v === "-" ? null : v);

async function call(method, route, { token, body } = {}) {
  for (;;) {
    const r = await fetch(`${API}${route}`, {
      method,
      headers: { ...(body ? { "Content-Type": "application/json" } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (r.status === 429) {
      await new Promise((done) => setTimeout(done, 1000 * (Number(r.headers.get("retry-after")) || 30)));
      continue;
    }
    let json = null;
    try {
      json = await r.json();
    } catch {
      // sin JSON
    }
    return { status: r.status, json };
  }
}

(async () => {
  const password = randomBytes(18).toString("base64url");
  sql(`UPDATE "User" SET "passwordHash" = '${bcrypt.hashSync(password, 10)}' WHERE email = '${ids.farmerEmail}';`);
  const login = await call("POST", "/auth/v2/login", { body: { email: ids.farmerEmail, password, refreshTransport: "BODY" } });
  if (login.status !== 200) throw new Error(`login ${login.status}`);
  const token = login.json.accessToken;
  const reg = await call("POST", "/auth/clients", { token, body: { clientId: randomUUID() } });
  const bind = await call("POST", "/auth/v2/session/client", { token, body: { registrationId: reg.json.registrationId } });
  const campaign = sql(`SELECT id FROM "AgriculturalCampaign" WHERE "tenantId"='${ids.tenant}' AND name='${campaignName}';`);
  const product = sql(`SELECT id FROM "Product" WHERE "tenantId"='${ids.tenant}' AND name='${productName}';`);
  const envelope = {
    contractVersion: 1,
    operationId: orNull(givenId) ?? randomUUID(),
    projectionType: "DECLARED_NEED",
    action,
    causal: { predecessorOperationId: orNull(predecessor), reconciliationReference: orNull(reconciliation) },
    payload: { campaign_ref: campaign, product_ref: product, base_unit: "ML", ...(action === "CANCEL" ? {} : { quantity_base: quantity }) },
  };
  const push = await call("POST", "/sync/v1/push", { token, body: envelope });
  const ack = push.json ?? {};
  console.log(
    `${new Date().toISOString()} otra instalación (registro nuevo ${reg.status}, vínculo ${bind.status}): ${action} ` +
      `op=${envelope.operationId.slice(0, 8)} pred=${String(orNull(predecessor)).slice(0, 8)} → ${push.status} ` +
      `${ack.outcome ?? "-"}/${ack.code ?? ack.errorCode ?? "-"} reconciliación=${ack.reconciliationReference ? "sí" : "no"}`,
  );
  if (ack.reconciliationReference) console.log(`RECONCILIATION=${ack.reconciliationReference}`);
  const out = await call("POST", "/auth/v2/logout", { body: { refreshToken: login.json.refreshToken } });
  console.log(`logout ${out.status}`);
})().catch((error) => {
  console.error(`ERROR ${error.message}`);
  process.exit(1);
});
