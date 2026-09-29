import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'database_helper.dart';
import 'pdf_helper.dart';
import 'app_session.dart';
import 'subscription_screen.dart';
import 'subscription_rules.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final db = DatabaseHelper.instance;
  late Future<_DailyReport> reportFuture;
  final currencyFormat = NumberFormat.currency(symbol: '₵');

  @override
  void initState() {
    super.initState();
    reportFuture = _loadReport();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) {
      setState(() {
        reportFuture = _loadReport();
      });
    }
  }

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _currentWorkerWindowStart() {
    final now = DateTime.now();
    final resetTime = DateTime(now.year, now.month, now.day, 5, 0, 0);
    return now.hour < 5
        ? resetTime.subtract(const Duration(days: 1))
        : resetTime;
  }

  bool _isToday(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return false;
    final start = AppSession.isWorker
        ? _currentWorkerWindowStart()
        : _startOfToday();
    return !date.isBefore(start);
  }

  Future<_DailyReport> _loadReport() async {
    if (!AppSession.isWorker && await db.isSubscriptionLocked()) {
      if (mounted) {
        await SubscriptionRules.redirectIfLocked(
          context: context,
          isLocked: db.isSubscriptionLocked,
          subscriptionScreen: const SubscriptionScreen(),
        );
      }
    }
    final user = await db.getCurrentUser();
    final allSales = await db.getSales();
    final allExpenses = await db.getExpenses();
    final allDebts = await db.getDebts();
    final products = await db.getProducts();
    final payments = await db.getPayments();
    final customers = await db.getCustomers();
    final todaysPayments = payments
        .where((payment) => _isToday(payment['date']))
        .toList();

    return _DailyReport(
      companyName: user == null
          ? 'Company'
          : (user['company'] ?? 'Company').toString(),
      workerName: AppSession.currentName.isNotEmpty
          ? AppSession.currentName
          : 'Owner',
      sales: allSales.where((sale) => _isToday(sale['date'])).toList(),
      expenses: allExpenses
          .where((expense) => _isToday(expense['date']))
          .toList(),
      debts: allDebts.where((debt) => _isToday(debt['date'])).toList(),
      products: products,
      orderCount: AppSession.isWorker ? 0 : todaysPayments.length,
      customerCount: AppSession.isWorker ? 0 : customers.length,
      cashTotal: AppSession.isWorker
          ? 0
          : _paymentTotal(todaysPayments, 'cash'),
      momoTotal: AppSession.isWorker
          ? 0
          : _paymentTotal(todaysPayments, 'mobile_money'),
    );
  }

  double _paymentTotal(List<Map<String, dynamic>> payments, String method) =>
      payments
          .where((payment) => payment['method'] == method)
          .fold<double>(
            0,
            (sum, payment) =>
                sum + ((payment['finalTotal'] as num?)?.toDouble() ?? 0),
          );

  Future<void> _downloadReport(_DailyReport report) async {
    final bytes = await PdfHelper.generateReport(
      companyName: report.companyName,
      sales: report.sales.cast<Map<String, Object?>>(),
      expenses: report.expenses.cast<Map<String, Object?>>(),
      debts: report.debts.cast<Map<String, Object?>>(),
      products: report.products.cast<Map<String, Object?>>(),
      orderCount: report.orderCount,
      customerCount: report.customerCount,
      cashTotal: report.cashTotal,
      momoTotal: report.momoTotal,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'market_tracker_report_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
    );
  }

  Future<void> _refreshReport() async {
    final nextReport = _loadReport();
    if (mounted) {
      setState(() {
        reportFuture = nextReport;
      });
    }
    await nextReport;
  }

  double _sum(List<Map<String, dynamic>> rows) => rows.fold<double>(
    0,
    (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
  );

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? value?.toString() ?? ''
        : DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_DailyReport>(
          future: reportFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final report = snapshot.data!;
            final salesTotal = _sum(report.sales);
            final expenseTotal = _sum(report.expenses);
            final debtTotal = _sum(report.debts);

            return RefreshIndicator(
              onRefresh: _refreshReport,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        tooltip: 'Exit reports',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Flexible(
                        child: Text(
                          report.companyName,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/watermark2.png',
                            width: 100,
                            height: 100,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'REPORTS',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Center(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                        ),
                        children: [
                          TextSpan(
                            text: DateFormat(
                              'dd MMMM yyyy',
                            ).format(DateTime.now()),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: '  •  '),
                          TextSpan(
                            text: report.workerName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('Summary'),
                  _summaryGrid([
                    ('Sales', currencyFormat.format(salesTotal)),
                    ('Expenses', currencyFormat.format(expenseTotal)),
                    ('Debts', currencyFormat.format(debtTotal)),
                    ('Orders', report.orderCount.toString()),
                    ('Customers', report.customerCount.toString()),
                    ('Cash at hand', currencyFormat.format(report.cashTotal)),
                    ('Mobile Money', currencyFormat.format(report.momoTotal)),
                    (
                      'Profit',
                      currencyFormat.format(salesTotal - expenseTotal),
                    ),
                  ]),
                  _sectionTitle('Products Sold Today'),
                  if (report.sales.isEmpty)
                    const Text('No products sold today.')
                  else
                    ...report.sales.map(
                      (sale) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          sale['product']?.toString() ?? 'Unknown product',
                        ),
                        subtitle: Text(
                          'Quantity: ${sale['quantity'] ?? '-'} • ${_date(sale['date'])}',
                        ),
                        trailing: Text(
                          currencyFormat.format(sale['amount'] ?? 0),
                        ),
                      ),
                    ),
                  _sectionTitle('Expenses Today'),
                  if (report.expenses.isEmpty)
                    const Text('No expenses today.')
                  else
                    ...report.expenses.map(
                      (expense) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(expense['name']?.toString() ?? 'Expense'),
                        subtitle: Text(
                          'Details: ${expense['name'] ?? 'Expense'} • ${_date(expense['date'])}',
                        ),
                        trailing: Text(
                          currencyFormat.format(expense['amount'] ?? 0),
                        ),
                      ),
                    ),
                  _sectionTitle('Debts Today'),
                  if (report.debts.isEmpty)
                    const Text('No debts recorded today.')
                  else
                    ...report.debts.map(
                      (debt) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(debt['creditor']?.toString() ?? 'Debt'),
                        subtitle: Text(_date(debt['date'])),
                        trailing: Text(
                          currencyFormat.format(debt['amount'] ?? 0),
                        ),
                      ),
                    ),
                  _sectionTitle('Inventory'),
                  ...report.products.map(
                    (product) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(product['name']?.toString() ?? 'Product'),
                      trailing: Text('Stock: ${product['stock'] ?? 0}'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: FilledButton.icon(
                      onPressed: () => _downloadReport(report),
                      icon: const Icon(Icons.download),
                      label: const Text('Download PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );

  Widget _summaryGrid(List<(String, String)> values) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: values
        .map(
          (value) => SizedBox(
            width: 155,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value.$1),
                    const SizedBox(height: 4),
                    Text(
                      value.$2,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .toList(),
  );
}

class _DailyReport {
  final String companyName;
  final String workerName;
  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> debts;
  final List<Map<String, dynamic>> products;
  final int orderCount;
  final int customerCount;
  final double cashTotal;
  final double momoTotal;

  const _DailyReport({
    required this.companyName,
    required this.workerName,
    required this.sales,
    required this.expenses,
    required this.debts,
    required this.products,
    required this.orderCount,
    required this.customerCount,
    required this.cashTotal,
    required this.momoTotal,
  });
}
