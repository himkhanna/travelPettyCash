// Minimal static server for the Flutter release web build, with SPA
// fallback (any non-file path -> index.html) so path-URL routes like
// /portal and /app/auth/uaepass/callback work. Dev convenience only.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, 'build', 'web');
const PORT = 5173;
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json',
  '.bin': 'application/octet-stream',
};

http.createServer((req, res) => {
  let urlPath = decodeURIComponent(req.url.split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';
  let file = path.join(ROOT, urlPath);
  if (!file.startsWith(ROOT)) { res.writeHead(403); res.end(); return; }

  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      // SPA fallback ONLY for route paths (no file extension). Missing
      // assets (with an extension) must 404, not get index.html — else
      // Flutter parses HTML as an asset and the app silently breaks.
      if (path.extname(urlPath)) { res.writeHead(404); res.end('not found'); return; }
      file = path.join(ROOT, 'index.html');
    }
    fs.readFile(file, (e, buf) => {
      if (e) { res.writeHead(404); res.end('not found'); return; }
      const ext = path.extname(file).toLowerCase();
      res.writeHead(200, {
        'Content-Type': MIME[ext] || 'application/octet-stream',
        'Cache-Control': 'no-cache',
      });
      res.end(buf);
    });
  });
}).listen(PORT, () => console.log('Serving ' + ROOT + ' on http://localhost:' + PORT));
