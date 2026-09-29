import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'app_session.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('market_tracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
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
  }

  int get _userId => AppSession.userId ?? 0;

  Map<String, dynamic> _scoped(Map<String, dynamic> values) => {
    ...values,
    'userId': _userId,
  };

  String get _scopeWhere => 'userId = ?';

  List<int> get _scopeArgs => [_userId];

  DateTime workerDashboardStart() {
    final now = DateTime.now();
    final resetTime = DateTime(now.year, now.month, now.day, 5, 0, 0);
    return now.hour < 5
        ? resetTime.subtract(const Duration(days: 1))
        : resetTime;
  }

  // ---------- PIN ----------
  String hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  Future<int> saveUser(String username, String company, String pin) async {
    final db = await database;
    return await db.insert('users', {
      'username': username,
      'company': company,
      'pinHash': hashPin(pin),
    });
  }

  Future<void> saveWorkers(int userId, List<String> workerNames) async {
    final db = await database;
    for (final name in workerNames) {
      await db.insert('workers', {'userId': userId, 'name': name});
    }
  }

  Future<bool> addWorker(String name) async {
    final db = await database;
    final userId = _userId;
    if (userId == 0) return false;
    final existing = await db.query(
      'workers',
      where: 'userId = ? AND lower(name) = lower(?)',
      whereArgs: [userId, name],
    );
    if (existing.isNotEmpty) return false;
    await db.insert('workers', {'userId': userId, 'name': name});
    return true;
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
      where: '''
      userId = ? AND
      id IN (
        SELECT id FROM customers
        WHERE id NOT IN (SELECT DISTINCT customerId FROM sales)
        AND id NOT IN (SELECT DISTINCT customerId FROM payments)
        AND id NOT IN (SELECT DISTINCT customerId FROM receipts)
      )
      AND date(createdAt) < date(?)
    ''',
      whereArgs: [_userId, cutoffDate],
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
    final storedHash = result.first['pinHash'] as String;
    return hashPin(pin) == storedHash;
  }

  Future<void> updatePin(String newPin) async {
    final db = await database;
    await db.update(
      'users',
      {'pinHash': hashPin(newPin)},
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
      where: _scopeWhere,
      whereArgs: _scopeArgs,
    );
  }

  Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await database;
    return await db.query(
      'expenses',
      where: _scopeWhere,
      whereArgs: _scopeArgs,
      orderBy: 'date DESC',
    );
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete(
      'expenses',
      where: 'id = ? AND userId = ?',
      whereArgs: [id, _userId],
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
    await db.insert('products', _scoped(product));
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
      where: _scopeWhere,
      whereArgs: _scopeArgs,
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
          'userId = ? AND customerId = ? AND product = ? AND quantity = ? AND amount = ? AND date = ?',
      whereArgs: [
        _userId,
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
      where: 'customerId = ? AND userId = ?',
      whereArgs: [customerId, _userId],
      orderBy: 'date DESC',
    );
  }

  Future<double> totalSales() async {
    final db = await database;
    if (AppSession.isWorker) {
      final start = workerDashboardStart().toIso8601String();
      final result = await db.rawQuery(
        'SELECT SUM(amount) as total FROM sales WHERE userId = ? AND date >= ?',
        [_userId, start],
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    }
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM sales WHERE userId = ?',
      [_userId],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> adminDeleteSale(int id) async {
    final db = await database;
    final sale = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (sale.isEmpty) return 0;

    final deleted = await db.delete('sales', where: 'id = ?', whereArgs: [id]);
    if (deleted > 0) {
      final productName = sale.first['product']?.toString();
      final qty = (sale.first['quantity'] as num?)?.toInt() ?? 0;
      if (productName != null && qty > 0) {
        final currentStock = await getProductStock(productName);
        final restored = (currentStock ?? 0) + qty;
        await db.update(
          'products',
          {'stock': restored},
          where: 'name = ? AND userId = ?',
          whereArgs: [productName, _userId],
        );
      }
      await db.delete(
        'payments',
        where: 'customerId = ? AND saleId = ?',
        whereArgs: [sale.first['customerId'], id],
      );
      final customerCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE userId = ?',
        [_userId],
      );
      final totalCustomers =
          (customerCount.first['count'] as num?)?.toInt() ?? 0;
      if (totalCustomers == 0) {
        await db.delete('customers', where: 'userId = ?', whereArgs: [_userId]);
      }
    }
    return deleted;
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
      where: _scopeWhere,
      whereArgs: _scopeArgs,
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
      where: 'userId = ? AND name = ? AND amount = ? AND date = ?',
      whereArgs: [_userId, expense['name'], expense['amount'], expense['date']],
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
        'SELECT SUM(amount) as total FROM expenses WHERE userId = ? AND date >= ?',
        [_userId, start],
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
      where: _scopeWhere,
      whereArgs: _scopeArgs,
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
      where: 'userId = ? AND creditor = ? AND amount = ? AND date = ?',
      whereArgs: [_userId, debt['creditor'], debt['amount'], debt['date']],
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
        'SELECT SUM(amount) as total FROM debts WHERE userId = ? AND date >= ?',
        [_userId, start],
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
    return await db.rawQuery(
      '''
      SELECT 'Sale' as type, amount, date FROM sales WHERE userId = ?
      UNION
      SELECT 'Payment' as type, finalTotal as amount, date FROM payments WHERE userId = ?
      UNION
      SELECT 'Expense' as type, amount, date FROM expenses WHERE userId = ?
      UNION
      SELECT 'Debt' as type, amount, date FROM debts WHERE userId = ?
      ORDER BY date DESC
    ''',
      [_userId, _userId, _userId, _userId],
    );
  }
}
