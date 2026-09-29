import 'dart:async';
import 'package:flutter/material.dart';
import 'database_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final db = DatabaseHelper.instance;
  Timer? _resetWatcher;

  late Future<double> totalSales;
  late Future<double> totalExpenses;
  late Future<double> totalDebts;
  late Future<double> totalProfit;

  @override
  void initState() {
    super.initState();
    _loadTotals();
    _startResetWatcher();
  }

  @override
  void dispose() {
    _resetWatcher?.cancel();
    super.dispose();
  }

  void _startResetWatcher() {
    _resetWatcher?.cancel();
    _resetWatcher = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(_loadTotals);
    });
  }

  void _loadTotals() {
    totalSales = db.totalSales();
    totalExpenses = db.totalExpenses();
    totalDebts = db.totalDebts();
    totalProfit = db.totalProfit();
  }

  Widget _buildCard(String title, Future<double> future, Color color) {
    return FutureBuilder<double>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return Card(
          color: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "₵${snapshot.data!.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard")),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [
          _buildCard("Total Sales", totalSales, Colors.green),
          _buildCard("Total Expenses", totalExpenses, Colors.red),
          _buildCard("Total Debts", totalDebts, Colors.blue),
          _buildCard("Profit", totalProfit, Colors.orange),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _loadTotals(); // refresh totals
          });
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
