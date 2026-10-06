// Membungkus landing/page.html (format artifact: tanpa <html>/<head>) menjadi dokumen lengkap
// landing/index.html untuk Firebase Hosting. Dipanggil otomatis oleh predeploy hosting.
//   node tools/build-landing.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const src = new URL('../landing/page.html', import.meta.url);
const out = new URL('../landing/index.html', import.meta.url);

const page = readFileSync(src, 'utf8');
// <title>, meta, dan font link di awal page.html dipindah ke <head>.
const cut = page.indexOf('<style>');
const head = page.slice(0, cut).trim();
const body = page.slice(cut);
const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
${head}
<style>[hidden]{display:none!important}</style>
</head>
<body>
${body}
</body>
</html>
`;
writeFileSync(out, html);
console.log(`landing/index.html (${(html.length / 1024).toFixed(1)} KB)`);
