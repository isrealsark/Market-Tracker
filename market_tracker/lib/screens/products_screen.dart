import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'user_setup_screen.dart';
import 'package:intl/intl.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Map<String, dynamic>> products = [];
  final currencyFormat = NumberFormat.currency(symbol: '₵');
  final db = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final result = await db.getProducts();
    setState(() => products = result);
  }

  Future<bool> _addProduct(String name, double price) async {
    final database = await db.database;
    final users = await database.query('users');
    if (users.isEmpty) {
      // No user/PIN set up — prompt to register first.
      final goToRegister = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No account found'),
          content: const Text(
            'You must set up an account and PIN before adding products.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Register'),
            ),
          ],
        ),
      );
      if (goToRegister == true) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserSetupScreen()),
        );
      }
      return false;
    }

    if (await _requirePin()) {
      try {
        await db.insertProduct({'name': name, 'price': price, 'stock': 0});
        await _loadProducts();
        return true;
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add product: $e')));
        return false;
      }
    }

    return false;
  }

  Future<void> _removeProduct(int id) async {
    if (await _requirePin()) {
      final database = await db.database;
      await database.delete('products', where: 'id = ?', whereArgs: [id]);
      _loadProducts();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.shopping_bag, color: Colors.orange),
              title: Text(product['name']),
              subtitle: Text(
                'Price: ${currencyFormat.format(product['price'])}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _removeProduct(product['id'] as int),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          final nameController = TextEditingController();
          final priceController = TextEditingController();

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.shopping_bag, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Add Product'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      prefixIcon: Icon(Icons.shopping_cart),
                    ),
                  ),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefixIcon: Icon(Icons.money),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () async {
                    final name = nameController.text;
                    final price = double.tryParse(priceController.text) ?? 0;
                    final added = await _addProduct(name, price);
                    if (added) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Product added')),
                      );
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
