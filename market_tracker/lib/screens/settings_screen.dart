import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'login_screen.dart';
import 'account_management_screen.dart';
import 'subscription_screen.dart';
import 'subscription_rules.dart';
import 'app_session.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final db = DatabaseHelper.instance;

  final oldPinController = TextEditingController();
  final newPinController = TextEditingController();
  final confirmPinController = TextEditingController();

  final usernameController = TextEditingController();
  final companyController = TextEditingController();

  String? error;

  Future<void> _updateAccount() async {
    // Verify current PIN
    final isPinValid = await db.verifyPin(oldPinController.text.trim());
    if (!isPinValid) {
      setState(() => error = "Invalid current PIN");
      return;
    }

    // Validate new PIN
    if (newPinController.text.isNotEmpty) {
      if (newPinController.text.length != 4 ||
          newPinController.text != confirmPinController.text) {
        setState(() => error = "New PIN must be 4 digits and match");
        return;
      }
      await db.updatePin(newPinController.text.trim());
    }

    // Update username & company
    if (usernameController.text.isNotEmpty &&
        companyController.text.isNotEmpty) {
      await db.updateUserInfo(
        usernameController.text.trim(),
        companyController.text.trim(),
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Account updated successfully")),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _openAccountManagement() async {
    final pinController = TextEditingController();
    final verified = await showDialog<bool>(
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
              final valid = await db.verifyPin(pinController.text.trim());
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, valid);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    pinController.dispose();

    if (!mounted) return;
    if (verified == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AccountManagementScreen()),
      );
    } else if (verified == false) {
      setState(() => error = 'Invalid PIN');
    }
  }

  Future<void> _ensureAccess() async {
    if (AppSession.isWorker) return;
    final locked = await db.isSubscriptionLocked();
    if (!mounted) return;
    if (locked) {
      await SubscriptionRules.redirectIfLocked(
        context: context,
        isLocked: db.isSubscriptionLocked,
        subscriptionScreen: const SubscriptionScreen(),
      );
    }
  }

  Future<void> _addWorker() async {
    await _ensureAccess();
    if (!mounted) return;
    final workerController = TextEditingController();
    final pinController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Worker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: workerController,
              decoration: const InputDecoration(labelText: 'Worker name'),
            ),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = workerController.text.trim();
              final validPin = await db.verifyPin(pinController.text.trim());
              if (!dialogContext.mounted) return;
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a worker name')),
                );
                return;
              }
              if (!validPin) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
                return;
              }
              final saved = await db.addWorker(name);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, saved);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    workerController.dispose();
    pinController.dispose();

    if (!mounted || added == null) return;
    setState(() => error = added ? null : 'Worker name already exists');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Worker added successfully' : 'Worker name already exists',
        ),
      ),
    );
  }

  @override
  void dispose() {
    oldPinController.dispose();
    newPinController.dispose();
    confirmPinController.dispose();
    usernameController.dispose();
    companyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: companyController,
              decoration: const InputDecoration(labelText: "Company Name"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: oldPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: "Current PIN"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: "New PIN"),
            ),
            TextField(
              controller: confirmPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: "Confirm New PIN"),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _updateAccount,
              child: const Text("Update Account"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addWorker,
              icon: const Icon(Icons.person_add),
              label: const Text("Add Worker"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openAccountManagement,
              icon: const Icon(Icons.person_off),
              label: const Text("Deactivate Account"),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
