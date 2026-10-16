// Prints a demo Library guide (HTML, A4 pages) to PDF with Chromium, so the example PDF looks like a real one.
//   cd backend && node scripts/demo_pdf.js apps/common/demo_media/eat.html apps/common/demo_media/eat.pdf
// Needs Playwright (npm i -D playwright, or a global install). Only for refreshing the shipped demo file.
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const [, , src, out] = process.argv;
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('file://' + path.resolve(src));
  await page.evaluate(() => document.fonts.ready);
  await page.pdf({ path: out, format: 'A4', printBackground: true, preferCSSPageSize: true });
  await browser.close();
})();
