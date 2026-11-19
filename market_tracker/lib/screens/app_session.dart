class AppSession {
  static bool isWorker = false;
  static bool isAdmin = false;
  static int? userId;
  static String currentName = '';

  static void setOwner([int? accountId, String? name]) {
    isWorker = false;
    isAdmin = false;
    userId = accountId;
    currentName = name ?? '';
  }

  static void setWorker([int? accountId, String? name]) {
    isWorker = true;
    isAdmin = false;
    userId = accountId;
    currentName = name ?? '';
  }

  static void setAdmin(String username) {
    isWorker = false;
    isAdmin = true;
    userId = null;
    currentName = username;
  }

  static void clear() {
    isWorker = false;
    isAdmin = false;
    userId = null;
    currentName = '';
  }
}
