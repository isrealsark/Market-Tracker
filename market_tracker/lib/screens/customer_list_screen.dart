import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'customer_profile_screen.dart';
import 'subscription_screen.dart';
import 'subscription_rules.dart';
import 'app_session.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> customers = [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    if (!AppSession.isWorker && await db.isSubscriptionLocked()) {
      if (!mounted) return;
      await SubscriptionRules.redirectIfLocked(
        context: context,
        isLocked: db.isSubscriptionLocked,
        subscriptionScreen: const SubscriptionScreen(),
      );
      return;
    }
    await db.deleteOldCustomers(); // cleanup before loading
    final list = await db.getCustomers();
    setState(() => customers = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Customers")),
      body: customers.isEmpty
          ? const Center(child: Text("No customers yet"))
          : ListView.builder(
              itemCount: customers.length,
              itemBuilder: (_, i) {
                final c = customers[i];
                return ListTile(
                  title: Text(c['name'] ?? "Unknown"),
                  subtitle: Text("Type: ${c['type']}"),
                  trailing: Text(c['createdAt'] ?? ""),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CustomerProfileScreen(customerId: c['id']),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
