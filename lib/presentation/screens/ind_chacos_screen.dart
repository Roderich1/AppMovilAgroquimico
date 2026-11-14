// Modo individual — pestaña «Chacos» (láminas I-40 y I-43; sesión C,
// 2026-11-13).
//
// Lista de chacos del titular con su actividad en la campaña activa, el costo
// aplicado de esa campaña (abre «Costos», I-42) y el alta de chacos con el
// mismo diálogo y la misma escritura que Datos (`createFarmFromDialog`). En
// el modo con varias personas la ruta sigue existiendo y lista todos los
// chacos con su propietario; su barra no la muestra (los chacos siguen bajo
// Personas).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/ind_c_chacos_reads.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';
import '../widgets/ind_c_chacos_ui.dart';
import '../widgets/rdm_b_ui.dart' show RdmScrollPage, ScreenTitleBar, splitBob;
import 'ind_c_chaco_costs_screen.dart';

class ChacosScreen extends ConsumerStatefulWidget {
  const ChacosScreen({super.key});

  @override
  ConsumerState<ChacosScreen> createState() => _ChacosScreenState();
}

class _ChacosScreenState extends ConsumerState<ChacosScreen> {
  late Future<IndCChacos> data = _load();

  Future<IndCChacos> _load() =>
      ref.read(repositoryProvider).indCChacos(useActiveCampaign: true);

  void _refresh() {
    if (!mounted) return;
    setState(() {
      data = _load();
    });
  }

  Future<void> _add() async {
    final id = await createFarmFromDialog(
      context,
      ref.read(repositoryProvider),
    );
    if (id != null) _refresh();
  }

  Future<void> _open(int farmId) async {
    await GoRouter.maybeOf(context)?.push('/chacos/$farmId');
    _refresh();
  }

  Future<void> _costs(IndCCampaign? campaign) async {
    await openIndCCosts(context, campaignId: campaign?.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Un cambio de modo con la pantalla abierta cambia qué chacos se ven.
    ref.listen(operationModeProvider, (previous, next) {
      if (previous != next) _refresh();
    });
    return FutureBuilder<IndCChacos>(
      future: data,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        final farms = loaded?.activeFarms ?? const <IndCFarm>[];
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: RdmScrollPage(
            children: [
              ScreenTitleBar(
                title: 'Chacos',
                actions: [
                  if (farms.isNotEmpty)
                    CircleIconButton(
                      key: const Key('ind-chacos-nuevo'),
                      icon: Icons.add,
                      tooltip: 'Agregar chaco',
                      background: AgroColors.ink,
                      foreground: AgroColors.lime,
                      onPressed: _add,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                EmptyState(
                  icon: Icons.error_outline,
                  message: friendlyError(snapshot.error!),
                )
              else if (loaded == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (farms.isEmpty && loaded.farms.isEmpty)
                IndCNoFarms(onAdd: _add)
              else ...[
                IndCDarkFigureCard(
                  key: const Key('ind-chacos-costos'),
                  label: 'Costos · ${_scopeLabel(loaded.campaign)}',
                  number: loaded.applicationCount == 0
                      ? null
                      : splitBob(loaded.appliedCostMinor).number,
                  numberKey: const Key('ind-chacos-costos-total'),
                  emptyText: loaded.campaign == null
                      ? 'Todavía no hay aplicaciones'
                      : 'Todavía no hay aplicaciones en esta campaña',
                  note: 'Por chaco, por producto y por campaña',
                  onTap: () => _costs(loaded.campaign),
                ),
                const SizedBox(height: 16),
                if (farms.isEmpty)
                  // Sólo hay chacos archivados con aplicaciones en el alcance.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No hay chacos activos.',
                            style: AgroText.value,
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _add,
                            child: const Text('Agregar chaco'),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final farm in farms)
                  IndCFarmCard(
                    farm: farm,
                    campaign: loaded.campaign,
                    showOwner: !loaded.scope.personal,
                    onTap: () => _open(farm.farmId),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _scopeLabel(IndCCampaign? campaign) =>
      campaign?.name ?? 'todas las campañas';
}
