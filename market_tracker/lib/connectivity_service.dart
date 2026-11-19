import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/company_sync_service.dart';
import 'screens/database_helper.dart';

class ConnectivityService {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _syncInProgress = false;

  void start() {
    _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        syncPendingChanges();
      }
    });
    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => syncPendingChanges(),
    );
    syncPendingChanges();
  }

  Future<void> syncPendingChanges() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final connections = await Connectivity().checkConnectivity();
      if (connections.every((result) => result == ConnectivityResult.none)) {
        return;
      }
      await CompanySyncService.syncPendingChanges(DatabaseHelper.instance);
    } catch (_) {
      // Keep the dirty flag set and retry on the next connectivity event or timer.
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _connectivitySubscription?.cancel();
  }
}
