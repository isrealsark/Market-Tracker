import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'database_helper.dart';
import 'subscription_screen.dart';
import 'subscription_rules.dart';
import 'app_session.dart';

class CustomerProfileScreen extends StatefulWidget {
  final int customerId;
  const CustomerProfileScreen({super.key, required this.customerId});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final db = DatabaseHelper.instance;
  Map<String, dynamic>? customer;
  List<Map<String, dynamic>> sales = [];
  List<Map<String, dynamic>> receipts = [];

  @override
  void initState() {
    super.initState();
    _loadCustomer();
    _loadSales();
    _loadReceipts();
  }

  Future<void> _ensureAccess() async {
    if (AppSession.isWorker) return;
    final locked = await db.isSubscriptionLocked();
    if (!mounted) return;
    if (locked) {
      await SubscriptionRules.redirectIfLocked(
        context: context,
        isLocked: db.isSubscriptionLocked,
        subscriptionScreen: const SubscriptionScreen(),
      );
    }
  }

  Future<void> _loadCustomer() async {
    await _ensureAccess();
    final dbInstance = await db.database;
    final result = await dbInstance.query(
      'customers',
      where: 'id = ?',
      whereArgs: [widget.customerId],
    );
    if (result.isNotEmpty) {
      setState(() => customer = result.first);
    }
  }

  Future<void> _loadSales() async {
    final list = await db.getSalesByCustomer(widget.customerId);
    setState(() => sales = list);
  }

  Future<void> _loadReceipts() async {
    final dbInstance = await db.database;
    final list = await dbInstance.query(
      'receipts',
      where: 'customerId = ?',
      whereArgs: [widget.customerId],
      orderBy: 'date DESC',
    );
    setState(() => receipts = list);
  }

  Future<void> _printCustomerProfile() async {
    if (customer == null) return;
    if (!AppSession.isWorker && await db.isSubscriptionLocked()) {
      if (!mounted) return;
      await SubscriptionRules.redirectIfLocked(
        context: context,
        isLocked: db.isSubscriptionLocked,
        subscriptionScreen: const SubscriptionScreen(),
      );
      return;
    }

    final pdf = pw.Document();

    final logo = await imageFromAssetBundle('assets/images/logo.png');

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Company branding
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Image(logo, width: 60, height: 60),
                  pw.SizedBox(width: 10),
                  pw.Text(
                    "MT Market Trader", // 🔹 Replace with your company name
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  "CUSTOMER RECEIPT",
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Divider(),

              // Customer Info
              pw.Text("Name: ${customer!['name'] ?? ''}"),
              pw.Text("Phone: ${customer!['phone'] ?? ''}"),
              pw.Text("Card: ${customer!['cardNumber'] ?? ''}"),
              pw.Text("Type: ${customer!['type'] ?? ''}"),
              pw.SizedBox(height: 10),
              pw.Divider(),

              // Purchase History
              pw.Text(
                "Purchase History",
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              ...sales.map(
                (s) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("${s['product']} x${s['quantity']}"),
                    pw.Text("GHS ${s['amount']}"),
                    pw.Text("${s['date']}"),
                  ],
                ),
              ),
              pw.Divider(),

              // Receipts
              pw.Text(
                "Receipts",
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              ...receipts.map(
                (r) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Receipt #${r['id']}"),
                    pw.Text("${r['date']}"),
                    pw.Text("Total: GHS ${r['total'] ?? ''}"),
                  ],
                ),
              ),
              pw.Divider(),

              // Footer
              pw.SizedBox(height: 20),
              pw.Text("Signature: __________________________"),
              pw.SizedBox(height: 10),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  "Printed on: ${DateTime.now()}",
                  style: pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    if (customer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(customer!['name'] ?? "Customer Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printCustomerProfile, // 🔹 Optional print
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Phone: ${customer!['phone'] ?? ''}"),
            Text("Card: ${customer!['cardNumber'] ?? ''}"),
            Text("Type: ${customer!['type']}"),
            const SizedBox(height: 16),

            const Text(
              "Purchase History",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: sales.length,
                itemBuilder: (_, i) {
                  final s = sales[i];
                  return ListTile(
                    title: Text("${s['product']} x${s['quantity']}"),
                    subtitle: Text("Amount: GHS ${s['amount']}"),
                    trailing: Text(s['date']),
                  );
                },
              ),
            ),

            const Text(
              "Receipts",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: receipts.length,
                itemBuilder: (_, i) {
                  final r = receipts[i];
                  return ListTile(
                    title: Text("Receipt #${r['id']}"),
                    subtitle: Text(r['date']),
                    trailing: Text("Total: GHS ${r['total'] ?? ''}"),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
