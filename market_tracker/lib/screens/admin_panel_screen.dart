import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'company_detail_screen.dart';
import 'login_screen.dart'; // 🔹 Import your login screen

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> filteredCustomers = [];
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCompanies();
    searchController.addListener(_filterCompanies);
  }

  Future<void> _loadCompanies() async {
    final c = await db.getUsers();
    setState(() {
      customers = c;
      filteredCustomers = c;
    });
  }

  Future<void> _debugShowUsers() async {
    final database = await db.database;
    try {
      final dbList = await database.rawQuery('PRAGMA database_list;');
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table';",
      );
      final rows = await database.rawQuery(
        'SELECT id, username, company, pinHash FROM users',
      );

      final info = {
        'database_list': dbList,
        'tables': tables,
        'users_rows': rows,
      };

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('DB inspection'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: Text(info.toString())),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('DB error: $e')));
    }
  }

  void _filterCompanies() {
    final query = searchController.text.toLowerCase();
    setState(() {
      filteredCustomers = customers.where((c) {
        final company = (c['company'] ?? "").toLowerCase();
        return company.contains(query);
      }).toList();
    });
  }

  void _logout() {
    // 🔹 Optional: clear any session data here
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome, Admin"),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'Logout') _logout();
              if (value == 'Inspect Users') _debugShowUsers();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'Inspect Users',
                child: Text('Inspect Users'),
              ),
              const PopupMenuItem(value: 'Logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔍 Search Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search company...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredCustomers.length,
              itemBuilder: (context, index) {
                final company =
                    filteredCustomers[index]['company'] ?? "Unknown Company";
                return ListTile(
                  title: Text(company),
                  onTap: () {
                    // 👉 Navigate to Company Detail Screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompanyDetailScreen(
                          companyId: filteredCustomers[index]['id'],
                          companyName: company,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
