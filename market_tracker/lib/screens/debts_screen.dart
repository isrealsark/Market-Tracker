import 'package:flutter/material.dart';
import 'database_helper.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final db = DatabaseHelper.instance;
  final creditorController = TextEditingController();
  final amountController = TextEditingController();
  late Future<List<Map<String, dynamic>>> debtsFuture;
  String selectedPeriod = 'Day';

  @override
  void initState() {
    super.initState();
    debtsFuture = db.getDebts();
  }

  @override
  void dispose() {
    creditorController.dispose();
    amountController.dispose();
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

  List<Map<String, dynamic>> _debtsForSelectedPeriod(
    List<Map<String, dynamic>> debts,
  ) {
    final start = _periodStart();
    return debts.where((debt) {
      final date = DateTime.tryParse(debt['date']?.toString() ?? '');
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

  Future<void> _saveDebt() async {
    if (creditorController.text.isEmpty || amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter creditor name and amount")),
      );
      return;
    }

    final amount = double.tryParse(amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Amount must be greater than zero")),
      );
      return;
    }

    // 🔹 Require PIN before saving
    if (!(await _requirePin())) return;

    final debt = {
      'creditor': creditorController.text,
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
    };

    await db.insertDebtIfNotExists(debt);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Debt recorded: ₵${amount.toStringAsFixed(2)}")),
    );

    creditorController.clear();
    amountController.clear();
    setState(() {
      debtsFuture = db.getDebts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Record Debt")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Creditor name input
            TextField(
              controller: creditorController,
              decoration: const InputDecoration(labelText: "Creditor Name"),
            ),
            const SizedBox(height: 16),

            // Debt amount input
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount"),
            ),
            const SizedBox(height: 16),

            // Save button
            ElevatedButton(
              onPressed: _saveDebt,
              child: const Text("Save Debt"),
            ),
            const Divider(height: 32),
            Row(
              children: [
                const Text(
                  "Debts",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                future: debtsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final debts = _debtsForSelectedPeriod(snapshot.data!);
                  if (debts.isEmpty) {
                    return Center(
                      child: Text("No debts recorded this $selectedPeriod"),
                    );
                  }
                  final total = debts.fold<double>(
                    0,
                    (sum, debt) =>
                        sum + ((debt['amount'] as num?)?.toDouble() ?? 0),
                  );
                  return ListView.builder(
                    itemCount: debts.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Total: ₵${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      }
                      final debt = debts[index - 1];
                      final date = DateTime.tryParse(
                        debt['date']?.toString() ?? '',
                      );
                      final dateText = date == null
                          ? debt['date'].toString()
                          : '${date.day}/${date.month}/${date.year}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.money_off),
                        title: Text(debt['creditor']?.toString() ?? 'Unknown'),
                        subtitle: Text(dateText),
                        trailing: Text(
                          '₵${((debt['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
