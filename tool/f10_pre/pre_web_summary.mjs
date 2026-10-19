// Preflight DS-UX (sesión A, 2026-10-18): resumen colectivo de «Verano Demo» en la Web, como ADMINISTRADOR
// sintético con funciones de Directiva, contrastado con la API. Sólo lectura. No imprime secretos.
// Entorno: WEB_URL, API_URL, EMAIL, PASSWORD (credential.sh run), SHOT (ruta de la captura), PUPPETEER (ruta del módulo).
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const puppeteer = require(process.env.PUPPETEER);
const { WEB_URL, API_URL, EMAIL, PASSWORD, SHOT } = process.env;
const browser = await puppeteer.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--window-size=1366,768'] });
const page = await browser.newPage();
await page.setViewport({ width: 1366, height: 768 });
const rowText = (el) => el.innerText.replace(/\s+/g, ' ').trim();
try {
  await page.goto(`${WEB_URL}/login`, { waitUntil: 'networkidle0' });
  await page.type('#email', EMAIL);
  await page.type('#password', PASSWORD);
  await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle0' }), page.click('button[type="submit"]')]);
  await page.waitForFunction(() => !['/', '/login'].includes(location.pathname), { timeout: 15000 });
  await page.goto(`${WEB_URL}/colectivo/resumen`, { waitUntil: 'networkidle0' });
  const name = 'Verano Demo';
  await page.waitForFunction((w) => [...document.querySelectorAll('#campaign-picker option')].some((o) => o.textContent.startsWith(w)), { timeout: 15000 }, name);
  const value = await page.$$eval('#campaign-picker option', (o, w) => o.find((x) => x.textContent.startsWith(w))?.value, name);
  await page.select('#campaign-picker', value);
  await page.waitForSelector('[data-testid="cell-DECLARED_NEED-Glifosato Demo-ML"]', { timeout: 15000 });
  const cell = await page.$eval('[data-testid="cell-DECLARED_NEED-Glifosato Demo-ML"]', rowText);
  const coverage = await page.$eval('[data-testid="coverage"]', rowText).catch(() => null);
  const mode = await page.$$eval('body', (b) => (b[0].innerText.match(/[^\n]*(provisional|sintétic|no aprobad)[^\n]*/i) || [''])[0].trim());
  await page.screenshot({ path: SHOT, fullPage: true });
  console.log(`${new Date().toISOString()} WEB celda Glifosato Demo: ${cell}`);
  console.log(`${new Date().toISOString()} WEB cobertura: ${coverage}`);
  console.log(`${new Date().toISOString()} WEB aviso de modo: ${mode}`);
  console.log(`CHECK celda 60 L con 3: ${/60\s*L/.test(cell) && /\b3\b/.test(cell)}`);
  console.log(`CHECK cobertura 3 de 12: ${/3 de 12/.test(coverage || '')}`);
  for (const button of await page.$$('xpath/.//button[contains(., "Cerrar sesión")]')) { if (await button.boundingBox()) { await button.click(); break; } }
} finally {
  await browser.close();
}
