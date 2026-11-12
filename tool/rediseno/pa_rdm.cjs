// Recorrido P-A del rediseño (2026-11-12) sobre el entorno AISLADO del rediseño (API 3370, base
// agro_demo del contenedor agro_rdm_pg). Datos SINTÉTICOS. Complementa tool/etapa3/pa_walk.cjs de
// la rama F (mismas personas): conceder el permiso, sustituir (y la autosustitución), crear y
// cerrar la segunda convocatoria, y leer el consolidado. Nunca imprime contraseñas ni tokens: son
// de un solo uso, en memoria, fijadas en la base aislada. No toca a agricultor15 (sesión del teléfono).
// Desde _wt/RDM-BE/Back:  node <ruta>/pa_rdm.cjs <orden> ...
//   grant <titular>                      ADMINISTRADOR concede «Sustituir responsable» a <titular>
//   create <nombre> <responsable>        convocatoria abierta (crea directiva, abre la responsable)
//   detail <nombre> [quien]              estado, responsable, versión, delegaciones suspendidas
//   sub <quien> <sucesora> <nombre>      sustituir (sucesora = quien → autosustitución)
//   close <nombre> <quien>               cerrar con confirmación
//   closing <nombre> <quien>             consolidado (resumen y huella)
// Entorno: DEMO_PG_ADMIN_URL, DEMO_API.
const { createRequire } = require("node:module");
const { randomBytes, randomUUID, createHash } = require("node:crypto");
const { resolve } = require("node:path");
const req = createRequire(resolve(process.cwd(), "package.json"));
const { PrismaClient } = req("@prisma/client");
const bcrypt = req("bcrypt");

const [cmd, ...args] = process.argv.slice(2);
const API = process.env.DEMO_API;
if (!API || !API.includes(":3370/")) throw new Error("DEMO_API debe ser la API aislada del rediseño (3370)");
const DB_URL = (() => { const u = new URL(process.env.DEMO_PG_ADMIN_URL); u.pathname = "/agro_demo"; return u.toString(); })();
if (!DB_URL.includes(":15436/")) throw new Error("DEMO_PG_ADMIN_URL debe ser el contenedor del rediseño (15436)");
const PEOPLE = {
  admin: "admin.demo@example.test",
  directiva: "directiva.demo@example.test",
  resp: "responsable.pa@example.test",
  suc: "sucesora.pa@example.test",
  admin2: "admin2.pa@example.test",
  resp2: "responsable2.pa@example.test",
};
const db = new PrismaClient({ datasources: { db: { url: DB_URL } } });
const call = async (method, path, { token, body } = {}) => {
  const r = await fetch(`${API}${path}`, {
    method,
    headers: { ...(body ? { "Content-Type": "application/json" } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const t = await r.text();
  return { status: r.status, json: (() => { try { return JSON.parse(t); } catch { return null; } })() };
};
const must = (r, ok, what) => { if (!ok.includes(r.status)) throw new Error(`${what}: HTTP ${r.status} ${r.json?.errorCode ?? r.json?.message ?? ""}`); return r.json; };
const tokens = {};
async function login(key) {
  if (tokens[key]) return tokens[key];
  const password = randomBytes(18).toString("base64url");
  await db.user.update({ where: { email: PEOPLE[key] }, data: { passwordHash: await bcrypt.hash(password, 10) } });
  tokens[key] = must(await call("POST", "/auth/login", { body: { email: PEOPLE[key], password } }), [200, 201], `login ${key}`).accessToken;
  return tokens[key];
}
const userId = async (key) => (await db.user.findUniqueOrThrow({ where: { email: PEOPLE[key] }, select: { id: true } })).id;
const callId = async (name) => (await db.jointPurchaseCall.findFirstOrThrow({ where: { name }, orderBy: { createdAt: "desc" } })).id;
const version = async (id) => (await db.jointPurchaseCall.findUniqueOrThrow({ where: { id }, select: { responsibleVersion: true } })).responsibleVersion;

(async () => {
  try {
    if (cmd === "grant") {
      const r = await call("POST", "/joint-purchase-substitution-permissions", {
        token: await login("admin"),
        body: { user_ref: await userId(args[0]), reason: "Recorrido P-A del rediseño (sintético)", confirmed: true },
      });
      console.log(JSON.stringify({ grant: args[0], status: r.status, error: r.json?.errorCode ?? null }));
    } else if (cmd === "create") {
      const [name, respKey] = args;
      const existing = await db.jointPurchaseCall.findFirst({ where: { name } });
      if (existing) { console.log(JSON.stringify({ exists: existing.id.slice(0, 8) })); return; }
      const admin = await db.user.findUniqueOrThrow({ where: { email: PEOPLE.admin } });
      const campaign = await db.agriculturalCampaign.findFirstOrThrow({ where: { tenantId: admin.tenantId, status: "ABIERTA" } });
      const busy = new Set((await db.jointPurchaseCallProduct.findMany({ where: { tenantId: admin.tenantId, openCampaignId: campaign.id }, select: { productId: true } })).map((b) => b.productId));
      const aliased = new Set((await db.productCanonicalAssociation.findMany({ where: { tenantId: admin.tenantId, validTo: null } })).filter((a) => a.productId !== a.canonicalProductId).map((a) => a.productId));
      const products = (await db.product.findMany({ where: { tenantId: admin.tenantId, isActive: true }, orderBy: { name: "asc" } }))
        .filter((p) => !busy.has(p.id) && !aliased.has(p.id) && ["L", "KG", "l", "kg", "Litros", "Kilogramos"].includes(p.unit)).slice(0, 1);
      if (!products.length) throw new Error("no hay productos libres");
      const created = must(await call("POST", "/joint-purchase-calls", {
        token: await login("directiva"),
        body: { campaign_id: campaign.id, name, deadline_at: new Date(Date.now() + 48 * 3600e3).toISOString(), responsible_user_id: await userId(respKey), products: products.map((p) => ({ product_ref: p.id })) },
      }), [201], "crear");
      must(await call("POST", `/joint-purchase-calls/${created.call_id}/open`, { token: await login(respKey), body: { confirmed: true } }), [200], "abrir");
      console.log(JSON.stringify({ created: created.call_id.slice(0, 8), products: products.map((p) => p.name) }));
    } else if (cmd === "detail") {
      const [name, who = "admin"] = args;
      const d = must(await call("GET", `/joint-purchase-calls/${await callId(name)}`, { token: await login(who) }), [200], "detalle");
      console.log(JSON.stringify({ status: d.status, responsible: d.responsible?.name, version: await version(d.call_id), closed_at: d.closed_at, participant_count: d.participant_count, delegations_suspended: d.delegations_suspended, can_view_participants: d.can_view_participants }));
    } else if (cmd === "sub") {
      const [who, successor, name] = args;
      const id = await callId(name);
      const before = await version(id);
      const body = { request_id: randomUUID(), expected_responsible_version: before, new_responsible_ref: await userId(successor), reason: "Recorrido P-A del rediseño (sintético)", confirmed: true };
      const r = await call("POST", `/joint-purchase-calls/${id}/responsible`, { token: await login(who), body });
      const after = await version(id);
      console.log(JSON.stringify({ by: who, successor, status: r.status, error: r.json?.errorCode ?? null, version_before: before, version_after: after, responsible_after: r.json?.responsible?.name ?? null, call_status: r.json?.status ?? null }));
    } else if (cmd === "close") {
      const [name, who] = args;
      const r = await call("POST", `/joint-purchase-calls/${await callId(name)}/close`, { token: await login(who), body: { confirmed: true } });
      console.log(JSON.stringify({ close: r.status, error: r.json?.errorCode ?? null, status: r.json?.status ?? null }));
    } else if (cmd === "closing") {
      const [name, who] = args;
      const r = await call("GET", `/joint-purchase-calls/${await callId(name)}/closing`, { token: await login(who) });
      const j = r.json ?? {};
      // Huella del consolidado: toda la respuesta salvo lo que depende de quién pregunta o de la hora.
      const volatile = new Set(["server_time", "can_view_participants", "contractVersion"]);
      const stable = JSON.stringify(Object.keys(j).sort().filter((k) => !volatile.has(k)).map((k) => [k, j[k]]));
      console.log(JSON.stringify({ status: r.status, error: j.errorCode ?? null, keys: Object.keys(j).sort(), huella: createHash("sha256").update(stable).digest("hex").slice(0, 16), huella_lineas: createHash("sha256").update(JSON.stringify(j.lines ?? null)).digest("hex").slice(0, 16), lineas: (j.lines ?? []).length, ocultas: j.hidden_participant_count, pendientes_autorizar: j.pending_authorization_count, cutoff_at: j.cutoff_at, closed_at: j.closed_at, participant_count: j.participant_count }));
    } else {
      throw new Error("orden desconocida");
    }
  } catch (e) {
    console.error(`ERROR ${e.message}`);
    process.exitCode = 1;
  } finally {
    await db.$disconnect();
  }
})();
