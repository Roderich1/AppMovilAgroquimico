// F06 (D4): emite por stdout el SQL que rota las contraseñas de TODOS los
// usuarios de una base desechable. Las cuentas de la prueba reciben la de su
// variable de entorno; el resto, una aleatoria que no se conserva. Se usa sólo
// en tubería hacia `docker exec -i ... psql` (nunca a un archivo ni a un log).
// Uso: node rotate_passwords.cjs EMAIL=VARIABLE [...] | docker exec -i <pg> psql ...
const path = require('node:path');
const crypto = require('node:crypto');

const bcrypt = require(path.join(process.env.F06_BE_DIR, 'node_modules', 'bcrypt'));

async function main() {
  const pairs = process.argv.slice(2).map((arg) => arg.split('='));
  const quote = (value) => `'${value.replaceAll("'", "''")}'`;
  const statements = ['BEGIN;'];
  for (const [email, variable] of pairs) {
    const password = process.env[variable];
    if (!email || !password) throw new Error(`Falta ${variable}`);
    const hash = await bcrypt.hash(password, 12);
    statements.push(`UPDATE "User" SET "passwordHash"=${quote(hash)} WHERE email=${quote(email)};`);
  }
  const others = await bcrypt.hash(crypto.randomBytes(24).toString('base64url'), 12);
  statements.push(
    `UPDATE "User" SET "passwordHash"=${quote(others)} WHERE email NOT IN (${pairs.map(([e]) => quote(e)).join(',')});`,
    // Termina con error si alguna cuenta de la prueba no existe.
    `DO $$ BEGIN IF (SELECT count(*) FROM "User" WHERE email IN (${pairs.map(([e]) => quote(e)).join(',')})) <> ${pairs.length} THEN RAISE EXCEPTION 'faltan cuentas de la prueba'; END IF; END $$;`,
    'COMMIT;',
  );
  process.stdout.write(`${statements.join('\n')}\n`);
}

main().catch((error) => {
  console.error(`rotate_passwords: ${error.message}`);
  process.exit(1);
});
