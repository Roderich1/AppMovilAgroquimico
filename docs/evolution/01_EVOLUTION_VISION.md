# Visión de evolución

## Objetivo

Evolucionar Agrocuentas significa aumentar su valor operativo sin degradar contabilidad,
trazabilidad, uso offline ni recuperación. Cada capacidad nace como un cambio aislado, con
contrato, pruebas y verificación proporcional al riesgo.

## Estados que no deben mezclarse

| Estado | Significado | Ejemplo vigente |
|---|---|---|
| Baseline | Punto histórico cerrado e inmutable | `v1.0.0-base-stable` |
| Evolución aprobada | Capacidad autorizada todavía no iniciada | `EVOLUTION-2` |
| Evolución condicionada | Autorizada pero dependiente de otra | `EVO-009`, después de EVOLUTION-2 |
| En desarrollo | Rama real con implementación iniciada | Ninguna al aprobar estos documentos |
| Producción | Artefacto distribuible y operable | Bloqueado por keystore |
| Futuro | Hipótesis sin compromiso | comandos de voz, nube, sincronización |

`READY FOR EVOLUTION` no significa `READY FOR STORE`. `APPROVED` no significa `IMPLEMENTED`,
y un merge no significa `VERIFIED` sin evidencia.

## Orden aprobado

1. `EVOLUTION-2`: modelos tipados de lectura y exportación PDF/CSV.
2. `EVOLUTION-3`: captura, transcripción y vista previa editable, sin ejecutar operaciones.

Compartir backup, diagnóstico exportable, comandos de voz, cloud y sincronización permanecen
diferidos salvo nueva decisión explícita.

## Resultado buscado

- Operaciones agrícolas rápidas y comprensibles en campo.
- Cuentas exactas y auditables.
- Datos preservados durante años y entre actualizaciones.
- Reportes producidos desde contratos tipados, no desde widgets ni SQL duplicado.
- Voz detrás de un puerto reemplazable, sin escritura de dominio en su primera versión.
- Arquitectura que crece por extracción oportunista, no por reescritura.

## Límites

La baseline es local, monodispositivo y Android es la plataforma verificada. Backend,
autenticación, nube, telemetría, IA y comandos de voz son subsistemas nuevos. La voz aprobada
en `EVO-009` sólo produce texto editable y no confirma compras, aplicaciones, transferencias,
pagos, inventario ni SQLite.

## Medida de éxito

Una evolución es exitosa cuando entrega valor observable, conserva invariantes, mantiene
backups compatibles, pasa CI y queda trazable desde requisito hasta evidencia.

