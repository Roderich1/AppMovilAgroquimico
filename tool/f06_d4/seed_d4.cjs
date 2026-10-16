// F06 (D4): catálogo central del dataset (docs/evidence/F06_DATASET.csv) sobre
// el seed del Backend. Belator y Bellator son la misma denominación escrita de
// dos formas: nacen separados; la Directiva los asocia durante la prueba.
// Abre «Campana Invierno 2026» (en el seed está PLANIFICADA) como segunda
// campaña. Sólo para bases desechables. Uso: DATABASE_URL=... node seed_d4.cjs
const path = require('node:path');

const { PrismaClient } = require(path.join(process.env.F06_BE_DIR, 'node_modules', '@prisma/client'));

const PRODUCTS = [
  ['Belator', 'Insecticida', 'L'],
  ['Bellator', 'Insecticida', 'L'],
  ['Glifosato F06', 'Herbicida', 'L'],
  ['Urea F06', 'Fertilizante', 'KG'],
  ['Mancozeb F06', 'Fungicida', 'KG'],
];

async function main() {
  const prisma = new PrismaClient();
  try {
    const tenant = await prisma.tenant.findUniqueOrThrow({ where: { slug: 'default' } });
    for (const [name, category, unit] of PRODUCTS) {
      await prisma.product.upsert({
        where: { tenantId_name: { tenantId: tenant.id, name } },
        update: { unit, isActive: true },
        create: { tenantId: tenant.id, name, commercialName: name, category, unit },
      });
    }
    const opened = await prisma.agriculturalCampaign.updateMany({
      where: { tenantId: tenant.id, name: 'Campana Invierno 2026' },
      data: { status: 'ABIERTA', isActive: true },
    });
    const open = await prisma.agriculturalCampaign.count({
      where: { tenantId: tenant.id, status: 'ABIERTA', isActive: true },
    });
    console.log(`catálogo F06: ${PRODUCTS.length} productos; campañas abiertas: ${open} (abierta ahora: ${opened.count})`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(`seed_d4: ${error.message}`);
  process.exit(1);
});
