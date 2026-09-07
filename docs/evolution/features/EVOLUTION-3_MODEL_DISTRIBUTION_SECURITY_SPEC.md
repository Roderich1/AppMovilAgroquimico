# EVOLUTION-3 — Distribución y seguridad de modelos locales

## Objetivo

Garantizar que los modelos de voz locales sean auténticos, reproducibles, instalables sin
corrupción y eliminables, sin comprometer el modo manual ni los datos de Agrocuentas.

## Manifest de modelo

Cada modelo debe tener un manifest versionado con:

```text
engine_id
engine_version_or_commit
model_id
model_version
source_url
license_id
license_file
compressed_size_bytes
installed_size_bytes
sha256
supported_abis
minimum_android_api
audio_format
created_at
```

No aceptar URLs móviles sin versión, artefactos reemplazables, hashes parciales ni modelos cuya
licencia no autorice distribución dentro de la aplicación.

## Alternativas de entrega a medir

### A. Empaquetado en la aplicación

Ventaja: funciona tras instalar sin red. Desventajas: APK/AAB grande, actualizaciones costosas y
duplicación temporal durante instalación.

### B. Paquete de voz descargable

Ventaja: app base pequeña. Desventaja: primera instalación requiere conectividad. Debe permitir
descargar en casa antes de ir al campo y mostrar progreso, tamaño y espacio necesario.

### C. Importación local

Permite copiar un paquete verificado por cable, memoria o selector de documentos. Es el respaldo
para instalaciones sin Internet, no una vía para aceptar modelos arbitrarios.

La decisión se toma después de medir tamaño final y proceso real de instalación.

## Instalación atómica

1. Comprobar espacio libre suficiente para descarga, extracción y rollback.
2. Descargar/importar a staging privado.
3. Verificar longitud y SHA-256 antes de extraer.
4. Validar allowlist de rutas; impedir path traversal y enlaces.
5. Extraer con límites de cantidad de archivos y tamaño total.
6. Verificar estructura y manifest interno.
7. Realizar smoke test del motor.
8. Activar mediante rename atómico o puntero de versión.
9. Mantener una versión anterior hasta confirmar el primer uso.
10. Borrar staging de forma segura ante fallo.

Nunca modificar SQLite ni incluir modelos dentro de `.agrobackup`.

## Privacidad

- Audio exclusivamente en memoria nativa y con duración máxima.
- No escribir WAV/PCM temporal en almacenamiento.
- No incluir transcripción ni audio en logs, analytics o crash reports.
- Métricas sólo con códigos, duración, tamaños y tiempos.
- Limpiar buffers al finalizar, cancelar, perder permiso o destruir el proceso.
- La pantalla debe indicar “Procesamiento local en este teléfono” sólo cuando se use realmente
  Vosk/Whisper local.
- Un fallback a un servicio del sistema debe ser explícito y nunca llamarse local sin evidencia.

## Supply chain

- Fijar commits de Vosk API y whisper.cpp.
- Compilar bibliotecas nativas reproduciblemente para ABI autorizadas.
- Generar SBOM o inventario equivalente.
- Conservar textos de licencia y atribuciones.
- Escanear bibliotecas nativas y dependencias.
- Prohibir descarga de ejecutables; sólo se instalan datos de modelo verificados.
- Documentar toolchain, NDK, CMake, flags y símbolos eliminados.

## Fallos seguros

| Fallo | Comportamiento |
|---|---|
| Modelo ausente | ofrecer instalar/importar o continuar manualmente |
| Hash inválido | rechazar, borrar staging y mantener versión anterior |
| Poco espacio | no iniciar; informar espacio necesario |
| Modelo incompatible | no cargar; mostrar versión y diagnóstico |
| OOM o temperatura | cancelar final, conservar texto manual/parcial como no confirmado |
| Crash nativo | reinicio seguro sin repetir automáticamente la inferencia |

## Gates

- instalación limpia en API 31 y API 36;
- modo avión desde el primer uso;
- actualización, rollback y corrupción inducida;
- falta de espacio;
- cierre durante descarga/extracción;
- hash y licencias comprobables;
- ningún cambio en esquema, backup ni datos de negocio;
- ingreso manual siempre disponible.

