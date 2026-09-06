# Visión de evolución

## Objetivo

Evolucionar Agrocuentas significa aumentar su valor operativo sin degradar contabilidad,
trazabilidad, uso offline ni recuperación. Cada capacidad nace como un cambio aislado, con
contrato, pruebas y verificación proporcional al riesgo.

## Estados que no deben mezclarse

| Estado | Significado | Ejemplo vigente |
|---|---|---|
| Baseline | Punto histórico cerrado e inmutable | `v1.0.0-base-stable` |
| Evolución aprobada | Capacidad autorizada todavía no iniciada | `EVOLUTION-3` |
| Evolución verificada | Capacidad implementada y cerrada con evidencia | `EVOLUTION-2` |
| En desarrollo | Rama real con implementación iniciada | Ninguna de EVOLUTION-3 al aprobar estos documentos |
| Producción | Artefacto distribuible y operable | Bloqueado por keystore |
| Futuro | Hipótesis sin compromiso | consultas por voz, nube, sincronización |

`READY FOR EVOLUTION` no significa `READY FOR STORE`. `APPROVED` no significa `IMPLEMENTED`,
y un merge no significa `VERIFIED` sin evidencia.

## Orden aprobado

1. `EVOLUTION-2`: modelos tipados de lectura y exportación PDF/CSV, integrada y verificada.
2. `EVOLUTION-3`: voz continua que prepara drafts editables para compra, aplicación de una
   planificación y pago; toda escritura requiere confirmación táctil.

Compartir backup, diagnóstico exportable, consultas por voz, cloud y sincronización permanecen
diferidos salvo nueva decisión explícita.

## Resultado buscado

- Operaciones agrícolas rápidas y comprensibles en campo.
- Cuentas exactas y auditables.
- Datos preservados durante años y entre actualizaciones.
- Reportes producidos desde contratos tipados, no desde widgets ni SQL duplicado.
- Voz detrás de puertos reemplazables; la transcripción/interpretación no escribe dominio y los
  casos aprobados sólo escriben tras un draft válido y confirmación táctil.
- Arquitectura que crece por extracción oportunista, no por reescritura.

## Límites

La baseline es local, monodispositivo y Android es la plataforma verificada. Backend,
autenticación, nube y telemetría son subsistemas nuevos. EVOLUTION-3 no permite SQL generado,
confirmación hablada, escucha permanente, transferencias, reversiones, cierres ni borrado.

## Medida de éxito

Una evolución es exitosa cuando entrega valor observable, conserva invariantes, mantiene
backups compatibles, pasa CI y queda trazable desde requisito hasta evidencia.
