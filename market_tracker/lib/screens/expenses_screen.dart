import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'package:intl/intl.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> expenses = [];
  List<Map<String, dynamic>> filteredExpenses = [];
  final currencyFormat = NumberFormat.currency(symbol: '₵');
  String sortOption = 'date';
  final db = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    final result = await db.getExpenses();
    setState(() {
      expenses = result;
      filteredExpenses = expenses;
      _applySort();
    });
  }

  void _applySort() {
    if (sortOption == 'date') {
      filteredExpenses.sort(
        (a, b) => (b['date'] as String).compareTo(a['date'] as String),
      );
    } else if (sortOption == 'amount') {
      filteredExpenses.sort(
        (a, b) => (b['amount'] as num).compareTo(a['amount'] as num),
      );
    }
  }

  void _filterExpenses(String query) {
    setState(() {
      filteredExpenses = expenses.where((expense) {
        final name = (expense['name'] ?? '').toString().toLowerCase();
        return name.contains(query.toLowerCase());
      }).toList();
      _applySort();
    });
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

  Future<bool> _addExpense(String name, double amount, DateTime date) async {
    if (!await _requirePin()) return false;

    try {
      await db.insertExpense({
        'name': name,
        'amount': amount,
        'date': date.toIso8601String(),
      });
      await _loadExpenses();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add expense: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _removeExpense(int id) async {
    if (await _requirePin()) {
      await db.deleteExpense(id);
      _loadExpenses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                sortOption = value;
                _applySort();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'date', child: Text('Sort by Date')),
              const PopupMenuItem(
                value: 'amount',
                child: Text('Sort by Amount'),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: _filterExpenses,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: filteredExpenses.length,
        itemBuilder: (context, index) {
          final expense = filteredExpenses[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.money_off, color: Colors.red),
              title: Text(
                '${expense['name']} - ${currencyFormat.format(expense['amount'])}',
              ),
              subtitle: Text(expense['date'].toString().split('T')[0]),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _removeExpense(expense['id'] as int),
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
          final amountController = TextEditingController();
          DateTime selectedDate = DateTime.now();

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.money_off, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Add Expense'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Expense Name',
                      prefixIcon: Icon(Icons.receipt),
                    ),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.money),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Select Date'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        selectedDate = picked;
                      }
                    },
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
                    final name = nameController.text.trim();
                    final amount = double.tryParse(amountController.text);
                    if (name.isEmpty || amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter an expense name and a valid amount',
                          ),
                        ),
                      );
                      return;
                    }

                    final saved = await _addExpense(name, amount, selectedDate);
                    if (saved && context.mounted) {
                      Navigator.pop(context);
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
