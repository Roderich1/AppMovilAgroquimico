// F03-RES-01 (#71): rota las contraseñas de TODOS los usuarios del seed.
// Las tres cuentas del ensayo reciben la contraseña de su variable de entorno;
// el resto, una aleatoria que no se conserva. No imprime contraseñas ni hashes.
// Uso: node rotate_passwords.cjs   (con DATABASE_URL y F03_* en el entorno)
const path = require('node:path');
const crypto = require('node:crypto');

const beDir = process.env.F03_BE_DIR;
const { PrismaClient } = require(path.join(beDir, 'node_modules', '@prisma/client'));
const bcrypt = require(path.join(beDir, 'node_modules', 'bcrypt'));

const assigned = new Map([
  [process.env.F03_ADMIN_EMAIL, process.env.F03_ADMIN_PASSWORD],
  [process.env.F03_FARMER_D_EMAIL, process.env.F03_FARMER_D_PASSWORD],
  [process.env.F03_FARMER_E2_EMAIL, process.env.F03_FARMER_E2_PASSWORD],
]);

async function main() {
  for (const [email, password] of assigned) {
    if (!email || !password) throw new Error('Faltan variables F03_* de cuentas');
  }
  const prisma = new PrismaClient();
  try {
    const users = await prisma.user.findMany({ select: { id: true, email: true } });
    let named = 0;
    for (const user of users) {
      const password = assigned.get(user.email) ?? crypto.randomBytes(24).toString('base64url');
      if (assigned.has(user.email)) named += 1;
      const passwordHash = await bcrypt.hash(password, 12);
      await prisma.user.update({ where: { id: user.id }, data: { passwordHash } });
    }
    if (named !== assigned.size) throw new Error(`Cuentas del ensayo encontradas: ${named}/${assigned.size}`);
    console.log(`contraseñas rotadas: ${users.length} usuarios (${named} del ensayo con contraseña efímera)`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(`rotate_passwords: ${error.message}`);
  process.exit(1);
});
