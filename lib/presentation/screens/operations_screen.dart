import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../../domain/person_roles.dart' show PersonPurpose;
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_b_ui.dart';
import '../widgets/register_sheet.dart' show registerRevisionProvider;
import 'ind_b_suppliers_screen.dart';

/// Actividad (lámina 1.3; antes «Operaciones»).
///
/// Un historial único, del más reciente al más antiguo, de compras,
/// aplicaciones y transferencias (éstas sólo en el modo con varias personas), con
/// «Por hacer» para los planes pendientes. Lee las mismas listas que las
/// pantallas de cada operación (`purchases()`, `applications()`, `plans()`,
/// `transfers()`) y no cambia ninguna cifra.
///
/// Las acciones de cada operación siguen en su lista, que se abre desde aquí
/// («Lista de compras»: buscar por campaña, pagar al proveedor, revertir,
/// ver la factura; aplicaciones y planes: los de la sesión A). Actividad
/// sólo abre: el detalle de una compra, la lista de cada tipo y el
/// formulario de aplicación de un plan («Aplicar», como en Planificación).
///
/// **Modo individual** (lámina I-04, 2026-11-13): las mismas operaciones,
/// sin repetir el nombre del titular en cada fila (una aplicación o un plan
/// de otra persona, de la historia anterior al cambio de modo, conserva su
/// nombre), y arriba «Proveedores y saldos» con lo que se debe a
/// proveedores de todas las campañas (el mismo saldo que Inicio). Sin
/// transferencias (ya antes). El modo con varias personas no cambia.
class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

enum _Filter { all, purchases, applications, plans, transfers }

typedef _Row = Map<String, Object?>;

/// Lo que Actividad lee. Cada lista con el límite de su pantalla; si una
/// llega al límite, el historial combinado se corta en su fecha más antigua
/// para no mostrar un hueco como si no hubiera habido operaciones.
typedef _ActivityData = ({
  List<_Row> purchases,
  List<_Row> applications,
  List<_Row> plans,
  List<_Row> transfers,
  bool transfersShown,
  SupplierDebt? supplierDebt,
  String? titularName,
});

const _purchaseLimit = 200;
const _applicationLimit = 200;
const _transferLimit = 50;

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  late Future<_ActivityData> future = _load();
  _Filter filter = _Filter.all;
  bool searching = false;
  String query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _personal => ref.read(personalModeProvider);

  Future<_ActivityData> _load() async {
    final repo = ref.read(repositoryProvider);
    final shared = !_personal;
    // En propio, todas las compras (sin límite) en la misma consulta: el
    // saldo con proveedores es de todas las campañas, como en Inicio, y con
    // el límite de 200 se contaría de menos. El historial sigue mostrando
    // las 200 más recientes. En compartido, exactamente lo de antes.
    final purchases = await repo.purchases(
      limit: shared ? _purchaseLimit : 1 << 30,
    );
    String? titularName;
    if (!shared) {
      final read = await repo.peopleAndContextFor(PersonPurpose.providerPayer);
      for (final person in read.people) {
        if (person['id'] == read.context.ownerPersonId) {
          titularName = person['name'] as String?;
        }
      }
    }
    return (
      purchases: shared ? purchases : purchases.take(_purchaseLimit).toList(),
      applications: await repo.applications(limit: _applicationLimit),
      plans: await repo.plans(),
      transfers: shared
          ? await repo.transfers(limit: _transferLimit)
          : const <_Row>[],
      transfersShown: shared,
      supplierDebt: shared ? null : supplierDebt(purchases),
      titularName: titularName,
    );
  }

  void _refresh() {
    final next = _load();
    setState(() {
      future = next;
    });
  }

  /// Abre otra pantalla y, al volver, relee: lo hecho allí cambia el
  /// historial (un pago, una reversión, un plan aplicado).
  /// Espera a que se cierre [navigation] (un `context.push` con su ruta
  /// escrita, para que la guarda de rutas sin origen la encuentre).
  Future<void> _open(Future<Object?> navigation) async {
    await navigation;
    if (mounted) _refresh();
  }

  void _toggleSearch() {
    setState(() {
      searching = !searching;
      if (!searching) {
        query = '';
        _search.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final personal = ref.watch(personalModeProvider);
    // Al cambiar de modo con la pantalla abierta, se relee (las
    // transferencias aparecen o desaparecen).
    ref.listen(operationModeProvider, (previous, next) {
      if (previous != next) _refresh();
    });
    // Lo registrado desde la hoja «+ Registrar» del shell.
    ref.listen(registerRevisionProvider, (_, _) => _refresh());
    // En propio no hay transferencias: si el filtro quedó en ellas al
    // cambiar de modo, vuelve a «Todo».
    final current = personal && filter == _Filter.transfers
        ? _Filter.all
        : filter;
    final filters = [
      (_Filter.all, 'Todo'),
      (_Filter.purchases, 'Compras'),
      (_Filter.applications, 'Aplicaciones'),
      (_Filter.plans, 'Planes'),
      if (!personal) (_Filter.transfers, 'Transferencias'),
    ];
    final list = switch (current) {
      _Filter.purchases => (
        'activity-open-purchases',
        'Lista de compras',
        'Por campaña, pagar al proveedor, revertir, factura',
        () => context.push('/compras'),
      ),
      _Filter.applications => (
        'activity-open-applications',
        'Lista de aplicaciones',
        'Registrar y revertir',
        () => context.push('/aplicaciones'),
      ),
      _Filter.plans => (
        'activity-open-plans',
        'Planificación',
        'Nuevo plan, aplicados y necesidades',
        () => context.push('/planificacion'),
      ),
      _Filter.transfers => (
        'activity-open-transfers',
        'Lista de transferencias',
        'Nueva y revertir',
        () => context.push('/transferencias'),
      ),
      _Filter.all => null,
    };
    return RdmScrollPage(
      children: [
        ScreenTitleBar(
          title: 'Actividad',
          actions: [
            CircleIconButton(
              key: const Key('activity-search-toggle'),
              icon: searching ? Icons.close : Icons.search,
              tooltip: searching ? 'Cerrar búsqueda' : 'Buscar',
              onPressed: _toggleSearch,
            ),
            CircleIconButton(
              key: const Key('activity-reports'),
              icon: Icons.summarize_outlined,
              tooltip: 'Reportes',
              onPressed: () => _open(context.push('/reportes')),
            ),
          ],
        ),
        if (searching) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('activity-search'),
            controller: _search,
            autofocus: true,
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: personal
                  ? 'Buscar proveedor, chaco o producto'
                  : 'Buscar proveedor, persona, chaco o producto',
            ),
          ),
        ],
        const SizedBox(height: 10),
        FilterPillBar(
          children: [
            for (final (value, label) in filters)
              FilterPill(
                key: Key('activity-filter-${value.name}'),
                label: label,
                selected: current == value,
                onSelected: () => setState(() => filter = value),
              ),
          ],
        ),
        // La lista completa de cada tipo, con sus acciones: no depende de
        // los datos del historial.
        if (list != null) ...[
          const SizedBox(height: 12),
          AgroGroup(
            children: [
              LinkRow(
                key: Key(list.$1),
                icon: Icons.list_alt_outlined,
                title: list.$2,
                subtitle: list.$3,
                onTap: () => _open(list.$4()),
              ),
            ],
          ),
        ],
        FutureBuilder<_ActivityData>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: EmptyState(
                  icon: Icons.error_outline,
                  message: friendlyError(snapshot.error!),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final data = snapshot.data!;
            final debt = data.supplierDebt;
            final body = _ActivityBody(
              data: data,
              filter: current,
              query: query,
              onOpen: _open,
              titularName: personal ? data.titularName : null,
            );
            if (!personal || debt == null) return body;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                _SuppliersBanner(
                  debt: debt,
                  onTap: () => _open(context.push(indProvidersPath)),
                ),
                body,
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Una operación del historial.
class _Entry {
  _Entry({
    required this.key,
    required this.when,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
    required this.search,
    required this.open,
    this.amount,
    this.badge,
    this.reversed = false,
  });

  final String key;
  final DateTime? when;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String subtitle;
  final String search;

  /// Abre la pantalla de la operación.
  final Future<Object?> Function(BuildContext context) open;
  final String? amount;
  final StatusBadge? badge;
  final bool reversed;
}

DateTime? _parse(Object? value) =>
    value == null ? null : DateTime.tryParse('$value')?.toLocal();

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// «5 nov» (con el año si no es el de hoy).
String _shortDay(DateTime? d) {
  if (d == null) return 'Sin fecha';
  final month = _months[d.month - 1].substring(0, 3);
  final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return '${d.day} $month$year';
}

/// «Noviembre» o «Noviembre 2025».
String _monthLabel(DateTime? d) {
  if (d == null) return 'Sin fecha';
  final name = _months[d.month - 1];
  final title = '${name[0].toUpperCase()}${name.substring(1)}';
  return d.year == DateTime.now().year ? title : '$title ${d.year}';
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Estado del pago al proveedor de una compra, con texto (no sólo color).
StatusBadge _purchaseBadge(_Row row) {
  if (row['status'] == 'REVERSED') {
    return const StatusBadge(label: 'Revertida', tone: BadgeTone.neutral);
  }
  final total = row['total_bob_minor']! as int;
  final paid = row['paid_bob_minor']! as int;
  if (paid <= 0) {
    return const StatusBadge(label: 'Sin pagar', tone: BadgeTone.review);
  }
  if (paid < total) {
    return StatusBadge(
      label: 'Pagó ${splitBob(paid).number}',
      tone: BadgeTone.review,
    );
  }
  return const StatusBadge(label: 'Pagada', tone: BadgeTone.ok);
}

class _ActivityBody extends StatelessWidget {
  const _ActivityBody({
    required this.data,
    required this.filter,
    required this.query,
    required this.onOpen,
    this.titularName,
  });

  final _ActivityData data;
  final _Filter filter;
  final String query;
  final void Function(Future<Object?> navigation) onOpen;

  /// Modo individual: el titular, cuyo nombre no se repite en cada fila.
  final String? titularName;

  /// «Chaco Norte» si la persona es el titular (modo individual); si no,
  /// «Chaco Norte · Beto».
  String _withPerson(Object? place, Object? person) =>
      titularName != null && person == titularName
      ? '$place'
      : '$place · $person';

  ({List<_Entry> entries, bool truncated}) _entries() {
    final entries = <_Entry>[];
    if (filter == _Filter.all || filter == _Filter.purchases) {
      for (final row in data.purchases) {
        final items = row['item_count'] as int? ?? 0;
        entries.add(
          _Entry(
            key: 'activity-purchase-${row['id']}',
            when: _parse(row['purchase_date']),
            icon: Icons.shopping_bag_outlined,
            iconBg: AgroColors.lime,
            iconFg: AgroColors.ink,
            title: '${row['supplier_name']}',
            subtitle:
                '${_shortDay(_parse(row['purchase_date']))} · Compra · '
                '${_plural(items, 'producto', 'productos')}',
            search:
                '${row['supplier_name']} ${row['invoice_number'] ?? ''} '
                '${row['campaign_name']}',
            open: (c) => c.push('/compras/detalle/${row['id']}'),
            amount: formatBob(row['total_bob_minor']! as int),
            badge: _purchaseBadge(row),
            reversed: row['status'] == 'REVERSED',
          ),
        );
      }
    }
    if (filter == _Filter.all || filter == _Filter.applications) {
      for (final row in data.applications) {
        final items = formatItemsSummary(row['items_summary']);
        final reversed = row['status'] == 'REVERSED';
        entries.add(
          _Entry(
            key: 'activity-application-${row['id']}',
            when: _parse(row['applied_at']),
            icon: Icons.spa_outlined,
            iconBg: AgroColors.ink,
            iconFg: AgroColors.lime,
            title: _withPerson(row['farm_name'], row['person_name']),
            subtitle: [
              _shortDay(_parse(row['applied_at'])),
              'Aplicación',
              if (items.isNotEmpty) items,
            ].join(' · '),
            search:
                '${row['farm_name']} ${row['person_name']} $items '
                '${row['campaign_name']}',
            open: (c) => c.push('/aplicaciones'),
            // UIBUG-010: el importe de una aplicación revertida se tacha.
            amount: formatBob(row['total_cost_bob_minor']! as int),
            badge: reversed
                ? const StatusBadge(label: 'Revertida', tone: BadgeTone.neutral)
                : null,
            reversed: reversed,
          ),
        );
      }
    }
    if (data.transfersShown &&
        (filter == _Filter.all || filter == _Filter.transfers)) {
      for (final row in data.transfers) {
        final items = formatItemsSummary(row['products_summary']);
        final reversed = row['status'] == 'REVERSED';
        entries.add(
          _Entry(
            key: 'activity-transfer-${row['id']}',
            when: _parse(row['transfer_date']),
            icon: Icons.swap_horiz,
            iconBg: AgroColors.chip,
            iconFg: AgroColors.ink,
            title: '${row['from_person_name']} → ${row['to_person_name']}',
            subtitle: [
              _shortDay(_parse(row['transfer_date'])),
              'Transferencia',
              if (items.isNotEmpty) items,
            ].join(' · '),
            search:
                '${row['from_person_name']} ${row['to_person_name']} $items',
            open: (c) => c.push('/transferencias'),
            // Una transferencia no genera deuda: no se muestra importe.
            badge: reversed
                ? const StatusBadge(label: 'Revertida', tone: BadgeTone.neutral)
                : null,
            reversed: reversed,
          ),
        );
      }
    }
    // Corte: si una lista llegó a su límite, lo anterior a su fecha más
    // antigua puede estar incompleto en las demás.
    DateTime? cutoff;
    void limitBy(List<_Row> rows, int limit, String dateKey) {
      if (rows.length < limit || rows.isEmpty) return;
      final oldest = rows
          .map((r) => _parse(r[dateKey]))
          .whereType<DateTime>()
          .fold<DateTime?>(null, (m, d) => m == null || d.isBefore(m) ? d : m);
      if (oldest != null && (cutoff == null || oldest.isAfter(cutoff!))) {
        cutoff = oldest;
      }
    }

    if (filter == _Filter.all) {
      limitBy(data.purchases, _purchaseLimit, 'purchase_date');
      limitBy(data.applications, _applicationLimit, 'applied_at');
      if (data.transfersShown) {
        limitBy(data.transfers, _transferLimit, 'transfer_date');
      }
    }
    final visible = entries.where((e) {
      if (cutoff != null && e.when != null && e.when!.isBefore(cutoff!)) {
        return false;
      }
      return query.isEmpty || matchesSearch(e.search, query);
    }).toList();
    visible.sort((a, b) {
      final x = a.when, y = b.when;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return (entries: visible, truncated: cutoff != null);
  }

  @override
  Widget build(BuildContext context) {
    final built = filter == _Filter.plans
        ? (entries: <_Entry>[], truncated: false)
        : _entries();
    final entries = built.entries;
    final truncated = built.truncated;
    final plans = _groupPlans(data.plans);
    final showPlans =
        (filter == _Filter.all || filter == _Filter.plans) &&
        plans.isNotEmpty &&
        query.isEmpty;
    final children = <Widget>[
      if (showPlans) ...[
        const GroupLabel('Por hacer'),
        for (final plan in plans) ...[
          _PlanCard(plan: plan, onOpen: onOpen, titularName: titularName),
          const SizedBox(height: 8),
        ],
      ] else if (filter == _Filter.plans && query.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: EmptyState(
            icon: Icons.event_note_outlined,
            message: 'No hay planes pendientes.',
          ),
        ),
    ];
    if (filter != _Filter.plans) {
      if (entries.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: EmptyState(
              icon: query.isEmpty
                  ? Icons.history_outlined
                  : Icons.search_off_outlined,
              message: query.isNotEmpty
                  ? 'Nada coincide con "$query".'
                  : switch (filter) {
                      _Filter.purchases => 'No hay compras confirmadas.',
                      _Filter.applications => 'No hay aplicaciones.',
                      _Filter.transfers => 'No hay transferencias.',
                      _ =>
                        data.transfersShown
                            ? 'Aún no hay compras, aplicaciones ni '
                                  'transferencias.'
                            : 'Aún no hay compras ni aplicaciones.',
                    },
            ),
          ),
        );
      } else {
        String? month;
        var group = <Widget>[];
        void flush() {
          if (group.isEmpty) return;
          children
            ..add(GroupLabel(month!))
            ..add(AgroGroup(children: group));
          group = <Widget>[];
        }

        for (final entry in entries) {
          final label = _monthLabel(entry.when);
          if (label != month) {
            flush();
            month = label;
          }
          group.add(_EntryRow(entry: entry, onOpen: onOpen));
        }
        flush();
        if (truncated) {
          children.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text(
                'Lo anterior está en la lista de cada tipo.',
                key: Key('activity-truncated'),
                style: AgroText.detail,
              ),
            ),
          );
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Un plan pendiente con sus productos.
typedef _Plan = ({
  int id,
  String farm,
  String owner,
  String? plannedDate,
  List<String> items,
});

List<_Plan> _groupPlans(List<_Row> rows) {
  final byId = <int, _Plan>{};
  for (final row in rows) {
    final id = row['plan_id']! as int;
    final item =
        '${row['product_name']} '
        '${formatQuantity(row['required_quantity_base']! as int, '${row['unit']}')}';
    final existing = byId[id];
    byId[id] = (
      id: id,
      farm: '${row['farm_name']}',
      owner: '${row['owner_name']}',
      plannedDate: row['planned_date'] as String?,
      items: [...?existing?.items, item],
    );
  }
  return byId.values.toList();
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onOpen, this.titularName});
  final _Plan plan;
  final void Function(Future<Object?> navigation) onOpen;

  /// Modo individual: un plan del titular no repite su nombre.
  final String? titularName;

  @override
  Widget build(BuildContext context) {
    final applyButton = FilledButton(
      key: Key('activity-apply-plan-${plan.id}'),
      style: FilledButton.styleFrom(
        backgroundColor: AgroColors.lime,
        foregroundColor: AgroColors.ink,
        minimumSize: const Size(0, 44),
        shape: const StadiumBorder(),
      ),
      // El mismo formulario que «Aplicar» en Planificación (sesión A).
      onPressed: () =>
          onOpen(context.push('/aplicaciones/nueva?planId=${plan.id}')),
      child: const Text(
        'Aplicar',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    return Material(
      color: AgroColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: Key('activity-plan-${plan.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => onOpen(context.push('/planificacion')),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconCircle(icon: Icons.event_note_outlined),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plan · ${plan.farm}',
                          style: const TextStyle(
                            fontSize: 16,
                            height: 21 / 16,
                            fontWeight: FontWeight.w700,
                            color: AgroColors.ink,
                          ),
                        ),
                        Text(
                          [
                            if (titularName == null ||
                                plan.owner != titularName)
                              plan.owner,
                            ...plan.items,
                            if (plan.plannedDate != null)
                              'para el ${formatDate(plan.plannedDate)}',
                          ].join(' · '),
                          style: AgroText.detail,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              applyButton,
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onOpen});
  final _Entry entry;
  final void Function(Future<Object?> navigation) onOpen;

  @override
  Widget build(BuildContext context) {
    final amount = entry.amount;
    final trailing = (amount != null || entry.badge != null)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (amount != null)
                Text(
                  amount,
                  style: AgroText.amount.copyWith(
                    decoration: entry.reversed
                        ? TextDecoration.lineThrough
                        : null,
                    color: entry.reversed ? AgroColors.muted : null,
                  ),
                ),
              if (entry.badge != null) ...[
                const SizedBox(height: 4),
                entry.badge!,
              ],
            ],
          )
        : null;
    return InkWell(
      key: Key(entry.key),
      onTap: () => onOpen(entry.open(context)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 21 / 16,
                    fontWeight: FontWeight.w700,
                    color: AgroColors.ink,
                  ),
                ),
                Text(entry.subtitle, style: AgroText.detail),
              ],
            );
            final icon = IconCircle(
              icon: entry.icon,
              background: entry.iconBg,
              foreground: entry.iconFg,
            );
            // Si al nombre le quedarían menos de 150 dp, el importe baja
            // debajo del texto, alineado a la derecha (letra grande, 360 dp).
            final amountWidth = amount == null
                ? 0.0
                : measureText(context, amount, AgroText.amount);
            final narrow =
                constraints.maxWidth - 40 - 12 - 8 - amountWidth < 150;
            if (trailing == null || !narrow) {
              return Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// «Proveedores y saldos» (lámina I-04): lo que se debe a proveedores, de
/// todas las campañas, y el acceso a pagarlo. La misma cifra que Inicio.
class _SuppliersBanner extends StatelessWidget {
  const _SuppliersBanner({required this.debt, required this.onTap});
  final SupplierDebt debt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AgroColors.ink,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      key: const Key('activity-suppliers'),
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Proveedores y saldos',
                    style: TextStyle(
                      fontSize: 18,
                      height: 24 / 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    supplierDebtLine(debt),
                    style: const TextStyle(
                      fontSize: 15,
                      color: AgroColors.onInkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AgroColors.lime),
          ],
        ),
      ),
    ),
  );
}
