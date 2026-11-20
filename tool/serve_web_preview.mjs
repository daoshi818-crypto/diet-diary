// Serves only Flutter's compiled output, never the source tree or .env.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../build/web/', import.meta.url));
const port = Number(process.argv[2] || 4173);
const mime = { '.html':'text/html; charset=utf-8', '.js':'application/javascript',
  '.mjs':'application/javascript', '.json':'application/json', '.wasm':'application/wasm',
  '.png':'image/png', '.jpg':'image/jpeg', '.svg':'image/svg+xml', '.ttf':'font/ttf',
  '.woff2':'font/woff2', '.bin':'application/octet-stream' };
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const requested = decodeURIComponent(url.pathname);
    let path = resolve(root, `.${requested}`);
    if (path !== resolve(root) && !path.startsWith(resolve(root) + sep)) {
      res.writeHead(403).end(); return;
    }
    if ((await stat(path)).isDirectory()) path = resolve(path, 'index.html');
    const bytes = await readFile(path);
    res.writeHead(200, { 'Content-Type': mime[extname(path)] || 'application/octet-stream',
      'Cache-Control': 'no-store', 'X-Content-Type-Options':'nosniff' });
    res.end(req.method === 'HEAD' ? undefined : bytes);
  } catch { res.writeHead(404).end('Not found'); }
});
server.listen(port, '127.0.0.1', () => {
  console.log(`Official Flutter source preview: http://localhost:${port}/`);
});
