// F03-RES-01 (#71) y E2E de D3: proxy local transparente entre el túnel y el Backend.
// Registra SOLO hora, método, ruta (UUID enmascarados) y estado HTTP. No registra
// cabeceras, cuerpos ni consultas. Uso: node observer.cjs <puerto-escucha> <puerto-api> <archivo>
//
// Fallo controlado (E2E de D3): si existe <archivo>.fault, la PRÓXIMA petición
// POST /api/v1/sync/v1/push lo consume (una sola vez):
//   drop-push-response  se reenvía a Central y se lee su respuesta completa (el
//                       commit ya está confirmado), pero no se entrega: la conexión
//                       queda retenida hasta que el cliente la abandona.
//   hold-push-request   no se reenvía: Central nunca la recibe. Se retiene hasta que
//                       el cliente la abandona.
// En ambos casos la conexión se cierra sin respuesta a los 30 s como máximo.
const http = require('node:http');
const fs = require('node:fs');

const [listenPort, apiPort, logFile] = process.argv.slice(2);
const faultFile = `${logFile}.fault`;
const pushPath = '/api/v1/sync/v1/push';
const uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const record = (line) => fs.appendFileSync(logFile, `${new Date().toISOString()} ${line}\n`);

function takeFault(method, path) {
  if (method !== 'POST' || path !== pushPath) return null;
  let mode;
  try {
    mode = fs.readFileSync(faultFile, 'utf8').trim();
  } catch {
    return null;
  }
  fs.rmSync(faultFile, { force: true });
  return mode === 'drop-push-response' || mode === 'hold-push-request' ? mode : null;
}

// Sin respuesta: se registra cuándo se va el cliente o el cierre a los 30 s.
function withhold(res, label) {
  let done = false;
  const timer = setTimeout(() => {
    if (done) return;
    done = true;
    record(`POST ${pushPath} - ${label}_CERRADA_A_LOS_30S`);
    res.destroy();
  }, 30000);
  res.on('close', () => {
    clearTimeout(timer);
    if (done) return;
    done = true;
    record(`POST ${pushPath} - ${label}_CLIENTE_SE_FUE`);
  });
}

http
  .createServer((req, res) => {
    const path = (req.url ?? '').split('?')[0].replace(uuid, '{id}');
    const fault = takeFault(req.method, path);
    if (fault === 'hold-push-request') {
      req.resume();
      record(`POST ${path} - RETENIDA_SIN_REENVIAR`);
      withhold(res, 'RETENIDA');
      return;
    }
    const upstream = http.request(
      { host: '127.0.0.1', port: Number(apiPort), method: req.method, path: req.url, headers: req.headers },
      (answer) => {
        if (fault === 'drop-push-response') {
          answer.resume();
          answer.on('end', () => {
            record(`${req.method} ${path} ${answer.statusCode} RESPUESTA_RETENIDA`);
            withhold(res, 'RESPUESTA');
          });
          return;
        }
        record(`${req.method} ${path} ${answer.statusCode}`);
        res.writeHead(answer.statusCode ?? 502, answer.headers);
        answer.pipe(res);
      },
    );
    upstream.on('error', () => {
      record(`${req.method} ${path} 502`);
      res.writeHead(502).end();
    });
    req.pipe(upstream);
  })
  .listen(Number(listenPort), '127.0.0.1');
