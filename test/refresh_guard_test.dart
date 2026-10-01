import 'dart:io';

import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/refresh_guard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var persisted = false;
  var failSet = false;
  var failClear = false;

  setUp(() {
    persisted = false;
    failSet = false;
    failClear = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readRefreshGuard':
          return persisted;
        case 'setRefreshGuard':
          if (persisted || failSet) throw PlatformException(code: 'STORAGE');
          persisted = true;
          return true;
        case 'clearRefreshGuard':
          if (!persisted || failClear) throw PlatformException(code: 'STORAGE');
          persisted = false;
          return false;
      }
      throw MissingPluginException();
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'clear, set, recreated wrapper read, and clear use dedicated methods',
    () async {
      const first = AndroidRefreshGuard(channel: channel);
      expect(await first.isQuarantined(), isFalse);
      await first.quarantine();
      const recreated = AndroidRefreshGuard(channel: channel);
      expect(await recreated.isQuarantined(), isTrue);
      await recreated.clear();
      expect(await first.isQuarantined(), isFalse);
    },
  );

  test('failed set and clear never report a successful transition', () async {
    const guard = AndroidRefreshGuard(channel: channel);
    failSet = true;
    await expectLater(guard.quarantine(), throwsA(isA<PlatformException>()));
    expect(persisted, isFalse);
    failSet = false;
    await guard.quarantine();
    failClear = true;
    await expectLater(guard.clear(), throwsA(isA<PlatformException>()));
    expect(persisted, isTrue);
  });

  test('second set is rejected across wrapper instances', () async {
    const first = AndroidRefreshGuard(channel: channel);
    const second = AndroidRefreshGuard(channel: channel);
    await first.quarantine();
    await expectLater(second.quarantine(), throwsA(isA<PlatformException>()));
    expect(await second.isQuarantined(), isTrue);
  });

  test(
    'pointer preferences holding guard remain excluded from all backups',
    () {
      final pre12 = File('android/app/src/main/res/xml/backup_rules.xml')
          .readAsStringSync();
      final modern = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      expect(pre12, contains('path="AgrocuentasSessionPointer.xml"'));
      expect(
        RegExp('path="AgrocuentasSessionPointer.xml"')
            .allMatches(modern)
            .length,
        2,
      );
    },
  );
}
