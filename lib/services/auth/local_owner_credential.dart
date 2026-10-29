// Credencial local del titular (PIN) — F03 §4 / RF-13
// (docs/architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md). Un solo mecanismo
// para autorizar sin red las acciones del titular (reversiones, revisión de
// operaciones tardías y, en F08, mostrar o rotar la clave del respaldo).
//
// - El PIN nunca se guarda ni se registra: sólo un verificador PBKDF2 en el
//   almacén seguro de Android, en su propio espacio de nombres. Nunca en
//   SQLite ni en un respaldo. Nunca se borran otros espacios (no deleteAll).
// - El PIN no se usa como clave de nada: sólo autoriza.
// - Enrolar o restablecer exige acreditar en línea al mismo titular.
// - Cada autorización es de un solo uso, de vida corta y ligada a un
//   propósito, un objeto y el vínculo de titular vigente al consumirla.
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/installation_access.dart' show OwnerScope;
import 'activation_owner_evidence.dart';

/// Para qué se autoriza (F03 §4).
enum AuthorizationPurpose {
  reversePurchase('REVERSE_PURCHASE'),
  reverseApplication('REVERSE_APPLICATION'),
  reverseTransfer('REVERSE_TRANSFER'),
  confirmLateOperation('CONFIRM_LATE_OPERATION'),
  rejectLateOperation('REJECT_LATE_OPERATION'),
  showBackupRecoveryKey('SHOW_BACKUP_RECOVERY_KEY'),
  rotateBackupRecoveryKey('ROTATE_BACKUP_RECOVERY_KEY');

  const AuthorizationPurpose(this.code);
  final String code;
}

/// El vínculo de titular vigente (de SQLite) contra el que se enrola, se
/// verifica y se consume una autorización.
class OwnerBindingContext {
  const OwnerBindingContext({
    required this.bindingId,
    required this.personId,
    required this.scope,
  });

  final int bindingId;
  final int personId;
  final OwnerScope scope;
}

enum CredentialState {
  notEnrolled,
  enrolled,
  locked,
  requiresOnlineReset,

  /// El verificador pertenece a otro Member o tenant (p. ej. tras restaurar
  /// una base de otro titular): no vale; hay que enrolar de nuevo.
  scopeMismatch,
}

class CredentialStatus {
  const CredentialStatus(this.state, {this.lockedUntil});

  final CredentialState state;
  final DateTime? lockedUntil;

  bool get canVerify => state == CredentialState.enrolled;
}

/// De dónde sale un [OnlineOwnerProof] (F03 §4, interfaz).
enum _ProofOrigin {
  /// Contraseña de la cuenta en `/titular/pin` (§9): enrola o restablece.
  password,

  /// Acreditación de activación (§4 bis): sólo el primer PIN del titular.
  activation,
}

/// Comprobante de un solo uso de que el titular se acreditó en línea en esta
/// instalación (mismo Member y tenant). Lo emite sólo
/// [OwnerOnlineVerification]; vence a los 5 minutos y, si viene de la
/// activación, nunca después de la acreditación. Recuerda quién lo emitió:
/// una credencial sólo acepta los de su propia acreditación configurada.
class OnlineOwnerProof {
  OnlineOwnerProof._(
    this.scope,
    this.issuedAt,
    this._issuer, {
    _ProofOrigin origin = _ProofOrigin.password,
    DateTime? notAfter,
    int? bindingId,
    int? personId,
  }) : _origin = origin,
       _notAfter = notAfter,
       _bindingId = bindingId,
       _personId = personId;

  final OwnerScope scope;
  final DateTime issuedAt;
  final OwnerOnlineVerification _issuer;
  final _ProofOrigin _origin;
  final DateTime? _notAfter;

  /// Sólo en los de activación: el vínculo exacto con el que se emitió, que
  /// [LocalOwnerCredential.enroll] vuelve a comparar (comprobación 5).
  final int? _bindingId;
  final int? _personId;
  bool _used = false;

  @override
  String toString() => 'OnlineOwnerProof(redacted)';
}

/// Acreditación en línea del titular para enrolar o restablecer el PIN: un
/// login de la misma cuenta, Member y tenant que la sesión guardada, que se
/// cierra en el acto sin tocarla ([confirmAccount]), y después la sesión
/// releída con el mismo Member y tenant que el vínculo. Sólo entonces emite
/// el comprobante. Sin red no hay comprobante.
class OwnerOnlineVerification {
  OwnerOnlineVerification({
    required Future<bool> Function(String email, String password)
    confirmAccount,
    required Future<OwnerScope?> Function() readSessionScope,
    DateTime Function()? clock,
    ActivationEvidenceSource? activation,
  }) : _confirmAccount = confirmAccount,
       _readSessionScope = readSessionScope,
       _clock = clock ?? DateTime.now,
       _activation = activation;

  final Future<bool> Function(String email, String password) _confirmAccount;
  final Future<OwnerScope?> Function() _readSessionScope;
  final DateTime Function() _clock;
  final ActivationEvidenceSource? _activation;

  /// null si la cuenta no se acreditó o no es la del titular de [binding].
  Future<OnlineOwnerProof?> verify({
    required String email,
    required String password,
    required OwnerBindingContext binding,
  }) async {
    if (!await _confirmAccount(email, password)) return null;
    final scope = await _readSessionScope();
    if (scope == null || scope != binding.scope) return null;
    return OnlineOwnerProof._(scope, _clock(), this);
  }

  /// F03 §4 bis.4: comprobante del primer PIN del titular a partir de la
  /// acreditación de activación, sin contraseña ni red. La retira primero, de
  /// forma síncrona (un solo uso), y después comprueba vigencia, sesión,
  /// instalación, vínculo y acceso. null ante cualquier diferencia, error o
  /// dependencia ausente (falla cerrado). La comprobación 7 (que el titular no
  /// tenga ya un PIN propio) la hace la credencial dentro de su cola.
  Future<OnlineOwnerProof?> fromActivation({
    required OwnerBindingContext binding,
  }) async {
    final source = _activation;
    final take = source?.take;
    if (source == null || take == null) return null;
    final evidence = take();
    final readSession = source.readSessionIdentity;
    final currentRef = source.currentInstallationRef;
    final activatedRef = source.activatedInstallationRef;
    final activeBinding = source.activeBinding;
    final accessActivated = source.accessActivated;
    if (evidence == null ||
        readSession == null ||
        currentRef == null ||
        activatedRef == null ||
        activeBinding == null ||
        accessActivated == null) {
      return null;
    }
    try {
      if (!evidence.isFresh(_clock())) return null;
      final attached = evidence.binding;
      if (attached == null ||
          attached.bindingId != binding.bindingId ||
          attached.personId != binding.personId ||
          attached.scope != binding.scope ||
          evidence.scope != binding.scope) {
        return null;
      }
      if (!accessActivated()) return null;
      final session = await readSession();
      if (session == null || !session.sameAs(evidence.identity)) return null;
      final installation = currentRef();
      if (installation == null || installation != evidence.installationRef) {
        return null;
      }
      if (await activatedRef() != installation) return null;
      final active = await activeBinding();
      if (active == null || !active.active || !active.sameAs(attached)) {
        return null;
      }
      final now = _clock();
      if (!accessActivated() || !evidence.isFresh(now)) return null;
      return OnlineOwnerProof._(
        binding.scope,
        now,
        this,
        origin: _ProofOrigin.activation,
        notAfter: evidence.notAfter,
        bindingId: binding.bindingId,
        personId: binding.personId,
      );
    } on Object {
      return null;
    }
  }
}

/// De dónde lee [OwnerOnlineVerification.fromActivation] (F03 §4 bis.4). Si
/// falta cualquiera, no hay comprobante (H8).
class ActivationEvidenceSource {
  const ActivationEvidenceSource({
    this.take,
    this.readSessionIdentity,
    this.currentInstallationRef,
    this.activatedInstallationRef,
    this.activeBinding,
    this.accessActivated,
  });

  /// Retira la acreditación: síncrona, sin ningún await entre leerla y
  /// anularla.
  final ActivationOwnerEvidence? Function()? take;
  final Future<SessionIdentity?> Function()? readSessionIdentity;
  final String? Function()? currentInstallationRef;
  final Future<String?> Function()? activatedInstallationRef;
  final Future<ActivationBindingRef?> Function()? activeBinding;
  final bool Function()? accessActivated;
}

/// Autorización del titular: un solo uso, 120 s, propósito y objeto fijos.
/// Sólo la crea [LocalOwnerCredential.verify]. No contiene el PIN. Recuerda,
/// en privado, el almacén que la emitió (R3 de B): [enrolmentId] no es un
/// secreto (está en la auditoría y en los respaldos), así que no basta.
class OwnerAuthorization {
  OwnerAuthorization._({
    required this.id,
    required this.purpose,
    required this.subjectRef,
    required this.enrolmentId,
    required this.bindingId,
    required this.personId,
    required this.scope,
    required this.verifiedAt,
    required CredentialStorage issuer,
  }) : _issuer = issuer;

  final CredentialStorage _issuer;

  final String id;
  final AuthorizationPurpose purpose;
  final String subjectRef;
  final String enrolmentId;
  final int bindingId;
  final int personId;
  final OwnerScope scope;
  final DateTime verifiedAt;

  /// Método de verificación que queda en la auditoría.
  String get method => 'LOCAL_PIN';

  static const lifetime = Duration(seconds: 120);

  DateTime get expiresAt => verifiedAt.add(lifetime);

  @override
  String toString() => 'OwnerAuthorization(${purpose.code}, redacted)';
}

class CredentialException implements Exception {
  const CredentialException(this.message);
  final String message;

  @override
  String toString() => 'CredentialException($message)';
}

/// Una autorización ausente, vencida, ya usada, de otro propósito u objeto,
/// emitida para otro vínculo que el vigente (p. ej. antes de una restauración)
/// o con un PIN que no es el configurado ahora en la instalación.
class OwnerAuthorizationRejected implements Exception {
  const OwnerAuthorizationRejected(this.reason);
  final String reason;

  @override
  String toString() => 'OwnerAuthorizationRejected($reason)';
}

/// Comprueba y consume [authorization] (R2 de C): una sola vez, dentro de su
/// vida, para [purpose] y [subjectRef], para el vínculo vigente [current] y
/// para la credencial de la instalación [installation], leídos justo antes de
/// la acción.
///
/// Esto último es lo que da autoridad a una autorización: tiene que haberla
/// emitido el almacén de la instalación con el PIN vigente
/// ([LocalOwnerCredential.accepts]). Una emitida sobre otro almacén, aunque
/// copie el enrolamiento, o antes de restablecer el PIN, se rechaza. Que
/// [OwnerAuthorization] tenga constructor privado no basta por sí solo.
void consumeOwnerAuthorization(
  OwnerAuthorization? authorization, {
  required LocalOwnerCredential? installation,
  required AuthorizationPurpose purpose,
  required String subjectRef,
  required OwnerBindingContext? current,
  required DateTime now,
}) {
  final auth = authorization;
  if (auth == null) {
    throw const OwnerAuthorizationRejected(
      'Falta la autorización del titular.',
    );
  }
  if (_consumed.contains(auth.id)) {
    throw const OwnerAuthorizationRejected('La autorización ya se usó.');
  }
  if (now.isAfter(auth.expiresAt) || now.isBefore(auth.verifiedAt)) {
    throw const OwnerAuthorizationRejected(
      'La autorización venció. Vuelva a confirmar con el PIN.',
    );
  }
  if (auth.purpose != purpose || auth.subjectRef != subjectRef) {
    throw const OwnerAuthorizationRejected(
      'La autorización corresponde a otra acción.',
    );
  }
  if (current == null ||
      current.bindingId != auth.bindingId ||
      current.personId != auth.personId ||
      current.scope != auth.scope) {
    throw const OwnerAuthorizationRejected(
      'El titular de estos datos cambió. Vuelva a confirmar con el PIN.',
    );
  }
  if (installation == null || !installation.accepts(auth)) {
    throw const OwnerAuthorizationRejected(
      'El PIN del titular cambió o no está configurado en este teléfono. '
      'Vuelva a confirmar con el PIN.',
    );
  }
  _consumed.add(auth.id);
}

final Set<String> _consumed = <String>{};

/// Almacén del verificador y del contador de intentos. Sólo sus dos claves.
abstract interface class CredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class AndroidCredentialStorage implements CredentialStorage {
  /// Uno solo por proceso: la cola de [LocalOwnerCredential] va con el objeto
  /// almacén, y dos objetos sobre el mismo espacio de nombres no se
  /// esperarían entre sí (nota de B a P1).
  factory AndroidCredentialStorage() => _instance;

  static final _instance = AndroidCredentialStorage._();

  AndroidCredentialStorage._()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          storageNamespace: LocalOwnerCredential.androidNamespace,
          resetOnError: false,
          migrateOnAlgorithmChange: false,
        ),
      );

  final FlutterSecureStorage _storage;

  // Nunca deleteAll(): otros almacenes (sesión, llavero del respaldo) viven
  // en sus propios espacios y sobreviven a todo lo que haga esta credencial.
  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Deriva el verificador (PBKDF2-HMAC-SHA256, 32 bytes), fuera del hilo de
/// la interfaz. Inyectable en pruebas.
typedef PinKdf = Future<List<int>> Function(
  String pin,
  List<int> salt,
  int iterations,
);

Future<List<int>> isolatePbkdf2(String pin, List<int> salt, int iterations) =>
    Isolate.run(() async {
      final key = await Pbkdf2.hmacSha256(
        iterations: iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: pin, nonce: salt);
      return key.extractBytes();
    });

/// Política de intentos (F03 §4): esperas crecientes desde el 5.º fallo
/// seguido; al 10.º, sólo el restablecimiento en línea.
Duration? lockoutAfter(int failures) {
  if (failures < 5) return null;
  return switch (failures) {
    5 => const Duration(seconds: 30),
    6 => const Duration(minutes: 2),
    _ => const Duration(minutes: 10),
  };
}

const int onlineResetAfterFailures = 10;

/// F03 §4 bis.2: ya había un PIN del titular y la activación no lo cambia.
const activationExistingPinMessage =
    'Ya hay un PIN del titular en este teléfono. Para cambiarlo, confirme su '
    'cuenta en línea en Operaciones › Más › PIN del titular.';

/// 6 dígitos, sin todos iguales ni secuencias ascendentes o descendentes.
String? pinProblem(String pin) {
  if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) {
    return 'El PIN debe tener 6 dígitos.';
  }
  final digits = pin.codeUnits.map((c) => c - 48).toList();
  if (digits.toSet().length == 1) return 'El PIN no puede repetir un dígito.';
  bool step(int delta) {
    for (var i = 1; i < digits.length; i++) {
      if (digits[i] - digits[i - 1] != delta) return false;
    }
    return true;
  }

  if (step(1) || step(-1)) return 'El PIN no puede ser una secuencia.';
  return null;
}

class LocalOwnerCredential {
  /// [onlineVerification] es la acreditación en línea de la app: [enroll]
  /// sólo acepta comprobantes emitidos por esa instancia, no por otra armada
  /// con funciones cualesquiera.
  LocalOwnerCredential({
    required CredentialStorage storage,
    required OwnerOnlineVerification onlineVerification,
    PinKdf kdf = isolatePbkdf2,
    this.iterations = defaultIterations,
    DateTime Function()? clock,
    Random? random,
  }) : _storage = storage,
       _onlineVerification = onlineVerification,
       _kdf = kdf,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const androidNamespace = 'agrocuentas_owner_credential_v1';
  static const defaultIterations = 210000;
  static const _verifierKey = 'verifier';
  static const _attemptsKey = 'attempts';
  static const _version = 1;

  /// Un solo enrolamiento o verificación a la vez por almacén (P1 de B): dos
  /// verify() en paralelo leerían el mismo contador y se perdería un fallo.
  /// La cola va con el objeto almacén, no con la instancia, para que dos
  /// instancias sobre el mismo almacén también se esperen; la app tiene un
  /// solo almacén por ProviderScope.
  static final _tails = Expando<Future<void>>('owner-credential-lock');

  /// El enrolamiento vigente de cada almacén según este proceso. Sólo lo
  /// publican los caminos de la cola (R1 de B): [verify], al leer el
  /// verificador antes de emitir, y [enroll], que lo borra antes de escribir
  /// el verificador nuevo y lo fija después (R2 de B). Mientras se
  /// restablece, o si la escritura falla, no vale nada. Una lectura fuera de
  /// la cola ([status], [currentEnrolmentId]) no lo toca: si empezó antes de
  /// un restablecimiento, no puede devolverle el PIN anterior.
  static final _enrolments = Expando<String>('owner-credential-enrolment');

  Future<T> _serialized<T>(Future<T> Function() body) {
    final run = (_tails[_storage] ?? Future<void>.value()).then((_) => body());
    _tails[_storage] = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  final CredentialStorage _storage;
  final OwnerOnlineVerification _onlineVerification;
  final PinKdf _kdf;
  final int iterations;
  final DateTime Function() _clock;
  final Random _random;

  Future<_Verifier?> _verifier({bool publish = false}) async {
    final raw = await _storage.read(_verifierKey);
    _Verifier? verifier;
    if (raw != null) {
      try {
        verifier = _Verifier.decode(raw);
      } on Object {
        // Un verificador ilegible no autoriza nada; se enrola de nuevo.
      }
    }
    if (publish) _enrolments[_storage] = verifier?.enrolmentId;
    return verifier;
  }

  Future<_Attempts> _attempts() async {
    final raw = await _storage.read(_attemptsKey);
    if (raw == null) return const _Attempts(0, null);
    try {
      return _Attempts.decode(raw);
    } on Object {
      // Un contador dañado no rebaja la protección: exige restablecer.
      return const _Attempts(onlineResetAfterFailures, null);
    }
  }

  /// Enrolamiento del PIN configurado ahora (null si no hay). Cambia al
  /// restablecer el PIN y es otro en cada instalación.
  Future<String?> currentEnrolmentId() async =>
      (await _verifier())?.enrolmentId;

  /// El enrolamiento vigente según este proceso, sin esperar al almacén. null
  /// si aún no se ha verificado ni enrolado, durante un restablecimiento o si
  /// no hay PIN; entonces nada se autoriza.
  String? get knownEnrolmentId => _enrolments[_storage];

  /// Si [authorization] la emitió este mismo almacén con el PIN vigente. Lo
  /// usa [consumeOwnerAuthorization], de forma síncrona.
  bool accepts(OwnerAuthorization authorization) {
    final known = _enrolments[_storage];
    return known != null &&
        identical(authorization._issuer, _storage) &&
        authorization.enrolmentId == known;
  }

  Future<CredentialStatus> status(OwnerBindingContext? binding) async {
    final verifier = await _verifier();
    if (verifier == null || binding == null) {
      return const CredentialStatus(CredentialState.notEnrolled);
    }
    if (verifier.scope != binding.scope) {
      return const CredentialStatus(CredentialState.scopeMismatch);
    }
    final attempts = await _attempts();
    if (attempts.failures >= onlineResetAfterFailures) {
      return const CredentialStatus(CredentialState.requiresOnlineReset);
    }
    final until = attempts.lockedUntil;
    if (until != null && until.isAfter(_clock())) {
      return CredentialStatus(CredentialState.locked, lockedUntil: until);
    }
    return const CredentialStatus(CredentialState.enrolled);
  }

  void _requireProof(OnlineOwnerProof? proof, OwnerBindingContext binding) {
    final now = _clock();
    final notAfter = proof?._notAfter;
    if (proof == null ||
        !identical(proof._issuer, _onlineVerification) ||
        proof._used ||
        proof.scope != binding.scope ||
        now.difference(proof.issuedAt) > const Duration(minutes: 5) ||
        now.isBefore(proof.issuedAt) ||
        (notAfter != null && now.isAfter(notAfter)) ||
        (proof._origin == _ProofOrigin.activation &&
            (proof._bindingId != binding.bindingId ||
                proof._personId != binding.personId))) {
      throw const CredentialException(
        'Hace falta acreditar en línea al titular antes de configurar el PIN.',
      );
    }
    proof._used = true;
  }

  /// Enrola o restablece (el mismo camino): exige el comprobante en línea del
  /// titular del vínculo vigente. Sustituye el verificador anterior y pone a
  /// cero los intentos. No toca ningún otro almacén.
  Future<void> enroll({
    required String pin,
    required String pinConfirmation,
    required OnlineOwnerProof? proof,
    required OwnerBindingContext binding,
  }) => _serialized(
    () => _enroll(
      pin: pin,
      pinConfirmation: pinConfirmation,
      proof: proof,
      binding: binding,
    ),
  );

  Future<void> _enroll({
    required String pin,
    required String pinConfirmation,
    required OnlineOwnerProof? proof,
    required OwnerBindingContext binding,
  }) async {
    final problem = pinProblem(pin);
    if (problem != null) throw CredentialException(problem);
    if (pin != pinConfirmation) {
      throw const CredentialException('Los dos PIN no coinciden.');
    }
    _requireProof(proof, binding);
    // F03 §4 bis.4, comprobación 7 (H1), dentro de la cola: la acreditación de
    // activación sólo crea el primer PIN del titular. Con un verificador
    // legible del mismo ámbito (enrolled, locked o requiresOnlineReset) se
    // rechaza sin escribir; cambiarlo exige la contraseña. Uno de otro Member
    // (scopeMismatch) o ilegible se sobrescribe, como al enrolar hoy.
    if (proof!._origin == _ProofOrigin.activation) {
      final existing = await _verifier();
      if (existing != null && existing.scope == binding.scope) {
        throw const CredentialException(activationExistingPinMessage);
      }
    }
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final hash = await _kdf(pin, salt, iterations);
    final verifier = _Verifier(
      salt: salt,
      iterations: iterations,
      hash: hash,
      scope: binding.scope,
      enrolmentId: _randomId(),
      enrolledAt: _clock().toUtc(),
    );
    _enrolments[_storage] = null;
    await _storage.write(_verifierKey, verifier.encode());
    _enrolments[_storage] = verifier.enrolmentId;
    await _storage.write(_attemptsKey, const _Attempts(0, null).encode());
  }

  /// Comprueba el PIN sin red y, si es correcto, emite una autorización de un
  /// solo uso. Cada fallo cuenta, también tras reiniciar la app.
  Future<OwnerAuthorization> verify({
    required String pin,
    required AuthorizationPurpose purpose,
    required String subjectRef,
    required OwnerBindingContext binding,
  }) => _serialized(
    () => _verify(
      pin: pin,
      purpose: purpose,
      subjectRef: subjectRef,
      binding: binding,
    ),
  );

  Future<OwnerAuthorization> _verify({
    required String pin,
    required AuthorizationPurpose purpose,
    required String subjectRef,
    required OwnerBindingContext binding,
  }) async {
    final current = await status(binding);
    switch (current.state) {
      case CredentialState.notEnrolled:
      case CredentialState.scopeMismatch:
        throw const CredentialException(
          'Configure el PIN del titular para autorizar esta acción.',
        );
      case CredentialState.requiresOnlineReset:
        throw const CredentialException(
          'El PIN quedó bloqueado. Restablézcalo acreditando al titular en línea.',
        );
      case CredentialState.locked:
        throw const CredentialException(
          'Demasiados intentos. Espere antes de volver a intentarlo.',
        );
      case CredentialState.enrolled:
        break;
    }
    final verifier = (await _verifier(publish: true))!;
    // El intento se cuenta como fallo antes del KDF (P1 de B) y se deshace
    // sólo si el PIN es correcto: cerrar la app a mitad no deja un intento
    // sin contar.
    final failures = (await _attempts()).failures + 1;
    final wait = lockoutAfter(failures);
    await _storage.write(
      _attemptsKey,
      _Attempts(failures, wait == null ? null : _clock().add(wait)).encode(),
    );
    final candidate = await _kdf(pin, verifier.salt, verifier.iterations);
    if (!_constantTimeEquals(candidate, verifier.hash)) {
      throw CredentialException(
        failures >= onlineResetAfterFailures
            ? 'El PIN quedó bloqueado. Restablézcalo acreditando al titular en línea.'
            : 'PIN incorrecto.',
      );
    }
    await _storage.write(_attemptsKey, const _Attempts(0, null).encode());
    return OwnerAuthorization._(
      id: _randomId(),
      purpose: purpose,
      subjectRef: subjectRef,
      enrolmentId: verifier.enrolmentId,
      bindingId: binding.bindingId,
      personId: binding.personId,
      scope: binding.scope,
      verifiedAt: _clock(),
      issuer: _storage,
    );
  }

  String _randomId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

class _Verifier {
  const _Verifier({
    required this.salt,
    required this.iterations,
    required this.hash,
    required this.scope,
    required this.enrolmentId,
    required this.enrolledAt,
  });

  final List<int> salt;
  final int iterations;
  final List<int> hash;
  final OwnerScope scope;
  final String enrolmentId;
  final DateTime enrolledAt;

  String encode() => jsonEncode({
    'v': LocalOwnerCredential._version,
    'salt': base64Encode(salt),
    'iterations': iterations,
    'hash': base64Encode(hash),
    'memberId': scope.memberId,
    'tenantId': scope.tenantId,
    'enrolmentId': enrolmentId,
    'enrolledAt': enrolledAt.toIso8601String(),
  });

  static _Verifier decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['v'] != LocalOwnerCredential._version) {
      throw const FormatException('verifier version');
    }
    final iterations = json['iterations'] as int;
    if (iterations < 1) throw const FormatException('iterations');
    return _Verifier(
      salt: base64Decode(json['salt'] as String),
      iterations: iterations,
      hash: base64Decode(json['hash'] as String),
      scope: OwnerScope(
        memberId: json['memberId'] as String,
        tenantId: json['tenantId'] as String,
      ),
      enrolmentId: json['enrolmentId'] as String,
      enrolledAt: DateTime.parse(json['enrolledAt'] as String),
    );
  }
}

class _Attempts {
  const _Attempts(this.failures, this.lockedUntil);

  final int failures;
  final DateTime? lockedUntil;

  String encode() => jsonEncode({
    'failures': failures,
    'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
  });

  static _Attempts decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final until = json['lockedUntil'] as String?;
    return _Attempts(
      json['failures'] as int,
      until == null ? null : DateTime.parse(until),
    );
  }
}
