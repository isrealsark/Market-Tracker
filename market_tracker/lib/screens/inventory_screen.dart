import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'reports_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final db = DatabaseHelper.instance;
  late Future<List<Map<String, dynamic>>> productsFuture;

  @override
  void initState() {
    super.initState();
    productsFuture = db.getProducts();
  }

  Future<bool> _requirePin() async {
    final pinController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final valid = await db.verifyPin(pinController.text);
              if (!dialogContext.mounted) return;
              if (valid) {
                Navigator.pop(dialogContext, true);
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    pinController.dispose();
    return result ?? false;
  }

  Future<void> _changeStock(Map<String, dynamic> product, int direction) async {
    final quantityController = TextEditingController(text: '1');
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(direction > 0 ? 'Add stock' : 'Reduce stock'),
        content: TextField(
          controller: quantityController,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(quantityController.text);
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a quantity greater than zero'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    quantityController.dispose();
    if (quantity == null || !mounted || !(await _requirePin())) return;

    final changed = await db.adjustProductStock(
      product['id'] as int,
      direction * quantity,
    );
    if (!mounted) return;
    setState(() {
      productsFuture = db.getProducts();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed ? 'Inventory updated' : 'Product could not be updated',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'View reports',
            icon: const Icon(Icons.assessment),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: productsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data!;
          if (products.isEmpty) {
            return const Center(child: Text('No products available'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              final nextProducts = db.getProducts();
              setState(() => productsFuture = nextProducts);
              await nextProducts;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: products.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final product = products[index];
                final stock = (product['stock'] as num?)?.toInt() ?? 0;
                return Card(
                  child: ListTile(
                    title: Text(product['name']?.toString() ?? 'Product'),
                    subtitle: Text('Current stock: $stock'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Reduce stock',
                          onPressed: () => _changeStock(product, -1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Add stock',
                          onPressed: () => _changeStock(product, 1),
                          icon: const Icon(Icons.add_circle_outline),
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
