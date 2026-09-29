class AppSession {
  static bool isWorker = false;
  static int? userId;
  static String currentName = '';

  static void setOwner([int? accountId, String? name]) {
    isWorker = false;
    userId = accountId;
    currentName = name ?? '';
  }

  static void setWorker([int? accountId, String? name]) {
    isWorker = true;
    userId = accountId;
    currentName = name ?? '';
  }

  static void clear() {
    isWorker = false;
    userId = null;
    currentName = '';
  }
}
