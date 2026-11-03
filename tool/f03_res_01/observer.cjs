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
//
// Transporte controlado (OE3, 2026-11-03). Lo CONTROLADO es lo que llega a Central;
// la decisión de Central y la reacción del teléfono son REALES, salvo en `inject-*`:
//   mutate <t>          se reenvía el envío del teléfono alterado (t: reorder,
//                       quantity-plus-one, version-2, version-0, extra-envelope,
//                       extra-causal, extra-payload, unknown-predecessor,
//                       quantity-overflow, quantity-text:<v>, quantity-number,
//                       uppercase-id, duplicate-key, array, malformed-json, empty-body,
//                       text-content-type, oversize) y el teléfono recibe la
//                       respuesta real de Central a ese envío
//   concurrent <n>      se reenvían n copias simultáneas; el teléfono recibe la última
//   burst <n>           antes de reenviar, n POST sin credencial al mismo endpoint
//                       consumen el límite real de la aplicación
//   inject-ack <outcome> <code> <disposition>   no se reenvía; ACK SINTÉTICO de 7
//                       claves para el operationId del envío (respuesta INYECTADA)
//   inject-status <http> <errorCode>            no se reenvía; error SINTÉTICO del
//                       contrato (respuesta INYECTADA)
//   get-unknown         el próximo GET /sync/v1/operations/{id} se reenvía con otro
//                       id aleatorio (consulta real de una operación inexistente)
// En todos los POST de push se registra además `outcome`, `code` o `errorCode` de la
// respuesta y el prefijo de 8 del operationId: no son credenciales ni datos personales.
const http = require('node:http');
const fs = require('node:fs');
const crypto = require('node:crypto');

const [listenPort, apiPort, logFile] = process.argv.slice(2);
const faultFile = `${logFile}.fault`;
const pushPath = '/api/v1/sync/v1/push';
// Variante de ensayo F01–F08 (A, 2026-10-24): también retiene la respuesta de UN
// refresh (modo drop-refresh-response) para provocar una cuarentena real.
const refreshPath = '/api/v1/auth/v2/refresh';
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
  let lines;
  try {
    lines = fs.readFileSync(faultFile, 'utf8').split('\n').map((line) => line.trim()).filter(Boolean);
  } catch {
    return null;
  }
  const [mode, ...rest] = lines;
  // Los modos ampliados los consume sólo takeExtended, en su ruta.
  if (mode !== undefined && EXTENDED.test(mode)) return null;
  // OE3 (2026-11-03): `hold-path <ruta>` retiene sin reenviar la PRÓXIMA petición POST a
  // esa ruta (p. ej. el vínculo de la activación), para cortar la red del teléfono
  // mientras está en curso. Central nunca la recibe.
  if (mode !== undefined && mode.startsWith('hold-path ')) {
    if (method !== 'POST' || path !== mode.slice('hold-path '.length).trim()) return null;
    if (rest.length > 0) fs.writeFileSync(faultFile, `${rest.join('\n')}\n`);
    else fs.rmSync(faultFile, { force: true });
    return 'hold-push-request';
  }
  if (method !== 'POST' || (path !== pushPath && path !== refreshPath)) return null;
  // Cada modo sólo se consume en su ruta: el de refresh no toca un push ni al revés.
  if ((path === refreshPath) !== (mode === 'drop-refresh-response')) return null;
  if (rest.length > 0) fs.writeFileSync(faultFile, `${rest.join('\n')}\n`);
  else fs.rmSync(faultFile, { force: true });
  if (mode === 'drop-refresh-response') return 'drop-push-response';
  return WITHHOLD.has(mode) || mode in INJECT ? mode : null;
}

// Sin respuesta: se registra cuándo se va el cliente o el cierre a los 30 s.
function withhold(res, label, path = pushPath) {
  let done = false;
  const timer = setTimeout(() => {
    if (done) return;
    done = true;
    record(`POST ${path} - ${label}_CERRADA_A_LOS_30S`);
    res.destroy();
  }, 30000);
  res.on('close', () => {
    clearTimeout(timer);
    if (done) return;
    done = true;
    record(`POST ${path} - ${label}_CLIENTE_SE_FUE`);
  });
}

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

const label = (mode) => `INYECTADA_${mode.toUpperCase().replaceAll('-', '_')}`;

const EXTENDED = /^(mutate |concurrent |burst |inject-ack |inject-status |get-unknown$)/;
const operationsPath = /^\/api\/v1\/sync\/v1\/operations\/\{id\}$/;

function takeExtended(method, path) {
  let lines;
  try {
    lines = fs.readFileSync(faultFile, 'utf8').split('\n').map((line) => line.trim()).filter(Boolean);
  } catch {
    return null;
  }
  const [mode, ...rest] = lines;
  if (mode === undefined || !EXTENDED.test(mode)) return null;
  const applies =
    mode === 'get-unknown' ? method === 'GET' && operationsPath.test(path) : method === 'POST' && path === pushPath;
  if (!applies) return null;
  if (rest.length > 0) fs.writeFileSync(faultFile, `${rest.join('\n')}\n`);
  else fs.rmSync(faultFile, { force: true });
  return mode;
}

function reversedKeys(value) {
  if (Array.isArray(value)) return value.map(reversedKeys);
  if (value === null || typeof value !== 'object') return value;
  return Object.fromEntries(
    Object.keys(value)
      .reverse()
      .map((key) => [key, reversedKeys(value[key])]),
  );
}

// Devuelve { body, contentType } con el envío alterado. Nunca se registra el cuerpo.
function mutate(transform, raw) {
  const json = 'application/json';
  if (transform === 'empty-body') return { body: '', contentType: json };
  if (transform === 'malformed-json') return { body: raw.slice(0, -1), contentType: json };
  if (transform === 'text-content-type') return { body: raw, contentType: 'text/plain' };
  if (transform === 'array') return { body: `[${raw}]`, contentType: json };
  if (transform === 'duplicate-key') return { body: raw.replace('{', '{"action":"PUBLISH",'), contentType: json };
  const env = JSON.parse(raw);
  if (transform === 'reorder') return { body: JSON.stringify(reversedKeys(env), null, 3), contentType: json };
  if (transform === 'quantity-plus-one')
    env.payload.quantity_base = String(BigInt(env.payload.quantity_base ?? '0') + 1n);
  else if (transform === 'version-2') env.contractVersion = 2;
  else if (transform === 'version-0') env.contractVersion = 0;
  else if (transform === 'extra-envelope') env.tenantId = crypto.randomUUID();
  else if (transform === 'extra-causal') env.causal.clientId = crypto.randomUUID();
  else if (transform === 'extra-payload') env.payload.notes = 'campo privado de ensayo';
  else if (transform === 'unknown-predecessor') env.causal.predecessorOperationId = crypto.randomUUID();
  else if (transform === 'quantity-overflow') env.payload.quantity_base = '9223372036854775808';
  else if (transform.startsWith('quantity-text:'))
    env.payload.quantity_base = transform.slice('quantity-text:'.length).replaceAll('_', ' ');
  else if (transform === 'quantity-number') env.payload.quantity_base = Number(env.payload.quantity_base);
  else if (transform === 'uppercase-id') env.operationId = env.operationId.toUpperCase();
  else if (transform === 'oversize') env.payload.notes = 'x'.repeat(17 * 1024);
  else throw new Error(`transformación desconocida: ${transform}`);
  return { body: JSON.stringify(env), contentType: json };
}

function summary(status, text) {
  try {
    const body = JSON.parse(text);
    const op = typeof body.operationId === 'string' ? body.operationId.slice(0, 8) : '-';
    return `${status} ${body.outcome ?? '-'}/${body.code ?? body.errorCode ?? '-'} op=${op}`;
  } catch {
    return `${status} (sin JSON)`;
  }
}

function forward(req, body, contentType, path = req.url) {
  return new Promise((resolve) => {
    const headers = { ...req.headers, 'content-type': contentType, 'content-length': Buffer.byteLength(body) };
    const upstream = http.request({ host: '127.0.0.1', port: Number(apiPort), method: req.method, path, headers }, (answer) => {
      const chunks = [];
      answer.on('data', (chunk) => chunks.push(chunk));
      answer.on('end', () =>
        resolve({ status: answer.statusCode ?? 502, headers: answer.headers, text: Buffer.concat(chunks).toString('utf8') }),
      );
    });
    upstream.on('error', () => resolve({ status: 502, headers: {}, text: '' }));
    upstream.end(body);
  });
}

function deliver(res, answer) {
  const headers = { ...answer.headers };
  delete headers['content-length'];
  delete headers['transfer-encoding'];
  res.writeHead(answer.status, headers);
  res.end(answer.text);
}

async function handleExtended(req, res, path, mode) {
  const raw = await new Promise((resolve) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  });
  const tag = `CONTROLADO_${mode.split(' ')[0].toUpperCase().replaceAll('-', '_')}`;
  if (mode === 'get-unknown') {
    const answer = await forward(req, '', 'application/json', `/api/v1/sync/v1/operations/${crypto.randomUUID()}`);
    record(`GET ${path} ${summary(answer.status, answer.text)} ${tag} (id aleatorio)`);
    return deliver(res, answer);
  }
  const [kind, ...args] = mode.split(' ');
  if (kind === 'inject-ack') {
    const [outcome, code, disposition] = args;
    let operationId = null;
    try {
      operationId = JSON.parse(raw).operationId;
    } catch {
      // sin envelope legible
    }
    const ack = { contractVersion: 1, operationId, outcome, disposition, serverAcceptedAt: null, code, reconciliationReference: null };
    record(`POST ${path} - INYECTADA_ACK_SIN_REENVIAR 200 ${outcome}/${code} op=${String(operationId).slice(0, 8)}`);
    return send(res, 200, JSON.stringify(ack));
  }
  if (kind === 'inject-status') {
    const [status, errorCode] = args;
    record(`POST ${path} - INYECTADA_ESTADO_SIN_REENVIAR ${status}/${errorCode}`);
    res.setHeader('Cache-Control', 'no-store');
    return send(res, Number(status), JSON.stringify({ contractVersion: 1, operationId: null, errorCode, disposition: 'KEEP_FOR_RETRY' }));
  }
  if (kind === 'burst') {
    const codes = [];
    for (let i = 0; i < Number(args[0]); i++) {
      const anonymous = { headers: { host: req.headers.host }, method: 'POST' };
      codes.push((await forward(anonymous, '{}', 'application/json', pushPath)).status);
    }
    record(`POST ${path} - ${tag} ${codes.length} sin credencial: ${[...new Set(codes)].join('/')}`);
    const answer = await forward(req, raw, req.headers['content-type'] ?? 'application/json');
    record(`POST ${path} ${summary(answer.status, answer.text)} ${tag} retry-after=${answer.headers['retry-after'] ?? '-'}`);
    return deliver(res, answer);
  }
  if (kind === 'concurrent') {
    const answers = await Promise.all(
      Array.from({ length: Number(args[0]) }, () => forward(req, raw, req.headers['content-type'] ?? 'application/json')),
    );
    record(`POST ${path} ${tag} ${answers.map((a) => summary(a.status, a.text)).join(' | ')} (se entrega la última)`);
    return deliver(res, answers[answers.length - 1]);
  }
  let altered;
  try {
    altered = mutate(args.join(' '), raw);
  } catch (error) {
    record(`POST ${path} - ${tag} ERROR ${error.message}`);
    return send(res, 502, '{}');
  }
  const answer = await forward(req, altered.body, altered.contentType);
  record(`POST ${path} ${summary(answer.status, answer.text)} ${tag}:${args.join(' ')}`);
  return deliver(res, answer);
}

http
  .createServer((req, res) => {
    const path = (req.url ?? '').split('?')[0].replace(uuid, '{id}');
    const extended = takeExtended(req.method, path);
    if (extended !== null) {
      handleExtended(req, res, path, extended);
      return;
    }
    const fault = takeFault(req.method, path);
    if (fault === 'hold-push-request') {
      req.resume();
      record(`POST ${path} - RETENIDA_SIN_REENVIAR`);
      withhold(res, 'RETENIDA', path);
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
        if (req.method === 'POST' && path === pushPath) {
          const chunks = [];
          answer.on('data', (chunk) => chunks.push(chunk));
          answer.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8');
            record(`${req.method} ${path} ${summary(answer.statusCode, text)}`);
            deliver(res, { status: answer.statusCode ?? 502, headers: answer.headers, text });
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
