import 'dart:async';
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
import 'company_sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _backgroundImages = [
    'assets/images/H1.jpg',
    'assets/images/Homepage.jpg',
    'assets/images/Homepage1.jpg',
    'assets/images/H2.png',
    'assets/images/H3.png',
    'assets/images/H4.png',
    'assets/images/A5.png',
    'assets/images/A6.png',
    'assets/images/A7.png',
  ];
  final db = DatabaseHelper.instance;
  String companyName = '';
  int _backgroundIndex = 0;
  late final Timer _backgroundTimer;

  @override
  void initState() {
    super.initState();
    _loadCompanyName();
    _backgroundTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {
        _backgroundIndex = (_backgroundIndex + 1) % _backgroundImages.length;
      });
    });
  }

  @override
  void dispose() {
    _backgroundTimer.cancel();
    super.dispose();
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

    return Center(
      child: SizedBox(
        width: 260,
        height: 150,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(10),
          ),
          onPressed: () async {
            final isBlocked =
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
              Icon(icon, size: 32, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
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
            onPressed: () async {
              await CompanySyncService.signOut();
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
      extendBodyBehindAppBar: true,
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              child: Image.asset(
                _backgroundImages[_backgroundIndex],
                key: ValueKey<String>(_backgroundImages[_backgroundIndex]),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.fill,
                color: Colors.black.withValues(alpha: 0.25),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          GridView.count(
            padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 16, 16, 16),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
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
        ],
      ),
    );
  }
}
