# Visión de evolución

## Objetivo

Evolucionar Agrocuentas significa aumentar su valor operativo sin degradar su contabilidad,
trazabilidad, uso offline ni capacidad de recuperación. Cada capacidad nace como un cambio
aislado, con contrato, pruebas y verificación proporcional al riesgo.

## Cuatro estados que no deben mezclarse

| Estado | Significado | Ejemplo vigente |
|---|---|---|
| Baseline | Punto histórico cerrado e inmutable | `v1.0.0-base-stable` |
| Evolución | Capacidad posterior, todavía propuesta/aprobada/en desarrollo | Backlog `EVO-*` |
| Producción | Artefacto firmable, distribuible y operable | Bloqueado por keystore |
| Futuro | Hipótesis sin compromiso | voz, nube, sincronización |

`READY FOR EVOLUTION` no significa `READY FOR STORE`. Del mismo modo, una idea futura no es
un requisito y un backlog `PROPOSED` no autoriza implementación.

## Resultado buscado

- Operaciones agrícolas rápidas y comprensibles en campo.
- Cuentas exactas y auditables entre administrador, familiares y terceros.
- Datos preservados durante años y entre actualizaciones.
- Capacidades externas —voz, cloud o sincronización— detrás de fronteras explícitas.
- Arquitectura que crece por extracción oportunista, no por reescritura.

## Límites actuales

La baseline es local, monodispositivo y Android es la plataforma verificada. Backend,
autenticación, nube, telemetría, IA y comandos por voz son subsistemas nuevos. No se asume su
existencia ni se insertan dentro de una pantalla o de `AgroRepository` sin contrato propio.

## Medida de éxito

Una evolución es exitosa cuando entrega valor observable, conserva invariantes, migra datos
sin pérdida, mantiene backups compatibles, pasa CI y queda verificable desde requisito hasta
evidencia. Más capas o más archivos no son una medida de éxito.
