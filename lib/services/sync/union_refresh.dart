import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/owner_binding_store.dart';
import '../../domain/installation_access.dart'
    show InstallationAccessState, OwnerScope, installationReference;
import '../../domain/sync/central_references.dart';
import '../../installation_access.dart'
    show installationAccessProvider, installationRefProvider;
import '../../local_data_providers.dart' show databaseProvider;
import '../auth/existing_session_providers.dart'
    show runtimeSessionTransitionProvider;
import '../auth/remote_session_coordinator.dart';
import '../auth/remote_session_providers.dart';
import 'joint_purchase_sender.dart' show JointPurchaseListProblem;
import 'sync_access.dart';
import 'sync_api.dart';
import 'sync_providers.dart';
import 'sync_read.dart';

enum UnionFeed {
  calls(Duration(minutes: 1)),
  references(Duration(minutes: 5)),
  identification(Duration(minutes: 1));

  const UnionFeed(this.interval);
  final Duration interval;
}

enum UnionReadIssue { offline, unavailable, access, incompatible }

typedef UnionReadStatus = ({
  DateTime? lastRead,
  UnionReadIssue? issue,
  bool busy,
  CentralReferences? references,
});

const emptyUnionRead = (
  lastRead: null,
  issue: null,
  busy: false,
  references: null,
);

final unionRefreshProvider =
    NotifierProvider<UnionRefresh, Map<UnionFeed, UnionReadStatus>>(
      UnionRefresh.new,
    );

class UnionRefresh extends Notifier<Map<UnionFeed, UnionReadStatus>> {
  final _running = <UnionFeed, Future<void>>{};
  final _retryAt = <UnionFeed, DateTime>{};
  final _failures = <UnionFeed, int>{};
  Future<void>? _cacheLoad;
  Future<VerifiedAccess>? _verification;
  DateTime? _nextRenewalProbe;
  int? _generation;
  int _revision = 0;
  OwnerScope? _scope;

  @override
  Map<UnionFeed, UnionReadStatus> build() {
    ref.listen(runtimeSessionTransitionProvider, (_, _) => _reset());
    return {};
  }

  void _reset() {
    _revision++;
    _running.clear();
    _retryAt.clear();
    _failures.clear();
    _cacheLoad = null;
    _verification = null;
    _nextRenewalProbe = null;
    _scope = null;
    state = {};
  }

  void _update(
    UnionFeed feed, {
    UnionReadIssue? issue,
    bool busy = false,
    DateTime? lastRead,
    CentralReferences? references,
  }) {
    final previous = state[feed];
    state = {
      ...state,
      feed: (
        lastRead: lastRead ?? previous?.lastRead,
        issue: issue,
        busy: busy,
        references: references ?? previous?.references,
      ),
    };
  }

  Future<void> refresh(
    Set<UnionFeed> feeds, {
    bool manual = false,
    bool connected = true,
    bool reconnect = false,
    bool Function()? inForeground,
  }) async {
    final db = ref.read(databaseProvider);
    final holder = ref.read(syncAccessHolderProvider);
    final scope = holder.forUnionReads?.scope;
    if (_generation != db.replacement.generation ||
        (_scope != null && scope != null && scope != _scope)) {
      _generation = db.replacement.generation;
      _reset();
    }
    _scope = scope ?? _scope;
    if (db.replacement.isReplacing) return;
    final revision = _revision;
    bool current() =>
        ref.mounted &&
        revision == _revision &&
        identical(ref.read(databaseProvider), db) &&
        !db.replacement.isReplacing &&
        db.replacement.generation == _generation;

    await (_cacheLoad ??= _restoreCache(current));
    if (!current() || inForeground?.call() == false) return;
    if (!connected) {
      for (final feed in feeds) {
        if (!_running.containsKey(feed) &&
            state[feed]?.issue != UnionReadIssue.offline) {
          _update(feed, issue: UnionReadIssue.offline);
        }
      }
      return;
    }

    final now = DateTime.now();
    final due = feeds
        .where(
          (feed) =>
              manual || _due(feed, now) || (reconnect && !_justRead(feed, now)),
        )
        .toSet();
    if (due.isEmpty) return;

    final sync = ref.read(syncControllerProvider.notifier);
    var access = holder.forUnionReads;
    var missingAccess = UnionReadIssue.access;
    if (access == null && !manual && inForeground != null) {
      final retryAt = _nextRenewalProbe;
      if (!reconnect && retryAt != null && now.isBefore(retryAt)) return;
      final result = await _renewForReads(
        current: current,
        inForeground: inForeground,
      );
      if (!current() || !inForeground()) return;
      access = holder.forUnionReads;
      if (result?.phase == RemoteSessionPhase.offline) {
        _nextRenewalProbe = DateTime.now().add(const Duration(seconds: 30));
        missingAccess = UnionReadIssue.offline;
      } else if (result?.problem == RemoteSessionProblem.alreadyRunning) {
        return;
      } else {
        _nextRenewalProbe = null;
      }
    }
    if (access == null && manual) {
      final task = _verification ??= sync.ensureAccess();
      try {
        access = await task;
      } on Object {
        if (current()) {
          for (final feed in feeds) {
            _update(feed, issue: UnionReadIssue.access);
          }
        }
        return;
      } finally {
        if (identical(_verification, task)) _verification = null;
      }
    }
    if (!current() || inForeground?.call() == false) return;
    if (access != null && _scope != null && access.scope != _scope) {
      _reset();
      return refresh(
        feeds,
        connected: connected,
        reconnect: true,
        inForeground: inForeground,
      );
    }
    if (access == null) {
      for (final feed in due) {
        if (!_running.containsKey(feed) &&
            state[feed]?.issue != missingAccess) {
          _update(feed, issue: missingAccess);
        }
      }
      return;
    }
    _scope ??= access.scope;
    await Future.wait([
      for (final feed in due)
        _running[feed] ??= _refreshFeed(feed, access, sync, current)
            .whenComplete(() {
              if (current()) _running.remove(feed);
            }),
    ]);
  }

  Future<RemoteSessionState?> _renewForReads({
    required ReadIsCurrent current,
    required bool Function() inForeground,
  }) async {
    final holder = ref.read(syncAccessHolderProvider);
    final installation = ref.read(installationRefProvider);
    bool sameContext() =>
        current() &&
        holder.canRenewSilently &&
        installation != null &&
        ref.read(installationRefProvider) == installation &&
        ref.read(installationAccessProvider) ==
            InstallationAccessState.activated;

    if (!sameContext()) return null;
    final remote = ref.read(remoteSessionProvider);
    if (remote.needsReauthentication ||
        remote.phase == RemoteSessionPhase.guardUnavailable ||
        remote.problem == RemoteSessionProblem.noReadableSession) {
      return remote;
    }
    final store = OwnerBindingStore(ref.read(databaseProvider));
    return ref
        .read(remoteSessionProvider.notifier)
        .renewForUnionReads(
          ForegroundSessionCheck(
            canStart: () => sameContext() && inForeground(),
            contextIsCurrent: sameContext,
            isSameInstallation: (session) async {
              if (!sameContext() ||
                  installationReference(session.installationClientId) !=
                      installation) {
                return false;
              }
              final owner = await store.activeBinding();
              final activated = await store.activatedInstallationRef();
              return sameContext() &&
                  activated == installation &&
                  owner?.scope ==
                      OwnerScope(
                        memberId: session.memberId,
                        tenantId: session.tenantId,
                      );
            },
          ),
        );
  }

  bool _justRead(UnionFeed feed, DateTime now) {
    final result = state[feed];
    final lastRead = result?.lastRead;
    return result?.issue == null &&
        lastRead != null &&
        !now.isBefore(lastRead) &&
        now.difference(lastRead) < const Duration(seconds: 2);
  }

  bool _due(UnionFeed feed, DateTime now) {
    final retry = _retryAt[feed];
    if (retry != null) return !now.isBefore(retry);
    final lastRead = state[feed]?.lastRead;
    return lastRead == null ||
        now.isBefore(lastRead) ||
        now.difference(lastRead) >= feed.interval;
  }

  Future<void> _restoreCache(ReadIsCurrent current) async {
    try {
      final scope = (await OwnerBindingStore(
        ref.read(databaseProvider),
      ).activeBinding())?.scope;
      if (!current() || scope == null) return;
      final remoteScope = ref
          .read(syncAccessHolderProvider)
          .forUnionReads
          ?.scope;
      if (remoteScope != null && remoteScope != scope) return;
      _scope ??= scope;
      final lastCalls = await ref
          .read(jointPurchaseStoreProvider)
          .lastListRead(scope);
      if (!current()) return;
      final saved = await ref
          .read(centralBindingStoreProvider)
          .cachedReferences(scope);
      if (!current()) return;
      if (lastCalls != null) _update(UnionFeed.calls, lastRead: lastCalls);
      if (saved != null) {
        _update(
          UnionFeed.references,
          lastRead: saved.at,
          references: saved.references,
        );
      }
    } on Object {
      // Una base temporalmente ilegible no impide volver a consultar.
    }
  }

  Future<void> _refreshFeed(
    UnionFeed feed,
    VerifiedAccess access,
    SyncController sync,
    ReadIsCurrent current,
  ) async {
    _update(feed, busy: true);
    UnionReadIssue? issue;
    CentralReferences? references;
    try {
      switch (feed) {
        case UnionFeed.calls:
          final report = await sync.readJointPurchases(access);
          issue = switch (report.listProblem) {
            JointPurchaseListProblem.incompatibleVersion =>
              UnionReadIssue.incompatible,
            JointPurchaseListProblem.offline => UnionReadIssue.offline,
            JointPurchaseListProblem.temporary => UnionReadIssue.unavailable,
            _ when report.authFailed || report.ownerMismatch =>
              UnionReadIssue.access,
            _ when !report.listed => UnionReadIssue.unavailable,
            _ => null,
          };
        case UnionFeed.references:
          references = await sync.readReferences(access);
        case UnionFeed.identification:
          final report = await sync.readIdentification(access);
          issue = switch (report) {
            _ when report.authFailed || report.ownerMismatch =>
              UnionReadIssue.access,
            _ when report.offline => UnionReadIssue.offline,
            _ when report.listUnavailable => UnionReadIssue.unavailable,
            _ => null,
          };
      }
    } on SyncReadInvalidated {
      issue = UnionReadIssue.access;
    } on SyncAccessUnavailable {
      issue = UnionReadIssue.access;
    } on SyncQueryException catch (error) {
      issue = error.authRequired || error.forbidden
          ? UnionReadIssue.access
          : error.statusCode == null
          ? UnionReadIssue.offline
          : UnionReadIssue.unavailable;
    } on Object {
      issue = UnionReadIssue.unavailable;
    }
    if (!current()) return;
    final now = DateTime.now();
    if (issue == null) {
      _retryAt.remove(feed);
      _failures.remove(feed);
      _update(feed, lastRead: now, references: references);
    } else {
      final failures = ((_failures[feed] ?? 0) + 1).clamp(1, 5);
      _failures[feed] = failures;
      _retryAt[feed] = now.add(Duration(seconds: 15 << (failures - 1)));
      _update(feed, issue: issue);
    }
  }
}
