import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'existing_session_startup.dart';

/// main.dart overrides this with the completed local read before runApp.
/// Missing wiring fails closed for activation without blocking SQLite.
final existingSessionStartupProvider = Provider<ExistingSessionStartupState>(
  (ref) => ExistingSessionStartupState.unavailable,
);
