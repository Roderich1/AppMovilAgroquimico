// F03-RES-01 (#71): proxy local transparente entre el túnel y el Backend.
// Registra SOLO hora, método, ruta (UUID enmascarados) y estado HTTP. No registra
// cabeceras, cuerpos ni consultas. Uso: node observer.cjs <puerto-escucha> <puerto-api> <archivo>
const http = require('node:http');
const fs = require('node:fs');

const [listenPort, apiPort, logFile] = process.argv.slice(2);
const uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

http
  .createServer((req, res) => {
    const path = (req.url ?? '').split('?')[0].replace(uuid, '{id}');
    const upstream = http.request(
      { host: '127.0.0.1', port: Number(apiPort), method: req.method, path: req.url, headers: req.headers },
      (answer) => {
        fs.appendFileSync(logFile, `${new Date().toISOString()} ${req.method} ${path} ${answer.statusCode}\n`);
        res.writeHead(answer.statusCode ?? 502, answer.headers);
        answer.pipe(res);
      },
    );
    upstream.on('error', () => {
      fs.appendFileSync(logFile, `${new Date().toISOString()} ${req.method} ${path} 502\n`);
      res.writeHead(502).end();
    });
    req.pipe(upstream);
  })
  .listen(Number(listenPort), '127.0.0.1');
