import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/sync_service.dart';

class ConnectivityService {
  final SyncService _syncService = SyncService();

  void listenForConnectivityChanges() {
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      // Check if any of the results show online connectivity
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi)) {
        // Device is online → trigger sync
        await _syncService.mergeSalesFromCloud();
        await _syncService.mergeExpensesFromCloud();
      }
    });
  }
}
