import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/installation_access.dart';
import '../../installation_access.dart';
import '../../services/auth/existing_session_providers.dart';

/// Pantalla de la política de activación cuando la instalación no puede
/// operar todavía (#76). Muestra la condición y la acción permitida. No ofrece
/// ningún restablecimiento que borre datos, sesión o identidad.
class AccessStatusScreen extends ConsumerWidget {
  const AccessStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(installationAccessProvider);
    final session = ref.watch(effectiveLocalSessionProvider);
    final scope = ref.read(installationAccessProvider.notifier).sessionScope;
    return Scaffold(
      appBar: AppBar(title: const Text('Agrocuentas')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: access == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Verificando el estado de la instalación…',
                          key: Key('access-loading'),
                        ),
                        SizedBox(height: 12),
                        _RetryButton(),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_outlined, size: 54),
                        const SizedBox(height: 16),
                        Text(
                          access.message,
                          key: const Key('access-status-message'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        if (session.allowsFirstActivation &&
                            !access.allowsOwnerBinding)
                          FilledButton.icon(
                            key: const Key('access-activate'),
                            onPressed: () => context.go('/activar'),
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('Activar en línea'),
                          ),
                        if (access.allowsOwnerBinding && scope != null)
                          FilledButton.icon(
                            key: const Key('access-choose-owner'),
                            onPressed: () => context.go('/titular'),
                            icon: const Icon(Icons.person_pin_outlined),
                            label: const Text('Elegir titular'),
                          ),
                        if (access ==
                                InstallationAccessState.identityMismatch ||
                            access ==
                                InstallationAccessState
                                    .sessionDamagedNotActivated)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Esta condición requiere revisión. Los datos '
                              'quedan intactos en este dispositivo.',
                              key: Key('access-needs-review'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryButton extends ConsumerWidget {
  const _RetryButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    key: const Key('access-retry'),
    onPressed: () => ref.read(installationAccessProvider.notifier).refresh(),
    child: const Text('Reintentar'),
  );
}
