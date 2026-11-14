# Modo individual — entrega

**Estado:** lista para la revisión del autor. Sin push, PR, fusión a main ni cambios en la DEMO. **Todavía no se integró con la sesión de permisos y consentimiento**: su entrega no es estable (ver «Pendiente»).

## Rama y candidata

- Rama: `feat/modo-individual` (`_wt/IND-INT`), código final `b8248fb`. Base: `507efc8` (`feat/rediseno-movil`).
- Sesiones integradas: A `b563eef` (compra, aplicación, plan, voz), B `6f9d0e0` (almacén, actividad, proveedores), C `64ce789` (chacos y costos).
- APK instalada en `emulator-5556` (AVD `RDM_Pixel8`): `com.comunidad.agro.agroquimicos.ind` «AC IND», SHA-256 `3ee883f783325ccb739a1b947ff90f895d3cfbfd9e50b09472bc42a76c3f5cdb`. El archivo está en `C:/Users/MSI/AppData/Local/Temp/agro_ind/apk/agrocuentas.ind-profile-x64.apk`. Está atada a un túnel ya cerrado: funciona sin conexión, pero no sincroniza.

## Qué cambió

- **Navegación por modo:** Inicio · Actividad · Almacén · Chacos · Sindicato. Chacos sustituye a Personas sólo en el modo individual. Las rutas de personas siguen accesibles para consultar el historial.
- Las 28 láminas, con su matriz en `MATRIZ_VISTAS.md`.
- **Cambios funcionales:** ninguno en reglas ni en cálculos. Todo depende de `OperationMode.personal`, que ya existía; no hay otra bandera ni otro titular. Sólo se añadieron pantallas y lecturas (SELECT).
- **Textos:** los visibles pasan a «Modo individual» y «Modo con varias personas», también en los mensajes del repositorio. Los códigos internos siguen siendo PERSONAL y SHARED.
- **Plan:** fecha prevista opcional (`planned_date`, que ya existía en el modelo).

## Verificación

Ver `docs/evidence/rediseno-individual/2026-11-13/README.md`.
- Suite completa: 3164 pasan, 3 omitidas y 2 fallos nuevos, corregidos y reejecutados en verde.
- `analyze` sin avisos.
- Recorrido en emulador con efectos comprobados en los datos. **No se probó en un teléfono físico.**

**Modo con varias personas conservado:**
- Las pruebas de cada sesión cubren los dos modos.
- La suite completa incluye todas las pruebas anteriores del modo compartido.
- En el emulador se cambió a varias personas y de vuelta, con las cifras idénticas.
- La instalación `.rdm` no se tocó.

## Limitaciones reales

- No hay prueba en un teléfono físico.
- Voz: sólo estados visuales en el emulador, sin audio real. En el arnés se usó un motor falso. «Procesando» y «Revisar tras dictar» sólo se vieron en el arnés.
- I-52 (cambio bloqueado) e I-53 (con envíos pendientes) sólo se vieron en el arnés: el hogar del emulador no tiene terceros ni envíos.
- El informe «Costo por chaco» exportado incluye todos los chacos de la base. Si hay historial de terceros, mostrará chacos que la pantalla individual no muestra. `reports_screen.dart` es un archivo compartido con la sesión de permisos.
- En el historial, la Actividad compara al titular por nombre, no por id (petición P-3 de la sesión B, sin aplicar).
- A 200 %, el subtotal de la hoja de producto queda bajo los botones hasta desplazar. Ya pasaba antes, en los dos modos.
- No hay pantalla de Ayuda; no se inventó.

## Pendiente

1. **Integración con la sesión de permisos (`proyectoagro-cb`).** `9da5054` todavía no es estable. Cuando pase el SHA de ACC-MOB y el de Backend de `feat/acceso-rol-sin-k` (contrato 4):
   - fusionarlo en `feat/modo-individual`;
   - activar el aviso «Revise quién puede ver su participación en las compras conjuntas» (`jointPurchaseAccessReviewCountProvider` > 0 → `/compras-conjuntas`) en «Avisos» de `ind_home.dart` y en «Para atender» de `dashboard_screen.dart`;
   - correr la suite completa;
   - compilar **una sola APK** con un túnel nuevo autorizado.
2. **Decisiones del autor:**
   - ¿llevar el panel de voz nuevo (Escuchando/Procesando) también al modo con varias personas?
   - ¿permitir editar la superficie de un chaco? Hoy el repositorio no lo permite.

> **Resuelto en el cierre (2026-11-13, `integracion/cierre-mob`):**
> - Integración con permisos: entrega estable `f9aac3a` fusionada con `bfe0fa2` en `f8de886`. El aviso de Inicio está en los dos modos (`64e1d7b`), junto al aviso de convocatoria nueva y no dentro de «Avisos»/«Para atender», para que se vea aunque el resumen tarde. La suite completa pasa sobre `aeeb4f0`: 3202 pasan, 3 omitidas, 0 fallan.
> - Panel de voz en el modo con varias personas: el autor lo autorizó (decisión A); aplicado en `1310f9e`.
> - Superficie del chaco: el autor decidió no añadir la edición en el cierre (decisión B); queda como mejora pendiente.
> - Exportación «Costo por chaco»: corregida (decisión C), y también «Costo por producto»; «Resumen de campaña» queda como limitación aceptada.
>
> Detalle: `docs/cierre/RESUMEN_CIERRE_MOBILE_2026-11-13.md`.

## Guía breve de revisión

En el emulador, abra «AC IND», que ya tiene datos sintéticos de Rosa Vargas:
1. Inicio y la hoja Registrar.
2. Compra (hoja de producto y revisión).
3. Actividad › Proveedores y saldos › Pagar.
4. Aplicación y Plan, y luego Almacén.
5. Chacos › Chaco Norte › Ver todos los costos.
6. Ajustes › Modo de uso.

Para ver el modo con varias personas, cambie el modo en la misma app y vuelva; no se borra nada.
