import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'products_screen.dart';
import 'payment_screen.dart';
import 'sales_screen.dart';
import 'expenses_screen.dart';
import 'debts_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import 'customer_list_screen.dart';
import 'reports_screen.dart';
import 'inventory_screen.dart';
import 'app_session.dart';
import 'database_helper.dart';
import 'subscription_screen.dart';
import 'subscription_rules.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final db = DatabaseHelper.instance;
  String companyName = '';

  @override
  void initState() {
    super.initState();
    _loadCompanyName();
  }

  Future<void> _loadCompanyName() async {
    final user = await db.getCurrentUser();
    if (!mounted || user == null) return;
    setState(() {
      companyName = (user['company'] ?? '').toString();
    });
  }

  Widget _buildSquareButton(IconData icon, String label, BuildContext context) {
    final restrictedScreens = {"Sales", "Customers", "Reports", "Settings"};

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(16),
      ),
      onPressed: () async {
        final isBlocked =
            !AppSession.isWorker &&
            restrictedScreens.contains(label) &&
            await db.isSubscriptionLocked();

        if (isBlocked) {
          if (!context.mounted) return;
          await SubscriptionRules.redirectIfLocked(
            context: context,
            isLocked: db.isSubscriptionLocked,
            subscriptionScreen: const SubscriptionScreen(),
          );
          return;
        }

        if (label == "Dashboard") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          );
        } else if (label == "Order") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PaymentScreen()),
          );
        } else if (label == "Products") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductsScreen()),
          );
        } else if (label == "Inventory") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const InventoryScreen()),
          );
        } else if (label == "Sales") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SalesScreen()),
          );
        } else if (label == "Expenses") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExpensesScreen()),
          );
        } else if (label == "Debts") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DebtsScreen()),
          );
        } else if (label == "Settings") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        } else if (label == "Customers") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CustomersScreen()),
          );
        } else if (label == "Reports") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReportsScreen()),
          );
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // cancel
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              AppSession.clear();
              Navigator.pop(context); // close dialog
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          companyName.isEmpty ? 'Market Tracker' : companyName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == "Logout") {
                _confirmLogout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: "Logout", child: Text("Logout")),
            ],
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [
          _buildSquareButton(Icons.add_shopping_cart, "Order", context),
          _buildSquareButton(Icons.dashboard, "Dashboard", context),
          _buildSquareButton(Icons.shopping_cart, "Products", context),
          _buildSquareButton(Icons.inventory_2, "Inventory", context),
          _buildSquareButton(Icons.point_of_sale, "Sales", context),
          _buildSquareButton(Icons.people, "Customers", context),
          _buildSquareButton(Icons.receipt_long, "Expenses", context),
          _buildSquareButton(Icons.people, "Debts", context),
          _buildSquareButton(Icons.assessment, "Reports", context),
          _buildSquareButton(Icons.settings, "Settings", context),
        ],
      ),
    );
  }
}
