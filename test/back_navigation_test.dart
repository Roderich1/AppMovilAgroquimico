import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _DirtyFormHarness()),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('Back limpio cierra exactamente una pantalla', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Formulario'), findsNothing);
  });

  testWidgets('Back dirty permite seguir editando o descartar', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'cambio');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar cambios?'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Formulario'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Replica aislada del contrato PopScope compartido por los formularios V5.
class _DirtyFormHarness extends StatefulWidget {
  const _DirtyFormHarness();

  @override
  State<_DirtyFormHarness> createState() => _DirtyFormHarnessState();
}

class _DirtyFormHarnessState extends State<_DirtyFormHarness> {
  bool dirty = false;

  Future<bool> discard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> close() async {
    if (!dirty || await discard()) {
      if (!mounted) return;
      setState(() => dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: close,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Formulario'),
      ),
      body: TextField(onChanged: (_) => setState(() => dirty = true)),
    ),
  );
}
