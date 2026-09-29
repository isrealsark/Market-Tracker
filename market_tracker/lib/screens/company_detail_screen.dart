import 'package:flutter/material.dart';
import 'database_helper.dart';

class CompanyDetailScreen extends StatefulWidget {
  final int companyId;
  final String companyName;

  const CompanyDetailScreen({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> expenses = [];
  List<Map<String, dynamic>> debts = [];

  @override
  void initState() {
    super.initState();
    _loadCompanyData();
  }

  Future<void> _loadCompanyData() async {
    try {
      final c = await db.getCustomersByCompany(widget.companyId);
      final s = await db.getSalesByCompany(widget.companyId);
      final e = await db.getExpensesByCompany(widget.companyId);
      final d = await db.getDebtsByCompany(widget.companyId);

      final purchases = <int, List<String>>{};
      for (final sale in s) {
        final customerId = sale['customerId'];
        if (customerId == null) continue;
        final productName = (sale['product'] ?? 'Product').toString();
        purchases.putIfAbsent(customerId as int, () => []).add(productName);
      }

      setState(() {
        customers = c;
        sales = s;
        expenses = e;
        debts = d;
      });
    } catch (err) {
      // If company-linked columns/tables are not present, fail gracefully.
      setState(() {
        customers = [];
        sales = [];
        expenses = [];
        debts = [];
      });
    }
  }

  Future<void> _deleteCustomer(int id) async {
    await db.adminDeleteCustomer(id);
    _loadCompanyData();
  }

  Future<void> _deleteSale(int id) async {
    await db.adminDeleteSale(id);
    _loadCompanyData();
  }

  @override
  Widget build(BuildContext context) {
    final purchaseSummary = <int, String>{};
    for (final sale in sales) {
      final customerId = sale['customerId'];
      if (customerId == null) continue;
      final productName = (sale['product'] ?? 'Product').toString();
      final existing = purchaseSummary[customerId as int] ?? '';
      purchaseSummary[customerId] = existing.isEmpty
          ? productName
          : '$existing, $productName';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.companyName} Details"),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // Customers Section
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Customers",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...customers.map(
            (c) => ListTile(
              title: Text(c['name'] ?? "Unknown"),
              subtitle: Text(
                "Phone: ${c['phone'] ?? ''}\nBought: ${purchaseSummary[c['id']] ?? 'No purchases'}",
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteCustomer(c['id']),
              ),
            ),
          ),
          const Divider(),

          // Sales Section
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Sales Orders",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...sales.map(
            (s) => ListTile(
              title: Text("${s['product']} - GHS ${s['amount']}"),
              subtitle: Text("Date: ${s['date']}"),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteSale(s['id']),
              ),
            ),
          ),
          const Divider(),

          // Expenses Section
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Expenses",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...expenses.map(
            (e) => ListTile(
              title: Text(e['description'] ?? "Expense"),
              subtitle: Text("Amount: GHS ${e['amount']}"),
            ),
          ),
          const Divider(),

          // Debts Section
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Debts",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...debts.map(
            (d) => ListTile(
              title: Text("Debtor: ${d['debtor']}"),
              subtitle: Text("Amount: GHS ${d['amount']}"),
            ),
          ),
        ],
      ),
    );
  }
}
