import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'subscription_screen.dart';
import 'subscription_rules.dart';
import 'app_session.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final db = DatabaseHelper.instance;
  String? selectedProduct;
  double productPrice = 0.0;
  final qtyController = TextEditingController();
  String selectedPeriod = 'Day';
  late Future<List<Map<String, dynamic>>> salesFuture;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    if (!AppSession.isWorker && await db.isSubscriptionLocked()) {
      if (!mounted) return;
      await SubscriptionRules.redirectIfLocked(
        context: context,
        isLocked: db.isSubscriptionLocked,
        subscriptionScreen: const SubscriptionScreen(),
      );
      return;
    }
    salesFuture = db.getSales();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    qtyController.dispose();
    super.dispose();
  }

  DateTime _periodStart() {
    final now = DateTime.now();
    switch (selectedPeriod) {
      case 'Week':
        final today = DateTime(now.year, now.month, now.day);
        return today.subtract(Duration(days: today.weekday - 1));
      case 'Month':
        return DateTime(now.year, now.month);
      default:
        return DateTime(now.year, now.month, now.day);
    }
  }

  List<Map<String, dynamic>> _salesForSelectedPeriod(
    List<Map<String, dynamic>> sales,
  ) {
    final start = _periodStart();
    return sales.where((sale) {
      final date = DateTime.tryParse(sale['date']?.toString() ?? '');
      return date != null && !date.isBefore(start);
    }).toList();
  }

  Future<bool> _requirePin() async {
    final pinController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Enter PIN"),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: "PIN"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final isValid = await db.verifyPin(pinController.text);
              if (isValid) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Incorrect PIN")));
              }
            },
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _saveSale() async {
    if (selectedProduct == null || qtyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select product and enter quantity")),
      );
      return;
    }

    final qty = int.tryParse(qtyController.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Quantity must be greater than zero")),
      );
      return;
    }

    final canFulfill = await db.canFulfillOrder(selectedProduct!, qty);
    if (!canFulfill) {
      final stock = await db.getProductStock(selectedProduct!);
      final message = stock == null || stock <= 0
          ? "${selectedProduct!} is out of stock. Order cannot be placed."
          : "Only $stock ${selectedProduct!} left in stock. Reduce the quantity.";
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final total = productPrice * qty;

    final sale = {
      'product': selectedProduct,
      'quantity': qty,
      'amount': total,
      'date': DateTime.now().toIso8601String(),
    };

    await db.insertSaleIfNotExists(sale);

    // 🔹 Reduce stock after sale
    await db.reduceProductStock(selectedProduct!, qty);
    setState(() {
      salesFuture = db.getSales();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Sale recorded: ₵${total.toStringAsFixed(2)}")),
    );

    qtyController.clear();
    setState(() {
      selectedProduct = null;
      productPrice = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Record Sale")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: db.getProducts(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data!;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (products.isEmpty)
                  const Text("No products available. Add products first.")
                else ...[
                  DropdownButtonFormField<String>(
                    value: selectedProduct,
                    hint: const Text("Select Product"),
                    items: products.map((p) {
                      return DropdownMenuItem<String>(
                        value: p['name'],
                        child: Text(
                          "${p['name']} (₵${p['price']}) • Stock: ${p['stock']}",
                        ),
                        onTap: () {
                          productPrice = (p['price'] as num).toDouble();
                        },
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedProduct = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Quantity"),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _saveSale,
                    child: const Text("Save Sale"),
                  ),
                  const Divider(height: 32),
                ],
                Row(
                  children: [
                    const Text(
                      "Products sold",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    DropdownButton<String>(
                      value: selectedPeriod,
                      items: ['Day', 'Week', 'Month']
                          .map(
                            (period) => DropdownMenuItem(
                              value: period,
                              child: Text(period),
                            ),
                          )
                          .toList(),
                      onChanged: (period) {
                        if (period != null) {
                          setState(() => selectedPeriod = period);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: salesFuture,
                    builder: (context, salesSnapshot) {
                      if (!salesSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final sales = _salesForSelectedPeriod(
                        salesSnapshot.data!,
                      );
                      if (sales.isEmpty) {
                        return Center(
                          child: Text("No products sold this $selectedPeriod."),
                        );
                      }
                      final total = sales.fold<double>(
                        0,
                        (sum, sale) =>
                            sum + ((sale['amount'] as num?)?.toDouble() ?? 0),
                      );
                      return Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Total: ₵${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: ListView.builder(
                              itemCount: sales.length,
                              itemBuilder: (context, index) {
                                final sale = sales[index];
                                final date = DateTime.tryParse(
                                  sale['date']?.toString() ?? '',
                                );
                                final dateText = date == null
                                    ? sale['date'].toString()
                                    : '${date.day}/${date.month}/${date.year}';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    sale['product']?.toString() ??
                                        'Unknown product',
                                  ),
                                  subtitle: Text(
                                    'Quantity: ${sale['quantity'] ?? '-'} • $dateText',
                                  ),
                                  trailing: Text(
                                    '₵${((sale['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
