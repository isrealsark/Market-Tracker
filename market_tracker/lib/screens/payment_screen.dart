import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'database_helper.dart';
import 'dart:convert';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final db = DatabaseHelper.instance;

  String? companyName;
  String customerType = "walk-in";
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final cashReceivedController = TextEditingController();
  String paymentMethod = "mobile_money";

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];
  final searchController = TextEditingController();

  List<Map<String, dynamic>> cart = [];

  double initialTotal = 0.0;
  double surcharge = 0.0;
  double finalTotal = 0.0;

  double get cashReceived =>
      double.tryParse(cashReceivedController.text.trim()) ?? 0.0;

  double get changeDue =>
      (cashReceived - finalTotal).clamp(0.0, double.infinity);

  @override
  void initState() {
    super.initState();
    _loadCompany();
    _loadProducts();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    cashReceivedController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCompany() async {
    final user = await db.getCurrentUser();
    if (user != null) {
      setState(() {
        companyName = user['company'] as String?;
      });
    }
  }

  Future<void> _loadProducts() async {
    final list = await db.getProducts();
    setState(() {
      products = list;
      filteredProducts = list;
    });
  }

  void _filterProducts(String query) {
    setState(() {
      filteredProducts = products
          .where(
            (p) => p['name'].toString().toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
    });
  }

  void _addToCart(Map<String, dynamic> product, int qty) async {
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than zero')),
      );
      return;
    }

    final canFulfill = await db.canFulfillOrder(product['name'], qty);
    if (!canFulfill) {
      final stock = await db.getProductStock(product['name']);
      final message = stock == null || stock <= 0
          ? '${product['name']} is out of stock. Order cannot be placed.'
          : 'Only $stock ${product['name']} left in stock. Reduce the quantity.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final subtotal = (product['price'] as num) * qty;
    setState(() {
      cart.add({
        'product': product['name'],
        'price': product['price'],
        'quantity': qty,
        'subtotal': subtotal,
      });
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    initialTotal = cart.fold(0.0, (sum, item) => sum + item['subtotal']);
    surcharge =
        (paymentMethod == "mobile_money" || paymentMethod == "bank_card")
        ? initialTotal * 0.01
        : 0.0;
    finalTotal = initialTotal + surcharge;
  }

  Future<void> _confirmPayment() async {
    final now = DateTime.now().toIso8601String();

    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product to the cart')),
      );
      return;
    }

    if (paymentMethod == 'cash' && cashReceived < finalTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash received is less than the total')),
      );
      return;
    }

    // Step 1: Validate stock before accepting the order
    for (final item in cart) {
      final productName = item['product'] as String;
      final qty = (item['quantity'] as int?) ?? 0;
      final canFulfill = await db.canFulfillOrder(productName, qty);
      if (!canFulfill) {
        final stock = await db.getProductStock(productName);
        final message = stock == null || stock <= 0
            ? '$productName is out of stock. Order cannot be placed.'
            : 'Only $stock $productName left in stock. Reduce the quantity.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
    }

    // Step 2: Insert or fetch customer
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer name and phone')),
      );
      return;
    }

    final receiptDetails = {
      'company': companyName,
      'customerType': customerType,
      'customerName': name,
      'customerPhone': phone,
      'products': cart.map((item) => Map<String, dynamic>.from(item)).toList(),
      'paymentMethod': paymentMethod,
      'initialTotal': initialTotal,
      'surcharge': surcharge,
      'finalTotal': finalTotal,
      if (paymentMethod == 'cash') ...{
        'cashReceived': cashReceived,
        'changeDue': changeDue,
      },
      'date': now,
    };

    final confirmed = await _showOrderReceipt(receiptDetails, preview: true);
    if (confirmed != true || !mounted) return;

    final customerId = await db.insertCustomer({
      'name': name,
      'phone': phone,
      'cardNumber': '',
      'type': customerType,
    });

    // Step 3: Save sales and reduce stock
    for (var item in cart) {
      await db.insertSale({
        'customerId': customerId,
        'product': item['product'],
        'quantity': item['quantity'],
        'amount': item['subtotal'],
        'date': now,
      });
      await db.reduceProductStock(item['product'], item['quantity']);
    }

    // Step 3: Save payment
    await db.insertPayment({
      'customerId': customerId,
      'saleId': null,
      'method': paymentMethod,
      'initialTotal': initialTotal,
      'surcharge': surcharge,
      'finalTotal': finalTotal,
      'date': now,
    });

    // Step 4: Save receipt (optional)
    await db.insertReceipt({
      'customerId': customerId,
      'details': jsonEncode(receiptDetails),
      'date': now,
    });

    await _showOrderReceipt(receiptDetails);
  }

  Future<bool?> _showOrderReceipt(
    Map<String, dynamic> receipt, {
    bool preview = false,
  }) async {
    final items = (receipt['products'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final date = DateTime.parse(receipt['date'] as String);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Image.asset(
                                'assets/images/watermark2.png',
                                width: 44,
                                height: 44,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      (receipt['company'] as String?)
                                                  ?.isNotEmpty ==
                                              true
                                          ? receipt['company'] as String
                                          : 'Market Tracker',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'SALES RECEIPT',
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _receiptDetailRow('Date', _formatReceiptDate(date)),
                          _receiptDetailRow(
                            'Customer',
                            receipt['customerName']?.toString() ?? '',
                          ),
                          _receiptDetailRow(
                            'Phone',
                            receipt['customerPhone']?.toString() ?? '',
                          ),
                          _receiptDetailRow(
                            'Order type',
                            receipt['customerType']?.toString() ?? '',
                          ),
                          _receiptDetailRow(
                            'Payment method',
                            _paymentMethodLabel(
                              receipt['paymentMethod']?.toString() ?? '',
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(),
                          ),
                          Row(
                            children: [
                              const Expanded(
                                flex: 4,
                                child: Text(
                                  'ITEM',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const Expanded(
                                flex: 1,
                                child: Text(
                                  'QTY',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'TOTAL',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...items.map((item) {
                            final quantity = (item['quantity'] as num).toInt();
                            final price = (item['price'] as num).toDouble();
                            final subtotal = (item['subtotal'] as num)
                                .toDouble();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['product']?.toString() ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '$quantity x ${_formatMoney(price)}',
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      '$quantity',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _formatMoney(subtotal),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(),
                          ),
                          _receiptDetailRow(
                            'Subtotal',
                            _formatMoney(
                              (receipt['initialTotal'] as num).toDouble(),
                            ),
                          ),
                          _receiptDetailRow(
                            'Surcharge',
                            _formatMoney(
                              (receipt['surcharge'] as num).toDouble(),
                            ),
                          ),
                          if (receipt['paymentMethod'] == 'cash') ...[
                            _receiptDetailRow(
                              'Cash received',
                              _formatMoney(
                                (receipt['cashReceived'] as num).toDouble(),
                              ),
                            ),
                            _receiptDetailRow(
                              'Change',
                              _formatMoney(
                                (receipt['changeDue'] as num).toDouble(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _receiptDetailRow(
                            'TOTAL',
                            _formatMoney(
                              (receipt['finalTotal'] as num).toDouble(),
                            ),
                            emphasized: true,
                          ),
                          const SizedBox(height: 20),
                          const Center(
                            child: Text(
                              'Thank you for your purchase',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (preview) ...[
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Edit order'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        icon: const Icon(Icons.check),
                        label: const Text('Confirm Payment'),
                      ),
                    ] else ...[
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop(true);
                          Navigator.of(context).pop();
                        },
                        child: const Text('Done'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _printReceipt(receipt),
                        icon: const Icon(Icons.print),
                        label: const Text('Print receipt'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printReceipt(Map<String, dynamic> receipt) async {
    final items = (receipt['products'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final date = DateTime.parse(receipt['date'] as String);
    final logo = pw.MemoryImage(
      (await rootBundle.load(
        'assets/images/watermark2.png',
      )).buffer.asUint8List(),
    );
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Image(logo, width: 35, height: 35),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        (receipt['company'] as String?)?.isNotEmpty == true
                            ? receipt['company'] as String
                            : 'Market Tracker',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'RECEIPT',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text('Date: ${_formatReceiptDate(date)}'),
            pw.Text('Customer: ${receipt['customerName'] ?? ''}'),
            pw.Text('Phone: ${receipt['customerPhone'] ?? ''}'),
            pw.Text('Order type: ${receipt['customerType'] ?? ''}'),
            pw.Text(
              'Payment method: ${_paymentMethodLabel(receipt['paymentMethod']?.toString() ?? '')}',
            ),
            pw.SizedBox(height: 14),
            pw.TableHelper.fromTextArray(
              headers: ['Item', 'Qty', 'Unit price', 'Total'],
              data: items
                  .map(
                    (item) => [
                      item['product']?.toString() ?? '',
                      item['quantity']?.toString() ?? '0',
                      _formatMoney((item['price'] as num).toDouble()),
                      _formatMoney((item['subtotal'] as num).toDouble()),
                    ],
                  )
                  .toList(),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.deepOrange,
              ),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 14),
            _pdfReceiptRow(
              'Subtotal',
              _formatMoney((receipt['initialTotal'] as num).toDouble()),
            ),
            _pdfReceiptRow(
              'Surcharge',
              _formatMoney((receipt['surcharge'] as num).toDouble()),
            ),
            if (receipt['paymentMethod'] == 'cash')
              _pdfReceiptRow(
                'Cash received',
                _formatMoney((receipt['cashReceived'] as num).toDouble()),
              ),
            if (receipt['paymentMethod'] == 'cash')
              _pdfReceiptRow(
                'Change',
                _formatMoney((receipt['changeDue'] as num).toDouble()),
              ),
            pw.Divider(color: PdfColors.deepOrange),
            _pdfReceiptRow(
              'TOTAL',
              _formatMoney((receipt['finalTotal'] as num).toDouble()),
              emphasized: true,
            ),
            pw.Spacer(),
            pw.Center(child: pw.Text('Thank you for your purchase')),
          ],
        ),
      ),
    );

    try {
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the print dialog.')),
      );
    }
  }

  Widget _receiptDetailRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: emphasized ? Colors.black : Colors.black54,
              fontWeight: emphasized ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.bold : FontWeight.w500,
                fontSize: emphasized ? 17 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfReceiptRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: emphasized
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              fontSize: emphasized ? 15 : 11,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: emphasized
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              fontSize: emphasized ? 15 : 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMoney(double amount) => 'GHS ${amount.toStringAsFixed(2)}';

  String _paymentMethodLabel(String method) => switch (method) {
    'cash' => 'Cash',
    'bank_card' => 'Bank Card',
    'mobile_money' => 'Mobile Money',
    _ => method,
  };

  String _formatReceiptDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(companyName ?? "Payment")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: "Phone number"),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: customerType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: "walk-in", child: Text("Walk in")),
                DropdownMenuItem(value: "delivery", child: Text("Delivery")),
              ],
              onChanged: (val) {
                setState(() => customerType = val!);
              },
            ),
            const SizedBox(height: 16),

            // Payment method
            DropdownButton<String>(
              value: paymentMethod,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: "mobile_money",
                  child: Text("Mobile Money"),
                ),
                DropdownMenuItem(value: "bank_card", child: Text("Bank Card")),
                DropdownMenuItem(value: "cash", child: Text("Cash")),
              ],
              onChanged: (val) {
                setState(() {
                  paymentMethod = val!;
                  _calculateTotals();
                });
              },
            ),
            if (paymentMethod == 'cash') ...[
              const SizedBox(height: 12),
              TextField(
                controller: cashReceivedController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cash received',
                  prefixText: 'GHS ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (cashReceivedController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    cashReceived >= finalTotal
                        ? 'Change: ${_formatMoney(changeDue)}'
                        : 'Remaining: ${_formatMoney(finalTotal - cashReceived)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cashReceived >= finalTotal
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),

            // Search bar
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: "Search Products",
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterProducts,
            ),
            const SizedBox(height: 12),

            // Product dropdown with quantity dialog
            DropdownButton<Map<String, dynamic>>(
              hint: const Text("Select Product"),
              isExpanded: true,
              items: filteredProducts.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text("${p['name']} - GHS ${p['price']}"),
                );
              }).toList(),
              onChanged: (product) {
                if (product != null) {
                  showDialog(
                    context: context,
                    builder: (_) {
                      final qtyController = TextEditingController();
                      return AlertDialog(
                        title: Text("Add ${product['name']}"),
                        content: TextField(
                          controller: qtyController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Quantity",
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel"),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              final qty = int.tryParse(qtyController.text) ?? 1;
                              _addToCart(product, qty);
                              Navigator.pop(context);
                            },
                            child: const Text("Add"),
                          ),
                        ],
                      );
                    },
                  );
                }
              },
            ),

            const SizedBox(height: 16),

            // Cart list
            Expanded(
              child: ListView.builder(
                itemCount: cart.length,
                itemBuilder: (_, i) {
                  final item = cart[i];
                  return ListTile(
                    title: Text("${item['product']} x${item['quantity']}"),
                    subtitle: Text("Subtotal: GHS ${item['subtotal']}"),
                  );
                },
              ),
            ),

            // Totals
            Text("Initial Total: GHS $initialTotal"),
            Text("Surcharge: GHS $surcharge"),
            Text(
              "Final Total: GHS $finalTotal",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _confirmPayment,
              child: const Text("Confirm Payment"),
            ),
          ],
        ),
      ),
    );
  }
}
