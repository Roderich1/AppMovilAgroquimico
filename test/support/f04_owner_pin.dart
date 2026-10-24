// PIN del titular para las pruebas de RF-13/RF-03: la credencial y la
// acreditación en línea que acepta son la misma instancia, como en la app.
import 'package:agroquimicos/services/auth/local_owner_credential.dart';

class MemoryCredentialStorage implements CredentialStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class TestOwnerPin {
  TestOwnerPin._(this.binding, this.verification, this.credential);

  /// Credencial sin PIN (la acreditación en línea nunca se concede).
  static LocalOwnerCredential unenrolled() => LocalOwnerCredential(
    storage: MemoryCredentialStorage(),
    onlineVerification: OwnerOnlineVerification(
      reauthenticate: (_, __) async => false,
      readSessionScope: () async => null,
    ),
    iterations: 1000,
  );

  /// Credencial con [pin] enrolado para [binding].
  static Future<TestOwnerPin> enrolled(
    OwnerBindingContext binding, {
    String pin = '284917',
  }) async {
    final verification = OwnerOnlineVerification(
      reauthenticate: (_, __) async => true,
      readSessionScope: () async => binding.scope,
    );
    final owner = TestOwnerPin._(
      binding,
      verification,
      LocalOwnerCredential(
        storage: MemoryCredentialStorage(),
        onlineVerification: verification,
        iterations: 1000,
      ),
    );
    await owner.reset(pin);
    return owner;
  }

  final OwnerBindingContext binding;
  final OwnerOnlineVerification verification;
  final LocalOwnerCredential credential;

  /// Enrola o restablece el PIN con una acreditación en línea nueva.
  Future<void> reset(String pin) async => credential.enroll(
    pin: pin,
    pinConfirmation: pin,
    proof: await verification.verify(
      email: 'e',
      password: 'p',
      binding: binding,
    ),
    binding: binding,
  );

  Future<String?> enrolment() => credential.currentEnrolmentId();
}
