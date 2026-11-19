import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'app_session.dart';

enum WorkerSaveResult { added, alreadyExists, limitReached }

class DatabaseHelper {
  static final Argon2id _pinKdf = Argon2id(
    parallelism: 1,
    memory: 19456,
    iterations: 2,
    hashLength: 32,
  );
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('market_tracker.db');
    return _database!;
  }

  static const List<String> _cloudSyncTables = [
    'users',
    'workers',
    'customers',
    'products',
    'sales',
    'payments',
    'expenses',
    'debts',
    'receipts',
  ];
  static const List<String> _workerActivityTables = [
    'customers',
    'sales',
    'payments',
    'expenses',
    'debts',
    'receipts',
  ];

  Future<void> _initializeCloudSyncState(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_pin_security_state (
        userId INTEGER PRIMARY KEY,
        failedAttempts INTEGER NOT NULL DEFAULT 0,
        lockoutUntil TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cloud_sync_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        dirty INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 0,
        cloud_revision INTEGER NOT NULL DEFAULT 0
      )
    ''');
    final stateColumns = await db.rawQuery(
      'PRAGMA table_info(cloud_sync_state)',
    );
    if (!stateColumns.any((column) => column['name'] == 'revision')) {
      await db.execute(
        'ALTER TABLE cloud_sync_state ADD COLUMN revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!stateColumns.any((column) => column['name'] == 'cloud_revision')) {
      await db.execute(
        'ALTER TABLE cloud_sync_state ADD COLUMN cloud_revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.insert('cloud_sync_state', {
      'id': 1,
      'dirty': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    for (final table in _cloudSyncTables) {
      for (final action in ['INSERT', 'UPDATE', 'DELETE']) {
        final event = action.toLowerCase();
        await db.execute('''
          CREATE TRIGGER IF NOT EXISTS cloud_sync_${table}_$event
          AFTER $action ON $table
          BEGIN
            UPDATE cloud_sync_state
            SET dirty = 1, revision = revision + 1
            WHERE id = 1;
          END
        ''');
      }
    }
  }

  Future<bool> hasPendingCloudChanges() async {
    final db = await database;
    final result = await db.query(
      'cloud_sync_state',
      columns: ['dirty'],
      where: 'id = 1',
      limit: 1,
    );
    return result.isNotEmpty && result.first['dirty'] == 1;
  }

  Future<int> getCloudSyncRevision() async {
    final db = await database;
    final result = await db.query(
      'cloud_sync_state',
      columns: ['revision'],
      where: 'id = 1',
      limit: 1,
    );
    return (result.first['revision'] as num?)?.toInt() ?? 0;
  }

  Future<int> getCloudServerRevision() async {
    final db = await database;
    final result = await db.query(
      'cloud_sync_state',
      columns: ['cloud_revision'],
      where: 'id = 1',
      limit: 1,
    );
    return (result.first['cloud_revision'] as num?)?.toInt() ?? 0;
  }

  Future<void> markCloudChangesSyncedAtRevision(
    int revision,
    int cloudRevision,
  ) async {
    final db = await database;
    await db.update(
      'cloud_sync_state',
      {'dirty': 0, 'cloud_revision': cloudRevision},
      where: 'id = 1 AND revision = ?',
      whereArgs: [revision],
    );
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onOpen: _initializeCloudSyncState,
    );
  }

  Future _createDB(Database db, int version) async {
    // ---------- Users ----------
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT,
        company TEXT,
        pinHash TEXT,
        firstOrderAt TEXT,
        subscriptionPaid INTEGER NOT NULL DEFAULT 0,
        subscriptionExpiresAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE workers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        name TEXT NOT NULL,
        FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // ---------- Customers ----------
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        workerName TEXT,
        name TEXT,
        phone TEXT,
        cardNumber TEXT,
        type TEXT,
        createdAt TEXT
      )
    ''');

    // ---------- Products ----------
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        name TEXT,
        price REAL,
        stock INTEGER
      )
    ''');

    // ---------- Sales ----------
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        workerName TEXT,
        customerId INTEGER,
        product TEXT,
        quantity INTEGER,
        amount REAL,
        date TEXT
      )
    ''');

    // ---------- Payments ----------
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        workerName TEXT,
        customerId INTEGER,
        saleId INTEGER,
        method TEXT,
        initialTotal REAL,
        surcharge REAL,
        finalTotal REAL,
        date TEXT
      )
    ''');

    // ---------- Expenses ----------
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        workerName TEXT,
        name TEXT,
        amount REAL,
        date TEXT
      )
    ''');

    // ---------- Debts ----------
    await db.execute('''
      CREATE TABLE debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        workerName TEXT,
        creditor TEXT,
        amount REAL,
        date TEXT
      )
    ''');

    // ---------- Receipts ----------
    await db.execute('''
      CREATE TABLE receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER,
        workerName TEXT,
        customerId INTEGER,
        details TEXT,
        date TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE workers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          name TEXT NOT NULL,
          FOREIGN KEY (userId) REFERENCES users (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      for (final table in [
        'customers',
        'products',
        'sales',
        'payments',
        'expenses',
        'debts',
        'receipts',
      ]) {
        await db.execute('ALTER TABLE $table ADD COLUMN userId INTEGER');
        await db.execute('''
          UPDATE $table SET userId = (SELECT id FROM users ORDER BY id LIMIT 1)
          WHERE userId IS NULL
        ''');
      }
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE users ADD COLUMN firstOrderAt TEXT');
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN subscriptionPaid INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN subscriptionExpiresAt TEXT',
      );
    }
    if (oldVersion < 7) {
      for (final table in _workerActivityTables) {
        await db.execute('ALTER TABLE $table ADD COLUMN workerName TEXT');
      }
    }
  }

  int get _userId => AppSession.userId ?? 0;

  Map<String, dynamic> _scoped(
    Map<String, dynamic> values, {
    bool trackWorker = true,
  }) => {
    ...values,
    'userId': _userId,
    if (trackWorker)
      'workerName': AppSession.isWorker ? AppSession.currentName : null,
  };

  String get _scopeWhere => 'userId = ?';

  List<int> get _scopeArgs => [_userId];

  String get _activityWhere => AppSession.isWorker
      ? 'userId = ? AND lower(workerName) = lower(?)'
      : _scopeWhere;

  List<Object?> get _activityArgs =>
      AppSession.isWorker ? [_userId, AppSession.currentName] : _scopeArgs;

  DateTime workerDashboardStart() {
    final now = DateTime.now();
    final resetTime = DateTime(now.year, now.month, now.day, 5, 0, 0);
    return now.hour < 5
        ? resetTime.subtract(const Duration(days: 1))
        : resetTime;
  }

  // ---------- PIN ----------
  Future<String> hashPin(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await _pinKdf.deriveKeyFromPassword(password: pin, nonce: salt);
    final digest = await key.extractBytes();
    return 'argon2id-v1\$${base64Url.encode(salt)}\$${base64Url.encode(digest)}';
  }

  Future<bool> _matchesPin(String pin, String storedHash) async {
    final parts = storedHash.split(r'$');
    if (parts.length == 3 && parts.first == 'argon2id-v1') {
      try {
        final salt = base64Url.decode(parts[1]);
        final expected = base64Url.decode(parts[2]);
        final key = await _pinKdf.deriveKeyFromPassword(
          password: pin,
          nonce: salt,
        );
        return _constantTimeEquals(await key.extractBytes(), expected);
      } on FormatException {
        return false;
      }
    }

    final legacyHash = sha256.convert(utf8.encode(pin)).toString();
    return _constantTimeEquals(
      utf8.encode(legacyHash),
      utf8.encode(storedHash),
    );
  }

  bool _constantTimeEquals(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0;
  }

  Future<int> saveUser(String username, String company, String pin) async {
    final db = await database;
    final pinHash = await hashPin(pin);
    return await db.insert('users', {
      'username': username,
      'company': company,
      'pinHash': pinHash,
    });
  }

  Future<void> saveWorkers(int userId, List<String> workerNames) async {
    final db = await database;
    for (final name in workerNames) {
      await db.insert('workers', {'userId': userId, 'name': name});
    }
  }

  Future<WorkerSaveResult> addWorker(String name) async {
    final db = await database;
    final userId = _userId;
    if (userId == 0) return WorkerSaveResult.alreadyExists;
    final subscriptionLocked = await isSubscriptionLocked();

    return db.transaction((txn) async {
      final existing = await txn.query(
        'workers',
        where: 'userId = ? AND lower(name) = lower(?)',
        whereArgs: [userId, name],
      );
      if (existing.isNotEmpty) return WorkerSaveResult.alreadyExists;

      if (subscriptionLocked) {
        final countResult = await txn.rawQuery(
          'SELECT COUNT(*) AS count FROM workers WHERE userId = ?',
          [userId],
        );
        final workerCount = (countResult.first['count'] as num?)?.toInt() ?? 0;
        if (workerCount >= 3) return WorkerSaveResult.limitReached;
      }

      await txn.insert('workers', {'userId': userId, 'name': name});
      return WorkerSaveResult.added;
    });
  }

  Future<List<Map<String, dynamic>>> getWorkers() async {
    final db = await database;
    if (_userId == 0) return [];
    return await db.rawQuery(
      '''
      SELECT workers.id, workers.name
      FROM workers
      INNER JOIN users ON users.id = workers.userId
      WHERE workers.userId = ?
      ORDER BY workers.name COLLATE NOCASE
    ''',
      [_userId],
    );
  }

  Future<void> deactivateWorker(int workerId) async {
    final db = await database;
    await db.delete(
      'workers',
      where: 'id = ? AND userId = ?',
      whereArgs: [workerId, _userId],
    );
  }

  Future<void> deactivateAccount() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'customers',
        'products',
        'sales',
        'payments',
        'expenses',
        'debts',
        'receipts',
      ]) {
        await txn.delete(table, where: 'userId = ?', whereArgs: [_userId]);
      }
      await txn.delete('workers', where: 'userId = ?', whereArgs: [_userId]);
      await txn.delete('users', where: 'id = ?', whereArgs: [_userId]);
    });
  }

  Future<void> deleteOldCustomers() async {
    final dbInstance = await database;
    final cutoffDate = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    await dbInstance.delete(
      'customers',
      where:
          '''
      $_activityWhere AND
      id IN (
        SELECT id FROM customers WHERE userId = ?
        AND id NOT IN (SELECT DISTINCT customerId FROM sales WHERE userId = ?)
        AND id NOT IN (SELECT DISTINCT customerId FROM payments WHERE userId = ?)
        AND id NOT IN (SELECT DISTINCT customerId FROM receipts WHERE userId = ?)
      )
      AND date(createdAt) < date(?)
    ''',
      whereArgs: [
        ..._activityArgs,
        _userId,
        _userId,
        _userId,
        _userId,
        cutoffDate,
      ],
    );
  }

  // Get all customers for a specific company
  Future<List<Map<String, dynamic>>> getCustomersByCompany(
    int companyId,
  ) async {
    final db = await database;
    return await db.query(
      'customers',
      where: 'userId = ?',
      whereArgs: [companyId],
    );
  }

  Future<bool> verifyUser(String username, String company) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT users.id FROM users
      LEFT JOIN workers ON workers.userId = users.id
      WHERE users.company = ?
        AND (users.username = ? OR workers.name = ?)
      LIMIT 1
      ''',
      [company, username, username],
    );
    return result.isNotEmpty;
  }

  Future<int?> getUserIdForLogin(String username, String company) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT users.id FROM users
      LEFT JOIN workers ON workers.userId = users.id
      WHERE users.company = ? AND (users.username = ? OR workers.name = ?)
      LIMIT 1
      ''',
      [company, username, username],
    );
    return result.isEmpty ? null : result.first['id'] as int;
  }

  Future<bool> isWorker(String username, String company) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT workers.id FROM workers
      INNER JOIN users ON users.id = workers.userId
      WHERE users.company = ? AND workers.name = ?
      LIMIT 1
      ''',
      [company, username],
    );
    return result.isNotEmpty;
  }

  Future<DateTime?> getFirstOrderDate() async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [_userId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final raw = result.first['firstOrderAt'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  Future<void> recordFirstOrderIfNeeded() async {
    final db = await database;
    final existing = await getFirstOrderDate();
    if (existing != null) return;
    await db.update(
      'users',
      {'firstOrderAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [_userId],
    );
  }

  Future<bool> isSubscriptionLocked() async {
    final user = await getCurrentUser();
    if (user?['subscriptionPaid'] == 1) {
      final rawExpiry = user?['subscriptionExpiresAt'];
      final expiry = rawExpiry == null
          ? null
          : DateTime.tryParse(rawExpiry.toString());
      if (expiry == null || DateTime.now().isBefore(expiry)) return false;
    }

    final firstOrder = await getFirstOrderDate();
    if (firstOrder == null) return false;
    final expiry = firstOrder.add(const Duration(days: 30));
    final now = DateTime.now();
    return now.isAfter(expiry);
  }

  Future<void> setSubscriptionStatus({
    required bool paid,
    DateTime? expiresAt,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {
        'subscriptionPaid': paid ? 1 : 0,
        'subscriptionExpiresAt': expiresAt?.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [_userId],
    );
  }

  Future<bool> verifyPin(String pin) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: _userId == 0 ? null : 'id = ?',
      whereArgs: _userId == 0 ? null : [_userId],
    );
    if (result.isEmpty) return false;
    final user = result.first;
    final userId = (user['id'] as num).toInt();
    final states = await db.query(
      'local_pin_security_state',
      where: 'userId = ?',
      whereArgs: [userId],
      limit: 1,
    );
    final state = states.isEmpty ? null : states.first;
    final lockoutUntil = DateTime.tryParse(
      state?['lockoutUntil']?.toString() ?? '',
    );
    final now = DateTime.now();
    if (lockoutUntil != null && now.isBefore(lockoutUntil)) return false;

    final storedHash = user['pinHash'] as String;
    final isValid = await _matchesPin(pin, storedHash);
    if (isValid && !storedHash.startsWith('argon2id-v1\$')) {
      final upgradedHash = await hashPin(pin);
      await db.update(
        'users',
        {'pinHash': upgradedHash},
        where: 'id = ?',
        whereArgs: [userId],
      );
    }
    if (isValid) {
      await db.delete(
        'local_pin_security_state',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      return true;
    }

    final previousAttempts = lockoutUntil != null && !now.isBefore(lockoutUntil)
        ? 0
        : (state?['failedAttempts'] as num?)?.toInt() ?? 0;
    final failedAttempts = previousAttempts + 1;
    await db.insert('local_pin_security_state', {
      'userId': userId,
      'failedAttempts': failedAttempts,
      'lockoutUntil': failedAttempts >= 5
          ? now.add(const Duration(minutes: 15)).toIso8601String()
          : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return isValid;
  }

  Future<void> updatePin(String newPin) async {
    final db = await database;
    final pinHash = await hashPin(newPin);
    await db.update(
      'users',
      {'pinHash': pinHash},
      where: 'id = ?',
      whereArgs: [_userId],
    );
  }

  Future<void> updateUserInfo(String username, String company) async {
    final db = await database;
    await db.update(
      'users',
      {'username': username, 'company': company},
      where: 'id = ?',
      whereArgs: [_userId],
    );
  }

  // ---------- Customers ----------
  Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final dbInstance = await database;
    customer['createdAt'] = DateTime.now().toIso8601String();
    return await dbInstance.insert('customers', _scoped(customer));
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;
    return await db.query(
      'customers',
      where: _activityWhere,
      whereArgs: _activityArgs,
    );
  }

  Future<Map<String, dynamic>?> getCustomerById(int customerId) async {
    final db = await database;
    final result = await db.query(
      'customers',
      where: 'id = ? AND $_activityWhere',
      whereArgs: [customerId, ..._activityArgs],
      limit: 1,
    );
    return result.isEmpty ? null : result.first;
  }

  Future<List<Map<String, dynamic>>> getReceiptsByCustomer(
    int customerId,
  ) async {
    final db = await database;
    return db.query(
      'receipts',
      where: 'customerId = ? AND $_activityWhere',
      whereArgs: [customerId, ..._activityArgs],
      orderBy: 'date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await database;
    return await db.query(
      'expenses',
      where: _activityWhere,
      whereArgs: _activityArgs,
      orderBy: 'date DESC',
    );
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete(
      'expenses',
      where: 'id = ? AND $_activityWhere',
      whereArgs: [id, ..._activityArgs],
    );
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [_userId],
      limit: 1,
    );
    return result.isEmpty ? null : result.first;
  }

  Future<Map<String, List<Map<String, dynamic>>>>
  exportCompanySnapshot() async {
    final db = await database;
    const tables = [
      'users',
      'workers',
      'customers',
      'products',
      'sales',
      'payments',
      'expenses',
      'debts',
      'receipts',
    ];
    final snapshot = <String, List<Map<String, dynamic>>>{};
    for (final table in tables) {
      snapshot[table] = await db.query(
        table,
        where: table == 'users' ? 'id = ?' : _scopeWhere,
        whereArgs: _scopeArgs,
      );
    }
    return snapshot;
  }

  Future<int> importCompanySnapshot(
    Map<String, List<Map<String, dynamic>>> snapshot, {
    String? pin,
    int cloudRevision = 0,
  }) async {
    final userRows = snapshot['users'];
    if (userRows == null || userRows.length != 1) {
      throw const FormatException('Company snapshot must include one user.');
    }

    final user = Map<String, dynamic>.from(userRows.single);
    final userId = (user['id'] as num?)?.toInt();
    if (userId == null) {
      throw const FormatException('Company snapshot user has no ID.');
    }

    final importedPinHash = pin == null ? null : await hashPin(pin);
    final db = await database;
    await db.transaction((txn) async {
      final localUsers = await txn.query(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      final localUser = localUsers.isEmpty
          ? <String, dynamic>{}
          : localUsers.first;
      user['pinHash'] = importedPinHash ?? localUser['pinHash'];
      user['subscriptionPaid'] = localUser['subscriptionPaid'] ?? 0;
      user['subscriptionExpiresAt'] = localUser['subscriptionExpiresAt'];

      if (localUsers.isEmpty) {
        await txn.insert('users', user);
      } else {
        await txn.update('users', user, where: 'id = ?', whereArgs: [userId]);
      }

      const tables = [
        'workers',
        'customers',
        'products',
        'sales',
        'payments',
        'expenses',
        'debts',
        'receipts',
      ];
      for (final table in tables) {
        await txn.delete(table, where: _scopeWhere, whereArgs: [userId]);
        for (final row in snapshot[table] ?? const []) {
          if ((row['userId'] as num?)?.toInt() != userId) continue;
          await txn.insert(table, row);
        }
      }
      await txn.update('cloud_sync_state', {
        'dirty': 0,
        'cloud_revision': cloudRevision,
      }, where: 'id = 1');
    });
    return userId;
  }

  // ---------- Users ----------
  Future<List<Map<String, dynamic>>> getUsers() async {
    final db = await database;
    return await db.query('users');
  }

  Future<int> adminDeleteCustomer(int id) async {
    final db = await database;
    await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    final deleted = await db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted > 0) {
      await db.delete('sales', where: 'customerId = ?', whereArgs: [id]);
      await db.delete('payments', where: 'customerId = ?', whereArgs: [id]);
      await db.delete('receipts', where: 'customerId = ?', whereArgs: [id]);
    }
    return deleted;
  }

  // ---------- Products ----------
  Future<void> insertProduct(Map<String, dynamic> product) async {
    final db = await database;
    await db.insert('products', _scoped(product, trackWorker: false));
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.delete(
      'products',
      where: 'id = ? AND userId = ?',
      whereArgs: [id, _userId],
    );
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;
    return await db.query(
      'products',
      where: _scopeWhere,
      whereArgs: _scopeArgs,
    );
  }

  Future<int?> getProductStock(String productName) async {
    final db = await database;
    final result = await db.query(
      'products',
      where: 'name = ? AND userId = ?',
      whereArgs: [productName, _userId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final stock = result.first['stock'];
    return stock == null ? 0 : (stock as num).toInt();
  }

  Future<bool> canFulfillOrder(String productName, int qty) async {
    if (qty <= 0) return false;
    final stock = await getProductStock(productName);
    return stock != null && stock >= qty;
  }

  Future<void> reduceProductStock(String productName, int qty) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE products SET stock = stock - ? WHERE name = ? AND stock >= ? AND userId = ?',
      [qty, productName, qty, _userId],
    );
  }

  Future<bool> adjustProductStock(int productId, int change) async {
    final db = await database;
    final result = await db.rawUpdate(
      'UPDATE products SET stock = MAX(COALESCE(stock, 0) + ?, 0) WHERE id = ? AND userId = ?',
      [change, productId, _userId],
    );
    return result > 0;
  }

  // ---------- Sales ----------
  Future<int> insertSale(Map<String, dynamic> sale) async {
    final db = await database;
    await recordFirstOrderIfNeeded();
    return await db.insert('sales', _scoped(sale));
  }

  Future<List<Map<String, dynamic>>> getSales() async {
    final db = await database;
    return await db.query(
      'sales',
      where: _activityWhere,
      whereArgs: _activityArgs,
      orderBy: 'date DESC',
    );
  }

  // Get all sales for a specific company
  Future<List<Map<String, dynamic>>> getSalesByCompany(int companyId) async {
    final db = await database;
    return await db.query('sales', where: 'userId = ?', whereArgs: [companyId]);
  }

  Future<void> insertSaleIfNotExists(Map<String, dynamic> sale) async {
    final db = await database;
    await recordFirstOrderIfNeeded();
    final existing = await db.query(
      'sales',
      where:
          '$_activityWhere AND customerId = ? AND product = ? AND quantity = ? AND amount = ? AND date = ?',
      whereArgs: [
        ..._activityArgs,
        sale['customerId'],
        sale['product'],
        sale['quantity'],
        sale['amount'],
        sale['date'],
      ],
    );
    if (existing.isEmpty) {
      await db.insert('sales', _scoped(sale));
    }
  }

  Future<List<Map<String, dynamic>>> getSalesByCustomer(int customerId) async {
    final db = await database;
    return await db.query(
      'sales',
      where: 'customerId = ? AND $_activityWhere',
      whereArgs: [customerId, ..._activityArgs],
      orderBy: 'date DESC',
    );
  }

  Future<double> totalSales() async {
    final db = await database;
    if (AppSession.isWorker) {
      final start = workerDashboardStart().toIso8601String();
      final result = await db.rawQuery(
        'SELECT SUM(amount) as total FROM sales WHERE $_activityWhere AND date >= ?',
        [..._activityArgs, start],
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    }
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM sales WHERE userId = ?',
      [_userId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> adminDeleteSale(int id, {required int companyId}) async {
    final db = await database;
    return db.transaction((txn) async {
      final sales = await txn.query(
        'sales',
        where: 'id = ? AND userId = ?',
        whereArgs: [id, companyId],
        limit: 1,
      );
      if (sales.isEmpty) return 0;

      final sale = sales.first;
      final deleted = await txn.delete(
        'sales',
        where: 'id = ? AND userId = ?',
        whereArgs: [id, companyId],
      );
      if (deleted == 0) return 0;

      final productName = sale['product']?.toString();
      final quantity = (sale['quantity'] as num?)?.toInt() ?? 0;
      if (productName != null && quantity > 0) {
        final products = await txn.query(
          'products',
          columns: ['stock'],
          where: 'name = ? AND userId = ?',
          whereArgs: [productName, companyId],
          limit: 1,
        );
        if (products.isNotEmpty) {
          final stock = (products.first['stock'] as num?)?.toInt() ?? 0;
          await txn.update(
            'products',
            {'stock': stock + quantity},
            where: 'name = ? AND userId = ?',
            whereArgs: [productName, companyId],
          );
        }
      }

      final customerId = (sale['customerId'] as num?)?.toInt();
      final date = sale['date']?.toString();
      if (customerId == null || date == null) return deleted;

      const orderWhere = 'userId = ? AND customerId = ? AND date = ?';
      final orderArgs = [companyId, customerId, date];
      final remainingSales = await txn.query(
        'sales',
        columns: ['amount'],
        where: orderWhere,
        whereArgs: orderArgs,
      );
      if (remainingSales.isEmpty) {
        await txn.delete('payments', where: orderWhere, whereArgs: orderArgs);
        await txn.delete('receipts', where: orderWhere, whereArgs: orderArgs);
        return deleted;
      }

      final orderTotal = remainingSales.fold<double>(
        0,
        (total, row) => total + ((row['amount'] as num?)?.toDouble() ?? 0),
      );
      final payments = await txn.query(
        'payments',
        where: orderWhere,
        whereArgs: orderArgs,
      );
      for (final payment in payments) {
        final method = payment['method']?.toString();
        final surcharge = method == 'mobile_money' || method == 'bank_card'
            ? orderTotal * 0.01
            : 0.0;
        await txn.update(
          'payments',
          {
            'initialTotal': orderTotal,
            'surcharge': surcharge,
            'finalTotal': orderTotal + surcharge,
          },
          where: 'id = ? AND userId = ?',
          whereArgs: [payment['id'], companyId],
        );
      }

      final receipts = await txn.query(
        'receipts',
        where: orderWhere,
        whereArgs: orderArgs,
      );
      for (final receipt in receipts) {
        final rawDetails = receipt['details'];
        if (rawDetails is! String) continue;
        try {
          final decoded = jsonDecode(rawDetails);
          if (decoded is! Map) continue;
          final details = Map<String, dynamic>.from(decoded);
          final products = (details['products'] as List? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          final saleAmount = (sale['amount'] as num?)?.toDouble();
          final productIndex = products.indexWhere((item) {
            final lineAmount =
                (item['subtotal'] as num?)?.toDouble() ??
                (item['amount'] as num?)?.toDouble();
            return item['product']?.toString() == productName &&
                (item['quantity'] as num?)?.toInt() == quantity &&
                (saleAmount == null || lineAmount == saleAmount);
          });
          if (productIndex == -1) continue;

          products.removeAt(productIndex);
          details['products'] = products;
          details['initialTotal'] = orderTotal;
          final method = details['paymentMethod']?.toString();
          final surcharge = method == 'mobile_money' || method == 'bank_card'
              ? orderTotal * 0.01
              : 0.0;
          details['surcharge'] = surcharge;
          details['finalTotal'] = orderTotal + surcharge;
          final cashReceived = (details['cashReceived'] as num?)?.toDouble();
          if (cashReceived != null) {
            details['changeDue'] = cashReceived - (orderTotal + surcharge);
          }
          await txn.update(
            'receipts',
            {'details': jsonEncode(details)},
            where: 'id = ? AND userId = ?',
            whereArgs: [receipt['id'], companyId],
          );
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }

      return deleted;
    });
  }

  // ---------- Payments ----------
  Future<int> insertPayment(Map<String, dynamic> payment) async {
    final db = await database;
    return await db.insert('payments', _scoped(payment));
  }

  Future<List<Map<String, dynamic>>> getPayments() async {
    final db = await database;
    return await db.query(
      'payments',
      where: _activityWhere,
      whereArgs: _activityArgs,
      orderBy: 'date DESC',
    );
  }

  Future<int> insertReceipt(Map<String, dynamic> receipt) async {
    final db = await database;
    return await db.insert('receipts', _scoped(receipt));
  }

  // ---------- Expenses ----------
  Future<void> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    await db.insert('expenses', _scoped(expense));
  }

  // Get all expenses for a specific company
  Future<List<Map<String, dynamic>>> getExpensesByCompany(int companyId) async {
    final db = await database;
    return await db.query(
      'expenses',
      where: 'userId = ?',
      whereArgs: [companyId],
    );
  }

  Future<void> insertExpenseIfNotExists(Map<String, dynamic> expense) async {
    final db = await database;
    final existing = await db.query(
      'expenses',
      where: '$_activityWhere AND name = ? AND amount = ? AND date = ?',
      whereArgs: [
        ..._activityArgs,
        expense['name'],
        expense['amount'],
        expense['date'],
      ],
    );
    if (existing.isEmpty) {
      await db.insert('expenses', _scoped(expense));
    }
  }

  Future<double> totalExpenses() async {
    final db = await database;
    if (AppSession.isWorker) {
      final start = workerDashboardStart().toIso8601String();
      final result = await db.rawQuery(
        'SELECT SUM(amount) as total FROM expenses WHERE $_activityWhere AND date >= ?',
        [..._activityArgs, start],
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    }
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE userId = ?',
      [_userId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ---------- Debts ----------
  Future<void> insertDebt(Map<String, dynamic> debt) async {
    final db = await database;
    await db.insert('debts', _scoped(debt));
  }

  Future<List<Map<String, dynamic>>> getDebts() async {
    final db = await database;
    return await db.query(
      'debts',
      where: _activityWhere,
      whereArgs: _activityArgs,
      orderBy: 'date DESC',
    );
  }

  // Get all debts for a specific company
  Future<List<Map<String, dynamic>>> getDebtsByCompany(int companyId) async {
    final db = await database;
    return await db.query('debts', where: 'userId = ?', whereArgs: [companyId]);
  }

  Future<void> insertDebtIfNotExists(Map<String, dynamic> debt) async {
    final db = await database;
    final existing = await db.query(
      'debts',
      where: '$_activityWhere AND creditor = ? AND amount = ? AND date = ?',
      whereArgs: [
        ..._activityArgs,
        debt['creditor'],
        debt['amount'],
        debt['date'],
      ],
    );
    if (existing.isEmpty) {
      await db.insert('debts', _scoped(debt));
    }
  }

  Future<double> totalDebts() async {
    final db = await database;
    if (AppSession.isWorker) {
      final start = workerDashboardStart().toIso8601String();
      final result = await db.rawQuery(
        'SELECT SUM(amount) as total FROM debts WHERE $_activityWhere AND date >= ?',
        [..._activityArgs, start],
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    }
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM debts WHERE userId = ?',
      [_userId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ---------- Profit ----------
  Future<double> totalProfit() async {
    final sales = await totalSales();
    final expenses = await totalExpenses();
    return sales - expenses;
  }

  // ---------- Transaction History ----------
  Future<List<Map<String, dynamic>>> getTransactionHistory() async {
    final db = await database;
    final activityArgs = [
      ..._activityArgs,
      ..._activityArgs,
      ..._activityArgs,
      ..._activityArgs,
    ];
    return await db.rawQuery('''
      SELECT 'Sale' as type, amount, date FROM sales WHERE $_activityWhere
      UNION
      SELECT 'Payment' as type, finalTotal as amount, date FROM payments WHERE $_activityWhere
      UNION
      SELECT 'Expense' as type, amount, date FROM expenses WHERE $_activityWhere
      UNION
      SELECT 'Debt' as type, amount, date FROM debts WHERE $_activityWhere
      ORDER BY date DESC
    ''', activityArgs);
  }
}
