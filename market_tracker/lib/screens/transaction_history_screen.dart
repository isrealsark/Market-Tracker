import 'package:flutter/material.dart';
import 'database_helper.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final list = await db.getTransactionHistory();
    setState(() => transactions = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Transaction History")),
      body: ListView.builder(
        itemCount: transactions.length,
        itemBuilder: (_, i) {
          final t = transactions[i];
          return ListTile(
            leading: Icon(
              t['type'] == 'Sale'
                  ? Icons.shopping_cart
                  : t['type'] == 'Payment'
                  ? Icons.payment
                  : t['type'] == 'Expense'
                  ? Icons.receipt_long
                  : Icons.people,
              color: Colors.orange,
            ),
            title: Text("${t['type']} - GHS ${t['amount']}"),
            subtitle: Text(t['date']),
          );
        },
      ),
    );
  }
}
