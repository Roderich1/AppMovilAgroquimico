# 19 — Notificaciones

## Conclusión

**Esta capacidad no fue encontrada en la implementación actual.**

La aplicación no emite notificaciones push ni locales, ni programa recordatorios, ni tiene
ningún canal de aviso fuera de la propia interfaz.

## Evidencia de la ausencia

| Elemento buscado | Resultado |
|---|---|
| `firebase_messaging` | Sin dependencia |
| `flutter_local_notifications` | Sin dependencia |
| `awesome_notifications`, `onesignal_flutter` | Sin dependencia |
| Servicio FCM o `<service>` en `AndroidManifest.xml` | Ausente |
| `POST_NOTIFICATIONS` (Android 13+) | **No declarado** |
| `UNUserNotificationCenter` / `UIBackgroundModes: remote-notification` en `Info.plist` | Ausente |
| `google-services.json` / `GoogleService-Info.plist` | **No existen** |
| Programación de tareas (`workmanager`, `android_alarm_manager_plus`) | Sin dependencia |
| Canales de notificación | Ninguno |

La ausencia del permiso `INTERNET` en el manifiesto de release confirma además que **las
notificaciones push serían técnicamente imposibles** sin cambiar la configuración de la app.

## Qué cumple hoy la función de avisar al usuario

Toda la retroalimentación es **síncrona y dentro de la pantalla**:

| Mecanismo | Implementación | Uso |
|---|---|---|
| Snackbar de error | `showError(context, error)` → `SnackBar` con `colorScheme.error`, comportamiento `floating` | Errores de negocio y de validación en todas las pantallas |
| Snackbar de éxito | `showSuccess(context, message)` → `SnackBar` neutro | *"Compra multiproducto confirmada; lotes e inventario creados."*, *"Aplicación multiproducto confirmada."*, *"Backup guardado en `<ruta>`"* |
| Diálogos de confirmación | `AlertDialog` | Descartar cambios, cerrar campaña, cambiar campaña activa, confirmar transferencia, falta campaña activa |
| Estados vacíos | `EmptyState` | Cuando una lista no tiene datos |
| Indicadores de carga | `CircularProgressIndicator`, `LinearProgressIndicator` | Durante consultas y guardados |
| Señales de color | Naranja para saldo pendiente, verde para saldo a favor, `colorScheme.error` para proyección de inventario negativa | `settlements_screen.dart`, `inventory_screen.dart` |

El estilo de los snackbars se define una sola vez en `lib/app.dart`
(`SnackBarThemeData(behavior: SnackBarBehavior.floating)`), lo que da consistencia visual.

## Oportunidades no implementadas

El dominio ofrece varios disparadores naturales que hoy no notifican nada. Registrados en
[29_IMPROVEMENT_AUDIT](29_IMPROVEMENT_AUDIT.md) con prioridad baja (P3), porque son
funcionalidad nueva y no corrección de defectos:

| Disparador | Dato ya disponible en el código |
|---|---|
| Stock proyectado negativo | `inventorySummary().projected_base < 0` — ya se pinta en rojo en `/inventario` |
| Planes pendientes al cerrar campaña | `campaignCloseSummary().pending_plans` — ya se muestra en el diálogo de cierre |
| Compra con saldo pendiente al proveedor | `purchases().paid_bob_minor < total_bob_minor` |
| Saldos elevados de familiares o terceros | `settlements().balance > 0` |
| Recordatorio de copia de seguridad | No hay registro de la fecha del último backup; habría que añadirlo (la tabla `app_settings`, hoy muerta, serviría exactamente para esto) |

Cualquiera de estos requeriría añadir `flutter_local_notifications` y, en Android 13 o
superior, declarar y solicitar `POST_NOTIFICATIONS`.
