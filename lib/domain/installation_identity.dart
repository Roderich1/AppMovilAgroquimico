enum InstallationIdentityStatus { ready, corrupt, unavailable }

class InstallationIdentityInitialization {
  const InstallationIdentityInitialization(this.status);

  final InstallationIdentityStatus status;

  bool get isReady => status == InstallationIdentityStatus.ready;
}

typedef InstallationIdentityDiagnostic = void Function(String message);
