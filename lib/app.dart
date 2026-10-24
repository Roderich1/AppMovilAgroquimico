import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/agro_repository.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/farmer_operation_gate.dart';
import 'domain/installation_access.dart';
import 'domain/operation_mode.dart';
import 'installation_access.dart';
import 'operation_mode_controller.dart';
import 'services/auth/local_owner_credential_providers.dart';
import 'domain/reports/report_composer.dart';
import 'presentation/app_shell.dart';
import 'presentation/screens/access_status_screen.dart';
import 'presentation/screens/applications_screen.dart';
import 'presentation/screens/application_form_screen.dart';
import 'presentation/screens/catalogs_screen.dart';
import 'presentation/screens/central_binding_screen.dart';
import 'presentation/screens/remote_backup_screen.dart';
import 'presentation/screens/consumption_publish_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/declared_needs_screen.dart';
import 'presentation/screens/first_activation_screen.dart';
import 'presentation/screens/reauthentication_screen.dart';
import 'presentation/screens/farm_logbook_screen.dart';
import 'presentation/screens/inventory_detail_screen.dart';
import 'presentation/screens/inventory_screen.dart';
import 'presentation/screens/operation_mode_screen.dart';
import 'presentation/screens/operations_screen.dart';
import 'presentation/screens/owner_setup_screen.dart';
import 'presentation/screens/person_detail_screen.dart';
import 'presentation/screens/persons_screen.dart';
import 'presentation/screens/planning_screen.dart';
import 'presentation/screens/plan_form_screen.dart';
import 'presentation/screens/purchases_screen.dart';
import 'presentation/screens/purchase_form_screen.dart';
import 'presentation/screens/reports_screen.dart';
import 'presentation/screens/settlements_screen.dart';
import 'presentation/screens/sync_status_screen.dart';
import 'presentation/screens/transfers_screen.dart';
import 'presentation/screens/transfer_form_screen.dart';
import 'presentation/screens/access_recovery_screen.dart';
import 'presentation/screens/owner_credential_screen.dart';
import 'presentation/screens/late_operations_screen.dart';
import 'services/reports/report_export_service.dart';
import 'services/reports/report_storage.dart';
import 'presentation/voice/voice_application_draft_screen.dart';
import 'presentation/voice/voice_entry_screen.dart';
import 'presentation/voice/voice_plan_draft_screen.dart';
import 'presentation/voice/voice_purchase_draft_screen.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// El repositorio de la app aplica la política de activación en cada
/// escritura (#76). Las pruebas que no tratan la activación sobrescriben este
/// proveedor con un repositorio sin restricción.
final repositoryProvider = Provider<AgroRepository>(
  (ref) => AgroRepository(
    ref.watch(databaseProvider),
    gate: FarmerOperationGate(() => ref.read(installationAccessProvider)),
    // RF-13/RF-03: una autorización del titular vale sólo con el PIN
    // configurado ahora en el almacén de la instalación.
    ownerCredential: () => ref.read(localOwnerCredentialProvider),
  ),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

/// Dónde se guardan los reportes. Es un proveedor propio para que las pruebas
/// de pantalla puedan escribir en una carpeta temporal.
final reportStorageProvider = Provider<ReportStorage>(
  (ref) => LocalReportStorage(),
);

final reportExportServiceProvider = Provider<ReportExportService>(
  (ref) => ReportExportService(
    ref.watch(repositoryProvider),
    ref.watch(reportStorageProvider),
  ),
);

/// Rutas que se pueden abrir aunque la instalación no pueda operar.
const _accessRoutes = {
  '/acceso',
  '/activar',
  '/titular',
  '/reauth',
  '/recuperar',
};

/// Compuerta de navegación de la política de activación (#76). La compuerta
/// de dominio está en el repositorio; ésta sólo evita mostrar pantallas que
/// fallarían.
String? accessRedirect(InstallationAccessState? access, String path) {
  if (access == null) return _accessRoutes.contains(path) ? null : '/acceso';
  if (access.allowsFarmerOperations) return path == '/acceso' ? '/' : null;
  // Activación incompleta: el único paso pendiente es elegir el titular.
  if (access == InstallationAccessState.activationPendingOwner) {
    return path == '/titular' ? null : '/titular';
  }
  // Resto de estados bloqueados: la pantalla de acceso y, si corresponde, la
  // activación o la reautenticación. El titular no se elige en estos estados.
  return _accessRoutes.contains(path) && path != '/titular' ? null : '/acceso';
}

final routerProvider = Provider<GoRouter>((ref) {
  final accessChanges = ValueNotifier<InstallationAccessState?>(
    ref.read(installationAccessProvider),
  );
  ref.listen(
    installationAccessProvider,
    (_, next) => accessChanges.value = next,
  );
  ref.onDispose(accessChanges.dispose);
  // La modalidad se crea con el router para que se lea en paralelo con el
  // acceso al arrancar, antes de mostrar el shell (#26).
  final modeChanges = ValueNotifier<OperationMode?>(
    ref.read(operationModeProvider),
  );
  ref.listen(operationModeProvider, (_, next) => modeChanges.value = next);
  ref.onDispose(modeChanges.dispose);
  Future.microtask(ref.read(operationModeProvider.notifier).reload);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([accessChanges, modeChanges]),
    redirect: (_, state) =>
        accessRedirect(ref.read(installationAccessProvider), state.uri.path) ??
        operationModeRedirect(ref.read(operationModeProvider), state.uri.path),
    routes: [
      ShellRoute(
        builder: (context, state, child) => Consumer(
          builder: (context, ref, _) => AppShell(
            location: state.uri.path,
            transfersEnabled:
                ref.watch(operationModeProvider) != OperationMode.personal,
            child: child,
          ),
        ),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: '/operaciones',
            builder: (_, __) => const OperationsScreen(),
          ),
          GoRoute(
            path: '/catalogos',
            builder: (_, __) => const CatalogsScreen(),
          ),
          GoRoute(
            path: '/planificacion',
            builder: (_, __) => const PlanningScreen(),
          ),
          GoRoute(
            path: '/compras',
            builder: (_, __) => const PurchasesScreen(),
          ),
          GoRoute(
            path: '/aplicaciones',
            builder: (_, __) => const ApplicationsScreen(),
          ),
          GoRoute(
            path: '/liquidacion',
            builder: (_, __) => const SettlementsScreen(),
          ),
          GoRoute(
            path: '/inventario',
            builder: (_, __) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/reportes',
            builder: (_, state) => ReportsScreen(
              initialKind: reportKindFromRoute(
                state.uri.queryParameters['tipo'],
              ),
              initialPersonId: int.tryParse(
                state.uri.queryParameters['persona'] ?? '',
              ),
              initialCampaignId: int.tryParse(
                state.uri.queryParameters['campana'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/inventario/:id',
            builder: (_, state) => InventoryDetailScreen(
              productId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(path: '/personas', builder: (_, __) => const PersonsScreen()),
          GoRoute(
            path: '/personas/:id',
            builder: (_, state) => PersonDetailScreen(
              personId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/chacos/:id',
            builder: (_, state) => FarmLogbookScreen(
              farmId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/transferencias',
            builder: (_, __) => const TransfersScreen(),
          ),
          GoRoute(
            path: '/planificacion/necesidades',
            builder: (_, __) => const DeclaredNeedsScreen(),
          ),
          GoRoute(
            path: '/sincronizacion',
            builder: (_, __) => const SyncStatusScreen(),
          ),
          GoRoute(
            path: '/sindicato/vinculos',
            builder: (_, __) => const CentralBindingScreen(),
          ),
          GoRoute(
            path: '/sincronizacion/consumo',
            builder: (_, __) => const ConsumptionPublishScreen(),
          ),
          GoRoute(
            path: '/respaldo-remoto',
            builder: (_, __) => const RemoteBackupScreen(),
          ),
          // F09. La voz vive DENTRO del shell, como los subdestinos de
          // Operaciones: se llega apilando y Atrás vuelve. Cada borrador
          // ofrece su formulario manual, que lo sustituye (el borrador se
          // descarta sin escribir).
          GoRoute(
            path: voiceEntryPath,
            builder: (_, __) => const VoiceEntryScreen(),
          ),
          GoRoute(
            path: voicePurchasePath,
            builder: (context, __) => VoicePurchaseDraftScreen(
              onOpenManualForm: () => context.pushReplacement('/compras/nueva'),
            ),
          ),
          GoRoute(
            path: voicePlanPath,
            builder: (context, __) => VoicePlanDraftScreen(
              onOpenManualForm: () =>
                  context.pushReplacement('/planificacion/nueva'),
            ),
          ),
          GoRoute(
            path: voiceApplicationPath,
            builder: (context, __) => VoiceApplicationDraftScreen(
              onOpenManualForm: () =>
                  context.pushReplacement('/aplicaciones/nueva'),
            ),
          ),
        ],
      ),
      GoRoute(path: '/acceso', builder: (_, __) => const AccessStatusScreen()),
      GoRoute(path: '/titular', builder: (_, __) => const OwnerSetupScreen()),
      GoRoute(path: '/modo', builder: (_, __) => const OperationModeScreen()),
      GoRoute(
        path: '/activar',
        builder: (_, __) => const FirstActivationScreen(),
      ),
      GoRoute(
        path: '/reauth',
        builder: (_, __) => const ReauthenticationScreen(),
      ),
      GoRoute(
        path: '/recuperar',
        builder: (_, __) => const AccessRecoveryScreen(),
      ),
      GoRoute(
        path: '/titular/pin',
        builder: (_, __) => const OwnerCredentialScreen(),
      ),
      GoRoute(
        path: '/operaciones/tardias',
        builder: (_, __) => const LateOperationsScreen(),
      ),
      GoRoute(
        path: '/transferencias/nueva',
        builder: (_, __) => const TransferFormScreen(),
      ),
      GoRoute(
        path: '/compras/nueva',
        builder: (_, __) => const PurchaseFormScreen(),
      ),
      GoRoute(
        path: '/aplicaciones/nueva',
        builder: (_, state) => ApplicationFormScreen(
          planId: int.tryParse(state.uri.queryParameters['planId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/planificacion/nueva',
        builder: (_, __) => const PlanFormScreen(),
      ),
    ],
  );
});

class AgroApp extends ConsumerWidget {
  const AgroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Agrocuentas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF35693E)),
      scaffoldBackgroundColor: const Color(0xFFF7F7F1),
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      listTileTheme: const ListTileThemeData(dense: true),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    ),
    routerConfig: ref.watch(routerProvider),
  );
}
