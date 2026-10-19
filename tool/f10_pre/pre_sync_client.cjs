// Preflight DS-UX (sesión A, 2026-10-18): cliente Sync v1 sintético por la API REAL, con el mismo
// recorrido que la app: POST /auth/v2/login → POST /auth/clients → POST /auth/v2/session/client →
// acción → POST /auth/clients/{id}/revoke (su propio registro) → POST /auth/v2/logout.
// No inserta nada en la base ni firma tokens. Nunca imprime contraseñas ni tokens.
// Entorno: ORIGIN, EMAIL, PASSWORD (sólo en el proceso, vía credential.sh run), ACTION=references|need,
//          OUT (references), CAMPAIGN_REF, PRODUCT_REF, QUANTITY_BASE (need; ML).
const { randomUUID } = require("crypto");
const fs = require("fs");
const env = process.env;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function call(method, path, token, body) {
  for (;;) {
    const res = await fetch(`${env.ORIGIN}/api/v1${path}`, {
      method,
      headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (res.status === 429) { console.log(`${new Date().toISOString()} ${method} ${path} 429 → espera 15 s`); await sleep(15000); continue; }
    const text = await res.text();
    let json = null; try { json = JSON.parse(text); } catch {}
    console.log(`${new Date().toISOString()} ${method} ${path.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, "{id}")} ${res.status}`);
    return { status: res.status, json, text };
  }
}
(async () => {
  const login = await call("POST", "/auth/v2/login", null, { email: env.EMAIL, password: env.PASSWORD, refreshTransport: "BODY" });
  if (login.status !== 200) throw new Error("login");
  const token = login.json.accessToken;
  const reg = await call("POST", "/auth/clients", token, { clientId: randomUUID() });
  if (reg.status !== 201) throw new Error("register");
  const registrationId = reg.json.registrationId;
  const bind = await call("POST", "/auth/v2/session/client", token, { registrationId });
  if (bind.status !== 201) throw new Error("bind");
  let result = {};
  if (env.ACTION === "references") {
    const r = await call("GET", "/sync/v1/references", token);
    if (r.status !== 200) throw new Error("references");
    fs.writeFileSync(env.OUT, r.text);
    result = { bytes: r.text.length };
  } else if (env.ACTION === "need") {
    const operationId = randomUUID();
    const r = await call("POST", "/sync/v1/push", token, {
      contractVersion: 1, projectionType: "DECLARED_NEED", operationId, action: "PUBLISH",
      causal: { predecessorOperationId: null, reconciliationReference: null },
      payload: { campaign_ref: env.CAMPAIGN_REF, product_ref: env.PRODUCT_REF, base_unit: "ML", quantity_base: env.QUANTITY_BASE },
    });
    result = { push: r.status, outcome: r.json && r.json.outcome, operation: operationId.slice(0, 8) };
    if (r.status !== 200 || r.json.outcome !== "APPLIED") { console.log(JSON.stringify(result)); throw new Error("push"); }
  }
  await call("POST", `/auth/clients/${registrationId}/revoke`, token, {});
  await call("POST", "/auth/v2/logout", null, { refreshToken: login.json.refreshToken });
  console.log(`RESULT ${JSON.stringify(result)}`);
})().catch((e) => { console.error(`ERROR ${e.message}`); process.exit(1); });
