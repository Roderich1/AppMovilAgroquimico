# EVOLUTION-3 — Visión y alcance de operación por voz

## Estado

`APPROVED` para documentación e implementación incremental. La aprobación comprende
`EVO-009`, `EVO-010`, `EVO-017`, `EVO-018` y `EVO-019`. `EVO-020` queda `DEFERRED`.

## Problema

Los usuarios objetivo abandonan flujos que perciben como largos o difíciles de aprender. La
voz debe reducir el tecleo sin reducir exactitud, control ni trazabilidad. No se pretende crear
un asistente autónomo: se pretende preparar rápidamente el mismo borrador que hoy se completa
manualmente y someterlo a las mismas reglas de dominio.

## Resultado de esta evolución

El usuario toca un micrófono visible, habla de forma continua y la app:

1. transcribe mientras escucha;
2. detecta una única intención soportada;
3. extrae y resuelve datos contra catálogos locales;
4. actualiza un borrador tipado y editable;
5. muestra faltantes, ambigüedades, cálculos y efectos previstos;
6. permite seguir hablando o editar cualquier campo manualmente;
7. sólo ejecuta tras una confirmación táctil explícita.

## Capacidades aprobadas

| Orden | ID | Capacidad | Efecto antes de confirmar |
|---:|---|---|---|
| 1 | `EVO-009` | Captura, transcripción y sesión editable | Ninguna escritura de negocio |
| 2 | `EVO-010` | Intención, entidades, resolución y borrador tipado | Ninguna escritura de negocio |
| 3 | `EVO-017` | Borrador de compra por voz | Puede proponer productos nuevos |
| 4 | `EVO-018` | Borrador para aplicar una planificación | Calcula diferencias y stock previsto |
| 5 | `EVO-019` | Borrador de pago de cuenta | Calcula saldo antes/después |

Las consultas por voz (`EVO-020`) están diseñadas como evolución posterior de sólo lectura.

## Principios de experiencia

- **Entrada híbrida:** voz y edición manual operan sobre el mismo borrador.
- **Conversación acumulativa:** una frase posterior completa o corrige la sesión sin reiniciarla.
- **Estado visible:** escuchando, procesando, incompleto, ambiguo, listo, confirmando o error.
- **Una intención por borrador:** si se detectan dos operaciones, se pide separar; nunca se
  ejecutan silenciosamente como lote.
- **Confirmación específica:** el botón dice, por ejemplo, `Registrar compra`, no `Aceptar`.
- **Sin manos libres permanente:** no hay escucha siempre activa ni palabra de activación.
- **Salida segura:** descartar no deja efectos y volver atrás con cambios pide confirmación.

## Ejemplos objetivo

### Compra

> “Quiero registrar compra: cincuenta litros de Bellator a ciento ochenta y seis bolivianos el
> litro, cincuenta litros de Germispa a ciento ochenta y uno...”

El proveedor, campaña, propietario, moneda u otro dato faltante puede añadirse hablando o
seleccionarse manualmente. Todo el borrador es editable.

### Aplicación planificada

> “Quiero que apliques la planificación para el chaco Limoncitos. De Bellator en realidad
> usamos diez litros.”

Sólo se consideran planes pendientes de la campaña activa y del chaco resuelto.

### Pago

> “Registra un pago para José Luis de dos mil bolivianos.”

Si la persona es ambigua o el pago excede la deuda, el borrador queda bloqueado hasta una
decisión explícita.

## No incluido

- Confirmar o cancelar una escritura sólo con voz.
- Transferencias, reversiones, cierre/reapertura de campaña o borrado.
- Consultas libres o respuestas habladas en esta etapa.
- SQL generado, acceso del motor de voz a SQLite o modificación de FIFO.
- Cloud, sincronización, autenticación, telemetría o almacenamiento remoto.
- Diagnóstico o consejo agronómico producido por IA.

## Éxito de producto

- El usuario puede completar los tres borradores con menos teclado.
- Ninguna escritura ocurre antes de la confirmación táctil.
- Toda ambigüedad crítica se muestra y bloquea.
- La edición manual siempre puede terminar el flujo si la voz falla.
- El tiempo, exactitud, memoria y comportamiento offline se miden con un corpus real y en
  dispositivos representativos antes de declarar la evolución `VERIFIED`.

