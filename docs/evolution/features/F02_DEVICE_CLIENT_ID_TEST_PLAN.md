# F02 — Plan de prueba física de identidad de instalación

## Alcance

Este plan verifica el lifecycle Android de `InstallationClientIdStore`. El identificador es un UUID v4
seudónimo, no secreto, no autenticador y no autoridad de negocio. No implementa networking, Sync F05,
sesiones ni cambios de voz.

## Preparación

- Compilar una APK debug desde `feat/f02-installation-client-id`.
- Usar un dispositivo Android físico con `adb` y una instalación limpia.
- Leer el archivo únicamente mediante `run-as` sobre la build debug; no añadir una pantalla ni logs de
  release para exponer el valor.
- Ruta relativa Android: `no_backup/installation_identity/client_id` dentro del sandbox de la app.

Comando orientativo:

```text
adb shell run-as com.comunidad.agro.agroquimicos cat no_backup/installation_identity/client_id
```

## Casos

| Caso | Procedimiento | Resultado esperado |
|---|---|---|
| A — instalación limpia | Instalar, abrir y leer el archivo | UUID v4 canónico `A` |
| B — force-stop | Cerrar/force-stop, abrir y releer | valor igual a `A` |
| C — reinicio | Reiniciar el teléfono, abrir y releer | valor igual a `A` |
| D — backup Agrocuentas | Exportar y restaurar `.agrobackup`, releer | valor igual a `A` |
| E — reinstalación | Desinstalar, reinstalar, abrir y releer | UUID `B`, con `B != A` |
| F — privacidad | Revisar permisos/código y tráfico | no IMEI, Android ID, serial, MAC ni networking |

## Evidencia a registrar

- dispositivo, Android/API y SHA probado;
- hash parcial o comparación `A == A` / `B != A`, sin publicar el clientId completo;
- resultados A–F y cualquier desviación;
- `ANDROID_SYSTEM_BACKUP_EXCLUDED`: el archivo reside en `noBackupFilesDir`;
- `APP_BACKUP_EXCLUDED`: no aparece en `manifest.json`, `database.db`, invoices ni entradas ZIP.

Hasta ejecutar este plan en hardware: `DEVICE = NOT_MEASURED`.
