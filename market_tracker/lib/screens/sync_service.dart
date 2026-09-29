import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart'; // your SQLite helper

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Push local sale to Firestore
  Future<void> syncSale(Map<String, dynamic> sale) async {
    await _firestore.collection('sales').add(sale);
  }

  // Push local expense to Firestore
  Future<void> syncExpense(Map<String, dynamic> expense) async {
    await _firestore.collection('expenses').add(expense);
  }

  // Download Firestore sales and merge into SQLite
  Future<void> mergeSalesFromCloud() async {
    final snapshot = await _firestore.collection('sales').get();
    for (var doc in snapshot.docs) {
      final sale = doc.data();
      await _db.insertSaleIfNotExists(sale); // custom method
    }
  }

  // Download Firestore expenses and merge into SQLite
  Future<void> mergeExpensesFromCloud() async {
    final snapshot = await _firestore.collection('expenses').get();
    for (var doc in snapshot.docs) {
      final expense = doc.data();
      await _db.insertExpenseIfNotExists(expense); // custom method
    }
  }
}
