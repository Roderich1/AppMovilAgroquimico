// #18 (F10), C40: revocación DENTRO de la ventana de decisión de Central.
//
// La API comprueba el contexto en el guard con lecturas sin bloqueo y lo
// revalida dentro de la transacción del push con `FOR SHARE OF s, m, u, t, r`
// (push-operation.use-case.ts, revalidateContext). Este script abre una
// transacción que bloquea con FOR UPDATE las sesiones ACTIVE de la cuenta y sus
// registros de cliente; el push del teléfono pasa el guard y espera en ese
// FOR SHARE. Cuando pg_stat_activity muestra esa espera, el script aplica la
// revocación en la misma transacción y confirma. La revalidación ve entonces
// el estado revocado.
//
// No cambia el código de Central ni añade ganchos: la técnica es un bloqueo de
// filas y una revocación por SQL equivalente a la del servicio (sesiones
// REVOKED, refresh tokens V2 revocados y, con `registration`, el registro).
// Imprime sólo horas, conteos y el resultado; ningún identificador.
//
//   node decision_window.cjs <email> <session|registration> [espera-máx-s]
//   (con F03_PG_CONTAINER y F03_PG_DB de config.sh en el entorno)
const { spawn, execFileSync } = require('node:child_process');

const [email, target, waitArg] = process.argv.slice(2);
const container = process.env.F03_PG_CONTAINER;
const database = process.env.F03_PG_DB;
const maxWaitMs = Number(waitArg ?? 180) * 1000;
if (!/^[a-z.]+@agro\.local$/.test(email ?? '') || !['session', 'registration'].includes(target) ||
    !container || !database) {
  console.error('uso: node decision_window.cjs <email-del-seed> <session|registration> [espera-máx-s]');
  process.exit(2);
}
const now = () => new Date().toISOString().slice(11, 23);
const log = (line) => console.log(`${now()} ${line}`);

const scope = `FROM "AuthSession" s
  JOIN "ClientRegistration" r ON r."id" = s."clientRegistrationId"
  JOIN "Member" m ON m."id" = s."memberId"
  JOIN "User" u ON u."id" = m."userId"
  WHERE u."email" = '${email}' AND s."status" = 'ACTIVE'`;

const psql = spawn('docker', ['exec', '-i', container, 'psql', '-U', 'postgres', '-d', database,
  '-v', 'ON_ERROR_STOP=1', '-At', '-q'], { stdio: ['pipe', 'pipe', 'pipe'] });
let buffer = '';
const waiters = [];
psql.stdout.on('data', (chunk) => {
  buffer += chunk.toString('utf8');
  let index;
  while ((index = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);
    const waiter = waiters.shift();
    if (waiter) waiter(line);
  }
});
psql.stderr.on('data', (chunk) => process.stderr.write(chunk));
const query = (sql) => new Promise((resolve) => {
  waiters.push(resolve);
  psql.stdin.write(`${sql}\n`);
});

// Pushes que esperan un bloqueo en la revalidación (no en otra sentencia).
function waiting() {
  const out = execFileSync('docker', ['exec', container, 'psql', '-U', 'postgres', '-d', database, '-At', '-c',
    "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' " +
    "AND query ILIKE '%FOR SHARE OF s, m, u, t, r%'"]).toString().trim();
  return Number(out);
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  // psql -q no imprime BEGIN: cada llamada termina con una consulta que devuelve
  // exactamente una fila, para leer la salida en orden.
  await query("BEGIN; SELECT 'begin';");
  const locked = await query(`SELECT count(*) FROM (SELECT 1 ${scope} FOR UPDATE OF s, r) x;`);
  // Las filas ya están bloqueadas por esta transacción: se guardan sus ids.
  await query(`CREATE TEMP TABLE w ON COMMIT DROP AS SELECT s."id" AS "sid", r."id" AS "rid" ${scope};
    SELECT 'w';`);
  if (Number(locked) === 0) {
    await query("ROLLBACK; SELECT 'rollback';");
    log('sin sesiones ACTIVE ligadas a un registro para esa cuenta: nada que bloquear');
    psql.stdin.end();
    process.exitCode = 1;
    return;
  }
  log(`VENTANA_PREPARADA: ${locked} sesión(es) ACTIVE y su registro bloqueados (FOR UPDATE). Provoque el push ahora.`);
  const deadline = Date.now() + maxWaitMs;
  let seen = 0;
  while (Date.now() < deadline) {
    seen = waiting();
    if (seen > 0) break;
    await sleep(200);
  }
  if (seen === 0) {
    await query("ROLLBACK; SELECT 'rollback';");
    log('SIN_PUSH_EN_LA_VENTANA: ningún push esperó la revalidación; no se revocó nada');
    psql.stdin.end();
    process.exitCode = 2;
    return;
  }
  log(`PUSH_EN_ESPERA: ${seen} push(es) pasaron el guard y esperan en FOR SHARE de la revalidación`);
  const count = async (sql) => query(`WITH x AS (${sql} RETURNING 1) SELECT count(*) FROM x;`);
  log(`sesiones revocadas en la transacción: ${await count(
    `UPDATE "AuthSession" SET "status" = 'REVOKED', "revokedAt" = now() WHERE "id" IN (SELECT "sid" FROM w)`)}`);
  log(`refresh tokens V2 revocados: ${await count(
    `UPDATE "RefreshToken" SET "revokedAt" = now() WHERE "sessionId" IN (SELECT "sid" FROM w)
     AND "contractVersion" = 2 AND "revokedAt" IS NULL`)}`);
  if (target === 'registration') {
    log(`registros de cliente revocados: ${await count(
      `UPDATE "ClientRegistration" SET "status" = 'REVOKED', "revokedAt" = now()
       WHERE "id" IN (SELECT "rid" FROM w) AND "status" = 'ACTIVE'`)}`);
  }
  await query("COMMIT; SELECT 'commit';");
  log('REVOCACION_CONFIRMADA (COMMIT) mientras el push esperaba');
  psql.stdin.end();
  const after = Date.now() + 20000;
  while (Date.now() < after && waiting() > 0) await sleep(200);
  log(`pushes aún en espera tras el commit: ${waiting()}`);
}

main().catch((error) => {
  console.error(`decision_window: ${error.message}`);
  psql.stdin.end();
  process.exitCode = 1;
});
