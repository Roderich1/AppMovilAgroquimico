// F03-RES-01 (#71) y E2E de D3: proxy local transparente entre el túnel y el Backend.
// Registra SOLO hora, método, ruta (UUID enmascarados) y estado HTTP. No registra
// cabeceras, cuerpos ni consultas. Uso: node observer.cjs <puerto-escucha> <puerto-api> <archivo>
//
// Fallo controlado (E2E de D3 y #18 en F10): si existe <archivo>.fault, la PRÓXIMA
// petición POST /api/v1/sync/v1/push consume su primera línea (una por petición; las
// demás quedan para las siguientes):
//   drop-push-response  se reenvía a Central y se lee su respuesta completa (el
//                       commit ya está confirmado), pero no se entrega: la conexión
//                       queda retenida hasta que el cliente la abandona.
//   hold-push-request   no se reenvía: Central nunca la recibe. Se retiene hasta que
//                       el cliente la abandona.
//   (en ambos casos la conexión se cierra sin respuesta a los 30 s como máximo)
//
// Respuesta inyectada (#18, F10). Mide la REACCIÓN DEL CLIENTE, no la decisión de
// Central. El cuerpo de Central se modifica sólo en memoria y nunca se registra:
//   ack-incomplete      se reenvía; 200 con el ACK de Central sin `serverAcceptedAt`
//   ack-contradictory   se reenvía; 200 con el ACK de Central y otra `disposition`
//   ack-other-operation se reenvía; 200 con el ACK de Central para otro operationId
//   status-500-after    se reenvía (el commit puede haberse confirmado); 500 genérico
//   status-500-before   no se reenvía (Central nunca la recibe); 500 genérico
const http = require('node:http');
const fs = require('node:fs');
const crypto = require('node:crypto');

const [listenPort, apiPort, logFile] = process.argv.slice(2);
const faultFile = `${logFile}.fault`;
const pushPath = '/api/v1/sync/v1/push';
const uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const record = (line) => fs.appendFileSync(logFile, `${new Date().toISOString()} ${line}\n`);

const WITHHOLD = new Set(['drop-push-response', 'hold-push-request']);
// Modo → transformación del ACK de Central (null: no se reenvía).
const INJECT = {
  'ack-incomplete': (ack) => {
    delete ack.serverAcceptedAt;
    return ack;
  },
  'ack-contradictory': (ack) => {
    ack.disposition = ack.disposition === 'RETIRE_FROM_OUTBOX' ? 'KEEP_FOR_RETRY' : 'RETIRE_FROM_OUTBOX';
    return ack;
  },
  'ack-other-operation': (ack) => {
    ack.operationId = crypto.randomUUID();
    return ack;
  },
  'status-500-after': 'status-500',
  'status-500-before': null,
};
// Cuerpo por defecto de NestJS para un error no controlado.
const GENERIC_500 = JSON.stringify({ statusCode: 500, message: 'Internal server error' });

function takeFault(method, path) {
  if (method !== 'POST' || path !== pushPath) return null;
  let lines;
  try {
    lines = fs.readFileSync(faultFile, 'utf8').split('\n').map((line) => line.trim()).filter(Boolean);
  } catch {
    return null;
  }
  const [mode, ...rest] = lines;
  if (rest.length > 0) fs.writeFileSync(faultFile, `${rest.join('\n')}\n`);
  else fs.rmSync(faultFile, { force: true });
  return WITHHOLD.has(mode) || mode in INJECT ? mode : null;
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

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

const label = (mode) => `INYECTADA_${mode.toUpperCase().replaceAll('-', '_')}`;

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
    if (fault === 'status-500-before') {
      req.resume();
      req.on('end', () => {
        record(`POST ${path} - ${label(fault)}_SIN_REENVIAR 500`);
        send(res, 500, GENERIC_500);
      });
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
        if (fault !== null) {
          const chunks = [];
          answer.on('data', (chunk) => chunks.push(chunk));
          answer.on('end', () => {
            const transform = INJECT[fault];
            if (transform === 'status-500') {
              record(`${req.method} ${path} ${answer.statusCode} ${label(fault)} 500`);
              send(res, 500, GENERIC_500);
              return;
            }
            let ack = null;
            try {
              ack = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            } catch {
              // se entrega tal cual: no era JSON
            }
            if (answer.statusCode !== 200 || ack === null || typeof ack !== 'object') {
              record(`${req.method} ${path} ${answer.statusCode} ${label(fault)}_NO_APLICADA`);
              res.writeHead(answer.statusCode ?? 502, answer.headers);
              res.end(Buffer.concat(chunks));
              return;
            }
            record(`${req.method} ${path} ${answer.statusCode} ${label(fault)} 200`);
            send(res, 200, JSON.stringify(transform(ack)));
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
