import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/agro_repository.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'domain/reports/report_composer.dart';
import 'presentation/app_shell.dart';
import 'presentation/screens/applications_screen.dart';
import 'presentation/screens/application_form_screen.dart';
import 'presentation/screens/catalogs_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/farm_logbook_screen.dart';
import 'presentation/screens/inventory_detail_screen.dart';
import 'presentation/screens/inventory_screen.dart';
import 'presentation/screens/operations_screen.dart';
import 'presentation/screens/person_detail_screen.dart';
import 'presentation/screens/persons_screen.dart';
import 'presentation/screens/planning_screen.dart';
import 'presentation/screens/plan_form_screen.dart';
import 'presentation/screens/purchases_screen.dart';
import 'presentation/screens/purchase_form_screen.dart';
import 'presentation/screens/reports_screen.dart';
import 'presentation/screens/settlements_screen.dart';
import 'presentation/screens/transfers_screen.dart';
import 'presentation/screens/transfer_form_screen.dart';
import 'services/reports/report_export_service.dart';
import 'services/reports/report_storage.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final repositoryProvider = Provider<AgroRepository>(
  (ref) => AgroRepository(ref.watch(databaseProvider)),
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

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
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
        ],
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
  ),
);

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
