import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/app_database.dart';
import '../../data/owner_binding_store.dart';
import '../../domain/installation_access.dart';
import '../../domain/operation_mode.dart';
import '../../installation_access.dart';
import '../../licenses/third_party_licenses.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/rdm_c_page.dart';
import 'operation_mode_screen.dart' show operationModeTitle;

/// «Ajustes y datos» (`/mas`, rediseño, lámina «Ajustes»): las funciones que
/// se usan de vez en cuando, en tres grupos (Datos, Seguridad, Uso). Se abre
/// desde el engranaje de Inicio. Aquí sólo se navega: cada pantalla conserva
/// sus guardas.
///
/// Respecto de la lámina: Reportes no se repite (está en la cabecera de
/// Actividad, decisión del 2026-11-05); «Vínculos» y «Compras conjuntas»
/// viven en la pestaña Sindicato; no se muestran estados («Verificado», «Sin
/// clave») que exigirían consultas nuevas al abrir la pantalla.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const _data = <_Entry>[
    _Entry(
      key: 'more-catalogs',
      title: 'Personas, chacos, productos y proveedores',
      path: '/catalogos',
    ),
    _Entry(key: 'more-campaigns', title: 'Campañas', path: '/campanas'),
    // RF-03: compras y aplicaciones con fecha de una campaña cerrada,
    // pendientes de que el titular las confirme o las rechace.
    _Entry(
      key: 'more-late',
      title: 'Operaciones tardías',
      detail: 'De campañas cerradas, en revisión',
      path: '/operaciones/tardias',
    ),
  ];

  static const _security = <_Entry>[
    _Entry(key: 'more-access', title: 'Acceso en línea', path: '/acceso'),
    _Entry(
      key: 'more-pin',
      title: 'PIN del titular',
      detail: 'Autoriza reversiones en este teléfono',
      path: '/titular/pin',
    ),
    _Entry(
      key: 'more-backups',
      title: 'Respaldos',
      detail: 'En la nube y en este teléfono',
      path: '/respaldo-remoto',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(operationModeProvider);
    if (mode == OperationMode.personal) return const _IndividualSettings();
    final usage = <_Entry>[
      _Entry(
        key: 'more-mode',
        title: 'Modo de uso',
        detail: switch (mode) {
          OperationMode.personal => 'Ahora: modo individual',
          OperationMode.shared => 'Ahora: modo con varias personas',
          null => 'Individual o con varias personas',
        },
        path: '/modo',
      ),
      // F09: lleva a los formularios con el panel de voz; no registra nada
      // por sí sola.
      const _Entry(key: 'more-voice', title: 'Registrar por voz', path: '/voz'),
    ];

    Widget group(String title, List<_Entry> entries, {Widget? extra}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RdmCOverline(title),
        AgroGroup(
          children: [
            for (final entry in entries)
              RdmCRow(
                key: Key(entry.key),
                title: entry.title,
                detail: entry.detail,
                // Se APILAN: Atrás vuelve aquí (UIBUG-004A).
                onTap: () => context.push(entry.path),
              ),
            ?extra,
          ],
        ),
        const SizedBox(height: 16),
      ],
    );

    return RdmCPage(
      title: 'Ajustes y datos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          group('Datos', _data),
          group('Seguridad', _security),
          group(
            'Uso',
            usage,
            // Avisos de licencia (F09): abre la página de licencias de
            // Flutter con los paquetes Dart y los componentes de la voz local
            // (lib/licenses).
            extra: RdmCRow(
              key: const Key('more-licenses'),
              title: 'Licencias',
              onTap: () => showAgroLicenses(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry({
    required this.key,
    required this.title,
    required this.path,
    this.detail,
  });
  final String key;
  final String title;
  final String? detail;
  final String path;
}

/// «Ajustes y datos» del modo individual (lámina I-50): el modo y el titular
/// arriba, en una tarjeta que abre Modo de uso; luego Datos, Cuenta y
/// seguridad, y Licencias. Sólo navega: cada pantalla conserva sus guardas.
///
/// Respecto de la lámina: «Ayuda» no se muestra porque la app no tiene una
/// pantalla de ayuda (no se inventa); la cuenta dice «Activada» (estado
/// local de la activación, sin consulta en línea) en vez de «Verificada»;
/// «Registrar por voz» queda dentro de cada formulario (hoja Registrar).
class _IndividualSettings extends ConsumerWidget {
  const _IndividualSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activated =
        ref.watch(installationAccessProvider) ==
        InstallationAccessState.activated;
    Widget group(String? title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) RdmCOverline(title),
        AgroGroup(children: rows),
        const SizedBox(height: 16),
      ],
    );
    RdmCRow row(String key, String title, String path, {Widget? trailing}) =>
        RdmCRow(
          key: Key(key),
          title: title,
          trailing: trailing,
          // Se APILAN: Atrás vuelve aquí (UIBUG-004A).
          onTap: () => context.push(path),
        );
    return RdmCPage(
      title: 'Ajustes y datos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ModeCard(),
          const SizedBox(height: 8),
          group('Datos', [
            row(
              'more-catalogs',
              'Chacos, productos y proveedores',
              '/catalogos',
            ),
            row(
              'more-campaigns',
              'Campañas',
              '/campanas',
              trailing: const _ActiveCampaignName(),
            ),
            row(
              'more-reports',
              'Reportes',
              '/reportes',
              trailing: const Text('Excel o PDF', style: AgroText.detail),
            ),
            row('more-late', 'Operaciones tardías', '/operaciones/tardias'),
          ]),
          group('Cuenta y seguridad', [
            row(
              'more-access',
              'Cuenta y titular',
              '/acceso',
              trailing: activated
                  ? const StatusBadge(label: 'Activada', tone: BadgeTone.ok)
                  : null,
            ),
            row('more-pin', 'PIN del titular', '/titular/pin'),
            row('more-backups', 'Respaldos', '/respaldo-remoto'),
          ]),
          group(null, [
            RdmCRow(
              key: const Key('more-licenses'),
              title: 'Licencias',
              onTap: () => showAgroLicenses(context),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Tarjeta oscura «Modo de uso · Modo individual · Titular: …» (I-50).
class _ModeCard extends ConsumerStatefulWidget {
  const _ModeCard();

  @override
  ConsumerState<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends ConsumerState<_ModeCard> {
  late final Future<String?> _owner = _ownerName(
    ref.read(repositoryProvider).appDatabase,
  );

  static Future<String?> _ownerName(AppDatabase database) async {
    final binding = await OwnerBindingStore(database).activeBinding();
    if (binding == null) return null;
    final rows = await (await database.database).query(
      'persons',
      columns: ['name'],
      where: 'id=?',
      whereArgs: [binding.personId],
    );
    return rows.isEmpty ? null : rows.single['name'] as String?;
  }

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.ink,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      key: const Key('more-mode'),
      borderRadius: BorderRadius.circular(24),
      onTap: () => context.push('/modo'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 14, 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modo de uso',
                    style: TextStyle(
                      fontSize: 14,
                      color: AgroColors.onInkMuted,
                    ),
                  ),
                  Text(
                    operationModeTitle(OperationMode.personal),
                    style: AgroText.h2.copyWith(color: Colors.white),
                  ),
                  FutureBuilder<String?>(
                    future: _owner,
                    builder: (context, snapshot) => snapshot.data == null
                        ? const SizedBox.shrink()
                        : Text(
                            'Titular: ${snapshot.data}',
                            key: const Key('more-owner-name'),
                            style: const TextStyle(
                              fontSize: 15,
                              color: AgroColors.onInkMuted,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AgroColors.lime),
          ],
        ),
      ),
    ),
  );
}

class _ActiveCampaignName extends ConsumerStatefulWidget {
  const _ActiveCampaignName();

  @override
  ConsumerState<_ActiveCampaignName> createState() =>
      _ActiveCampaignNameState();
}

class _ActiveCampaignNameState extends ConsumerState<_ActiveCampaignName> {
  late final Future<Map<String, Object?>?> _active = ref
      .read(repositoryProvider)
      .activeCampaign();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _active,
    builder: (context, snapshot) {
      final name = snapshot.data?['name'] as String?;
      return name == null
          ? const SizedBox.shrink()
          : Text(name, style: AgroText.detail);
    },
  );
}
